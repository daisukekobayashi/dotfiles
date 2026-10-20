import assert from "node:assert/strict";
import * as fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as net from "node:net";
import { spawn, spawnSync } from "node:child_process";
import test from "node:test";

const repo = path.resolve(import.meta.dirname, "../..");
const runtime = path.join(repo, "setup/claude.js");

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "claude-setup-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const dotfiles = path.join(root, "dot files");
  const home = path.join(root, "user home");
  const envs = path.join(home, ".claude-envs");
  const destination = path.join(envs, "acme");
  const write = (file, text) => {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  };
  write(path.join(dotfiles, "claude/profile-settings.json"), '{"statusLine":{"type":"command","command":"node statusline.cjs"}}\n');
  write(path.join(dotfiles, "claude/settings.json"), '{"model":"sonnet","effortLevel":"medium","permissions":{"deny":["Read(.env)"]},"statusLine":{"type":"command","command":"node statusline.cjs"},"theme":"light"}\n');
  for (const file of ["claude/statusline.cjs", "ai-rules/base/global.md", "ai-rules/agents/claude.md"]) {
    write(path.join(dotfiles, file), "shared source\n");
  }
  for (const name of ["one", "two"]) write(path.join(dotfiles, ".agents/user/skills", name, "SKILL.md"), `# ${name}\n`);
  write(path.join(home, ".claude/settings.json"), '{"enabledPlugins":{"private":true}}\n');
  const env = { ...process.env, SETUP_HOME: home, SETUP_DOTFILES_ROOT: dotfiles, SETUP_DRY_RUN: "0" };
  const run = (args = [], extra = {}) => spawnSync(process.execPath, [runtime, ...args], { env: { ...env, ...extra }, encoding: "utf8" });
  const initialize = (args = [], extra = {}) => run(["--env", "acme", ...args], extra);
  const inject = source => {
    const preload = path.join(root, "inject.cjs");
    fs.writeFileSync(preload, source);
    return { NODE_OPTIONS: `--require ${JSON.stringify(preload)}` };
  };
  return { root, dotfiles, home, envs, destination, env, write, run, initialize, inject };
}

function success(result) { assert.equal(result.status, 0, result.stderr || result.stdout); }

function snapshot(f) {
  return Object.fromEntries(["settings.json", ".dotfiles-env.json", ".claude-pick"]
    .map(name => [name, fs.readFileSync(path.join(f.destination, name), "utf8")]));
}

function updateSource(f, change) {
  const file = path.join(f.dotfiles, "claude/settings.json");
  const value = JSON.parse(fs.readFileSync(file, "utf8"));
  change(value);
  fs.writeFileSync(file, JSON.stringify(value));
}

test("creates independent settings from the shared source and links every installed skill", t => {
  const f = fixture(t);
  fs.unlinkSync(path.join(f.dotfiles, "claude/profile-settings.json"));
  success(f.initialize(["--skill", "one", "--skill", "one"]));
  assert.equal(fs.readFileSync(path.join(f.destination, ".claude-pick"), "utf8"), "1\n");
  const settings = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"));
  const shared = JSON.parse(fs.readFileSync(path.join(f.dotfiles, "claude/settings.json"), "utf8"));
  assert.deepEqual(settings, { ...shared, env: {
    ...shared.env,
    CLAUDE_MEM_DATA_DIR: path.join(f.destination, "claude-mem"),
    CLAUDE_MEM_WORKER_PORT: settings.env?.CLAUDE_MEM_WORKER_PORT,
    CLAUDE_MEM_WORKER_HOST: "127.0.0.1",
  } });
  assert.equal(fs.lstatSync(path.join(f.destination, "skills")).isSymbolicLink(), false);
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.destination, ".dotfiles-env.json"), "utf8")).env, "acme");
  for (const [name, source] of Object.entries({
    "statusline.cjs": "claude/statusline.cjs",
    "rules/00-global.md": "ai-rules/base/global.md",
    "rules/10-claude.md": "ai-rules/agents/claude.md",
    "skills/one": ".agents/user/skills/one",
    "skills/two": ".agents/user/skills/two",
  })) assert.equal(fs.realpathSync(path.join(f.destination, name)), fs.realpathSync(path.join(f.dotfiles, source)));
  if (process.platform !== "win32") {
    assert.equal(fs.statSync(f.destination).mode & 0o777, 0o700);
    assert.equal(fs.statSync(path.join(f.destination, "settings.json")).mode & 0o777, 0o600);
  }
  assert.equal(fs.existsSync(path.join(f.destination, ".credentials.json")), false);
  assert.equal(fs.existsSync(path.join(f.destination, "mcp.json")), false);
  assert.equal(fs.readFileSync(path.join(f.home, ".claude/settings.json"), "utf8"), '{"enabledPlugins":{"private":true}}\n');
});

