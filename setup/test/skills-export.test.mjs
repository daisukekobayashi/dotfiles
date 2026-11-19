import assert from "node:assert/strict";
import { chmod, cp, lstat, mkdir, readdir, readFile, rm, stat, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { createRequire } from "node:module";
import { repoRoot, skillsRuntime, createFixture } from "./skills-helpers.mjs";

const require = createRequire(import.meta.url);

// Export fixtures never read the real identity or marker file: git sees only a
// fixture global config (no system config, no repository above the fixture),
// and HOME and XDG_CONFIG_HOME point into the fixture.
async function createExportFixture() {
  const fixture = await createFixture();
  const dotfiles = fixture.dotfiles;
  const gitConfig = path.join(fixture.root, "gitconfig");
  const xdgConfig = path.join(fixture.root, "xdg-config");
  await writeFile(gitConfig, "");
  await mkdir(xdgConfig, { recursive: true });
  const env = {
    ...fixture.env,
    GIT_CONFIG_GLOBAL: gitConfig,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CEILING_DIRECTORIES: fixture.root,
    XDG_CONFIG_HOME: xdgConfig,
  };
  delete env.SETUP_EXPORT_PERSONAL_MARKERS_FILE;
  delete env.SETUP_DRY_RUN;
  delete env.GIT_DIR;

  await rm(path.join(dotfiles, "skills"), { recursive: true, force: true });
  await writeSkill(dotfiles, "alpha", "Read `../beta/references/guide.md` before acting.\n");
  await writeSkill(dotfiles, "beta", "Run `node ../gamma/scripts/check.mjs`.\n");
  await mkdir(path.join(dotfiles, "skills", "local", "beta", "references"), { recursive: true });
  await writeFile(path.join(dotfiles, "skills", "local", "beta", "references", "guide.md"), "Guide.\n");
  await writeSkill(dotfiles, "gamma", "Leaf skill.\n");
  await mkdir(path.join(dotfiles, "skills", "local", "gamma", "scripts"), { recursive: true });
  await writeFile(path.join(dotfiles, "skills", "local", "gamma", "scripts", "check.mjs"), "#!/usr/bin/env node\n", { mode: 0o755 });
  await chmod(path.join(dotfiles, "skills", "local", "gamma", "scripts", "check.mjs"), 0o755);
  await writeSkill(dotfiles, "delta", "Hand off to `epsilon` when asked.\n");
  await mkdir(path.join(dotfiles, "skills", "local", "delta", "evals", "files"), { recursive: true });
  await writeFile(path.join(dotfiles, "skills", "local", "delta", "evals", "files", "fixture.md"), "See ../zeta/SKILL.md.\n");
  await writeSkill(dotfiles, "epsilon", "Named only.\n");
  await writeSkill(dotfiles, "zeta", "Only an eval fixture links here.\n");

  await writeProfile(dotfiles, "base", {
    description: "Base",
    external: [
      { source: "owner/one", skills: ["ext-a", "ext-b"] },
      { source: "owner/two", skills: ["ext-c"] },
    ],
    local: ["delta"],
  });
  await writeProfile(dotfiles, "work", { description: "Work", includes: ["base"], external: [], local: ["alpha"] });

  await mkdir(path.join(dotfiles, "ai-rules", "base"), { recursive: true });
  await mkdir(path.join(dotfiles, "ai-rules", "agents"), { recursive: true });
  await writeFile(path.join(dotfiles, "ai-rules", "base", "global.md"), "# Global\n\nShared rule.\n");
  await writeFile(path.join(dotfiles, "ai-rules", "agents", "codex.md"), "\n");
  await writeFile(path.join(dotfiles, "ai-rules", "agents", "claude.md"), "Claude rule.\n");

  // Personal configuration that must never reach a bundle.
  for (const [relative, content] of [
    ["claude/settings.json", "{}\n"],
    ["codex/config.toml", "model = 'x'\n"],
    ["codex/profiles/work.toml", "x = 1\n"],
    ["claude/mcp/base.json", "{}\n"],
  ]) {
    await mkdir(path.dirname(path.join(dotfiles, relative)), { recursive: true });
    await writeFile(path.join(dotfiles, relative), content);
  }

  const outParent = path.join(fixture.root, "exports");
  await mkdir(outParent, { recursive: true });
  return { ...fixture, env, gitConfig, xdgConfig, outParent, out: path.join(outParent, "bundle") };
}

async function writeSkill(dotfiles, name, body) {
  const dir = path.join(dotfiles, "skills", "local", name);
  await mkdir(dir, { recursive: true });
  await writeFile(path.join(dir, "SKILL.md"), `---\nname: ${name}\ndescription: Test skill ${name}\n---\n\n${body}`);
}

async function writeProfile(dotfiles, name, profile) {
  await mkdir(path.join(dotfiles, "skills", "profiles"), { recursive: true });
  await writeFile(path.join(dotfiles, "skills", "profiles", `${name}.json`), `${JSON.stringify(profile, null, 2)}\n`);
}

function runExport(args, fixture, env = {}) {
  return spawnSync(process.execPath, [skillsRuntime, "export", ...args], {
    cwd: fixture.root,
    env: { ...fixture.env, ...env },
    encoding: "utf8",
  });
}

async function listTree(root) {
  const entries = [];
  async function walk(relative) {
    for (const entry of await readdir(path.join(root, relative), { withFileTypes: true })) {
      const child = path.posix.join(relative, entry.name);
      entries.push({ path: child, entry });
      if (entry.isDirectory()) {
        await walk(child);
      }
    }
  }
  await walk("");
  return entries;
}

async function readManifest(out) {
  return JSON.parse(await readFile(path.join(out, "skills-bundle.json"), "utf8"));
}

async function withFixture(body) {
  const fixture = await createExportFixture();
  try {
    await body(fixture);
  } finally {
    await fixture.cleanup();
  }
}

function assertOk(result) {
  assert.equal(result.status, 0, result.stderr || result.stdout);
}

test("export resolves profiles and writes skills, rules, README, and manifest", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
    assertOk(result);

    const manifest = await readManifest(fixture.out);
    assert.equal(manifest.schemaVersion, 1);
    assert.equal(manifest.generatedBy, "dotfiles setup skills export");
    assert.deepEqual(manifest.requestedProfiles, ["work"]);
    assert.deepEqual(manifest.expandedProfiles, ["base", "work"]);
    assert.deepEqual(manifest.agents, ["codex", "claude-code"]);
    assert.deepEqual(manifest.external, [
      { source: "owner/one", skills: ["ext-a", "ext-b"] },
      { source: "owner/two", skills: ["ext-c"] },
    ]);
    assert.deepEqual(manifest.rules, ["AGENTS.md", "CLAUDE.md"]);

    const tree = await listTree(fixture.out);
    const files = tree.filter((item) => item.entry.isFile()).map((item) => item.path).sort();
    assert.deepEqual(manifest.files, files);
    assert.deepEqual(
      tree.filter((item) => item.entry.isSymbolicLink()).map((item) => item.path),
      [],
      "bundle must not contain symbolic links",
    );

    const readme = await readFile(path.join(fixture.out, "README.md"), "utf8");
    assert.match(readme, /npx skills add owner\/one --skill ext-a --skill ext-b --agent codex --agent claude-code/);
    assert.match(readme, /npx skills add owner\/two --skill ext-c/);
    assert.match(readme, /~\/\.claude\/skills\//);
    assert.match(readme, /~\/\.agents\/skills\//);
    assert.match(readme, /AGENTS\.md/);
    assert.match(readme, /CLAUDE\.md/);
    assert.match(readme, /Node\.js/);

    assert.equal(await readFile(path.join(fixture.out, "AGENTS.md"), "utf8"), "# Global\n\nShared rule.\n\n");
    assert.equal(await readFile(path.join(fixture.out, "CLAUDE.md"), "utf8"), "# Global\n\nShared rule.\n\n---\n\nClaude rule.\n\n");
  }));

test("export writes only the selected agent's rules", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "base", "--agent", "codex", "--out", fixture.out], fixture));
    assert.ok(existsSync(path.join(fixture.out, "AGENTS.md")));
    assert.ok(!existsSync(path.join(fixture.out, "CLAUDE.md")));
    const readme = await readFile(path.join(fixture.out, "README.md"), "utf8");
    assert.doesNotMatch(readme, /claude-code/);
  }));

