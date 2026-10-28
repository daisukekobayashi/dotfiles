"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.copyMarker = copyMarker;
exports.snapshot = snapshot;
exports.sameSnapshot = sameSnapshot;
exports.planSharedLink = planSharedLink;
exports.copyMetadata = copyMetadata;
exports.stageSharedLinks = stageSharedLinks;
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const node_crypto_1 = require("node:crypto");
const node_child_process_1 = require("node:child_process");
function copyMarker(name) {
    return path.join(path.dirname(name), `.dotfiles-copy-${path.basename(name)}.json`);
}
// Content fingerprints include empty directories and binary supporting files.
// Only source trees may contain symlinks; an installed copy must be independent.
function snapshot(file, source = false) {
    if (!fs.lstatSync(file, { throwIfNoEntry: false }))
        return undefined;
    const result = Object.create(null);
    const visit = (current, name, ancestors) => {
        const stat = fs.lstatSync(current);
        if (stat.isSymbolicLink() && !source)
            throw new Error(`Unexpected link in shared copy: ${name}`);
        const real = fs.realpathSync(current);
        if (ancestors.has(real))
            throw new Error(`Cyclic shared source: ${name}`);
        if (fs.statSync(current).isDirectory()) {
            result[name] = "directory";
            const next = new Set([...ancestors, real]);
            for (const child of fs.readdirSync(current).sort())
                visit(path.join(current, child), name === "." ? child : `${name}/${child}`, next);
        }
        else if (fs.statSync(current).isFile()) {
            result[name] = (0, node_crypto_1.createHash)("sha256").update(fs.readFileSync(current)).digest("hex");
        }
        else
            throw new Error(`Unexpected shared entry: ${name}`);
    };
    visit(file, ".", new Set());
    return result;
}
function sameSnapshot(a, b) {
    if (!a || !b)
        return a === b;
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every(key => a[key] === b[key]);
}
function planSharedLink(destination, link) {
    const target = path.join(destination, link.name);
    const stat = fs.lstatSync(target, { throwIfNoEntry: false });
    const marker = path.join(destination, copyMarker(link.name));
    const markerStat = fs.lstatSync(marker, { throwIfNoEntry: false });
    if (markerStat && (!markerStat.isFile() || markerStat.isSymbolicLink()))
        throw new Error(`Invalid copy marker: ${link.name}`);
    const markerBefore = markerStat ? fs.readFileSync(marker, "utf8") : undefined;
    if (!stat && !markerBefore)
        return { ...link };
    if (stat?.isSymbolicLink() && path.resolve(path.dirname(target), fs.readlinkSync(target)) === link.source)
        return undefined;
    if (stat?.isSymbolicLink() || !markerBefore)
        throw new Error(`Refusing to replace an existing entry: ${link.name}`);
    let saved;
    try {
        saved = JSON.parse(markerBefore);
    }
    catch {
        throw new Error(`Invalid copy marker: ${link.name}`);
    }
    if (!saved || saved.version !== 1 || saved.source !== link.source || !saved.files || typeof saved.files !== "object" || Array.isArray(saved.files) ||
        !Object.hasOwn(saved.files, ".") || Object.values(saved.files).some(value => value !== "directory" && (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)))) {
        throw new Error(`Invalid copy marker: ${link.name}`);
    }
    if (!stat)
        return { ...link, markerBefore, copy: true };
    const before = snapshot(target);
    const desired = snapshot(link.source, true);
    // Local-only edits survive. A changed source may replace only an unchanged
    // managed copy (or a copy already identical to the new source).
    if (sameSnapshot(saved.files, desired))
        return undefined;
    if (!sameSnapshot(before, saved.files) && !sameSnapshot(before, desired)) {
        throw new Error(`Conflicting local and dotfiles changes: ${link.name}`);
    }
    return { ...link, before, markerBefore, copy: true };
}
function copyMetadata(source, files) {
    return JSON.stringify({ version: 1, source, files }, null, 2) + "\n";
}
// All targets belong to caller-owned staging directories. A single Windows
// helper elevates only this link batch, never the Node runtime or its secrets.
function stageSharedLinks(links, copyWithoutElevation = false) {
    const pending = [];
    for (const link of links) {
        fs.mkdirSync(path.dirname(link.target), { recursive: true });
        if (link.copy) {
            fs.cpSync(link.source, link.target, { recursive: true, dereference: true, errorOnExist: true, force: false });
            continue;
        }
        try {
            fs.symlinkSync(link.source, link.target, link.directory ? "dir" : "file");
        }
        catch (error) {
            if (error.code !== "EPERM")
                throw error;
            if (process.platform === "win32")
                pending.push(link);
            else if (copyWithoutElevation)
                fs.cpSync(link.source, link.target, { recursive: true, dereference: true, errorOnExist: true, force: false });
            else
                throw error;
        }
    }
    if (!pending.length)
        return;
    const work = fs.mkdtempSync(path.join(os.tmpdir(), "dotfiles-links-"));
    try {
        const plan = path.join(work, "links.json");
        fs.writeFileSync(plan, JSON.stringify(pending.map(link => ({ Link: link.target, Target: link.source }))));
        const result = (0, node_child_process_1.spawnSync)(process.env.SETUP_POWERSHELL_PATH || "powershell.exe", [
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.resolve(__dirname, "../lib/windows-links.ps1"), "-PlanPath", plan,
        ], { encoding: "utf8", windowsHide: true });
        if (result.stdout)
            process.stdout.write(result.stdout);
        if (result.error)
            throw result.error;
        if (result.status !== 0)
            throw new Error(`Windows link setup failed: ${result.stderr || result.stdout}`);
    }
    finally {
        fs.rmSync(work, { recursive: true, force: true });
    }
}