test("new environments isolate memory and reserve different ports without copying default data", t => {
  const f = fixture(t);
  const defaultMemory = path.join(f.home, ".claude-mem");
  f.write(path.join(defaultMemory, "settings.json"), '{"CLAUDE_MEM_WORKER_PORT":"37800"}\n');
  f.write(path.join(defaultMemory, "claude-mem.db"), "existing memory placeholder\n");
  updateSource(f, value => { value.env = { KEEP: "shared", CLAUDE_MEM_DATA_DIR: defaultMemory, CLAUDE_MEM_WORKER_PORT: "37800" }; });
  const ports = new Set();
  for (const name of ["acme", "second"]) {
    success(f.run(["--env", name]));
    const destination = path.join(f.envs, name);
    const settings = JSON.parse(fs.readFileSync(path.join(destination, "settings.json"), "utf8"));
    assert.equal(settings.env.CLAUDE_MEM_DATA_DIR, path.join(destination, "claude-mem"));
    assert.equal(settings.env.CLAUDE_MEM_WORKER_HOST, "127.0.0.1");
    assert.equal(settings.env.KEEP, "shared");
    const port = Number(settings.env.CLAUDE_MEM_WORKER_PORT);
    assert.ok(Number.isInteger(port) && port > 37800 && port <= 65535);
    assert.equal(ports.has(port), false);
    ports.add(port);
    const data = path.join(destination, "claude-mem");
    assert.deepEqual(fs.readdirSync(data), ["settings.json"]);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(data, "settings.json"), "utf8")), {
      CLAUDE_MEM_DATA_DIR: data,
      CLAUDE_MEM_WORKER_PORT: String(port),
      CLAUDE_MEM_WORKER_HOST: "127.0.0.1",
    });
    if (process.platform !== "win32") {
      assert.equal(fs.statSync(data).mode & 0o777, 0o700);
      assert.equal(fs.statSync(path.join(data, "settings.json")).mode & 0o777, 0o600);
    }
  }
  assert.equal(fs.readFileSync(path.join(defaultMemory, "claude-mem.db"), "utf8"), "existing memory placeholder\n");
  assert.equal(fs.readFileSync(path.join(defaultMemory, "settings.json"), "utf8"), '{"CLAUDE_MEM_WORKER_PORT":"37800"}\n');
  const before = snapshot(f);
  updateSource(f, value => { value.theme = "dark"; });
  success(f.initialize());
  const refreshed = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"));
  assert.deepEqual(refreshed.env, JSON.parse(before["settings.json"]).env);
  assert.equal(refreshed.theme, "dark");
});

test("new environments skip ports held by active listeners", async t => {
  const f = fixture(t);
  const server = net.createServer();
  const listening = await new Promise((resolve, reject) => {
    server.once("error", error => error.code === "EADDRINUSE" ? resolve(false) : reject(error));
    server.listen({ host: "127.0.0.1", port: 37800 }, () => resolve(true));
  });
  if (listening) t.after(() => new Promise(resolve => server.close(resolve)));
  success(f.initialize());
  const settings = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"));
  assert.notEqual(settings.env.CLAUDE_MEM_WORKER_PORT, "37800");
});

test("concurrent environment creation allocates distinct memory ports", async t => {
  const f = fixture(t);
  const names = ["first", "second", "third", "fourth"];
  const results = await Promise.all(names.map(name => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [runtime, "--env", name], { env: f.env });
    t.after(() => { if (child.exitCode === null) child.kill(); });
    let stdout = "", stderr = "";
    child.stdout.on("data", chunk => { stdout += chunk; });
    child.stderr.on("data", chunk => { stderr += chunk; });
    child.once("error", reject);
    child.once("close", status => resolve({ status, stdout, stderr }));
  })));
  for (const result of results) success(result);
  const ports = names.map(name => JSON.parse(fs.readFileSync(path.join(f.envs, name, "settings.json"), "utf8")).env.CLAUDE_MEM_WORKER_PORT);
  assert.equal(new Set(ports).size, names.length);
});

