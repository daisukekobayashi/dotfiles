"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
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
function main() {
    let env = "";
    let dryRun = process.env.SETUP_DRY_RUN === "1";
    const skills = new Set();
    const args = process.argv.slice(2);
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === "--help" || arg === "-h") {
            console.log(`Usage: setup claude --env NAME [--skill NAME ...] [--dry-run]

Create or refresh a named Claude Code environment without login or launch.
Settings are copied only on creation; later runs preserve local settings and state.
Shared rules, statusline and selected installed skills use dotfiles symlinks.
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
    if (existing) {
        const marker = path.join(destination, ".claude-pick");
        const stat = entry(marker);
        if (!stat?.isFile() || stat.isSymbolicLink() || fs.readFileSync(marker, "utf8").replace(/[\r\n]+$/, "") !== "1") {
            throw new Error(`Environment missing or incomplete: ${env}; refusing to adopt existing files`);
        }
        const settings = entry(path.join(destination, "settings.json"));
        if (!settings?.isFile() || settings.isSymbolicLink())
            throw new Error("Expected an independent settings.json file");
    }
    for (const name of ["rules", "skills"])
        directory(path.join(destination, name), `${name} directory`);
    const links = [
        { name: "statusline.cjs", source: path.join(dotfiles, "claude/statusline.cjs") },
        { name: "rules/00-global.md", source: path.join(dotfiles, "ai-rules/base/global.md") },
        { name: "rules/10-claude.md", source: path.join(dotfiles, "ai-rules/agents/claude.md") },
    ];
    for (const skill of skills) {
        if (!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(skill))
            throw new Error(`Invalid skill name: ${skill}`);
        const source = path.join(dotfiles, ".agents/user/skills", skill);
        if (!fs.existsSync(path.join(source, "SKILL.md")))
            throw new Error(`Installed skill not found: ${skill}`);
        links.push({ name: `skills/${skill}`, source, directory: true });
    }
    const changes = [];
    for (const link of links) {
        if (!fs.existsSync(link.source))
            throw new Error(`Missing shared file for ${link.name}`);
        const target = path.join(destination, link.name);
        const stat = entry(target);
        if (stat) {
            if (!stat.isSymbolicLink() || path.resolve(path.dirname(target), fs.readlinkSync(target)) !== link.source) {
                throw new Error(`Refusing to replace an existing entry: ${link.name}`);
            }
        }
        else
            changes.push(link);
    }
    if (!existing) {
        let content;
        try {
            content = fs.readFileSync(path.join(dotfiles, "claude/profile-settings.json"), "utf8");
            const settings = JSON.parse(content);
            if (!settings || typeof settings !== "object" || Array.isArray(settings))
                throw new Error();
        }
        catch {
            throw new Error("Missing or invalid claude/profile-settings.json");
        }
        changes.unshift({ name: "settings.json", content });
        // Keep the launcher's existing readiness marker, written only after all assets.
        changes.push({ name: ".claude-pick", content: "1\n" });
    }
    if (dryRun) {
        console.log(`Would ${existing ? "refresh" : "create"} environment: ${env}`);
        for (const change of changes)
            console.log(`  ${change.source ? "Link" : "Create"} ${change.name}`);
        return;
    }
    const createdFiles = [];
    const createdDirectories = [];
    const mkdir = (file) => {
        if (!entry(file)) {
            fs.mkdirSync(file, { mode: 0o700 });
            createdDirectories.push(file);
        }
        else
            directory(file, "environment directory");
    };
    try {
        fs.mkdirSync(home, { recursive: true });
        mkdir(root);
        if (!existing) {
            // No recursive mkdir: never adopt a home created by another invocation.
            fs.mkdirSync(destination, { mode: 0o700 });
            createdDirectories.push(destination);
        }
        else
            directory(destination, "Claude environment home");
        mkdir(path.join(destination, "rules"));
        mkdir(path.join(destination, "skills"));
        for (const change of changes) {
            const target = path.join(destination, change.name);
            if (change.source) {
                try {
                    fs.symlinkSync(change.source, target, change.directory ? "dir" : "file");
                }
                catch (error) {
                    if (["EPERM", "EACCES"].includes(error.code || "")) {
                        throw new Error("Cannot create a shared-file symlink. On Windows, enable Developer Mode or use an appropriately privileged terminal for setup.");
                    }
                    throw error;
                }
                createdFiles.push({ file: target, stat: fs.lstatSync(target) });
            }
            else {
                const fd = fs.openSync(target, "wx", 0o600);
                createdFiles.push({ file: target, stat: fs.fstatSync(fd) });
                try {
                    fs.writeFileSync(fd, change.content);
                }
                finally {
                    fs.closeSync(fd);
                }
            }
        }
    }
    catch (error) {
        for (const { file, stat } of createdFiles.reverse()) {
            const current = entry(file);
            if (current?.dev === stat.dev && current.ino === stat.ino)
                fs.unlinkSync(file);
        }
        for (const file of createdDirectories.reverse()) {
            try {
                fs.rmdirSync(file);
            }
            catch { /* Keep any concurrent additions. */ }
        }
        throw error;
    }
    console.log(`${existing ? (changes.length ? "Refreshed" : "Unchanged") : "Created"} environment: ${env}`);
}
try {
    main();
}
catch (error) {
    console.error(`Claude setup: ${error.message}`);
    process.exitCode = 2;
}
