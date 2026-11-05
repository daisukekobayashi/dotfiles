import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import {
  repoRoot,
  readText,
  readRepoProfile,
  skillsForSource,
} from "./skills-helpers.mjs";

test("design preflight delegates to the installed grilling primitive", async () => {
  const base = await readRepoProfile("base");
  const designPreflight = await readText(
    path.join(repoRoot, "skills", "local", "design-preflight", "SKILL.md"),
  );

  assert.equal(skillsForSource(base, "mattpocock/skills").includes("grilling"), true);
  assert.match(designPreflight, /\*\*REQUIRED SUB-SKILL:\*\* Use `grilling`\./);
  assert.match(designPreflight, /\| `\$design-preflight open` \| Raw `grilling`;/);
  assert.doesNotMatch(designPreflight, /\*\*REQUIRED SUB-SKILL:\*\* Use `grill-me`\./);
});

test("delivery runs the issue understanding check before start and preflight", async () => {
  const checkRoot = path.join(repoRoot, "skills", "local", "issue-understanding-check");
  const check = await readText(path.join(checkRoot, "SKILL.md"));
  const metadata = await readText(path.join(checkRoot, "agents", "openai.yaml"));

  assert.match(check, /^description: Use only when explicitly requested with `\$issue-understanding-check`.*`github-issue-delivery`.*`azure-devops-work-item-delivery`/m);
  assert.match(metadata, /allow_implicit_invocation:\s*false/);
  assert.match(check, /before \/ after/);
  assert.match(check, /Ask one question/);
  for (const status of ["confirmed", "corrected", "skipped", "unresolved", "not run"]) {
    assert.match(check, new RegExp(`\`${status}\``));
  }

  for (const [delivery, start] of [
    ["github-issue-delivery", "github-issue-start"],
    ["azure-devops-work-item-delivery", "azure-devops-work-item-start"],
  ]) {
    const deliverySkill = await readText(path.join(repoRoot, "skills", "local", delivery, "SKILL.md"));
    const checkIndex = deliverySkill.indexOf("run `issue-understanding-check`");
    const startIndex = deliverySkill.indexOf(`Use \`${start}\``);
    const preflightIndex = deliverySkill.indexOf("Use `design-preflight-with-docs`");
    assert.ok(checkIndex > 0, `${delivery}: missing understanding check`);
    assert.ok(checkIndex < startIndex, `${delivery}: check must precede start`);
    assert.ok(startIndex < preflightIndex, `${delivery}: start must precede preflight`);
    assert.match(deliverySkill, /`confirmed`, `corrected`, or `skipped`/);
    assert.match(deliverySkill, /understanding check result: its confirmed examples/);
  }
});

test("provider delivery skills link the same delivery-common targets", async () => {
  const localRoot = path.join(repoRoot, "skills", "local");
  const deliveryCommon = path.join(localRoot, "delivery-common");
  const commonTargets = async (delivery) => {
    const skillDir = path.join(localRoot, delivery);
    const content = await readText(path.join(skillDir, "SKILL.md"));
    const targets = new Set();
    for (const [, target] of content.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) {
      if (/^[a-z][a-z\d+.-]*:/i.test(target)) continue;
      const relative = path.relative(deliveryCommon, path.resolve(skillDir, target.split("#")[0]));
      if (relative && !relative.startsWith("..") && !path.isAbsolute(relative)) {
        targets.add(relative.split(path.sep).join("/"));
      }
    }
    return [...targets].sort();
  };

  const github = await commonTargets("github-issue-delivery");
  const azure = await commonTargets("azure-devops-work-item-delivery");
  for (const target of ["references/local-review.md", "references/risk-tier.md"]) {
    assert.ok(github.includes(target), `github-issue-delivery: missing delivery-common link ${target}`);
  }
  assert.deepEqual(azure, github, [
    "provider delivery skills must link the same delivery-common targets",
    `only github-issue-delivery: ${github.filter((t) => !azure.includes(t)).join(", ") || "none"}`,
    `only azure-devops-work-item-delivery: ${azure.filter((t) => !github.includes(t)).join(", ") || "none"}`,
  ].join("\n"));
});