test("a port recorded by another setup during allocation is not reused", t => {
  const f = fixture(t);
  const peer = path.join(f.envs, "peer/settings.json");
  const injected = f.inject(`const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const original = net.Server.prototype.listen;
let recorded = false;
net.Server.prototype.listen = function(options, callback) {
  return original.call(this, options, () => {
    if (!recorded) {
      recorded = true;
      fs.mkdirSync(path.dirname(${JSON.stringify(peer)}), { recursive: true });
      fs.writeFileSync(${JSON.stringify(peer)}, JSON.stringify({ env: { CLAUDE_MEM_WORKER_PORT: String(options.port) } }));
    }
    callback();
  });
};`);
  success(f.initialize([], injected));
  const selected = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8")).env.CLAUDE_MEM_WORKER_PORT;
  const claimed = JSON.parse(fs.readFileSync(peer, "utf8")).env.CLAUDE_MEM_WORKER_PORT;
  assert.notEqual(selected, claimed);
});

test("a memory settings write failure rolls back the fresh environment", t => {
  const f = fixture(t);
  const target = path.join(f.destination, "claude-mem/settings.json");
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.renameSync;
fs.renameSync = (source, destination) => {
  if (destination === ${JSON.stringify(target)}) throw new Error('Injected memory settings failure');
  return original(source, destination);
};`);
  assert.equal(f.initialize([], injected).status, 2);
  assert.equal(fs.existsSync(f.envs), false);
  success(f.initialize());
});

test("dry-run and invalid input create no directories", t => {
  const f = fixture(t);
  success(f.initialize(["--dry-run"]));
  success(f.initialize([], { SETUP_DRY_RUN: "1" }));
  const invalid = [[], ["--env"], ["--env="], ["--unknown"], ["--env", "default"],
    ...["../bad", "Acme", "two words", "con", "nul", "com1", "lpt9", "a".repeat(65)].map(name => ["--env", name]),
    ["--env", "acme", "--env", "other"], ["--env", "acme", "--skill", "../bad"], ["--env", "acme", "--skill", "missing"]];
  for (const args of invalid) assert.equal(f.run(args).status, 2, JSON.stringify(args));
  assert.equal(fs.existsSync(f.envs), false);
});

test("invalid sources fail before creating an environment", t => {
  const f = fixture(t);
  f.write(path.join(f.dotfiles, "claude/settings.json"), "invalid JSON\n");
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.existsSync(f.envs), false);
  f.write(path.join(f.dotfiles, "claude/settings.json"), "{}\n");
  fs.unlinkSync(path.join(f.dotfiles, "claude/statusline.cjs"));
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.existsSync(f.envs), false);
});

test("refreshes shared settings while preserving local choices, credentials, history, MCP and skills", t => {
  const f = fixture(t);
  success(f.initialize(["--skill", "one"]));
  const local = {
    "settings.json": JSON.stringify({ ...JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8")), model: "opus", effortLevel: "high", enabledPlugins: { local: true } }),
    ".credentials.json": "account-a-placeholder\n",
    "history.jsonl": "history-placeholder\n",
    "mcp.json": '{"mcpServers":{"local":{}}}\n',
    "skills/local/SKILL.md": "local skill\n",
  };
  for (const [name, content] of Object.entries(local)) f.write(path.join(f.destination, name), content);
  fs.unlinkSync(path.join(f.destination, "rules/00-global.md"));
  const shared = JSON.parse(fs.readFileSync(path.join(f.dotfiles, "claude/settings.json"), "utf8"));
  shared.theme = "dark";
  f.write(path.join(f.dotfiles, "claude/settings.json"), JSON.stringify(shared));
  success(f.initialize(["--skill", "two"]));
  success(f.initialize(["--skill", "two"]));
  for (const [name, content] of Object.entries(local)) {
    if (name !== "settings.json") assert.equal(fs.readFileSync(path.join(f.destination, name), "utf8"), content);
  }
  const settings = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"));
  assert.equal(settings.model, "opus");
  assert.equal(settings.effortLevel, "high");
  assert.deepEqual(settings.enabledPlugins, {local: true});
  assert.equal(settings.theme, "dark");
  assert.equal(fs.realpathSync(path.join(f.destination, "rules/00-global.md")), fs.realpathSync(path.join(f.dotfiles, "ai-rules/base/global.md")));
  assert.deepEqual(fs.readdirSync(path.join(f.destination, "skills")).sort(), ["local", "one", "two"]);
  success(f.run(["--env=second"]));
  assert.equal(fs.existsSync(path.join(f.envs, "second/.credentials.json")), false);
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.envs, "second/settings.json"), "utf8")).model, "sonnet");
});

test("rejects unmanaged homes and symlinked environment directories without writes", t => {
  const f = fixture(t);
  fs.mkdirSync(f.destination, { recursive: true });
  f.write(path.join(f.destination, "settings.json"), "user-owned\n");
  assert.equal(f.initialize().status, 2);
  assert.deepEqual(fs.readdirSync(f.destination), ["settings.json"]);
  fs.renameSync(f.destination, path.join(f.root, "unmanaged"));
  fs.symlinkSync(path.join(f.root, "unmanaged"), f.destination, "dir");
  assert.equal(f.initialize().status, 2);
  fs.unlinkSync(f.destination);
  fs.rmdirSync(f.envs);
  fs.symlinkSync(path.join(f.root, "unmanaged"), f.envs, "dir");
  assert.equal(f.initialize().status, 2);
  assert.deepEqual(fs.readdirSync(path.join(f.root, "unmanaged")), ["settings.json"]);
});

test("preflights conflicting shared entries before adding missing links", t => {
  const f = fixture(t);
  success(f.initialize());
  fs.unlinkSync(path.join(f.destination, "rules/00-global.md"));
  fs.unlinkSync(path.join(f.destination, "statusline.cjs"));
  fs.unlinkSync(path.join(f.destination, "skills/one"));
  f.write(path.join(f.destination, "statusline.cjs"), "local renderer\n");
  assert.equal(f.initialize(["--skill", "one"]).status, 2);
  assert.equal(fs.readFileSync(path.join(f.destination, "statusline.cjs"), "utf8"), "local renderer\n");
  assert.equal(fs.existsSync(path.join(f.destination, "rules/00-global.md")), false);
  assert.equal(fs.existsSync(path.join(f.destination, "skills/one")), false);
});

test("rejects settings and rules symlinks without modifying their targets", t => {
  const f = fixture(t);
  success(f.initialize());
  fs.unlinkSync(path.join(f.destination, "settings.json"));
  const target = path.join(f.root, "settings.json");
  f.write(target, "local settings\n");
  fs.symlinkSync(target, path.join(f.destination, "settings.json"));
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.readFileSync(target, "utf8"), "local settings\n");
  fs.unlinkSync(path.join(f.destination, "settings.json"));
  f.write(path.join(f.destination, "settings.json"), "local settings\n");
  fs.renameSync(path.join(f.destination, "rules"), path.join(f.root, "rules"));
  fs.symlinkSync(path.join(f.root, "rules"), path.join(f.destination, "rules"), "dir");
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.readdirSync(path.join(f.root, "rules")).length, 2);
});

test("failed creation rolls back only its own entries and keeps concurrent additions", t => {
  const f = fixture(t);
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.symlinkSync;
fs.symlinkSync = (source, target, type) => {
  if (target.endsWith('10-claude.md')) {
    fs.writeFileSync(require('node:path').join(require('node:path').dirname(target), 'concurrent.txt'), 'keep');
    throw Object.assign(new Error('Injected failure'), { code: 'EPERM' });
  }
  return original(source, target, type);
};`);
  const result = f.initialize([], injected);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Cannot create a shared-file symlink/);
  assert.equal(fs.existsSync(path.join(f.destination, ".claude-pick")), false);
  assert.deepEqual(fs.readdirSync(f.destination), ["rules"]);
  assert.equal(fs.readFileSync(path.join(f.destination, "rules/concurrent.txt"), "utf8"), "keep");
});

