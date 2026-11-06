import assert from "node:assert/strict";
import { chmod, lstat, mkdir, readdir, readlink, realpath, rename, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import {
  repoRoot,
  skillsRuntime,
  createFixture,
  runSkills,
  runSkillsWithSymlinkError,
  runSkillsWithCrossDeviceBackupRenameError,
  readText,
  createClaudeEnvironment,
  privateSkillsBase,
} from "./skills-helpers.mjs";

test("profile validate accepts selected profiles", async () => {
  const fixture = await createFixture();
  try {
    const result = runSkills(["profile", "validate", "--profile", "base,office"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stdout, /Profiles valid: base,office/);
  } finally {
    await fixture.cleanup();
  }
});

test("profile validate rejects skill name collisions", async () => {
  const fixture = await createFixture();
  try {
    await mkdir(path.join(fixture.dotfiles, "skills", "local", "find-skills"), { recursive: true });
    await writeFile(
      path.join(fixture.dotfiles, "skills", "profiles", "collide.json"),
      JSON.stringify(
        {
          description: "Colliding test profile",
          includes: ["base"],
          external: [{ source: "acme/skills", skills: ["docx"] }],
          local: ["find-skills"],
        },
        null,
        2,
      ) + "\n",
    );

    const result = runSkills(["profile", "validate", "--profile", "office,collide"], fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skill name collision: docx \(anthropics\/skills, acme\/skills\)/);
    assert.match(result.stderr, /find-skills \(vercel-labs\/skills, local\)/);
  } finally {
    await fixture.cleanup();
  }
});

test("user scope builds one managed skill view and links selected user agents", async () => {
  const fixture = await createFixture();
  try {
    await mkdir(path.join(fixture.home, ".gemini"), { recursive: true });
    await symlink("/tmp/stale-gemini-skills", path.join(fixture.home, ".gemini", "skills"));

    const result = runSkills(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills", "find-skills")), true);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills", "local-one")), true);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills-profile.json")), true);
    assert.equal(existsSync(path.join(fixture.home, ".agents", "skills")), true);
    assert.equal(existsSync(path.join(fixture.home, ".claude", "skills")), true);
    assert.equal((await lstat(path.join(fixture.home, ".gemini", "skills"))).isSymbolicLink(), true);
    assert.equal(await readlink(path.join(fixture.home, ".gemini", "skills")), "/tmp/stale-gemini-skills");
    assert.match(await readText(fixture.log), /skills add vercel-labs\/skills/);
  } finally {
    await fixture.cleanup();
  }
});

test("user scope copies skill directories when symlinks are denied", async () => {
  const fixture = await createFixture();
  try {
    const result = runSkillsWithSymlinkError(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const restoreLocalSkill = path.join(fixture.dotfiles, ".agents", "user", "skills", "local-one");
    const homeCodexSkills = path.join(fixture.home, ".agents", "skills");
    const homeClaudeSkills = path.join(fixture.home, ".claude", "skills");
    assert.equal(existsSync(path.join(restoreLocalSkill, "SKILL.md")), true);
    assert.equal(existsSync(path.join(homeCodexSkills, "find-skills", "SKILL.md")), true);
    assert.equal(existsSync(path.join(homeCodexSkills, "local-one", "SKILL.md")), true);
    assert.equal(existsSync(path.join(homeClaudeSkills, "local-one", "SKILL.md")), true);
    assert.equal((await lstat(restoreLocalSkill)).isSymbolicLink(), false);
    assert.equal((await lstat(homeCodexSkills)).isSymbolicLink(), false);
  } finally {
    await fixture.cleanup();
  }
});

test("user refresh keeps dangling links from installs and synced skills", async () => {
  const fixture = await createFixture({ npxSuffix: "ln -s missing-target .agents/skills/installed-alias\n" });
  try {
    const view = path.join(fixture.dotfiles, ".agents", "user", "skills");
    await mkdir(path.join(view, "synced"), { recursive: true });
    await symlink("../missing-synced", path.join(view, "synced", "alias"));

    const result = runSkills(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readlink(path.join(view, "installed-alias")), "missing-target");
    assert.equal(await readlink(path.join(view, "synced", "alias")), "../missing-synced");
    assert.equal(existsSync(path.join(view, "find-skills", "SKILL.md")), true);
  } finally {
    await fixture.cleanup();
  }
});

test("user refresh preserves synced skills but removes deselected managed skills", async () => {
  const fixture = await createFixture();
  try {
    const view = path.join(fixture.dotfiles, ".agents", "user", "skills");
    const synced = path.join(view, "synced", "account", "custom");
    await mkdir(synced, { recursive: true });
    await writeFile(path.join(synced, "SKILL.md"), "synchronized content\n");
    await writeFile(path.join(synced, "helper.txt"), "supporting content\n");
    await symlink("helper.txt", path.join(synced, "helper-link"));
    await mkdir(path.join(view, "old-managed"), { recursive: true });
    await writeFile(path.join(view, "old-managed", "SKILL.md"), "old\n");

    const result = runSkills(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readText(path.join(synced, "SKILL.md")), "synchronized content\n");
    assert.equal(await readText(path.join(synced, "helper-link")), "supporting content\n");
    assert.equal(await readlink(path.join(synced, "helper-link")), "helper.txt");
    assert.equal(existsSync(path.join(view, "old-managed")), false);
    assert.equal(existsSync(path.join(view, "find-skills", "SKILL.md")), true);
  } finally {
    await fixture.cleanup();
  }
});

test("user install rejects missing skills even when the CLI exits successfully", async () => {
  const fixture = await createFixture({ npxBody: "#!/bin/sh\nexit 0\n" });
  try {
    const root = path.join(fixture.dotfiles, ".agents", "user");
    const old = path.join(root, "skills", "find-skills");
    await mkdir(old, { recursive: true });
    await writeFile(path.join(old, "SKILL.md"), "previous skill\n");
    await writeFile(path.join(root, "skills-profile.json"), "previous metadata\n");

    const result = runSkills(["--scope", "user", "--profile", "base"], fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr + result.stdout, /Missing installed skill find-skills/);
    assert.equal(await readText(path.join(old, "SKILL.md")), "previous skill\n");
    assert.equal(await readText(path.join(root, "skills-profile.json")), "previous metadata\n");
    assert.equal(existsSync(path.join(fixture.home, ".agents", "skills")), false);
  } finally {
    await fixture.cleanup();
  }
});

test("project install restores prior state when a selected agent is missing a skill", async () => {
  const fixture = await createFixture({ npxBody: `#!/bin/sh
mkdir -p .agents/skills/find-skills
printf 'new skill' > .agents/skills/find-skills/SKILL.md
printf 'new lock' > skills-lock.json
printf 'ran\\n' > "\${TEST_SKILLS_LOG}.ran"
exit 0
` });
  try {
    const old = path.join(fixture.project, ".claude", "skills", "custom");
    await mkdir(old, { recursive: true });
    await writeFile(path.join(old, "SKILL.md"), "previous skill\n");
    await mkdir(path.join(fixture.project, ".agents"), { recursive: true });
    const metadata = path.join(fixture.project, ".agents", "skills-profile.json");
    await writeFile(metadata, "previous metadata\n");
    await writeFile(path.join(fixture.project, "skills-lock.json"), "previous lock\n");

    const result = runSkills(
      ["--scope", "project", "--profile", "base", "--agent", "codex", "--agent", "claude-code"],
      fixture, { cwd: fixture.project },
    );

    assert.notEqual(result.status, 0);
    assert.equal(await readText(`${fixture.log}.ran`), "ran\n");
    assert.match(result.stderr + result.stdout, /Missing installed skill find-skills/);
    assert.equal(await readText(path.join(old, "SKILL.md")), "previous skill\n");
    assert.equal(await readText(metadata), "previous metadata\n");
    assert.equal(await readText(path.join(fixture.project, "skills-lock.json")), "previous lock\n");
    assert.equal(existsSync(path.join(fixture.project, ".agents", "skills")), false);
  } finally {
    await fixture.cleanup();
  }
});

test("user scope can skip linking user agent skill directories", async () => {
  const fixture = await createFixture();
  try {
    const environment = await createClaudeEnvironment(fixture);
    const result = spawnSync(process.execPath, [skillsRuntime, "--scope", "user", "--profile", "base"], {
      cwd: repoRoot,
      env: {
        ...fixture.env,
        SETUP_SKIP_USER_AGENT_SKILL_LINKS: "1",
      },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills", "find-skills")), true);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills", "local-one")), true);
    assert.equal(existsSync(path.join(fixture.home, ".agents", "skills")), false);
    assert.equal(existsSync(path.join(fixture.home, ".claude", "skills")), false);
    assert.deepEqual(await readdir(path.join(environment, "skills")), []);
    assert.match(result.stdout, /User agent skill links skipped/);
  } finally {
    await fixture.cleanup();
  }
});

