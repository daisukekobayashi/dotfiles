#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

function fail(message) {
  console.error(message);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item.startsWith("--")) {
      args._.push(item);
      continue;
    }

    const key = item.slice(2);
    if (key === "dry-run") {
      args[key] = "1";
      continue;
    }

    if (index + 1 >= argv.length) {
      fail(`--${key} requires a value`);
    }
    args[key] = argv[index + 1];
    index += 1;
  }
  return args;
}

function required(args, key) {
  if (!args[key]) {
    fail(`--${key} is required`);
  }
  return args[key];
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

function readJson(filePath) {
  let raw;
  try {
    raw = fs.readFileSync(filePath, "utf8");
  } catch (error) {
    fail(`failed to read ${filePath}: ${error.message}`);
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
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
    const includes = ensureArray(profile.includes, filePath, "includes");
    for (const includeName of includes) {
      if (typeof includeName !== "string" || includeName.trim() === "") {
        fail(`${filePath}: includes must contain profile names`);
      }
      load(includeName, stack.concat(name));
    }

    const external = ensureArray(profile.external, filePath, "external");
    for (const entry of external) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
        fail(`${filePath}: external entries must be objects`);
      }
      if (typeof entry.source !== "string" || entry.source.trim() === "") {
        fail(`${filePath}: external entry is missing source`);
      }
      const skills = ensureArray(entry.skills, filePath, "external[].skills");
      if (skills.length === 0) {
        fail(`${filePath}: external entry for ${entry.source} has no skills`);
      }
      if (!externalBySource.has(entry.source)) {
        externalBySource.set(entry.source, new Set());
      }
      for (const skillName of skills) {
        if (typeof skillName !== "string" || skillName.trim() === "") {
          fail(`${filePath}: external skills must contain names`);
        }
        externalBySource.get(entry.source).add(skillName);
      }
    }

    const local = ensureArray(profile.local, filePath, "local");
    for (const skillName of local) {
      if (typeof skillName !== "string" || skillName.trim() === "") {
        fail(`${filePath}: local must contain skill names`);
      }
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

  const external = Array.from(externalBySource.entries())
    .map(([source, skills]) => ({
      source,
      skills: Array.from(skills).sort(),
    }))
    .sort((left, right) => left.source.localeCompare(right.source));

  const local = Array.from(localSkills)
    .sort()
    .map((name) => ({
      name,
      path: path.join(localDir, name),
    }));

  return {
    generatedBy: "dotfiles setup skills",
    scope,
    requestedProfiles,
    expandedProfiles: expanded,
    agents,
    external,
    local,
  };
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writePlan(args) {
  const dotfilesRoot = path.resolve(required(args, "dotfiles-root"));
  const requestedProfiles = csv(required(args, "profiles"));
  const agents = csv(required(args, "agents"));
  const scope = required(args, "scope");
  if (requestedProfiles.length === 0) {
    fail("--profiles must contain at least one profile");
  }
  if (agents.length === 0) {
    fail("--agents must contain at least one agent");
  }

  const plan = resolveProfiles(dotfilesRoot, requestedProfiles, agents, scope);
  const output = args.output;
  if (output) {
    writeJson(path.resolve(output), plan);
  } else {
    process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`);
  }
}

function validate(args) {
  const dotfilesRoot = path.resolve(required(args, "dotfiles-root"));
  const profileDir = path.join(dotfilesRoot, "skills", "profiles");
  const profiles = csv(args.profiles);
  const requestedProfiles = profiles.length > 0 ? profiles : listProfiles(profileDir);
  resolveProfiles(dotfilesRoot, requestedProfiles, ["codex"], "validate");
  console.log(`Profiles valid: ${requestedProfiles.join(",")}`);
}

function readPlan(args) {
  return readJson(path.resolve(required(args, "plan")));
}

function externalLines(args) {
  const plan = readPlan(args);
  for (const entry of plan.external || []) {
    console.log(`${entry.source}\t${entry.skills.join(",")}`);
  }
}

function isManagedLocalSymlink(targetPath, expectedRoot) {
  if (!fs.existsSync(targetPath) && !fs.lstatSync(path.dirname(targetPath)).isDirectory()) {
    return false;
  }
  let stat;
  try {
    stat = fs.lstatSync(targetPath);
  } catch (_error) {
    return false;
  }
  if (!stat.isSymbolicLink()) {
    return false;
  }
  const linked = fs.readlinkSync(targetPath);
  return linked === expectedRoot || linked.startsWith(`${expectedRoot}${path.sep}`);
}

function linkSkill(sourcePath, targetPath, localRoot, dryRun) {
  let targetExists = false;
  try {
    fs.lstatSync(targetPath);
    targetExists = true;
  } catch (_error) {
    targetExists = false;
  }

  if (targetExists) {
    if (!isManagedLocalSymlink(targetPath, localRoot)) {
      fail(`skill target already exists and is not a dotfiles local symlink: ${targetPath}`);
    }
    if (dryRun) {
      console.log(`DRY-RUN rm ${targetPath}`);
    } else {
      fs.unlinkSync(targetPath);
    }
  }

  if (dryRun) {
    console.log(`DRY-RUN ln -s ${sourcePath} ${targetPath}`);
    return;
  }
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.symlinkSync(sourcePath, targetPath, "dir");
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

function linkLocal(args) {
  const plan = readPlan(args);
  const dotfilesRoot = path.resolve(required(args, "dotfiles-root"));
  const localRoot = path.join(dotfilesRoot, "skills", "local");
  const dryRun = args["dry-run"] === "1";
  const target = required(args, "target");

  if (target === "project") {
    const root = path.resolve(required(args, "root"));
    for (const agent of plan.agents || []) {
      const skillsDir = agentSkillDir(root, agent);
      for (const skill of plan.local || []) {
        linkSkill(skill.path, path.join(skillsDir, skill.name), localRoot, dryRun);
      }
    }
    return;
  }

  if (target === "user") {
    const skillsDir = path.resolve(required(args, "skills-dir"));
    for (const skill of plan.local || []) {
      linkSkill(skill.path, path.join(skillsDir, skill.name), localRoot, dryRun);
    }
    return;
  }

  fail(`unsupported local link target: ${target}`);
}

function metadata(args) {
  const plan = readPlan(args);
  const output = path.resolve(required(args, "output"));
  const metadataValue = {
    generatedBy: plan.generatedBy,
    scope: plan.scope,
    requestedProfiles: plan.requestedProfiles,
    expandedProfiles: plan.expandedProfiles,
    agents: plan.agents,
    external: plan.external,
    localSkills: (plan.local || []).map((skill) => skill.name),
  };
  writeJson(output, metadataValue);
}

function main() {
  const [command, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);

  switch (command) {
    case "plan":
      writePlan(args);
      break;
    case "validate":
      validate(args);
      break;
    case "external-lines":
      externalLines(args);
      break;
    case "link-local":
      linkLocal(args);
      break;
    case "metadata":
      metadata(args);
      break;
    default:
      fail(`unknown skills profile command: ${command || ""}`);
  }
}

main();