test("export never includes personal configuration", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    const files = (await listTree(fixture.out)).filter((item) => item.entry.isFile()).map((item) => item.path);
    for (const file of files) {
      assert.ok(
        ["README.md", "skills-bundle.json", "AGENTS.md", "CLAUDE.md"].includes(file) || file.startsWith("skills/"),
        `unexpected bundle file ${file}`,
      );
      assert.doesNotMatch(file, /settings\.json|config\.toml|profiles\/|mcp/);
    }
  }));

test("export adds linked local skills transitively and reports them", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
    assertOk(result);
    assert.match(result.stdout, /Added as a dependency: beta \(required by alpha\)/);
    assert.match(result.stdout, /Added as a dependency: gamma \(required by beta\)/);

    const manifest = await readManifest(fixture.out);
    assert.deepEqual(manifest.local, [
      { name: "alpha", origin: "profile" },
      { name: "beta", origin: "dependency", requiredBy: ["alpha"] },
      { name: "delta", origin: "profile" },
      { name: "gamma", origin: "dependency", requiredBy: ["beta"] },
    ]);
    // A bare name is not a dependency, and evals/ is neither copied nor scanned.
    assert.ok(!existsSync(path.join(fixture.out, "skills", "epsilon")));
    assert.ok(!existsSync(path.join(fixture.out, "skills", "zeta")));
    assert.ok(!existsSync(path.join(fixture.out, "skills", "delta", "evals")));
  }));

test("export copies whole skill directories and keeps executable bits", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    assert.ok(existsSync(path.join(fixture.out, "skills", "beta", "references", "guide.md")));
    const script = path.join(fixture.out, "skills", "gamma", "scripts", "check.mjs");
    if (process.platform !== "win32") {
      assert.equal((await stat(script)).mode & 0o777, 0o755);
      assert.equal((await stat(path.join(fixture.out, "skills", "gamma", "SKILL.md"))).mode & 0o111, 0);
    }
  }));

test("export fails on a symbolic link inside a selected skill", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    await symlink("SKILL.md", path.join(fixture.dotfiles, "skills", "local", "delta", "alias.md"));
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /local skill delta contains a symbolic link or special file: alias\.md/);
    assert.ok(!existsSync(fixture.out));
  }));

test("export --exclude drops local and external skills", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "work", "--exclude", "delta,ext-c", "--exclude", "ext-a", "--out", fixture.out], fixture);
    assertOk(result);
    const manifest = await readManifest(fixture.out);
    assert.deepEqual(manifest.local.map((skill) => skill.name), ["alpha", "beta", "gamma"]);
    assert.deepEqual(manifest.excluded, ["delta", "ext-a", "ext-c"]);
    assert.deepEqual(manifest.external, [{ source: "owner/one", skills: ["ext-b"] }]);
    const readme = await readFile(path.join(fixture.out, "README.md"), "utf8");
    assert.doesNotMatch(readme, /owner\/two|ext-a/);
  }));

test("export --exclude of a dependency fails naming both skills", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "work", "--exclude", "gamma", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /gamma is required by beta/);
    assert.ok(!existsSync(fixture.out));

    const direct = runExport(["--profile", "work", "--exclude", "beta", "--out", fixture.out], fixture);
    assert.notEqual(direct.status, 0);
    assert.match(direct.stderr, /beta is required by alpha/);
  }));

test("export --exclude rejects names the profiles do not select", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "base", "--exclude", "epsilon", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /do not include: epsilon/);
  }));

async function assertPersonalFailure(fixture, env, pattern) {
  const result = runExport(["--profile", "work", "--out", fixture.out], fixture, env);
  assert.notEqual(result.status, 0, "personal data check must fail the export");
  assert.match(result.stderr, pattern);
  assert.ok(!existsSync(fixture.out), "a failed check must not create the output directory");
  assert.deepEqual(await readdir(fixture.outParent), [], "a failed check must remove its staging directory");
  return result;
}

test("personal data check rejects the home path", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "notes.md"), `Path ${fixture.home}/work\n`);
    const result = await assertPersonalFailure(fixture, {}, /skills\/gamma\/notes\.md: home path/);
    assert.ok(!result.stderr.includes(fixture.home), "the check must not print the home path");
  }));

test("personal data check rejects git user.name and user.email case-insensitively", () =>
  withFixture(async (fixture) => {
    await writeFile(fixture.gitConfig, "[user]\n\tname = Fixture Person\n\temail = fixture.person@example.test\n");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "alpha", "credit.md"), "By fixture person.\n");
    const nameResult = await assertPersonalFailure(fixture, {}, /skills\/alpha\/credit\.md: git user\.name/);
    assert.doesNotMatch(nameResult.stderr, /Fixture Person/i);

    await writeFile(path.join(fixture.dotfiles, "skills", "local", "alpha", "credit.md"), "Mail FIXTURE.PERSON@example.test.\n");
    await assertPersonalFailure(fixture, {}, /skills\/alpha\/credit\.md: git user\.email/);
  }));

test("personal data check reads the marker file under XDG_CONFIG_HOME without printing markers", () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.xdgConfig, "dotfiles"), { recursive: true });
    await writeFile(path.join(fixture.xdgConfig, "dotfiles", "export-personal-markers"), "# comment\n\nsecret-handle\n");
    await writeFile(path.join(fixture.dotfiles, "ai-rules", "base", "global.md"), "Ask Secret-Handle.\n");
    const result = await assertPersonalFailure(fixture, {}, /AGENTS\.md: personal marker on line 3 of the marker file/);
    assert.doesNotMatch(result.stderr, /secret-handle/i);
  }));

test("personal marker file defaults to HOME/.config without XDG_CONFIG_HOME", () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.home, ".config", "dotfiles"), { recursive: true });
    await writeFile(path.join(fixture.home, ".config", "dotfiles", "export-personal-markers"), "leaf skill\n");
    const env = { ...fixture.env };
    delete env.XDG_CONFIG_HOME;
    const result = spawnSync(process.execPath, [skillsRuntime, "export", "--profile", "work", "--out", fixture.out], {
      cwd: fixture.root,
      env,
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/gamma\/SKILL\.md: personal marker on line 1/);
  }));

test("SETUP_EXPORT_PERSONAL_MARKERS_FILE overrides the marker file and must exist", () =>
  withFixture(async (fixture) => {
    const markers = path.join(fixture.root, "markers.txt");
    await writeFile(markers, "leaf skill\n");
    await assertPersonalFailure(fixture, { SETUP_EXPORT_PERSONAL_MARKERS_FILE: markers }, /skills\/gamma\/SKILL\.md: personal marker on line 1/);

    const missing = runExport(["--profile", "work", "--out", fixture.out], fixture, {
      SETUP_EXPORT_PERSONAL_MARKERS_FILE: path.join(fixture.root, "missing.txt"),
    });
    assert.notEqual(missing.status, 0);
    assert.match(missing.stderr, /SETUP_EXPORT_PERSONAL_MARKERS_FILE names a missing file/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("export refuses a non-empty output directory without --force", () =>
  withFixture(async (fixture) => {
    await mkdir(fixture.out);
    await writeFile(path.join(fixture.out, "notes.txt"), "mine\n");
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /output directory is not empty/);

    const forced = runExport(["--profile", "base", "--out", fixture.out, "--force"], fixture);
    assert.notEqual(forced.status, 0);
    assert.match(forced.stderr, /no valid skills-bundle\.json/);
    assert.deepEqual(await readdir(fixture.out), ["notes.txt"]);
  }));

test("export writes into an existing empty directory", () =>
  withFixture(async (fixture) => {
    await mkdir(fixture.out);
    assertOk(runExport(["--profile", "base", "--out", fixture.out], fixture));
    assert.ok(existsSync(path.join(fixture.out, "skills-bundle.json")));
  }));

test("export --force replaces a previous bundle and drops stale skills", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    assert.ok(existsSync(path.join(fixture.out, "skills", "alpha")));
    assertOk(runExport(["--profile", "base", "--out", fixture.out, "--force"], fixture));
    assert.ok(!existsSync(path.join(fixture.out, "skills", "alpha")));
    assert.deepEqual((await readManifest(fixture.out)).requestedProfiles, ["base"]);
    assert.deepEqual((await readdir(fixture.outParent)).sort(), ["bundle"]);
  }));

test("export --force refuses a previous bundle with entries it did not write", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    await writeFile(path.join(fixture.out, "skills", "alpha", "my-notes.md"), "mine\n");
    await mkdir(path.join(fixture.out, ".git"));
    const result = runExport(["--profile", "base", "--out", fixture.out, "--force"], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /entries not written by skills export: \.git\/, skills\/alpha\/my-notes\.md/);
    assert.ok(existsSync(path.join(fixture.out, "skills", "alpha", "my-notes.md")));
    assert.deepEqual((await readManifest(fixture.out)).requestedProfiles, ["work"]);
  }));

