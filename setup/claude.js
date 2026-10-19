"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const node_util_1 = require("node:util");
function entry(file) {
    try {
        return fs.lstatSync(file);
    }
    catch (error) {
        if (error.code === "ENOENT")
            return undefined;
        throw error;
    }
}
function directory(file, label) {
    const stat = entry(file);
    if (stat && (!stat.isDirectory() || stat.isSymbolicLink())) {
        throw new Error(`Refusing a symlink or unexpected ${label}`);
    }
}
function readOptional(file, label) {
    const stat = entry(file);
    if (!stat)
        return undefined;
    if (!stat.isFile() || stat.isSymbolicLink())
        throw new Error(`Expected an independent file: ${label}`);
    return fs.readFileSync(file, "utf8");
}
function table(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}
function readSettings(text, label) {
    try {
        const value = JSON.parse(text ?? "");
        if (!table(value))
            throw new Error();
        return value;
    }
    catch {
        throw new Error(`Missing or invalid JSON object: ${label}`);
    }
}
function mergeSettings(previous, current, desired, key = "settings.json", legacy = false) {
    if ((0, node_util_1.isDeepStrictEqual)(current, previous))
        return desired;
    if ((0, node_util_1.isDeepStrictEqual)(previous, desired) || (0, node_util_1.isDeepStrictEqual)(current, desired))
        return current;
    if (table(current) && table(desired) && (previous === undefined || table(previous))) {
        const old = previous ?? {};
        const entries = [];
        for (const name of new Set([...Object.keys(old), ...Object.keys(current), ...Object.keys(desired)])) {
            const value = mergeSettings(old[name], current[name], desired[name], `${key}.${name}`, legacy);
            if (value !== undefined)
                entries.push([name, value]);
        }
        return Object.fromEntries(entries);
    }
    // Old homes recorded no source baseline. Treat their differences from the
    // former minimal template as local choices on this first migration only.
    if (legacy)
        return current;
    throw new Error(`Conflicting local and dotfiles changes: ${key}`);
}
function sharedSkills(dotfiles, required) {
    const root = path.join(dotfiles, ".agents/user/skills");
    const names = fs.existsSync(root) ? fs.readdirSync(root).sort() : [];
    const valid = (name) => /^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(name) && !/^(synced|anthropic-skills)$/i.test(name);
    const installed = (name) => {
        const file = path.join(root, name, "SKILL.md");
        return fs.existsSync(file) && fs.statSync(file).isFile();
    };
    for (const name of required) {
        if (!valid(name))
            throw new Error(`Invalid or reserved skill name: ${name}`);
        if (!installed(name))
            throw new Error(`Installed skill not found: ${name}`);
    }
    return names.filter(name => valid(name) && installed(name))
        .map(name => ({ name: `skills/${name}`, source: path.join(root, name), directory: true }));
}
function applyChanges(root, destination, existing, links, changes, guards) {
    const createdLinks = [];
    const createdDirectories = [];
    const applied = [];
    let stage;
    let backup;
    let complete = false;
    let keepStage = false;
    const mkdir = (file) => {
        if (!entry(file)) {
            fs.mkdirSync(file, { mode: 0o700 });
            createdDirectories.push(file);
        }
        else
            directory(file, "environment directory");
    };
    const checkFiles = () => {
        directory(root, "Claude environment directory");
        directory(destination, "Claude environment home");
        for (const name of ["rules", "skills"])
            directory(path.join(destination, name), `${name} directory`);
        for (const guard of guards) {
            const expected = applied.find(change => change.name === guard.name)?.after ?? guard.before;
            if (readOptional(path.join(destination, guard.name), guard.name) !== expected) {
                throw new Error(`Target changed during generation: ${guard.name}`);
            }
        }
    };
    try {
        fs.mkdirSync(path.dirname(root), { recursive: true });
        mkdir(root);
        if (!existing) {
            // Never adopt a home created by another invocation after preflight.
            fs.mkdirSync(destination, { mode: 0o700 });
            createdDirectories.push(destination);
        }
        else
            directory(destination, "Claude environment home");
        mkdir(path.join(destination, "rules"));
        mkdir(path.join(destination, "skills"));
        stage = fs.mkdtempSync(path.join(destination, ".dotfiles-claude-stage-"));
        for (let i = 0; i < changes.length; i++) {
            fs.writeFileSync(path.join(stage, `${i}.new`), changes[i].after, { flag: "wx", mode: 0o600 });
        }
        checkFiles();
        if (changes.some(change => change.before !== undefined)) {
            const backups = path.join(destination, ".dotfiles-claude-backups");
            directory(backups, "backup directory");
            fs.mkdirSync(backups, { recursive: true, mode: 0o700 });
            backup = fs.mkdtempSync(path.join(backups, "update-"));
            for (const change of changes) {
                if (change.before !== undefined)
                    fs.writeFileSync(path.join(backup, change.name), change.before, { flag: "wx", mode: 0o600 });
            }
        }
        for (const link of links) {
            const target = path.join(destination, link.name);
            try {
                fs.symlinkSync(link.source, target, link.directory ? "dir" : "file");
            }
            catch (error) {
                if (["EPERM", "EACCES"].includes(error.code || "")) {
                    throw new Error("Cannot create a shared-file symlink. On Windows, enable Developer Mode or use an appropriately privileged terminal for setup.");
                }
                throw error;
            }
            createdLinks.push({ file: target, stat: fs.lstatSync(target) });
        }
        checkFiles();
        for (let i = 0; i < changes.length; i++) {
            checkFiles();
            fs.renameSync(path.join(stage, `${i}.new`), path.join(destination, changes[i].name));
            applied.push(changes[i]);
        }
        complete = true;
    }
    catch (error) {
        try {
            for (const change of applied.reverse()) {
                const target = path.join(destination, change.name);
                if (readOptional(target, change.name) !== change.after) {
                    throw new Error(`Rollback stopped because a target changed: ${change.name}. Recovery files: ${backup ?? stage}`);
                }
                if (change.before === undefined)
                    fs.unlinkSync(target);
                else {
                    const restore = path.join(stage, "restore");
                    fs.writeFileSync(restore, change.before, { mode: 0o600 });
                    fs.renameSync(restore, target);
                }
            }
        }
        catch (restoreError) {
            keepStage = true;
            throw restoreError;
        }
        throw error;
    }
    finally {
        if (!complete) {
            for (const { file, stat } of createdLinks.reverse()) {
                const current = entry(file);
                if (current?.dev === stat.dev && current.ino === stat.ino)
                    fs.unlinkSync(file);
            }
        }
        if (stage && !keepStage) {
            for (const file of fs.readdirSync(stage))
                fs.unlinkSync(path.join(stage, file));
            fs.rmdirSync(stage);
        }
        if (!complete) {
            for (const file of createdDirectories.reverse()) {
                try {
                    fs.rmdirSync(file);
                }
                catch { /* Keep concurrent additions and backups. */ }
            }
        }
    }
    if (backup)
        console.log(`Previous settings backed up in ${backup}`);
}
function main() {
    let env = "";
    let dryRun = process.env.SETUP_DRY_RUN === "1";
    const skills = new Set();
    const args = process.argv.slice(2);
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === "--help" || arg === "-h") {
            console.log(`Usage: setup claude --env NAME [--dry-run]

Create or refresh a named Claude Code environment without login or launch.
Generate settings from claude/settings.json; preserve independent local edits.
Conflicting edits stop before writes. Previous settings are backed up on refresh.
All installed dotfiles user skills, shared rules and statusline use symlinks.
Legacy --skill NAME validates that a skill is installed; it does not filter sharing.
The default environment keeps using setup links.
Names: 1-64 lowercase letters, digits, hyphens, underscores; start with a letter.`);
            return;
        }
        if (arg === "--dry-run") {
            dryRun = true;
            continue;
        }
        if (arg === "--env" || arg === "--skill" || arg.startsWith("--env=")) {
            const value = arg.startsWith("--env=") ? arg.slice(6) : args[++i];
            if (!value || value.startsWith("-"))
                throw new Error(`${arg.split("=")[0]} requires a value`);
            if (arg === "--skill")
                skills.add(value);
            else {
                if (env && env !== value)
                    throw new Error("Environment specified twice with different names");
                env = value;
            }
        }
        else
            throw new Error(`Unknown Claude setup argument: ${arg}`);
    }
    if (!env)
        throw new Error("Claude setup requires --env NAME");
    if (env === "default")
        throw new Error("The default environment uses setup links; choose a separate --env NAME");
    if (!/^[a-z][a-z0-9_-]{0,63}$/.test(env) || /^(con|prn|aux|nul|com[0-9]|lpt[0-9])$/.test(env)) {
        throw new Error(`Invalid or reserved environment name: ${env}`);
    }
    if (process.env.SETUP_DRY_RUN && !["0", "1"].includes(process.env.SETUP_DRY_RUN)) {
        throw new Error("SETUP_DRY_RUN must be 0 or 1");
    }
    const home = path.resolve(process.env.SETUP_HOME || os.homedir());
    const dotfiles = path.resolve(process.env.SETUP_DOTFILES_ROOT || path.join(__dirname, ".."));
    const root = path.join(home, ".claude-profiles");
    const destination = path.join(root, env);
    directory(root, "Claude environment directory");
    directory(destination, "Claude environment home");
    const existing = entry(destination) !== undefined;
    const markerBefore = readOptional(path.join(destination, ".claude-pick"), ".claude-pick");
    const settingsBefore = readOptional(path.join(destination, "settings.json"), "settings.json");
    const baselineBefore = readOptional(path.join(destination, ".dotfiles-env.json"), ".dotfiles-env.json");
    if (existing) {
        if (markerBefore?.replace(/[\r\n]+$/, "") !== "1") {
            throw new Error(`Environment missing or incomplete: ${env}; refusing to adopt existing files`);
        }
        if (settingsBefore === undefined)
            throw new Error("Expected an independent settings.json file");
    }
    for (const name of ["rules", "skills"])
        directory(path.join(destination, name), `${name} directory`);
    directory(path.join(destination, ".dotfiles-claude-backups"), "backup directory");
    const source = readSettings(readOptional(path.join(dotfiles, "claude/settings.json"), "claude/settings.json"), "claude/settings.json");
    let settings = source;
    if (settingsBefore !== undefined) {
        const current = readSettings(settingsBefore, "settings.json");
        let previous;
        if (baselineBefore !== undefined) {
            const baseline = readSettings(baselineBefore, ".dotfiles-env.json");
            if (baseline.version !== 1 || baseline.env !== env || !table(baseline.settings))
                throw new Error("Invalid Claude environment baseline");
            previous = baseline.settings;
        }
        else {
            previous = readSettings(readOptional(path.join(dotfiles, "claude/profile-settings.json"), "claude/profile-settings.json"), "claude/profile-settings.json");
        }
        settings = mergeSettings(previous, current, source, "settings.json", baselineBefore === undefined);
    }
    const settingsAfter = settingsBefore !== undefined && (0, node_util_1.isDeepStrictEqual)(settings, readSettings(settingsBefore, "settings.json"))
        ? settingsBefore : JSON.stringify(settings, null, 2) + "\n";
    const baseline = { version: 1, env, settings: source };
    const baselineAfter = baselineBefore !== undefined && (0, node_util_1.isDeepStrictEqual)(readSettings(baselineBefore, ".dotfiles-env.json"), baseline)
        ? baselineBefore : JSON.stringify(baseline, null, 2) + "\n";
    const guards = [
        { name: "settings.json", before: settingsBefore },
        { name: ".dotfiles-env.json", before: baselineBefore },
        { name: ".claude-pick", before: markerBefore },
    ];
    const changes = [
        { ...guards[0], after: settingsAfter },
        { ...guards[1], after: baselineAfter },
        ...(!existing ? [{ ...guards[2], after: "1\n" }] : []),
    ].filter(change => change.before !== change.after);
    const candidates = [
        { name: "statusline.cjs", source: path.join(dotfiles, "claude/statusline.cjs") },
        { name: "rules/00-global.md", source: path.join(dotfiles, "ai-rules/base/global.md") },
        { name: "rules/10-claude.md", source: path.join(dotfiles, "ai-rules/agents/claude.md") },
        ...sharedSkills(dotfiles, skills),
    ];
    const links = [];
    for (const link of candidates) {
        if (!fs.existsSync(link.source) || !(link.directory ? fs.statSync(link.source).isDirectory() : fs.statSync(link.source).isFile())) {
            throw new Error(`Missing shared file for ${link.name}`);
        }
        const target = path.join(destination, link.name);
        const stat = entry(target);
        if (stat) {
            if (!stat.isSymbolicLink() || path.resolve(path.dirname(target), fs.readlinkSync(target)) !== link.source) {
                throw new Error(`Refusing to replace an existing entry: ${link.name}`);
            }
        }
        else
            links.push(link);
    }
    if (dryRun) {
        console.log(`Would ${existing ? "refresh" : "create"} environment: ${env}`);
        for (const change of changes)
            console.log(`  ${change.before === undefined ? "Create" : "Update"} ${change.name}`);
        for (const link of links)
            console.log(`  Link ${link.name}`);
        return;
    }
    if (changes.length || links.length)
        applyChanges(root, destination, existing, links, changes, guards);
    console.log(`${existing ? (changes.length || links.length ? "Refreshed" : "Unchanged") : "Created"} environment: ${env}`);
}
try {
    main();
}
catch (error) {
    console.error(`Claude setup: ${error.message}`);
    process.exitCode = 2;
}
