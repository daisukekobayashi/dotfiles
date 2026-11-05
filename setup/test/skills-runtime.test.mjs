import assert from "node:assert/strict";
import { lstat, mkdir, readdir, readlink, symlink, writeFile } from "node:fs/promises";
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
