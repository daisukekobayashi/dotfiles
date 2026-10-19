import assert from "node:assert/strict";
import * as fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { parse, stringify } from "smol-toml";

const repo = path.resolve(import.meta.dirname, "../..");
const runtime = path.join(repo, "setup/codex.js");
const profile = "azure_gpt-6_1-sol_max";
const baseUrl = "https://example.openai.azure.com/openai";
const apiVersion = "2025-04-01-preview";

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codex-setup-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const dotfiles = path.join(root, "dot files");
  const home = path.join(root, "user home");
  const azure = path.join(home, ".codex-azure");
  const source = path.join(dotfiles, "codex/config.toml");
  const write = (file, text) => {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  };
  write(source, `model = "subscription-default"
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
forced_login_method = "chatgpt"
forced_chatgpt_workspace_id = "main-workspace"
log_dir = "/main-only/logs"
sqlite_home = "/main-only/state"
[features]
hooks = true
[mcp_servers.example]
command = "node"
args = ["two words", "quote \\\" and #"]
[tui]
status_line = ["model-name", "context-remaining"]
model_availability_nux = { "main-model" = true }
screen_reader_detection_done = true
[notice]
hide_rate_limit_model_nudge = true
[notice.model_migrations]
"old" = "new"
[projects."/main-only"]
trust_level = "trusted"
[hooks.state."main-source"]
trusted_hash = "main-only-hash"
`);
  write(path.join(dotfiles, `codex/${profile}.config.toml`), `model = "gpt-6.1-sol"
model_provider = "azure"
model_reasoning_effort = "max"
[projects."/profile-main-only"]
trust_level = "trusted"
[hooks.state."profile-main-source"]
trusted_hash = "profile-main-only-hash"
`);
  write(path.join(dotfiles, "codex/azure_gpt-6-luna_max.config.toml"), 'model = "gpt-6-luna"\nmodel_provider = "azure"\nmodel_reasoning_effort = "max"\n');
  write(path.join(dotfiles, "codex/hooks.json"), '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"example cleanup"}]}]}}\n');
  write(path.join(dotfiles, "codex/rules/user.rules"), 'prefix_rule(pattern=["git", "status"], decision="allow")\n');
  write(path.join(dotfiles, "ai-rules/base/global.md"), "# Shared rules\n\nKeep changes focused.\n");
  write(path.join(dotfiles, "ai-rules/agents/codex.md"), "# Codex rules\n\nUse existing checks.\n");
  write(path.join(home, ".codex/auth.json"), '{"auth_mode":"chatgpt"}\n');
  fs.symlinkSync(source, path.join(home, ".codex/config.toml"));
  const env = { ...process.env, SETUP_HOME: home, SETUP_DOTFILES_ROOT: dotfiles, SETUP_DRY_RUN: "0" };
  delete env.AZURE_OPENAI_API_KEY;
  const run = (args = [], extra = {}) => spawnSync(process.execPath, [runtime, ...args], { env: { ...env, ...extra }, encoding: "utf8" });
  const initialize = (args = [], extra = {}) => run(["--azure-base-url", baseUrl, "--azure-api-version", apiVersion, ...args], extra);
  const config = (name = "config.toml") => parse(fs.readFileSync(path.join(azure, name), "utf8"));
  const updateSource = update => {
    const value = parse(fs.readFileSync(source, "utf8"));
    update(value);
    fs.writeFileSync(source, stringify(value));
  };
  return { root, dotfiles, home, azure, source, env, run, initialize, config, write, updateSource };
}

function success(result) {
  assert.equal(result.status, 0, result.stderr || result.stdout);
}

function managedSnapshot(azure) {
  const marker = fs.readFileSync(path.join(azure, ".dotfiles-azure.json"), "utf8");
  return Object.fromEntries([".dotfiles-azure.json", ...Object.keys(JSON.parse(marker).files)]
    .map(name => [name, fs.readFileSync(path.join(azure, name), "utf8")]));
}