test("a failed export leaves a previous bundle unchanged", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    const before = await readFile(path.join(fixture.out, "skills-bundle.json"), "utf8");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "notes.md"), `Path ${fixture.home}\n`);
    const result = runExport(["--profile", "work", "--out", fixture.out, "--force"], fixture);
    assert.notEqual(result.status, 0);
    assert.equal(await readFile(path.join(fixture.out, "skills-bundle.json"), "utf8"), before);
    assert.ok(!existsSync(path.join(fixture.out, "skills", "gamma", "notes.md")));
    assert.deepEqual(await readdir(fixture.outParent), ["bundle"]);
  }));

test("export dry run writes nothing", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "work", "--out", fixture.out], fixture, { SETUP_DRY_RUN: "1" });
    assertOk(result);
    assert.match(result.stdout, /DRY-RUN write skills bundle/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("export refuses an output directory inside the dotfiles repository", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "base", "--out", path.join(fixture.dotfiles, "bundle")], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /must be outside the dotfiles repository/);
  }));

test("export validates its arguments", () =>
  withFixture(async (fixture) => {
    assert.match(runExport(["--out", fixture.out], fixture).stderr, /--profile is required/);
    assert.match(runExport(["--profile", "base"], fixture).stderr, /--out is required/);
    assert.match(runExport(["--profile", "base", "--out", fixture.out, "--agent", "claude"], fixture).stderr, /unsupported skills agent: claude/);
    assert.match(runExport(["--profile", "base", "--out", fixture.out, "--copy"], fixture).stderr, /Unknown skills export argument: --copy/);
    assert.match(runExport(["--profile", "nope", "--out", fixture.out], fixture).stderr, /unknown profile nope/);
  }));

// Real profiles: copy this repository's skills and rules into the fixture so
// the export reads them without touching the real identity.
async function useRepositorySources(fixture) {
  for (const relative of ["skills", "ai-rules"]) {
    await rm(path.join(fixture.dotfiles, relative), { recursive: true, force: true });
    await cp(path.join(repoRoot, relative), path.join(fixture.dotfiles, relative), { recursive: true });
  }
}

test("repository bundles resolve every ../ link inside the bundle", () =>
  withFixture(async (fixture) => {
    await useRepositorySources(fixture);
    for (const profiles of ["base,github", "github", "azure-devops", "base,beads", "pstack"]) {
      const out = path.join(fixture.outParent, profiles.replace(/,/g, "-"));
      const result = runExport(["--profile", profiles, "--out", out], fixture);
      assertOk(result);
      const tree = await listTree(out);
      assert.deepEqual(tree.filter((item) => item.entry.isSymbolicLink()).map((item) => item.path), []);
      const skills = new Set((await readdir(path.join(out, "skills"))));
      const missing = [];
      for (const item of tree.filter((entry) => entry.entry.isFile() && entry.path.startsWith("skills/"))) {
        const text = await readFile(path.join(out, item.path), "utf8");
        for (const match of text.matchAll(/\.\.\/([A-Za-z0-9_][A-Za-z0-9._-]*)\/([A-Za-z0-9._/-]*)/g)) {
          const [, skill, rest] = match;
          if (!existsSync(path.join(repoRoot, "skills", "local", skill))) {
            continue;
          }
          const target = rest.replace(/[./]+$/, "");
          if (!skills.has(skill) || (target && !existsSync(path.join(out, "skills", skill, target)))) {
            missing.push(`${profiles}: ${item.path} -> ../${skill}/${target}`);
          }
        }
      }
      assert.deepEqual(missing, []);
    }
  }));

test("repository github bundle adds delivery-common and worktree-runtime-cleanup", () =>
  withFixture(async (fixture) => {
    await useRepositorySources(fixture);
    const result = runExport(["--profile", "github", "--out", fixture.out], fixture);
    assertOk(result);
    assert.match(result.stdout, /Added as a dependency: delivery-common \(required by .*github-issue-delivery/);
    assert.match(result.stdout, /Added as a dependency: worktree-runtime-cleanup \(required by .*github-worktree-cleanup/);
    const manifest = await readManifest(fixture.out);
    assert.deepEqual(
      manifest.local.filter((skill) => skill.origin === "dependency").map((skill) => skill.name),
      ["delivery-common", "worktree-runtime-cleanup"],
    );
    const mode = (await stat(path.join(fixture.out, "skills", "worktree-runtime-cleanup", "scripts"))).isDirectory();
    assert.ok(mode);
  }));

test("export rules match compose-rules.sh", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    await useRepositorySources(fixture);
    assertOk(runExport(["--profile", "base", "--out", fixture.out], fixture));
    for (const [agent, file] of [
      ["codex", "AGENTS.md"],
      ["claude", "CLAUDE.md"],
    ]) {
      const expected = path.join(fixture.root, `expected-${file}`);
      const composed = spawnSync("bash", [path.join(repoRoot, "ai-rules", "scripts", "compose-rules.sh"), agent, expected], {
        encoding: "utf8",
      });
      assert.equal(composed.status, 0, composed.stderr);
      assert.equal(await readFile(path.join(fixture.out, file), "utf8"), await readFile(expected, "utf8"), file);
    }
  }));

