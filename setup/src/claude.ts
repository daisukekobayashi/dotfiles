import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { isDeepStrictEqual } from "node:util";

type Table = Record<string, unknown>;
type Link = { name: string; source: string; directory?: boolean };
type Guard = { name: string; before: string | undefined };
type Change = Guard & { after: string };

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

function applyChanges(root: string, destination: string, existing: boolean, links: Link[], changes: Change[], guards: Guard[]): void {
  const createdLinks: { file: string; stat: fs.Stats }[] = [];
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
  const checkFiles = () => {
    directory(root, "Claude environment directory");
    directory(destination, "Claude environment home");
    for (const name of ["rules", "skills", ...(!existing ? ["claude-mem"] : [])]) directory(path.join(destination, name), `${name} directory`);
    for (const guard of guards) {
      const expected = applied.find(change => change.name === guard.name)?.after ?? guard.before;
      if (readOptional(path.join(destination, guard.name), guard.name) !== expected) {
        throw new Error(`Target changed during generation: ${guard.name}`);
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
        if (change.before !== undefined) fs.writeFileSync(path.join(backup, change.name), change.before, { flag: "wx", mode: 0o600 });
      }
    }
    for (const link of links) {
      const target = path.join(destination, link.name);
      try { fs.symlinkSync(link.source, target, link.directory ? "dir" : "file"); } catch (error) {
        if (["EPERM", "EACCES"].includes((error as NodeJS.ErrnoException).code || "")) {
          throw new Error("Cannot create a shared-file symlink. On Windows, enable Developer Mode or use an appropriately privileged terminal for setup.");
        }
        throw error;
      }
      createdLinks.push({ file: target, stat: fs.lstatSync(target) });
    }
    checkFiles();
    for (let i = 0; i < changes.length; i++) {
      checkFiles();
      fs.renameSync(path.join(stage, `${i}.new`), path.join(destination, changes[i].name));
      applied.push(changes[i]);
    }
    complete = true;
  } catch (error) {
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
      throw restoreError;
    }
    throw error;
  } finally {
    if (!complete) {
      for (const { file, stat } of createdLinks.reverse()) {
        const current = entry(file);
        if (current?.dev === stat.dev && current.ino === stat.ino) fs.unlinkSync(file);
      }
    }
    if (stage && !keepStage) {
      for (const file of fs.readdirSync(stage)) fs.unlinkSync(path.join(stage, file));
      fs.rmdirSync(stage);
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
  const skills = new Set<string>();
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      console.log(`Usage: setup claude --env NAME [--dry-run]

Create or refresh a named Claude Code environment without login or launch.
Generate settings from claude/settings.json; preserve independent local edits.
Conflicting edits stop before writes. Previous settings are backed up on refresh.
All installed dotfiles user skills, shared rules and statusline use symlinks.
New environments get a private claude-mem data directory and unused worker port.
Legacy --skill NAME validates that a skill is installed; it does not filter sharing.
The default environment keeps using setup links.
Names: 1-64 lowercase letters, digits, hyphens, underscores; start with a letter.`);
      return;
    }
    if (arg === "--dry-run") { dryRun = true; continue; }
    if (arg === "--env" || arg === "--skill" || arg.startsWith("--env=")) {
      const value = arg.startsWith("--env=") ? arg.slice(6) : args[++i];
      if (!value || value.startsWith("-")) throw new Error(`${arg.split("=")[0]} requires a value`);
      if (arg === "--skill") skills.add(value);
      else {
        if (env && env !== value) throw new Error("Environment specified twice with different names");
        env = value;
      }
    } else throw new Error(`Unknown Claude setup argument: ${arg}`);
  }
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
  const root = path.join(home, ".claude-profiles");
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

  const source = readSettings(readOptional(path.join(dotfiles, "claude/settings.json"), "claude/settings.json"), "claude/settings.json");
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
    if (baselineBefore !== undefined) {
      const baseline = readSettings(baselineBefore, ".dotfiles-env.json");
      if (baseline.version !== 1 || baseline.env !== env || !table(baseline.settings)) throw new Error("Invalid Claude environment baseline");
      previous = baseline.settings;
    } else {
      previous = readSettings(readOptional(path.join(dotfiles, "claude/profile-settings.json"), "claude/profile-settings.json"), "claude/profile-settings.json");
    }
    settings = mergeSettings(previous, current, source, "settings.json", baselineBefore === undefined) as Table;
  }
  const settingsAfter = settingsBefore !== undefined && isDeepStrictEqual(settings, readSettings(settingsBefore, "settings.json"))
    ? settingsBefore : JSON.stringify(settings, null, 2) + "\n";
  const baseline = { version: 1, env, settings: source };
  const baselineAfter = baselineBefore !== undefined && isDeepStrictEqual(readSettings(baselineBefore, ".dotfiles-env.json"), baseline)
    ? baselineBefore : JSON.stringify(baseline, null, 2) + "\n";
  const guards: Guard[] = [
    { name: "settings.json", before: settingsBefore },
    { name: ".dotfiles-env.json", before: baselineBefore },
    { name: ".claude-pick", before: markerBefore },
    ...(!existing ? [{ name: "claude-mem/settings.json", before: undefined }] : []),
  ];
  const changes: Change[] = [
    { ...guards[0], after: settingsAfter },
    { ...guards[1], after: baselineAfter },
    ...(!existing ? [
      { ...guards[3], after: JSON.stringify(memory, null, 2) + "\n" },
      { ...guards[2], after: "1\n" },
    ] : []),
  ].filter(change => change.before !== change.after);

  const candidates: Link[] = [
    { name: "statusline.cjs", source: path.join(dotfiles, "claude/statusline.cjs") },
    { name: "rules/00-global.md", source: path.join(dotfiles, "ai-rules/base/global.md") },
    { name: "rules/10-claude.md", source: path.join(dotfiles, "ai-rules/agents/claude.md") },
    ...sharedSkills(dotfiles, skills),
  ];
  const links: Link[] = [];
  for (const link of candidates) {
    if (!fs.existsSync(link.source) || !(link.directory ? fs.statSync(link.source).isDirectory() : fs.statSync(link.source).isFile())) {
      throw new Error(`Missing shared file for ${link.name}`);
    }
    const target = path.join(destination, link.name);
    const stat = entry(target);
    if (stat) {
      if (!stat.isSymbolicLink() || path.resolve(path.dirname(target), fs.readlinkSync(target)) !== link.source) {
        throw new Error(`Refusing to replace an existing entry: ${link.name}`);
      }
    } else links.push(link);
  }

  if (dryRun) {
    console.log(`Would ${existing ? "refresh" : "create"} environment: ${env}`);
    if (memory) console.log(`  claude-mem: ${memory.CLAUDE_MEM_DATA_DIR} (127.0.0.1:${memory.CLAUDE_MEM_WORKER_PORT})`);
    for (const change of changes) console.log(`  ${change.before === undefined ? "Create" : "Update"} ${change.name}`);
    for (const link of links) console.log(`  Link ${link.name}`);
    return;
  }
  if (changes.length || links.length) applyChanges(root, destination, existing, links, changes, guards);
  console.log(`${existing ? (changes.length || links.length ? "Refreshed" : "Unchanged") : "Created"} environment: ${env}`);
  if (memory) console.log(`claude-mem: ${memory.CLAUDE_MEM_DATA_DIR} (127.0.0.1:${memory.CLAUDE_MEM_WORKER_PORT})`);
}

void main().catch((error: Error) => {
  console.error(`Claude setup: ${(error as Error).message}`);
  process.exitCode = 2;
});