test("a failed new environment leaves no incomplete home when there are no concurrent additions", t => {
  const f = fixture(t);
  const injected = f.inject(`require('node:fs').symlinkSync = () => { throw new Error('Injected link failure'); };`);
  assert.equal(f.initialize([], injected).status, 2);
  assert.equal(fs.existsSync(f.envs), false);
  assert.equal(fs.readFileSync(path.join(f.home, ".claude/settings.json"), "utf8"), '{"enabledPlugins":{"private":true}}\n');
});

test("failed refresh removes additions while retaining the existing environment", t => {
  const f = fixture(t);
  success(f.initialize());
  const settings = fs.readFileSync(path.join(f.destination, "settings.json"), "utf8");
  fs.unlinkSync(path.join(f.destination, "rules/00-global.md"));
  f.write(path.join(f.dotfiles, ".agents/user/skills/three/SKILL.md"), "# Three\n");
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.symlinkSync;
fs.symlinkSync = (source, target, type) => {
  if (target.endsWith('three')) throw new Error('Injected skill link failure');
  return original(source, target, type);
};`);
  assert.equal(f.initialize(["--skill", "one"], injected).status, 2);
  assert.equal(fs.existsSync(path.join(f.destination, "rules/00-global.md")), false);
  assert.equal(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"), settings);
  assert.equal(fs.readFileSync(path.join(f.destination, ".claude-pick"), "utf8"), "1\n");
  assert.equal(fs.existsSync(path.join(f.destination, "statusline.cjs")), true);
});

test("a concurrently created home is never adopted or removed", t => {
  const f = fixture(t);
  const injected = f.inject(`const fs = require('node:fs');
const path = require('node:path');
const original = fs.mkdirSync;
fs.mkdirSync = (file, options) => {
  if (file === ${JSON.stringify(f.destination)}) {
    original(file, options);
    fs.writeFileSync(path.join(file, 'user-owned'), 'keep');
  }
  return original(file, options);
};`);
  assert.equal(f.initialize([], injected).status, 2);
  assert.deepEqual(fs.readdirSync(f.destination), ["user-owned"]);
  assert.equal(fs.readFileSync(path.join(f.destination, "user-owned"), "utf8"), "keep");
});

test("repeat generation is a no-op and preserves local formatting and deleted settings", t => {
  const f = fixture(t);
  success(f.initialize());
  const value = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"));
  delete value.theme;
  const text = JSON.stringify(value) + "\n\n";
  fs.writeFileSync(path.join(f.destination, "settings.json"), text);
  const before = snapshot(f);
  const result = f.initialize();
  success(result);
  assert.match(result.stdout, /Unchanged environment/);
  assert.deepEqual(snapshot(f), before);
  assert.equal(fs.existsSync(path.join(f.destination, ".dotfiles-claude-backups")), false);
});

test("new shared skills appear on refresh and definitions update across isolated homes", t => {
  const f = fixture(t);
  success(f.initialize());
  success(f.run(["--env", "second"]));
  for (const name of ["acme", "second"]) f.write(path.join(f.envs, name, "skills/synced/account/SKILL.md"), name);
  f.write(path.join(f.dotfiles, ".agents/user/skills/one/SKILL.md"), "updated shared definition\n");
  f.write(path.join(f.dotfiles, ".agents/user/skills/three/SKILL.md"), "new shared definition\n");
  // Account sync data and installer metadata are not dotfiles skill definitions.
  f.write(path.join(f.dotfiles, ".agents/user/skills/synced/SKILL.md"), "not shared\n");
  f.write(path.join(f.dotfiles, ".agents/user/skills/manifest.json"), "{}\n");
  success(f.initialize());
  success(f.run(["--env", "second"]));
  for (const name of ["acme", "second"]) {
    const root = path.join(f.envs, name, "skills");
    assert.equal(fs.readFileSync(path.join(root, "one/SKILL.md"), "utf8"), "updated shared definition\n");
    assert.equal(fs.readFileSync(path.join(root, "three/SKILL.md"), "utf8"), "new shared definition\n");
    assert.equal(fs.readFileSync(path.join(root, "synced/account/SKILL.md"), "utf8"), name);
    assert.equal(fs.existsSync(path.join(root, "manifest.json")), false);
  }
});

test("an existing local skill with a shared name is not replaced", t => {
  const f = fixture(t);
  success(f.initialize());
  fs.unlinkSync(path.join(f.destination, "skills/one"));
  f.write(path.join(f.destination, "skills/one/SKILL.md"), "local definition\n");
  const before = snapshot(f);
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.readFileSync(path.join(f.destination, "skills/one/SKILL.md"), "utf8"), "local definition\n");
  assert.deepEqual(snapshot(f), before);
});

test("missing installed skills allow a fresh environment and are added after restoration", t => {
  const f = fixture(t);
  fs.renameSync(path.join(f.dotfiles, ".agents/user/skills"), path.join(f.root, "saved-skills"));
  success(f.initialize());
  assert.deepEqual(fs.readdirSync(path.join(f.destination, "skills")), []);
  fs.renameSync(path.join(f.root, "saved-skills"), path.join(f.dotfiles, ".agents/user/skills"));
  success(f.initialize());
  assert.deepEqual(fs.readdirSync(path.join(f.destination, "skills")), ["one", "two"]);
});

test("legacy minimal-template homes migrate with their local settings and state intact", t => {
  const f = fixture(t);
  const legacy = '{"statusLine":{"type":"command","command":"node statusline.cjs"},"model":"local-model","permissions":{"allow":["Read(src/**)"]}}\n';
  f.write(path.join(f.destination, ".claude-pick"), "1\n");
  f.write(path.join(f.destination, "settings.json"), legacy);
  f.write(path.join(f.destination, ".credentials.json"), "old-account-placeholder\n");
  success(f.initialize());
  const settings = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"));
  assert.equal(settings.model, "local-model");
  assert.equal(settings.effortLevel, "medium");
  assert.deepEqual(settings.permissions, { deny: ["Read(.env)"], allow: ["Read(src/**)"] });
  assert.equal(fs.readFileSync(path.join(f.destination, ".credentials.json"), "utf8"), "old-account-placeholder\n");
  const backupRoot = path.join(f.destination, ".dotfiles-claude-backups");
  assert.equal(fs.readFileSync(path.join(backupRoot, fs.readdirSync(backupRoot)[0], "settings.json"), "utf8"), legacy);
  const baseline = JSON.parse(fs.readFileSync(path.join(f.destination, ".dotfiles-env.json"), "utf8"));
  assert.equal(baseline.settings.model, "sonnet");
  const before = snapshot(f);
  success(f.initialize());
  assert.deepEqual(snapshot(f), before);
});

test("conflicting settings and invalid baselines stop before writing settings or links", t => {
  const f = fixture(t);
  success(f.initialize());
  const local = JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"));
  local.model = "local-private-value";
  fs.writeFileSync(path.join(f.destination, "settings.json"), JSON.stringify(local));
  updateSource(f, value => { value.model = "other-private-value"; });
  fs.unlinkSync(path.join(f.destination, "rules/00-global.md"));
  const before = snapshot(f);
  const result = f.initialize();
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Conflicting local and dotfiles changes: settings.json.model/);
  assert.doesNotMatch(result.stderr, /private-value/);
  assert.deepEqual(snapshot(f), before);
  assert.equal(fs.existsSync(path.join(f.destination, "rules/00-global.md")), false);
  assert.equal(fs.existsSync(path.join(f.destination, ".dotfiles-claude-backups")), false);
  fs.writeFileSync(path.join(f.destination, ".dotfiles-env.json"), '{"version":99}\n');
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.existsSync(path.join(f.destination, "rules/00-global.md")), false);
});

test("a failed legacy migration restores the original settings before allowing retry", t => {
  const f = fixture(t);
  const original = '{"statusLine":{"type":"command","command":"node statusline.cjs"},"model":"local-model"}\n';
  f.write(path.join(f.destination, ".claude-pick"), "1\n");
  f.write(path.join(f.destination, "settings.json"), original);
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.renameSync;
fs.renameSync = (source, target) => {
  if (target.endsWith('.dotfiles-env.json')) throw new Error('Injected migration failure');
  return original(source, target);
};`);
  assert.equal(f.initialize([], injected).status, 2);
  assert.equal(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"), original);
  assert.equal(fs.readFileSync(path.join(f.destination, ".claude-pick"), "utf8"), "1\n");
  assert.equal(fs.existsSync(path.join(f.destination, ".dotfiles-env.json")), false);
  assert.equal(fs.existsSync(path.join(f.destination, "statusline.cjs")), false);
  success(f.initialize());
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8")).model, "local-model");
});

