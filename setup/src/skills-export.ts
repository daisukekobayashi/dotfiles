import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { type Agent, type ExternalSkillSource, csv, fail, isPathComponentName, parseAgents, resolveProfiles } from "./skill-profiles";

// Writes a self-contained bundle of profile-selected local skills, the local
// skills they link to, a record of external skills, and composed agent rules.
// See docs/skills-profiles.md "Export".

export const BUNDLE_MANIFEST = "skills-bundle.json";
const GENERATED_BY = "dotfiles setup skills export";
const SCHEMA_VERSION = 1;
const MARKERS_FILE_ENV = "SETUP_EXPORT_PERSONAL_MARKERS_FILE";
const TOP_LEVEL_FILES = new Set(["AGENTS.md", "CLAUDE.md", "README.md", BUNDLE_MANIFEST]);

export interface ExportOptions {
  profiles: string[];
  agents: Agent[];
  exclude: string[];
  out: string;
  force: boolean;
}

export interface ExportContext {
  dotfilesRoot: string;
  home: string;
  dryRun: boolean;
  env: NodeJS.ProcessEnv;
  // Returns the git executable to run; Windows resolves it to an absolute path
  // so a git in the current directory is never picked.
  gitCommand: () => string;
}

interface BundleSkill {
  name: string;
  origin: "profile" | "dependency";
  requiredBy?: string[];
}

interface BundleManifest {
  schemaVersion: number;
  generatedBy: string;
  requestedProfiles: string[];
  expandedProfiles: string[];
  agents: Agent[];
  local: BundleSkill[];
  excluded: string[];
  external: ExternalSkillSource[];
  rules: string[];
  files: string[];
}

interface RulesTarget {
  agent: Agent;
  file: string;
  override: string;
}

const RULES_TARGETS: RulesTarget[] = [
  { agent: "codex", file: "AGENTS.md", override: "codex.md" },
  { agent: "claude-code", file: "CLAUDE.md", override: "claude.md" },
];