test("generates Azure defaults, all profiles and shared assets without altering the main home", t => {
  const f = fixture(t);
  const original = fs.readFileSync(f.source, "utf8");
  success(f.initialize());
  for (const name of ["config.toml", `${profile}.config.toml`, "azure_gpt-6-luna_max.config.toml"]) {
    const config = f.config(name);
    assert.equal(config.model_provider, "azure");
    assert.equal(config.cli_auth_credentials_store, "file");
    assert.equal(config.model_providers.azure.env_key, "AZURE_OPENAI_API_KEY");
    assert.equal(config.model_providers.azure.requires_openai_auth, false);
    assert.equal(config.model_providers.azure.base_url, baseUrl);
    assert.equal(config.model_providers.azure.query_params["api-version"], apiVersion);
    assert.equal(config.projects, undefined);
    assert.equal(config.hooks, undefined);
    assert.equal(config.tui.model_availability_nux, undefined);
    assert.equal(config.tui.screen_reader_detection_done, undefined);
    assert.equal(config.notice.model_migrations, undefined);
    assert.equal(config.notice.hide_rate_limit_model_nudge, true);
    for (const key of ["forced_login_method", "forced_chatgpt_workspace_id", "log_dir", "sqlite_home"]) assert.equal(config[key], undefined);
    assert.deepEqual(config.tui.status_line, ["model-name", "context-remaining"]);
    assert.deepEqual(config.mcp_servers.example.args, ["two words", 'quote " and #']);
    assert.equal(fs.lstatSync(path.join(f.azure, name)).isSymbolicLink(), false);
  }
  assert.equal(f.config().model, "gpt-6.1-sol");
  assert.equal(f.config("azure_gpt-6-luna_max.config.toml").model, "gpt-6-luna");
  for (const name of ["hooks.json", "rules/user.rules"]) {
    assert.equal(fs.readFileSync(path.join(f.azure, name), "utf8"), fs.readFileSync(path.join(f.dotfiles, "codex", name), "utf8"));
  }
  const expectedRules = fs.readFileSync(path.join(f.dotfiles, "ai-rules/base/global.md"), "utf8") +
    "\n---\n\n" + fs.readFileSync(path.join(f.dotfiles, "ai-rules/agents/codex.md"), "utf8") + "\n";
  assert.equal(fs.readFileSync(path.join(f.azure, "AGENTS.md"), "utf8"), expectedRules);
  assert.equal(fs.readFileSync(f.source, "utf8"), original);
  assert.equal(fs.readlinkSync(path.join(f.home, ".codex/config.toml")), f.source);
  assert.equal(fs.readFileSync(path.join(f.home, ".codex/auth.json"), "utf8"), '{"auth_mode":"chatgpt"}\n');
  for (const name of ["auth.json", "sessions", "plugins", "memories", "skills"]) assert.equal(fs.existsSync(path.join(f.azure, name)), false);
});

test("dry-run validates inputs and creates no Azure home", t => {
  const f = fixture(t);
  const result = f.initialize(["--dry-run"]);
  success(result);
  assert.match(result.stdout, /Would write/);
  assert.equal(fs.existsSync(f.azure), false);
  success(f.initialize([], { SETUP_DRY_RUN: "1" }));
  assert.equal(fs.existsSync(f.azure), false);
});

test("repeated generation is a no-op and preserves comments and Azure runtime state", t => {
  const f = fixture(t);
  success(f.initialize());
  const config = f.config();
  config.projects = { "/azure-only": { trust_level: "trusted" } };
  config.hooks = { state: { "azure-source": { trusted_hash: "azure-only-hash" } } };
  config.tui.model_availability_nux = { "azure-model": true };
  const file = path.join(f.azure, "config.toml");
  const text = "# Local comment\n" + stringify(config);
  fs.writeFileSync(file, text);
  const before = fs.statSync(file).mtimeMs;
  const result = f.run();
  success(result);
  assert.match(result.stdout, /already up to date/);
  assert.equal(fs.readFileSync(file, "utf8"), text);
  assert.equal(fs.statSync(file).mtimeMs, before);
  assert.equal(fs.existsSync(path.join(f.azure, ".dotfiles-azure-backups")), false);
});