test("repository bundle README lists the optional Codex plugin for change reviews", () =>
  withFixture(async (fixture) => {
    await useRepositorySources(fixture);
    assertOk(runExport(["--profile", "base", "--out", fixture.out], fixture));
    const readme = await readFile(path.join(fixture.out, "README.md"), "utf8");
    assert.match(readme, /Optional: the Codex plugin for Claude Code/);
    assert.match(readme, /By default, .* run in a fresh\n  subagent of the current agent/);
    assert.match(readme, /explicitly names Codex/);
    assert.match(readme, /codex-companion\.mjs`; if the plugin is missing, that review reports the failure and stops/);
    const script = path.join(fixture.out, "skills", "worktree-runtime-cleanup", "scripts");
    if (process.platform !== "win32" && existsSync(script)) {
      for (const name of await readdir(script)) {
        const source = await lstat(path.join(repoRoot, "skills", "local", "worktree-runtime-cleanup", "scripts", name));
        assert.equal((await stat(path.join(script, name))).mode & 0o777, source.mode & 0o777, name);
      }
    }
  }));

// Runs the export with fs patched by `patch`, a function body that receives
// fs, path, and the resolved --out path, to inject failures at boundaries.
function runExportPatched(args, fixture, patch, env = {}) {
  const launcher = `
const fs = require("node:fs");
const path = require("node:path");
const runtime = process.argv[1];
const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
const out = path.resolve(args[outIndex + 1]);
(function (fs, path, out) { ${patch} })(fs, path, out);
process.argv = [process.execPath, runtime, ...args];
require(runtime);
`;
  return spawnSync(process.execPath, ["-e", launcher, skillsRuntime, "export", ...args], {
    cwd: fixture.root,
    env: { ...fixture.env, ...env },
    encoding: "utf8",
  });
}

// D1: the documented PowerShell entry point.
const pwsh = spawnSync(process.platform === "win32" ? "where" : "which", ["pwsh"], { encoding: "utf8" }).stdout?.trim().split(/\r?\n/)[0];

test("setup.ps1 skills export passes --out and other flags through to Node", { skip: !pwsh && "pwsh is not installed" }, () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.dotfiles, "setup"), { recursive: true });
    for (const name of await readdir(path.join(repoRoot, "setup"))) {
      if (name.endsWith(".js")) {
        await cp(path.join(repoRoot, "setup", name), path.join(fixture.dotfiles, "setup", name));
      }
    }
    const quote = (value) => `'${value.replace(/'/g, "''")}'`;
    const command = `& ${quote(path.join(repoRoot, "setup.ps1"))} skills export --profile 'work' --agent codex --exclude ext-a --out ${quote(fixture.out)}`;
    const result = spawnSync(pwsh, ["-NoProfile", "-NonInteractive", "-Command", command], {
      cwd: fixture.root,
      env: { ...fixture.env, CUSTOM_HOME: fixture.home, SETUP_DOTFILES_ROOT: fixture.dotfiles },
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const manifest = await readManifest(fixture.out);
    assert.deepEqual(manifest.agents, ["codex"]);
    assert.deepEqual(manifest.excluded, ["ext-a"]);
    assert.deepEqual(manifest.rules, ["AGENTS.md"]);

    const copy = spawnSync(pwsh, ["-NoProfile", "-NonInteractive", "-Command", `${command} -Copy`], {
      cwd: fixture.root,
      env: { ...fixture.env, CUSTOM_HOME: fixture.home, SETUP_DOTFILES_ROOT: fixture.dotfiles },
      encoding: "utf8",
    });
    assert.notEqual(copy.status, 0);
    assert.match(copy.stderr + copy.stdout, /-Copy is not supported for skills export/);
  }));

// D2: path confinement.
test("export rejects profile and skill names that are not one path component", () =>
  withFixture(async (fixture) => {
    await writeProfile(fixture.dotfiles, "escape", { description: "Escape", local: ["../../claude"] });
    let result = runExport(["--profile", "escape", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Invalid or reserved skill name: \.\.\/\.\.\/claude/);

    await writeProfile(fixture.dotfiles, "includer", { description: "Includer", includes: ["../profiles/base"], local: [] });
    result = runExport(["--profile", "includer", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Invalid profile name: \.\.\/profiles\/base/);

    result = runExport(["--profile", "../profiles/base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Invalid profile name/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("export rejects a selected skill root that is a symbolic link", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    const outside = path.join(fixture.root, "outside-skill");
    await mkdir(outside);
    await writeFile(path.join(outside, "SKILL.md"), "---\nname: linked\n---\n");
    await symlink(outside, path.join(fixture.dotfiles, "skills", "local", "linked"));
    await writeProfile(fixture.dotfiles, "linked", { description: "Linked", local: ["linked"] });
    const result = runExport(["--profile", "linked", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/local\/linked is a symbolic link/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("export rejects profile and rule files that resolve outside their roots", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    const outsideProfile = path.join(fixture.root, "outside.json");
    await writeFile(outsideProfile, JSON.stringify({ description: "Outside", local: ["gamma"] }));
    await symlink(outsideProfile, path.join(fixture.dotfiles, "skills", "profiles", "outside.json"));
    let result = runExport(["--profile", "outside", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/profiles\/outside\.json is a symbolic link/);

    const outsideRule = path.join(fixture.root, "claude-rule.md");
    await writeFile(outsideRule, "Outside rule.\n");
    await rm(path.join(fixture.dotfiles, "ai-rules", "agents", "claude.md"));
    await symlink(outsideRule, path.join(fixture.dotfiles, "ai-rules", "agents", "claude.md"));
    result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /ai-rules\/agents\/claude\.md is a symbolic link/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("export refuses an output directory that resolves inside the dotfiles repository", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    const alias = path.join(fixture.root, "alias");
    await symlink(fixture.dotfiles, alias);
    const result = runExport(["--profile", "base", "--out", path.join(alias, "bundle")], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /must be outside the dotfiles repository/);
  }));

// D3: manifest validation and recheck before deletion.
test("export --force refuses manifests that are not a complete version 1 manifest", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "base", "--out", fixture.out], fixture));
    const original = await readManifest(fixture.out);
    const cases = [
      { ...original, schemaVersion: undefined },
      { ...original, schemaVersion: 2 },
      { generatedBy: original.generatedBy, files: original.files },
      { ...original, files: [...original.files, "../escape.txt"] },
      { ...original, files: [...original.files, "/tmp/abs.txt"] },
      { ...original, files: [...original.files, "notes.txt"] },
    ];
    for (const manifest of cases) {
      await writeFile(path.join(fixture.out, "skills-bundle.json"), JSON.stringify(manifest));
      const result = runExport(["--profile", "base", "--out", fixture.out, "--force"], fixture);
      assert.notEqual(result.status, 0, JSON.stringify(manifest).slice(0, 80));
      assert.match(result.stderr, /no valid skills-bundle\.json/);
      assert.ok(existsSync(path.join(fixture.out, "AGENTS.md")));
    }
  }));

test("export --force rechecks the moved directory and restores it when entries appeared", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    const result = runExportPatched(["--profile", "base", "--out", fixture.out, "--force"], fixture, `
      const rename = fs.renameSync;
      let done = false;
      fs.renameSync = (from, to) => {
        if (!done && path.resolve(from) === out) {
          done = true;
          fs.writeFileSync(path.join(from, "late-note.txt"), "mine\\n");
        }
        return rename(from, to);
      };
    `);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /entries not written by skills export: late-note\.txt/);
    assert.equal(await readFile(path.join(fixture.out, "late-note.txt"), "utf8"), "mine\n");
    assert.deepEqual((await readManifest(fixture.out)).requestedProfiles, ["work"]);
    assert.deepEqual(await readdir(fixture.outParent), ["bundle"]);
  }));

// D4: rollback.
test("a failed promotion keeps an existing empty output directory", () =>
  withFixture(async (fixture) => {
    await mkdir(fixture.out);
    const result = runExportPatched(["--profile", "base", "--out", fixture.out], fixture, `
      const rename = fs.renameSync;
      fs.renameSync = (from, to) => {
        if (path.basename(from).startsWith(".skx-s")) {
          throw new Error("injected promotion failure");
        }
        return rename(from, to);
      };
    `);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /injected promotion failure/);
    assert.ok((await stat(fixture.out)).isDirectory());
    assert.deepEqual(await readdir(fixture.out), []);
    assert.deepEqual(await readdir(fixture.outParent), ["bundle"]);
  }));

test("a failed promotion keeps a previous bundle", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    const before = await readFile(path.join(fixture.out, "skills-bundle.json"), "utf8");
    const result = runExportPatched(["--profile", "base", "--out", fixture.out, "--force"], fixture, `
      const rename = fs.renameSync;
      fs.renameSync = (from, to) => {
        if (path.basename(from).startsWith(".skx-s")) {
          throw new Error("injected promotion failure");
        }
        return rename(from, to);
      };
    `);
    assert.notEqual(result.status, 0);
    assert.equal(await readFile(path.join(fixture.out, "skills-bundle.json"), "utf8"), before);
    assert.deepEqual(await readdir(fixture.outParent), ["bundle"]);
  }));

test("a failed backup removal reports the installed bundle and where the backup remains", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    const result = runExportPatched(["--profile", "base", "--out", fixture.out, "--force"], fixture, `
      const rmdir = fs.rmdirSync;
      fs.rmdirSync = (target, options) => {
        if (path.basename(target).startsWith(".skx-b")) {
          throw new Error("injected cleanup failure");
        }
        return rmdir(target, options);
      };
    `);
    assertOk(result);
    assert.match(result.stderr, /the new bundle is installed at .*bundle, but the previous one was not fully removed and remains at .*\.skx-b/);
    assert.match(result.stdout, /Skills bundle written/);
    assert.deepEqual((await readManifest(fixture.out)).requestedProfiles, ["base"]);
    const left = (await readdir(fixture.outParent)).filter((name) => name.startsWith(".skx-b"));
    assert.equal(left.length, 1);
  }));

