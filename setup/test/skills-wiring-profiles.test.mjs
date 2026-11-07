import assert from "node:assert/strict";
import { cp, mkdtemp, mkdir, readdir, rm } from "node:fs/promises";
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
  "shared-understanding",
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

test("the shared safe branch name check resolves and runs in copied base and provider profiles", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "branch-check-profile-test."));
  const link = "../delivery-common/scripts/check-branch-name.mjs";
  try {
    const base = await readRepoProfile("base");
    for (const provider of ["github", "azure-devops", "beads"]) {
      const profile = await readRepoProfile(provider);
      const skillsDir = path.join(root, provider, "skills");
      await mkdir(skillsDir, { recursive: true });
      for (const name of new Set([...base.local, ...profile.local])) {
        await cp(path.join(repoRoot, "skills", "local", name), path.join(skillsDir, name), {
          recursive: true,
        });
      }

      const callers = [];
      for (const name of profile.local) {
        const content = await readText(path.join(skillsDir, name, "SKILL.md"));
        if (!content.includes(`](${link})`)) continue;
        callers.push(name);
        const script = path.resolve(skillsDir, name, link);
        assert.equal(existsSync(script), true, `${provider}/${name}: missing ${link}`);
        const safe = spawnSync(process.execPath, [script, "--", "main", "feat/1-x"], { encoding: "utf8" });
        assert.equal(safe.status, 0, `${provider}/${name}: ${safe.stderr}`);
        const unsafe = spawnSync(process.execPath, [script, "--", "main", "-x"], { encoding: "utf8" });
        assert.equal(unsafe.status, 3, `${provider}/${name}: leading - accepted`);
        assert.equal(unsafe.stderr, 'unsafe branch name: "-x"\n');
      }
      assert.notEqual(callers.length, 0, `${provider}: no skill runs the shared check`);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("every shared delivery-common script link resolves and runs in copied base and provider profiles", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "shared-script-profile-test."));
  const linkPattern = /\]\(((?:\.\.\/)+delivery-common\/scripts\/[A-Za-z0-9-]+\.mjs)\)/g;
  try {
    const base = await readRepoProfile("base");
    const linked = new Set();
    for (const provider of ["github", "azure-devops", "beads"]) {
      const profile = await readRepoProfile(provider);
      const skillsDir = path.join(root, provider, "skills");
      await mkdir(skillsDir, { recursive: true });
      const installed = [...new Set([...base.local, ...profile.local])];
      for (const name of installed) {
        await cp(path.join(repoRoot, "skills", "local", name), path.join(skillsDir, name), {
          recursive: true,
        });
      }

      for (const name of installed) {
        const docs = [path.join(skillsDir, name, "SKILL.md")];
        const references = path.join(skillsDir, name, "references");
        if (existsSync(references)) {
          for (const entry of await readdir(references)) {
            if (entry.endsWith(".md")) docs.push(path.join(references, entry));
          }
        }
        for (const doc of docs) {
          if (!existsSync(doc)) continue;
          for (const [, link] of (await readText(doc)).matchAll(linkPattern)) {
            const script = path.resolve(path.dirname(doc), link);
            assert.equal(existsSync(script), true, `${provider}/${path.relative(skillsDir, doc)}: missing ${link}`);
            const usage = spawnSync(process.execPath, [script], { encoding: "utf8" });
            assert.equal(usage.status, 2, `${provider}/${path.relative(skillsDir, doc)}: ${link} did not run`);
            linked.add(path.basename(script));
          }
        }
      }
    }
    assert.ok(linked.has("check-push-target.mjs"), "no skill links the shared push target check");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
