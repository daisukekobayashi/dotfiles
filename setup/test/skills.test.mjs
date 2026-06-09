import assert from "node:assert/strict";
import { lstat, mkdtemp, mkdir, readFile, readlink, rm, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const repoRoot = path.resolve(import.meta.dirname, "..", "..");
const skillsRuntime = path.join(repoRoot, "setup", "skills.js");
const githubLocalSkills = [
  "github-issue-create",
  "github-issue-review",
  "github-issue-triage",
  "github-issue-worktree",
  "github-merge-cleanup",
  "github-pr",
  "github-pr-ai-review-followup",
  "github-pr-ai-review-request",
  "github-pr-codex-review-request",
  "github-pr-copilot-review-request",
  "github-pr-publish",
  "github-pr-publish-and-ai-review-request",
  "github-pr-review",
];
const azureDevOpsLocalSkills = [
  "azure-devops-common",
  "azure-devops-work-item-create",
  "azure-devops-work-item-review",
  "azure-devops-work-item-triage",
  "azure-devops-work-item-worktree",
  "azure-devops-pr",
  "azure-devops-pr-publish",
  "azure-devops-pr-review",
  "azure-devops-merge-cleanup",
];

async function writeExecutable(filePath, content) {
  await writeFile(filePath, content, { mode: 0o755 });
}

async function createFixture(options = {}) {
  const root = await mkdtemp(path.join(os.tmpdir(), "skills-node-test."));
  const home = path.join(root, "home");
  const tmp = path.join(root, "tmp");
  const dotfiles = path.join(root, "dotfiles");
  const bin = path.join(root, "bin");
  const project = path.join(root, "project");
  const log = path.join(root, "skills.log");

  await mkdir(home, { recursive: true });
  await mkdir(tmp, { recursive: true });
  await mkdir(bin, { recursive: true });
  await mkdir(project, { recursive: true });
  await mkdir(path.join(dotfiles, "skills", "local", "local-one"), { recursive: true });
  await mkdir(path.join(dotfiles, "skills", "profiles"), { recursive: true });

  await writeFile(
    path.join(dotfiles, "skills", "local", "local-one", "SKILL.md"),
    "---\nname: local-one\ndescription: Test local skill\n---\n\nLocal skill.\n",
  );
  await writeFile(
    path.join(dotfiles, "skills", "profiles", "base.json"),
    JSON.stringify(
      {
        description: "Base test profile",
        external: [{ source: "vercel-labs/skills", skills: ["find-skills"] }],
        local: ["local-one"],
      },
      null,
      2,
    ) + "\n",
  );
  await writeFile(
    path.join(dotfiles, "skills", "profiles", "office.json"),
    JSON.stringify(
      {
        description: "Office test profile",
        includes: ["base"],
        external: [{ source: "anthropics/skills", skills: ["docx", "pdf"] }],
        local: [],
      },
      null,
      2,
    ) + "\n",
  );

  const npxBody =
    options.npxBody ??
    `#!/usr/bin/env bash
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
mkdir -p .agents/skills .claude/skills
printf '{"version":3,"source":"%s"}\\n' "\${source_name}" > skills-lock.json
for skill_name in "\${skills[@]}"; do
  if [ "\${#agents[@]}" -eq 0 ]; then
    agents=(codex)
  fi
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
`;
  await writeExecutable(path.join(bin, options.npxName ?? "npx"), npxBody);

  if (options.withWindowsWhere) {
    await writeExecutable(
      path.join(bin, "where"),
      `#!/bin/bash
set -euo pipefail
command_name="$1"
found=0
IFS=':' read -ra path_entries <<< "\${PATH}"
for path_entry in "\${path_entries[@]}"; do
  if [ -x "\${path_entry}/\${command_name}" ]; then
    printf '%s\\n' "\${path_entry}/\${command_name}"
    found=1
  fi
  if [ -x "\${path_entry}/\${command_name}.exe" ]; then
    printf '%s\\n' "\${path_entry}/\${command_name}.exe"
    found=1
  fi
  if [ -x "\${path_entry}/\${command_name}.cmd" ]; then
    printf '%s\\n' "\${path_entry}/\${command_name}.cmd"
    found=1
  fi
done
exit $((found == 0))
`,
    );
    await writeExecutable(
      path.join(bin, "cmd.exe"),
      `#!/bin/bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in
    /d|/D|/s|/S)
      shift
      ;;
    /c|/C)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done
if [ "$#" -eq 0 ]; then
  exit 0
fi
command_line="$*"
if [[ "\${command_line}" == \\"*\\" ]]; then
  command_line="\${command_line:1:\${#command_line}-2}"
fi
eval "exec \${command_line}"
`,
    );
  }

  spawnSync("git", ["init", "-q"], { cwd: project });

  const env = {
    ...process.env,
    HOME: home,
    SETUP_HOME: home,
    SETUP_TMPDIR: tmp,
    SETUP_DOTFILES_ROOT: dotfiles,
    PATH: options.isolatedPath ? bin : `${bin}${path.delimiter}${process.env.PATH}`,
    TEST_SKILLS_LOG: log,
  };

  return {
    root,
    home,
    tmp,
    dotfiles,
    bin,
    project,
    log,
    env,
    cleanup: () => rm(root, { recursive: true, force: true }),
  };
}

function runSkills(args, fixture, options = {}) {
  return spawnSync(process.execPath, [skillsRuntime, ...args], {
    cwd: options.cwd ?? repoRoot,
    env: fixture.env,
    encoding: "utf8",
  });
}

function runSkillsWithSymlinkError(args, fixture, options = {}) {
  const launcher = `
const fs = require("node:fs");
fs.symlinkSync = () => {
  const error = new Error("EPERM: operation not permitted, symlink");
  error.code = "EPERM";
  throw error;
};
const runtime = process.argv[1];
const args = process.argv.slice(2);
process.argv = [process.execPath, runtime, ...args];
require(runtime);
`;
  return spawnSync(process.execPath, ["-e", launcher, skillsRuntime, ...args], {
    cwd: options.cwd ?? repoRoot,
    env: fixture.env,
    encoding: "utf8",
  });
}

function runSkillsAsWindows(args, fixture, options = {}) {
  const launcher = `
const runtime = process.argv[1];
const args = process.argv.slice(2);
Object.defineProperty(process, "platform", { value: "win32" });
process.argv = [process.execPath, runtime, ...args];
require(runtime);
`;
  return spawnSync(process.execPath, ["-e", launcher, skillsRuntime, ...args], {
    cwd: options.cwd ?? repoRoot,
    env: fixture.env,
    encoding: "utf8",
  });
}

async function readText(filePath) {
  return readFile(filePath, "utf8");
}

async function readRepoProfile(name) {
  return JSON.parse(await readText(path.join(repoRoot, "skills", "profiles", `${name}.json`)));
}

function skillsForSource(profile, source) {
  return profile.external.find((entry) => entry.source === source)?.skills ?? [];
}

test("repository profiles keep provider workflow skills separated", async () => {
  for (const profileName of ["base", "github", "azure", "azure-devops"]) {
    assert.equal(existsSync(path.join(repoRoot, "skills", "profiles", `${profileName}.json`)), true);
  }

  const base = await readRepoProfile("base");
  const github = await readRepoProfile("github");
  const azure = await readRepoProfile("azure");
  const azureDevOps = await readRepoProfile("azure-devops");

  assert.equal(base.description, "Provider-neutral baseline workflow skills for repository work.");
  assert.deepEqual(skillsForSource(base, "github/awesome-copilot"), ["git-commit"]);
  for (const skillName of githubLocalSkills) {
    assert.equal(base.local.includes(skillName), false, `${skillName} should not be in base`);
  }

  assert.deepEqual(skillsForSource(github, "github/awesome-copilot"), ["gh-cli"]);
  assert.deepEqual(github.local, githubLocalSkills);

  assert.deepEqual(skillsForSource(azure, "github/awesome-copilot"), []);
  assert.deepEqual(skillsForSource(azureDevOps, "github/awesome-copilot"), ["azure-devops-cli"]);
  assert.deepEqual(azureDevOps.local, azureDevOpsLocalSkills);

  for (const skillName of azureDevOpsLocalSkills) {
    assert.equal(existsSync(path.join(repoRoot, "skills", "local", skillName, "SKILL.md")), true);
  }

  const result = spawnSync(
    process.execPath,
    [skillsRuntime, "profile", "validate", "--profile", "base,github,azure,azure-devops"],
    {
      cwd: repoRoot,
      env: {
        ...process.env,
        SETUP_DOTFILES_ROOT: repoRoot,
      },
      encoding: "utf8",
    },
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
});

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

test("Windows user scope runs npx.cmd when npx resolves through PATHEXT", async () => {
  const fixture = await createFixture({
    npxName: "npx.cmd",
    npxBody: `#!/bin/bash
set -euo pipefail
PATH="/bin:\${PATH}"
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
mkdir -p .agents/skills
printf '{"version":3,"source":"%s"}\\n' "$3" > skills-lock.json
mkdir -p .agents/skills/find-skills
printf '%s\\n' "find-skills" > .agents/skills/find-skills/SKILL.md
`,
    isolatedPath: true,
    withWindowsWhere: true,
  });
  try {
    const result = runSkillsAsWindows(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(await readText(fixture.log), /skills add vercel-labs\/skills/);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows user scope prefers executable npx shim over extensionless npx", async () => {
  const fixture = await createFixture({
    npxName: "npx",
    npxBody: `#!/bin/bash
printf 'extensionless npx should not run\\n' >&2
exit 99
`,
    isolatedPath: true,
    withWindowsWhere: true,
  });
  try {
    await writeExecutable(
      path.join(fixture.bin, "npx.exe"),
      `#!/bin/bash
set -euo pipefail
PATH="/bin:\${PATH}"
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
mkdir -p .agents/skills
printf '{"version":3,"source":"%s"}\\n' "$3" > skills-lock.json
mkdir -p .agents/skills/find-skills
printf '%s\\n' "find-skills" > .agents/skills/find-skills/SKILL.md
`,
    );

    const result = runSkillsAsWindows(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(await readText(fixture.log), /skills add vercel-labs\/skills/);
  } finally {
    await fixture.cleanup();
  }
});

test("dry-run user scope does not write managed skill outputs", async () => {
  const fixture = await createFixture();
  try {
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