// D5: no marker value is printed.
test("markers in file names, skill names, and paths are redacted from all output", () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.xdgConfig, "dotfiles"), { recursive: true });
    await writeFile(path.join(fixture.xdgConfig, "dotfiles", "export-personal-markers"), "hush-word\n");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "hush-word.md"), "Plain.\n");
    await writeSkill(fixture.dotfiles, "hush-word-skill", "Plain.\n");
    await writeProfile(fixture.dotfiles, "hush", { description: "Hush", local: ["gamma", "hush-word-skill"] });
    const result = runExport(["--profile", "hush", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/gamma\/<redacted>\.md: personal marker on line 1/);
    assert.match(result.stdout, /<redacted>-skill/);
    assert.doesNotMatch(result.stdout + result.stderr, /hush-word/i);
  }));

test("the home path is redacted from progress output", () =>
  withFixture(async (fixture) => {
    const out = path.join(fixture.home, "share", "bundle");
    const result = runExport(["--profile", "base", "--out", out], fixture);
    assertOk(result);
    assert.match(result.stdout, /Skills bundle written: <home>\/share\/bundle/);
    assert.ok(!result.stdout.includes(fixture.home));
  }));

// D6: fail closed on unreadable identity and undecodable text.
test("a git config read error fails the export", () =>
  withFixture(async (fixture) => {
    await writeFile(fixture.gitConfig, "[user\n\tname = broken\n");
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cannot read git config user\.name: git exited with status 128/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("a missing git fails the export", () =>
  withFixture(async (fixture) => {
    const empty = path.join(fixture.root, "empty-bin");
    await mkdir(empty);
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture, { PATH: empty });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cannot read git config user\.name/);
  }));

test("skill files that are not strict UTF-8 without NUL fail the export", () =>
  withFixture(async (fixture) => {
    const file = path.join(fixture.dotfiles, "skills", "local", "gamma", "credit.md");
    for (const bytes of [
      Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from("By someone\n", "utf16le")]),
      Buffer.from("By someone\n", "utf16le"),
      Buffer.from([0x41, 0xc3, 0x28, 0x0a]),
      Buffer.from([0x41, 0x00, 0x42, 0x0a]),
    ]) {
      await writeFile(file, bytes);
      await assertPersonalFailure(fixture, {}, /cannot read skills\/gamma\/credit\.md: it (is not UTF-8 text|contains NUL characters)/);
    }
  }));

test("the default marker file is read from both SETUP_HOME and the OS home", () =>
  withFixture(async (fixture) => {
    const setupHome = path.join(fixture.root, "setup-home");
    await mkdir(setupHome);
    await mkdir(path.join(fixture.home, ".config", "dotfiles"), { recursive: true });
    await writeFile(path.join(fixture.home, ".config", "dotfiles", "export-personal-markers"), "leaf skill\n");
    const env = { ...fixture.env, SETUP_HOME: setupHome };
    delete env.XDG_CONFIG_HOME;
    const result = spawnSync(process.execPath, [skillsRuntime, "export", "--profile", "work", "--out", fixture.out], { cwd: fixture.root, env, encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/gamma\/SKILL\.md: personal marker on line 1/);
  }));

test("an empty SETUP_EXPORT_PERSONAL_MARKERS_FILE fails the export", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture, { SETUP_EXPORT_PERSONAL_MARKERS_FILE: "" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /SETUP_EXPORT_PERSONAL_MARKERS_FILE is set but empty/);
  }));

// D7: links and name ownership after closure.
test("export fails when a relative link does not resolve inside the bundle", () =>
  withFixture(async (fixture) => {
    for (const [body, pattern] of [
      ["See ../beta/references/missing.md.\n", /skills\/alpha\/SKILL\.md -> \.\.\/beta\/references\/missing\.md/],
      ["See ../nowhere/SKILL.md.\n", /skills\/alpha\/SKILL\.md -> \.\.\/nowhere\/SKILL\.md/],
      ["See ../delta/evals/files/fixture.md.\n", /skills\/alpha\/SKILL\.md -> \.\.\/delta\/evals\/files\/fixture\.md/],
    ]) {
      await writeSkill(fixture.dotfiles, "alpha", `Read \`../beta/references/guide.md\`. ${body}`);
      await writeProfile(fixture.dotfiles, "work", { description: "Work", includes: ["base"], external: [], local: ["alpha"] });
      const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /relative links in the bundle do not resolve inside it/);
      assert.match(result.stderr, pattern);
      assert.deepEqual(await readdir(fixture.outParent), []);
    }
  }));

test("export accepts links relative to the referring file", () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.dotfiles, "skills", "local", "beta", "references", "deep"), { recursive: true });
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "beta", "references", "deep", "note.md"), "See [guide](../guide.md) and [gamma](../../../gamma/SKILL.md).\n");
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
  }));

test("export fails when a dependency collides with an external skill name", () =>
  withFixture(async (fixture) => {
    await writeProfile(fixture.dotfiles, "clash", {
      description: "Clash",
      external: [{ source: "owner/three", skills: ["gamma"] }],
      local: ["beta"],
    });
    const result = runExport(["--profile", "clash", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skill name collision between a local dependency and an external skill: gamma/);
  }));

// D8: external values reach shell commands.
test("export rejects hostile external sources and names", () =>
  withFixture(async (fixture) => {
    for (const external of [
      [{ source: "owner/repo; touch /tmp/pwned", skills: ["ok"] }],
      [{ source: "owner/repo", skills: ["$(touch /tmp/pwned)"] }],
      [{ source: "--global", skills: ["ok"] }],
    ]) {
      await writeProfile(fixture.dotfiles, "hostile", { description: "Hostile", external, local: [] });
      const result = runExport(["--profile", "hostile", "--out", fixture.out], fixture);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /unsupported external skill (source|name) for export/);
    }
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("README shell arguments are quoted", () => {
  const { shellArg } = require("../skills-export.js");
  assert.equal(shellArg("owner/repo"), "owner/repo");
  assert.equal(shellArg("a b"), "'a b'");
  assert.equal(shellArg("x; rm -rf ~"), "'x; rm -rf ~'");
  assert.equal(shellArg("it's"), "'it'\\''s'");
  const parsed = spawnSync("sh", ["-c", `printf '%s\\n' ${shellArg("x; $(id) 'q'")}`], { encoding: "utf8" });
  assert.equal(parsed.stdout, "x; $(id) 'q'\n");
});

// D10: Windows resolves git to an absolute path.
test("export resolves git through the Windows command search", () => {
  const source = require("node:fs").readFileSync(path.join(repoRoot, "setup", "src", "skills.ts"), "utf8");
  assert.match(source, /gitCommand: \(\) => \(process\.platform === "win32" \? resolveWindowsCommand\("git"\) : "git"\)/);
});

// Round 2.
// D11: source roots and containment.
test("export refuses source roots that are symbolic links", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    for (const relative of ["ai-rules", "skills/local", "skills/profiles"]) {
      const real = path.join(fixture.dotfiles, relative);
      const moved = path.join(fixture.root, `moved-${relative.replace("/", "-")}`);
      await cp(real, moved, { recursive: true });
      await rm(real, { recursive: true });
      await symlink(moved, real);
      const result = runExport(["--profile", "base", "--out", fixture.out], fixture);
      assert.notEqual(result.status, 0, relative);
      assert.match(result.stderr, new RegExp(`${relative.replace("/", "\\/")} is a symbolic link`));
      await rm(real);
      await cp(moved, real, { recursive: true });
    }
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("export refuses an included profile that is a symbolic link before reading it", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    const outside = path.join(fixture.root, "outside.json");
    await writeFile(outside, "{ not json: outside-fragment }");
    await symlink(outside, path.join(fixture.dotfiles, "skills", "profiles", "linked.json"));
    await writeProfile(fixture.dotfiles, "includer", { description: "Includer", includes: ["linked"], local: [] });
    const result = runExport(["--profile", "includer", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/profiles\/linked\.json is a symbolic link/);
    assert.doesNotMatch(result.stderr, /outside-fragment/);
  }));

test("profile parse errors do not echo the profile contents", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "skills", "profiles", "broken.json"), "{ \"local\": [secret-fragment] }");
    const result = runExport(["--profile", "broken", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /broken\.json: invalid JSON/);
    assert.doesNotMatch(result.stderr, /secret-fragment/);
  }));

test("a child directory named ..share counts as inside the dotfiles repository", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "base", "--out", path.join(fixture.dotfiles, "..share", "bundle")], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /must be outside the dotfiles repository/);
  }));