export function parseExportArgs(argv: string[]): ExportOptions {
  let profiles = "";
  let out = "";
  let force = false;
  const agentArgs: string[] = [];
  const exclude: string[] = [];
  let index = 0;

  function value(flag: string): string {
    if (index + 1 >= argv.length) {
      fail(`${flag} requires a value`);
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
      exclude.push(...csv(value(item)));
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
    fail(`Unknown skills export argument: ${item}`);
  }

  if (csv(profiles).length === 0) {
    fail("--profile is required for skills export");
  }
  if (!out) {
    fail("--out is required for skills export");
  }
  const agents = agentArgs.length > 0 ? parseAgents(agentArgs) : (["codex", "claude-code"] as Agent[]);
  if (agents.length === 0) {
    fail("--agent requires a value");
  }
  return { profiles: csv(profiles), agents, exclude: Array.from(new Set(exclude)), out, force };
}

function toPosix(relative: string): string {
  return relative.split(path.sep).join("/");
}

function isInsideOrSame(candidate: string, root: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function isStrictlyInside(candidate: string, root: string): boolean {
  return candidate !== root && isInsideOrSame(candidate, root);
}

// Resolves a path that may not exist yet through its nearest existing ancestor.
function realPathOfPossiblyMissing(target: string): string {
  const missing: string[] = [];
  let current = path.resolve(target);
  for (;;) {
    try {
      return path.join(fs.realpathSync(current), ...missing.reverse());
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
        throw error;
      }
      const parent = path.dirname(current);
      if (parent === current) {
        return path.resolve(target);
      }
      missing.push(path.basename(current));
      current = parent;
    }
  }
}

// Every source read must resolve inside its allowed root, so a link in the
// checkout cannot bring other files into a bundle.
function requireRealInside(target: string, rootReal: string, label: string): string {
  const real = fs.realpathSync(target);
  if (!isInsideOrSame(real, rootReal)) {
    fail(`${label} resolves outside ${path.basename(rootReal)}/: ${target}`);
  }
  return real;
}

// Lists a skill's files relative to its directory, without the top-level
// evals/ directory, which holds development fixtures for this repository.
// A symbolic link fails the export because the bundle must hold real files.
function skillFiles(skillDir: string, skillName: string): string[] {
  const files: string[] = [];
  function walk(relativeDir: string): void {
    const entries = fs.readdirSync(path.join(skillDir, relativeDir), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      if (relativeDir === "" && entry.name === "evals") {
        continue;
      }
      const relative = path.join(relativeDir, entry.name);
      if (entry.isSymbolicLink()) {
        fail(`local skill ${skillName} contains a symbolic link: ${toPosix(relative)}`);
      }
      if (entry.isDirectory()) {
        walk(relative);
      } else if (entry.isFile()) {
        files.push(relative);
      } else {
        fail(`local skill ${skillName} contains an unsupported entry: ${toPosix(relative)}`);
      }
    }
  }
  walk("");
  return files;
}

// A selected skill root must be a real directory inside skills/local.
function requireSkillRoot(localDir: string, localReal: string, name: string): string {
  if (!isPathComponentName(name)) {
    fail(`Invalid or reserved skill name: ${name}`);
  }
  const skillDir = path.join(localDir, name);
  const stat = fs.lstatSync(skillDir, { throwIfNoEntry: false });
  if (!stat) {
    fail(`unknown local skill ${name}`);
  }
  if (stat.isSymbolicLink()) {
    fail(`local skill ${name} is a symbolic link`);
  }
  if (!stat.isDirectory()) {
    fail(`local skill ${name} is not a directory`);
  }
  requireRealInside(skillDir, localReal, `local skill ${name}`);
  return skillDir;
}

// A skill depends on another local skill when one of its files links into it
// relative to the skill directory, such as ../delivery-common/scripts/x.mjs.
// Bare skill names in prose are not dependencies.
function skillDependencies(skillDir: string, skillName: string, localNames: ReadonlySet<string>): Set<string> {
  const dependencies = new Set<string>();
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

interface Selection {
  local: BundleSkill[];
  external: ExternalSkillSource[];
  excluded: string[];
}

function selectSkills(localDir: string, localReal: string, profileLocal: string[], external: ExternalSkillSource[], exclude: string[]): Selection {
  const localNames = new Set(
    fs
      .readdirSync(localDir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && isPathComponentName(entry.name))
      .map((entry) => entry.name),
  );
  const excluded = new Set(exclude);
  const included = new Map<string, BundleSkill>();
  const dependencyCache = new Map<string, Set<string>>();
  const dependenciesOf = (name: string): Set<string> => {
    let dependencies = dependencyCache.get(name);
    if (!dependencies) {
      dependencies = skillDependencies(requireSkillRoot(localDir, localReal, name), name, localNames);
      dependencyCache.set(name, dependencies);
    }
    return dependencies;
  };

  const queue: string[] = [];
  for (const name of profileLocal) {
    if (!excluded.has(name)) {
      included.set(name, { name, origin: "profile" });
      queue.push(name);
    }
  }
  const conflicts: string[] = [];
  while (queue.length > 0) {
    const name = queue.shift() as string;
    for (const dependency of Array.from(dependenciesOf(name)).sort()) {
      if (excluded.has(dependency)) {
        conflicts.push(`${dependency} is required by ${name}`);
        continue;
      }
      const existing = included.get(dependency);
      if (!existing) {
        included.set(dependency, { name: dependency, origin: "dependency", requiredBy: [name] });
        queue.push(dependency);
      } else if (existing.origin === "dependency" && !existing.requiredBy?.includes(name)) {
        existing.requiredBy?.push(name);
      }
    }
  }
  if (conflicts.length > 0) {
    fail(`cannot exclude a skill that a selected skill depends on: ${conflicts.sort().join("; ")}`);
  }

  const externalNames = new Set(external.flatMap((entry) => entry.skills));
  const unknown = exclude.filter((name) => !profileLocal.includes(name) && !externalNames.has(name)).sort();
  if (unknown.length > 0) {
    fail(`--exclude names skills that the selected profiles do not include: ${unknown.join(", ")}`);
  }

  const keptExternal = external
    .map((entry) => ({ source: entry.source, skills: entry.skills.filter((name) => !excluded.has(name)) }))
    .filter((entry) => entry.skills.length > 0);
  // Dependencies join after the resolver's collision check, so check again.
  const keptExternalNames = new Set(keptExternal.flatMap((entry) => entry.skills));
  const collisions = Array.from(included.keys()).filter((name) => keptExternalNames.has(name)).sort();
  if (collisions.length > 0) {
    fail(`skill name collision between a local dependency and an external skill: ${collisions.join(", ")}`);
  }
  const local = Array.from(included.values())
    .map((skill) => (skill.requiredBy ? { ...skill, requiredBy: skill.requiredBy.sort() } : skill))
    .sort((left, right) => left.name.localeCompare(right.name));
  return { local, external: keptExternal, excluded: Array.from(excluded).sort() };
}

// External sources and names reach the README as shell commands, so only
// owner/repo sources and plain skill names are accepted.
function requireSafeExternal(external: ExternalSkillSource[]): void {
  for (const entry of external) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._-]*$/.test(entry.source)) {
      fail(`unsupported external skill source for export: ${JSON.stringify(entry.source)} (expected owner/repo)`);
    }
    for (const name of entry.skills) {
      if (!isPathComponentName(name)) {
        fail(`unsupported external skill name for export: ${JSON.stringify(name)}`);
      }
    }
  }
}

