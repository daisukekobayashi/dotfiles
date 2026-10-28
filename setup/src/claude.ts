import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import * as readline from "node:readline";
import { Writable } from "node:stream";
import { isDeepStrictEqual } from "node:util";
import { copyMarker, copyMetadata, planSharedLink, sameSnapshot, snapshot, stageSharedLinks, SharedChange, SharedLink } from "./shared-links";

type Table = Record<string, unknown>;
type Link = SharedLink;
type Guard = { name: string; before: string | undefined };
type Change = Guard & { after: string };
type Connection = { baseUrl?: string; model?: string; contextTokens?: number };

function entry(file: string): fs.Stats | undefined {
  try { return fs.lstatSync(file); } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}

function directory(file: string, label: string): void {
  const stat = entry(file);
  if (stat && (!stat.isDirectory() || stat.isSymbolicLink())) {
    throw new Error(`Refusing a symlink or unexpected ${label}`);
  }
}

function readOptional(file: string, label: string): string | undefined {
  const stat = entry(file);
  if (!stat) return undefined;
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`Expected an independent file: ${label}`);
  return fs.readFileSync(file, "utf8");
}

function table(value: unknown): value is Table {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function readSettings(text: string | undefined, label: string): Table {
  try {
    const value: unknown = JSON.parse(text ?? "");
    if (!table(value)) throw new Error();
    return value;
  } catch { throw new Error(`Missing or invalid JSON object: ${label}`); }
}

function readConnection(value: unknown): Connection {
  if (value === undefined) return {};
  if (!table(value) || Object.keys(value).some(key => !["baseUrl", "model", "contextTokens"].includes(key))) {
    throw new Error("Invalid Claude connection settings");
  }
  if (value.baseUrl !== undefined) {
    try {
      if (typeof value.baseUrl !== "string" || /\s/.test(value.baseUrl)) throw new Error();
      const url = new URL(value.baseUrl);
      if (!["http:", "https:"].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error();
    } catch { throw new Error("--base-url requires an HTTP(S) URL without credentials, query or fragment"); }
  }
  if (value.model !== undefined && (typeof value.model !== "string" || !value.model || /^-|\s/.test(value.model))) {
    throw new Error("--model requires a model ID without whitespace or a leading hyphen");
  }
  if (value.contextTokens !== undefined && (typeof value.contextTokens !== "number" || !Number.isSafeInteger(value.contextTokens) || value.contextTokens <= 0)) {
    throw new Error("--context-tokens requires a positive integer");
  }
  return value as Connection;
}

function withConnection(shared: Table, connection: Connection): Table {
  if (!Object.keys(connection).length) return shared;
  if (shared.env !== undefined && !table(shared.env)) throw new Error("Expected an env object in claude/settings.json");
  const env = { ...(shared.env as Table | undefined) };
  if (connection.baseUrl !== undefined) env.ANTHROPIC_BASE_URL = connection.baseUrl;
  if (connection.contextTokens !== undefined) env.CLAUDE_CODE_MAX_CONTEXT_TOKENS = String(connection.contextTokens);
  if (connection.baseUrl && connection.model) {
    // A single-model gateway must also accept requests from built-in aliases.
    for (const family of ["FABLE", "OPUS", "SONNET", "HAIKU"]) env[`ANTHROPIC_DEFAULT_${family}_MODEL`] = connection.model;
  }
  return { ...shared, ...(connection.model !== undefined ? { model: connection.model } : {}), env };
}

async function readAuthToken(fromStdin: boolean): Promise<string> {
  let token: string;
  if (fromStdin) {
    if (process.stdin.isTTY) throw new Error("--auth-token-stdin requires piped input");
    process.stdin.setEncoding("utf8");
    token = "";
    for await (const chunk of process.stdin) {
      token += chunk;
      if (token.length > 65536) throw new Error("Auth token input is too long");
    }
    token = token.replace(/^\uFEFF/, "").replace(/\r?\n$/, "");
  } else {
    if (!process.stdin.isTTY) throw new Error("Auth token required: run in a terminal for hidden input, or use --auth-token-stdin");
    const silent = new Writable({ write(_chunk, _encoding, callback) { callback(); } });
    const prompt = readline.createInterface({ input: process.stdin, output: silent, terminal: true, historySize: 0 });
    try {
      const answer = new Promise<string>((resolve, reject) => {
        prompt.once("SIGINT", () => reject(new Error("Auth token input cancelled")));
        prompt.once("close", () => reject(new Error("Auth token input cancelled")));
        prompt.question("", resolve);
      });
      process.stderr.write("Gateway auth token (hidden): ");
      token = await answer;
    } finally {
      prompt.close();
      silent.end();
      process.stderr.write("\n");
    }
  }
  if (!token || /[\s\x00-\x1f\x7f]/.test(token)) throw new Error("Auth token must be nonempty and contain no whitespace or control characters");
  return token;
}

function memoryPorts(home: string, root: string): Set<number> {
  const ports = new Set<number>();
  const read = (file: string): Table => {
    try { return readSettings(fs.readFileSync(file, "utf8"), file); } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
      throw error;
    }
  };
  const collect = (settings: Table) => {
    const port = parseInt(String(settings.CLAUDE_MEM_WORKER_PORT), 10);
    if (port > 0 && port <= 65535) ports.add(port);
  };
  const collectData = (file: string) => {
    const settings = read(file);
    collect(table(settings.env) ? settings.env : settings);
  };
  collectData(path.join(home, ".claude-mem/settings.json"));
  const homes = [path.join(home, ".claude")];
  if (entry(root)) {
    for (const item of fs.readdirSync(root, { withFileTypes: true })) {
      if (item.isDirectory()) homes.push(path.join(root, item.name));
    }
  }
  for (const directory of homes) {
    const settings = read(path.join(directory, "settings.json"));
    const env = table(settings.env) ? settings.env : {};
    collect(env);
    collectData(path.join(directory, "claude-mem/settings.json"));
    if (typeof env.CLAUDE_MEM_DATA_DIR === "string") {
      const data = env.CLAUDE_MEM_DATA_DIR.replace(/^~(?=$|[\\/])/, home);
      collectData(path.join(data, "settings.json"));
    }
  }
  return ports;
}

async function reserveMemoryPort(home: string, root: string): Promise<number> {
  let used = memoryPorts(home, root);
  // Leave the per-user default range (37700-37799) available to the default home.
  for (let port = 37800; port <= 65535; port++) {
    if (used.has(port)) continue;
    const server = await new Promise<net.Server | undefined>((resolve, reject) => {
      const listener = net.createServer(socket => socket.destroy());
      listener.once("error", (error: NodeJS.ErrnoException) => {
        if (error.code === "EADDRINUSE") resolve(undefined);
        else reject(error);
      });
      listener.listen({ host: "127.0.0.1", port, exclusive: true }, () => resolve(listener));
    });
    if (!server) continue;
    try {
      // Another setup may have saved its allocation after our first scan.
      used = memoryPorts(home, root);
      if (!used.has(port)) {
        // Hold the port until this process has saved (or rolled back) its files.
        server.unref();
        process.once("exit", () => server.close());
        return port;
      }
    } catch (error) {
      server.close();
      throw error;
    }
    await new Promise<void>(resolve => server.close(() => resolve()));
  }
  throw new Error("No unused loopback port is available for claude-mem");
}

function mergeSettings(previous: unknown, current: unknown, desired: unknown, key = "settings.json", legacy = false): unknown {
  if (isDeepStrictEqual(current, previous)) return desired;
  if (isDeepStrictEqual(previous, desired) || isDeepStrictEqual(current, desired)) return current;
  if (table(current) && table(desired) && (previous === undefined || table(previous))) {
    const old = previous ?? {};
    const entries: [string, unknown][] = [];
    for (const name of new Set([...Object.keys(old), ...Object.keys(current), ...Object.keys(desired)])) {
      const value = mergeSettings(old[name], current[name], desired[name], `${key}.${name}`, legacy);
      if (value !== undefined) entries.push([name, value]);
    }
    return Object.fromEntries(entries);
  }
  // Old homes recorded no source baseline. Treat their differences from the
  // former minimal template as local choices on this first migration only.
  if (legacy) return current;
  throw new Error(`Conflicting local and dotfiles changes: ${key}`);
}

function sharedSkills(dotfiles: string, required: Set<string>): Link[] {
  const root = path.join(dotfiles, ".agents/user/skills");
  const names = fs.existsSync(root) ? fs.readdirSync(root).sort() : [];
  const valid = (name: string) => /^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(name) && !/^(synced|anthropic-skills)$/i.test(name);
  const installed = (name: string) => {
    const file = path.join(root, name, "SKILL.md");
    return fs.existsSync(file) && fs.statSync(file).isFile();
  };
  for (const name of required) {
    if (!valid(name)) throw new Error(`Invalid or reserved skill name: ${name}`);
    if (!installed(name)) throw new Error(`Installed skill not found: ${name}`);
  }
  return names.filter(name => valid(name) && installed(name))
    .map(name => ({ name: `skills/${name}`, source: path.join(root, name), directory: true }));
}

function applyChanges(root: string, destination: string, existing: boolean, links: SharedChange[], changes: Change[], guards: Guard[], copy: boolean): void {
  const sharedApplied: { link: SharedChange; old: string; installed?: fs.Stats; files?: ReturnType<typeof snapshot> }[] = [];
  const createdDirectories: string[] = [];
  const applied: Change[] = [];
  let stage: string | undefined;
  let backup: string | undefined;
  let complete = false;
  let keepStage = false;
  const mkdir = (file: string) => {
    if (!entry(file)) {
      try {
        fs.mkdirSync(file, { mode: 0o700 });
        createdDirectories.push(file);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
        directory(file, "environment directory");
      }
    } else directory(file, "environment directory");
  };
  const checkFiles = (verifyShared = false) => {
    directory(root, "Claude environment directory");
    directory(destination, "Claude environment home");
    for (const name of ["rules", "skills", ...(!existing ? ["claude-mem"] : [])]) directory(path.join(destination, name), `${name} directory`);
    for (const guard of guards) {
      const expected = applied.find(change => change.name === guard.name)?.after ?? guard.before;
      if (readOptional(path.join(destination, guard.name), guard.name) !== expected) {
        throw new Error(`Target changed during generation: ${guard.name}`);
      }
    }
    for (const link of verifyShared ? links : []) {
      const applied = sharedApplied.find(item => item.link === link);
      const target = path.join(destination, link.name);
      if (applied?.installed) {
        const stat = entry(target);
        if (stat?.ino !== applied.installed.ino || stat.dev !== applied.installed.dev ||
            (applied.files && !sameSnapshot(snapshot(target), applied.files))) {
          throw new Error(`Target changed during generation: ${link.name}`);
        }
      } else if (link.before ? !sameSnapshot(snapshot(target), link.before) : entry(target) !== undefined) {
        throw new Error(`Target changed during generation: ${link.name}`);
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
    } else directory(destination, "Claude environment home");
    mkdir(path.join(destination, "rules"));
    mkdir(path.join(destination, "skills"));
    if (!existing) mkdir(path.join(destination, "claude-mem"));
    stage = fs.mkdtempSync(path.join(destination, ".dotfiles-claude-stage-"));
    checkFiles();
    stageSharedLinks(links.map(link => ({
      source: link.source, target: path.join(stage!, "shared", link.name), directory: link.directory, copy: copy || link.copy,
    })));
    for (const link of links) {
      const artifact = path.join(stage, "shared", link.name);
      if (!fs.lstatSync(artifact).isSymbolicLink()) {
        changes.push({ name: copyMarker(link.name), before: link.markerBefore, after: copyMetadata(link.source, snapshot(artifact)!) });
        console.warn(`Copied shared entry: ${link.name}; rerun setup to refresh copies.`);
      }
    }
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
        if (change.before !== undefined) {
          const file = path.join(backup, change.name);
          fs.mkdirSync(path.dirname(file), { recursive: true });
          fs.writeFileSync(file, change.before, { flag: "wx", mode: 0o600 });
        }
      }
    }
    checkFiles(true);
    for (const link of links) {
      checkFiles();
      const target = path.join(destination, link.name);
      if (link.before ? !sameSnapshot(snapshot(target), link.before) : entry(target) !== undefined) {
        throw new Error(`Target changed during generation: ${link.name}`);
      }
      const artifact = path.join(stage, "shared", link.name);
      const stat = fs.lstatSync(artifact);
      const item = { link, old: path.join(stage, `previous-shared-${sharedApplied.length}`), installed: undefined as fs.Stats | undefined,
        files: stat.isSymbolicLink() ? undefined : snapshot(artifact) };
      sharedApplied.push(item);
      if (link.before) fs.renameSync(target, item.old);
      fs.renameSync(artifact, target);
      item.installed = stat;
    }
    checkFiles(true);
    for (let i = 0; i < changes.length; i++) {
      checkFiles();
      fs.renameSync(path.join(stage, `${i}.new`), path.join(destination, changes[i].name));
      applied.push(changes[i]);
    }
    checkFiles(true);
    complete = true;
  } catch (error) {
    let rollbackError: unknown;
    try {
      for (const change of applied.reverse()) {
        const target = path.join(destination, change.name);
        if (readOptional(target, change.name) !== change.after) {
          throw new Error(`Rollback stopped because a target changed: ${change.name}. Recovery files: ${backup ?? stage}`);
        }
        if (change.before === undefined) fs.unlinkSync(target);
        else {
          const restore = path.join(stage!, "restore");
          fs.writeFileSync(restore, change.before, { mode: 0o600 });
          fs.renameSync(restore, target);
        }
      }
    } catch (restoreError) {
      keepStage = true;
      rollbackError = restoreError;
    }
    try {
      for (const item of sharedApplied.reverse()) {
        if (!item.installed && !entry(item.old)) continue;
        const target = path.join(destination, item.link.name);
        const current = entry(target);
        if (current) {
          if (!item.installed || current.dev !== item.installed.dev || current.ino !== item.installed.ino ||
              (item.files && !sameSnapshot(snapshot(target), item.files))) {
            throw new Error(`Rollback stopped because a target changed: ${item.link.name}. Recovery files: ${stage}`);
          }
          if (current.isSymbolicLink()) fs.unlinkSync(target);
          else fs.rmSync(target, { recursive: true });
        }
        if (entry(item.old)) fs.renameSync(item.old, target);
      }
    } catch (restoreError) {
      keepStage = true;
      rollbackError ??= restoreError;
    }
    if (rollbackError) throw rollbackError;
    throw error;
  } finally {
    if (stage && !keepStage) {
      fs.rmSync(stage, { recursive: true, force: true });
    }
    if (!complete) {
      for (const file of createdDirectories.reverse()) {
        try { fs.rmdirSync(file); } catch { /* Keep concurrent additions and backups. */ }
      }
    }
  }
  if (backup) console.log(`Previous settings backed up in ${backup}`);
}