// D12: the backup keeps entries added after the recheck.
test("entries added to the backup after the recheck are kept, with a warning", () =>
  withFixture(async (fixture) => {
    for (const setup of ["bundle", "empty"]) {
      await rm(fixture.out, { recursive: true, force: true });
      for (const name of await readdir(fixture.outParent)) {
        await rm(path.join(fixture.outParent, name), { recursive: true, force: true });
      }
      if (setup === "bundle") {
        assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
      } else {
        await mkdir(fixture.out);
      }
      const result = runExportPatched(["--profile", "base", "--out", fixture.out, ...(setup === "bundle" ? ["--force"] : [])], fixture, `
        const rename = fs.renameSync;
        fs.renameSync = (from, to) => {
          if (path.basename(from).startsWith(".skx-s")) {
            const previous = fs.readdirSync(path.dirname(out)).find((name) => name.startsWith(".skx-b"));
            fs.writeFileSync(path.join(path.dirname(out), previous, "late-note.txt"), "mine\\n");
          }
          return rename(from, to);
        };
      `);
      assertOk(result);
      assert.match(result.stderr, /the previous one was not fully removed and remains at .*\.skx-b/, setup);
      const previous = (await readdir(fixture.outParent)).find((name) => name.startsWith(".skx-b"));
      assert.ok(previous, setup);
      assert.deepEqual(await readdir(path.join(fixture.outParent, previous)), ["late-note.txt"], setup);
      assert.deepEqual((await readManifest(fixture.out)).requestedProfiles, ["base"]);
    }
  }));

// D13: unsafe parents.
test("export refuses an output parent that others can write without the sticky bit", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    const shared = path.join(fixture.root, "shared");
    await mkdir(shared);
    await chmod(shared, 0o777);
    let result = runExport(["--profile", "base", "--out", path.join(shared, "bundle")], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /other users can write to it and it has no sticky bit/);
    assert.deepEqual(await readdir(shared), []);


    await chmod(shared, 0o1777);
    result = runExport(["--profile", "base", "--out", path.join(shared, "bundle")], fixture);
    assertOk(result);
  }));

// D14: strict manifests.
test("export --force refuses manifests whose fields disagree or list files export would not write", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    const original = await readManifest(fixture.out);
    const dependency = original.local.find((skill) => skill.origin === "dependency");
    const cases = {
      "missing README": { ...original, files: original.files.filter((file) => file !== "README.md") },
      "dependency without requiredBy": { ...original, local: original.local.map((skill) => (skill === dependency ? { name: skill.name, origin: "dependency" } : skill)) },
      "dependency without name": { ...original, local: original.local.map((skill) => (skill === dependency ? { origin: "dependency", requiredBy: ["alpha"] } : skill)) },
      "unselected skill files": { ...original, files: [...original.files, "skills/bogus/evals/unrelated.txt"].sort() },
      "evals files": { ...original, files: [...original.files, "skills/alpha/evals/unrelated.txt"].sort() },
      "rules without agent": { ...original, agents: ["codex"] },
      "extra key": { ...original, note: "x" },
      "requiredBy unknown": { ...original, local: original.local.map((skill) => (skill === dependency ? { ...skill, requiredBy: ["ghost"] } : skill)) },
      "requested profile not expanded": { ...original, requestedProfiles: ["base", "other"] },
      "joined rules": { ...original, rules: [original.rules.join("\n")] },
      "excluded selected skill": { ...original, excluded: ["alpha"] },
      "unsafe source": { ...original, external: [{ source: "a b/c", skills: ["x"] }] },
    };
    for (const [label, manifest] of Object.entries(cases)) {
      await writeFile(path.join(fixture.out, "skills-bundle.json"), JSON.stringify(manifest));
      const result = runExport(["--profile", "base", "--out", fixture.out, "--force"], fixture);
      assert.notEqual(result.status, 0, label);
      assert.match(result.stderr, /no valid skills-bundle\.json/, label);
    }
    await writeFile(path.join(fixture.out, "skills-bundle.json"), `${JSON.stringify(original, null, 2)}\n`);
    assertOk(runExport(["--profile", "base", "--out", fixture.out, "--force"], fixture));
  }));

// D15: redaction everywhere.
test("argument errors and Unicode paths never print a marker", () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.xdgConfig, "dotfiles"), { recursive: true });
    await writeFile(path.join(fixture.xdgConfig, "dotfiles", "export-personal-markers"), "hush-word\n");
    let result = runExport(["--profile", "base", "--agent", "hush-word", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /unsupported skills agent: <redacted>/);
    assert.doesNotMatch(result.stderr, /hush-word/i);

    result = runExport(["--profile", "base", "--out", fixture.out, "--bogus-hush-word"], fixture);
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stderr, /hush-word/i);

    const out = path.join(fixture.outParent, "İİİİ-hush-word", "bundle");
    result = runExport(["--profile", "base", "--out", out], fixture);
    assertOk(result);
    assert.match(result.stdout, /İİİİ-<redacted>/);
    assert.doesNotMatch(result.stdout + result.stderr, /hush-word|ush-word|sh-word/i);
  }));

// D16: strict decoding of inputs.
test("a marker file that is not strict UTF-8 without NUL fails the export", () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.xdgConfig, "dotfiles"), { recursive: true });
    const markerFile = path.join(fixture.xdgConfig, "dotfiles", "export-personal-markers");
    for (const bytes of [Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from("leaf skill\n", "utf16le")]), Buffer.from([0x41, 0xc3, 0x28, 0x0a])]) {
      await writeFile(markerFile, bytes);
      const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /cannot read the default personal marker file: it (is not UTF-8 text|contains NUL characters)/);
    }
  }));

test("a default marker path that cannot be read fails the export", () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.xdgConfig, "dotfiles", "export-personal-markers"), { recursive: true });
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /the default personal marker file is not a regular file/);
  }));

test("rule files that are not strict UTF-8 fail the export", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "ai-rules", "base", "global.md"), Buffer.from([0x41, 0xc3, 0x28, 0x0a]));
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cannot read ai-rules\/base\/global\.md: it is not UTF-8 text/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

// D17: references resolve exactly from their file.
test("a reference that climbs out of skills/ fails even when a same-named skill exists", () =>
  withFixture(async (fixture) => {
    await writeSkill(fixture.dotfiles, "alpha", "Read `../beta/references/guide.md` and ../../beta/SKILL.md.\n");
    const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/alpha\/SKILL\.md -> \.\.\/\.\.\/beta\/SKILL\.md/);
  }));

// Round 3.
// D18a: every bundle export writes can be replaced by the next --force.
test("export bundles round-trip through --force", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "beta", "references", "note:v2 \\ draft.md"), "Note.\n");
    await mkdir(path.join(fixture.dotfiles, "skills", "local", "empty", "evals"), { recursive: true });
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "empty", "SKILL.md"), "---\nname: empty\n---\n");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "empty", "evals", "only.md"), "Fixture.\n");
    await writeProfile(fixture.dotfiles, "hollow", { description: "Hollow", local: ["empty"] });
    for (const args of [
      ["--profile", "work,work"],
      ["--profile", "work", "--exclude", "delta,ext-a"],
      ["--profile", "base", "--agent", "codex"],
      ["--profile", "hollow,work", "--agent", "claude-code"],
    ]) {
      await rm(fixture.out, { recursive: true, force: true });
      assertOk(runExport([...args, "--out", fixture.out], fixture));
      const result = runExport([...args, "--out", fixture.out, "--force"], fixture);
      assertOk(result);
    }
    assert.deepEqual((await readManifest(fixture.out)).local.find((skill) => skill.name === "empty"), { name: "empty", origin: "profile" });
    assertOk(runExport(["--profile", "work,work", "--out", fixture.out, "--force"], fixture));
    assert.deepEqual((await readManifest(fixture.out)).requestedProfiles, ["work"]);
  }));