// Quotes one POSIX shell argument; plain words stay readable.
export function shellArg(value: string): string {
  return /^[A-Za-z0-9_./=:@-]+$/.test(value) ? value : `'${value.replace(/'/g, "'\\''")}'`;
}

// Mirrors ai-rules/scripts/compose-rules.sh without --with-metadata, in Node
// so setup.ps1 can export without Bash.
export function composeRules(dotfilesRoot: string, overrideName: string): string {
  const rulesDir = path.join(dotfilesRoot, "ai-rules");
  const basePath = path.join(rulesDir, "base", "global.md");
  if (!fs.existsSync(basePath)) {
    fail(`base rule file not found: ${basePath}`);
  }
  const rulesReal = fs.realpathSync(rulesDir);
  requireRealInside(basePath, rulesReal, "base rule file");
  const docs = [fs.readFileSync(basePath, "utf8")];
  const overridePath = path.join(rulesDir, "agents", overrideName);
  if (fs.existsSync(overridePath)) {
    requireRealInside(overridePath, rulesReal, `agent rule file ${overrideName}`);
    const override = fs.readFileSync(overridePath, "utf8");
    if (/\S/.test(override)) {
      docs.push(override);
    }
  }
  return `${docs.join("\n---\n\n")}\n`;
}

// Joins a bundle-relative path onto the staging directory and refuses any
// result outside it, so no write leaves staging.
function stagedPath(staging: string, relative: string): string {
  const target = path.resolve(staging, relative);
  if (!isStrictlyInside(target, staging)) {
    fail(`refusing to write outside the staging directory: ${relative}`);
  }
  return target;
}

function copySkill(sourceDir: string, staging: string, name: string, files: string[]): void {
  for (const relative of skillFiles(sourceDir, name)) {
    const source = path.join(sourceDir, relative);
    const bundlePath = toPosix(path.join("skills", name, relative));
    const target = stagedPath(staging, bundlePath);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(source, target);
    fs.chmodSync(target, fs.statSync(source).mode & 0o777);
    files.push(bundlePath);
  }
}