test("user scope can skip linking local skills while recording metadata", async () => {
  const fixture = await createFixture();
  try {
    const environment = await createClaudeEnvironment(fixture);
    const result = spawnSync(process.execPath, [skillsRuntime, "--scope", "user", "--profile", "base"], {
      cwd: repoRoot,
      env: {
        ...fixture.env,
        SETUP_SKIP_USER_LOCAL_SKILL_LINKS: "1",
      },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills", "find-skills")), true);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills", "local-one")), false);
    assert.equal(existsSync(path.join(environment, "skills", "find-skills", "SKILL.md")), true);
    assert.equal(existsSync(path.join(environment, "skills", "local-one")), false);
    const metadata = JSON.parse(await readText(path.join(fixture.dotfiles, ".agents", "user", "skills-profile.json")));
    assert.deepEqual(metadata.localSkills, ["local-one"]);
    assert.match(result.stdout, /User local skill links skipped/);
  } finally {
    await fixture.cleanup();
  }
});

test("dry-run user scope does not write managed skill outputs", async () => {
  const fixture = await createFixture();
  try {
    const environment = await createClaudeEnvironment(fixture);
    const result = spawnSync(process.execPath, [skillsRuntime, "--scope", "user", "--profile", "base"], {
      cwd: repoRoot,
      env: {
        ...fixture.env,
        SETUP_DRY_RUN: "1",
      },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stdout, /DRY-RUN/);
    assert.ok(result.stdout.includes(path.join(environment, "skills", "local-one")));
    assert.deepEqual(await readdir(path.join(environment, "skills")), []);
    assert.equal(existsSync(path.join(fixture.dotfiles, ".agents", "user", "skills")), false);
    assert.equal(existsSync(path.join(fixture.home, ".agents", "skills")), false);
    assert.equal(existsSync(fixture.log), false);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope installs external and local skills for selected agents", async () => {
  const fixture = await createFixture();
  try {
    const result = runSkills(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(path.join(fixture.project, ".agents", "skills", "docx")), true);
    assert.equal(existsSync(path.join(fixture.project, ".agents", "skills", "pdf")), true);
    assert.equal(existsSync(path.join(fixture.project, ".agents", "skills", "find-skills")), true);
    assert.equal(existsSync(path.join(fixture.project, ".claude", "skills", "docx")), true);
    assert.equal(existsSync(path.join(fixture.project, ".claude", "skills", "pdf")), true);
    assert.equal(existsSync(path.join(fixture.project, ".claude", "skills", "find-skills")), true);
    assert.equal(existsSync(path.join(fixture.project, ".agents", "skills", "local-one")), true);
    assert.equal(existsSync(path.join(fixture.project, ".claude", "skills", "local-one")), true);
    assert.equal(existsSync(path.join(fixture.project, "skills-lock.json")), true);
    assert.match(await readText(path.join(fixture.project, ".agents", "skills-profile.json")), /"office"/);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope preserves unmanaged existing skills when install refreshes targets", async () => {
  const fixture = await createFixture({
    npxBody: `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"

if [ "$#" -lt 3 ] || [ "$1" != "skills" ] || [ "$2" != "add" ]; then
  printf 'unexpected npx invocation: %s\\n' "$*" >&2
  exit 1
fi

shift 2
source_name="$1"
shift

agents=()
skills=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)
      agents+=("$2")
      shift 2
      ;;
    --skill)
      skills+=("$2")
      shift 2
      ;;
    --copy|--yes)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -f .refresh-targets-once ]; then
  rm -rf .agents/skills .claude/skills
  touch .refresh-targets-once
fi
mkdir -p .agents/skills .claude/skills
printf '{"version":3,"source":"%s"}\\n' "\${source_name}" > skills-lock.json
for skill_name in "\${skills[@]}"; do
  for agent_name in "\${agents[@]}"; do
    case "\${agent_name}" in
      codex)
        mkdir -p ".agents/skills/\${skill_name}"
        printf '%s\\n' "\${skill_name}" > ".agents/skills/\${skill_name}/SKILL.md"
        ;;
      claude-code)
        mkdir -p ".claude/skills/\${skill_name}"
        printf '%s\\n' "\${skill_name}" > ".claude/skills/\${skill_name}/SKILL.md"
        ;;
    esac
  done
done
`,
  });
  try {
    await mkdir(path.join(fixture.project, ".agents", "skills", "beads-generated"), { recursive: true });
    await mkdir(path.join(fixture.project, ".claude", "skills", "beads-generated"), { recursive: true });
    await writeFile(path.join(fixture.project, ".agents", "skills", "beads-generated", "SKILL.md"), "codex beads\n");
    await writeFile(path.join(fixture.project, ".claude", "skills", "beads-generated", "SKILL.md"), "claude beads\n");

    const result = runSkills(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "beads-generated", "SKILL.md")), "codex beads\n");
    assert.equal(await readText(path.join(fixture.project, ".claude", "skills", "beads-generated", "SKILL.md")), "claude beads\n");
    assert.equal(existsSync(path.join(fixture.project, ".agents", "skills", "docx")), true);
    assert.equal(existsSync(path.join(fixture.project, ".claude", "skills", "docx")), true);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope prunes links of a renamed local skill and keeps unmanaged links", async () => {
  const fixture = await createFixture();
  try {
    const args = ["--scope", "project", "--profile", "base", "--agent", "codex"];
    const skills = path.join(fixture.project, ".agents", "skills");
    const local = path.join(fixture.dotfiles, "skills", "local");
    const outside = path.join(fixture.root, "outside-skill");
    await mkdir(outside);
    let result = runSkills(args, fixture, { cwd: fixture.project });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readlink(path.join(skills, "local-one")), path.join(local, "local-one"));
    await symlink(outside, path.join(skills, "user-link"), "dir");

    await rename(path.join(local, "local-one"), path.join(local, "local-two"));
    await symlink(path.join(local, "local-two"), path.join(skills, "alias"), "dir");
    const profile = path.join(fixture.dotfiles, "skills", "profiles", "base.json");
    const base = JSON.parse(await readText(profile));
    base.local = ["local-two"];
    await writeFile(profile, JSON.stringify(base, null, 2) + "\n");

    const dryRun = runSkills(args, { ...fixture, env: { ...fixture.env, SETUP_DRY_RUN: "1" } }, { cwd: fixture.project });
    assert.equal(dryRun.status, 0, dryRun.stderr || dryRun.stdout);
    assert.ok(dryRun.stdout.includes(`DRY-RUN remove stale skill entry ${path.join(skills, "local-one")}`));
    assert.equal(dryRun.stdout.includes(path.join(skills, "user-link")), false);
    assert.equal(dryRun.stdout.includes(path.join(skills, "alias")), false);
    assert.equal(await readlink(path.join(skills, "local-one")), path.join(local, "local-one"));
    assert.equal(await readlink(path.join(skills, "alias")), path.join(local, "local-two"));

    result = runSkills(args, fixture, { cwd: fixture.project });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.deepEqual((await readdir(skills)).sort(), ["alias", "find-skills", "local-two", "user-link"]);
    assert.equal(await readlink(path.join(skills, "local-two")), path.join(local, "local-two"));
    assert.equal(await readlink(path.join(skills, "user-link")), outside);
    assert.ok(result.stdout.includes(`Removed stale skill entry: ${path.join(skills, "local-one")}`));
  } finally {
    await fixture.cleanup();
  }
});

test("project scope keeps unchanged copies of a removed skill only in the backup and restores edited ones", async () => {
  const fixture = await createFixture();
  try {
    const args = ["--scope", "project", "--profile", "base", "--agent", "codex", "--agent", "claude-code"];
    const codexSkills = path.join(fixture.project, ".agents", "skills");
    const claudeSkills = path.join(fixture.project, ".claude", "skills");
    const local = path.join(fixture.dotfiles, "skills", "local");
    let result = runSkillsWithSymlinkError(args, fixture, { cwd: fixture.project });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    for (const skills of [codexSkills, claudeSkills]) {
      assert.equal((await lstat(path.join(skills, "local-one"))).isSymbolicLink(), false);
      assert.equal(existsSync(path.join(skills, ".dotfiles-copy-local-one.json")), true);
    }
    await writeFile(path.join(claudeSkills, "local-one", "SKILL.md"), "local edit\n");

    await rename(path.join(local, "local-one"), path.join(local, "local-two"));
    const profile = path.join(fixture.dotfiles, "skills", "profiles", "base.json");
    const base = JSON.parse(await readText(profile));
    base.local = ["local-two"];
    await writeFile(profile, JSON.stringify(base, null, 2) + "\n");

    const dryRun = runSkillsWithSymlinkError(args, { ...fixture, env: { ...fixture.env, SETUP_DRY_RUN: "1" } }, { cwd: fixture.project });
    assert.equal(dryRun.status, 0, dryRun.stderr || dryRun.stdout);
    assert.ok(dryRun.stdout.includes(`DRY-RUN remove stale skill entry ${path.join(codexSkills, "local-one")}`));
    assert.equal(dryRun.stdout.includes(path.join(claudeSkills, "local-one")), false);
    assert.equal(existsSync(path.join(codexSkills, "local-one", "SKILL.md")), true, "dry run should not remove copies");

    result = runSkillsWithSymlinkError(args, fixture, { cwd: fixture.project });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.ok(result.stdout.includes(`Removed stale skill entry: ${path.join(codexSkills, "local-one")}`));
    assert.equal(existsSync(path.join(codexSkills, "local-one")), false);
    assert.equal(existsSync(path.join(codexSkills, ".dotfiles-copy-local-one.json")), false);
    assert.equal(existsSync(path.join(codexSkills, "local-two", "SKILL.md")), true);
    const backupRoot = path.join(await realpath(privateSkillsBase(fixture)), "dotfiles-skills-backup", path.basename(fixture.project));
    assert.match(result.stderr, new RegExp(`Backed up existing skills path to ${escapeRegExp(backupRoot + path.sep)}`));
    const [codexBackup] = (await readdir(backupRoot)).filter(name => name.startsWith(".agents-skills."));
    assert.ok(codexBackup, "the codex skills directory should be backed up");
    assert.equal(existsSync(path.join(backupRoot, codexBackup, "local-one", "SKILL.md")), true,
      "the unchanged copy should stay in the backup");
    assert.equal(existsSync(path.join(backupRoot, codexBackup, ".dotfiles-copy-local-one.json")), true);
    assert.equal(await readText(path.join(claudeSkills, "local-one", "SKILL.md")), "local edit\n");
    assert.equal(existsSync(path.join(claudeSkills, ".dotfiles-copy-local-one.json")), true);
    assert.match(result.stderr, /Keeping locally edited copy of a removed skill: .*\.claude.skills.local-one/);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope restores dangling unmanaged links unchanged", async () => {
  const fixture = await createFixture();
  try {
    const codexSkills = path.join(fixture.project, ".agents", "skills");
    const claudeSkills = path.join(fixture.project, ".claude", "skills");
    const outside = path.join(fixture.root, "outside-skill");
    const removed = path.join(fixture.root, "removed-skill");
    await mkdir(outside);
    await mkdir(path.join(codexSkills, "kept"), { recursive: true });
    await mkdir(claudeSkills, { recursive: true });
    await writeFile(path.join(codexSkills, "kept", "SKILL.md"), "kept\n");
    await symlink("missing.md", path.join(codexSkills, "kept", "nested-link"));
    await symlink("../renamed-skill", path.join(codexSkills, "relative-alias"));
    await symlink(removed, path.join(claudeSkills, "absolute-alias"));
    await symlink(outside, path.join(codexSkills, "valid-link"), "dir");

    const result = runSkills(
      ["--scope", "project", "--profile", "base", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readlink(path.join(codexSkills, "relative-alias")), "../renamed-skill");
    assert.equal(await readlink(path.join(claudeSkills, "absolute-alias")), removed);
    assert.equal(await readlink(path.join(codexSkills, "kept", "nested-link")), "missing.md");
    assert.equal(await readText(path.join(codexSkills, "kept", "SKILL.md")), "kept\n");
    assert.equal(await readlink(path.join(codexSkills, "valid-link")), outside);
    assert.equal(existsSync(path.join(codexSkills, "find-skills", "SKILL.md")), true);
    assert.equal(existsSync(path.join(claudeSkills, "find-skills", "SKILL.md")), true);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope requires an explicit profile", async () => {
  const fixture = await createFixture();
  try {
    const result = runSkills(["--scope", "project"], fixture, { cwd: fixture.project });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /--profile is required for project scope/);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope restores existing outputs when external install fails", async () => {
  const fixture = await createFixture({
    npxBody: `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
exit 42
`,
  });
  try {
    await mkdir(path.join(fixture.project, ".agents", "skills", "old-agent"), { recursive: true });
    await mkdir(path.join(fixture.project, ".claude", "skills", "old-claude"), { recursive: true });
    await writeFile(path.join(fixture.project, "skills-lock.json"), "old-lock\n");
    await writeFile(path.join(fixture.project, ".agents", "skills-profile.json"), "old-profile\n");
    await writeFile(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md"), "old-agent\n");
    await writeFile(path.join(fixture.project, ".claude", "skills", "old-claude", "SKILL.md"), "old-claude\n");

    const result = runSkills(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.notEqual(result.status, 0);
    assert.equal(await readText(path.join(fixture.project, "skills-lock.json")), "old-lock\n");
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills-profile.json")), "old-profile\n");
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md")), "old-agent\n");
    assert.equal(await readText(path.join(fixture.project, ".claude", "skills", "old-claude", "SKILL.md")), "old-claude\n");
  } finally {
    await fixture.cleanup();
  }
});

test("project scope restores existing outputs when backup moves cross devices", async () => {
  const fixture = await createFixture({
    npxBody: `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
mkdir -p .agents/skills/partial .claude/skills/partial
printf 'partial-lock\\n' > skills-lock.json
printf 'partial-agent\\n' > .agents/skills/partial/SKILL.md
printf 'partial-claude\\n' > .claude/skills/partial/SKILL.md
exit 42
`,
  });
  try {
    await mkdir(path.join(fixture.project, ".agents", "skills", "old-agent"), { recursive: true });
    await mkdir(path.join(fixture.project, ".claude", "skills", "old-claude"), { recursive: true });
    await writeFile(path.join(fixture.project, "skills-lock.json"), "old-lock\n");
    await writeFile(path.join(fixture.project, ".agents", "skills-profile.json"), "old-profile\n");
    await writeFile(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md"), "old-agent\n");
    await writeFile(path.join(fixture.project, ".claude", "skills", "old-claude", "SKILL.md"), "old-claude\n");

    const result = runSkillsWithCrossDeviceBackupRenameError(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.notEqual(result.status, 0);
    assert.equal(existsSync(`${fixture.log}.exdev`), true, "backup moves should take the cross-device path");
    assert.doesNotMatch(result.stderr, /EXDEV/);
    assert.match(await readText(fixture.log), /skills add anthropics\/skills/);
    assert.equal(await readText(path.join(fixture.project, "skills-lock.json")), "old-lock\n");
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills-profile.json")), "old-profile\n");
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md")), "old-agent\n");
    assert.equal(await readText(path.join(fixture.project, ".claude", "skills", "old-claude", "SKILL.md")), "old-claude\n");
  } finally {
    await fixture.cleanup();
  }
});

test("project scope rollback keeps dangling links when backups move cross devices", async () => {
  const fixture = await createFixture({
    npxBody: `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
exit 42
`,
  });
  try {
    const codexSkills = path.join(fixture.project, ".agents", "skills");
    const claudeSkills = path.join(fixture.project, ".claude", "skills");
    await mkdir(codexSkills, { recursive: true });
    await mkdir(claudeSkills, { recursive: true });
    await symlink("missing-skill", path.join(codexSkills, "alias"));
    await symlink("../missing-skills", path.join(claudeSkills, "relative-alias"));

    const result = runSkillsWithCrossDeviceBackupRenameError(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.notEqual(result.status, 0);
    assert.equal(existsSync(`${fixture.log}.exdev`), true, "backup moves should take the cross-device path");
    assert.doesNotMatch(result.stderr, /ENOENT|EXDEV/);
    assert.match(await readText(fixture.log), /skills add anthropics\/skills/);
    assert.equal(await readlink(path.join(codexSkills, "alias")), "missing-skill");
    assert.equal(await readlink(path.join(claudeSkills, "relative-alias")), "../missing-skills");
  } finally {
    await fixture.cleanup();
  }
});

// Like npx, run a node_modules/.bin/skills found in any ancestor of the
// current directory before installing.
const stagingNpxBody = `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\${PWD}" > "\${TEST_SKILLS_LOG}.cwd"
mode="$(ls -ld "\${PWD}")"
printf '%s\\n' "\${mode:0:10}" > "\${TEST_SKILLS_LOG}.mode"
printf '%s\\n' "\${NPM_CONFIG_CACHE}" > "\${TEST_SKILLS_LOG}.cache"
dir="\${PWD}"
while :; do
  if [ -x "\${dir}/node_modules/.bin/skills" ]; then
    exec "\${dir}/node_modules/.bin/skills" "$@"
  fi
  [ "\${dir}" = / ] && break
  dir="\${dir%/*}"
  dir="\${dir:-/}"
done
if [ -n "\${TEST_NPX_EXIT:-}" ]; then
  exit "\${TEST_NPX_EXIT}"
fi
if [ -n "\${TEST_LOCK_STAGING:-}" ]; then
  mkdir -p locked
  : > locked/file
  chmod 500 locked
fi
mkdir -p .agents/skills/find-skills
printf 'find-skills\\n' > .agents/skills/find-skills/SKILL.md
printf 'new lock\\n' > skills-lock.json
`;

function runProjectInstall(fixture) {
  return runSkills(["--scope", "project", "--profile", "base", "--agent", "codex"], fixture, { cwd: fixture.project });
}

test("project scope stages each install in a private directory under XDG_CACHE_HOME", { skip: process.platform === "darwin" || process.platform === "win32" }, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  fixture.env.XDG_CACHE_HOME = path.join(fixture.root, "xdg-cache");
  try {
    const result = runProjectInstall(fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const staging = (await readText(`${fixture.log}.cwd`)).trim();
    assert.equal(path.dirname(staging), fixture.env.XDG_CACHE_HOME);
    assert.match(path.basename(staging), /^dotfiles-skills-.+/);
    assert.equal((await readText(`${fixture.log}.mode`)).trim(), "drwx------");
    assert.equal(existsSync(staging), false);
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "find-skills", "SKILL.md")), "find-skills\n");
    assert.equal(await readText(path.join(fixture.project, "skills-lock.json")), "new lock\n");
  } finally {
    await fixture.cleanup();
  }
});

test("project scope stages under ~/.cache when XDG_CACHE_HOME is not absolute", { skip: process.platform === "darwin" || process.platform === "win32" }, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  fixture.env.XDG_CACHE_HOME = "relative-cache";
  try {
    const result = runProjectInstall(fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const staging = (await readText(`${fixture.log}.cwd`)).trim();
    assert.equal(path.dirname(staging), path.join(fixture.home, ".cache"));
    assert.equal(existsSync(staging), false);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope removes the staging directory after a failed install", { skip: process.platform === "darwin" || process.platform === "win32" }, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  fixture.env.XDG_CACHE_HOME = path.join(fixture.root, "xdg-cache");
  fixture.env.TEST_NPX_EXIT = "42";
  try {
    const result = runProjectInstall(fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /failed with exit 42/);
    const staging = (await readText(`${fixture.log}.cwd`)).trim();
    assert.equal(path.dirname(staging), fixture.env.XDG_CACHE_HOME);
    assert.equal(existsSync(staging), false);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope does not stage under SETUP_TMPDIR where a parent node_modules/.bin could be planted", async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  fixture.env.XDG_CACHE_HOME = path.join(fixture.root, "xdg-cache");
  fixture.env.TMPDIR = path.join(fixture.root, "user-temp");
  await mkdir(fixture.env.TMPDIR, { recursive: true });
  try {
    const plantedBin = path.join(fixture.tmp, "node_modules", ".bin");
    await mkdir(plantedBin, { recursive: true });
    await writeFile(
      path.join(plantedBin, "skills"),
      `#!/bin/sh\nprintf 'planted\\n' >> "\${TEST_SKILLS_LOG}.planted"\nexit 99\n`,
      { mode: 0o755 },
    );

    const result = runProjectInstall(fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(`${fixture.log}.planted`), false);
    const staging = (await readText(`${fixture.log}.cwd`)).trim();
    assert.equal(staging.startsWith(fixture.tmp + path.sep), false);
  } finally {
    await fixture.cleanup();
  }
});

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const posixOnly = { skip: process.platform === "win32" };
const linuxOnly = { skip: process.platform === "darwin" || process.platform === "win32" };

async function plantSkillsBin(dir) {
  const bin = path.join(dir, "node_modules", ".bin");
  await mkdir(bin, { recursive: true });
  await writeFile(
    path.join(bin, "skills"),
    `#!/bin/sh\nprintf 'planted\\n' >> "\${TEST_SKILLS_LOG}.planted"\nexit 99\n`,
    { mode: 0o755 },
  );
}

test("project scope fails closed when SETUP_HOME is relative", linuxOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  fixture.env.SETUP_HOME = "relative-home";
  try {
    await plantSkillsBin(fixture.project);

    const result = runProjectInstall(fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /set HOME or XDG_CACHE_HOME to an absolute path/);
    assert.equal(existsSync(`${fixture.log}.planted`), false);
    assert.equal(existsSync(`${fixture.log}.cwd`), false);
    assert.equal(existsSync(path.join(fixture.project, "relative-home")), false);
    assert.equal(existsSync(path.join(fixture.project, ".cache")), false);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope refuses a staging base with an ancestor others can write", linuxOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  const shared = path.join(fixture.root, "shared");
  fixture.env.XDG_CACHE_HOME = path.join(shared, "cache");
  try {
    await mkdir(shared);
    await chmod(shared, 0o1777);

    const refused = runProjectInstall(fixture);

    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, new RegExp(`${shared.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")} must be owned by you or root and not writable by others`));
    assert.equal(existsSync(`${fixture.log}.cwd`), false);

    // Whether a group-writable ancestor is allowed depends on the host's
    // groups; private-base.test.mjs covers that rule.
    await chmod(shared, 0o755);
    const allowed = runProjectInstall(fixture);

    assert.equal(allowed.status, 0, allowed.stderr || allowed.stdout);
    assert.equal(path.dirname((await readText(`${fixture.log}.cwd`)).trim()), await realpath(fixture.env.XDG_CACHE_HOME));
  } finally {
    await fixture.cleanup();
  }
});

test("macOS project scope fails closed when TMPDIR is unset and the temp dir is /tmp", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  delete fixture.env.TMPDIR;
  try {
    const launcher = `
const runtime = process.argv[1];
Object.defineProperty(process, "platform", { value: "darwin" });
process.argv = [process.execPath, runtime, ...process.argv.slice(2)];
require(runtime);
`;
    const result = spawnSync(
      process.execPath,
      ["-e", launcher, skillsRuntime, "--scope", "project", "--profile", "base", "--agent", "codex"],
      { cwd: fixture.project, env: fixture.env, encoding: "utf8" },
    );

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /must be owned by you or root and not writable by others; set XDG_CACHE_HOME \(Linux\) or TMPDIR \(macOS\)/);
    assert.equal(existsSync(`${fixture.log}.cwd`), false);
  } finally {
    await fixture.cleanup();
  }
});

function runSkillsAsDarwin(args, fixture) {
  const launcher = `
const runtime = process.argv[1];
Object.defineProperty(process, "platform", { value: "darwin" });
process.argv = [process.execPath, runtime, ...process.argv.slice(2)];
require(runtime);
`;
  return spawnSync(process.execPath, ["-e", launcher, skillsRuntime, ...args], {
    cwd: fixture.project,
    env: fixture.env,
    encoding: "utf8",
  });
}

for (const scope of ["project", "user"]) {
  test(`macOS ${scope} scope fails closed on a relative TMPDIR, even one linking out of the project, and creates nothing`, posixOnly, async () => {
    const fixture = await createFixture({ npxBody: stagingNpxBody });
    const outside = path.join(fixture.root, "outside-temp");
    try {
      await mkdir(outside, { mode: 0o700 });
      await symlink(outside, path.join(fixture.project, "linked-temp"));
      for (const temp of ["relative-temp", "linked-temp"]) {
        fixture.env.TMPDIR = temp;
        const args = scope === "project"
          ? ["--scope", "project", "--profile", "base", "--agent", "codex"]
          : ["--scope", "user", "--profile", "base"];

        const result = runSkillsAsDarwin(args, fixture);

        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /set TMPDIR to an absolute per-user directory/);
        assert.equal(existsSync(`${fixture.log}.cwd`), false);
        assert.deepEqual((await readdir(fixture.project)).sort(), [".git", "linked-temp"]);
        assert.deepEqual(await readdir(outside), []);
      }
    } finally {
      await fixture.cleanup();
    }
  });
}

test("project scope refuses a TMPDIR inside the project that differs only in letter case", posixOnly, async (t) => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  try {
    const variant = path.join(path.dirname(fixture.project), path.basename(fixture.project).toUpperCase());
    if (!existsSync(variant)) {
      t.skip("the file system is case-sensitive");
      return;
    }
    fixture.env.TMPDIR = path.join(variant, "temp");

    const result = runSkillsAsDarwin(["--scope", "project", "--profile", "base", "--agent", "codex"], fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cannot keep project skill staging inside the project/);
    assert.equal(existsSync(`${fixture.log}.cwd`), false);
    assert.deepEqual(await readdir(fixture.project), [".git"]);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope refusing a staging base creates none of its missing directories", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  const shared = path.join(fixture.root, "shared");
  try {
    await mkdir(shared);
    await chmod(shared, 0o1777);
    fixture.env.TMPDIR = path.join(shared, "new", "temp");

    const result = runSkillsAsDarwin(["--scope", "project", "--profile", "base", "--agent", "codex"], fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /must be owned by you or root and not writable by others/);
    assert.deepEqual(await readdir(shared), []);
    assert.deepEqual(await readdir(fixture.project), [".git"]);
  } finally {
    await fixture.cleanup();
  }
});

test("macOS project scope refuses a group-writable ancestor and creates nothing", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  const grouped = path.join(fixture.root, "grouped");
  try {
    await mkdir(grouped);
    await chmod(grouped, 0o775);
    fixture.env.TMPDIR = path.join(grouped, "temp");

    const result = runSkillsAsDarwin(["--scope", "project", "--profile", "base", "--agent", "codex"], fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, new RegExp(`${escapeRegExp(await realpath(grouped))} is writable by group \\d+, which is not your private group; run chmod g-w`));
    assert.equal(existsSync(`${fixture.log}.cwd`), false);
    assert.deepEqual(await readdir(grouped), []);
    assert.deepEqual(await readdir(fixture.project), [".git"]);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope warns and keeps a successful install when staging cleanup fails", {
  skip: process.platform === "win32" || process.getuid?.() === 0,
}, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  fixture.env.TEST_LOCK_STAGING = "1";
  let staging;
  try {
    const result = runProjectInstall(fixture);
    staging = (await readText(`${fixture.log}.cwd`)).trim();

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stderr, /Could not remove staging directory/);
    assert.doesNotMatch(result.stderr, /Restored previous project skills/);
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "find-skills", "SKILL.md")), "find-skills\n");
  } finally {
    if (staging && existsSync(path.join(staging, "locked"))) {
      await chmod(path.join(staging, "locked"), 0o700);
    }
    await fixture.cleanup();
  }
});

