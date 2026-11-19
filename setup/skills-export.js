"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BUNDLE_MANIFEST = void 0;
exports.parseExportArgs = parseExportArgs;
exports.composeRules = composeRules;
exports.personalMarkers = personalMarkers;
exports.exportSkills = exportSkills;
const node_child_process_1 = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const skill_profiles_1 = require("./skill-profiles");
// Writes a self-contained bundle of profile-selected local skills, the local
// skills they link to, a record of external skills, and composed agent rules.
// See docs/skills-profiles.md "Export".
exports.BUNDLE_MANIFEST = "skills-bundle.json";
const GENERATED_BY = "dotfiles setup skills export";
const SCHEMA_VERSION = 1;
const MARKERS_FILE_ENV = "SETUP_EXPORT_PERSONAL_MARKERS_FILE";
const RULES_TARGETS = [
    { agent: "codex", file: "AGENTS.md", override: "codex.md" },
    { agent: "claude-code", file: "CLAUDE.md", override: "claude.md" },
];
function parseExportArgs(argv) {
    let profiles = "";
    let out = "";
    let force = false;
    const agentArgs = [];
    const exclude = [];
    let index = 0;
    function value(flag) {
        if (index + 1 >= argv.length) {
            (0, skill_profiles_1.fail)(`${flag} requires a value`);
        }
        return argv[index + 1] ?? "";
    }
    while (index < argv.length) {
        const item = argv[index];
        if (item === "--profile") {
            profiles = value(item);
            index += 2;
            continue;
        }
        if (item === "--agent") {
            agentArgs.push(value(item));
            index += 2;
            continue;
        }
        if (item === "--exclude") {
            exclude.push(...(0, skill_profiles_1.csv)(value(item)));
            index += 2;
            continue;
        }
        if (item === "--out") {
            out = value(item);
            index += 2;
            continue;
        }
        if (item === "--force") {
            force = true;
            index += 1;
            continue;
        }
        (0, skill_profiles_1.fail)(`Unknown skills export argument: ${item}`);
    }
    if ((0, skill_profiles_1.csv)(profiles).length === 0) {
        (0, skill_profiles_1.fail)("--profile is required for skills export");
    }
    if (!out) {
        (0, skill_profiles_1.fail)("--out is required for skills export");
    }
    const agents = agentArgs.length > 0 ? (0, skill_profiles_1.parseAgents)(agentArgs) : ["codex", "claude-code"];
    if (agents.length === 0) {
        (0, skill_profiles_1.fail)("--agent requires a value");
    }
    return { profiles: (0, skill_profiles_1.csv)(profiles), agents, exclude: Array.from(new Set(exclude)), out, force };
}
function toPosix(relative) {
    return relative.split(path.sep).join("/");
}
function isInsideOrSame(candidate, root) {
    const relative = path.relative(root, candidate);
    return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}
