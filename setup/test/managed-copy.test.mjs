import assert from "node:assert/strict";
import * as fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { parse } from "smol-toml";

const repo = path.resolve(import.meta.dirname, "../..");
const runtime = path.join(repo, "setup/managed-copy.js");

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "managed-copy-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const dotfiles = path.join(root, "dot files");
  const home = path.join(root, "user home");
  const write = (file, text) => {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  };
  const f = {
    dotfiles,
    home,
    write,
    codexSource: path.join(dotfiles, "codex/config.toml"),
    claudeSource: path.join(dotfiles, "claude/settings.json"),
    codex: path.join(home, ".codex/config.toml"),
    claude: path.join(home, ".claude/settings.json"),
    codexBaseline: path.join(home, ".codex/.dotfiles-managed/config.toml"),
    claudeBaseline: path.join(home, ".claude/.dotfiles-managed/settings.json"),
    run: (...args) => spawnSync(process.execPath, [runtime, ...args], {
      encoding: "utf8",
      env: { ...process.env, SETUP_HOME: home, SETUP_DOTFILES_ROOT: dotfiles, SETUP_DRY_RUN: "0" },
    }),
  };
  write(f.codexSource, 'model = "gpt-6"\napproval_policy = "on-request"\n\n[features]\nhooks = true\n');
  write(f.claudeSource, JSON.stringify({ model: "opus", env: { MCP_TIMEOUT: "30000" }, enabledPlugins: { a: true } }, null, 2) + "\n");
  return f;
}

const read = file => fs.readFileSync(file, "utf8");

test("apply installs copies and records the applied dotfiles version", t => {
  const f = fixture(t);
  const result = f.run("apply");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(read(f.codex), read(f.codexSource));
  assert.equal(read(f.claude), read(f.claudeSource));
  assert.equal(read(f.codexBaseline), read(f.codexSource));
  assert.equal(read(f.claudeBaseline), read(f.claudeSource));
  assert.equal(fs.lstatSync(f.codex).isSymbolicLink(), false);
  assert.equal(f.run("apply").stdout, "");
});

test("apply replaces links with copies without changing the dotfiles files", t => {
  const f = fixture(t);
  const linked = read(f.codexSource) + '\n[projects."/private/project"]\ntrust_level = "trusted"\n';
  f.write(f.codexSource, linked);
  fs.mkdirSync(path.dirname(f.codex), { recursive: true });
  fs.symlinkSync(f.codexSource, f.codex);
  const result = f.run("apply");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /replacing the link with a copy/);
  assert.equal(fs.lstatSync(f.codex).isSymbolicLink(), false);
  assert.equal(read(f.codex), linked);
  assert.equal(read(f.codexSource), linked);
});

test("apply merges dotfiles changes with local edits and runtime state", t => {
  const f = fixture(t);
  assert.equal(f.run("apply").status, 0);
  f.write(f.codex, `approval_policy = "never"\nmodel = "gpt-6"\n\n[features]\nhooks = true\n\n[projects."/private/project"]\ntrust_level = "trusted"\n\n[tui]\ntheme = "dark"\n\n[tui.model_availability_nux]\ngpt-6 = 1\n`);
  // Stale state in dotfiles must not reach the local copy.
  f.write(f.codexSource, 'model = "gpt-6.1"\napproval_policy = "on-request"\n\n[features]\nhooks = true\n\n[projects."/old"]\ntrust_level = "untrusted"\n');

  const result = f.run("apply");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  const merged = JSON.parse(JSON.stringify(parse(read(f.codex))));
  assert.equal(merged.model, "gpt-6.1");
  assert.equal(merged.approval_policy, "never");
  assert.deepEqual(merged.projects, { "/private/project": { trust_level: "trusted" } });
  assert.deepEqual(merged.tui, { theme: "dark", model_availability_nux: { "gpt-6": 1 } });
  assert.equal(read(f.codexBaseline), read(f.codexSource));
});

test("apply removes settings dropped from dotfiles unless they changed locally", t => {
  const f = fixture(t);
  assert.equal(f.run("apply").status, 0);
  f.write(f.claudeSource, JSON.stringify({ model: "opus", env: { MCP_TIMEOUT: "30000" } }, null, 2) + "\n");
  assert.equal(f.run("apply").status, 0);
  assert.deepEqual(JSON.parse(read(f.claude)), { model: "opus", env: { MCP_TIMEOUT: "30000" } });
});