test("shared updates preserve independent Azure changes and back up replaced files", t => {
  const f = fixture(t);
  success(f.initialize());
  const config = f.config();
  config.projects = { "/azure-only": { trust_level: "trusted" } };
  config.model_reasoning_effort = "high";
  fs.writeFileSync(path.join(f.azure, "config.toml"), stringify(config));
  const before = fs.readFileSync(path.join(f.azure, "config.toml"), "utf8");
  f.write(path.join(f.azure, "auth.json"), "azure-local-auth-placeholder\n");
  f.write(path.join(f.azure, "sessions/local.jsonl"), "azure-session\n");
  f.updateSource(value => { value.sandbox_mode = "read-only"; });
  success(f.run());
  assert.equal(f.config().sandbox_mode, "read-only");
  assert.equal(f.config().model_reasoning_effort, "high");
  assert.equal(f.config().projects["/azure-only"].trust_level, "trusted");
  assert.equal(fs.readFileSync(path.join(f.azure, "auth.json"), "utf8"), "azure-local-auth-placeholder\n");
  assert.equal(fs.readFileSync(path.join(f.azure, "sessions/local.jsonl"), "utf8"), "azure-session\n");
  const backups = path.join(f.azure, ".dotfiles-azure-backups");
  const backup = fs.readdirSync(backups)[0];
  assert.equal(fs.readFileSync(path.join(backups, backup, "config.toml"), "utf8"), before);
  success(f.run());
});

test("runtime additions in a generated model profile survive synchronization", t => {
  const f = fixture(t);
  success(f.initialize());
  const name = `${profile}.config.toml`;
  const config = f.config(name);
  config.hooks = { state: { local: { trusted_hash: "local" } } };
  fs.writeFileSync(path.join(f.azure, name), stringify(config));
  f.updateSource(value => { value.model_reasoning_summary = "detailed"; });
  success(f.run());
  assert.equal(f.config(name).model_reasoning_summary, "detailed");
  assert.equal(f.config(name).hooks.state.local.trusted_hash, "local");
});

test("conflicting shared and local edits stop before any managed file changes", t => {
  const f = fixture(t);
  success(f.initialize());
  const config = f.config(`${profile}.config.toml`);
  config.sandbox_mode = "danger-full-access";
  fs.writeFileSync(path.join(f.azure, `${profile}.config.toml`), stringify(config));
  const before = managedSnapshot(f.azure);
  f.updateSource(value => { value.sandbox_mode = "read-only"; });
  const result = f.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Conflicting local and dotfiles changes: .*sandbox_mode/);
  assert.deepEqual(managedSnapshot(f.azure), before);
});

test("provider or credential-store changes cannot silently reroute the generated home", t => {
  for (const [key, value] of [["model_provider", "openai"], ["cli_auth_credentials_store", "keyring"]]) {
    const f = fixture(t);
    success(f.initialize());
    const config = f.config();
    config[key] = value;
    fs.writeFileSync(path.join(f.azure, "config.toml"), stringify(config));
    const before = managedSnapshot(f.azure);
    const result = f.run();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Azure provider or credential isolation/);
    assert.deepEqual(managedSnapshot(f.azure), before);
  }
});

test("a chosen Azure default persists on later generation without flags", t => {
  const f = fixture(t);
  success(f.initialize(["--profile", "azure_gpt-6-luna_max"]));
  assert.equal(f.config().model, "gpt-6-luna");
  success(f.run());
  assert.equal(f.config().model, "gpt-6-luna");
});

test("unmanaged files are preserved and cause a preflight failure", t => {
  const f = fixture(t);
  f.write(path.join(f.azure, "hooks.json"), "user-owned\n");
  const result = f.initialize();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /unmanaged file/);
  assert.equal(fs.readFileSync(path.join(f.azure, "hooks.json"), "utf8"), "user-owned\n");
  assert.equal(fs.existsSync(path.join(f.azure, "config.toml")), false);
});

test("symlinked homes, managed files and rule directories are rejected", t => {
  for (const target of ["home", "config.toml", "rules"]) {
    const f = fixture(t);
    const other = path.join(f.root, "other");
    fs.mkdirSync(other);
    if (target === "home") fs.symlinkSync(other, f.azure);
    else {
      fs.mkdirSync(f.azure);
      fs.symlinkSync(target === "config.toml" ? f.source : other, path.join(f.azure, target));
    }
    const result = f.initialize();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /symlink/);
    assert.equal(fs.existsSync(path.join(f.azure, ".dotfiles-azure.json")), false);
  }
});