async function main(): Promise<void> {
  let env = "";
  let dryRun = process.env.SETUP_DRY_RUN === "1";
  let copy = false;
  let tokenFromStdin = false;
  const requested: Connection = {};
  const skills = new Set<string>();
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      console.log(`Usage: setup claude --env NAME [--base-url URL] [--model ID]
                    [--context-tokens N] [--auth-token-stdin] [--copy] [--dry-run]

Create or refresh a named Claude Code environment without login or launch.
Generate settings from claude/settings.json; preserve independent local edits.
Conflicting edits stop before writes. Previous settings are backed up on refresh.
Shared skills, rules and statusline prefer symlinks. On Windows, retry elevated,
then copy if link privileges remain unavailable. --copy skips link attempts.
Managed copies refresh on rerun; conflicting local edits stop before writes.
New environments get a private claude-mem data directory and unused worker port.
Connection options are saved only in the selected local environment; omitted values persist.
The endpoint must speak Anthropic Messages. Gateway model aliases use the saved model.
Missing gateway tokens are requested with hidden input; --auth-token-stdin reads a pipe.
Tokens are never accepted as arguments or saved in generation metadata.
Dry-run does not read tokens, contact the endpoint, or print connection values.
Legacy --skill NAME validates that a skill is installed; it does not filter sharing.
The default environment keeps using setup links.
Names: 1-64 lowercase letters, digits, hyphens, underscores; start with a letter.`);
      return;
    }
    if (arg === "--dry-run") { dryRun = true; continue; }
    if (arg === "--copy") { copy = true; continue; }
    if (arg === "--auth-token-stdin") { tokenFromStdin = true; continue; }
    const separator = arg.indexOf("=");
    const option = separator === -1 ? arg : arg.slice(0, separator);
    if (["--env", "--skill", "--base-url", "--model", "--context-tokens"].includes(option)) {
      const value = separator === -1 ? args[++i] : arg.slice(separator + 1);
      if (!value || value.startsWith("-")) throw new Error(`${option} requires a value`);
      if (option === "--skill") skills.add(value);
      else if (option === "--base-url") requested.baseUrl = value;
      else if (option === "--model") requested.model = value;
      else if (option === "--context-tokens") {
        if (!/^\d+$/.test(value)) throw new Error("--context-tokens requires a positive integer");
        requested.contextTokens = Number(value);
      } else {
        if (env && env !== value) throw new Error("Environment specified twice with different names");
        env = value;
      }
    } else throw new Error("Unknown Claude setup argument; see --help (tokens must not be passed as arguments)");
  }
  readConnection(requested);
  if (!env) throw new Error("Claude setup requires --env NAME");
  if (env === "default") throw new Error("The default environment uses setup links; choose a separate --env NAME");
  if (!/^[a-z][a-z0-9_-]{0,63}$/.test(env) || /^(con|prn|aux|nul|com[0-9]|lpt[0-9])$/.test(env)) {
    throw new Error(`Invalid or reserved environment name: ${env}`);
  }
  if (process.env.SETUP_DRY_RUN && !["0", "1"].includes(process.env.SETUP_DRY_RUN)) {
    throw new Error("SETUP_DRY_RUN must be 0 or 1");
  }
  const home = path.resolve(process.env.SETUP_HOME || os.homedir());
  const dotfiles = path.resolve(process.env.SETUP_DOTFILES_ROOT || path.join(__dirname, ".."));
  const root = path.join(home, ".claude-envs");
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
    if (settingsBefore === undefined) throw new Error("Expected an independent settings.json file");
  }
  for (const name of ["rules", "skills"]) directory(path.join(destination, name), `${name} directory`);
  directory(path.join(destination, ".dotfiles-claude-backups"), "backup directory");

  const saved = baselineBefore === undefined ? undefined : readSettings(baselineBefore, ".dotfiles-env.json");
  if (saved && (saved.version !== 1 || saved.env !== env || !table(saved.settings))) throw new Error("Invalid Claude environment baseline");
  const connection = readConnection({ ...readConnection(saved?.connection), ...requested });
  const source = withConnection(readSettings(readOptional(path.join(dotfiles, "claude/settings.json"), "claude/settings.json"), "claude/settings.json"), connection);
  let settings = source;
  let memory: Table | undefined;
  if (!existing) {
    const sharedEnv = source.env === undefined ? {} : source.env;
    if (!table(sharedEnv)) throw new Error("Expected an env object in claude/settings.json");
    memory = {
      CLAUDE_MEM_DATA_DIR: path.join(destination, "claude-mem"),
      CLAUDE_MEM_WORKER_PORT: String(await reserveMemoryPort(home, root)),
      CLAUDE_MEM_WORKER_HOST: "127.0.0.1",
    };
    settings = { ...source, env: { ...sharedEnv, ...memory } };
  }
  if (settingsBefore !== undefined) {
    const current = readSettings(settingsBefore, "settings.json");
    let previous: Table;
    if (saved) {
      previous = saved.settings as Table;
    } else {
      previous = readSettings(readOptional(path.join(dotfiles, "claude/profile-settings.json"), "claude/profile-settings.json"), "claude/profile-settings.json");
    }
    settings = mergeSettings(previous, current, source, "settings.json", baselineBefore === undefined) as Table;
  }
  const candidates: Link[] = [
    { name: "statusline.cjs", source: path.join(dotfiles, "claude/statusline.cjs") },
    { name: "rules/00-global.md", source: path.join(dotfiles, "ai-rules/base/global.md") },
    { name: "rules/10-claude.md", source: path.join(dotfiles, "ai-rules/agents/claude.md") },
    ...sharedSkills(dotfiles, skills),
  ];
  const links: SharedChange[] = [];
  for (const link of candidates) {
    if (!fs.existsSync(link.source) || !(link.directory ? fs.statSync(link.source).isDirectory() : fs.statSync(link.source).isFile())) {
      throw new Error(`Missing shared file for ${link.name}`);
    }
    const change = planSharedLink(destination, link);
    if (change) links.push(change);
  }

  const settingsEnv = settings.env === undefined ? {} : settings.env;
  if (!table(settingsEnv)) throw new Error("Expected an env object in settings.json");
  const needsToken = tokenFromStdin || (connection.baseUrl !== undefined && !settingsEnv.ANTHROPIC_AUTH_TOKEN);
  if (tokenFromStdin && !settingsEnv.ANTHROPIC_BASE_URL) throw new Error("--auth-token-stdin requires a gateway base URL");
  if (needsToken && !dryRun) {
    settings = { ...settings, env: { ...settingsEnv, ANTHROPIC_AUTH_TOKEN: await readAuthToken(tokenFromStdin) } };
  }
  const settingsAfter = settingsBefore !== undefined && isDeepStrictEqual(settings, readSettings(settingsBefore, "settings.json"))
    ? settingsBefore : JSON.stringify(settings, null, 2) + "\n";
  const baseline = { version: 1, env, settings: source, ...(Object.keys(connection).length ? { connection } : {}) };
  const baselineAfter = saved && isDeepStrictEqual(saved, baseline) ? baselineBefore! : JSON.stringify(baseline, null, 2) + "\n";
  const guards: Guard[] = [
    { name: "settings.json", before: settingsBefore },
    { name: ".dotfiles-env.json", before: baselineBefore },
    { name: ".claude-pick", before: markerBefore },
    ...(!existing ? [{ name: "claude-mem/settings.json", before: undefined }] : []),
    ...links.map(link => ({ name: copyMarker(link.name), before: link.markerBefore })),
  ];
  const changes: Change[] = [
    { ...guards[0], after: settingsAfter },
    { ...guards[1], after: baselineAfter },
    ...(!existing ? [
      { ...guards[3], after: JSON.stringify(memory, null, 2) + "\n" },
      { ...guards[2], after: "1\n" },
    ] : []),
  ].filter(change => change.before !== change.after);

  if (dryRun) {
    console.log(`Would ${existing ? "refresh" : "create"} environment: ${env}`);
    if (memory) console.log(`  claude-mem: ${memory.CLAUDE_MEM_DATA_DIR} (127.0.0.1:${memory.CLAUDE_MEM_WORKER_PORT})`);
    for (const change of changes) console.log(`  ${change.before === undefined ? "Create" : "Update"} ${change.name}`);
    for (const link of links) console.log(`  ${copy || link.copy ? "Copy" : "Link"} ${link.name}`);
    if (needsToken) console.log("  Auth token: hidden input or --auth-token-stdin required on apply");
    return;
  }
  if (changes.length || links.length) applyChanges(root, destination, existing, links, changes, guards, copy);
  console.log(`${existing ? (changes.length || links.length ? "Refreshed" : "Unchanged") : "Created"} environment: ${env}`);
  if (memory) console.log(`claude-mem: ${memory.CLAUDE_MEM_DATA_DIR} (127.0.0.1:${memory.CLAUDE_MEM_WORKER_PORT})`);
}

void main().catch((error: Error) => {
  console.error(`Claude setup: ${(error as Error).message}`);
  process.exitCode = 2;
});