// D18b: values are registered before later steps can print them.
test("a marker file path error does not print the git identity", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    await writeFile(fixture.gitConfig, "[user]\n\tname = Fixture Person\n");
    const blocker = path.join(fixture.root, "Fixture Person");
    await writeFile(blocker, "a file, not a directory\n");
    const result = runExport(["--profile", "base", "--out", fixture.out], fixture, { XDG_CONFIG_HOME: path.join(blocker, "config") });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /ENOTDIR/);
    assert.match(result.stderr, /<redacted>/);
    assert.doesNotMatch(result.stderr, /Fixture Person/i);
  }));

test("anything the personal data check finds is redacted in its report", () =>
  withFixture(async (fixture) => {
    await writeFile(fixture.gitConfig, "[user]\n\tname = Fixture Person\n");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "FIXTURE PERSON notes.md"), "Plain.\n");
    const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skills\/gamma\/<redacted> notes\.md: git user\.name/);
    assert.doesNotMatch(result.stderr, /fixture person/i);
  }));

// D18c: reference parsing.
test("references with %-encoding, non-ASCII names, and .. resolve as written", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "beta", "references", "guide one.md"), "One.\n");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "beta", "日本語.md"), "Nihongo.\n");
    const { parseReferences } = require("../skills-export.js");
    assert.deepEqual(parseReferences("See [g](../beta/references/guide%20one.md#top), `../beta/日本語.md`, and ../beta/references/.."), [
      "../beta/references/guide%20one.md",
      "../beta/日本語.md",
      "../beta/references/..",
    ]);
    assert.deepEqual(parseReferences("Ignore ../../.agents/skills and x/../y."), []);

    await writeSkill(fixture.dotfiles, "alpha", "Read `../beta/references/guide.md`, [g](../beta/references/guide%20one.md), `../beta/日本語.md`, and ../beta/references/...\n");
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));

    for (const [body, written] of [
      ["See ../beta/missing/../SKILL.md now.\n", "../beta/missing/../SKILL.md"],
      ["See `../beta/存在しない.md`.\n", "../beta/存在しない.md"],
      ["See [g](../beta/references/guide%20two.md).\n", "../beta/references/guide%20two.md"],
    ]) {
      await rm(fixture.out, { recursive: true, force: true });
      await writeSkill(fixture.dotfiles, "alpha", `Read \`../beta/references/guide.md\`. ${body}`);
      const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
      assert.notEqual(result.status, 0, written);
      assert.ok(result.stderr.includes(`skills/alpha/SKILL.md -> ${written}`), result.stderr);
    }
  }));

// D18d: README isolates npx from projects.
test("README runs npx skills add from a new empty directory outside any project", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "base", "--out", fixture.out], fixture));
    const readme = await readFile(path.join(fixture.out, "README.md"), "utf8");
    assert.match(readme, /from a new, empty directory outside any\nproject/);
    assert.match(readme, /```sh\ncd "\$\(mktemp -d\)"\nnpx skills add owner\/one/);
  }));

// D18e: cleanup removes only files seen at the recheck.
test("a listed file that was missing at the recheck is kept when it appears later", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "work", "--out", fixture.out], fixture));
    await rm(path.join(fixture.out, "README.md"));
    const result = runExportPatched(["--profile", "base", "--out", fixture.out, "--force"], fixture, `
      const rename = fs.renameSync;
      fs.renameSync = (from, to) => {
        if (path.basename(from).startsWith(".skx-s")) {
          const previous = fs.readdirSync(path.dirname(out)).find((name) => name.startsWith(".skx-b"));
          fs.writeFileSync(path.join(path.dirname(out), previous, "README.md"), "late\\n");
        }
        return rename(from, to);
      };
    `);
    assertOk(result);
    assert.match(result.stderr, /not fully removed and remains at/);
    const previous = (await readdir(fixture.outParent)).find((name) => name.startsWith(".skx-b"));
    assert.deepEqual(await readdir(path.join(fixture.outParent, previous)), ["README.md"]);
    assert.equal(await readFile(path.join(fixture.outParent, previous, "README.md"), "utf8"), "late\n");
  }));

// D18f: the manifest is checked to be a regular file before it is read.
test("a manifest that is a FIFO is refused without blocking", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "base", "--out", fixture.out], fixture));
    await rm(path.join(fixture.out, "skills-bundle.json"));
    assert.equal(spawnSync("mkfifo", [path.join(fixture.out, "skills-bundle.json")]).status, 0);
    const result = spawnSync(process.execPath, [skillsRuntime, "export", "--profile", "base", "--out", fixture.out, "--force"], {
      cwd: fixture.root,
      env: fixture.env,
      encoding: "utf8",
      timeout: 20000,
    });
    assert.notEqual(result.status, 0);
    assert.equal(result.signal, null, "export must not block on the FIFO");
    assert.match(result.stderr, /no valid skills-bundle\.json \(it has no regular manifest file\)/);
  }));

// Round 4.
// D19: an option never takes another option as its value.
test("a value option followed by another option fails as missing its value", () =>
  withFixture(async (fixture) => {
    for (const args of [
      ["--profile", "base", "--out", "--force"],
      ["--profile", "--out", fixture.out],
      ["--profile", "base", "--agent", "--force", "--out", fixture.out],
      ["--profile", "base", "--exclude", "--out", fixture.out],
    ]) {
      const result = runExport(args, fixture);
      assert.notEqual(result.status, 0, args.join(" "));
      assert.match(result.stderr, /--(out|profile|agent|exclude) requires a value/);
    }
    assert.deepEqual(await readdir(fixture.root).then((names) => names.filter((name) => name.startsWith("--"))), []);
    assertOk(runExport(["--profile", "base", "--out", "./--force"], fixture));
    assert.ok(existsSync(path.join(fixture.root, "--force", "skills-bundle.json")));
  }));

// D20: every exported skill has a regular SKILL.md.
test("selected and dependency skills without a SKILL.md file fail the export", () =>
  withFixture(async (fixture) => {
    await rm(path.join(fixture.dotfiles, "skills", "local", "gamma", "SKILL.md"));
    let result = runExport(["--profile", "work", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /local skill gamma has no SKILL\.md file/);

    await mkdir(path.join(fixture.dotfiles, "skills", "local", "gamma", "SKILL.md"));
    result = runExport(["--profile", "work", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /local skill gamma has no SKILL\.md file/);

    await rm(path.join(fixture.dotfiles, "skills", "local", "delta", "SKILL.md"));
    result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /local skill delta has no SKILL\.md file/);
  }));

// D21: only directories may be followed by more components.
test("references through a file or with a trailing slash on a file fail", () =>
  withFixture(async (fixture) => {
    const { resolveReference } = require("../skills-export.js");
    const from = path.join(fixture.dotfiles, "skills", "local", "alpha");
    assert.equal(resolveReference(from, "../beta/SKILL.md/../SKILL.md"), undefined);
    assert.equal(resolveReference(from, "../beta/SKILL.md/"), undefined);
    assert.ok(resolveReference(from, "../beta/references/"));
    assert.ok(resolveReference(from, "../beta/references/../SKILL.md"));
    for (const written of ["../beta/SKILL.md/../SKILL.md", "../beta/SKILL.md/"]) {
      await writeSkill(fixture.dotfiles, "alpha", `Read \`../beta/references/guide.md\` and \`${written}\`.\n`);
      const result = runExport(["--profile", "work", "--out", fixture.out], fixture);
      assert.notEqual(result.status, 0, written);
      assert.ok(result.stderr.includes(`skills/alpha/SKILL.md -> ${written}`), result.stderr);
    }
  }));

// D22: the destination is resolved physically and compared by identity.
test("links are resolved before .. in --out, and the resolved path is used", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    const inside = path.join(fixture.root, "inside-link");
    await symlink(path.join(fixture.dotfiles, "skills"), inside);
    let result = runExport(["--profile", "base", "--out", `${inside}/../bundle`], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /must be outside the dotfiles repository/);
    assert.ok(!existsSync(path.join(fixture.dotfiles, "bundle")));

    const elsewhere = path.join(fixture.root, "elsewhere", "deep");
    await mkdir(elsewhere, { recursive: true });
    const outside = path.join(fixture.root, "outside-link");
    await symlink(elsewhere, outside);
    result = runExport(["--profile", "base", "--out", `${outside}/../bundle`], fixture);
    assertOk(result);
    assert.ok(existsSync(path.join(fixture.root, "elsewhere", "bundle", "skills-bundle.json")));
    assert.ok(!existsSync(path.join(fixture.root, "bundle")));

    result = runExport(["--profile", "base", "--out", `${fixture.root}/missing/../bundle`], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /has "\.\." after a directory that does not exist/);
  }));