test("invalid TOML and hooks JSON are reported without source excerpts or writes", t => {
  for (const name of ["config.toml", "hooks.json"]) {
    const f = fixture(t);
    f.write(path.join(f.dotfiles, "codex", name), 'do-not-echo-this-value = "unterminated');
    const result = f.initialize();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Invalid (TOML|JSON)/);
    assert.doesNotMatch(result.stderr, /do-not-echo/);
    assert.equal(fs.existsSync(f.azure), false);
  }
});

test("failed replacement rolls back artifacts and the saved connection, then permits a clean retry", t => {
  const f = fixture(t);
  success(f.initialize());
  const before = managedSnapshot(f.azure);
  f.updateSource(value => { value.sandbox_mode = "read-only"; });
  const script = `
    const fs = require('node:fs');
    const rename = fs.renameSync;
    let replacements = 0;
    fs.renameSync = (from, to) => {
      if (from.endsWith('.new') && ++replacements === 2) throw new Error('injected replacement failure');
      return rename(from, to);
    };
    require(${JSON.stringify(runtime)}).main(['--azure-base-url', 'https://replacement.example/openai']);
  `;
  const result = spawnSync(process.execPath, ["-e", script], { env: f.env, encoding: "utf8" });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /injected replacement failure/);
  assert.deepEqual(managedSnapshot(f.azure), before);
  assert.equal(fs.readdirSync(f.azure).some(name => name.startsWith(".dotfiles-azure-stage-")), false);
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.azure, ".dotfiles-azure.json"), "utf8")).azureProvider.base_url, baseUrl);
  success(f.run(["--azure-base-url", "https://replacement.example/openai"]));
  assert.equal(f.config().sandbox_mode, "read-only");
  assert.equal(f.config().model_providers.azure.base_url, "https://replacement.example/openai");
  success(f.run());
});

test("the shell setup entry point uses the requested home and accepts dry-run", t => {
  const f = fixture(t);
  const preview = spawnSync("bash", [path.join(repo, "setup.sh"), "codex", "--azure-base-url", baseUrl, "--dry-run"], { env: f.env, encoding: "utf8" });
  success(preview);
  assert.equal(fs.existsSync(f.azure), false);
  const result = spawnSync("bash", [path.join(repo, "setup.sh"), "codex", "--azure-base-url", baseUrl], { env: f.env, encoding: "utf8" });
  success(result);
  assert.equal(f.config().model_provider, "azure");
});

test("first generation requires a URL even when shared config still defines Azure", t => {
  const f = fixture(t);
  f.updateSource(value => {
    value.model_providers = { azure: { base_url: baseUrl, env_key: "AZURE_OPENAI_API_KEY", wire_api: "responses" } };
  });
  const result = f.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /requires --azure-base-url/);
  assert.equal(fs.existsSync(f.azure), false);

  const selectedUrl = "https://selected.example/openai/v1";
  success(f.run(["--azure-base-url", selectedUrl]));
  assert.equal(f.config().model_providers.azure.base_url, selectedUrl);
  assert.equal(f.config().model_providers.azure.query_params, undefined);
});

test("saved URL and API version survive a new process and shared settings updates", t => {
  const f = fixture(t);
  success(f.initialize());
  const markerFile = path.join(f.azure, ".dotfiles-azure.json");
  const metadata = JSON.parse(fs.readFileSync(markerFile, "utf8"));
  assert.equal(metadata.version, 2);
  assert.equal(metadata.azureProvider.base_url, baseUrl);
  assert.equal(metadata.azureProvider.query_params["api-version"], apiVersion);
  assert.equal(metadata.azureProvider.env_key, "AZURE_OPENAI_API_KEY");
  f.updateSource(value => { value.sandbox_mode = "read-only"; });
  success(f.run());
  assert.equal(f.config().model_providers.azure.base_url, baseUrl);
  assert.equal(f.config().model_providers.azure.query_params["api-version"], apiVersion);
  assert.equal(f.config().sandbox_mode, "read-only");
});

