#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

type Scope = "user" | "project";
type Agent = "codex" | "claude-code";
type Action = "install" | "profile-validate";

interface ExternalSkillSource {
  source: string;
  skills: string[];
}

interface LocalSkill {
  name: string;
  path: string;
}

interface SkillsPlan {
  generatedBy: string;
  scope: Scope | "validate";
  requestedProfiles: string[];
  expandedProfiles: string[];
  agents: Agent[];
  external: ExternalSkillSource[];
  local: LocalSkill[];
}

interface ParsedArgs {
  action: Action;
  scope: Scope;
  profiles: string;
  agents: Agent[];
}

interface BackupRecord {
  targetPath: string;
  backupPath: string | null;
}

interface SetupContext {
  dotfilesRoot: string;
  home: string;
  tmpdir: string;
  dryRun: boolean;
}

const SUPPORTED_AGENTS = new Set<Agent>(["codex", "claude-code"]);

function fail(message: string): never {
  throw new Error(message);
}

function info(message: string): void {
  console.log(message);
}

function warn(message: string): void {
  console.warn(message);
}

function csv(value: string): string[] {
  if (!value) {
    return [];
  }
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseAgent(value: string): Agent {
  const trimmed = value.trim();
  if (trimmed === "codex" || trimmed === "claude-code") {
    return trimmed;
  }
  fail(`unsupported skills agent: ${trimmed}`);
}

function parseAgents(values: string[]): Agent[] {
  const agents: Agent[] = [];
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

function parseArgs(argv: string[]): ParsedArgs {
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
    };
  }

  let scope: Scope = "user";
  let profiles = "";
  const agentArgs: string[] = [];
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
    fail(`Unknown skills argument: ${item}`);
  }

  const agents: Agent[] = agentArgs.length > 0 ? parseAgents(agentArgs) : ["codex", "claude-code"];
  return {
    action: "install",
    scope,
    profiles,
    agents,
  };
}

function requireCommand(command: string): void {
  const checker = process.platform === "win32" ? "where" : "command";
  const args = process.platform === "win32" ? [command] : ["-v", command];
  const result = process.platform === "win32"
    ? spawnSync(checker, args, { stdio: "ignore" })
    : spawnSync("sh", ["-c", `command -v ${shellQuote(command)}`], { stdio: "ignore" });
  if (result.status !== 0) {
    fail(`Required command not found: ${command}`);
  }
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

function readJson(filePath: string): unknown {
  let raw: string;
  try {
    raw = fs.readFileSync(filePath, "utf8");
  } catch (error) {
    fail(`failed to read ${filePath}: ${(error as Error).message}`);
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    fail(`failed to parse ${filePath}: ${(error as Error).message}`);
  }
}

function ensureArray(value: unknown, filePath: string, key: string): unknown[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    fail(`${filePath}: ${key} must be an array`);
  }
  return value;
}

function getObjectProperty(value: unknown, key: string): unknown {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }
  return (value as Record<string, unknown>)[key];
}

function profilePath(profileDir: string, name: string): string {
  return path.join(profileDir, `${name}.json`);
}

function listProfiles(profileDir: string): string[] {
  if (!fs.existsSync(profileDir)) {
    fail(`skills profiles directory not found: ${profileDir}`);
  }
  return fs
    .readdirSync(profileDir)
    .filter((entry) => entry.endsWith(".json"))
    .map((entry) => path.basename(entry, ".json"))
    .sort();
}

