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
  "triage-common",
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
  "triage-common",
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
];
const beadsLocalSkills = [
  "beads-issue-create",
  "beads-issue-triage",
  "triage-common",
  "beads-issue-worktree",
  "beads-merge-cleanup",
];

test("repository profiles keep provider workflow skills separated", async () => {
  for (const profileName of ["base", "github", "azure", "azure-devops", "beads", "docs"]) {
    assert.equal(existsSync(path.join(repoRoot, "skills", "profiles", `${profileName}.json`)), true);
  }

  const base = await readRepoProfile("base");
  const github = await readRepoProfile("github");
  const azure = await readRepoProfile("azure");
  const azureDevOps = await readRepoProfile("azure-devops");
  const beads = await readRepoProfile("beads");
  const docs = await readRepoProfile("docs");

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
  for (const skillName of ["code-review-expert", "find-skills", "web-design-guidelines", "writing-partner"]) {
    assert.equal(base.external.some((entry) => entry.skills.includes(skillName)) || base.local.includes(skillName), false, `${skillName} should not be in base`);
  }
  assert.deepEqual(docs.external, []);
  assert.deepEqual(docs.local, ["writing-partner"]);
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
            if (path.basename(script) === "check-cleanup-targets.mjs") {
              // The cleanup target check runs the push target check and the
              // read-only runtime listings from the same installed tree.
              for (const dependency of [
                "check-push-target.mjs",
                "../../worktree-runtime-cleanup/scripts/list-processes.sh",
                "../../worktree-runtime-cleanup/scripts/list-stacks.sh",
              ]) {
                assert.equal(existsSync(path.resolve(path.dirname(script), dependency)), true, `${provider}: ${link} needs ${dependency}`);
              }
            }
          }
        }
      }
    }
    assert.ok(linked.has("check-push-target.mjs"), "no skill links the shared push target check");
    assert.ok(linked.has("check-cleanup-targets.mjs"), "no skill links the shared cleanup target check");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

const triageSkills = [
  ["github", "github-issue-triage"],
  ["azure-devops", "azure-devops-work-item-triage"],
  ["beads", "beads-issue-triage"],
];
const lensesLink = "../triage-common/references/lenses.md";

