import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { isDeepStrictEqual } from "node:util";
import { parse, stringify } from "smol-toml";

type Table = Record<string, unknown>;
type Format = "toml" | "json";
type Managed = { source: string; home: string; name: string; format: Format; state: string[][] };
type Difference = { sign: "+" | "-" | "~"; keys: string[]; repo?: unknown; live?: unknown };

// Codex and Claude rewrite these files while running, so setup installs copies
// instead of links. State keys hold machine-local runtime records, such as
// trusted project paths and hook approvals; they are never synced or reported.
const managed: Managed[] = [
  {
    source: "codex/config.toml", home: ".codex", name: "config.toml", format: "toml",
    state: [["projects"], ["hooks", "state"], ["tui", "model_availability_nux"], ["tui", "screen_reader_detection_done"], ["notice", "model_migrations"]],
  },
  { source: "claude/settings.json", home: ".claude", name: "settings.json", format: "json", state: [] },
];

// The dotfiles version last applied to each copy, kept beside it for 3-way merges.
const baselineDir = ".dotfiles-managed";

function table(value: unknown): value is Table {
  return value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof Date);
}

function entry(file: string): fs.Stats | undefined {
  try {
    return fs.lstatSync(file);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw new Error(`Cannot inspect file: ${file}`);
  }
}