function runUserInstall(fixture) {
  return runSkills(["--scope", "user", "--profile", "base", "--agent", "codex"], fixture);
}

test("user scope stages each source in a private per-run directory outside SETUP_TMPDIR", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  try {
    await plantSkillsBin(fixture.tmp);

    const result = runUserInstall(fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(`${fixture.log}.planted`), false);
    const base = await realpath(privateSkillsBase(fixture));
    const installDir = (await readText(`${fixture.log}.cwd`)).trim();
    assert.equal(path.basename(installDir), "0");
    const workDir = path.dirname(installDir);
    assert.equal(path.dirname(workDir), base);
    assert.match(path.basename(workDir), /^dotfiles-skills-user-.+/);
    assert.equal((await readText(`${fixture.log}.mode`)).trim(), "drwx------");
    assert.equal(existsSync(workDir), false);
    assert.equal(await readText(`${fixture.log}.cache`), `${path.join(base, "dotfiles-skills-npm-cache")}\n`);
    assert.deepEqual(await readdir(fixture.tmp), ["node_modules"]);
    assert.equal(await readText(path.join(fixture.dotfiles, ".agents", "user", "skills", "find-skills", "SKILL.md")), "find-skills\n");
  } finally {
    await fixture.cleanup();
  }
});

test("dry-run user scope shows the private staging directory and npm cache", posixOnly, async () => {
  const fixture = await createFixture();
  try {
    const result = runSkills(["--scope", "user", "--profile", "base"], { ...fixture, env: { ...fixture.env, SETUP_DRY_RUN: "1" } });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const base = privateSkillsBase(fixture);
    assert.ok(result.stdout.includes(`DRY-RUN mktemp -d ${path.join(base, "dotfiles-skills-user-XXXXXX")}`), result.stdout);
    assert.ok(result.stdout.includes(`NPM_CONFIG_CACHE=${path.join(base, "dotfiles-skills-npm-cache")} npx skills add`), result.stdout);
    assert.equal(result.stdout.includes(fixture.tmp), false);
    assert.equal(existsSync(path.join(base, "dotfiles-skills-npm-cache")), false);
  } finally {
    await fixture.cleanup();
  }
});

