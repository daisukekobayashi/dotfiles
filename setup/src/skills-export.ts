import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { type Agent, type ExternalSkillSource, csv, fail, isPathComponentName, parseAgents, resolveProfiles } from "./skill-profiles";

// Writes a self-contained bundle of profile-selected local skills, the local
// skills they link to, a record of external skills, and composed agent rules.
// See docs/skills-profiles.md "Export", including its threat model: the
// operator and the checkout are trusted; the guards here catch operator
// mistakes, broken bundles, and personal data leaving in a bundle.

export const BUNDLE_MANIFEST = "skills-bundle.json";
const GENERATED_BY = "dotfiles setup skills export";
const SCHEMA_VERSION = 1;
const MARKERS_FILE_ENV = "SETUP_EXPORT_PERSONAL_MARKERS_FILE";
const SOURCE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._-]*$/;

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

const RULES_TARGETS: { agent: Agent; file: string; override: string }[] = [
  { agent: "codex", file: "AGENTS.md", override: "codex.md" },
  { agent: "claude-code", file: "CLAUDE.md", override: "claude.md" },
];

function unique<T>(values: T[]): T[] {
  return Array.from(new Set(values));
}

export function parseExportArgs(argv: string[]): ExportOptions {
  let profiles = "";
  let out = "";
  let force = false;
  const agentArgs: string[] = [];
  const exclude: string[] = [];
  let index = 0;

  // A following option is a missing value, not the value; a literal path
  // that starts with -- can be written as ./--name.
  function value(flag: string): string {
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      fail(`${flag} requires a value`);
    }
    return next;
  }

  while (index < argv.length) {
    const item = argv[index];
    if (item === "--force") {
      force = true;
      index += 1;
      continue;
    }
    if (item === "--profile") {
      profiles = value(item);
    } else if (item === "--agent") {
      agentArgs.push(value(item));
    } else if (item === "--exclude") {
      exclude.push(...csv(value(item)));
    } else if (item === "--out") {
      out = value(item);
    } else {
      fail(`Unknown skills export argument: ${item}`);
    }
    index += 2;
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
  return { profiles: unique(csv(profiles)), agents, exclude: unique(exclude), out, force };
}

function toPosix(relative: string): string {
  return relative.split(path.sep).join("/");
}

// Judges ".." by path component, so a child named "..share" stays inside.
function isInsideOrSame(candidate: string, root: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

// Resolves --out the way the filesystem does: each existing component is
// resolved, links included, before a following ".." applies. Components past
// the first missing one are appended as written and may not contain "..".
function physicalPath(target: string): string {
  const absolute = path.isAbsolute(target) ? target : `${process.cwd()}${path.sep}${target}`;
  const root = path.parse(absolute).root;
  let current = fs.realpathSync(root);
  let missing = false;
  for (const part of absolute.slice(root.length).split(/[\\/]+/)) {
    if (part === "" || part === ".") {
      continue;
    }
    if (part === "..") {
      if (missing) {
        fail(`output path has ".." after a directory that does not exist: ${target}`);
      }
      current = path.dirname(current);
      continue;
    }
    const next = path.join(current, part);
    if (!missing && fs.lstatSync(next, { throwIfNoEntry: false })) {
      current = fs.realpathSync(next);
    } else {
      missing = true;
      current = next;
    }
  }
  return current;
}

function sameEntry(left: fs.Stats, right: fs.Stats): boolean {
  return left.dev === right.dev && left.ino === right.ino;
}

// Compares filesystem identities rather than strings, so another spelling of
// the checkout, such as a different letter case on a case-insensitive volume,
// is still recognized.
function requireOutsideCheckout(out: string, dotfilesRoot: string): void {
  const checkout = fs.statSync(dotfilesRoot);
  const outStat = fs.statSync(out, { throwIfNoEntry: false });
  for (let current = out; ; current = path.dirname(current)) {
    const stat = fs.statSync(current, { throwIfNoEntry: false });
    if (stat && sameEntry(stat, checkout)) {
      fail(`output directory must be outside the dotfiles repository: ${out}`);
    }
    if (path.dirname(current) === current) {
      break;
    }
  }
  for (let current = fs.realpathSync(dotfilesRoot); outStat; current = path.dirname(current)) {
    if (sameEntry(fs.statSync(current), outStat)) {
      fail(`output directory must be outside the dotfiles repository: ${out}`);
    }
    if (path.dirname(current) === current) {
      break;
    }
  }
}

// Source paths below the checkout root must be real directories or files,
// never links, and resolve inside the checkout, so a link cannot bring other
// files into a bundle. Checked before anything under them is read.
function requireSourcePath(dotfilesRoot: string, relative: string, kind: "directory" | "file"): string {
  const parts = relative.split("/");
  let current = dotfilesRoot;
  for (const [index, part] of parts.entries()) {
    current = path.join(current, part);
    const stat = fs.lstatSync(current, { throwIfNoEntry: false });
    const shown = parts.slice(0, index + 1).join("/");
    if (!stat) {
      fail(`${shown} not found in the dotfiles repository`);
    }
    if (stat.isSymbolicLink()) {
      fail(`${shown} is a symbolic link; export reads only real files in the dotfiles repository`);
    }
    const wantDirectory = index < parts.length - 1 || kind === "directory";
    if (wantDirectory ? !stat.isDirectory() : !stat.isFile()) {
      fail(`${shown} is not a ${wantDirectory ? "directory" : "file"}`);
    }
  }
  if (!isInsideOrSame(fs.realpathSync(current), fs.realpathSync(dotfilesRoot))) {
    fail(`${relative} resolves outside the dotfiles repository`);
  }
  return current;
}

// Reads text that must be strict UTF-8 without NUL; anything else, such as
// UTF-16 or binary data, fails the export rather than going unscanned.
function decodeText(bytes: Buffer, label: string, keepBom = false): string {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: keepBom }).decode(bytes);
  } catch {
    fail(`cannot read ${label}: it is not UTF-8 text`);
  }
  if (text.includes("\0")) {
    fail(`cannot read ${label}: it contains NUL characters`);
  }
  return text;
}