function readOptional(file: string): string | undefined {
  try {
    return fs.readFileSync(file, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw new Error(`Cannot read file: ${file}`);
  }
}

function readConfig(text: string, format: Format, name: string): Table {
  let value: unknown;
  try {
    value = format === "toml" ? parse(text) : JSON.parse(text);
  } catch {
    // Parser excerpts can contain local configuration values.
    throw new Error(`Invalid ${format.toUpperCase()}: ${name}`);
  }
  if (!table(value)) throw new Error(`Expected a table: ${name}`);
  // TOML tables have no prototype; normalize them so comparisons match JSON.
  return copyTables(value);
}

function writeConfig(value: Table, format: Format): string {
  return format === "toml" ? stringify(value) : JSON.stringify(value, null, 2) + "\n";
}

// Defined as own properties so a "__proto__" key stays an ordinary setting.
function assign(target: Table, key: string, value: unknown): void {
  Object.defineProperty(target, key, { value, enumerable: true, writable: true, configurable: true });
}

function own(value: Table, key: string): unknown {
  return Object.hasOwn(value, key) ? value[key] : undefined;
}

// Copies tables only; TOML dates and arrays keep their identity and type.
function copyTables(value: Table): Table {
  const result: Table = {};
  for (const [key, item] of Object.entries(value)) assign(result, key, table(item) ? copyTables(item) : item);
  return result;
}

function withoutState(config: Table, state: string[][]): Table {
  const result = copyTables(config);
  for (const keys of state) {
    const parents: Table[] = [result];
    for (const key of keys.slice(0, -1)) {
      const next = own(parents[parents.length - 1], key);
      if (!table(next)) break;
      parents.push(next);
    }
    if (parents.length !== keys.length) continue;
    delete parents[parents.length - 1][keys[keys.length - 1]];
    for (let index = parents.length - 1; index > 0 && Object.keys(parents[index]).length === 0; index--) {
      delete parents[index - 1][keys[index - 1]];
    }
  }
  return result;
}

// Local edits win over a conflicting dotfiles change; the key is reported.
function merge(previous: unknown, current: unknown, desired: unknown, keys: string[], conflicts: string[][]): unknown {
  if (isDeepStrictEqual(current, previous)) return desired;
  if (isDeepStrictEqual(previous, desired) || isDeepStrictEqual(current, desired)) return current;
  if (table(current) && table(desired) && (previous === undefined || table(previous))) {
    const old = previous ?? {};
    const merged: Table = {};
    for (const name of new Set([...Object.keys(old), ...Object.keys(current), ...Object.keys(desired)])) {
      const value = merge(own(old, name), own(current, name), own(desired, name), [...keys, name], conflicts);
      if (value !== undefined) assign(merged, name, value);
    }
    return merged;
  }
  conflicts.push(keys);
  return current;
}

function replaceFile(file: string, text: string, mode: number): void {
  const temp = `${file}.dotfiles-${process.pid}.tmp`;
  fs.writeFileSync(temp, text, { mode });
  try {
    fs.chmodSync(temp, mode);
    // Renaming replaces a link itself, never the file it points to.
    fs.renameSync(temp, file);
  } catch (error) {
    fs.rmSync(temp, { force: true });
    throw error;
  }
}

function keyPath(keys: string[]): string {
  return keys.map(key => /^[A-Za-z0-9_-]+$/.test(key) ? key : JSON.stringify(key)).join(".");
}

function show(keys: string[], value: unknown): string {
  if (keys.some(key => key === "env" || /token|key|secret|password|credential/i.test(key))) return "***";
  const text = value instanceof Date ? value.toISOString() : JSON.stringify(value) ?? String(value);
  return text.length > 80 ? `${text.slice(0, 77)}...` : text;
}

function leaves(value: unknown, keys: string[]): [string[], unknown][] {
  if (!table(value) || Object.keys(value).length === 0) return [[keys, value]];
  return Object.entries(value).flatMap(([name, item]) => leaves(item, [...keys, name]));
}

function differences(repo: unknown, live: unknown, keys: string[], out: Difference[]): void {
  if (isDeepStrictEqual(repo, live)) return;
  if (table(repo) && table(live)) {
    for (const name of new Set([...Object.keys(repo), ...Object.keys(live)])) {
      differences(own(repo, name), own(live, name), [...keys, name], out);
    }
  } else if (repo === undefined) {
    for (const [path, value] of leaves(live, keys)) out.push({ sign: "+", keys: path, live: value });
  } else if (live === undefined) {
    for (const [path, value] of leaves(repo, keys)) out.push({ sign: "-", keys: path, repo: value });
  } else {
    out.push({ sign: "~", keys, repo, live });
  }
}

function apply(root: string, home: string, item: Managed, dryRun: boolean): void {
  const sourceText = fs.readFileSync(path.join(root, item.source), "utf8");
  const desired = withoutState(readConfig(sourceText, item.format, item.source), item.state);
  const dir = path.join(home, item.home);
  const file = path.join(dir, item.name);
  const baseline = path.join(dir, baselineDir, item.name);
  const stat = entry(file);
  if (stat && !stat.isFile() && !stat.isSymbolicLink()) throw new Error(`Refusing an unexpected file type: ${file}`);
  const baselineStat = entry(baseline);
  if (baselineStat && !baselineStat.isFile()) throw new Error(`Refusing an unexpected file type: ${baseline}`);

  // A link from an older setup still shows the live content; replace it with a copy.
  const currentText = readOptional(file);
  const previousText = baselineStat ? readOptional(baseline) : undefined;
  const conflicts: string[][] = [];
  let after = sourceText;
  if (currentText !== undefined) {
    const current = readConfig(currentText, item.format, file);
    const previous = previousText === undefined ? undefined : withoutState(readConfig(previousText, item.format, baseline), item.state);
    const merged = merge(previous, current, desired, [], conflicts) as Table;
    after = isDeepStrictEqual(merged, current) ? currentText : writeConfig(merged, item.format);
  }
  if (conflicts.length > 0) {
    console.warn(`Kept local values that conflict with dotfiles changes in ${file}: ${conflicts.map(keyPath).join(", ")}`);
  }
  const linked = stat?.isSymbolicLink() === true;
  const writeLive = linked || after !== currentText;
  const writeBaseline = previousText !== sourceText;
  if (writeLive) console.log(`${dryRun ? "Would write" : "Updating"} ${file}${linked ? " (replacing the link with a copy)" : ""}`);
  if (dryRun || (!writeLive && !writeBaseline)) return;

  fs.mkdirSync(path.join(dir, baselineDir), { recursive: true, mode: 0o700 });
  if (writeLive) {
    // Codex or Claude may have written the file during the merge.
    if (readOptional(file) !== currentText) throw new Error(`File changed during setup: ${file}`);
    replaceFile(file, after, stat?.isFile() ? stat.mode & 0o777 : 0o600);
  }
  if (writeBaseline) replaceFile(baseline, sourceText, 0o600);
}

function report(root: string, home: string, item: Managed, summary: boolean): number {
  const file = path.join(home, item.home, item.name);
  const stat = entry(file);
  if (!stat?.isFile()) {
    if (!summary) console.log(`${item.source}: ${file} is not a managed copy yet; run setup links\n`);
    return 0;
  }
  const repo = withoutState(readConfig(fs.readFileSync(path.join(root, item.source), "utf8"), item.format, item.source), item.state);
  const live = withoutState(readConfig(fs.readFileSync(file, "utf8"), item.format, file), item.state);
  const found: Difference[] = [];
  differences(repo, live, [], found);
  if (!summary && found.length > 0) {
    console.log(`${item.source} <- ${file}`);
    for (const diff of found) {
      const value = diff.sign === "+" ? ` = ${show(diff.keys, diff.live)}`
        : diff.sign === "-" ? ` = ${show(diff.keys, diff.repo)}`
          : `: ${show(diff.keys, diff.repo)} -> ${show(diff.keys, diff.live)}`;
      console.log(`  ${diff.sign} ${keyPath(diff.keys)}${value}`);
    }
    console.log("");
  }
  return found.length;
}

const usage = "Usage: managed-copy apply [--dry-run]\n" +
  "       managed-copy diff [--check] [--summary]\n" +
  "apply installs or refreshes the local copies of codex/config.toml and claude/settings.json,\n" +
  "merging dotfiles changes with local edits; a conflicting local value is kept with a warning.\n" +
  "diff lists settings that differ between the local copies and dotfiles, ignoring runtime state:\n" +
  "+ only in the local copy, - only in dotfiles, ~ changed locally. Secret-like values are masked.\n" +
  "--check exits 1 when they differ; --summary prints only a count.";

export function main(args = process.argv.slice(2)): void {
  const [command, ...options] = args;
  if (command === "--help" || command === "-h" || command === "help") {
    console.log(usage);
    return;
  }
  const allowed = command === "apply" ? ["--dry-run"] : command === "diff" ? ["--check", "--summary"] : undefined;
  if (!allowed) throw new Error("Expected apply or diff; see --help");
  const unknown = options.find(option => !allowed.includes(option));
  if (unknown !== undefined) throw new Error(`Unknown ${command} argument: ${unknown}`);
  const root = path.resolve(process.env.SETUP_DOTFILES_ROOT || path.join(__dirname, ".."));
  const home = path.resolve(process.env.SETUP_HOME || os.homedir());

  if (command === "apply") {
    const dryRun = options.includes("--dry-run") || process.env.SETUP_DRY_RUN === "1";
    let failed = false;
    for (const item of managed) {
      try {
        apply(root, home, item, dryRun);
      } catch (error) {
        console.error(`managed-copy: ${error instanceof Error ? error.message : "Update failed"}`);
        failed = true;
      }
    }
    if (failed) process.exitCode = 1;
    return;
  }

  const summary = options.includes("--summary");
  let total = 0;
  const changed: string[] = [];
  for (const item of managed) {
    try {
      const count = report(root, home, item, summary);
      if (count > 0) changed.push(item.source);
      total += count;
    } catch (error) {
      console.error(`managed-copy: ${error instanceof Error ? error.message : "Comparison failed"}`);
      changed.push(item.source);
      total += 1;
    }
  }
  if (summary && total > 0) {
    const command = process.platform === "win32" ? ".\\setup.ps1 diff" : "./setup.sh diff";
    console.log(`Local Codex/Claude settings differ from dotfiles in ${total} place(s) (${changed.join(", ")}); review with ${command}`);
  }
  if (options.includes("--check") && total > 0) process.exitCode = 1;
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`managed-copy: ${error instanceof Error ? error.message : "Failed"}`);
    process.exitCode = 1;
  }
}