test("user scope refuses a staging base with an ancestor others can write and keeps the user view", linuxOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  const shared = path.join(fixture.root, "shared");
  fixture.env.XDG_CACHE_HOME = path.join(shared, "cache");
  try {
    await mkdir(shared);
    await chmod(shared, 0o1777);
    const userRoot = path.join(fixture.dotfiles, ".agents", "user");
    await mkdir(path.join(userRoot, "skills", "old-user"), { recursive: true });
    await writeFile(path.join(userRoot, "skills", "old-user", "SKILL.md"), "old-user\n");
    await writeFile(path.join(userRoot, "skills-profile.json"), "old-profile\n");

    const result = runUserInstall(fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, new RegExp(`cannot keep user skill staging under .*: ${escapeRegExp(shared)} must be owned by you or root and not writable by others`));
    assert.equal(existsSync(`${fixture.log}.cwd`), false);
    assert.deepEqual((await readdir(userRoot)).sort(), ["skills", "skills-profile.json"]);
    assert.equal(await readText(path.join(userRoot, "skills", "old-user", "SKILL.md")), "old-user\n");
    assert.equal(await readText(path.join(userRoot, "skills-profile.json")), "old-profile\n");
  } finally {
    await fixture.cleanup();
  }
});

for (const scope of ["user", "project"]) {
  test(`${scope} scope refuses an npm cache directory that others can write`, posixOnly, async () => {
    const fixture = await createFixture({ npxBody: stagingNpxBody });
    try {
      const cache = path.join(privateSkillsBase(fixture), "dotfiles-skills-npm-cache");
      await mkdir(cache, { recursive: true });
      await chmod(cache, 0o777);

      const result = scope === "user" ? runUserInstall(fixture) : runProjectInstall(fixture);

      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /cannot keep the skills npm cache under .* must be owned by you or root and not writable by others/);
      assert.equal(existsSync(`${fixture.log}.cwd`), false);
      assert.deepEqual(await readdir(fixture.project), [".git"]);
      assert.equal(existsSync(path.join(fixture.dotfiles, ".agents")), false);
    } finally {
      await fixture.cleanup();
    }
  });
}