// Lists a skill's files relative to its directory, without the top-level
// evals/ directory, which holds development fixtures for this repository.
// A symbolic link fails the export because the bundle must hold real files.
function skillFiles(skillDir, skillName) {
    const files = [];
    function walk(relativeDir) {
        const entries = fs.readdirSync(path.join(skillDir, relativeDir), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
        for (const entry of entries) {
            if (relativeDir === "" && entry.name === "evals") {
                continue;
            }
            const relative = path.join(relativeDir, entry.name);
            if (entry.isSymbolicLink()) {
                (0, skill_profiles_1.fail)(`local skill ${skillName} contains a symbolic link: ${toPosix(relative)}`);
            }
            if (entry.isDirectory()) {
                walk(relative);
            }
            else if (entry.isFile()) {
                files.push(relative);
            }
            else {
                (0, skill_profiles_1.fail)(`local skill ${skillName} contains an unsupported entry: ${toPosix(relative)}`);
            }
        }
    }
    walk("");
    return files;
}
// A skill depends on another local skill when one of its files links into it
// relative to the skill directory, such as ../delivery-common/scripts/x.mjs.
// Bare skill names in prose are not dependencies.
function skillDependencies(localDir, skillName, localNames) {
    const skillDir = path.join(localDir, skillName);
    const dependencies = new Set();
    const pattern = /\.\.\/([A-Za-z0-9_][A-Za-z0-9._-]*)\//g;
    for (const relative of skillFiles(skillDir, skillName)) {
        const text = fs.readFileSync(path.join(skillDir, relative), "utf8");
        for (const match of text.matchAll(pattern)) {
            const target = match[1] ?? "";
            if (target !== skillName && localNames.has(target)) {
                dependencies.add(target);
            }
        }
    }
    return dependencies;
}
function selectSkills(dotfilesRoot, profileLocal, external, exclude) {
    const localDir = path.join(dotfilesRoot, "skills", "local");
    const localNames = new Set(fs
        .readdirSync(localDir, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name));
    const excluded = new Set(exclude);
    const included = new Map();
    const dependencyCache = new Map();
    const dependenciesOf = (name) => {
        let dependencies = dependencyCache.get(name);
        if (!dependencies) {
            dependencies = skillDependencies(localDir, name, localNames);
            dependencyCache.set(name, dependencies);
        }
        return dependencies;
    };
    const queue = [];
    for (const name of profileLocal) {
        if (!excluded.has(name)) {
            included.set(name, { name, origin: "profile" });
            queue.push(name);
        }
    }
    const conflicts = [];
    while (queue.length > 0) {
        const name = queue.shift();
        for (const dependency of Array.from(dependenciesOf(name)).sort()) {
            if (excluded.has(dependency)) {
                conflicts.push(`${dependency} is required by ${name}`);
                continue;
            }
            const existing = included.get(dependency);
            if (!existing) {
                included.set(dependency, { name: dependency, origin: "dependency", requiredBy: [name] });
                queue.push(dependency);
            }
            else if (existing.origin === "dependency" && !existing.requiredBy?.includes(name)) {
                existing.requiredBy?.push(name);
            }
        }
    }
    if (conflicts.length > 0) {
        (0, skill_profiles_1.fail)(`cannot exclude a skill that a selected skill depends on: ${conflicts.sort().join("; ")}`);
    }
    const externalNames = new Set(external.flatMap((entry) => entry.skills));
    const unknown = exclude.filter((name) => !profileLocal.includes(name) && !externalNames.has(name)).sort();
    if (unknown.length > 0) {
        (0, skill_profiles_1.fail)(`--exclude names skills that the selected profiles do not include: ${unknown.join(", ")}`);
    }
    const keptExternal = external
        .map((entry) => ({ source: entry.source, skills: entry.skills.filter((name) => !excluded.has(name)) }))
        .filter((entry) => entry.skills.length > 0);
    const local = Array.from(included.values())
        .map((skill) => (skill.requiredBy ? { ...skill, requiredBy: skill.requiredBy.sort() } : skill))
        .sort((left, right) => left.name.localeCompare(right.name));
    return { local, external: keptExternal, excluded: Array.from(excluded).sort() };
}
// Mirrors ai-rules/scripts/compose-rules.sh without --with-metadata, in Node
// so setup.ps1 can export without Bash.
function composeRules(dotfilesRoot, overrideName) {
    const basePath = path.join(dotfilesRoot, "ai-rules", "base", "global.md");
    if (!fs.existsSync(basePath)) {
        (0, skill_profiles_1.fail)(`base rule file not found: ${basePath}`);
    }
    const docs = [fs.readFileSync(basePath, "utf8")];
    const overridePath = path.join(dotfilesRoot, "ai-rules", "agents", overrideName);
    if (fs.existsSync(overridePath)) {
        const override = fs.readFileSync(overridePath, "utf8");
        if (/\S/.test(override)) {
            docs.push(override);
        }
    }
    return `${docs.join("\n---\n\n")}\n`;
}
function copySkill(sourceDir, targetDir, name, files) {
    for (const relative of skillFiles(sourceDir, name)) {
        const source = path.join(sourceDir, relative);
        const target = path.join(targetDir, relative);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.copyFileSync(source, target);
        fs.chmodSync(target, fs.statSync(source).mode & 0o777);
        files.push(toPosix(path.join("skills", name, relative)));
    }
}
function readmeText(manifest, hasNodeScripts) {
    const lines = [];
    const agents = manifest.agents;
    const skillList = manifest.local.map((skill) => skill.origin === "dependency" ? `- \`${skill.name}\` (added because it is linked from ${skill.requiredBy?.map((name) => `\`${name}\``).join(", ")})` : `- \`${skill.name}\``);
    lines.push("# AI Skills Bundle", "", `Exported from the profiles ${manifest.requestedProfiles.map((name) => `\`${name}\``).join(", ")} for ${agents.map((agent) => `\`${agent}\``).join(" and ")}.`, `\`${exports.BUNDLE_MANIFEST}\` records what was selected and every file in this bundle.`, "", "## Local Skills", "", ...(skillList.length > 0 ? skillList : ["None."]), "");
    if (manifest.local.length > 0) {
        lines.push("Copy every directory under `skills/` into one agent skill directory, side by side.", "Skills link to each other relative to their own directory, such as", "`../delivery-common/scripts/check-branch-name.mjs`, so keep them together.", "");
        if (agents.includes("claude-code")) {
            lines.push("- Claude Code: `~/.claude/skills/` for every project, or `.claude/skills/` in one project.");
        }
        if (agents.includes("codex")) {
            lines.push("- Codex: `~/.agents/skills/` for every project, or `.agents/skills/` in one project.");
        }
        lines.push("");
    }
    lines.push("## Rules", "");
    if (agents.includes("claude-code")) {
        lines.push("- `CLAUDE.md` is for Claude Code: use it as `~/.claude/CLAUDE.md`, or merge it into a project's `CLAUDE.md`.");
    }
    if (agents.includes("codex")) {
        lines.push("- `AGENTS.md` is for Codex: use it as `~/.codex/AGENTS.md`, or merge it into a project's `AGENTS.md`.");
    }
    lines.push("", "Merge with your existing rules instead of overwriting them.", "");
    lines.push("## External Skills", "");
    if (manifest.external.length === 0) {
        lines.push("None.", "");
    }
    else {
        lines.push("These skills are not copied. Install them with the `skills` CLI from their sources; run each command in the", "project that should use them, and see `npx skills add --help` for other install locations.", "", "```sh");
        for (const entry of manifest.external) {
            const args = ["npx skills add", entry.source, ...entry.skills.map((name) => `--skill ${name}`), ...agents.map((agent) => `--agent ${agent}`)];
            lines.push(args.join(" "));
        }
        lines.push("```", "");
    }
    const reviewSkills = manifest.local.filter((skill) => /^change-.*review$/.test(skill.name)).map((skill) => skill.name);
    if (hasNodeScripts || reviewSkills.length > 0) {
        lines.push("## Prerequisites", "");
        if (hasNodeScripts) {
            lines.push("- Node.js: some skills run `.mjs` scripts from `scripts/` directories.");
        }
        if (reviewSkills.length > 0) {
            lines.push(`- Optional: the Codex plugin for Claude Code. ${reviewSkills.map((name) => `\`${name}\``).join(", ")} can route a review to Codex`, "  through the plugin's `scripts/codex-companion.mjs` when the user names Codex; without it, they review with the current agent.");
        }
        lines.push("");
    }
    return `${lines.join("\n").replace(/\n+$/, "")}\n`;
}
function gitConfig(dotfilesRoot, key, env) {
    const result = (0, node_child_process_1.spawnSync)("git", ["config", "--get", key], { cwd: dotfilesRoot, env, encoding: "utf8" });
    if (result.error || result.status !== 0) {
        return "";
    }
    return result.stdout.trim();
}
function markersFilePath(context) {
    const override = context.env[MARKERS_FILE_ENV];
    if (override) {
        return { file: path.resolve(override), required: true };
    }
    const xdg = context.env.XDG_CONFIG_HOME;
    const configHome = xdg && path.isAbsolute(xdg) ? xdg : path.join(context.home, ".config");
    return { file: path.join(configHome, "dotfiles", "export-personal-markers"), required: false };
}
function homeVariants(home) {
    const variants = new Set();
    const trimmed = home.replace(/[\\/]+$/, "");
    if (trimmed.length <= 2) {
        return [];
    }
    variants.add(trimmed);
    variants.add(trimmed.split("\\").join("/"));
    variants.add(trimmed.split("/").join("\\"));
    return Array.from(variants);
}
function personalMarkers(context) {
    const markers = [];
    for (const home of new Set([context.home, os.homedir()])) {
        for (const value of homeVariants(home)) {
            markers.push({ kind: "home path", value });
        }
    }
    for (const key of ["user.name", "user.email"]) {
        const value = gitConfig(context.dotfilesRoot, key, context.env);
        if (value) {
            markers.push({ kind: `git ${key}`, value });
        }
    }
    const { file, required } = markersFilePath(context);
    if (fs.existsSync(file)) {
        const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
        lines.forEach((line, index) => {
            const value = line.trim();
            if (value && !value.startsWith("#")) {
                markers.push({ kind: `personal marker on line ${index + 1} of the marker file`, value });
            }
        });
    }
    else if (required) {
        (0, skill_profiles_1.fail)(`${MARKERS_FILE_ENV} names a missing file: ${file}`);
    }
    return markers;
}
// Reports where markers occur without printing their values.
function checkPersonalData(stagingDir, files, markers) {
    const findings = [];
    const lowered = markers.map((marker) => ({ kind: marker.kind, value: marker.value.toLowerCase() }));
    for (const relative of files) {
        const text = `${relative}\n${fs.readFileSync(path.join(stagingDir, relative), "utf8")}`.toLowerCase();
        const kinds = new Set(lowered.filter((marker) => text.includes(marker.value)).map((marker) => marker.kind));
        for (const kind of Array.from(kinds).sort()) {
            findings.push(`${relative}: ${kind}`);
        }
    }
    if (findings.length > 0) {
        (0, skill_profiles_1.fail)(`personal data check failed; nothing was written:\n  ${findings.join("\n  ")}`);
    }
}
function listEntries(directory) {
    const files = [];
    const others = [];
    function walk(relativeDir) {
        for (const entry of fs.readdirSync(path.join(directory, relativeDir), { withFileTypes: true })) {
            const relative = toPosix(path.join(relativeDir, entry.name));
            if (entry.isDirectory()) {
                const before = files.length + others.length;
                walk(relative);
                if (files.length + others.length === before) {
                    others.push(`${relative}/`);
                }
            }
            else if (entry.isFile()) {
                files.push(relative);
            }
            else {
                others.push(relative);
            }
        }
    }
    walk("");
    return { files, others };
}
// --force replaces only a previous bundle: a directory whose manifest lists
// every file in it. Anything else is refused, even with --force, so export
// never deletes files it did not write.
function inspectOut(out, force) {
    let stat;
    try {
        stat = fs.lstatSync(out);
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return { kind: "absent" };
        }
        throw error;
    }
    if (stat.isSymbolicLink()) {
        (0, skill_profiles_1.fail)(`output path is a symbolic link: ${out}`);
    }
    if (!stat.isDirectory()) {
        (0, skill_profiles_1.fail)(`output path is not a directory: ${out}`);
    }
    if (fs.readdirSync(out).length === 0) {
        return { kind: "empty" };
    }
    if (!force) {
        (0, skill_profiles_1.fail)(`output directory is not empty: ${out} (use --force to replace a previous skills bundle)`);
    }
    const manifestPath = path.join(out, exports.BUNDLE_MANIFEST);
    let manifest;
    try {
        manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    }
    catch {
        (0, skill_profiles_1.fail)(`--force replaces only a previous skills bundle, and ${out} has no readable ${exports.BUNDLE_MANIFEST}`);
    }
    const record = manifest;
    if (!record || record.generatedBy !== GENERATED_BY || !Array.isArray(record.files) || !record.files.every((file) => typeof file === "string")) {
        (0, skill_profiles_1.fail)(`--force replaces only a previous skills bundle, and ${exports.BUNDLE_MANIFEST} in ${out} is not one`);
    }
    const listed = new Set(record.files);
    const { files, others } = listEntries(out);
    const extras = files.filter((file) => !listed.has(file)).concat(others).sort();
    if (extras.length > 0) {
        (0, skill_profiles_1.fail)(`refusing to replace ${out}: entries not written by skills export: ${extras.join(", ")}`);
    }
    return { kind: "bundle" };
}
function uniqueSibling(out, label) {
    return path.join(path.dirname(out), `.${path.basename(out)}.${label}-${process.pid}-${Date.now()}`);
}
function install(staging, out, state) {
    if (state.kind === "empty") {
        fs.rmdirSync(out);
    }
    if (state.kind !== "bundle") {
        fs.renameSync(staging, out);
        return;
    }
    const previous = uniqueSibling(out, "previous");
    fs.renameSync(out, previous);
    try {
        fs.renameSync(staging, out);
    }
    catch (error) {
        fs.renameSync(previous, out);
        throw error;
    }
    fs.rmSync(previous, { recursive: true, force: true });
}
function exportSkills(options, context) {
    const out = path.resolve(options.out);
    if (isInsideOrSame(out, context.dotfilesRoot) || isInsideOrSame(context.dotfilesRoot, out)) {
        (0, skill_profiles_1.fail)(`output directory must be outside the dotfiles repository: ${out}`);
    }
    const plan = (0, skill_profiles_1.resolveProfiles)(context.dotfilesRoot, options.profiles, options.agents, "export");
    const selection = selectSkills(context.dotfilesRoot, plan.local.map((skill) => skill.name), plan.external, options.exclude);
    const state = inspectOut(out, options.force);
    const rules = RULES_TARGETS.filter((target) => options.agents.includes(target.agent));
    const dependencies = selection.local.filter((skill) => skill.origin === "dependency");
    console.log(`Local skills: ${selection.local.map((skill) => skill.name).join(", ") || "none"}`);
    for (const skill of dependencies) {
        console.log(`Added as a dependency: ${skill.name} (required by ${skill.requiredBy?.join(", ")})`);
    }
    if (selection.excluded.length > 0) {
        console.log(`Excluded: ${selection.excluded.join(", ")}`);
    }
    console.log(`External skills recorded: ${selection.external.flatMap((entry) => entry.skills).length}`);
    if (context.dryRun) {
        console.log(`DRY-RUN write skills bundle ${out}`);
        return;
    }
    // Check markers before writing so a bad override fails without staging.
    const markers = personalMarkers(context);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const staging = fs.mkdtempSync(path.join(path.dirname(out), `.${path.basename(out)}.staging-`));
    try {
        const files = [];
        const localDir = path.join(context.dotfilesRoot, "skills", "local");
        for (const skill of selection.local) {
            copySkill(path.join(localDir, skill.name), path.join(staging, "skills", skill.name), skill.name, files);
        }
        for (const target of rules) {
            fs.writeFileSync(path.join(staging, target.file), composeRules(context.dotfilesRoot, target.override));
            files.push(target.file);
        }
        files.push("README.md", exports.BUNDLE_MANIFEST);
        files.sort();
        const manifest = {
            schemaVersion: SCHEMA_VERSION,
            generatedBy: GENERATED_BY,
            requestedProfiles: plan.requestedProfiles,
            expandedProfiles: plan.expandedProfiles,
            agents: options.agents,
            local: selection.local,
            excluded: selection.excluded,
            external: selection.external,
            rules: rules.map((target) => target.file),
            files,
        };
        const hasNodeScripts = files.some((file) => /^skills\/[^/]+\/scripts\/.+\.mjs$/.test(file));
        fs.writeFileSync(path.join(staging, "README.md"), readmeText(manifest, hasNodeScripts));
        fs.writeFileSync(path.join(staging, exports.BUNDLE_MANIFEST), `${JSON.stringify(manifest, null, 2)}\n`);
        checkPersonalData(staging, files, markers);
        fs.chmodSync(staging, 0o777 & ~process.umask());
        install(staging, out, state);
    }
    catch (error) {
        fs.rmSync(staging, { recursive: true, force: true });
        throw error;
    }
    console.log(`Skills bundle written: ${out}`);
}