test("change review skills are explicit-only and share target selection", async () => {
  const adversarialRoot = path.join(repoRoot, "skills", "local", "change-adversarial-review");
  const changeReviewRoot = path.join(repoRoot, "skills", "local", "change-review");
  const adversarial = await readText(path.join(adversarialRoot, "SKILL.md"));
  const changeReview = await readText(path.join(changeReviewRoot, "SKILL.md"));
  const adversarialMetadata = await readText(path.join(adversarialRoot, "agents", "openai.yaml"));
  const changeReviewMetadata = await readText(
    path.join(changeReviewRoot, "agents", "openai.yaml"),
  );
  const targetSection = (skill) => skill.match(/## Resolve and Collect\n[\s\S]*?(?=\n## )/)?.[0];
  const runnerSection = (skill) => skill.match(/## Run the Reviewer\n[\s\S]*?(?=\n## )/)?.[0];

  assert.match(adversarial, /Use only when explicitly invoked with `\$change-adversarial-review`/);
  assert.match(changeReview, /Use only when explicitly invoked with `\$change-review`/);
  assert.match(adversarialMetadata, /allow_implicit_invocation:\s*false/);
  assert.match(changeReviewMetadata, /allow_implicit_invocation:\s*false/);
  assert.ok(targetSection(adversarial));
  assert.equal(targetSection(changeReview), targetSection(adversarial));
  assert.match(targetSection(changeReview), /git worktree list --porcelain/);
  assert.match(targetSection(changeReview), /merge-base/);
  assert.match(targetSection(changeReview), /git diff --cached/);
  assert.match(targetSection(changeReview), /Issue Context/);
  assert.equal(runnerSection(changeReview).replaceAll("change-review", "NAME"),
    runnerSection(adversarial).replaceAll("change-adversarial-review", "NAME"));
  for (const [skill, name] of [[changeReview, "change-review"], [adversarial, "change-adversarial-review"]]) {
    assert.match(runnerSection(skill), /By default, run this review in one fresh subagent of the current host/);
    assert.match(runnerSection(skill), /only when the user explicitly names it/);
    assert.match(runnerSection(skill), /do\s+not fall back/);
    assert.match(runnerSection(skill), /codex-companion\.mjs" task --fresh --cwd/);
    assert.match(runnerSection(skill), /no `--write`/);
    assert.match(runnerSection(skill), /--cwd <worktree> \\\n  --prompt-file <prompt-file>\n```/);
    assert.match(runnerSection(skill), /host's file-writing tool, not a shell command/);
    assert.match(runnerSection(skill), /outside the target worktree/);
    assert.match(runnerSection(skill), new RegExp(`Start it with \`Use \\$${name}\``));
    assert.doesNotMatch(runnerSection(skill), /single quotes|'Use \$/);
  }
  const securityRoot = path.join(repoRoot, "skills", "local", "change-security-review");
  const security = await readText(path.join(securityRoot, "SKILL.md"));
  const securityMetadata = await readText(path.join(securityRoot, "agents", "openai.yaml"));
  assert.match(security, /Use only when explicitly invoked with `\$change-security-review`/);
  assert.match(securityMetadata, /allow_implicit_invocation:\s*false/);
  assert.equal(targetSection(security), targetSection(changeReview));
  assert.equal(runnerSection(security).replaceAll("change-security-review", "NAME"),
    runnerSection(changeReview).replaceAll("change-review", "NAME"));
  assert.match(security, /SECURITY\.md/);
  for (const skill of [changeReview, adversarial, security]) {
    const target = targetSection(skill);
    assert.match(target, /root has a `REVIEW\.md` at the merge-base/);
    assert.match(target, /never lowers material or security\s+criteria, skips a sensitive path/);
    assert.match(target, /\(\.\.\/delivery-common\/references\/risk-tier\.md#sensitive-paths\)/);
    assert.match(target, /`change-security-review` applies none of its skip paths/);
    assert.match(target, /never\s+policy for this review/);
    assert.match(target, /state that change in Coverage and Residual Risk even\s+without a finding/);
  }
  assert.match(security, /`introduced`[\s\S]*`worsened`[\s\S]*`pre-existing`/);
  assert.match(security, /^description:.*`github-issue-delivery`.*`azure-devops-work-item-delivery`.*risk tier/m);
  const deliveryCommon = path.join(repoRoot, "skills", "local", "delivery-common");
  const riskTier = await readText(path.join(deliveryCommon, "references", "risk-tier.md"));
  const localReview = await readText(path.join(deliveryCommon, "references", "local-review.md"));
  for (const tier of ["Low", "Medium", "High"]) {
    assert.match(riskTier, new RegExp(`^- \\*\\*${tier}:\\*\\*`, "m"));
  }
  assert.match(riskTier, /Run `change-security-review` as a third local reviewer/);
  assert.match(riskTier, /Keep them\s+out of the PR body/);
  assert.match(riskTier, /Repository policy adds paths; it never removes a default/);
  assert.match(riskTier, /^## Sensitive paths$/m);
  assert.match(riskTier, /deletes `SECURITY\.md`, `REVIEW\.md`, or `CODEOWNERS`\s+touches a sensitive path/);
  assert.match(riskTier, /Always read policy at the delivery's recorded base/);
  assert.match(riskTier, /Always run it with `--base <base-sha>`/);
  assert.match(riskTier, /current tier is High/);
  assert.match(riskTier, /closes only by a\s+verified fix or an explicit decision to accept it in the user.s own message/);
  assert.match(localReview, /\[Risk Tier\]\(risk-tier\.md\)/);
  assert.match(localReview, /`change-security-review`/);
  assert.match(localReview, /`change-security-review`\s+with the base Risk Tier sets/);
  for (const delivery of ["github-issue-delivery", "azure-devops-work-item-delivery"]) {
    const deliverySkill = await readText(path.join(repoRoot, "skills", "local", delivery, "SKILL.md"));
    assert.match(deliverySkill, /\[Risk Tier\]\(\.\.\/delivery-common\/references\/risk-tier\.md\)/);
    assert.match(deliverySkill, /risk tier for that head with\s+(its )?recommended human review/);
  }
  assert.match(changeReview, /correctness/i);
  assert.match(changeReview, /regression/i);
  assert.match(adversarial, /challenge the approach/i);
  assert.match(adversarial, /review-only/i);
  assert.equal(existsSync(path.join(repoRoot, "skills", "local", "code-review")), false);
  assert.equal(existsSync(path.join(repoRoot, "skills", "local", "local-code-review")), false);
  assert.equal(existsSync(path.join(repoRoot, "skills", "local", "adversarial-review", "SKILL.md")), false);
  assert.equal(existsSync(path.join(repoRoot, "skills", "local", "review-change", "SKILL.md")), false);
  assert.equal(existsSync(path.join(repoRoot, "skills", "local", "codex-review", "SKILL.md")), false);
  assert.equal(existsSync(path.join(repoRoot, "skills", "local", "codex-adversarial-review", "SKILL.md")), false);
  assert.doesNotMatch(`${changeReview}\n${adversarial}`, /\$code-review|local-code-review|\$codex-review/);
});