test("project scope reuses one npm cache and keeps backups in the private directory, not SETUP_TMPDIR", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  try {
    let result = runProjectInstall(fixture);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const firstCache = await readText(`${fixture.log}.cache`);

    result = runProjectInstall(fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const base = await realpath(privateSkillsBase(fixture));
    assert.equal(firstCache, `${path.join(base, "dotfiles-skills-npm-cache")}\n`);
    assert.equal(await readText(`${fixture.log}.cache`), firstCache);
    assert.equal(existsSync(firstCache.trim()), true);
    const backupRoot = path.join(base, "dotfiles-skills-backup", path.basename(fixture.project));
    const backups = await readdir(backupRoot);
    assert.ok(backups.some(name => name.startsWith(".agents-skills.")), backups.join(","));
    assert.ok(backups.some(name => name.startsWith("project-skills-lock.json.")), backups.join(","));
    assert.deepEqual(await readdir(fixture.tmp), []);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope refuses a backup directory that others can write before moving anything", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  try {
    const backups = path.join(privateSkillsBase(fixture), "dotfiles-skills-backup");
    await mkdir(backups, { recursive: true });
    await chmod(backups, 0o777);
    await mkdir(path.join(fixture.project, ".agents", "skills", "old-agent"), { recursive: true });
    await writeFile(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md"), "old-agent\n");

    const result = runProjectInstall(fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cannot keep project skill backups under .* must be owned by you or root and not writable by others/);
    assert.equal(existsSync(`${fixture.log}.cwd`), false);
    assert.deepEqual(await readdir(path.join(fixture.project, ".agents")), ["skills"]);
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md")), "old-agent\n");
    assert.deepEqual(await readdir(backups), []);
    // The npm cache, checked before the backups, is not created either.
    assert.deepEqual(await readdir(privateSkillsBase(fixture)), ["dotfiles-skills-backup"]);
  } finally {
    await fixture.cleanup();
  }
});

// A checkout controls .agents, .claude, and the managed paths below them.
// Setup refuses a link at any of them, wherever it points: a link moved into
// the backup directory resolves again from there.
const projectLinkCases = [
  { name: ".claude links outside", agent: "claude-code", link: ".claude", target: root => path.join(root, "outside") },
  { name: ".agents links outside", agent: "codex", link: ".agents", target: root => path.join(root, "outside") },
  { name: ".claude/skills links outside", agent: "claude-code", link: path.join(".claude", "skills"), target: root => path.join(root, "outside", "skills") },
  { name: ".agents/skills links outside", agent: "codex", link: path.join(".agents", "skills"), target: root => path.join(root, "outside", "skills") },
  { name: "skills-lock.json links outside", agent: "codex", link: "skills-lock.json", target: root => path.join(root, "outside", "skills-lock.json") },
  { name: ".agents/skills-profile.json links outside", agent: "codex", link: path.join(".agents", "skills-profile.json"), target: root => path.join(root, "outside", "skills-profile.json") },
  { name: ".claude links to a missing directory outside", agent: "claude-code", link: ".claude", target: root => path.join(root, "missing-outside") },
  { name: ".agents/skills links to the project root", agent: "codex", link: path.join(".agents", "skills"), target: () => ".." },
  { name: ".agents/skills links to a directory inside the project", agent: "codex", link: path.join(".agents", "skills"), target: () => path.join("..", "shared-skills") },
  { name: ".claude/skills links to a missing path inside the project", agent: "claude-code", link: path.join(".claude", "skills"), target: () => path.join("..", "missing-skills") },
  { name: ".agents/skills-profile.json links to a file inside the project", agent: "codex", link: path.join(".agents", "skills-profile.json"), target: () => path.join("..", "shared-profile.json") },
  {
    name: ".claude links to a dangling link that points outside",
    agent: "claude-code",
    link: ".claude",
    target: () => "chained",
    prepare: async fixture => symlink(path.join(fixture.root, "missing-outside"), path.join(fixture.project, "chained")),
  },
];

for (const { name, agent, link, target, prepare } of projectLinkCases) {
  test(`project scope refuses to change anything when ${name}`, posixOnly, async () => {
    const fixture = await createFixture({ npxBody: stagingNpxBody });
    try {
      const outside = path.join(fixture.root, "outside");
      await mkdir(path.join(outside, "skills", "precious"), { recursive: true });
      await writeFile(path.join(outside, "skills", "precious", "SKILL.md"), "precious\n");
      await writeFile(path.join(outside, "skills-lock.json"), "outside lock\n");
      await writeFile(path.join(outside, "skills-profile.json"), "outside profile\n");
      await mkdir(path.join(fixture.project, "shared-skills", "kept"), { recursive: true });
      await writeFile(path.join(fixture.project, "shared-profile.json"), "shared profile\n");
      await prepare?.(fixture);
      const linkPath = path.join(fixture.project, link);
      const linkText = target(fixture.root);
      await mkdir(path.dirname(linkPath), { recursive: true });
      await symlink(linkText, linkPath);
      const projectBefore = (await readdir(fixture.project)).sort();
      const linkDirBefore = (await readdir(path.dirname(linkPath))).sort();

      for (const dryRun of [true, false]) {
        const env = dryRun ? { ...fixture.env, SETUP_DRY_RUN: "1" } : fixture.env;
        const result = runSkills(["--scope", "project", "--profile", "base", "--agent", agent], { ...fixture, env }, { cwd: fixture.project });

        assert.notEqual(result.status, 0, result.stdout);
        assert.match(result.stderr, new RegExp(`refusing to set up project skills: ${escapeRegExp(linkPath)} is a symbolic link`));
        assert.doesNotMatch(result.stdout, /DRY-RUN/);
      }
      assert.equal(existsSync(`${fixture.log}.cwd`), false);
      assert.deepEqual((await readdir(fixture.project)).sort(), projectBefore);
      assert.deepEqual((await readdir(path.dirname(linkPath))).sort(), linkDirBefore);
      assert.equal(await readlink(linkPath), linkText);
      assert.deepEqual(await readdir(path.join(fixture.project, "shared-skills")), ["kept"]);
      assert.equal(await readText(path.join(fixture.project, "shared-profile.json")), "shared profile\n");
      assert.deepEqual((await readdir(outside)).sort(), ["skills", "skills-lock.json", "skills-profile.json"]);
      assert.deepEqual(await readdir(path.join(outside, "skills")), ["precious"]);
      assert.equal(await readText(path.join(outside, "skills-lock.json")), "outside lock\n");
      assert.equal(await readText(path.join(outside, "skills-profile.json")), "outside profile\n");
      assert.equal(existsSync(path.join(privateSkillsBase(fixture), "dotfiles-skills-backup")), false);
    } finally {
      await fixture.cleanup();
    }
  });
}

async function listTree(root) {
  const entries = [];
  for (const entry of await readdir(root, { recursive: true })) {
    entries.push(entry);
  }
  return entries;
}

// Moved into <base>/dotfiles-skills-backup/<project>/, a `..` link resolves to
// the backup directory itself, so restoring unmanaged entries through it would
// copy every project's backups into this checkout.
test("project scope does not copy other projects' backups through an .agents/skills link to ..", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  try {
    const otherBackup = path.join(privateSkillsBase(fixture), "dotfiles-skills-backup", "other-project", ".agents-skills.20260101000000.1", "victim-secret");
    await mkdir(otherBackup, { recursive: true });
    await writeFile(path.join(otherBackup, "SKILL.md"), "other project's backup\n");
    await mkdir(path.join(fixture.project, ".agents"));
    await symlink("..", path.join(fixture.project, ".agents", "skills"));

    const result = runProjectInstall(fixture);

    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /refusing to set up project skills: .*\.agents.skills is a symbolic link/);
    const leaked = (await listTree(fixture.project)).filter(entry => entry.includes("victim-secret") || entry.includes("other-project"));
    assert.deepEqual(leaked, []);
    assert.equal(await readlink(path.join(fixture.project, ".agents", "skills")), "..");
    assert.deepEqual(await readdir(path.join(privateSkillsBase(fixture), "dotfiles-skills-backup")), ["other-project"]);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope without external skills names backups when the private base is refused", posixOnly, async () => {
  const fixture = await createFixture({ npxBody: stagingNpxBody });
  delete fixture.env.TMPDIR;
  try {
    await writeFile(
      path.join(fixture.dotfiles, "skills", "profiles", "local-only.json"),
      JSON.stringify({ description: "Local only", external: [], local: ["local-one"] }, null, 2) + "\n",
    );
    const launcher = `
const runtime = process.argv[1];
Object.defineProperty(process, "platform", { value: "darwin" });
process.argv = [process.execPath, runtime, ...process.argv.slice(2)];
require(runtime);
`;
    const result = spawnSync(
      process.execPath,
      ["-e", launcher, skillsRuntime, "--scope", "project", "--profile", "local-only", "--agent", "codex"],
      { cwd: fixture.project, env: fixture.env, encoding: "utf8" },
    );

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cannot keep project skill backups under .* must be owned by you or root and not writable by others/);
    assert.doesNotMatch(result.stderr, /staging/);
    assert.deepEqual(await readdir(fixture.project), [".git"]);
  } finally {
    await fixture.cleanup();
  }
});

