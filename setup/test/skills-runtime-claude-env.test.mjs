import assert from "node:assert/strict";
import { lstat, mkdir, readdir, readlink, rm, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import {
  repoRoot,
  createFixture,
  runSkills,
  readText,
  createClaudeEnvironment,
} from "./skills-helpers.mjs";

test("user install refreshes shared skills in existing Claude environments", async () => {
  const fixture = await createFixture();
  try {
    const environments = await Promise.all(["acme", "second"].map(name => createClaudeEnvironment(fixture, name)));
    const view = path.join(fixture.dotfiles, ".agents", "user", "skills");

    let result = spawnSync(path.join(repoRoot, "setup.sh"), ["skills", "--profile", "base"], {
      cwd: repoRoot, env: fixture.env, encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    for (const environment of environments) {
      const skills = path.join(environment, "skills");
      assert.equal(existsSync(path.join(skills, "local-one", "SKILL.md")), true,
        "setup skills should link installed skills into existing Claude environments");
      assert.equal((await lstat(skills)).isSymbolicLink(), false);
      assert.equal(await readlink(path.join(skills, "find-skills")), path.join(view, "find-skills"));
    }

    await writeFile(path.join(fixture.dotfiles, "skills/local/local-one/SKILL.md"), "updated local definition\n");
    await writeFile(path.join(view, "find-skills/SKILL.md"), "definition before reinstall\n");
    result = runSkills(["--profile", "office"], fixture);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    for (const environment of environments) {
      const skills = path.join(environment, "skills");
      assert.equal(existsSync(path.join(skills, "pdf", "SKILL.md")), true,
        "reinstalling skills should add newly selected skills to existing environments");
      assert.equal(await readlink(path.join(skills, "pdf")), path.join(view, "pdf"));
      assert.equal(await readText(path.join(skills, "find-skills/SKILL.md")), "find-skills\n");
      assert.equal(await readText(path.join(skills, "local-one/SKILL.md")), "updated local definition\n");
      assert.equal(await readText(path.join(environment, "settings.json")), '{"theme":"local"}\n');
    }
    result = runSkills(["--profile", "base"], fixture);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    for (const environment of environments) {
      assert.equal(await readlink(path.join(environment, "skills/pdf")), path.join(view, "pdf"));
    }
  } finally {
    await fixture.cleanup();
  }
});

test("Claude skill refresh preserves local entries, synced data and environment state", async () => {
  const fixture = await createFixture();
  try {
    const environment = await createClaudeEnvironment(fixture);
    const skills = path.join(environment, "skills");
    const synced = path.join(fixture.dotfiles, ".agents/user/skills/synced");
    await mkdir(path.join(skills, "find-skills"));
    await writeFile(path.join(skills, "find-skills/SKILL.md"), "local definition\n");
    await symlink("../missing-local-skill", path.join(skills, "local-one"));
    await mkdir(path.join(skills, "synced/account"), { recursive: true });
    await writeFile(path.join(skills, "synced/account/SKILL.md"), "account definition\n");
    await mkdir(synced, { recursive: true });
    await writeFile(path.join(synced, "SKILL.md"), "default account definition\n");
    for (const file of [".dotfiles-env.json", "history.jsonl", "mcp.json"]) {
      await writeFile(path.join(environment, file), "environment state\n");
    }

    const result = runSkills(["--profile", "office"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stderr, /Preserving existing Claude environment skill/);
    assert.equal(await readText(path.join(skills, "find-skills/SKILL.md")), "local definition\n");
    assert.equal(await readlink(path.join(skills, "local-one")), "../missing-local-skill");
    assert.equal(await readText(path.join(skills, "synced/account/SKILL.md")), "account definition\n");
    assert.equal(existsSync(path.join(skills, "synced/SKILL.md")), false);
    assert.equal(existsSync(path.join(skills, "pdf/SKILL.md")), true);
    assert.equal(await readText(path.join(environment, "settings.json")), '{"theme":"local"}\n');
    for (const file of [".dotfiles-env.json", "history.jsonl", "mcp.json"]) {
      assert.equal(await readText(path.join(environment, file)), "environment state\n");
    }
  } finally {
    await fixture.cleanup();
  }
});

test("Claude skill refresh skips unmanaged, incomplete and symlinked environments", async () => {
  const fixture = await createFixture();
  try {
    const unmanaged = path.join(fixture.home, ".claude-envs", "unmanaged");
    const incomplete = path.join(fixture.home, ".claude-envs", "incomplete");
    await mkdir(unmanaged, { recursive: true });
    await mkdir(incomplete);
    await writeFile(path.join(incomplete, ".claude-pick"), "1\n");
    const linkedSkills = await createClaudeEnvironment(fixture, "linked-skills");
    const outside = path.join(fixture.root, "outside");
    await mkdir(outside);
    await rm(path.join(linkedSkills, "skills"), { recursive: true });
    await symlink(outside, path.join(linkedSkills, "skills"), "dir");
    await symlink(outside, path.join(fixture.home, ".claude-envs", "linked-home"), "dir");

    const result = runSkills(["--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(path.join(unmanaged, "skills")), false);
    assert.equal(existsSync(path.join(incomplete, "skills")), false);
    assert.deepEqual(await readdir(outside), []);
    assert.equal(await readlink(path.join(linkedSkills, "skills")), outside);
    assert.match(result.stderr, /Skipping symlink or unexpected Claude environment skills directory/);
  } finally {
    await fixture.cleanup();
  }
});

test("Claude skill refresh does not follow a symlinked environments root", async () => {
  const fixture = await createFixture();
  try {
    const outside = path.join(fixture.root, "outside");
    const otherHome = path.join(outside, "acme");
    await mkdir(otherHome, { recursive: true });
    await writeFile(path.join(otherHome, ".claude-pick"), "1\n");
    await writeFile(path.join(otherHome, "settings.json"), "{}\n");
    await symlink(outside, path.join(fixture.home, ".claude-envs"), "dir");

    const result = runSkills(["--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(path.join(otherHome, "skills")), false);
    assert.match(result.stderr, /Skipping symlink or unexpected Claude environment directory/);
  } finally {
    await fixture.cleanup();
  }
});

test("Codex-only and project installs do not add skills to Claude environments", async () => {
  const fixture = await createFixture();
  try {
    const environment = await createClaudeEnvironment(fixture);
    for (const args of [
      ["--profile", "base", "--agent", "codex"],
      ["--scope", "project", "--profile", "base", "--agent", "claude-code"],
    ]) {
      const result = runSkills(args, fixture, { cwd: fixture.project });
      assert.equal(result.status, 0, result.stderr || result.stdout);
      assert.deepEqual(await readdir(path.join(environment, "skills")), []);
    }
  } finally {
    await fixture.cleanup();
  }
});
