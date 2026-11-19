"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fail = fail;
exports.csv = csv;
exports.parseAgent = parseAgent;
exports.parseAgents = parseAgents;
exports.readJson = readJson;
exports.isPathComponentName = isPathComponentName;
exports.listProfiles = listProfiles;
exports.resolveProfiles = resolveProfiles;
const fs = require("node:fs");
const path = require("node:path");
const skill_names_1 = require("./skill-names");
function fail(message) {
    throw new Error(message);
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
// Profile and local skill names become path components under skills/, so each
// must be one plain component: no separators, no leading dot, no "..".
function isPathComponentName(name) {
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name);
}
function requireUnreservedSkillName(name) {
    if ((0, skill_names_1.isReservedSkillName)(name)) {
        fail(`Invalid or reserved skill name: ${name}`);
    }
}
function requireLocalSkillName(name) {
    if (!isPathComponentName(name)) {
        fail(`Invalid or reserved skill name: ${name}`);
    }
    requireUnreservedSkillName(name);
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
        if (!isPathComponentName(name)) {
            fail(`Invalid profile name: ${name}`);
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
            requireLocalSkillName(skillName);
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
