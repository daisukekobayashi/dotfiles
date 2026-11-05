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
    const backupRoot = path.join(fixture.env.SETUP_TMPDIR, "dotfiles-skills-backup", path.basename(fixture.project));
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
    await mkdir(path.dirname(claudeSkills), { recursive: true });
    await symlink("missing-skill", path.join(codexSkills, "alias"));
    await symlink("../missing-skills", claudeSkills);

    const result = runSkillsWithCrossDeviceBackupRenameError(
      ["--scope", "project", "--profile", "office", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stderr, /ENOENT|EXDEV/);
    assert.match(await readText(fixture.log), /skills add anthropics\/skills/);
    assert.equal(await readlink(path.join(codexSkills, "alias")), "missing-skill");
    assert.equal(await readlink(claudeSkills), "../missing-skills");
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

    // A group-writable ancestor is allowed, as with umask 002 and user-private groups.
    await chmod(shared, 0o775);
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
