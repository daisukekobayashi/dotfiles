import assert from "node:assert/strict";
import { cp, lstat, mkdir, readdir, readlink, rename, rm, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import {
  repoRoot,
  createFixture,
  runSkills,
  runSkillsWithSymlinkError,
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
      assert.equal(existsSync(path.join(environment, "skills/pdf")), false,
        "deselected skills should not leave links behind in Claude environments");
      assert.ok(result.stdout.includes(`Removed stale skill entry: ${path.join(environment, "skills", "pdf")}`));
      assert.equal(await readlink(path.join(environment, "skills/find-skills")), path.join(view, "find-skills"));
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

async function renameLocalSkill(fixture, from, to) {
  const local = path.join(fixture.dotfiles, "skills", "local");
  await rename(path.join(local, from), path.join(local, to));
  await writeFile(path.join(local, to, "SKILL.md"), `---\nname: ${to}\ndescription: Renamed\n---\n`);
  const profile = path.join(fixture.dotfiles, "skills", "profiles", "base.json");
  const base = JSON.parse(await readText(profile));
  base.local = base.local.map(name => (name === from ? to : name));
  await writeFile(profile, JSON.stringify(base, null, 2) + "\n");
}

test("Claude skill refresh prunes links of a renamed local skill and keeps unmanaged links", async () => {
  const fixture = await createFixture();
  try {
    const environment = await createClaudeEnvironment(fixture);
    const skills = path.join(environment, "skills");
    const view = path.join(fixture.dotfiles, ".agents", "user", "skills");
    const outside = path.join(fixture.root, "outside-skill");
    await mkdir(outside);
    await writeFile(path.join(outside, "SKILL.md"), "outside\n");

    let result = runSkills(["--profile", "base"], fixture);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readlink(path.join(skills, "local-one")), path.join(view, "local-one"));
    await symlink(outside, path.join(skills, "user-link"), "dir");
    await symlink(path.join(fixture.root, "missing"), path.join(skills, "user-dangling"), "dir");
    await symlink(path.join(view, "synced"), path.join(skills, "synced"), "dir");
    await symlink(path.join(view, "synced", "account"), path.join(skills, "account"), "dir");
    await symlink(path.join(view, "find-skills"), path.join(skills, "finder"), "dir");
    await symlink(path.join(view, "pdf"), path.join(skills, "pdf"), "dir");

    await renameLocalSkill(fixture, "local-one", "local-two");
    const dryRun = runSkills(["--profile", "office"], { ...fixture, env: { ...fixture.env, SETUP_DRY_RUN: "1" } });
    assert.equal(dryRun.status, 0, dryRun.stderr || dryRun.stdout);
    assert.ok(dryRun.stdout.includes(`DRY-RUN remove stale skill entry ${path.join(skills, "local-one")}`));
    assert.equal(dryRun.stdout.includes(path.join(skills, "user-link")), false);
    assert.equal(dryRun.stdout.includes(`remove stale skill entry ${path.join(skills, "pdf")}`), false,
      "dry run should not report a link to a skill the planned install provides");
    assert.equal(await readlink(path.join(skills, "local-one")), path.join(view, "local-one"),
      "dry run should not remove stale links");

    result = runSkills(["--profile", "office"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readlink(path.join(skills, "pdf")), path.join(view, "pdf"));
    assert.equal(await lstat(path.join(skills, "local-one")).catch(() => null), null,
      "the renamed skill's dangling link should be pruned");
    assert.equal(await readlink(path.join(skills, "local-two")), path.join(view, "local-two"));
    assert.equal(await readlink(path.join(skills, "user-link")), outside);
    assert.equal(await readlink(path.join(skills, "user-dangling")), path.join(fixture.root, "missing"));
    assert.equal(await readlink(path.join(skills, "synced")), path.join(view, "synced"));
    assert.equal(await readlink(path.join(skills, "account")), path.join(view, "synced", "account"),
      "links that setup does not create are not managed");
    assert.equal(await readlink(path.join(skills, "finder")), path.join(view, "find-skills"));
  } finally {
    await fixture.cleanup();
  }
});

test("Claude skill refresh prunes unchanged copies of a removed skill and keeps edited ones", async () => {
  const fixture = await createFixture();
  try {
    const [clean, edited] = await Promise.all(["clean", "edited"].map(name => createClaudeEnvironment(fixture, name)));
    let result = runSkillsWithSymlinkError(["--scope", "user", "--profile", "base"], fixture);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    for (const environment of [clean, edited]) {
      assert.equal((await lstat(path.join(environment, "skills/local-one"))).isSymbolicLink(), false);
      assert.equal(existsSync(path.join(environment, "skills/.dotfiles-copy-local-one.json")), true);
    }
    await writeFile(path.join(edited, "skills/local-one/SKILL.md"), "local edit\n");
    await mkdir(path.join(clean, "skills/broken"));
    await writeFile(path.join(clean, "skills/.dotfiles-copy-broken.json"), "not json\n");
    await cp(path.join(clean, "skills/local-one"), path.join(clean, "skills/old-version"), { recursive: true });
    const marker = JSON.parse(await readText(path.join(clean, "skills/.dotfiles-copy-local-one.json")));
    await writeFile(path.join(clean, "skills/.dotfiles-copy-old-version.json"),
      JSON.stringify({ ...marker, version: 99, source: marker.source.replace(/local-one$/, "old-version") }));
    await mkdir(path.join(clean, "skills/linked-marker"));
    await symlink(path.join(clean, "skills/.dotfiles-copy-local-one.json"), path.join(clean, "skills/.dotfiles-copy-linked-marker.json"));

    await renameLocalSkill(fixture, "local-one", "local-two");
    result = runSkillsWithSymlinkError(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(path.join(clean, "skills/local-one")), false);
    assert.equal(existsSync(path.join(clean, "skills/.dotfiles-copy-local-one.json")), false);
    assert.equal(existsSync(path.join(clean, "skills/local-two/SKILL.md")), true);
    assert.equal(await readText(path.join(edited, "skills/local-one/SKILL.md")), "local edit\n");
    assert.equal(existsSync(path.join(edited, "skills/.dotfiles-copy-local-one.json")), true);
    assert.match(result.stderr, /Keeping locally edited copy of a removed skill: .*edited.skills.local-one/);
    assert.equal(existsSync(path.join(clean, "skills/broken")), true);
    assert.match(result.stderr, /Keeping skill copy with an invalid copy marker: .*clean.skills.broken/);
    assert.equal(existsSync(path.join(clean, "skills/old-version/SKILL.md")), true,
      "a copy with an unsupported marker version is not removed");
    assert.match(result.stderr, /Keeping skill copy with an invalid copy marker: .*clean.skills.old-version/);
    assert.equal(existsSync(path.join(clean, "skills/linked-marker")), true);
    assert.match(result.stderr, /Keeping skill copy with an invalid copy marker: .*clean.skills.linked-marker/);
  } finally {
    await fixture.cleanup();
  }
});