// Each source's install also emits an undeclared "shared-helper" entry, in the
// form given for that source, so two installs collide in the user staging view.
const helperEntryForms = {
  "dir-with-links": 'mkdir -p "$1" && printf helper > "$1/SKILL.md" && ln -s SKILL.md "$1/link"',
  dir: 'mkdir -p "$1" && printf "%s" "${source_name}" > "$1/${source_name%%/*}.txt"',
  file: 'printf "%s" "${source_name}" > "$1"',
  link: 'ln -s missing-target "$1"',
};

const collisionCases = [
  ["a directory with links onto a directory with links", "dir-with-links", "dir-with-links"],
  ["a link onto a non-link", "dir", "link"],
  ["a directory onto a directory", "dir", "dir"],
  ["a file onto a file", "file", "file"],
  ["a non-link onto a link", "link", "dir"],
];

for (const [label, first, second] of collisionCases) {
  test(`user scope fails on a same-name entry collision of ${label} and keeps the user view`, posixOnly, async () => {
    const fixture = await createFixture({
      npxSuffix: `emit_helper() {
  case "\${source_name}" in
    anthropics/skills) ${helperEntryForms[first]} ;;
    vercel-labs/skills) ${helperEntryForms[second]} ;;
  esac
}
emit_helper .agents/skills/shared-helper
`,
    });
    try {
      const userRoot = path.join(fixture.dotfiles, ".agents", "user");
      await mkdir(path.join(userRoot, "skills", "old-user"), { recursive: true });
      await writeFile(path.join(userRoot, "skills", "old-user", "SKILL.md"), "old-user\n");
      await writeFile(path.join(userRoot, "skills-profile.json"), "old-profile\n");

      const result = runSkills(["--scope", "user", "--profile", "office", "--agent", "codex"], fixture);

      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /skill entry collision in user staging: shared-helper \(anthropics\/skills, vercel-labs\/skills\)/);
      assert.doesNotMatch(result.stderr, /EEXIST|ERR_FS_CP_/);
      assert.deepEqual((await readdir(userRoot)).sort(), ["skills", "skills-profile.json"]);
      assert.deepEqual(await readdir(path.join(userRoot, "skills")), ["old-user"]);
      assert.equal(await readText(path.join(userRoot, "skills", "old-user", "SKILL.md")), "old-user\n");
      assert.equal(await readText(path.join(userRoot, "skills-profile.json")), "old-profile\n");
    } finally {
      await fixture.cleanup();
    }
  });
}