function readText(file: string, label: string): string {
  return decodeText(fs.readFileSync(file), label);
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
      if (entry.isDirectory()) {
        walk(relative);
      } else if (entry.isFile()) {
        files.push(relative);
      } else {
        fail(`local skill ${skillName} contains a symbolic link or special file: ${toPosix(relative)}`);
      }
    }
  }
  walk("");
  return files;
}

// Relative references such as `../delivery-common/scripts/x.mjs` or
// [guide](../beta/references/guide%20one.md). A reference starts with ../
// after a delimiter, names a path whose first component starts with a letter,
// digit, "_", or "%" (skill names never start with "."), and runs to the next
// delimiter; trailing sentence punctuation and #anchors are not part of it.
const REFERENCE_PATTERN = /(?<![^\s`'"()[\]<>{}|*=:])(?:\.\.\/)+(?=[\p{L}\p{N}_%])[^\s`'"()[\]<>{}|*]*/gu;

export function parseReferences(text: string): string[] {
  const references: string[] = [];
  for (const match of text.matchAll(REFERENCE_PATTERN)) {
    let reference = match[0].replace(/#.*$/, "");
    while (/[,;:!?]$/.test(reference) || (reference.endsWith(".") && !/(^|\/)\.\.?$/.test(reference))) {
      reference = reference.slice(0, -1);
    }
    if (reference.split("/").some((part) => part !== "" && part !== "..")) {
      references.push(reference);
    }
  }
  return references;
}

// Resolves a reference from its file's directory one component at a time, so
// a missing component cannot be hidden by a later "..". A %-encoded reference
// also resolves through its decoded form. Returns undefined when nothing
// exists at the written path.
export function resolveReference(fromDir: string, reference: string): string | undefined {
  const forms = [reference];
  try {
    const decoded = decodeURIComponent(reference);
    if (decoded !== reference) {
      forms.push(decoded);
    }
  } catch {
    // Not valid percent-encoding; only the literal form applies.
  }
  // Every component followed by anything, even a trailing "/" or "..", must
  // be a directory, as the operating system requires.
  const resolve = (form: string): string | undefined => {
    let current = fromDir;
    const parts = form.split("/");
    for (const [index, part] of parts.entries()) {
      if (part === "" || part === ".") {
        continue;
      }
      current = part === ".." ? path.dirname(current) : path.join(current, part);
      const stat = fs.statSync(current, { throwIfNoEntry: false });
      if (!stat || (index < parts.length - 1 && !stat.isDirectory())) {
        return undefined;
      }
    }
    return current;
  };
  for (const form of forms) {
    const resolved = resolve(form);
    if (resolved) {
      return resolved;
    }
  }
  return undefined;
}

interface Sources {
  root: string;
  localDir: string;
}

// A selected skill root must be a real directory inside skills/local.
// Every exported skill, selected or added as a dependency, needs SKILL.md.
function requireSkillRoot(sources: Sources, name: string): string {
  if (!fs.lstatSync(path.join(sources.localDir, name), { throwIfNoEntry: false })) {
    fail(`unknown local skill ${name}`);
  }
  const skillDir = requireSourcePath(sources.root, `skills/local/${name}`, "directory");
  if (!fs.lstatSync(path.join(skillDir, "SKILL.md"), { throwIfNoEntry: false })?.isFile()) {
    fail(`local skill ${name} has no SKILL.md file`);
  }
  return skillDir;
}

// A skill depends on another local skill when a reference in one of its files
// resolves into that skill. Bare skill names in prose are not dependencies.
function skillDependencies(sources: Sources, skillDir: string, skillName: string): Set<string> {
  const dependencies = new Set<string>();
  for (const relative of skillFiles(skillDir, skillName)) {
    const file = path.join(skillDir, relative);
    for (const reference of parseReferences(readText(file, `skills/${skillName}/${toPosix(relative)}`))) {
      const resolved = resolveReference(path.dirname(file), reference);
      if (resolved && isInsideOrSame(resolved, sources.localDir) && resolved !== sources.localDir) {
        const target = path.relative(sources.localDir, resolved).split(path.sep)[0] ?? "";
        if (target !== skillName && isPathComponentName(target) && fs.statSync(path.join(sources.localDir, target)).isDirectory()) {
          dependencies.add(target);
        }
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

function selectSkills(sources: Sources, profileLocal: string[], external: ExternalSkillSource[], exclude: string[]): Selection {
  const excluded = new Set(exclude);
  const included = new Map<string, BundleSkill>();
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
    for (const dependency of Array.from(skillDependencies(sources, requireSkillRoot(sources, name), name)).sort()) {
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
    if (!SOURCE_PATTERN.test(entry.source)) {
      fail(`unsupported external skill source for export: ${entry.source} (expected owner/repo)`);
    }
    for (const name of entry.skills) {
      if (!isPathComponentName(name)) {
        fail(`unsupported external skill name for export: ${name}`);
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
function composeRules(dotfilesRoot: string, overrideName: string): string {
  // A byte order mark stays, as compose-rules.sh copies bytes unchanged.
  const read = (relative: string): string => decodeText(fs.readFileSync(requireSourcePath(dotfilesRoot, relative, "file")), relative, true);
  const docs = [read("ai-rules/base/global.md")];
  const overrideRelative = `ai-rules/agents/${overrideName}`;
  if (fs.lstatSync(path.join(dotfilesRoot, overrideRelative), { throwIfNoEntry: false })) {
    const override = read(overrideRelative);
    if (/\S/.test(override)) {
      docs.push(override);
    }
  }
  return `${docs.join("\n---\n\n")}\n`;
}

function readmeText(manifest: BundleManifest, hasNodeScripts: boolean): string {
  const agents = manifest.agents;
  const quoted = (names: string[]): string => names.map((name) => `\`${name}\``).join(", ");
  const lines: string[] = [
    "# AI Skills Bundle",
    "",
    `Exported from the profiles ${quoted(manifest.requestedProfiles)} for ${agents.map((agent) => `\`${agent}\``).join(" and ")}.`,
    `\`${BUNDLE_MANIFEST}\` records what was selected and every file in this bundle.`,
    "",
    "## Local Skills",
    "",
  ];
  if (manifest.local.length === 0) {
    lines.push("None.", "");
  } else {
    for (const skill of manifest.local) {
      lines.push(skill.requiredBy ? `- \`${skill.name}\` (added because it is linked from ${quoted(skill.requiredBy)})` : `- \`${skill.name}\``);
    }
    lines.push(
      "",
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
  lines.push("", "Merge with your existing rules instead of overwriting them.", "", "## External Skills", "");

  if (manifest.external.length === 0) {
    lines.push("None.", "");
  } else {
    lines.push(
      "These skills are not copied. Install them with the `skills` CLI from a new, empty directory outside any",
      "project, such as one made with `mktemp -d`. `npx` resolves commands and npm settings from its current",
      "directory, so running it inside a project can run code that project provides; dotfiles setup isolates its",
      `own installs the same way. The commands write ${agents.map((agent) => (agent === "codex" ? "`.agents/skills/`" : "`.claude/skills/`")).join(" and ")} in that`,
      "directory; copy the installed skill directories next to the skills from this bundle.",
      "",
      "```sh",
      'cd "$(mktemp -d)"',
    );
    for (const entry of manifest.external) {
      const args = ["skills", "add", entry.source, ...entry.skills.flatMap((name) => ["--skill", name]), ...agents.flatMap((agent) => ["--agent", agent]), "--copy"];
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
        `- Optional: the Codex plugin for Claude Code. By default, ${quoted(reviewSkills)} run in a fresh`,
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
  pattern: RegExp;
  token: string;
}

// One case-insensitive matcher per marker serves both the personal data check
// and redaction, so anything the check detects is also redacted.
class Markers {
  private list: PersonalMarker[] = [];
  add(kind: string, value: string, token: string): void {
    this.list.push({ kind, pattern: new RegExp(value.replace(/[\\^$.*+?()[\]{}|/]/g, "\\$&"), "giu"), token });
    this.list.sort((left, right) => right.pattern.source.length - left.pattern.source.length);
  }

  kindsIn(text: string): string[] {
    return unique(this.list.filter((marker) => text.search(marker.pattern) !== -1).map((marker) => marker.kind)).sort();
  }

  redact(text: string): string {
    return this.list.reduce((result, marker) => result.replace(marker.pattern, marker.token), text);
  }
}

// The homes setup may use: the effective setup home, HOME, USERPROFILE,
// setup.ps1's CUSTOM_HOME, and the OS home.
function homes(context: ExportContext): string[] {
  return unique([context.home, context.env.HOME, context.env.USERPROFILE, context.env.CUSTOM_HOME, os.homedir()].filter((home): home is string => Boolean(home)));
}

// Each home is matched with either separator, and as written escaped in JSON
// or JavaScript (doubled backslashes, escaped slashes).
function addHomeMarkers(markers: Markers, context: ExportContext): void {
  for (const home of homes(context)) {
    const trimmed = home.replace(/[\\/]+$/, "");
    if (trimmed.length > 2) {
      const slashed = trimmed.split("\\").join("/");
      const backslashed = trimmed.split("/").join("\\");
      for (const value of unique([slashed, backslashed, backslashed.split("\\").join("\\\\"), slashed.split("/").join("\\/")])) {
        markers.add("home path", value, "<home>");
      }
    }
  }
}

// Variables that point git at another repository or inject configuration
// would read some other identity, so the lookup runs without them: it reads
// the dotfiles repository's own config plus global and system config.
function gitEnvironment(env: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  const cleaned = { ...env };
  for (const key of Object.keys(cleaned)) {
    if (/^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE|OBJECT_DIRECTORY|NAMESPACE|CONFIG|CONFIG_PARAMETERS|CONFIG_COUNT|CONFIG_KEY_\d+|CONFIG_VALUE_\d+)$/.test(key)) {
      delete cleaned[key];
    }
  }
  return cleaned;
}

// An unset key exits 1; anything else means the identity could not be read,
// and the check must not pass without it.
function gitConfig(context: ExportContext, key: string): string {
  const result = spawnSync(context.gitCommand(), ["config", "--get", key], { cwd: context.dotfilesRoot, env: gitEnvironment(context.env), encoding: "utf8" });
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
// user's own file. Each value is registered as soon as it is known, so a
// later error cannot print it.
function addConfiguredMarkers(markers: Markers, context: ExportContext): void {
  for (const key of ["user.name", "user.email"]) {
    let value: string;
    try {
      value = gitConfig(context, key);
    } catch (error) {
      fail(`cannot read git config ${key}: ${(error as Error).message.replace(/^cannot read git config \S+: /, "")}`);
    }
    if (value) {
      markers.add(`git ${key}`, value, "<redacted>");
    }
  }

  // Errors name only the file's role and the error code, never its path.
  let files: string[];
  let required = false;
  if (MARKERS_FILE_ENV in context.env) {
    const override = context.env[MARKERS_FILE_ENV] ?? "";
    if (!override) {
      fail(`${MARKERS_FILE_ENV} is set but empty`);
    }
    files = [path.resolve(override)];
    required = true;
  } else if (context.env.XDG_CONFIG_HOME && path.isAbsolute(context.env.XDG_CONFIG_HOME)) {
    files = [path.join(context.env.XDG_CONFIG_HOME, "dotfiles", "export-personal-markers")];
  } else {
    files = homes(context).map((home) => path.join(home, ".config", "dotfiles", "export-personal-markers"));
  }
  const role = required ? "override personal marker file" : "default personal marker file";
  for (const file of files) {
    // Only a missing entry is skipped; a broken link or unreadable file fails.
    if (!fs.lstatSync(file, { throwIfNoEntry: false })) {
      if (required) {
        fail(`${MARKERS_FILE_ENV} names a missing file`);
      }
      continue;
    }
    let bytes: Buffer;
    try {
      if (!fs.statSync(file).isFile()) {
        fail(`the ${role} is not a regular file`);
      }
      bytes = fs.readFileSync(file);
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      fail(code ? `cannot read the ${role}: ${code}` : (error as Error).message);
    }
    decodeText(bytes, `the ${role}`)
      .split(/\r?\n/)
      .forEach((line, index) => {
        const value = line.trim();
        if (value && !value.startsWith("#")) {
          markers.add(`personal marker on line ${index + 1} of the marker file`, value, "<redacted>");
        }
      });
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isNameList(value: unknown, nonEmpty: boolean): value is string[] {
  return Array.isArray(value) && (!nonEmpty || value.length > 0) && value.every((item) => typeof item === "string" && isPathComponentName(item)) && unique(value).length === value.length;
}

function sameList(left: unknown, right: string[]): boolean {
  return Array.isArray(left) && left.length === right.length && left.every((item, index) => item === right[index]);
}

// The single definition of a valid manifest. Export checks its own manifest
// with it before writing, and --force accepts a previous bundle only when its
// manifest passes, so every bundle export writes can be replaced later.
function manifestProblem(value: unknown): string | undefined {
  if (!isRecord(value)) {
    return "not a JSON object";
  }
  const keys = ["schemaVersion", "generatedBy", "requestedProfiles", "expandedProfiles", "agents", "local", "excluded", "external", "rules", "files"];
  if (Object.keys(value).length !== keys.length || !keys.every((key) => key in value)) {
    return "unexpected or missing fields";
  }
  const { requestedProfiles, expandedProfiles, agents, local, excluded, external, rules, files } = value;
  if (value.schemaVersion !== SCHEMA_VERSION || value.generatedBy !== GENERATED_BY) {
    return `not a schema version ${SCHEMA_VERSION} skills export manifest`;
  }
  if (!isNameList(requestedProfiles, true) || !isNameList(expandedProfiles, true) || !requestedProfiles.every((name) => expandedProfiles.includes(name))) {
    return "invalid profiles";
  }
  if (!Array.isArray(agents) || agents.length === 0 || unique(agents).length !== agents.length || !agents.every((agent) => RULES_TARGETS.some((target) => target.agent === agent))) {
    return "invalid agents";
  }
  const expectedRules = RULES_TARGETS.filter((target) => agents.includes(target.agent)).map((target) => target.file);
  if (!sameList(rules, expectedRules)) {
    return "rules do not match agents";
  }
  if (!Array.isArray(local) || !local.every(isRecord)) {
    return "invalid local skills";
  }
  const names = local.map((skill) => skill.name);
  if (!isNameList(names, false)) {
    return "invalid local skill names";
  }
  for (const skill of local) {
    const { origin, requiredBy } = skill;
    const valid =
      origin === "profile"
        ? Object.keys(skill).length === 2 && "origin" in skill
        : origin === "dependency" && Object.keys(skill).length === 3 && isNameList(requiredBy, true) && requiredBy.every((name) => names.includes(name));
    if (!valid) {
      return `invalid local skill ${String(skill.name)}`;
    }
  }
  if (!isNameList(excluded, false) || excluded.some((name) => names.includes(name))) {
    return "invalid excluded skills";
  }
  if (
    !Array.isArray(external) ||
    !external.every((entry) => isRecord(entry) && Object.keys(entry).length === 2 && typeof entry.source === "string" && SOURCE_PATTERN.test(entry.source) && isNameList(entry.skills, true))
  ) {
    return "invalid external skills";
  }
  if (!Array.isArray(files) || !files.every((file) => typeof file === "string") || unique(files).length !== files.length) {
    return "invalid files";
  }
  const topLevel = ["README.md", BUNDLE_MANIFEST, ...expectedRules];
  if (!topLevel.every((file) => files.includes(file))) {
    return "missing bundle files";
  }
  for (const file of files as string[]) {
    const parts = file.split("/");
    const skillFile = parts.length >= 3 && parts[0] === "skills" && names.includes(parts[1]) && parts[2] !== "evals" && parts.every((part) => part !== "" && part !== "." && part !== ".." && !part.includes("\0"));
    if (!topLevel.includes(file) && !skillFile) {
      return `a file export would not write: ${file}`;
    }
  }
  return undefined;
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

// Checks that a directory holds a previous bundle and returns the files seen
// in it; fails, naming them, when it holds anything the manifest does not list.
function requirePreviousBundle(directory: string, out: string): string[] {
  const manifestPath = path.join(directory, BUNDLE_MANIFEST);
  let problem = "it has no regular manifest file";
  if (fs.lstatSync(manifestPath, { throwIfNoEntry: false })?.isFile()) {
    try {
      problem = manifestProblem(JSON.parse(fs.readFileSync(manifestPath, "utf8"))) ?? "";
    } catch {
      problem = "the manifest is not valid JSON";
    }
  }
  if (problem) {
    fail(`--force replaces only a previous skills bundle, and ${out} has no valid ${BUNDLE_MANIFEST} (${problem})`);
  }
  const listed = new Set((JSON.parse(fs.readFileSync(manifestPath, "utf8")) as BundleManifest).files);
  const { files, others } = listEntries(directory);
  const extras = files.filter((file) => !listed.has(file)).concat(others).sort();
  if (extras.length > 0) {
    fail(`refusing to replace ${out}: entries not written by skills export: ${extras.join(", ")}`);
  }
  return files;
}

type OutState = "absent" | "empty" | "bundle";

// --force replaces only a previous bundle, so export never deletes files it
// did not write.
function inspectOut(out: string, force: boolean): OutState {
  const stat = fs.lstatSync(out, { throwIfNoEntry: false });
  if (!stat) {
    return "absent";
  }
  if (!stat.isDirectory()) {
    fail(`output path is not a directory: ${out}`);
  }
  if (fs.readdirSync(out).length === 0) {
    return "empty";
  }
  if (!force) {
    fail(`output directory is not empty: ${out} (use --force to replace a previous skills bundle)`);
  }
  requirePreviousBundle(out, out);
  return "bundle";
}

// Writing next to --out in a directory others can change is almost always a
// mistaken path, so export refuses a parent writable by others without the
// sticky bit, or owned and writable by another user other than root.
function requireSafeParent(out: string): void {
  if (process.platform === "win32" || typeof process.getuid !== "function") {
    return;
  }
  const parent = path.dirname(out);
  const stat = fs.statSync(parent);
  if ((stat.mode & 0o002) !== 0 && (stat.mode & 0o1000) === 0) {
    fail(`refusing to export into ${parent}: other users can write to it and it has no sticky bit`);
  }
  if (stat.uid !== process.getuid() && stat.uid !== 0 && (stat.mode & 0o200) !== 0) {
    fail(`refusing to export into ${parent}: it is owned and writable by another user`);
  }
}

// Removes the files seen in the old directory, then the directories that
// become empty; anything else stays. Returns false when something remains.
function removeSeen(previous: string, files: string[]): boolean {
  const directories = new Set<string>([""]);
  for (const file of files) {
    try {
      fs.unlinkSync(path.join(previous, ...file.split("/")));
    } catch {
      // Already gone or no longer a file; whatever is there stays.
    }
    const parts = file.split("/");
    for (let depth = 1; depth < parts.length; depth += 1) {
      directories.add(parts.slice(0, depth).join("/"));
    }
  }
  for (const directory of Array.from(directories).sort((left, right) => right.split("/").length - left.split("/").length || right.length - left.length)) {
    try {
      fs.rmdirSync(path.join(previous, ...directory.split("/").filter(Boolean)));
    } catch {
      // Not empty: something the check did not see; leave it.
    }
  }
  return !fs.existsSync(previous);
}

// Short work names beside --out, so they fit in any directory that holds
// a valid --out name.
function workName(out: string, kind: "s" | "b"): string {
  return path.join(path.dirname(out), `.skx-${kind}${randomBytes(4).toString("hex")}`);
}

// Moves an existing --out aside, rechecks it, and puts the new bundle in
// place; until then any failure moves the old directory back.
function install(staging: string, out: string, state: OutState, warn: (message: string) => void): void {
  if (state === "absent") {
    fs.renameSync(staging, out);
    return;
  }
  const previous = workName(out, "b");
  fs.renameSync(out, previous);
  let seen: string[] = [];
  try {
    if (state === "bundle") {
      seen = requirePreviousBundle(previous, out);
    } else if (fs.readdirSync(previous).length > 0) {
      fail(`refusing to replace ${out}: it is no longer empty`);
    }
    fs.renameSync(staging, out);
  } catch (error) {
    fs.renameSync(previous, out);
    throw error;
  }
  if (!removeSeen(previous, seen)) {
    warn(`Warning: the new bundle is installed at ${out}, but the previous one was not fully removed and remains at ${previous}`);
  }
}

// Loads the personal markers before anything else, so no message, including
// an argument error, can print a marker value.
export function runExportCommand(argv: string[], context: ExportContext): void {
  const markers = new Markers();
  addHomeMarkers(markers, context);
  try {
    addConfiguredMarkers(markers, context);
    runExport(parseExportArgs(argv), context, markers);
  } catch (error) {
    fail(markers.redact((error as Error).message));
  }
}

function runExport(options: ExportOptions, context: ExportContext, markers: Markers): void {
  const say = (message: string): void => console.log(markers.redact(message));
  const out = physicalPath(options.out);
  requireOutsideCheckout(out, context.dotfilesRoot);

  const sources: Sources = { root: context.dotfilesRoot, localDir: requireSourcePath(context.dotfilesRoot, "skills/local", "directory") };
  requireSourcePath(context.dotfilesRoot, "skills/profiles", "directory");
  const plan = resolveProfiles(context.dotfilesRoot, options.profiles, options.agents, "export", (_file, name) => {
    if (!isPathComponentName(name)) {
      fail(`Invalid profile name: ${name}`);
    }
    if (fs.lstatSync(path.join(context.dotfilesRoot, "skills", "profiles", `${name}.json`), { throwIfNoEntry: false })) {
      requireSourcePath(context.dotfilesRoot, `skills/profiles/${name}.json`, "file");
    }
  });
  requireSafeExternal(plan.external);
  const selection = selectSkills(
    sources,
    plan.local.map((skill) => skill.name),
    plan.external,
    options.exclude,
  );
  const state = inspectOut(out, options.force);
  const rules = RULES_TARGETS.filter((target) => options.agents.includes(target.agent));

  say(`Local skills: ${selection.local.map((skill) => skill.name).join(", ") || "none"}`);
  for (const skill of selection.local.filter((entry) => entry.requiredBy)) {
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

  // Everything is read and checked in memory before staging is written.
  const contents = new Map<string, { bytes: Buffer; mode?: number }>();
  for (const skill of selection.local) {
    const sourceDir = requireSkillRoot(sources, skill.name);
    for (const relative of skillFiles(sourceDir, skill.name)) {
      const source = path.join(sourceDir, relative);
      contents.set(toPosix(path.join("skills", skill.name, relative)), { bytes: fs.readFileSync(source), mode: fs.statSync(source).mode & 0o777 });
    }
  }
  for (const target of rules) {
    contents.set(target.file, { bytes: Buffer.from(composeRules(context.dotfilesRoot, target.override)) });
  }
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
    files: [...contents.keys(), "README.md", BUNDLE_MANIFEST].sort(),
  };
  const problem = manifestProblem(manifest);
  if (problem) {
    fail(`internal error: the generated manifest is invalid (${problem})`);
  }
  const hasNodeScripts = manifest.files.some((file) => /^skills\/[^/]+\/scripts\/.+\.mjs$/.test(file));
  contents.set("README.md", { bytes: Buffer.from(readmeText(manifest, hasNodeScripts)) });
  contents.set(BUNDLE_MANIFEST, { bytes: Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`) });
  requireNoCaseCollisions(manifest.files);
  checkPersonalData(contents, markers);

  fs.mkdirSync(path.dirname(out), { recursive: true });
  requireSafeParent(out);
  const staging = fs.mkdtempSync(workName(out, "s"));
  let installed = false;
  try {
    for (const [relative, { bytes, mode }] of contents) {
      const target = path.join(staging, ...relative.split("/"));
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, bytes);
      if (mode !== undefined) {
        fs.chmodSync(target, mode);
      }
    }
    requireStagedTree(staging, manifest.files);
    checkLinks(staging, contents);
    fs.chmodSync(staging, 0o777 & ~process.umask());
    install(staging, out, state, (message) => console.warn(markers.redact(message)));
    installed = true;
  } finally {
    if (!installed) {
      fs.rmSync(staging, { recursive: true, force: true });
    }
  }
  say(`Skills bundle written: ${out}`);
}

// Two output paths that differ only in letter case would merge or overwrite
// each other on a case-insensitive volume.
function requireNoCaseCollisions(files: string[]): void {
  const seen = new Map<string, string>();
  const collisions = new Set<string>();
  for (const file of files) {
    const parts = file.split("/");
    for (let depth = 1; depth <= parts.length; depth += 1) {
      const entry = parts.slice(0, depth).join("/");
      const other = seen.get(entry.toLowerCase());
      if (other !== undefined && other !== entry) {
        collisions.add(`${other} and ${entry}`);
      }
      seen.set(entry.toLowerCase(), other ?? entry);
    }
  }
  if (collisions.size > 0) {
    fail(`bundle paths differ only in letter case: ${Array.from(collisions).sort().join("; ")}`);
  }
}

// The staged tree must hold exactly the files the manifest lists.
function requireStagedTree(staging: string, files: string[]): void {
  const { files: staged, others } = listEntries(staging);
  if (others.length > 0 || !sameList(staged.sort(), [...files].sort())) {
    fail("internal error: the staged bundle does not match its manifest");
  }
}

// Scans every bundle file's path and content, which must be strict UTF-8
// without NUL, for personal markers.
function checkPersonalData(contents: Map<string, { bytes: Buffer }>, markers: Markers): void {
  const findings: string[] = [];
  for (const [relative, { bytes }] of contents) {
    for (const kind of markers.kindsIn(`${relative}\n${decodeText(bytes, relative)}`)) {
      findings.push(`${markers.redact(relative)}: ${kind}`);
    }
  }
  if (findings.length > 0) {
    fail(`personal data check failed; nothing was written:\n  ${findings.join("\n  ")}`);
  }
}

// Every relative reference in the staged skills must resolve to an existing
// path inside the bundle's skills/ directory.
function checkLinks(staging: string, contents: Map<string, { bytes: Buffer }>): void {
  const unresolved: string[] = [];
  const skillsRoot = path.join(staging, "skills");
  for (const [relative, { bytes }] of contents) {
    if (!relative.startsWith("skills/")) {
      continue;
    }
    const file = path.join(staging, ...relative.split("/"));
    for (const reference of parseReferences(decodeText(bytes, relative))) {
      const resolved = resolveReference(path.dirname(file), reference);
      if (!resolved || !isInsideOrSame(resolved, skillsRoot)) {
        unresolved.push(`${relative} -> ${reference}`);
      }
    }
  }
  if (unresolved.length > 0) {
    fail(`relative links in the bundle do not resolve inside it:\n  ${unique(unresolved).join("\n  ")}`);
  }
}