function resolveProfiles(dotfilesRoot: string, requestedProfiles: string[], agents: Agent[], scope: Scope | "validate"): SkillsPlan {
  const profileDir = path.join(dotfilesRoot, "skills", "profiles");
  const localDir = path.join(dotfilesRoot, "skills", "local");
  const expanded: string[] = [];
  const loaded = new Set<string>();
  const externalBySource = new Map<string, Set<string>>();
  const localSkills = new Set<string>();

  function load(name: string, stack: string[]): void {
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
      const source = (entry as Record<string, unknown>).source;
      if (typeof source !== "string" || source.trim() === "") {
        fail(`${filePath}: external entry is missing source`);
      }
      const skills = ensureArray((entry as Record<string, unknown>).skills, filePath, "external[].skills");
      if (skills.length === 0) {
        fail(`${filePath}: external entry for ${source} has no skills`);
      }
      if (!externalBySource.has(source)) {
        externalBySource.set(source, new Set<string>());
      }
      const sourceSkills = externalBySource.get(source);
      if (!sourceSkills) {
        fail(`failed to resolve external source ${source}`);
      }
      for (const skillName of skills) {
        if (typeof skillName !== "string" || skillName.trim() === "") {
          fail(`${filePath}: external skills must contain names`);
        }
        sourceSkills.add(skillName);
      }
    }

    const local = ensureArray(getObjectProperty(profile, "local"), filePath, "local");
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

function writeJson(filePath: string, value: unknown): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeMetadata(plan: SkillsPlan, outputFile: string): void {
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

function validateProfiles(dotfilesRoot: string, profilesCsv: string): void {
  const profileDir = path.join(dotfilesRoot, "skills", "profiles");
  const requestedProfiles = profilesCsv ? csv(profilesCsv) : listProfiles(profileDir);
  resolveProfiles(dotfilesRoot, requestedProfiles, ["codex"], "validate");
  console.log(`Profiles valid: ${requestedProfiles.join(",")}`);
}

function removePath(targetPath: string): void {
  fs.rmSync(targetPath, { recursive: true, force: true });
}

function copyDirectoryContents(sourceDir: string, targetDir: string): void {
  if (!fs.existsSync(sourceDir)) {
    return;
  }
  fs.mkdirSync(targetDir, { recursive: true });
  for (const entry of fs.readdirSync(sourceDir)) {
    fs.cpSync(path.join(sourceDir, entry), path.join(targetDir, entry), {
      recursive: true,
      dereference: false,
      force: true,
      verbatimSymlinks: true,
    });
  }
}

function normalizePath(targetPath: string): string {
  return path.resolve(targetPath);
}

function getLinkTarget(targetPath: string): string | null {
  try {
    const stat = fs.lstatSync(targetPath);
    if (!stat.isSymbolicLink()) {
      return null;
    }
    return fs.readlinkSync(targetPath);
  } catch {
    return null;
  }
}

function isManagedLocalSymlink(targetPath: string, expectedRoot: string): boolean {
  const linked = getLinkTarget(targetPath);
  if (!linked) {
    return false;
  }
  const resolvedLinked = normalizePath(path.resolve(path.dirname(targetPath), linked));
  const resolvedRoot = normalizePath(expectedRoot);
  return resolvedLinked === resolvedRoot || resolvedLinked.startsWith(`${resolvedRoot}${path.sep}`);
}

function createSymlink(sourcePath: string, targetPath: string, expectedRoot?: string): void {
  const resolvedSource = normalizePath(sourcePath);
  if (fs.existsSync(targetPath) || fs.existsSync(path.dirname(targetPath)) && getLinkTarget(targetPath) !== null) {
    if (expectedRoot && !isManagedLocalSymlink(targetPath, expectedRoot)) {
      fail(`skill target already exists and is not a dotfiles local symlink: ${targetPath}`);
    }
    removePath(targetPath);
  }
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.symlinkSync(resolvedSource, targetPath, "dir");
}

function agentSkillDir(root: string, agent: Agent): string {
  if (agent === "codex") {
    return path.join(root, ".agents", "skills");
  }
  if (agent === "claude-code") {
    return path.join(root, ".claude", "skills");
  }
  fail(`unsupported agent: ${agent satisfies never}`);
}

function linkLocalSkills(plan: SkillsPlan, dotfilesRoot: string, target: "user" | "project", rootOrSkillsDir: string): void {
  const localRoot = path.join(dotfilesRoot, "skills", "local");
  if (target === "user") {
    for (const skill of plan.local) {
      createSymlink(skill.path, path.join(rootOrSkillsDir, skill.name), localRoot);
    }
    return;
  }

  for (const agent of plan.agents) {
    const skillsDir = agentSkillDir(rootOrSkillsDir, agent);
    for (const skill of plan.local) {
      createSymlink(skill.path, path.join(skillsDir, skill.name), localRoot);
    }
  }
}

function runCommand(command: string, args: string[], cwd: string, env: NodeJS.ProcessEnv = process.env): void {
  const result = spawnSync(command, args, {
    cwd,
    env,
    stdio: ["ignore", "inherit", "inherit"],
  });
  if (result.error) {
    fail(result.error.message);
  }
  if (result.status !== 0) {
    fail(`${command} ${args.join(" ")} failed with exit ${result.status ?? "unknown"}`);
  }
}

function commandPreview(command: string, args: string[]): string {
  return [command, ...args].join(" ");
}

function logDryRunExternalInstalls(workDir: string, plan: SkillsPlan, agents: Agent[], npmCacheDir: string): void {
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
}

function logDryRunUserExternalInstalls(tempInstallDir: string, plan: SkillsPlan, npmCacheDir: string): void {
  for (const entry of plan.external) {
    info(`DRY-RUN rm -rf ${tempInstallDir}`);
    info(`DRY-RUN mkdir -p ${tempInstallDir}`);
    const args = ["skills", "add", entry.source, "--copy", "--yes", "--agent", "codex"];
    for (const skill of entry.skills) {
      args.push("--skill", skill);
    }
    info(`DRY-RUN cd ${tempInstallDir} && NPM_CONFIG_CACHE=${npmCacheDir} ${commandPreview("npx", args)}`);
  }
}

function logDryRunLinkLocalSkills(plan: SkillsPlan, target: "user" | "project", rootOrSkillsDir: string): void {
  if (target === "user") {
    for (const skill of plan.local) {
      info(`DRY-RUN ln -s ${skill.path} ${path.join(rootOrSkillsDir, skill.name)}`);
    }
    return;
  }

  for (const agent of plan.agents) {
    const skillsDir = agentSkillDir(rootOrSkillsDir, agent);
    for (const skill of plan.local) {
      info(`DRY-RUN ln -s ${skill.path} ${path.join(skillsDir, skill.name)}`);
    }
  }
}

function logDryRunUserAgentSkillDirs(restoreSkillsDir: string, setupHome: string, agents: Agent[]): void {
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

function runExternalInstalls(workDir: string, plan: SkillsPlan, agents: Agent[], npmCacheDir: string): void {
  if (plan.external.length === 0) {
    return;
  }
  requireCommand("npx");
  fs.mkdirSync(npmCacheDir, { recursive: true });

  for (const entry of plan.external) {
    const args = ["skills", "add", entry.source, "--copy", "--yes"];
    for (const agent of agents) {
      args.push("--agent", agent);
    }
    for (const skill of entry.skills) {
      args.push("--skill", skill);
    }
    runCommand("npx", args, workDir, {
      ...process.env,
      NPM_CONFIG_CACHE: npmCacheDir,
    });
  }
}

function runUserExternalInstalls(tempInstallDir: string, restoreSkillsDir: string, plan: SkillsPlan, npmCacheDir: string): void {
  if (plan.external.length === 0) {
    return;
  }
  requireCommand("npx");
  fs.mkdirSync(npmCacheDir, { recursive: true });

  for (const entry of plan.external) {
    removePath(tempInstallDir);
    fs.mkdirSync(tempInstallDir, { recursive: true });

    const args = ["skills", "add", entry.source, "--copy", "--yes", "--agent", "codex"];
    for (const skill of entry.skills) {
      args.push("--skill", skill);
    }
    runCommand("npx", args, tempInstallDir, {
      ...process.env,
      NPM_CONFIG_CACHE: npmCacheDir,
    });
    copyDirectoryContents(path.join(tempInstallDir, ".agents", "skills"), restoreSkillsDir);
  }
}

function swapUserSkillsView(restoreRoot: string, restoreSkillsDir: string, stagingSkillsDir: string, stagingMetadata: string): void {
  const metadataFile = path.join(restoreRoot, "skills-profile.json");
  const suffix = `${process.pid}`;
  const backupSkillsDir = path.join(restoreRoot, `skills.previous.${suffix}`);
  const backupMetadata = path.join(restoreRoot, `skills-profile.json.previous.${suffix}`);

  removePath(backupSkillsDir);
  removePath(backupMetadata);

  if (fs.existsSync(restoreSkillsDir) || getLinkTarget(restoreSkillsDir)) {
    fs.renameSync(restoreSkillsDir, backupSkillsDir);
  }
  if (fs.existsSync(metadataFile) || getLinkTarget(metadataFile)) {
    fs.renameSync(metadataFile, backupMetadata);
  }

  try {
    fs.renameSync(stagingSkillsDir, restoreSkillsDir);
    fs.renameSync(stagingMetadata, metadataFile);
  } catch (error) {
    removePath(restoreSkillsDir);
    removePath(metadataFile);
    if (fs.existsSync(backupSkillsDir) || getLinkTarget(backupSkillsDir)) {
      fs.renameSync(backupSkillsDir, restoreSkillsDir);
    }
    if (fs.existsSync(backupMetadata) || getLinkTarget(backupMetadata)) {
      fs.renameSync(backupMetadata, metadataFile);
    }
    throw error;
  }

  removePath(backupSkillsDir);
  removePath(backupMetadata);
}

function linkUserAgentSkillDirs(restoreSkillsDir: string, setupHome: string, agents: Agent[]): void {
  for (const agent of agents) {
    if (agent === "codex") {
      fs.mkdirSync(path.join(setupHome, ".agents"), { recursive: true });
      createSymlink(restoreSkillsDir, path.join(setupHome, ".agents", "skills"));
      continue;
    }
    if (agent === "claude-code") {
      fs.mkdirSync(path.join(setupHome, ".claude"), { recursive: true });
      createSymlink(restoreSkillsDir, path.join(setupHome, ".claude", "skills"));
      continue;
    }
    fail(`unsupported skills agent: ${agent satisfies never}`);
  }
}

function setupUserSkills(dotfilesRoot: string, setupHome: string, setupTmpdir: string, profilesCsv: string, agents: Agent[], dryRun: boolean): void {
  const requestedProfiles = csv(profilesCsv || "base");
  const plan = resolveProfiles(dotfilesRoot, requestedProfiles, agents, "user");
  const restoreRoot = path.join(dotfilesRoot, ".agents", "user");
  const restoreSkillsDir = path.join(restoreRoot, "skills");
  const suffix = `${process.pid}`;
  const stagingSkillsDir = path.join(restoreRoot, `skills.next.${suffix}`);
  const stagingMetadata = path.join(restoreRoot, `skills-profile.json.next.${suffix}`);
  const tempInstallDir = path.join(setupTmpdir, "dotfiles-skills-user-install");
  const npmCacheDir = path.join(setupTmpdir, "skills-npm-cache");

  if (dryRun) {
    info(`DRY-RUN rm -rf ${stagingSkillsDir}`);
    info(`DRY-RUN rm -rf ${stagingMetadata}`);
    info(`DRY-RUN rm -rf ${tempInstallDir}`);
    info(`DRY-RUN mkdir -p ${restoreRoot}`);
    info(`DRY-RUN mkdir -p ${stagingSkillsDir}`);
    info(`DRY-RUN mkdir -p ${tempInstallDir}`);
    logDryRunUserExternalInstalls(tempInstallDir, plan, npmCacheDir);
    logDryRunLinkLocalSkills(plan, "user", stagingSkillsDir);
    info(`DRY-RUN write skills metadata ${stagingMetadata}`);
    info(`DRY-RUN swap ${stagingSkillsDir} into ${restoreSkillsDir}`);
    info(`DRY-RUN mv ${stagingMetadata} ${path.join(restoreRoot, "skills-profile.json")}`);
    logDryRunUserAgentSkillDirs(restoreSkillsDir, setupHome, agents);
    info(`User skills installed for profiles: ${requestedProfiles.join(",")}`);
    return;
  }

  removePath(stagingSkillsDir);
  removePath(stagingMetadata);
  removePath(tempInstallDir);

  fs.mkdirSync(restoreRoot, { recursive: true });
  fs.mkdirSync(stagingSkillsDir, { recursive: true });
  fs.mkdirSync(tempInstallDir, { recursive: true });

  try {
    runUserExternalInstalls(tempInstallDir, stagingSkillsDir, plan, npmCacheDir);
    linkLocalSkills(plan, dotfilesRoot, "user", stagingSkillsDir);
    writeMetadata(plan, stagingMetadata);
    swapUserSkillsView(restoreRoot, restoreSkillsDir, stagingSkillsDir, stagingMetadata);
  } catch (error) {
    removePath(stagingSkillsDir);
    removePath(stagingMetadata);
    removePath(tempInstallDir);
    throw error;
  }

  removePath(stagingSkillsDir);
  removePath(stagingMetadata);
  removePath(tempInstallDir);
  linkUserAgentSkillDirs(restoreSkillsDir, setupHome, agents);
  info(`User skills installed for profiles: ${requestedProfiles.join(",")}`);
}

function backupPath(targetPath: string, backupRoot: string, records: BackupRecord[]): void {
  if (!fs.existsSync(targetPath) && !getLinkTarget(targetPath)) {
    records.push({ targetPath, backupPath: null });
    return;
  }

  const backupName = `${path.basename(path.dirname(targetPath))}-${path.basename(targetPath)}`;
  const backupTarget = path.join(backupRoot, `${backupName}.${timestamp()}.${process.pid}`);
  fs.mkdirSync(backupRoot, { recursive: true });
  fs.renameSync(targetPath, backupTarget);
  records.push({ targetPath, backupPath: backupTarget });
  warn(`Backed up existing skills path to ${backupTarget}`);
}

function timestamp(): string {
  const now = new Date();
  const pad = (value: number) => String(value).padStart(2, "0");
  return [
    now.getFullYear(),
    pad(now.getMonth() + 1),
    pad(now.getDate()),
    pad(now.getHours()),
    pad(now.getMinutes()),
    pad(now.getSeconds()),
  ].join("");
}

function prepareProjectTargets(projectRoot: string, agents: Agent[], backupRoot: string): BackupRecord[] {
  const records: BackupRecord[] = [];
  backupPath(path.join(projectRoot, "skills-lock.json"), backupRoot, records);
  backupPath(path.join(projectRoot, ".agents", "skills-profile.json"), backupRoot, records);
  for (const agent of agents) {
    backupPath(agentSkillDir(projectRoot, agent), backupRoot, records);
  }
  return records;
}

function rollbackProjectTargets(records: BackupRecord[]): void {
  for (const record of records) {
    removePath(record.targetPath);
    if (record.backupPath && (fs.existsSync(record.backupPath) || getLinkTarget(record.backupPath))) {
      fs.mkdirSync(path.dirname(record.targetPath), { recursive: true });
      fs.renameSync(record.backupPath, record.targetPath);
    }
  }
  warn("Restored previous project skills after failed install");
}

function gitProjectRoot(cwd: string): string {
  requireCommand("git");
  const result = spawnSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail("project scope requires running inside a git repository");
  }
  return result.stdout.trim();
}

function setupProjectSkills(dotfilesRoot: string, setupTmpdir: string, profilesCsv: string, agents: Agent[], dryRun: boolean): void {
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
  const workDir = path.join(setupTmpdir, "dotfiles-skills");
  const npmCacheDir = path.join(setupTmpdir, "skills-npm-cache");
  const backupRoot = path.join(setupTmpdir, "dotfiles-skills-backup", path.basename(projectRoot));

  if (dryRun) {
    info(`DRY-RUN mkdir -p ${workDir}`);
    info(`DRY-RUN mkdir -p ${npmCacheDir}`);
    info(`DRY-RUN mkdir -p ${path.join(projectRoot, ".agents")}`);
    info(`DRY-RUN backup ${path.join(projectRoot, "skills-lock.json")} to ${backupRoot}`);
    info(`DRY-RUN backup ${path.join(projectRoot, ".agents", "skills-profile.json")} to ${backupRoot}`);
    for (const agent of agents) {
      info(`DRY-RUN backup ${agentSkillDir(projectRoot, agent)} to ${backupRoot}`);
    }
    logDryRunExternalInstalls(projectRoot, plan, agents, npmCacheDir);
    logDryRunLinkLocalSkills(plan, "project", projectRoot);
    info(`DRY-RUN write skills metadata ${path.join(projectRoot, ".agents", "skills-profile.json")}`);
    info(`Project skills installed for profiles: ${requestedProfiles.join(",")}`);
    info("Consider ignoring generated skill directories: .agents/skills/ .claude/skills/");
    return;
  }

  fs.mkdirSync(workDir, { recursive: true });
  fs.mkdirSync(npmCacheDir, { recursive: true });
  fs.mkdirSync(path.join(projectRoot, ".agents"), { recursive: true });

  const backups = prepareProjectTargets(projectRoot, agents, backupRoot);
  try {
    runExternalInstalls(projectRoot, plan, agents, npmCacheDir);
    linkLocalSkills(plan, dotfilesRoot, "project", projectRoot);
    writeMetadata(plan, path.join(projectRoot, ".agents", "skills-profile.json"));
  } catch (error) {
    rollbackProjectTargets(backups);
    throw error;
  }

  info(`Project skills installed for profiles: ${requestedProfiles.join(",")}`);
  info("Consider ignoring generated skill directories: .agents/skills/ .claude/skills/");
}

function setupContext(): SetupContext {
  const defaultDotfilesRoot = path.resolve(__dirname, "..");
  const dryRun = process.env.SETUP_DRY_RUN || "0";
  if (dryRun !== "0" && dryRun !== "1") {
    fail(`SETUP_DRY_RUN must be 0 or 1: ${dryRun}`);
  }
  return {
    dotfilesRoot: path.resolve(process.env.SETUP_DOTFILES_ROOT || defaultDotfilesRoot),
    home: path.resolve(process.env.SETUP_HOME || process.env.HOME || os.homedir()),
    tmpdir: path.resolve(process.env.SETUP_TMPDIR || os.tmpdir()),
    dryRun: dryRun === "1",
  };
}

function main(argv: string[]): void {
  const parsed = parseArgs(argv);
  const context = setupContext();

  if (parsed.action === "profile-validate") {
    validateProfiles(context.dotfilesRoot, parsed.profiles);
    return;
  }

  if (parsed.scope === "user") {
    setupUserSkills(context.dotfilesRoot, context.home, context.tmpdir, parsed.profiles, parsed.agents, context.dryRun);
    return;
  }

  setupProjectSkills(context.dotfilesRoot, context.tmpdir, parsed.profiles, parsed.agents, context.dryRun);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error((error as Error).message);
  process.exit(1);
}