const reservedNameCases = [
  ["an external skill named synced", { source: "acme/skills", skills: ["synced"] }, null, "synced"],
  ["an external skill named Anthropic-Skills", { source: "acme/skills", skills: ["Anthropic-Skills"] }, null, "Anthropic-Skills"],
  ["a local skill named SYNCED", null, "SYNCED", "SYNCED"],
];

for (const [label, external, local, name] of reservedNameCases) {
  for (const args of [
    ["profile", "validate", "--profile", "reserved"],
    ["--scope", "user", "--profile", "reserved", "--agent", "codex"],
    ["--scope", "project", "--profile", "reserved", "--agent", "codex"],
  ]) {
    test(`${args.slice(0, 2).join(" ")} rejects ${label}`, async () => {
      const fixture = await createFixture();
      try {
        if (local) {
          await mkdir(path.join(fixture.dotfiles, "skills", "local", local), { recursive: true });
          await writeFile(path.join(fixture.dotfiles, "skills", "local", local, "SKILL.md"), "reserved\n");
        }
        await writeFile(
          path.join(fixture.dotfiles, "skills", "profiles", "reserved.json"),
          JSON.stringify({ description: "Reserved name profile", external: external ? [external] : [], local: local ? [local] : [] }) + "\n",
        );

        const result = runSkills(args, fixture, { cwd: fixture.project });

        assert.notEqual(result.status, 0);
        assert.match(result.stderr, new RegExp(`Invalid or reserved skill name: ${name}`));
        assert.equal(existsSync(fixture.log), false);
        assert.deepEqual(await readdir(fixture.project), [".git"]);
        assert.equal(existsSync(path.join(fixture.dotfiles, ".agents")), false);
      } finally {
        await fixture.cleanup();
      }
    });
  }
}

// An install emits an undeclared top-level synced entry in the given form.
const syncedEntryForms = {
  directory: 'mkdir -p .agents/skills/synced && printf ext > .agents/skills/synced/SKILL.md',
  file: "printf ext > .agents/skills/synced",
  "link to a directory outside staging": 'ln -s "${TEST_OUTSIDE_DIR}" .agents/skills/synced',
};

