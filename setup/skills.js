#!/usr/bin/env node
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const node_child_process_1 = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const shared_links_1 = require("./shared-links");
const skill_names_1 = require("./skill-names");
const private_base_1 = require("./private-base");
const SUPPORTED_AGENTS = new Set(["codex", "claude-code"]);
function fail(message) {
    throw new Error(message);
}
function info(message) {
    console.log(message);
}
function warn(message) {
    console.warn(message);
}
function envFlag(name) {
    const value = process.env[name] || "0";
    if (value !== "0" && value !== "1") {
        fail(`${name} must be 0 or 1: ${value}`);
    }
    return value === "1";
}
function csv(value) {
    if (!value) {
        return [];
    }
    return value
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
}
function parseAgent(value) {
    const trimmed = value.trim();
    if (trimmed === "codex" || trimmed === "claude-code") {
        return trimmed;
    }
    fail(`unsupported skills agent: ${trimmed}`);
}
function parseAgents(values) {
    const agents = [];
    for (const value of values) {
        for (const item of csv(value)) {
            const agent = parseAgent(item);
            if (!agents.includes(agent)) {
                agents.push(agent);
            }
        }
    }
    return agents;
}
function parseArgs(argv) {
    if (argv[0] === "profile") {
        if (argv.length < 2) {
            fail("skills profile requires a subcommand");
        }
        if (argv[1] !== "validate") {
            fail(`Unknown skills profile subcommand: ${argv[1]}`);
        }
        let profiles = "";
        let index = 2;
        while (index < argv.length) {
            const item = argv[index];
            if (item === "--profile") {
                if (index + 1 >= argv.length) {
                    fail("--profile requires a csv value");
                }
                profiles = argv[index + 1] ?? "";
                index += 2;
                continue;
            }
            fail(`Unknown skills profile argument: ${item}`);
        }
        return {
            action: "profile-validate",
            scope: "user",
            profiles,
            agents: ["codex"],
            copy: false,
        };
    }
    let scope = "user";
    let profiles = "";
    let copy = false;
    const agentArgs = [];
    let index = 0;
    while (index < argv.length) {
        const item = argv[index];
        if (item === "--scope") {
            if (index + 1 >= argv.length) {
                fail("--scope requires one of: user, project");
            }
            const rawScope = argv[index + 1];
            if (rawScope !== "user" && rawScope !== "project") {
                fail(`Unknown skills scope: ${rawScope}`);
            }
            scope = rawScope;
            index += 2;
            continue;
        }
        if (item === "--profile") {
            if (index + 1 >= argv.length) {
                fail("--profile requires a csv value");
            }
            profiles = argv[index + 1] ?? "";
            index += 2;
            continue;
        }
        if (item === "--agent") {
            if (index + 1 >= argv.length) {
                fail("--agent requires a value");
            }
            agentArgs.push(argv[index + 1] ?? "");
            index += 2;
            continue;
        }
        if (item === "--copy") {
            copy = true;
            index += 1;
            continue;
        }
        fail(`Unknown skills argument: ${item}`);
    }
    // User scope copies are made by the Windows PowerShell wrapper, which owns
    // the user link batch; the runtime copies only project skills.
    if (copy && scope !== "project") {
        fail("--copy is supported only for project scope");
    }
    const agents = agentArgs.length > 0 ? parseAgents(agentArgs) : ["codex", "claude-code"];
    return {
        action: "install",
        scope,
        profiles,
        agents,
        copy,
    };
}
const WINDOWS_EXECUTABLE_EXTENSIONS = [".com", ".exe", ".bat", ".cmd"];
function windowsExecutableExtensions(env) {
    const pathext = (env.PATHEXT ?? "")
        .split(";")
        .map((extension) => extension.trim().toLowerCase())
        .filter((extension) => WINDOWS_EXECUTABLE_EXTENSIONS.includes(extension));
    return pathext.length > 0 ? [...new Set(pathext)] : WINDOWS_EXECUTABLE_EXTENSIONS;
}
function isFile(candidate) {
    try {
        return fs.statSync(candidate).isFile();
    }
    catch {
        return false;
    }
}
// Walk PATH and PATHEXT directly instead of running `where`, which searches the
// current directory before PATH. The current directory is used only when PATH
// lists it explicitly.
function resolveWindowsCommand(command, env = process.env) {
    const extensions = windowsExecutableExtensions(env);
    const commandExtension = path.extname(command).toLowerCase();
    const names = extensions.includes(commandExtension)
        ? [command]
        : extensions.map((extension) => `${command}${extension}`);
    const pathEntries = (env.PATH ?? env.Path ?? "")
        .split(path.delimiter)
        .map((entry) => entry.trim().replace(/^"(.*)"$/, "$1"))
        .filter(Boolean);
    for (const entry of pathEntries) {
        for (const name of names) {
            const candidate = path.resolve(entry, name);
            if (isFile(candidate)) {
                return candidate;
            }
        }
    }
    fail(`Required command not found: ${command}`);
}
function resolveCommand(command, env = process.env) {
    if (process.platform === "win32") {
        return resolveWindowsCommand(command, env);
    }
    const result = (0, node_child_process_1.spawnSync)("sh", ["-c", `command -v ${shellQuote(command)}`], {
        env,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
    });
    if (result.status !== 0) {
        fail(`Required command not found: ${command}`);
    }
    const resolved = result.stdout.split(/\r?\n/).map((line) => line.trim()).find(Boolean);
    if (!resolved) {
        fail(`Required command not found: ${command}`);
    }
    return resolved;
}
function shellQuote(value) {
    return `'${value.replace(/'/g, "'\\''")}'`;
}
function readJson(filePath) {
    let raw;
    try {
        raw = fs.readFileSync(filePath, "utf8");
    }
    catch (error) {
        fail(`failed to read ${filePath}: ${error.message}`);
    }
    try {
        return JSON.parse(raw);
    }
    catch (error) {
        fail(`failed to parse ${filePath}: ${error.message}`);
    }
}
function ensureArray(value, filePath, key) {
    if (value === undefined) {
        return [];
    }
    if (!Array.isArray(value)) {
        fail(`${filePath}: ${key} must be an array`);
    }
    return value;
}
function getObjectProperty(value, key) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        return undefined;
    }
    return value[key];
}
function requireUnreservedSkillName(name) {
    if ((0, skill_names_1.isReservedSkillName)(name)) {
        fail(`Invalid or reserved skill name: ${name}`);
    }
}
function profilePath(profileDir, name) {
    return path.join(profileDir, `${name}.json`);
}
function listProfiles(profileDir) {
    if (!fs.existsSync(profileDir)) {
        fail(`skills profiles directory not found: ${profileDir}`);
    }
    return fs
        .readdirSync(profileDir)
        .filter((entry) => entry.endsWith(".json"))
        .map((entry) => path.basename(entry, ".json"))
        .sort();
}
function resolveProfiles(dotfilesRoot, requestedProfiles, agents, scope) {
    const profileDir = path.join(dotfilesRoot, "skills", "profiles");
    const localDir = path.join(dotfilesRoot, "skills", "local");
    const expanded = [];
    const loaded = new Set();
    const externalBySource = new Map();
    const localSkills = new Set();
    function load(name, stack) {
        if (loaded.has(name)) {
            return;
        }
        if (stack.includes(name)) {
            fail(`cyclic profile include: ${stack.concat(name).join(" -> ")}`);
        }
        const filePath = profilePath(profileDir, name);
        if (!fs.existsSync(filePath)) {
            fail(`unknown profile ${name}`);
        }
        const profile = readJson(filePath);
        const includes = ensureArray(getObjectProperty(profile, "includes"), filePath, "includes");
        for (const includeName of includes) {
            if (typeof includeName !== "string" || includeName.trim() === "") {
                fail(`${filePath}: includes must contain profile names`);
            }
            load(includeName, stack.concat(name));
        }
        const external = ensureArray(getObjectProperty(profile, "external"), filePath, "external");
        for (const entry of external) {
            if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
                fail(`${filePath}: external entries must be objects`);
            }
            const source = entry.source;
            if (typeof source !== "string" || source.trim() === "") {
                fail(`${filePath}: external entry is missing source`);
            }
            const skills = ensureArray(entry.skills, filePath, "external[].skills");
            if (skills.length === 0) {
                fail(`${filePath}: external entry for ${source} has no skills`);
            }
            if (!externalBySource.has(source)) {
                externalBySource.set(source, new Set());
            }
            const sourceSkills = externalBySource.get(source);
            if (!sourceSkills) {
                fail(`failed to resolve external source ${source}`);
            }
            for (const skillName of skills) {
                if (typeof skillName !== "string" || skillName.trim() === "") {
                    fail(`${filePath}: external skills must contain names`);
                }
                requireUnreservedSkillName(skillName);
                sourceSkills.add(skillName);
            }
        }
        const local = ensureArray(getObjectProperty(profile, "local"), filePath, "local");
        for (const skillName of local) {
            if (typeof skillName !== "string" || skillName.trim() === "") {
                fail(`${filePath}: local must contain skill names`);
            }
            requireUnreservedSkillName(skillName);
            const skillPath = path.join(localDir, skillName);
            if (!fs.existsSync(skillPath) || !fs.statSync(skillPath).isDirectory()) {
                fail(`unknown local skill ${skillName}`);
            }
            localSkills.add(skillName);
        }
        loaded.add(name);
        expanded.push(name);
    }
    for (const profileName of requestedProfiles) {
        load(profileName, []);
    }
    const owners = new Map();
    for (const [source, skills] of externalBySource) {
        for (const skillName of skills) {
            owners.set(skillName, (owners.get(skillName) ?? []).concat(source));
        }
    }
    for (const skillName of localSkills) {
        owners.set(skillName, (owners.get(skillName) ?? []).concat("local"));
    }
    const collisions = Array.from(owners.entries())
        .filter(([, skillOwners]) => skillOwners.length > 1)
        .map(([skillName, skillOwners]) => `${skillName} (${skillOwners.join(", ")})`)
        .sort();
    if (collisions.length > 0) {
        fail(`skill name collision: ${collisions.join("; ")}`);
    }
    return {
        generatedBy: "dotfiles setup skills",
        scope,
        requestedProfiles,
        expandedProfiles: expanded,
        agents,
        external: Array.from(externalBySource.entries())
            .map(([source, skills]) => ({ source, skills: Array.from(skills).sort() }))
            .sort((left, right) => left.source.localeCompare(right.source)),
        local: Array.from(localSkills)
            .sort()
            .map((name) => ({ name, path: path.join(localDir, name) })),
    };
}
function writeJson(filePath, value) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}
function writeMetadata(plan, outputFile) {
    writeJson(outputFile, {
        generatedBy: plan.generatedBy,
        scope: plan.scope,
        requestedProfiles: plan.requestedProfiles,
        expandedProfiles: plan.expandedProfiles,
        agents: plan.agents,
        external: plan.external,
        localSkills: plan.local.map((skill) => skill.name),
    });
}
function validateProfiles(dotfilesRoot, profilesCsv) {
    const profileDir = path.join(dotfilesRoot, "skills", "profiles");
    const requestedProfiles = profilesCsv ? csv(profilesCsv) : listProfiles(profileDir);
    resolveProfiles(dotfilesRoot, requestedProfiles, ["codex"], "validate");
    console.log(`Profiles valid: ${requestedProfiles.join(",")}`);
}
function removePath(targetPath) {
    fs.rmSync(targetPath, { recursive: true, force: true });
}
function isCrossDeviceRenameError(error) {
    return error.code === "EXDEV";
}
function movePath(sourcePath, targetPath) {
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    try {
        fs.renameSync(sourcePath, targetPath);
        return;
    }
    catch (error) {
        if (!isCrossDeviceRenameError(error)) {
            throw error;
        }
    }
    removePath(targetPath);
    copyEntry(sourcePath, targetPath, true);
    removePath(sourcePath);
}
// Copies one entry without following links. A link is recreated with its
// original target text, even when that target no longer exists; fs.cpSync
// rejects a dangling link given as its source. Links nested in directories are
// copied by fs.cpSync, which keeps them as they are.
function copyEntry(sourcePath, targetPath, force) {
    const linkTarget = getLinkTarget(sourcePath);
    if (linkTarget === null) {
        fs.cpSync(sourcePath, targetPath, { recursive: true, dereference: false, force, verbatimSymlinks: true });
        return;
    }
    if (fs.existsSync(targetPath) || getLinkTarget(targetPath) !== null) {
        if (!force) {
            return;
        }
        removePath(targetPath);
    }
    fs.symlinkSync(linkTarget, targetPath, windowsLinkType(sourcePath));
}
// Windows needs the link type up front. Skill entries are directories, so a
// link whose target is gone is recreated as a directory link.
function windowsLinkType(linkPath) {
    try {
        return fs.statSync(linkPath).isDirectory() ? "dir" : "file";
    }
    catch {
        return "dir";
    }
}
// The source that produced an entry, also when the name differs only in letter
// case, as it can on a case-insensitive file system.
function entryOwner(owners, entry) {
    return owners.get(entry)
        ?? Array.from(owners).find(([name]) => name.toLowerCase() === entry.toLowerCase())?.[1]
        ?? "an earlier install";
}
// Fails when directory already holds an entry named entry. The check uses
// lstat on the target path, so it also catches a dangling link and a name that
// differs only in letter case on a case-insensitive file system, and it never
// follows a link out of the directory.
function requireNoEntry(directory, entry, owners, origin, place) {
    if (fs.lstatSync(path.join(directory, entry), { throwIfNoEntry: false })) {
        fail(`skill entry collision in ${place}: ${entry} (${entryOwner(owners, entry)}, ${origin})`);
    }
}
// Fails when an install produced an entry with a reserved name in any letter
// case, such as synced, which the user view keeps for externally synchronized
// skills.
function requireUnreservedEntry(entry, source, place) {
    if ((0, skill_names_1.isReservedSkillName)(entry)) {
        fail(`skill entry collision in ${place}: ${entry} (${source}, reserved name)`);
    }
}
// Copies every entry an install produced into the user staging view, failing
// when the entry has a reserved name or an earlier install already produced an
// entry with the same name. owners maps each copied entry name to the source
// that produced it.
function copyDirectoryContents(sourceDir, targetDir, source, owners) {
    if (!fs.existsSync(sourceDir)) {
        return;
    }
    fs.mkdirSync(targetDir, { recursive: true });
    for (const entry of fs.readdirSync(sourceDir)) {
        requireUnreservedEntry(entry, source, "user staging");
        requireNoEntry(targetDir, entry, owners, source, "user staging");
        copyEntry(path.join(sourceDir, entry), path.join(targetDir, entry), false);
        owners.set(entry, source);
    }
}
function copyMissingDirectoryEntries(sourceDir, targetDir, skip = new Set()) {
    if (!fs.existsSync(sourceDir)) {
        return;
    }
    fs.mkdirSync(targetDir, { recursive: true });
    for (const entry of fs.readdirSync(sourceDir)) {
        const targetEntry = path.join(targetDir, entry);
        if (skip.has(entry) || fs.existsSync(targetEntry) || getLinkTarget(targetEntry)) {
            continue;
        }
        copyEntry(path.join(sourceDir, entry), targetEntry, false);
    }
}
function normalizePath(targetPath) {
    return path.resolve(targetPath);
}
function getLinkTarget(targetPath) {
    try {
        const stat = fs.lstatSync(targetPath);
        if (!stat.isSymbolicLink()) {
            return null;
        }
        return fs.readlinkSync(targetPath);
    }
    catch {
        return null;
    }
}
function isManagedLocalSymlink(targetPath, expectedRoot) {
    const linked = getLinkTarget(targetPath);
    if (!linked) {
        return false;
    }
    const resolvedLinked = normalizePath(path.resolve(path.dirname(targetPath), linked));
    const resolvedRoot = normalizePath(expectedRoot);
    return resolvedLinked === resolvedRoot || resolvedLinked.startsWith(`${resolvedRoot}${path.sep}`);
}
// A stale managed entry is one setup placed for a skill that `keep` no longer
// lists or whose source is gone. Setup installs `<name>` only as a link to
// `<managedRoot>/<name>` or as a copy whose marker names that source, so other
// links and copies are never treated as managed; a copy is stale only while its
// content is unchanged. Each result lists the entry name and, for a copy, its
// marker name. Links resolve from `linkBase`, the directory the entries were
// installed in. `keptExists` treats kept names as present, for a dry run
// planned before the managed root is rebuilt.
function staleManagedEntries(directory, managedRoot, keep, options = {}) {
    const linkBase = options.linkBase ?? directory;
    if (!fs.lstatSync(directory, { throwIfNoEntry: false })?.isDirectory()) {
        return [];
    }
    const stale = [];
    for (const name of fs.readdirSync(directory).sort()) {
        if (name.startsWith(".") || (options.prunable && !options.prunable(name))) {
            continue;
        }
        const entry = path.join(directory, name);
        const installed = path.join(linkBase, name);
        const managedSource = normalizePath(path.join(managedRoot, name));
        const isStale = (source) => !keep.has(name) || (!options.keptExists && !fs.existsSync(source));
        const linked = getLinkTarget(entry);
        if (linked !== null) {
            const source = path.resolve(linkBase, linked);
            if (normalizePath(source) === managedSource && isStale(source)) {
                stale.push([name]);
            }
            continue;
        }
        const marker = (0, shared_links_1.copyMarker)(name);
        const markerStat = fs.lstatSync(path.join(directory, marker), { throwIfNoEntry: false });
        if (!markerStat) {
            continue;
        }
        if (!markerStat.isFile() || markerStat.isSymbolicLink()) {
            warn(`Keeping skill copy with an invalid copy marker: ${installed}`);
            continue;
        }
        let saved;
        try {
            saved = (0, shared_links_1.parseCopyMarker)(fs.readFileSync(path.join(directory, marker), "utf8"));
        }
        catch {
            saved = undefined;
        }
        if (!saved) {
            warn(`Keeping skill copy with an invalid copy marker: ${installed}`);
            continue;
        }
        // Match planSharedLink: a marker is managed only when it names the source exactly.
        if (saved.source !== managedSource || !isStale(saved.source)) {
            continue;
        }
        let current;
        try {
            current = (0, shared_links_1.snapshot)(entry);
        }
        catch {
            current = undefined;
        }
        if (!(0, shared_links_1.sameSnapshot)(current, saved.files)) {
            warn(`Keeping locally edited copy of a removed skill: ${installed}`);
            continue;
        }
        stale.push([name, marker]);
    }
    return stale;
}
function pruneStaleManagedEntries(directory, stale, dryRun) {
    for (const [name, ...rest] of stale) {
        const entry = path.join(directory, name);
        if (dryRun) {
            info(`DRY-RUN remove stale skill entry ${entry}`);
            continue;
        }
        for (const item of [name, ...rest]) {
            removePath(path.join(directory, item));
        }
        info(`Removed stale skill entry: ${entry}`);
    }
}
// With copy, every entry is installed as a marked copy without attempting a
// link or elevation.
function createSymlinks(links, expectedRoot, copyAll = false) {
    const stages = [];
    const pending = [];
    try {
        for (const link of links) {
            const source = path.resolve(link.source);
            let copy = copyAll;
            const linked = getLinkTarget(link.target);
            if (!copyAll && linked !== null && path.resolve(path.dirname(link.target), linked) === source)
                continue;
            const marker = path.join(path.dirname(link.target), (0, shared_links_1.copyMarker)(path.basename(link.target)));
            if (fs.lstatSync(link.target, { throwIfNoEntry: false }) &&
                ((expectedRoot && !isManagedLocalSymlink(link.target, expectedRoot)) || fs.existsSync(marker))) {
                const change = (0, shared_links_1.planSharedLink)(path.dirname(link.target), { name: path.basename(link.target), source, directory: true });
                if (!change)
                    continue;
                copy = copyAll || change.copy === true;
            }
            fs.mkdirSync(path.dirname(link.target), { recursive: true });
            const stage = fs.mkdtempSync(path.join(path.dirname(link.target), ".dotfiles-skill-link-"));
            stages.push(stage);
            pending.push({ source, target: link.target, artifact: path.join(stage, path.basename(link.target)), copy });
        }
        (0, shared_links_1.stageSharedLinks)(pending.map(link => ({ source: link.source, target: link.artifact, directory: true, copy: link.copy })), true);
        for (const link of pending) {
            const copied = !fs.lstatSync(link.artifact).isSymbolicLink();
            const marker = path.join(path.dirname(link.target), (0, shared_links_1.copyMarker)(path.basename(link.target)));
            const metadata = copied ? (0, shared_links_1.copyMetadata)(link.source, (0, shared_links_1.snapshot)(link.artifact)) : undefined;
            removePath(link.target);
            fs.renameSync(link.artifact, link.target);
            if (metadata) {
                fs.writeFileSync(marker, metadata);
                warn(`Copied skill directory: ${link.target}; rerun setup to refresh copies.`);
            }
            else if (fs.existsSync(marker))
                fs.unlinkSync(marker);
        }
    }
    finally {
        for (const stage of stages)
            fs.rmSync(stage, { recursive: true, force: true });
    }
}
function agentSkillDir(root, agent) {
    if (agent === "codex") {
        return path.join(root, ".agents", "skills");
    }
    if (agent === "claude-code") {
        return path.join(root, ".claude", "skills");
    }
    fail(`unsupported agent: ${agent}`);
}
// Local skills never replace an entry an external install produced; a
// same-name entry fails with both origins before any link is created.
function requireNoLocalSkillEntries(plan, skillsDir, owners, place) {
    for (const skill of plan.local) {
        requireNoEntry(skillsDir, skill.name, owners, "local", place);
    }
}
function linkLocalSkills(plan, dotfilesRoot, target, rootOrSkillsDir, copy = false) {
    const localRoot = path.join(dotfilesRoot, "skills", "local");
    if (target === "user") {
        createSymlinks(plan.local.map(skill => ({ source: skill.path, target: path.join(rootOrSkillsDir, skill.name) })), localRoot);
        return;
    }
    createSymlinks(plan.agents.flatMap(agent => {
        const skillsDir = agentSkillDir(rootOrSkillsDir, agent);
        return plan.local.map(skill => ({ source: skill.path, target: path.join(skillsDir, skill.name) }));
    }), localRoot, copy);
}
function isWindowsBatchFile(command) {
    return process.platform === "win32" && /\.(cmd|bat)$/i.test(command);
}
// Node runs a bare `cmd.exe` when ComSpec is unset, which Windows may resolve
// from the current directory, so pass cmd.exe by absolute path.
function windowsCommandShell(env = process.env) {
    const comspec = env.ComSpec ?? env.COMSPEC;
    if (comspec && path.isAbsolute(comspec)) {
        return path.normalize(comspec);
    }
    const systemRoot = env.SystemRoot ?? env.SYSTEMROOT;
    if (systemRoot && path.isAbsolute(systemRoot)) {
        return path.join(systemRoot, "System32", "cmd.exe");
    }
    fail("cannot locate cmd.exe: set ComSpec or SystemRoot to an absolute path");
}
function runCommand(command, args, cwd, env = process.env) {
    // cmd.exe receives the command line unquoted under a shell, so quote the
    // batch file path to keep paths such as C:\Program Files intact.
    const batch = isWindowsBatchFile(command);
    const result = (0, node_child_process_1.spawnSync)(batch ? `"${command}"` : command, args, {
        cwd,
        env,
        shell: batch ? windowsCommandShell() : false,
        stdio: ["ignore", "inherit", "inherit"],
    });
    if (result.error) {
        fail(result.error.message);
    }
    if (result.status !== 0) {
        fail(`${command} ${args.join(" ")} failed with exit ${result.status ?? "unknown"}`);
    }
}
// Run npm's npx-cli.js with node when it sits next to the npx.cmd shim, which
// keeps cmd.exe out of the argument handling. Other shims (for example mise)
// fall back to running the batch file.
function resolveNpx() {
    const npxCommand = resolveCommand("npx");
    if (isWindowsBatchFile(npxCommand)) {
        const npxCli = path.join(path.dirname(npxCommand), "node_modules", "npm", "bin", "npx-cli.js");
        if (fs.existsSync(npxCli)) {
            return { command: process.execPath, args: [npxCli] };
        }
    }
    return { command: npxCommand, args: [] };
}
function commandPreview(command, args) {
    return [command, ...args].join(" ");
}
function logDryRunExternalInstalls(stagingBase, projectRoot, plan, agents, npmCacheDir) {
    if (plan.external.length === 0) {
        return;
    }
    const workDir = path.join(stagingBase, `${PROJECT_STAGING_PREFIX}XXXXXX`);
    info(`DRY-RUN mktemp -d ${workDir}`);
    for (const entry of plan.external) {
        const args = ["skills", "add", entry.source, "--copy", "--yes"];
        for (const agent of agents) {
            args.push("--agent", agent);
        }
        for (const skill of entry.skills) {
            args.push("--skill", skill);
        }
        info(`DRY-RUN cd ${workDir} && NPM_CONFIG_CACHE=${npmCacheDir} ${commandPreview("npx", args)}`);
    }
    info(`DRY-RUN move skills-lock.json and agent skill directories from ${workDir} to ${projectRoot}`);
    info(`DRY-RUN rm -rf ${workDir}`);
}
function logDryRunUserExternalInstalls(stagingBase, plan, npmCacheDir) {
    if (plan.external.length === 0) {
        return;
    }
    const workDir = path.join(stagingBase, `${USER_STAGING_PREFIX}XXXXXX`);
    info(`DRY-RUN mktemp -d ${workDir}`);
    plan.external.forEach((entry, index) => {
        const installDir = path.join(workDir, String(index));
        info(`DRY-RUN mkdir ${installDir}`);
        const args = ["skills", "add", entry.source, "--copy", "--yes", "--agent", "codex"];
        for (const skill of entry.skills) {
            args.push("--skill", skill);
        }
        info(`DRY-RUN cd ${installDir} && NPM_CONFIG_CACHE=${npmCacheDir} ${commandPreview("npx", args)}`);
    });
    info(`DRY-RUN rm -rf ${workDir}`);
}
function logDryRunLinkLocalSkills(plan, target, rootOrSkillsDir, copy = false) {
    if (target === "user") {
        for (const skill of plan.local) {
            info(`DRY-RUN ln -s ${skill.path} ${path.join(rootOrSkillsDir, skill.name)}`);
        }
        return;
    }
    for (const agent of plan.agents) {
        const skillsDir = agentSkillDir(rootOrSkillsDir, agent);
        for (const skill of plan.local) {
            info(`DRY-RUN ${copy ? "copy" : "ln -s"} ${skill.path} ${path.join(skillsDir, skill.name)}`);
        }
    }
}
function logDryRunUserAgentSkillDirs(restoreSkillsDir, setupHome, agents) {
    for (const agent of agents) {
        if (agent === "codex") {
            info(`DRY-RUN mkdir -p ${path.join(setupHome, ".agents")}`);
            info(`DRY-RUN ln -s ${restoreSkillsDir} ${path.join(setupHome, ".agents", "skills")}`);
            continue;
        }
        if (agent === "claude-code") {
            info(`DRY-RUN mkdir -p ${path.join(setupHome, ".claude")}`);
            info(`DRY-RUN ln -s ${restoreSkillsDir} ${path.join(setupHome, ".claude", "skills")}`);
        }
    }
}
const PROJECT_STAGING_PREFIX = "dotfiles-skills-";
const USER_STAGING_PREFIX = "dotfiles-skills-user-";
const NPM_CACHE_NAME = "dotfiles-skills-npm-cache";
const BACKUP_DIR_NAME = "dotfiles-skills-backup";
// npm and npx look for package.json, node_modules/.bin, and .npmrc in every
// ancestor of their current directory, so stage installs, and keep the npm
// cache and project backups, under a per-user directory rather than a shared
// temp directory such as /tmp. Linux uses the XDG cache directory, macOS the
// per-user temp directory, and Windows %TEMP%. SETUP_TMPDIR may be shared and
// is not used for skills. See private-base.ts for the checks: every directory
// is checked before any is created, so a refusal creates nothing.
function privateSkillsBase() {
    return (0, private_base_1.privateSkillsBase)(process.env, process.platform, path, os.tmpdir, os.homedir);
}
function removeStagingDir(workDir) {
    // A cleanup failure, such as EBUSY on Windows, must not replace the
    // install's own result.
    try {
        fs.rmSync(workDir, { recursive: true, force: true, maxRetries: 3 });
    }
    catch (error) {
        warn(`Could not remove staging directory ${workDir}: ${error.message}`);
    }
}
// Install in a private per-run staging directory and move the outputs into the
// project, so npx and any batch shim never run with the project as their
// current directory, where an untrusted checkout could plant node.exe,
// cmd.exe, or npm configuration.
// Returns, for each agent, the source that produced each installed entry.
function runExternalInstalls(stagingBase, projectRoot, plan, agents, npmCacheDir) {
    if (plan.external.length === 0) {
        return new Map();
    }
    const npx = resolveNpx();
    // mkdtemp creates the directory with mode 0700 on POSIX.
    const workDir = fs.mkdtempSync(path.join(stagingBase, PROJECT_STAGING_PREFIX));
    try {
        return installExternalSkills(workDir, projectRoot, plan, agents, npx, npmCacheDir);
    }
    finally {
        removeStagingDir(workDir);
    }
}
// Identifies one file system entry and everything inside it, without following
// symbolic links. Removing and recopying an entry gives it a new identity even
// when the content is the same, and the change time also catches a write,
// added or removed file, or permission change inside an entry that keeps its
// inode, and an inode reused on a file system without birth times.
function entryIdentity(entryPath) {
    const stat = fs.lstatSync(entryPath, { bigint: true, throwIfNoEntry: false });
    if (!stat) {
        return undefined;
    }
    const type = stat.isSymbolicLink() ? `link:${fs.readlinkSync(entryPath)}` : stat.isDirectory() ? "dir" : "file";
    const identity = `${stat.dev}:${stat.ino}:${stat.birthtimeNs}:${stat.ctimeNs}:${type}`;
    if (!stat.isDirectory()) {
        return identity;
    }
    const children = fs.readdirSync(entryPath).sort().map((name) => {
        return `${JSON.stringify(name)}=${entryIdentity(path.join(entryPath, name)) ?? "missing"}`;
    });
    return `${identity}{${children.join(",")}}`;
}
function entryIdentities(directory) {
    const identities = new Map();
    if (!fs.lstatSync(directory, { throwIfNoEntry: false })?.isDirectory()) {
        return identities;
    }
    for (const name of fs.readdirSync(directory)) {
        // Dot entries are not skills; the CLI may keep its own state there.
        if (name.startsWith(".")) {
            continue;
        }
        const identity = entryIdentity(path.join(directory, name));
        if (identity) {
            identities.set(name, identity);
        }
    }
    return identities;
}
// Fails when an install left an agent skills directory, or a directory on the
// way to it inside the work directory, as a symbolic link or anything other
// than a directory. In a project install entryIdentities sees no entries there,
// so the collision and reserved-name checks would pass, and the link would be
// moved into the project; in a user install the copy would read what the link
// points to outside the staging directory. An absent directory is left to
// requireInstalledSkills.
function requireRealAgentSkillDir(workDir, agent, source, place) {
    let current = workDir;
    for (const part of path.relative(workDir, agentSkillDir(workDir, agent)).split(path.sep)) {
        current = path.join(current, part);
        const stat = fs.lstatSync(current, { throwIfNoEntry: false });
        if (!stat) {
            return;
        }
        if (!stat.isDirectory()) {
            const reason = stat.isSymbolicLink() ? "symbolic link" : "not a directory";
            fail(`skill entry collision in ${place}: ${path.relative(workDir, current)} (${source}, ${reason})`);
        }
    }
}
// All sources install in sequence into one work directory, so a later source
// can replace an entry an earlier source produced. Fail when an install
// removes or replaces any entry that existed before it ran.
function installExternalSkills(workDir, projectRoot, plan, agents, npx, npmCacheDir) {
    const owners = new Map(agents.map(agent => [agent, new Map()]));
    for (const entry of plan.external) {
        const before = new Map(agents.map(agent => [agent, entryIdentities(agentSkillDir(workDir, agent))]));
        const args = ["skills", "add", entry.source, "--copy", "--yes"];
        for (const agent of agents) {
            args.push("--agent", agent);
        }
        for (const skill of entry.skills) {
            args.push("--skill", skill);
        }
        runCommand(npx.command, [...npx.args, ...args], workDir, {
            ...process.env,
            NPM_CONFIG_CACHE: npmCacheDir,
        });
        for (const agent of agents) {
            requireRealAgentSkillDir(workDir, agent, entry.source, "project install");
            const skillsDir = agentSkillDir(workDir, agent);
            const agentOwners = owners.get(agent);
            for (const [name, identity] of before.get(agent)) {
                if (entryIdentity(path.join(skillsDir, name)) !== identity) {
                    fail(`skill entry collision in project install: ${name} (${entryOwner(agentOwners, name)}, ${entry.source})`);
                }
            }
            for (const name of entryIdentities(skillsDir).keys()) {
                if (!agentOwners.has(name)) {
                    requireUnreservedEntry(name, entry.source, "project install");
                    agentOwners.set(name, entry.source);
                }
            }
            requireInstalledSkills(skillsDir, entry);
        }
    }
    const outputs = [
        "skills-lock.json",
        ...agents.map((agent) => path.relative(workDir, agentSkillDir(workDir, agent))),
    ];
    for (const output of outputs) {
        const staged = path.join(workDir, output);
        if (!fs.existsSync(staged) && !getLinkTarget(staged)) {
            continue;
        }
        const target = path.join(projectRoot, output);
        removePath(target);
        movePath(staged, target);
    }
    return owners;
}
function requireInstalledSkills(skillsDir, entry) {
    for (const name of entry.skills) {
        const skillFile = path.join(skillsDir, name, "SKILL.md");
        if (!fs.existsSync(skillFile) || !fs.statSync(skillFile).isFile()) {
            fail(`Missing installed skill ${name} from ${entry.source}: ${skillFile}`);
        }
    }
}
// Like project installs, run each source in a fresh directory inside a private
// per-run staging directory so npx never sees a shared parent directory.
// owners receives the source that produced each copied entry.
function runUserExternalInstalls(stagingBase, restoreSkillsDir, plan, npmCacheDir, owners) {
    if (plan.external.length === 0) {
        return;
    }
    const npx = resolveNpx();
    // mkdtemp creates the directory with mode 0700 on POSIX.
    const workDir = fs.mkdtempSync(path.join(stagingBase, USER_STAGING_PREFIX));
    try {
        plan.external.forEach((entry, index) => {
            const installDir = path.join(workDir, String(index));
            fs.mkdirSync(installDir, { mode: 0o700 });
            const args = ["skills", "add", entry.source, "--copy", "--yes", "--agent", "codex"];
            for (const skill of entry.skills) {
                args.push("--skill", skill);
            }
            runCommand(npx.command, [...npx.args, ...args], installDir, {
                ...process.env,
                NPM_CONFIG_CACHE: npmCacheDir,
            });
            requireRealAgentSkillDir(installDir, "codex", entry.source, "user staging");
            const installedSkillsDir = agentSkillDir(installDir, "codex");
            requireInstalledSkills(installedSkillsDir, entry);
            copyDirectoryContents(installedSkillsDir, restoreSkillsDir, entry.source, owners);
        });
    }
    finally {
        removeStagingDir(workDir);
    }
}
function swapUserSkillsView(restoreRoot, restoreSkillsDir, stagingSkillsDir, stagingMetadata) {
    const metadataFile = path.join(restoreRoot, "skills-profile.json");
    const suffix = `${process.pid}`;
    const backupSkillsDir = path.join(restoreRoot, `skills.previous.${suffix}`);
    const backupMetadata = path.join(restoreRoot, `skills-profile.json.previous.${suffix}`);
    removePath(backupSkillsDir);
    removePath(backupMetadata);
    if (fs.existsSync(restoreSkillsDir) || getLinkTarget(restoreSkillsDir)) {
        movePath(restoreSkillsDir, backupSkillsDir);
    }
    if (fs.existsSync(metadataFile) || getLinkTarget(metadataFile)) {
        movePath(metadataFile, backupMetadata);
    }
    try {
        movePath(stagingSkillsDir, restoreSkillsDir);
        movePath(stagingMetadata, metadataFile);
    }
    catch (error) {
        removePath(restoreSkillsDir);
        removePath(metadataFile);
        if (fs.existsSync(backupSkillsDir) || getLinkTarget(backupSkillsDir)) {
            movePath(backupSkillsDir, restoreSkillsDir);
        }
        if (fs.existsSync(backupMetadata) || getLinkTarget(backupMetadata)) {
            movePath(backupMetadata, metadataFile);
        }
        throw error;
    }
    removePath(backupSkillsDir);
    removePath(backupMetadata);
}
function linkUserAgentSkillDirs(restoreSkillsDir, setupHome, agents) {
    createSymlinks(agents.map(agent => ({ source: restoreSkillsDir, target: agentSkillDir(setupHome, agent) })));
}
function claudeEnvironmentSkillDirs(setupHome) {
    const root = path.join(setupHome, ".claude-envs");
    const stat = fs.lstatSync(root, { throwIfNoEntry: false });
    if (!stat) {
        return [];
    }
    if (!stat.isDirectory()) {
        warn(`Skipping symlink or unexpected Claude environment directory: ${root}`);
        return [];
    }
    const directories = [];
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
        if (!entry.isDirectory()) {
            continue;
        }
        const environment = path.join(root, entry.name);
        const marker = path.join(environment, ".claude-pick");
        const settings = path.join(environment, "settings.json");
        if (!fs.lstatSync(marker, { throwIfNoEntry: false })?.isFile()
            || !fs.lstatSync(settings, { throwIfNoEntry: false })?.isFile()
            || fs.readFileSync(marker, "utf8").replace(/[\r\n]+$/, "") !== "1") {
            continue;
        }
        const skills = path.join(environment, "skills");
        const skillsStat = fs.lstatSync(skills, { throwIfNoEntry: false });
        if (skillsStat && !skillsStat.isDirectory()) {
            warn(`Skipping symlink or unexpected Claude environment skills directory: ${skills}`);
            continue;
        }
        directories.push(skills);
    }
    return directories;
}
function isClaudeEnvironmentSkillName(name) {
    return /^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(name) && !(0, skill_names_1.isReservedSkillName)(name);
}
function linkClaudeEnvironmentSkills(restoreSkillsDir, directories, names, dryRun) {
    if (directories.length === 0) {
        return;
    }
    const links = [];
    for (const name of names.sort()) {
        if (!isClaudeEnvironmentSkillName(name)) {
            continue;
        }
        const source = path.join(restoreSkillsDir, name);
        const definition = path.join(source, "SKILL.md");
        if (!dryRun && (!fs.existsSync(definition) || !fs.statSync(definition).isFile())) {
            continue;
        }
        for (const directory of directories) {
            const target = path.join(directory, name);
            if (fs.lstatSync(target, { throwIfNoEntry: false })) {
                const linked = getLinkTarget(target);
                if (!linked || path.resolve(directory, linked) !== source) {
                    warn(`Preserving existing Claude environment skill: ${target}`);
                }
                continue;
            }
            if (dryRun) {
                info(`DRY-RUN ln -s ${source} ${target}`);
            }
            else {
                links.push({ source, target });
            }
        }
    }
    createSymlinks(links);
    const keep = new Set(names);
    for (const directory of directories) {
        const stale = staleManagedEntries(directory, restoreSkillsDir, keep, { prunable: isClaudeEnvironmentSkillName, keptExists: dryRun });
        pruneStaleManagedEntries(directory, stale, dryRun);
    }
}
function setupUserSkills(dotfilesRoot, setupHome, profilesCsv, agents, dryRun, skipUserLocalSkillLinks, skipUserAgentSkillLinks) {
    const requestedProfiles = csv(profilesCsv || "base");
    const plan = resolveProfiles(dotfilesRoot, requestedProfiles, agents, "user");
    const restoreRoot = path.join(dotfilesRoot, ".agents", "user");
    const restoreSkillsDir = path.join(restoreRoot, "skills");
    const suffix = `${process.pid}`;
    const stagingSkillsDir = path.join(restoreRoot, `skills.next.${suffix}`);
    const stagingMetadata = path.join(restoreRoot, `skills-profile.json.next.${suffix}`);
    if (dryRun) {
        info(`DRY-RUN rm -rf ${stagingSkillsDir}`);
        info(`DRY-RUN rm -rf ${stagingMetadata}`);
        info(`DRY-RUN mkdir -p ${restoreRoot}`);
        info(`DRY-RUN mkdir -p ${stagingSkillsDir}`);
        if (plan.external.length > 0) {
            const base = privateSkillsBase();
            const npmCacheDir = path.join(base, NPM_CACHE_NAME);
            info(`DRY-RUN mkdir -p ${npmCacheDir}`);
            logDryRunUserExternalInstalls(base, plan, npmCacheDir);
        }
        info(`DRY-RUN preserve ${path.join(restoreSkillsDir, "synced")} in ${stagingSkillsDir}`);
        if (skipUserLocalSkillLinks) {
            info("DRY-RUN skip user local skill links");
        }
        else {
            logDryRunLinkLocalSkills(plan, "user", stagingSkillsDir);
        }
        info(`DRY-RUN write skills metadata ${stagingMetadata}`);
        info(`DRY-RUN swap ${stagingSkillsDir} into ${restoreSkillsDir}`);
        info(`DRY-RUN mv ${stagingMetadata} ${path.join(restoreRoot, "skills-profile.json")}`);
        if (skipUserAgentSkillLinks) {
            info("DRY-RUN skip user agent skill links");
        }
        else {
            logDryRunUserAgentSkillDirs(restoreSkillsDir, setupHome, agents);
            if (agents.includes("claude-code")) {
                const names = [...new Set([
                        ...plan.external.flatMap(entry => entry.skills),
                        ...(skipUserLocalSkillLinks ? [] : plan.local.map(skill => skill.name)),
                    ])];
                linkClaudeEnvironmentSkills(restoreSkillsDir, claudeEnvironmentSkillDirs(setupHome), names, true);
            }
        }
        info(`User skills installed for profiles: ${requestedProfiles.join(",")}`);
        return;
    }
    let stagingBase = "";
    let npmCacheDir = "";
    if (plan.external.length > 0) {
        const base = privateSkillsBase();
        const staging = (0, private_base_1.planPrivateDir)(base, "user skill staging");
        const npmCache = (0, private_base_1.planPrivateDir)(path.join(staging.real, NPM_CACHE_NAME), "the skills npm cache");
        (0, private_base_1.createPrivateDirs)([staging, npmCache]);
        stagingBase = staging.real;
        npmCacheDir = npmCache.real;
    }
    removePath(stagingSkillsDir);
    removePath(stagingMetadata);
    fs.mkdirSync(restoreRoot, { recursive: true });
    fs.mkdirSync(stagingSkillsDir, { recursive: true });
    try {
        const owners = new Map();
        runUserExternalInstalls(stagingBase, stagingSkillsDir, plan, npmCacheDir, owners);
        // synced/ is reserved for externally synchronized skills; an install entry
        // that the file system resolves to it would be merged with them, or
        // written through as a link. copyDirectoryContents rejects reserved names,
        // but a case-insensitive file system can also fold a name the check does
        // not match, such as one spelled with U+017F, so check the path as well.
        requireNoEntry(stagingSkillsDir, "synced", owners, "reserved name", "user staging");
        copyMissingDirectoryEntries(path.join(restoreSkillsDir, "synced"), path.join(stagingSkillsDir, "synced"));
        if (skipUserLocalSkillLinks) {
            info("User local skill links skipped");
        }
        else {
            requireNoLocalSkillEntries(plan, stagingSkillsDir, owners, "user staging");
            linkLocalSkills(plan, dotfilesRoot, "user", stagingSkillsDir);
        }
        writeMetadata(plan, stagingMetadata);
        swapUserSkillsView(restoreRoot, restoreSkillsDir, stagingSkillsDir, stagingMetadata);
    }
    catch (error) {
        removePath(stagingSkillsDir);
        removePath(stagingMetadata);
        throw error;
    }
    removePath(stagingSkillsDir);
    removePath(stagingMetadata);
    if (skipUserAgentSkillLinks) {
        info("User agent skill links skipped");
    }
    else {
        linkUserAgentSkillDirs(restoreSkillsDir, setupHome, agents);
        if (agents.includes("claude-code")) {
            linkClaudeEnvironmentSkills(restoreSkillsDir, claudeEnvironmentSkillDirs(setupHome), fs.readdirSync(restoreSkillsDir), false);
        }
    }
    info(`User skills installed for profiles: ${requestedProfiles.join(",")}`);
}
function backupPath(targetPath, backupRoot, records) {
    if (!fs.existsSync(targetPath) && !getLinkTarget(targetPath)) {
        records.push({ targetPath, backupPath: null });
        return;
    }
    const backupName = `${path.basename(path.dirname(targetPath))}-${path.basename(targetPath)}`;
    const backupTarget = path.join(backupRoot, `${backupName}.${timestamp()}.${process.pid}`);
    fs.mkdirSync(backupRoot, { recursive: true });
    movePath(targetPath, backupTarget);
    // Record the target only after its move succeeds. Rollback removes each
    // recorded target before restoring it, so a record for a target whose move
    // failed would delete the user's original.
    records.push({ targetPath, backupPath: backupTarget });
    warn(`Backed up existing skills path to ${backupTarget}`);
}
function timestamp() {
    const now = new Date();
    const pad = (value) => String(value).padStart(2, "0");
    return [
        now.getFullYear(),
        pad(now.getMonth() + 1),
        pad(now.getDate()),
        pad(now.getHours()),
        pad(now.getMinutes()),
        pad(now.getSeconds()),
    ].join("");
}
// The project paths that setup backs up, replaces, and writes.
function projectTargets(projectRoot, agents, includeLockfile) {
    return [
        ...(includeLockfile ? [path.join(projectRoot, "skills-lock.json")] : []),
        path.join(projectRoot, ".agents", "skills-profile.json"),
        ...agents.map(agent => agentSkillDir(projectRoot, agent)),
    ];
}
// A checkout can make a target, or a directory such as .agents or .claude on
// the way to it, a link. Backups, moves, and writes would then follow it out
// of the project, and a link moved into the backup directory resolves again
// from there, so even a link inside the project can copy other projects'
// backups into this one. Refuse any link, wherever it points and even when it
// dangles, before changing anything.
function requireNoProjectTargetLinks(projectRoot, targets) {
    for (const target of targets) {
        let current = projectRoot;
        for (const part of path.relative(projectRoot, target).split(path.sep)) {
            current = path.join(current, part);
            const stat = fs.lstatSync(current, { throwIfNoEntry: false });
            if (!stat) {
                break;
            }
            if (stat.isSymbolicLink()) {
                fail(`refusing to set up project skills: ${current} is a symbolic link to ${fs.readlinkSync(current)}; ` +
                    "replace it with a directory or file in the project");
            }
        }
    }
}
// Fills the caller's records as each target moves, so the caller can roll
// back the targets already moved when a later move fails.
function prepareProjectTargets(targets, backupRoot, records) {
    for (const target of targets) {
        backupPath(target, backupRoot, records);
    }
}
function rollbackProjectTargets(records) {
    for (const record of records) {
        removePath(record.targetPath);
        if (record.backupPath && (fs.existsSync(record.backupPath) || getLinkTarget(record.backupPath))) {
            fs.mkdirSync(path.dirname(record.targetPath), { recursive: true });
            movePath(record.backupPath, record.targetPath);
        }
    }
    warn("Restored previous project skills after failed install");
}
// Entries the previous run installed for skills no longer selected stay in the
// backup instead of being restored. So does the copy marker of a selected
// skill: it describes the replaced entry, not the one this run installed.
function restoreUnmanagedProjectSkills(records, projectRoot, agents, localRoot, keep) {
    const agentSkillDirs = new Set(agents.map((agent) => agentSkillDir(projectRoot, agent)));
    const selectedMarkers = [...keep].map(name => (0, shared_links_1.copyMarker)(name));
    for (const record of records) {
        if (!record.backupPath || !agentSkillDirs.has(record.targetPath)) {
            continue;
        }
        const stale = staleManagedEntries(record.backupPath, localRoot, keep, { linkBase: record.targetPath });
        copyMissingDirectoryEntries(record.backupPath, record.targetPath, new Set([...stale.flat(), ...selectedMarkers]));
        for (const [name] of stale) {
            info(`Removed stale skill entry: ${path.join(record.targetPath, name)}`);
        }
    }
}
// A selected local skill always replaces its previous entry. Name the backup
// of a copy that was edited after setup made it, so the edits can be recovered.
function warnReplacedEditedCopies(records, projectRoot, agents, selected) {
    const agentSkillDirs = new Set(agents.map((agent) => agentSkillDir(projectRoot, agent)));
    for (const record of records) {
        if (!record.backupPath || !agentSkillDirs.has(record.targetPath)) {
            continue;
        }
        for (const name of [...selected].sort()) {
            const entry = path.join(record.backupPath, name);
            const marker = path.join(record.backupPath, (0, shared_links_1.copyMarker)(name));
            const markerStat = fs.lstatSync(marker, { throwIfNoEntry: false });
            const entryStat = fs.lstatSync(entry, { throwIfNoEntry: false });
            if (!markerStat?.isFile() || !entryStat?.isDirectory()) {
                continue;
            }
            let edited;
            try {
                const saved = (0, shared_links_1.parseCopyMarker)(fs.readFileSync(marker, "utf8"));
                edited = !saved || !(0, shared_links_1.sameSnapshot)((0, shared_links_1.snapshot)(entry), saved.files);
            }
            catch {
                edited = true;
            }
            if (edited) {
                warn(`Replaced locally edited skill copy: ${path.join(record.targetPath, name)}; previous copy kept in ${entry}`);
            }
        }
    }
}
function gitProjectRoot(cwd) {
    const gitCommand = resolveCommand("git");
    const result = (0, node_child_process_1.spawnSync)(gitCommand, ["-C", cwd, "rev-parse", "--show-toplevel"], {
        encoding: "utf8",
    });
    if (result.status !== 0) {
        fail("project scope requires running inside a git repository");
    }
    return result.stdout.trim();
}
function setupProjectSkills(dotfilesRoot, profilesCsv, agents, dryRun, copy) {
    if (!profilesCsv) {
        fail("--profile is required for project scope");
    }
    for (const agent of agents) {
        if (!SUPPORTED_AGENTS.has(agent)) {
            fail(`unsupported skills agent: ${agent}`);
        }
    }
    const requestedProfiles = csv(profilesCsv);
    const projectRoot = gitProjectRoot(process.cwd());
    const plan = resolveProfiles(dotfilesRoot, requestedProfiles, agents, "project");
    const hasExternal = plan.external.length > 0;
    const targets = projectTargets(projectRoot, agents, hasExternal);
    requireNoProjectTargetLinks(projectRoot, targets);
    const base = privateSkillsBase();
    const backupName = path.basename(projectRoot);
    const localRoot = path.join(dotfilesRoot, "skills", "local");
    const localNames = new Set(plan.local.map(skill => skill.name));
    if (dryRun) {
        const npmCacheDir = path.join(base, NPM_CACHE_NAME);
        const backupRoot = path.join(base, BACKUP_DIR_NAME, backupName);
        if (hasExternal) {
            info(`DRY-RUN mkdir -p ${npmCacheDir}`);
        }
        info(`DRY-RUN mkdir -p ${backupRoot}`);
        info(`DRY-RUN mkdir -p ${path.join(projectRoot, ".agents")}`);
        if (plan.external.length > 0) {
            info(`DRY-RUN backup ${path.join(projectRoot, "skills-lock.json")} to ${backupRoot}`);
        }
        info(`DRY-RUN backup ${path.join(projectRoot, ".agents", "skills-profile.json")} to ${backupRoot}`);
        for (const agent of agents) {
            info(`DRY-RUN backup ${agentSkillDir(projectRoot, agent)} to ${backupRoot}`);
        }
        logDryRunExternalInstalls(base, projectRoot, plan, agents, npmCacheDir);
        logDryRunLinkLocalSkills(plan, "project", projectRoot, copy);
        for (const agent of agents) {
            const skillsDir = agentSkillDir(projectRoot, agent);
            pruneStaleManagedEntries(skillsDir, staleManagedEntries(skillsDir, localRoot, localNames), true);
        }
        info(`DRY-RUN write skills metadata ${path.join(projectRoot, ".agents", "skills-profile.json")}`);
        info(`Project skills installed for profiles: ${requestedProfiles.join(",")}`);
        info("Consider ignoring generated skill directories: .agents/skills/ .claude/skills/");
        return;
    }
    // Check every directory, including the shared backup directory, before
    // creating any of them or this project's directory in it.
    const staging = (0, private_base_1.planPrivateDir)(base, hasExternal ? "project skill staging" : "project skill backups", projectRoot);
    const npmCache = hasExternal ? (0, private_base_1.planPrivateDir)(path.join(staging.real, NPM_CACHE_NAME), "the skills npm cache", projectRoot) : undefined;
    const backupBase = (0, private_base_1.planPrivateDir)(path.join(staging.real, BACKUP_DIR_NAME), "project skill backups", projectRoot);
    const backupDir = (0, private_base_1.planPrivateDir)(path.join(backupBase.real, backupName), "project skill backups", projectRoot);
    (0, private_base_1.createPrivateDirs)([staging, ...(npmCache ? [npmCache] : []), backupBase, backupDir], projectRoot);
    const stagingBase = staging.real;
    const npmCacheDir = npmCache ? npmCache.real : "";
    const backupRoot = backupDir.real;
    fs.mkdirSync(path.join(projectRoot, ".agents"), { recursive: true });
    const backups = [];
    try {
        prepareProjectTargets(targets, backupRoot, backups);
        const owners = runExternalInstalls(stagingBase, projectRoot, plan, agents, npmCacheDir);
        for (const agent of agents) {
            requireNoLocalSkillEntries(plan, agentSkillDir(projectRoot, agent), owners.get(agent) ?? new Map(), "project install");
        }
        linkLocalSkills(plan, dotfilesRoot, "project", projectRoot, copy);
        restoreUnmanagedProjectSkills(backups, projectRoot, agents, localRoot, localNames);
        warnReplacedEditedCopies(backups, projectRoot, agents, localNames);
        writeMetadata(plan, path.join(projectRoot, ".agents", "skills-profile.json"));
    }
    catch (error) {
        rollbackProjectTargets(backups);
        throw error;
    }
    info(`Project skills installed for profiles: ${requestedProfiles.join(",")}`);
    info("Consider ignoring generated skill directories: .agents/skills/ .claude/skills/");
}
function setupContext() {
    const defaultDotfilesRoot = path.resolve(__dirname, "..");
    return {
        dotfilesRoot: path.resolve(process.env.SETUP_DOTFILES_ROOT || defaultDotfilesRoot),
        home: path.resolve(process.env.SETUP_HOME || process.env.HOME || os.homedir()),
        dryRun: envFlag("SETUP_DRY_RUN"),
        skipUserLocalSkillLinks: envFlag("SETUP_SKIP_USER_LOCAL_SKILL_LINKS"),
        skipUserAgentSkillLinks: envFlag("SETUP_SKIP_USER_AGENT_SKILL_LINKS"),
    };
}
function main(argv) {
    const parsed = parseArgs(argv);
    const context = setupContext();
    if (parsed.action === "profile-validate") {
        validateProfiles(context.dotfilesRoot, parsed.profiles);
        return;
    }
    if (parsed.scope === "user") {
        setupUserSkills(context.dotfilesRoot, context.home, parsed.profiles, parsed.agents, context.dryRun, context.skipUserLocalSkillLinks, context.skipUserAgentSkillLinks);
        return;
    }
    setupProjectSkills(context.dotfilesRoot, parsed.profiles, parsed.agents, context.dryRun, parsed.copy);
}
try {
    main(process.argv.slice(2));
}
catch (error) {
    console.error(error.message);
    process.exit(1);
}
