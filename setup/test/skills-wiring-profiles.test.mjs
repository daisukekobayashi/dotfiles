import assert from "node:assert/strict";
import { cp, mkdtemp, mkdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import {
  repoRoot,
  skillsRuntime,
  readText,
  readRepoProfile,
  skillsForSource,
} from "./skills-helpers.mjs";

const githubLocalSkills = [
  "github-issue-create",
  "github-issue-review",
  "github-issue-triage",
  "github-issue-start",
  "github-issue-delivery",
  "github-worktree-cleanup",
  "github-pr-create",
  "github-pr-ai-review-followup",
  "github-pr-review-request",
  "github-pr-codex-review-cycle",
  "github-pr-publish",
  "github-pr-publish-and-ai-review-request",
  "github-pr-review",
];
const azureDevOpsLocalSkills = [
  "azure-devops-common",
  "azure-devops-work-item-create",
  "azure-devops-work-item-review",
  "azure-devops-work-item-triage",
  "azure-devops-work-item-start",
  "azure-devops-work-item-delivery",
  "azure-devops-pr-create",
  "azure-devops-pr-publish",
  "azure-devops-pr-review",
  "azure-devops-worktree-cleanup",
];
const baseLocalSkills = [
  "change-adversarial-review",
  "change-review",
  "change-security-review",
  "delivery-common",
  "design-preflight",
  "design-preflight-with-docs",
  "repo-execution-context",
  "find-unknowns",
  "issue-understanding-check",
  "learning-partner",
  "local-runtime-port-isolation",
  "worktree-runtime-cleanup",
  "writing-partner",
];
const beadsLocalSkills = [
  "beads-issue-create",
  "beads-issue-triage",
  "beads-issue-worktree",
  "beads-merge-cleanup",
];

test("repository profiles keep provider workflow skills separated", async () => {
  for (const profileName of ["base", "github", "azure", "azure-devops", "beads"]) {
    assert.equal(existsSync(path.join(repoRoot, "skills", "profiles", `${profileName}.json`)), true);
  }

  const base = await readRepoProfile("base");
  const github = await readRepoProfile("github");
  const azure = await readRepoProfile("azure");
  const azureDevOps = await readRepoProfile("azure-devops");
  const beads = await readRepoProfile("beads");

  assert.equal(base.description, "Provider-neutral baseline workflow skills for repository work.");
  assert.deepEqual(skillsForSource(base, "obra/superpowers"), []);
  assert.deepEqual(skillsForSource(base, "github/awesome-copilot"), ["git-commit"]);
  assert.deepEqual(skillsForSource(base, "mattpocock/skills"), [
    "ask-matt",
    "code-review",
    "codebase-design",
    "diagnosing-bugs",
    "domain-modeling",
    "grill-me",
    "grill-with-docs",
    "grilling",
    "handoff",
    "implement",
    "improve-codebase-architecture",
    "prototype",
    "research",
    "setup-matt-pocock-skills",
    "tdd",
    "teach",
    "to-spec",
    "to-tickets",
    "triage",
    "wayfinder",
    "writing-for-agents",
  ]);
  assert.deepEqual(base.local, baseLocalSkills);
  for (const skillName of githubLocalSkills) {
    assert.equal(base.local.includes(skillName), false, `${skillName} should not be in base`);
  }

  assert.deepEqual(skillsForSource(github, "github/awesome-copilot"), []);
  assert.deepEqual(github.local, githubLocalSkills);

  assert.deepEqual(skillsForSource(azure, "github/awesome-copilot"), []);
  assert.deepEqual(skillsForSource(azureDevOps, "github/awesome-copilot"), ["azure-devops-cli"]);
  assert.deepEqual(azureDevOps.local, azureDevOpsLocalSkills);
  assert.deepEqual(beads.external, []);
  assert.deepEqual(beads.local, beadsLocalSkills);

  for (const skillName of azureDevOpsLocalSkills) {
    assert.equal(existsSync(path.join(repoRoot, "skills", "local", skillName, "SKILL.md")), true);
  }
  for (const skillName of baseLocalSkills) {
    assert.equal(existsSync(path.join(repoRoot, "skills", "local", skillName, "SKILL.md")), true);
  }
  for (const skillName of beadsLocalSkills) {
    assert.equal(existsSync(path.join(repoRoot, "skills", "local", skillName, "SKILL.md")), true);
  }

  const result = spawnSync(
    process.execPath,
    [skillsRuntime, "profile", "validate", "--profile", "base,github,azure,azure-devops,beads"],
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

test("delivery references resolve in copied profiles without the other provider", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "delivery-profile-test."));
  try {
    const base = await readRepoProfile("base");
    for (const [provider, delivery] of [
      ["github", "github-issue-delivery"],
      ["azure-devops", "azure-devops-work-item-delivery"],
    ]) {
      const profile = await readRepoProfile(provider);
      const skillsDir = path.join(root, provider, "skills");
      await mkdir(skillsDir, { recursive: true });
      for (const name of new Set([...base.local, ...profile.local])) {
        await cp(path.join(repoRoot, "skills", "local", name), path.join(skillsDir, name), {
          recursive: true,
        });
      }

      const pending = [path.join(skillsDir, delivery, "SKILL.md")];
      const visited = new Set();
      while (pending.length > 0) {
        const file = pending.pop();
        if (visited.has(file)) continue;
        visited.add(file);
        const content = await readText(file);
        for (const [, target] of content.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
          if (/^[a-z][a-z\d+.-]*:/i.test(target)) continue;
          const relative = target.split("#")[0];
          if (!relative) continue;
          const resolved = path.resolve(path.dirname(file), relative);
          assert.equal(resolved.startsWith(skillsDir + path.sep), true, `${file}: ${target}`);
          assert.equal(existsSync(resolved), true, `${file}: missing copied reference ${target}`);
          if (resolved.endsWith(".md")) pending.push(resolved);
        }
      }
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
