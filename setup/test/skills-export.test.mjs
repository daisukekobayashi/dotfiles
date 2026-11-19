import assert from "node:assert/strict";
import { chmod, cp, lstat, mkdir, readdir, readFile, rm, stat, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { repoRoot, skillsRuntime, createFixture } from "./skills-helpers.mjs";

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
    assert.match(result.stderr, /local skill delta contains a symbolic link: alias\.md/);
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
    assert.match(forced.stderr, /no readable skills-bundle\.json/);
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
    assert.match(readme, /codex-companion\.mjs/);
    const script = path.join(fixture.out, "skills", "worktree-runtime-cleanup", "scripts");
    if (process.platform !== "win32" && existsSync(script)) {
      for (const name of await readdir(script)) {
        const source = await lstat(path.join(repoRoot, "skills", "local", "worktree-runtime-cleanup", "scripts", name));
        assert.equal((await stat(path.join(script, name))).mode & 0o777, source.mode & 0o777, name);
      }
    }
  }));
