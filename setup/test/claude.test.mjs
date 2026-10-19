import assert from "node:assert/strict";
import * as fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const repo = path.resolve(import.meta.dirname, "../..");
const runtime = path.join(repo, "setup/claude.js");

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "claude-setup-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const dotfiles = path.join(root, "dot files");
  const home = path.join(root, "user home");
  const envs = path.join(home, ".claude-profiles");
  const destination = path.join(envs, "acme");
  const write = (file, text) => {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  };
  write(path.join(dotfiles, "claude/profile-settings.json"), '{"model":"sonnet","statusLine":{"type":"command","command":"node statusline.cjs"}}\n');
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
  return { root, dotfiles, home, envs, destination, write, run, initialize, inject };
}

function success(result) { assert.equal(result.status, 0, result.stderr || result.stdout); }

test("creates an independent home with shared links, private settings and explicitly selected skills", t => {
  const f = fixture(t);
  success(f.initialize(["--skill", "one", "--skill", "one"]));
  assert.equal(fs.readFileSync(path.join(f.destination, ".claude-pick"), "utf8"), "1\n");
  assert.equal(fs.readFileSync(path.join(f.destination, "settings.json"), "utf8"), fs.readFileSync(path.join(f.dotfiles, "claude/profile-settings.json"), "utf8"));
  for (const [name, source] of Object.entries({
    "statusline.cjs": "claude/statusline.cjs",
    "rules/00-global.md": "ai-rules/base/global.md",
    "rules/10-claude.md": "ai-rules/agents/claude.md",
    "skills/one": ".agents/user/skills/one",
  })) assert.equal(fs.realpathSync(path.join(f.destination, name)), fs.realpathSync(path.join(f.dotfiles, source)));
  if (process.platform !== "win32") {
    assert.equal(fs.statSync(f.destination).mode & 0o777, 0o700);
    assert.equal(fs.statSync(path.join(f.destination, "settings.json")).mode & 0o777, 0o600);
  }
  assert.equal(fs.existsSync(path.join(f.destination, ".credentials.json")), false);
  assert.equal(fs.existsSync(path.join(f.destination, "mcp.json")), false);
  assert.equal(fs.readFileSync(path.join(f.home, ".claude/settings.json"), "utf8"), '{"enabledPlugins":{"private":true}}\n');
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
  f.write(path.join(f.dotfiles, "claude/profile-settings.json"), "invalid JSON\n");
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.existsSync(f.envs), false);
  f.write(path.join(f.dotfiles, "claude/profile-settings.json"), "{}\n");
  fs.unlinkSync(path.join(f.dotfiles, "claude/statusline.cjs"));
  assert.equal(f.initialize().status, 2);
  assert.equal(fs.existsSync(f.envs), false);
});

test("refreshes existing picker homes without changing settings, credentials, history, MCP or other skills", t => {
  const f = fixture(t);
  success(f.initialize(["--skill", "one"]));
  const local = {
    "settings.json": '{"model":"opus","effortLevel":"high","enabledPlugins":{"local":true}}\n',
    ".credentials.json": "account-a-placeholder\n",
    "history.jsonl": "history-placeholder\n",
    "mcp.json": '{"mcpServers":{"local":{}}}\n',
    "skills/local/SKILL.md": "local skill\n",
  };
  for (const [name, content] of Object.entries(local)) f.write(path.join(f.destination, name), content);
  fs.unlinkSync(path.join(f.destination, "rules/00-global.md"));
  f.write(path.join(f.dotfiles, "claude/profile-settings.json"), '{"model":"haiku"}\n');
  success(f.initialize(["--skill", "two"]));
  success(f.initialize(["--skill", "two"]));
  for (const [name, content] of Object.entries(local)) assert.equal(fs.readFileSync(path.join(f.destination, name), "utf8"), content);
  assert.equal(fs.realpathSync(path.join(f.destination, "rules/00-global.md")), fs.realpathSync(path.join(f.dotfiles, "ai-rules/base/global.md")));
  assert.deepEqual(fs.readdirSync(path.join(f.destination, "skills")).sort(), ["local", "one", "two"]);
  success(f.run(["--env=second"]));
  assert.equal(fs.existsSync(path.join(f.envs, "second/.credentials.json")), false);
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.envs, "second/settings.json"), "utf8")).model, "haiku");
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
  const injected = f.inject(`const fs = require('node:fs');
const original = fs.symlinkSync;
fs.symlinkSync = (source, target, type) => {
  if (target.endsWith('one')) throw new Error('Injected skill link failure');
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