function readmeText(manifest: BundleManifest, hasNodeScripts: boolean): string {
  const lines: string[] = [];
  const agents = manifest.agents;
  const skillList = manifest.local.map((skill) =>
    skill.origin === "dependency" ? `- \`${skill.name}\` (added because it is linked from ${skill.requiredBy?.map((name) => `\`${name}\``).join(", ")})` : `- \`${skill.name}\``,
  );
  lines.push(
    "# AI Skills Bundle",
    "",
    `Exported from the profiles ${manifest.requestedProfiles.map((name) => `\`${name}\``).join(", ")} for ${agents.map((agent) => `\`${agent}\``).join(" and ")}.`,
    `\`${BUNDLE_MANIFEST}\` records what was selected and every file in this bundle.`,
    "",
    "## Local Skills",
    "",
    ...(skillList.length > 0 ? skillList : ["None."]),
    "",
  );
  if (manifest.local.length > 0) {
    lines.push(
      "Copy every directory under `skills/` into one agent skill directory, side by side.",
      "Skills link to each other relative to their own directory, such as",
      "`../delivery-common/scripts/check-branch-name.mjs`, so keep them together.",
      "",
    );
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
  } else {
    lines.push(
      "These skills are not copied. Install them with the `skills` CLI from their sources; run each command in the",
      "project that should use them, and see `npx skills add --help` for other install locations.",
      "",
      "```sh",
    );
    for (const entry of manifest.external) {
      const args = ["skills", "add", entry.source, ...entry.skills.flatMap((name) => ["--skill", name]), ...agents.flatMap((agent) => ["--agent", agent])];
      lines.push(["npx", ...args.map(shellArg)].join(" "));
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
      lines.push(
        `- Optional: the Codex plugin for Claude Code. By default, ${reviewSkills.map((name) => `\`${name}\``).join(", ")} run in a fresh`,
        "  subagent of the current agent. Only when the user explicitly names Codex for a review do they run it through",
        "  the plugin's `scripts/codex-companion.mjs`; if the plugin is missing, that review reports the failure and stops.",
      );
    }
    lines.push("");
  }
  return `${lines.join("\n").replace(/\n+$/, "")}\n`;
}

interface PersonalMarker {
  kind: string;
  value: string;
  token: string;
}

// Hides marker values in everything export prints.
class Redactor {
  private markers: PersonalMarker[] = [];

  add(markers: PersonalMarker[]): void {
    this.markers = this.markers.concat(markers).sort((left, right) => right.value.length - left.value.length);
  }

  redact(text: string): string {
    let result = text;
    for (const marker of this.markers) {
      const lowered = marker.value.toLowerCase();
      let index = result.toLowerCase().indexOf(lowered);
      while (index !== -1) {
        result = result.slice(0, index) + marker.token + result.slice(index + marker.value.length);
        index = result.toLowerCase().indexOf(lowered, index + marker.token.length);
      }
    }
    return result;
  }
}

function homeVariants(home: string): string[] {
  const variants = new Set<string>();
  const trimmed = home.replace(/[\\/]+$/, "");
  if (trimmed.length <= 2) {
    return [];
  }
  variants.add(trimmed);
  variants.add(trimmed.split("\\").join("/"));
  variants.add(trimmed.split("/").join("\\"));
  return Array.from(variants);
}

function homeMarkers(context: ExportContext): PersonalMarker[] {
  const markers: PersonalMarker[] = [];
  for (const home of new Set([context.home, os.homedir()])) {
    for (const value of homeVariants(home)) {
      markers.push({ kind: "home path", value, token: "<home>" });
    }
  }
  return markers;
}

// An unset key exits 1; anything else means the identity could not be read,
// and the check must not pass without it.
function gitConfig(context: ExportContext, key: string): string {
  let command: string;
  try {
    command = context.gitCommand();
  } catch (error) {
    fail(`cannot read git config ${key}: ${(error as Error).message}`);
  }
  const result = spawnSync(command, ["config", "--get", key], { cwd: context.dotfilesRoot, env: context.env, encoding: "utf8" });
  if (result.error) {
    fail(`cannot read git config ${key}: ${result.error.message}`);
  }
  if (result.status === 1) {
    return "";
  }
  if (result.status !== 0) {
    fail(`cannot read git config ${key}: git exited with status ${result.status ?? result.signal}`);
  }
  return result.stdout.trim();
}

// The default marker file lives under the config home of both the effective
// setup home and the OS home, so a SETUP_HOME override never skips the
// user's own file.
function markerFiles(context: ExportContext): { files: string[]; required: boolean } {
  if (MARKERS_FILE_ENV in context.env) {
    const override = context.env[MARKERS_FILE_ENV] ?? "";
    if (!override) {
      fail(`${MARKERS_FILE_ENV} is set but empty`);
    }
    return { files: [path.resolve(override)], required: true };
  }
  const xdg = context.env.XDG_CONFIG_HOME;
  if (xdg && path.isAbsolute(xdg)) {
    return { files: [path.join(xdg, "dotfiles", "export-personal-markers")], required: false };
  }
  const files = Array.from(new Set([context.home, os.homedir()])).map((home) => path.join(home, ".config", "dotfiles", "export-personal-markers"));
  return { files, required: false };
}

function configuredMarkers(context: ExportContext): PersonalMarker[] {
  const markers: PersonalMarker[] = [];
  for (const key of ["user.name", "user.email"]) {
    const value = gitConfig(context, key);
    if (value) {
      markers.push({ kind: `git ${key}`, value, token: "<redacted>" });
    }
  }
  const { files, required } = markerFiles(context);
  for (const file of files) {
    if (!fs.existsSync(file)) {
      if (required) {
        fail(`${MARKERS_FILE_ENV} names a missing file`);
      }
      continue;
    }
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    lines.forEach((line, index) => {
      const value = line.trim();
      if (value && !value.startsWith("#")) {
        markers.push({ kind: `personal marker on line ${index + 1} of the marker file`, value, token: "<redacted>" });
      }
    });
  }
  return markers;
}

// Decodes a file for scanning. UTF-16 with a byte order mark is decoded as
// such; text with NUL bytes is also scanned as UTF-16; anything that is not
// valid UTF-8 otherwise fails closed rather than skipping the scan.
function textForScan(buffer: Buffer, relative: string): string {
  if (buffer.length >= 2 && buffer[0] === 0xff && buffer[1] === 0xfe) {
    return buffer.subarray(2).toString("utf16le");
  }
  if (buffer.length >= 2 && buffer[0] === 0xfe && buffer[1] === 0xff) {
    return Buffer.from(buffer.subarray(2)).swap16().toString("utf16le");
  }
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(buffer);
  } catch {
    fail(`cannot scan ${relative} for personal data: it is neither UTF-8 nor UTF-16 with a byte order mark`);
  }
  if (buffer.includes(0)) {
    const even = buffer.length - (buffer.length % 2);
    text += `\n${buffer.subarray(0, even).toString("utf16le")}\n${Buffer.from(buffer.subarray(0, even)).swap16().toString("utf16le")}`;
  }
  return text;
}

function checkPersonalData(staging: string, files: string[], markers: PersonalMarker[], redactor: Redactor): void {
  const findings: string[] = [];
  const lowered = markers.map((marker) => ({ kind: marker.kind, value: marker.value.toLowerCase() }));
  for (const relative of files) {
    const text = `${relative}\n${textForScan(fs.readFileSync(stagedPath(staging, relative)), relative)}`.toLowerCase();
    const kinds = new Set(lowered.filter((marker) => text.includes(marker.value)).map((marker) => marker.kind));
    for (const kind of Array.from(kinds).sort()) {
      findings.push(`${redactor.redact(relative)}: ${kind}`);
    }
  }
  if (findings.length > 0) {
    fail(`personal data check failed; nothing was written:\n  ${findings.join("\n  ")}`);
  }
}

// Every relative ../<name>/... reference in a staged skill must resolve inside
// the bundle, either from the referring file or from its skill directory.
function checkStagedLinks(staging: string, files: string[]): void {
  const skillsRoot = path.join(staging, "skills");
  const pattern = /((?:\.\.\/)+)([A-Za-z0-9_][A-Za-z0-9._-]*)\/([A-Za-z0-9._/-]*)/g;
  const unresolved: string[] = [];
  for (const relative of files.filter((file) => file.startsWith("skills/"))) {
    const [, skillName] = relative.split("/");
    const file = stagedPath(staging, relative);
    const text = textForScan(fs.readFileSync(file), relative);
    for (const match of text.matchAll(pattern)) {
      const ups = match[1] ?? "";
      const name = match[2] ?? "";
      const rest = (match[3] ?? "").replace(/[./]+$/, "");
      const target = rest ? `${name}/${rest}` : name;
      const candidates = [path.resolve(path.dirname(file), `${ups}${target}`), path.resolve(skillsRoot, target)];
      if (skillName && ups === "../") {
        candidates.push(path.resolve(skillsRoot, skillName, target));
      }
      if (!candidates.some((candidate) => isInsideOrSame(candidate, skillsRoot) && fs.existsSync(candidate))) {
        unresolved.push(`${relative} -> ${ups}${target}`);
      }
    }
  }
  if (unresolved.length > 0) {
    fail(`relative links in the bundle do not resolve inside it:\n  ${Array.from(new Set(unresolved)).join("\n  ")}`);
  }
}

function isGeneratedPath(file: string): boolean {
  if (TOP_LEVEL_FILES.has(file)) {
    return true;
  }
  const parts = file.split("/");
  return (
    parts.length >= 3 &&
    parts[0] === "skills" &&
    isPathComponentName(parts[1] ?? "") &&
    parts.every((part) => part !== "" && part !== "." && part !== ".." && !/[\\:\0]/.test(part))
  );
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

// Accepts only a manifest this export version writes, with file paths it can
// generate; anything else is not a previous bundle.
function validManifestFiles(value: unknown): string[] | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }
  const record = value as Record<string, unknown>;
  const local = record.local;
  const external = record.external;
  const files = record.files;
  const valid =
    record.schemaVersion === SCHEMA_VERSION &&
    record.generatedBy === GENERATED_BY &&
    isStringArray(record.requestedProfiles) &&
    isStringArray(record.expandedProfiles) &&
    isStringArray(record.agents) &&
    record.agents.every((agent) => agent === "codex" || agent === "claude-code") &&
    isStringArray(record.excluded) &&
    isStringArray(record.rules) &&
    record.rules.every((rule) => rule === "AGENTS.md" || rule === "CLAUDE.md") &&
    Array.isArray(local) &&
    local.every(
      (skill) =>
        skill &&
        typeof skill === "object" &&
        isPathComponentName(String((skill as Record<string, unknown>).name)) &&
        ["profile", "dependency"].includes(String((skill as Record<string, unknown>).origin)),
    ) &&
    Array.isArray(external) &&
    external.every((entry) => entry && typeof entry === "object" && typeof (entry as Record<string, unknown>).source === "string" && isStringArray((entry as Record<string, unknown>).skills)) &&
    isStringArray(files) &&
    new Set(files).size === files.length &&
    files.includes(BUNDLE_MANIFEST) &&
    files.every(isGeneratedPath);
  return valid ? (files as string[]) : undefined;
}

function listEntries(directory: string): { files: string[]; others: string[] } {
  const files: string[] = [];
  const others: string[] = [];
  function walk(relativeDir: string): void {
    for (const entry of fs.readdirSync(path.join(directory, relativeDir), { withFileTypes: true })) {
      const relative = toPosix(path.join(relativeDir, entry.name));
      if (entry.isDirectory()) {
        const before = files.length + others.length;
        walk(relative);
        if (files.length + others.length === before) {
          others.push(`${relative}/`);
        }
      } else if (entry.isFile()) {
        files.push(relative);
      } else {
        others.push(relative);
      }
    }
  }
  walk("");
  return { files, others };
}

// Returns the entries of a previous bundle that its manifest does not list.
function bundleExtras(directory: string): string[] | undefined {
  let manifest: unknown;
  try {
    manifest = JSON.parse(fs.readFileSync(path.join(directory, BUNDLE_MANIFEST), "utf8"));
  } catch {
    return undefined;
  }
  const listed = validManifestFiles(manifest);
  if (!listed) {
    return undefined;
  }
  const allowed = new Set(listed);
  const { files, others } = listEntries(directory);
  return files.filter((file) => !allowed.has(file)).concat(others).sort();
}

type OutState = { kind: "absent" } | { kind: "empty" } | { kind: "bundle" };

// --force replaces only a previous bundle: a directory whose manifest lists
// every file in it. Anything else is refused, even with --force, so export
// never deletes files it did not write.
function inspectOut(out: string, force: boolean): OutState {
  const stat = fs.lstatSync(out, { throwIfNoEntry: false });
  if (!stat) {
    return { kind: "absent" };
  }
  if (stat.isSymbolicLink()) {
    fail(`output path is a symbolic link: ${out}`);
  }
  if (!stat.isDirectory()) {
    fail(`output path is not a directory: ${out}`);
  }
  if (fs.readdirSync(out).length === 0) {
    return { kind: "empty" };
  }
  if (!force) {
    fail(`output directory is not empty: ${out} (use --force to replace a previous skills bundle)`);
  }
  requirePreviousBundle(out, out);
  return { kind: "bundle" };
}

function requirePreviousBundle(directory: string, out: string): void {
  const extras = bundleExtras(directory);
  if (!extras) {
    fail(`--force replaces only a previous skills bundle, and ${out} has no valid ${BUNDLE_MANIFEST} (schema version ${SCHEMA_VERSION})`);
  }
  if (extras.length > 0) {
    fail(`refusing to replace ${out}: entries not written by skills export: ${extras.join(", ")}`);
  }
}

function uniqueSibling(out: string, label: string): string {
  return path.join(path.dirname(out), `.${path.basename(out)}.${label}-${process.pid}-${Date.now()}`);
}

// Moves an existing --out aside, rechecks exactly what was moved, and only
// then puts the new bundle in place. Until the new bundle is in place, any
// failure moves the old directory back.
function install(staging: string, out: string, state: OutState, say: (message: string) => void): void {
  if (state.kind === "absent") {
    fs.renameSync(staging, out);
    return;
  }
  const previous = uniqueSibling(out, "previous");
  fs.renameSync(out, previous);
  try {
    if (state.kind === "empty") {
      const entries = fs.readdirSync(previous);
      if (entries.length > 0) {
        fail(`refusing to replace ${out}: entries appeared during export: ${entries.sort().join(", ")}`);
      }
    } else {
      requirePreviousBundle(previous, out);
    }
    fs.renameSync(staging, out);
  } catch (error) {
    try {
      fs.renameSync(previous, out);
    } catch (restoreError) {
      fail(`${(error as Error).message}\nthe previous output could not be moved back and remains at ${previous}: ${(restoreError as Error).message}`);
    }
    throw error;
  }
  try {
    fs.rmSync(previous, { recursive: true, force: false });
  } catch (error) {
    say(`Warning: the new bundle is installed at ${out}, but the previous one could not be removed and remains at ${previous}: ${(error as Error).message}`);
  }
}

export function exportSkills(options: ExportOptions, context: ExportContext): void {
  const redactor = new Redactor();
  const home = homeMarkers(context);
  redactor.add(home);
  const say = (message: string): void => console.log(redactor.redact(message));
  try {
    const markers = home.concat(configuredMarkers(context));
    redactor.add(markers.filter((marker) => !home.includes(marker)));
    runExport(options, context, markers, redactor, say);
  } catch (error) {
    fail(redactor.redact((error as Error).message));
  }
}

function runExport(options: ExportOptions, context: ExportContext, markers: PersonalMarker[], redactor: Redactor, say: (message: string) => void): void {
  const out = path.resolve(options.out);
  const dotfilesReal = fs.realpathSync(context.dotfilesRoot);
  const outReal = realPathOfPossiblyMissing(out);
  if (isInsideOrSame(outReal, dotfilesReal) || isInsideOrSame(dotfilesReal, outReal)) {
    fail(`output directory must be outside the dotfiles repository: ${out}`);
  }

  const localDir = path.join(context.dotfilesRoot, "skills", "local");
  const localReal = requireRealInside(localDir, dotfilesReal, "skills/local");
  const profilesDir = path.join(context.dotfilesRoot, "skills", "profiles");
  const profilesReal = requireRealInside(profilesDir, dotfilesReal, "skills/profiles");
  const plan = resolveProfiles(context.dotfilesRoot, options.profiles, options.agents, "export");
  for (const name of plan.expandedProfiles) {
    requireRealInside(path.join(profilesDir, `${name}.json`), profilesReal, `profile ${name}`);
  }
  requireSafeExternal(plan.external);
  const selection = selectSkills(
    localDir,
    localReal,
    plan.local.map((skill) => skill.name),
    plan.external,
    options.exclude,
  );
  const state = inspectOut(out, options.force);
  const rules = RULES_TARGETS.filter((target) => options.agents.includes(target.agent));
  const dependencies = selection.local.filter((skill) => skill.origin === "dependency");

  say(`Local skills: ${selection.local.map((skill) => skill.name).join(", ") || "none"}`);
  for (const skill of dependencies) {
    say(`Added as a dependency: ${skill.name} (required by ${skill.requiredBy?.join(", ")})`);
  }
  if (selection.excluded.length > 0) {
    say(`Excluded: ${selection.excluded.join(", ")}`);
  }
  say(`External skills recorded: ${selection.external.flatMap((entry) => entry.skills).length}`);

  if (context.dryRun) {
    say(`DRY-RUN write skills bundle ${out}`);
    return;
  }

  fs.mkdirSync(path.dirname(out), { recursive: true });
  const staging = fs.realpathSync(fs.mkdtempSync(path.join(path.dirname(out), `.${path.basename(out)}.staging-`)));
  let installed = false;
  try {
    const files: string[] = [];
    for (const skill of selection.local) {
      copySkill(requireSkillRoot(localDir, localReal, skill.name), staging, skill.name, files);
    }
    for (const target of rules) {
      fs.writeFileSync(stagedPath(staging, target.file), composeRules(context.dotfilesRoot, target.override));
      files.push(target.file);
    }
    files.push("README.md", BUNDLE_MANIFEST);
    files.sort();

    const manifest: BundleManifest = {
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
    fs.writeFileSync(stagedPath(staging, "README.md"), readmeText(manifest, hasNodeScripts));
    fs.writeFileSync(stagedPath(staging, BUNDLE_MANIFEST), `${JSON.stringify(manifest, null, 2)}\n`);

    checkPersonalData(staging, files, markers, redactor);
    checkStagedLinks(staging, files);
    fs.chmodSync(staging, 0o777 & ~process.umask());
    install(staging, out, state, (message) => console.warn(redactor.redact(message)));
    installed = true;
  } finally {
    if (!installed) {
      fs.rmSync(staging, { recursive: true, force: true });
    }
  }
  say(`Skills bundle written: ${out}`);
}