test("refresh dry-run reports settings and skills without changing files or baselines", t => {
  const f = fixture(t);
  success(f.initialize());
  const before = snapshot(f);
  updateSource(f, value => { value.theme = "dark"; });
  f.write(path.join(f.dotfiles, ".agents/user/skills/three/SKILL.md"), "# Three\n");
  const result = f.initialize(["--dry-run"]);
  success(result);
  assert.match(result.stdout, /Update settings.json/);
  assert.match(result.stdout, /Link skills\/three/);
  assert.deepEqual(snapshot(f), before);
  assert.equal(fs.existsSync(path.join(f.destination, "skills/three")), false);
});

test("a failed baseline replacement restores settings and additions, then permits retry", t => {
  const f = fixture(t);
  success(f.initialize());
  const before = snapshot(f);
  updateSource(f, value => { value.theme = "dark"; });
  f.write(path.join(f.dotfiles, ".agents/user/skills/three/SKILL.md"), "# Three\n");
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.renameSync;
fs.renameSync = (source, target) => {
  if (target.endsWith('.dotfiles-env.json')) throw new Error('Injected baseline replacement failure');
  return original(source, target);
};`);
  assert.equal(f.initialize([], injected).status, 2);
  assert.deepEqual(snapshot(f), before);
  assert.equal(fs.existsSync(path.join(f.destination, "skills/three")), false);
  assert.equal(fs.readdirSync(f.destination).some(name => name.startsWith('.dotfiles-claude-stage-')), false);
  const backupRoot = path.join(f.destination, ".dotfiles-claude-backups");
  const backup = path.join(backupRoot, fs.readdirSync(backupRoot)[0]);
  assert.equal(fs.readFileSync(path.join(backup, "settings.json"), "utf8"), before['settings.json']);
  success(f.initialize());
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8")).theme, "dark");
});

test("concurrent settings saves before replacement are preserved and do not advance the baseline", t => {
  const f = fixture(t);
  success(f.initialize());
  const before = snapshot(f);
  updateSource(f, value => { value.theme = "dark"; });
  f.write(path.join(f.dotfiles, ".agents/user/skills/three/SKILL.md"), "# Three\n");
  const saved = '{"model":"concurrent-local-choice"}\n';
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.symlinkSync;
fs.symlinkSync = (source, target, type) => {
  if (target.endsWith('three')) fs.writeFileSync(${JSON.stringify(path.join(f.destination, 'settings.json'))}, ${JSON.stringify(saved)});
  return original(source, target, type);
};`);
  const result = f.initialize([], injected);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Target changed during generation/);
  assert.equal(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"), saved);
  assert.equal(fs.readFileSync(path.join(f.destination, ".dotfiles-env.json"), "utf8"), before['.dotfiles-env.json']);
  assert.equal(fs.existsSync(path.join(f.destination, "skills/three")), false);
});

test("a concurrent save after settings replacement survives rollback with recovery files retained", t => {
  const f = fixture(t);
  success(f.initialize());
  const before = snapshot(f);
  updateSource(f, value => { value.theme = "dark"; });
  const saved = '{"model":"concurrent-local-choice"}\n';
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.renameSync;
fs.renameSync = (source, target) => {
  const result = original(source, target);
  if (target.endsWith('settings.json')) fs.writeFileSync(target, ${JSON.stringify(saved)});
  return result;
};`);
  const result = f.initialize([], injected);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Rollback stopped because a target changed/);
  assert.equal(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"), saved);
  assert.equal(fs.readFileSync(path.join(f.destination, ".dotfiles-env.json"), "utf8"), before['.dotfiles-env.json']);
  assert.equal(fs.readdirSync(f.destination).some(name => name.startsWith('.dotfiles-claude-stage-')), true);
});