test("an --out that is an ancestor of the checkout is refused", () =>
  withFixture(async (fixture) => {
    const result = runExport(["--profile", "base", "--out", fixture.root, "--force"], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /must be outside the dotfiles repository/);
  }));

// D23: case-insensitive collisions and the staged tree.
test("bundle paths that differ only in letter case fail the export", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "Notes.md"), "One.\n");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "notes.md"), "Two.\n");
    let result = runExport(["--profile", "work", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /differ only in letter case: skills\/gamma\/Notes\.md and skills\/gamma\/notes\.md/);
    await rm(path.join(fixture.dotfiles, "skills", "local", "gamma", "Notes.md"));

    await writeSkill(fixture.dotfiles, "Gamma", "Upper.\n");
    await writeProfile(fixture.dotfiles, "cased", { description: "Cased", local: ["gamma", "Gamma"] });
    result = runExport(["--profile", "cased", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /differ only in letter case: skills\/Gamma and skills\/gamma/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

test("a staged tree that differs from the manifest is not promoted", () =>
  withFixture(async (fixture) => {
    const result = runExportPatched(["--profile", "base", "--out", fixture.out], fixture, `
      const write = fs.writeFileSync;
      fs.writeFileSync = (file, ...rest) => {
        write(file, ...rest);
        if (String(file).endsWith("README.md") && path.basename(path.dirname(String(file))).startsWith(".skx-s")) {
          write(path.join(path.dirname(String(file)), "stray.txt"), "x");
        }
      };
    `);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /the staged bundle does not match its manifest/);
    assert.deepEqual(await readdir(fixture.outParent), []);
  }));

// D24: personal check inputs.
test("setup.ps1 keeps an explicit SETUP_HOME and still checks the PowerShell home", { skip: !pwsh && "pwsh is not installed" }, () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.dotfiles, "setup"), { recursive: true });
    for (const name of await readdir(path.join(repoRoot, "setup"))) {
      if (name.endsWith(".js")) {
        await cp(path.join(repoRoot, "setup", name), path.join(fixture.dotfiles, "setup", name));
      }
    }
    const explicit = path.join(fixture.root, "explicit-home");
    const psHome = path.join(fixture.root, "ps-home");
    await mkdir(explicit);
    await mkdir(psHome);
    const quote = (value) => `'${value.replace(/'/g, "''")}'`;
    const command = `& ${quote(path.join(repoRoot, "setup.ps1"))} skills export --profile 'work' --out ${quote(fixture.out)}`;
    for (const home of [explicit, psHome]) {
      await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "notes.md"), `See ${home}/x\n`);
      const result = spawnSync(pwsh, ["-NoProfile", "-NonInteractive", "-Command", command], {
        cwd: fixture.root,
        env: { ...fixture.env, SETUP_HOME: explicit, CUSTOM_HOME: psHome, SETUP_DOTFILES_ROOT: fixture.dotfiles },
        encoding: "utf8",
      });
      assert.notEqual(result.status, 0, home);
      assert.match(result.stderr + result.stdout, /skills\/gamma\/notes\.md: home path/);
    }
  }));

test("escaped forms of the home path are detected and redacted", () =>
  withFixture(async (fixture) => {
    const backslashed = fixture.home.split("/").join("\\");
    for (const written of [fixture.home.split("/").join("\\/"), backslashed.split("\\").join("\\\\")]) {
      await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "notes.md"), `{"path": "${written}"}\n`);
      await assertPersonalFailure(fixture, {}, /skills\/gamma\/notes\.md: home path/);
    }
    const out = path.join(fixture.outParent, "x");
    const result = runExport(["--profile", "base", "--out", out, "--agent", fixture.home.split("/").join("\\\\")], fixture);
    assert.notEqual(result.status, 0);
    assert.ok(!result.stderr.includes(fixture.home.split("/").join("\\\\")));
  }));

test("a default marker path that is a broken link fails, and errors never print marker paths", { skip: process.platform === "win32" }, () =>
  withFixture(async (fixture) => {
    await mkdir(path.join(fixture.xdgConfig, "dotfiles"), { recursive: true });
    await symlink(path.join(fixture.root, "secret-missing-target"), path.join(fixture.xdgConfig, "dotfiles", "export-personal-markers"));
    let result = runExport(["--profile", "base", "--out", fixture.out], fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cannot read the default personal marker file: ENOENT/);
    assert.doesNotMatch(result.stderr, /secret-missing-target|xdg-config/);

    const overrideDir = path.join(fixture.root, "secret-override-dir");
    await mkdir(overrideDir);
    result = runExport(["--profile", "base", "--out", fixture.out], fixture, { SETUP_EXPORT_PERSONAL_MARKERS_FILE: overrideDir });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /the override personal marker file is not a regular file/);
    assert.doesNotMatch(result.stderr, /secret-override-dir/);
  }));

test("the git identity lookup ignores repository and config overrides in the environment", () =>
  withFixture(async (fixture) => {
    await writeFile(fixture.gitConfig, "[user]\n\tname = Fixture Person\n");
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "credit.md"), "By Fixture Person.\n");
    for (const env of [
      { GIT_CONFIG_PARAMETERS: "'user.name'='Someone Else'" },
      { GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "user.name", GIT_CONFIG_VALUE_0: "Someone Else" },
      { GIT_DIR: path.join(fixture.root, "not-a-repo"), GIT_WORK_TREE: fixture.root },
    ]) {
      await assertPersonalFailure(fixture, env, /skills\/gamma\/credit\.md: git user\.name/);
    }
  }));

// D26: short work names.
test("a long --out name still works with --force", () =>
  withFixture(async (fixture) => {
    const out = path.join(fixture.outParent, "b".repeat(240));
    assertOk(runExport(["--profile", "base", "--out", out], fixture));
    assertOk(runExport(["--profile", "work", "--out", out, "--force"], fixture));
    assert.deepEqual(await readdir(fixture.outParent), ["b".repeat(240)]);
  }));

// D27: README installs copies.
test("README install commands pass --copy", () =>
  withFixture(async (fixture) => {
    assertOk(runExport(["--profile", "base", "--out", fixture.out], fixture));
    const readme = await readFile(path.join(fixture.out, "README.md"), "utf8");
    assert.match(readme, /npx skills add owner\/one --skill ext-a --skill ext-b --agent codex --agent claude-code --copy\n/);
  }));

// D28: scanning happens before staging, and files are written from buffers.
test("the personal data check runs before any staging directory is created", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "skills", "local", "gamma", "notes.md"), `Path ${fixture.home}\n`);
    const patch = `
      const mkdtemp = fs.mkdtempSync;
      fs.mkdtempSync = (...args) => { process.stderr.write("STAGING-CREATED\\n"); return mkdtemp(...args); };
      fs.copyFileSync = () => { throw new Error("copyFileSync must not be used"); };
    `;
    let result = runExportPatched(["--profile", "work", "--out", fixture.out], fixture, patch);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /personal data check failed/);
    assert.doesNotMatch(result.stderr, /STAGING-CREATED/);
    await rm(path.join(fixture.dotfiles, "skills", "local", "gamma", "notes.md"));
    result = runExportPatched(["--profile", "work", "--out", fixture.out], fixture, patch);
    assertOk(result);
    if (process.platform !== "win32") {
      assert.equal((await stat(path.join(fixture.out, "skills", "gamma", "scripts", "check.mjs"))).mode & 0o777, 0o755);
    }
  }));

// D29: a byte order mark in rules is kept, like compose-rules.sh.
test("rules keep a UTF-8 byte order mark", () =>
  withFixture(async (fixture) => {
    await writeFile(path.join(fixture.dotfiles, "ai-rules", "base", "global.md"), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("# Global\n")]));
    assertOk(runExport(["--profile", "base", "--agent", "codex", "--out", fixture.out], fixture));
    const bytes = await readFile(path.join(fixture.out, "AGENTS.md"));
    assert.deepEqual([...bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
  }));
