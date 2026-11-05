"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isLocalAbsoluteTemp = isLocalAbsoluteTemp;
exports.localRealPath = localRealPath;
exports.privateSkillsBase = privateSkillsBase;
exports.isInsideOrSame = isInsideOrSame;
exports.userPrivateGid = userPrivateGid;
exports.ancestorProblem = ancestorProblem;
exports.planPrivateDir = planPrivateDir;
exports.createPrivateDirs = createPrivateDirs;
const fs = require("node:fs");
const path = require("node:path");
// Windows TEMP must name a local drive: X:\... or \\?\X:\.... A UNC share, a
// device path, or a path rooted on the current drive (\Temp) is refused
// because Windows gets no ownership check and a share's access is unknown.
// With a POSIX path API, which the Windows tests use on POSIX, any absolute
// path is accepted.
function isLocalAbsoluteTemp(value, api) {
    if (!api.isAbsolute(value)) {
        return false;
    }
    if (api.sep !== "\\") {
        return true;
    }
    return /^[A-Za-z]:[\\/]/.test(value) || /^\\\\\?\\[A-Za-z]:\\/.test(value);
}
// Resolves an existing directory to its real path. On Windows, a drive letter
// mapped to a network share resolves to a UNC path, so the resolved path must
// name a local drive too; a subst drive that resolves locally stays accepted.
function localRealPath(directory, realpath, api, platform) {
    const real = realpath(directory);
    if (platform === "win32" && !isLocalAbsoluteTemp(real, api)) {
        throw new Error(`cannot find a private skills directory: set TEMP to an absolute per-user directory (${directory} resolves to ${real})`);
    }
    return real;
}
function privateSkillsBase(env, platform, api, tmpdir, homedir) {
    if (platform === "win32") {
        const temp = env.TEMP || env.TMP;
        if (!temp || !isLocalAbsoluteTemp(temp, api)) {
            throw new Error("cannot find a private skills directory: set TEMP to an absolute per-user directory");
        }
        return temp;
    }
    if (platform === "darwin") {
        const temp = tmpdir();
        if (!api.isAbsolute(temp)) {
            throw new Error("cannot find a private skills directory: set TMPDIR to an absolute per-user directory");
        }
        return temp;
    }
    if (env.XDG_CACHE_HOME && api.isAbsolute(env.XDG_CACHE_HOME)) {
        return env.XDG_CACHE_HOME;
    }
    const home = env.SETUP_HOME || env.HOME || homedir();
    if (!api.isAbsolute(home)) {
        throw new Error("cannot find a private skills directory: set HOME or XDG_CACHE_HOME to an absolute path");
    }
    return api.join(home, ".cache");
}
// Windows paths compare without regard to case.
function isInsideOrSame(candidate, root, api, platform) {
    const fold = (value) => (platform === "win32" ? value.toLowerCase() : value);
    const child = fold(candidate);
    const parent = fold(root);
    return child === parent || child.startsWith(parent.endsWith(api.sep) ? parent : parent + api.sep);
}
function parseColonFile(text, fields) {
    const rows = [];
    for (const line of text.split(/\r?\n/)) {
        if (line === "" || line.startsWith("#")) {
            continue;
        }
        // NIS compat entries (+ or -) pull in data this file does not show.
        if (line.startsWith("+") || line.startsWith("-")) {
            return undefined;
        }
        const row = line.split(":");
        if (row.length < fields) {
            return undefined;
        }
        rows.push(row);
    }
    return rows;
}
function parseId(value) {
    return /^\d+$/.test(value) ? Number(value) : undefined;
}
function parsePasswd(text) {
    const rows = parseColonFile(text, 7);
    if (!rows)
        return undefined;
    const entries = [];
    for (const row of rows) {
        const uid = parseId(row[2]);
        const gid = parseId(row[3]);
        if (uid === undefined || gid === undefined)
            return undefined;
        entries.push({ name: row[0], uid, gid });
    }
    return entries;
}
function parseGroup(text) {
    const rows = parseColonFile(text, 4);
    if (!rows)
        return undefined;
    const entries = [];
    for (const row of rows) {
        const gid = parseId(row[2]);
        if (gid === undefined)
            return undefined;
        entries.push({ name: row[0], gid, members: row[3] === "" ? [] : row[3].split(",") });
    }
    return entries;
}
// Returns gid when it is the user-private group of uid according to the local
// passwd and group files: the user's primary group, named after the user, with
// no listed members and no other user's primary group. Returns undefined when
// that cannot be shown, including on macOS, where Directory Services, not
// these files, is authoritative and the primary group staff is shared.
function userPrivateGid(uid, gid, platform, passwdText, groupText) {
    if (platform === "darwin" || passwdText === undefined || groupText === undefined) {
        return undefined;
    }
    const users = parsePasswd(passwdText);
    const groups = parseGroup(groupText);
    if (!users || !groups) {
        return undefined;
    }
    const self = users.filter((user) => user.uid === uid);
    if (self.length !== 1 || self[0].gid !== gid) {
        return undefined;
    }
    if (users.some((user) => user.gid === gid && user !== self[0])) {
        return undefined;
    }
    const group = groups.filter((entry) => entry.gid === gid);
    if (group.length !== 1 || group[0].name !== self[0].name || group[0].members.length !== 0) {
        return undefined;
    }
    return gid;
}
// Describes why a directory on the path to the private base is unsafe, or
// returns undefined. Root may own a directory; nobody but the owner and,
// for a directory the user owns, the user's private group may write to it.
// A sticky bit does not exempt a directory.
function ancestorProblem(stat, owner) {
    if ((stat.uid !== owner.uid && stat.uid !== 0) || (stat.mode & 0o002) !== 0) {
        return "owner";
    }
    if ((stat.mode & 0o020) !== 0 && !(stat.uid === owner.uid && owner.privateGid !== undefined && stat.gid === owner.privateGid)) {
        return "group";
    }
    return undefined;
}
function readOptional(file) {
    try {
        return fs.readFileSync(file, "utf8");
    }
    catch {
        return undefined;
    }
}
let cachedOwner;
function currentOwner() {
    if (!cachedOwner) {
        const uid = process.getuid();
        const gid = process.getgid();
        cachedOwner = {
            uid,
            privateGid: userPrivateGid(uid, gid, process.platform, readOptional("/etc/passwd"), readOptional("/etc/group")),
        };
    }
    return cachedOwner;
}
const REMEDY = "set XDG_CACHE_HOME (Linux) or TMPDIR (macOS) to a private directory";
// Checks a directory before anything is created: resolves its nearest existing
// ancestor, refuses a would-be path inside the project, and checks that
// ancestor and every directory above it. Creates nothing.
function planPrivateDir(directory, label, projectRoot) {
    if (!path.isAbsolute(directory)) {
        throw new Error(`cannot keep ${label} under ${directory}: the path must be absolute`);
    }
    const missing = [];
    let existing = path.resolve(directory);
    while (!fs.lstatSync(existing, { throwIfNoEntry: false })) {
        const parent = path.dirname(existing);
        if (parent === existing) {
            throw new Error(`cannot keep ${label} under ${directory}: no part of the path exists`);
        }
        missing.unshift(path.basename(existing));
        existing = parent;
    }
    const realExisting = localRealPath(existing, fs.realpathSync.native, path, process.platform);
    if (!fs.statSync(realExisting).isDirectory()) {
        throw new Error(`cannot keep ${label} under ${directory}: ${realExisting} is not a directory`);
    }
    const real = path.join(realExisting, ...missing);
    if (projectRoot !== undefined && isInsideOrSame(real, fs.realpathSync.native(projectRoot), path, process.platform)) {
        throw new Error(`cannot keep ${label} inside the project: ${real}`);
    }
    if (process.platform === "win32" || typeof process.getuid !== "function") {
        return { real, label };
    }
    const owner = currentOwner();
    for (let current = realExisting;; current = path.dirname(current)) {
        const stat = fs.statSync(current);
        const problem = ancestorProblem(stat, owner);
        if (problem === "owner") {
            throw new Error(`cannot keep ${label} under ${real}: ${current} must be owned by you or root and not writable by others; ${REMEDY}`);
        }
        if (problem === "group") {
            throw new Error(`cannot keep ${label} under ${real}: ${current} is writable by group ${stat.gid}, which is not your private group; ` +
                `run chmod g-w ${current} or ${REMEDY}`);
        }
        if (path.dirname(current) === current) {
            return { real, label };
        }
    }
}
// Creates planned directories, mode 0700 on POSIX, then checks each again.
// When a check fails, removes the directories this call created, so a refusal
// leaves no new directory behind.
// mkdir is injectable so tests can simulate another run creating a directory
// between the plan and its creation.
function createPrivateDirs(plans, projectRoot, mkdir = (directory) => fs.mkdirSync(directory, { mode: 0o700 })) {
    const created = [];
    try {
        for (const plan of plans) {
            const pending = [];
            for (let current = plan.real; !fs.lstatSync(current, { throwIfNoEntry: false }); current = path.dirname(current)) {
                pending.unshift(current);
            }
            for (const directory of pending) {
                try {
                    mkdir(directory);
                }
                catch (error) {
                    // Another run, such as one in a parallel worktree, created it first.
                    // It is not ours to remove; the checks below still decide.
                    if (error.code === "EEXIST") {
                        continue;
                    }
                    throw error;
                }
                created.push(directory);
            }
        }
        for (const plan of plans) {
            const again = planPrivateDir(plan.real, plan.label, projectRoot);
            if (again.real !== plan.real || !fs.statSync(again.real).isDirectory()) {
                throw new Error(`cannot keep ${plan.label} under ${plan.real}: the directory changed while it was created`);
            }
        }
    }
    catch (error) {
        for (const directory of created.reverse()) {
            try {
                fs.rmdirSync(directory);
            }
            catch {
                // Leave a directory that is no longer empty or no longer ours.
            }
        }
        throw error;
    }
}