test("apply keeps a conflicting local value and warns without failing", t => {
  const f = fixture(t);
  assert.equal(f.run("apply").status, 0);
  f.write(f.claude, JSON.stringify({ model: "sonnet", env: { MCP_TIMEOUT: "30000" }, enabledPlugins: { a: true } }, null, 2) + "\n");
  f.write(f.claudeSource, JSON.stringify({ model: "haiku", env: { MCP_TIMEOUT: "60000" }, enabledPlugins: { a: true } }, null, 2) + "\n");
  const result = f.run("apply");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /Kept local values that conflict with dotfiles changes in .*settings\.json: model$/m);
  assert.deepEqual(JSON.parse(read(f.claude)), { model: "sonnet", env: { MCP_TIMEOUT: "60000" }, enabledPlugins: { a: true } });
  assert.equal(read(f.claudeBaseline), read(f.claudeSource));
});

test("apply adopts an existing copy without a recorded baseline", t => {
  const f = fixture(t);
  f.write(f.claude, JSON.stringify({ model: "opus", skipWorkflowUsageWarning: true }, null, 2) + "\n");
  const result = f.run("apply");
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(read(f.claude)), { model: "opus", skipWorkflowUsageWarning: true, env: { MCP_TIMEOUT: "30000" }, enabledPlugins: { a: true } });
});

test("apply --dry-run reports without writing", t => {
  const f = fixture(t);
  const result = f.run("apply", "--dry-run");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Would write .*config\.toml/);
  assert.equal(fs.existsSync(path.join(f.home, ".codex")), false);
});

test("apply reports an invalid local file and still updates the others", t => {
  const f = fixture(t);
  f.write(f.codex, "model = [unterminated\n");
  const result = f.run("apply");
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Invalid TOML: .*config\.toml/);
  assert.doesNotMatch(result.stderr, /unterminated/);
  assert.equal(read(f.claude), read(f.claudeSource));
});

test("diff lists local differences, ignores runtime state and masks secrets", t => {
  const f = fixture(t);
  assert.equal(f.run("apply").status, 0);
  assert.equal(f.run("diff", "--check").status, 0);
  f.write(f.codex, 'model = "gpt-6.1"\n\n[features]\nhooks = true\nweb_search = true\n\n[projects."/private/project"]\ntrust_level = "trusted"\n\n[hooks.state."x"]\ntrusted_hash = "abc"\n');
  f.write(f.claude, JSON.stringify({ model: "opus", env: { MCP_TIMEOUT: "1", ANTHROPIC_AUTH_TOKEN: "s3cr3t" }, enabledPlugins: { a: true }, apiKeyHelper: "print-key" }, null, 2) + "\n");

  const result = f.run("diff");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^codex\/config\.toml <- /m);
  assert.match(result.stdout, /^ {2}~ model: "gpt-6" -> "gpt-6\.1"$/m);
  assert.match(result.stdout, /^ {2}- approval_policy = "on-request"$/m);
  assert.match(result.stdout, /^ {2}\+ features\.web_search = true$/m);
  assert.match(result.stdout, /^ {2}~ env\.MCP_TIMEOUT: \*\*\* -> \*\*\*$/m);
  assert.match(result.stdout, /^ {2}\+ env\.ANTHROPIC_AUTH_TOKEN = \*\*\*$/m);
  assert.match(result.stdout, /^ {2}\+ apiKeyHelper = \*\*\*$/m);
  assert.doesNotMatch(result.stdout, /private|projects|hooks\.state|s3cr3t|print-key|trusted_hash/);

  assert.equal(f.run("diff", "--check").status, 1);
  const summary = f.run("diff", "--summary");
  assert.equal(summary.status, 0);
  assert.match(summary.stdout, /^Local Codex\/Claude settings differ from dotfiles in 6 place\(s\) \(codex\/config\.toml, claude\/settings\.json\); review with /);
  assert.equal(summary.stdout.trim().split("\n").length, 1);
});

test("diff points links and missing copies to setup links", t => {
  const f = fixture(t);
  fs.mkdirSync(path.dirname(f.codex), { recursive: true });
  fs.symlinkSync(f.codexSource, f.codex);
  const result = f.run("diff", "--check");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /codex\/config\.toml: .* is not a managed copy yet; run setup links/);
  assert.equal(f.run("diff", "--summary").stdout, "");
});

test("unknown commands and arguments fail", t => {
  const f = fixture(t);
  assert.equal(f.run().status, 1);
  assert.equal(f.run("diff", "--dry-run").status, 1);
  assert.match(f.run("--help").stdout, /^Usage: managed-copy apply/);
});