test("URL and API version updates reach every profile and persist without flags", t => {
  const f = fixture(t);
  success(f.initialize());
  const newUrl = "https://replacement.example/openai";
  const newVersion = "2025-03-01-preview";
  success(f.run(["--azure-base-url", newUrl, "--azure-api-version", newVersion]));
  success(f.run());
  const files = Object.keys(JSON.parse(fs.readFileSync(path.join(f.azure, ".dotfiles-azure.json"), "utf8")).files);
  for (const name of files.filter(name => name.endsWith(".toml"))) {
    const provider = f.config(name).model_providers.azure;
    assert.equal(provider.base_url, newUrl);
    assert.equal(provider.query_params["api-version"], newVersion);
  }
  success(f.run(["--azure-api-version", "none"]));
  success(f.run());
  assert.equal(f.config().model_providers.azure.query_params, undefined);
  assert.equal(f.config().model_providers.azure.base_url, newUrl);
});

test("version 1 metadata migrates its provider while retaining local runtime state", t => {
  const f = fixture(t);
  success(f.initialize());
  const markerFile = path.join(f.azure, ".dotfiles-azure.json");
  const metadata = JSON.parse(fs.readFileSync(markerFile, "utf8"));
  // Simulate the old format, including an additional provider setting.
  metadata.version = 1;
  delete metadata.azureProvider;
  for (const name of Object.keys(metadata.files).filter(name => name.endsWith(".toml"))) {
    const value = f.config(name);
    value.model_providers.azure.request_max_retries = 4;
    const text = stringify(value);
    metadata.files[name] = text;
    fs.writeFileSync(path.join(f.azure, name), text);
  }
  fs.writeFileSync(markerFile, JSON.stringify(metadata, null, 2) + "\n");
  const local = f.config();
  local.projects = { "/azure-only": { trust_level: "trusted" } };
  fs.writeFileSync(path.join(f.azure, "config.toml"), "# Local comment\n" + stringify(local));
  const before = managedSnapshot(f.azure);
  const preview = f.run(["--dry-run"]);
  success(preview);
  assert.deepEqual(managedSnapshot(f.azure), before);
  success(f.run());
  const migrated = JSON.parse(fs.readFileSync(markerFile, "utf8"));
  assert.equal(migrated.version, 2);
  assert.equal(migrated.azureProvider.base_url, baseUrl);
  assert.equal(migrated.azureProvider.query_params["api-version"], apiVersion);
  assert.equal(migrated.azureProvider.request_max_retries, 4);
  assert.equal(f.config().projects["/azure-only"].trust_level, "trusted");
  for (const [name, contents] of Object.entries(before)) {
    if (name !== ".dotfiles-azure.json") assert.equal(fs.readFileSync(path.join(f.azure, name), "utf8"), contents);
  }
  success(f.run());
});

test("a conflicting local endpoint stops before overwriting the saved connection or profiles", t => {
  const f = fixture(t);
  success(f.initialize());
  const local = f.config();
  local.model_providers.azure.base_url = "https://local-edit.example/openai";
  fs.writeFileSync(path.join(f.azure, "config.toml"), stringify(local));
  const before = managedSnapshot(f.azure);
  const result = f.run(["--azure-base-url", "https://another.example/openai"]);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Conflicting local and dotfiles changes: .*model_providers.azure.base_url/);
  assert.deepEqual(managedSnapshot(f.azure), before);
});

test("invalid URL and incomplete connection arguments fail without echoing values or writing", t => {
  const f = fixture(t);
  for (const value of ["not-a-url", "ftp://example.invalid/openai", "https://user:do-not-echo@example.invalid/openai", "https://example.invalid/openai?key=do-not-echo", "https://example.invalid/openai#fragment"]) {
    const result = f.run(["--azure-base-url", value]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Azure base URL/);
    assert.doesNotMatch(result.stderr, /do-not-echo/);
    assert.equal(fs.existsSync(f.azure), false);
  }
  for (const option of ["--azure-base-url", "--azure-api-version"]) {
    const result = f.run([option]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /requires a value/);
    assert.equal(fs.existsSync(f.azure), false);
  }
});

test("connection changes in dry-run keep the saved and generated provider untouched", t => {
  const f = fixture(t);
  success(f.initialize());
  const before = managedSnapshot(f.azure);
  success(f.run(["--azure-base-url", "https://preview.example/openai", "--azure-api-version", "none", "--dry-run"]));
  assert.deepEqual(managedSnapshot(f.azure), before);
  success(f.run());
  assert.equal(f.config().model_providers.azure.base_url, baseUrl);
  assert.equal(f.config().model_providers.azure.query_params["api-version"], apiVersion);
});