for (const [form, emit] of Object.entries(syncedEntryForms)) {
  test(`user scope fails when an install emits synced as a ${form} and keeps the user view`, posixOnly, async () => {
    const fixture = await createFixture({
      npxSuffix: `if [ "\${source_name}" = anthropics/skills ]; then ${emit}; fi\n`,
    });
    try {
      const outside = path.join(fixture.root, "outside");
      await mkdir(outside);
      fixture.env.TEST_OUTSIDE_DIR = outside;
      const userRoot = path.join(fixture.dotfiles, ".agents", "user");
      const synced = path.join(userRoot, "skills", "synced", "account");
      await mkdir(synced, { recursive: true });
      await writeFile(path.join(synced, "SKILL.md"), "synchronized content\n");
      await writeFile(path.join(userRoot, "skills-profile.json"), "old-profile\n");

      const result = runSkills(["--scope", "user", "--profile", "office", "--agent", "codex"], fixture);

      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /skill entry collision in user staging: synced \(anthropics\/skills, reserved name\)/);
      assert.doesNotMatch(result.stderr, /EEXIST|ERR_FS_CP_/);
      assert.deepEqual(await readdir(outside), []);
      assert.deepEqual((await readdir(userRoot)).sort(), ["skills", "skills-profile.json"]);
      assert.deepEqual(await readdir(path.join(userRoot, "skills")), ["synced"]);
      assert.equal(await readText(path.join(synced, "SKILL.md")), "synchronized content\n");
      assert.equal(await readText(path.join(userRoot, "skills-profile.json")), "old-profile\n");
    } finally {
      await fixture.cleanup();
    }
  });
}

// An install emits an undeclared top-level entry with a reserved name in a
// letter case other than synced.
for (const name of ["anthropic-skills", "Anthropic-Skills", "SYNCED"]) {
  const reservedSuffix = `if [ "\${source_name}" = anthropics/skills ]; then
  for dir in .agents/skills .claude/skills; do
    mkdir -p "\${dir}/${name}" && printf ext > "\${dir}/${name}/SKILL.md"
  done
fi
`;

  test(`user scope fails when an install emits ${name} and keeps the user view`, posixOnly, async () => {
    const fixture = await createFixture({ npxSuffix: reservedSuffix });
    try {
      const userRoot = path.join(fixture.dotfiles, ".agents", "user");
      await mkdir(path.join(userRoot, "skills", "old-user"), { recursive: true });
      await writeFile(path.join(userRoot, "skills-profile.json"), "old-profile\n");

      const result = runSkills(["--scope", "user", "--profile", "office", "--agent", "codex"], fixture);

      assert.notEqual(result.status, 0);
      assert.match(result.stderr, new RegExp(`skill entry collision in user staging: ${name} \\(anthropics/skills, reserved name\\)`));
      assert.deepEqual((await readdir(userRoot)).sort(), ["skills", "skills-profile.json"]);
      assert.deepEqual(await readdir(path.join(userRoot, "skills")), ["old-user"]);
      assert.equal(await readText(path.join(userRoot, "skills-profile.json")), "old-profile\n");
    } finally {
      await fixture.cleanup();
    }
  });

  test(`project scope fails when an install emits ${name} and restores the project`, posixOnly, async () => {
    const fixture = await createFixture({ npxSuffix: reservedSuffix });
    try {
      const previous = path.join(fixture.project, ".claude", "skills", "previous");
      await mkdir(previous, { recursive: true });
      await writeFile(path.join(previous, "SKILL.md"), "previous skill\n");
      await writeFile(path.join(fixture.project, "skills-lock.json"), "previous lock\n");

      const result = runSkills(
        ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
        fixture,
        { cwd: fixture.project },
      );

      assert.notEqual(result.status, 0);
      assert.match(result.stderr, new RegExp(`skill entry collision in project install: ${name} \\(anthropics/skills, reserved name\\)`));
      assert.deepEqual(await readdir(path.join(fixture.project, ".claude", "skills")), ["previous"]);
      assert.equal(await readText(path.join(previous, "SKILL.md")), "previous skill\n");
      assert.equal(await readText(path.join(fixture.project, "skills-lock.json")), "previous lock\n");
      assert.equal(existsSync(path.join(fixture.project, ".agents", "skills")), false);
    } finally {
      await fixture.cleanup();
    }
  });
}

// An install emits an undeclared entry named like the local skill local-one.
const localNameSuffix = `if [ "\${source_name}" = anthropics/skills ]; then
  for dir in .agents/skills .claude/skills; do
    mkdir -p "\${dir}/local-one" && printf ext > "\${dir}/local-one/SKILL.md"
  done
fi
`;

test("user scope fails when an install emits a local skill name and keeps the user view", posixOnly, async () => {
  const fixture = await createFixture({ npxSuffix: localNameSuffix });
  try {
    const userRoot = path.join(fixture.dotfiles, ".agents", "user");
    await mkdir(path.join(userRoot, "skills", "old-user"), { recursive: true });

    const result = runSkills(["--scope", "user", "--profile", "office", "--agent", "codex"], fixture);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skill entry collision in user staging: local-one \(anthropics\/skills, local\)/);
    assert.deepEqual(await readdir(userRoot), ["skills"]);
    assert.deepEqual(await readdir(path.join(userRoot, "skills")), ["old-user"]);
  } finally {
    await fixture.cleanup();
  }
});

test("project scope fails when an install emits a local skill name and restores the project", posixOnly, async () => {
  const fixture = await createFixture({ npxSuffix: localNameSuffix });
  try {
    const previous = path.join(fixture.project, ".claude", "skills", "previous");
    await mkdir(previous, { recursive: true });
    await writeFile(path.join(previous, "SKILL.md"), "previous skill\n");
    await writeFile(path.join(fixture.project, "skills-lock.json"), "previous lock\n");

    const result = runSkills(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /skill entry collision in project install: local-one \(anthropics\/skills, local\)/);
    assert.deepEqual(await readdir(path.join(fixture.project, ".claude", "skills")), ["previous"]);
    assert.equal(await readText(path.join(previous, "SKILL.md")), "previous skill\n");
    assert.equal(await readText(path.join(fixture.project, "skills-lock.json")), "previous lock\n");
    assert.equal(existsSync(path.join(fixture.project, ".agents", "skills")), false);
  } finally {
    await fixture.cleanup();
  }
});

// Like the skills CLI in copy mode, each install removes a same-name skill and
// copies it again, here with the same content from both sources.
const replaceForms = {
  "different content": 'printf "%s" "${source_name}"',
  "the same content": "printf helper",
};

for (const [label, content] of Object.entries(replaceForms)) {
  test(`project scope fails when a later install replaces an entry with ${label} and restores the project`, posixOnly, async () => {
    const fixture = await createFixture({
      npxSuffix: `for dir in .agents/skills .claude/skills; do
  rm -rf "\${dir}/shared-helper"
  mkdir -p "\${dir}/shared-helper" && ${content} > "\${dir}/shared-helper/SKILL.md"
done
`,
    });
    try {
      const previous = path.join(fixture.project, ".agents", "skills", "previous");
      await mkdir(previous, { recursive: true });
      await writeFile(path.join(previous, "SKILL.md"), "previous skill\n");

      const result = runSkills(
        ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
        fixture,
        { cwd: fixture.project },
      );

      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /skill entry collision in project install: shared-helper \(anthropics\/skills, vercel-labs\/skills\)/);
      assert.deepEqual(await readdir(path.join(fixture.project, ".agents", "skills")), ["previous"]);
      assert.equal(existsSync(path.join(fixture.project, ".claude", "skills")), false);
      assert.equal(existsSync(path.join(fixture.project, "skills-lock.json")), false);
    } finally {
      await fixture.cleanup();
    }
  });
}

test("project scope keeps entries a later install leaves untouched", posixOnly, async () => {
  const fixture = await createFixture();
  try {
    const result = runSkills(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.deepEqual((await readdir(path.join(fixture.project, ".agents", "skills"))).sort(), ["docx", "find-skills", "local-one", "pdf"]);
  } finally {
    await fixture.cleanup();
  }
});