function markdownAnchors(content) {
  return new Set(
    [...content.matchAll(/^#{1,6} (.+)$/gm)].map(([, heading]) =>
      heading.trim().toLowerCase().replace(/[^a-z0-9 -]/g, "").replace(/ /g, "-"),
    ),
  );
}

// Read-only skills (no push, no PR) must work from their provider profile
// alone. Follow every Markdown link and every backtick `../<skill>/...`
// reference: each target must exist, with its anchor. Recurse into the
// starting skill's own files and other skills' references, but only check that
// another workflow skill's SKILL.md exists: that link names where a rule
// lives, not something the read-only skill reads.
const readOnlySkills = [
  ["github", ["github-issue-triage", "github-issue-create", "github-issue-review"]],
  ["azure-devops", ["azure-devops-work-item-triage", "azure-devops-work-item-create", "azure-devops-work-item-review"]],
  ["beads", ["beads-issue-triage", "beads-issue-create"]],
];

function skillReferences(content) {
  const targets = [];
  for (const [, target] of content.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    if (!/^[a-z][a-z\d+.-]*:/i.test(target)) targets.push(target);
  }
  for (const [, target] of content.matchAll(/`((?:\.\.\/)+[a-z0-9-]+\/[A-Za-z0-9._\/#-]*)`/g)) {
    targets.push(target);
  }
  return targets;
}

test("read-only skills resolve in each copied provider profile without base", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "read-only-profile-test."));
  try {
    for (const [provider, skills] of readOnlySkills) {
      const profile = await readRepoProfile(provider);
      assert.equal(profile.local.includes("triage-common"), true, `${provider}: triage-common missing`);
      const skillsDir = path.join(root, provider, "skills");
      await mkdir(skillsDir, { recursive: true });
      for (const name of profile.local) {
        await cp(path.join(repoRoot, "skills", "local", name), path.join(skillsDir, name), {
          recursive: true,
        });
      }

      for (const skill of skills) {
        assert.equal(profile.local.includes(skill), true, `${provider}: ${skill} missing`);
        const skillDir = path.join(skillsDir, skill);
        const pending = [path.join(skillDir, "SKILL.md")];
        const visited = new Set();
        while (pending.length > 0) {
          const file = pending.pop();
          if (visited.has(file)) continue;
          visited.add(file);
          const content = await readText(file);
          for (const target of skillReferences(content)) {
            const [relative, anchor] = target.split("#");
            const resolved = relative ? path.resolve(path.dirname(file), relative) : file;
            const where = `${provider}/${path.relative(skillsDir, file)}: ${target}`;
            assert.equal(resolved.startsWith(skillsDir + path.sep), true, where);
            assert.equal(existsSync(resolved), true, `${where}: missing in ${provider} alone`);
            if (!resolved.endsWith(".md")) continue;
            if (anchor) {
              assert.equal(markdownAnchors(await readText(resolved)).has(anchor), true, `${where}: missing anchor`);
            }
            const otherSkillEntry = path.basename(resolved) === "SKILL.md" && path.dirname(resolved) !== skillDir;
            if (!otherSkillEntry) pending.push(resolved);
          }
        }
        if (skill.endsWith("-triage")) {
          assert.equal(visited.has(path.join(skillsDir, "triage-common", "references", "lenses.md")), true, `${skill}: lenses not linked`);
        }
      }
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("triage skills rank through the shared lenses without restating them", async () => {
  const lenses = await readText(path.join(repoRoot, "skills", "local", "triage-common", "references", "lenses.md"));
  const valid = lenses.match(/Valid lenses: (.+), matched exactly/)[1].match(/`([a-z]+)`/g).map((name) => name.slice(1, -1));
  assert.deepEqual(valid, ["deliver", "stabilize"]);
  assert.match(lenses, /- No `lens=` argument: use `deliver`\./);
  assert.match(lenses, /`Unknown lens: <value>\. Valid lenses: deliver, stabilize\.`/);
  assert.match(lenses, /\*\*Prefers wins:\*\* an item a Prefers rule places keeps that place even when\s+it also matches the lens's Defers/);
  assert.match(lenses, /4\. Place last the Defers items that no Prefers rule places\./);
  for (const name of valid) {
    const section = lenses.split(`\n## Lens: ${name}\n`)[1]?.split("\n## ")[0];
    assert.ok(section, `missing lens section ${name}`);
    for (const field of ["**Basis.**", "**Prefers**", "**Defers:**", "**Report basis:**"]) {
      assert.equal(section.includes(field), true, `${name}: missing ${field}`);
    }
  }

  for (const [, triage] of triageSkills) {
    const skill = await readText(path.join(repoRoot, "skills", "local", triage, "SKILL.md"));
    assert.match(skill, new RegExp(`\\[Triage Lenses\\]\\(${lensesLink.replace(/\./g, "\\.")}#choose-the-lens\\)`), triage);
    assert.match(skill, new RegExp(`under the lens,? following\\s+\\[Rank\\]\\(${lensesLink.replace(/\./g, "\\.")}#rank\\)`), triage);
    assert.match(skill, /\*\*Current State\*\*\n- Lens: <lens>\n- Basis: <the lens's report basis>\n/, triage);
    assert.match(skill, /If product intent or the lens basis is unclear/, triage);
    assert.match(skill, /\n\d\. Classify (?:each open issue|Work Items|candidate issues)/, `${triage} lost its classification step`);
    assert.match(skill, /- Build the current wave: actionable/, `${triage} lost its parallel wave step`);
    assert.doesNotMatch(
      skill,
      /unblock later work|Prefer unblocking work|moderate blast radius|thin vertical|Deferred foundation|Valid lenses|policy-setting/,
      `${triage} restates ranking rules owned by triage-common`,
    );
  }
});
