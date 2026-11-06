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

const flat = (text) => text?.replace(/\s+/g, " ");

test("design preflight delegates to the installed grilling primitive", async () => {
  const base = await readRepoProfile("base");
  const designPreflight = await readText(
    path.join(repoRoot, "skills", "local", "design-preflight", "SKILL.md"),
  );

  assert.equal(skillsForSource(base, "mattpocock/skills").includes("grilling"), true);
  assert.match(designPreflight, /\*\*REQUIRED SUB-SKILL:\*\* Use `grilling`\./);
  assert.match(designPreflight, /\| `\$design-preflight open` \| Raw `grilling`;/);
  assert.match(designPreflight, /Give each recommended answer a one-line reason\./);
  assert.match(designPreflight, /name each viewpoint and the answer it favors, such as short-term smallest change versus long-term maintainability, then give the overall recommendation from the stance's baseline and why\./);
  assert.match(designPreflight, /When the evidence supports no recommendation, say so in place of one\./);
  assert.doesNotMatch(designPreflight, /\*\*REQUIRED SUB-SKILL:\*\* Use `grill-me`\./);
});

test("delivery starts the worker, then runs the shared understanding before preflight", async () => {
  const checkRoot = path.join(repoRoot, "skills", "local", "shared-understanding");
  const check = await readText(path.join(checkRoot, "SKILL.md"));
  const metadata = await readText(path.join(checkRoot, "agents", "openai.yaml"));

  assert.match(check, /^name: shared-understanding$/m);
  assert.match(check, /^description: Use only when explicitly requested with `\$shared-understanding`.*`github-issue-delivery`.*`azure-devops-work-item-delivery`/m);
  assert.match(check, /^description: .*Frame an unsettled problem with `find-unknowns`; decide how to build in `design-preflight`\.$/m);
  assert.match(metadata, /allow_implicit_invocation:\s*false/);
  assert.match(check, /before \/ after/);
  assert.match(check, /### 3\. Read back the decisions/);
  assert.match(check, /A decision stays open\s+until the user explicitly accepts or adjusts it\./);
  assert.match(check, /each an observable result of that\s+situation, plus `can't decide`/);
  assert.match(check, /Offer 2-3 options with equal detail/);
  assert.match(check, /Recommend one option with a one-line reason drawn from the sources;\s+the\s+recommendation informs the user's choice, and the decision stays theirs\./);
  assert.match(check, /When\s+viewpoints favor different options, name each viewpoint and the option it\s+favors, then give the overall recommendation and why/);
  assert.match(check, /The\s+default viewpoints are the short-term smallest change and long-term\s+maintainability;/);
  assert.match(check, /The overall recommendation favors\s+long-term maintainability unless the user's request states another stance/);
  assert.match(check, /When the sources\s+support no recommendation, say so in place of one\./);
  assert.match(check, /A point the user still cannot\s+decide after that explanation stays open\./);
  assert.match(check, /An open point closes here, never as `confirmed` or\s+`skipped`\./);
  assert.match(check, /`skipped`: the user explicitly skipped the check\./);
  assert.doesNotMatch(check, /Ask one intent question/);
  for (const status of ["confirmed", "corrected", "skipped", "unresolved", "not run"]) {
    assert.match(check, new RegExp(`\`${status}\``));
  }
  for (const section of ["Agreed Decisions", "Agreed Issue Changes", "Carry to Design Preflight", "Open Points"]) {
    assert.match(check, new RegExp(`^## ${section}$`, "m"));
  }

  for (const [delivery, start] of [
    ["github-issue-delivery", "github-issue-start"],
    ["azure-devops-work-item-delivery", "azure-devops-work-item-start"],
  ]) {
    const deliverySkill = await readText(path.join(repoRoot, "skills", "local", delivery, "SKILL.md"));
    const checkIndex = deliverySkill.indexOf("worker drafts `shared-understanding`");
    const startIndex = deliverySkill.indexOf(`Use \`${start}\``);
    const preflightIndex = deliverySkill.indexOf("Use `design-preflight-with-docs`");
    assert.ok(startIndex > 0, `${delivery}: missing start`);
    assert.ok(startIndex < checkIndex, `${delivery}: start must dispatch the worker before the shared understanding`);
    assert.ok(checkIndex < preflightIndex, `${delivery}: shared understanding must precede preflight`);
    assert.doesNotMatch(deliverySkill, /run `shared-understanding` in the\s+coordinator/, delivery);
    assert.match(deliverySkill, /`confirmed`, `corrected`, or `skipped`/);
    assert.match(deliverySkill, /waiting for the user with their open points/);
    assert.match(deliverySkill, /shared understanding result: its agreed decisions/);
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
  for (const target of ["references/completion.md", "references/local-review.md", "references/risk-tier.md", "references/worker-dialogue.md"]) {
    assert.ok(github.includes(target), `github-issue-delivery: missing delivery-common link ${target}`);
  }
  assert.deepEqual(azure, github, [
    "provider delivery skills must link the same delivery-common targets",
    `only github-issue-delivery: ${github.filter((t) => !azure.includes(t)).join(", ") || "none"}`,
    `only azure-devops-work-item-delivery: ${azure.filter((t) => !github.includes(t)).join(", ") || "none"}`,
  ].join("\n"));
});

test("delivery-common owns local review repetition, advancement, and rounds", async () => {
  const deliveryCommon = path.join(repoRoot, "skills", "local", "delivery-common");
  const common = await readText(path.join(deliveryCommon, "SKILL.md"));
  const localReview = await readText(path.join(deliveryCommon, "references", "local-review.md"));
  const repeat = localReview.match(/## Repeat and advance\n[\s\S]*?(?=\n## |$)/)?.[0];

  assert.ok(repeat, "local-review.md: missing Repeat and advance");
  assert.match(repeat, /After fixes, run\s+relevant checks and use focused follow-up/);
  assert.match(repeat, /Repeat the full review only when the design or\s+change scope shifts materially, or new evidence makes the earlier full-review\s+coverage insufficient/);
  assert.match(repeat, /no required\s+new full review is still pending, the most recent full review and the\s+follow-ups completed since it cover the current head with the reviewers its\s+current tier selects/);
  assert.match(repeat, /A required new full review counts as the most recent one only\s+after it completes\./);
  const fullReview = localReview.match(/## Run the full review\n[\s\S]*?(?=\n## |$)/)?.[0];
  assert.ok(fullReview, "local-review.md: missing Run the full review");
  assert.match(fullReview, /A full review is one pass of every selected reviewer over the entire task diff,\s+not only the last fix commit/);
  assert.match(repeat, /at most three local review rounds per target across the delivery,\s+including resumes/);
  assert.match(repeat, /Count the initial full review, each focused follow-up on a\s+fixed snapshot, and each required new full review as one round apiece/);
  assert.match(repeat, /full-review and\s+follow-up head SHAs, their coverage, and the local round count/);
  assert.doesNotMatch(common, /owns[^.]*review round\s+limits/);
  assert.match(common, /^description: .*repeat or advance/m);
  assert.doesNotMatch(localReview, /the caller selects focused follow-up/);

  const providers = {};
  for (const delivery of ["github-issue-delivery", "azure-devops-work-item-delivery"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", delivery, "SKILL.md"));
    providers[delivery] = skill;
    assert.match(skill, /After fixes, follow Local Review's Repeat and advance for focused follow-up,\s+escalation to a full review, and advancement\./, delivery);
    assert.match(skill, /Local review rounds follow Local Review's Repeat and advance/, delivery);
    assert.doesNotMatch(skill, /repeat the selected reviews on the new snapshot/, delivery);
    assert.doesNotMatch(skill, /three local review rounds/, delivery);
    assert.doesNotMatch(skill, /Count the initial full review/, delivery);
    assert.doesNotMatch(skill, /completed follow-ups cover the current head with the reviewers/, delivery);
    assert.doesNotMatch(skill, /selected local\s+reviews completed/, delivery);
    assert.doesNotMatch(skill, /Local Review's escalation rule/, delivery);
  }
  assert.match(providers["github-issue-delivery"], /at most three hosted Codex\s+review rounds per issue/);
  assert.match(providers["github-issue-delivery"], /hosted-fix\s+follow-ups use the same local budget/);
  assert.match(providers["azure-devops-work-item-delivery"], /Advance when the exact published implementation is covered by the most recent\s+full review and the follow-ups completed since it under Local Review's Repeat\s+and advance/);
  assert.match(providers["github-issue-delivery"], /Advance only when the current\s+published head is covered by the most recent full review and the follow-ups\s+completed since it under Local Review's Repeat and advance/);
  for (const [name, text] of Object.entries(providers)) {
    assert.doesNotMatch(text, /full local reviews and completed follow-ups|initial full\s+review and completed follow-ups/, name);
  }
  const riskTier = await readText(path.join(deliveryCommon, "references", "risk-tier.md"));
  const docs = {};
  for (const doc of ["skills-profiles.md", "skills-profiles.ja.md"]) {
    docs[doc] = await readText(path.join(repoRoot, "docs", doc));
  }
  for (const [name, text] of Object.entries({ "local-review.md": localReview, "risk-tier.md": riskTier, ...docs, ...providers })) {
    assert.doesNotMatch(text, /full\s+pair/, name);
  }
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
    assert.match(runnerSection(skill), /Run one Codex run at a time per target worktree/);
    assert.match(runnerSection(skill), /Before and after the run, including a failed run, follow\s+`\.\.\/worktree-runtime-cleanup\/SKILL\.md` "Brokers Started by a Codex Review"/);
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
  assert.doesNotMatch(riskTier, /it never removes a default/);
  assert.match(riskTier, /agent instruction files: skills[^\n]*\n\nThe base root `AGENTS\.md` may have a `## Delivery sensitive paths` section/);
  assert.match(riskTier, /`add <pattern>` and `exclude <pattern> from <default>` entries/);
  assert.match(riskTier, /the text before any colon, matched\s+case-insensitively/);
  assert.match(riskTier, /gitignore-style globs from the repository\s+root/);
  assert.match(riskTier, /An exclusion narrows only that default; it never removes a path another\s+source adds, or any `AGENTS\.md`, `CLAUDE\.md`, `GEMINI\.md`, `SECURITY\.md`,\s+`REVIEW\.md`, or `CODEOWNERS` file/);
  assert.match(riskTier, /Ignore an invalid entry, apply the rest, and\s+report the ignored one/);
  assert.match(riskTier, /`AGENTS\.md` entries ignored as invalid/);
  const agents = await readText(path.join(repoRoot, "AGENTS.md"));
  assert.match(agents, /^## Delivery sensitive paths$/m);
  assert.match(agents, /^- exclude `skills\/\*\*\/\*\.md` from agent instruction files$/m);
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
  }
  const completion = await readText(path.join(deliveryCommon, "references", "completion.md"));
  assert.match(completion, /risk tier for that head with its\s+recommended human review/);
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

test("delivery workers draft the understanding and preflight for the coordinator to ask", async () => {
  const localRoot = path.join(repoRoot, "skills", "local");
  const read = (...parts) => readText(path.join(localRoot, ...parts));
  const dialogue = flat(await read("delivery-common", "references", "worker-dialogue.md"));
  const common = await read("delivery-common", "SKILL.md");

  assert.match(dialogue, /the target's worker reads the task and code and drafts, and the coordinator holds every dialogue with the user\. No subagent asks the user a question\./);
  assert.match(dialogue, /including when the delivery has a single target\. The same worker drafts the shared understanding, drafts the preflight, and implements, keeping its context\./);
  assert.match(dialogue, /Without delegation, report the limitation and process targets one at a time\. The coordinator runs `shared-understanding` and `design-preflight-with-docs` itself and asks the user directly/);
  const order = ["runs `shared-understanding` in draft mode", "The coordinator verifies the draft", "Continue only with a status of `confirmed`, `corrected`, or `skipped`", "runs `design-preflight-with-docs` in draft mode", "The coordinator verifies the preflight draft", "implements on the settled decisions"]
    .map((step) => dialogue.indexOf(step));
  assert.ok(order.every((index, i) => index >= 0 && (i === 0 || order[i - 1] < index)), `worker-dialogue.md: step order ${order}`);
  assert.match(dialogue, /workers draft in parallel\. The coordinator holds one target's dialogue at a time/);
  assert.match(dialogue, /A drafted recommendation is not a decision; only the user's answers settle the points\./);
  assert.match(dialogue, /checks the listed defaults for a decision that should have been a question/);
  assert.match(common, /^description: Shared worker dialogue, .*workers draft the shared understanding and design preflight for the coordinator to ask/m);
  assert.match(common, /\[Worker Dialogue\]\(references\/worker-dialogue\.md\)/);

  for (const delivery of ["github-issue-delivery", "azure-devops-work-item-delivery"]) {
    const skill = flat(await read(delivery, "SKILL.md"));
    assert.match(skill, /dispatch the (issue|item)'s worker before the shared understanding/, delivery);
    assert.match(skill, /its worker drafts `shared-understanding`, and the coordinator asks the user one (issue|item) at a time/, delivery);
    assert.match(skill, /no worker asks the user directly/, delivery);
    assert.match(skill, /drafted by the worker and asked by the coordinator under Worker Dialogue/, delivery);
  }

  const rule = /defaults only for implementation tactics[^.]*?; return contract, boundary, compatibility, and security decisions to the coordinator as questions with options and a recommendation, even when they look low-risk/;
  const githubStart = flat(await read("github-issue-start", "SKILL.md"));
  assert.match(githubStart, rule);
  assert.match(githubStart, /never ask the user directly/);
  assert.match(githubStart, /open questions, every default chosen/);
  assert.match(githubStart, /also for a single issue when delegation is available/);
  const azureStart = flat(await read("azure-devops-work-item-start", "SKILL.md"));
  assert.match(azureStart, /A worker chooses defaults only for implementation tactics\. It returns contract, boundary, compatibility, and security decisions to the coordinator as questions with options and a recommendation, even when they look low-risk/);
  assert.match(azureStart, /It never asks the user directly, and its report lists open questions and every default it chose\./);
  assert.match(azureStart, /also for a single item when delegation is available/);

  const check = flat(await read("shared-understanding", "SKILL.md"));
  assert.match(check, /## Draft for a coordinator .*Ask the user nothing and settle nothing; every decision and point stays open until the coordinator returns the user's answers\./);
  for (const section of ["Overview", "Decisions to Read Back", "Undecided Points", "Carry to Design Preflight"]) {
    assert.match(await read("shared-understanding", "SKILL.md"), new RegExp(`^## ${section}$`, "m"));
  }
  const preflight = flat(await read("design-preflight", "SKILL.md"));
  assert.match(preflight, /## Draft for a coordinator .*return the questions instead of asking them\./);
  assert.match(preflight, /A drafted recommendation is not an accepted decision; do not proceed on it\./);
  const withDocs = flat(await read("design-preflight-with-docs", "SKILL.md"));
  assert.match(withDocs, /When a delivery coordinator asks for a draft, forward that request so `design-preflight` returns its questions instead of asking\./);
  assert.match(withDocs, /write documentation only after the coordinator returns the user's answers\./);
});

test("delivery-common owns the shared completion policy", async () => {
  const localRoot = path.join(repoRoot, "skills", "local");
  const read = (...parts) => readText(path.join(localRoot, ...parts));
  const completion = flat(await read("delivery-common", "references", "completion.md"));
  const localReview = flat(await read("delivery-common", "references", "local-review.md"));
  const common = await read("delivery-common", "SKILL.md");

  for (const rule of [
    /classify them as temporary and choose ignored agent-work storage or `\/tmp`/,
    /the shared understanding result and the latest worker drafts/,
    /the local review record under \[Local Review\]\(local-review\.md\)/,
    /Coordinate publication sequentially across targets\. Workers hand off their exact branch and worktree, task and spec, recorded base, verification, risk tier, and local review evidence\./,
    /Before publication, show the user the tier, its main reasons, the recommended human review/,
    /Pending, failed, or inaccessible required evidence leaves the task waiting or blocked\./,
    /Request confirmation to merge that specific PR\./,
    /a queued or scheduled merge remains pending/,
    /Advance as soon as the completion criteria are met\./,
    /If progress repeatedly stalls, a review times out, a required check fails, or a material human decision is needed, preserve progress and report the next action/,
    /Stop further publication targets after a publication failure/,
    /A wait or an unresolved approval stays open/,
    /Mark `Complete` only after acceptance criteria, current verification and reviews, actual merge, task closure, and confirmed local cleanup/,
    /the calling workflow defines task closure/,
    /Before cleanup, keep this task's follow-up candidates in a record outside the worktree being removed/,
    /create-or-drop recommendation/,
    /the creation criterion it meets or `none`/,
    /Recommend create only when the candidate meets at least one criterion/,
    /it reproduces under supported use of the changed behavior;/,
    /it is an exploitable security vulnerability;/,
    /the user asked for it\./,
    /Otherwise recommend drop, including theoretical edge cases and tests that only pin current behavior\./,
    /source links to the calling workflow's create skill/,
    /Pending candidates do not block `Complete`/,
  ]) {
    assert.match(completion, rule, `completion.md: ${rule}`);
  }
  assert.match(completion, /plus the calling workflow's additions/);
  assert.doesNotMatch(completion, /github|azure|codex|`[a-z-]+-create`/i, "completion.md stays provider-neutral");
  assert.match(common, /\[Delivery Completion\]\(references\/completion\.md\)/);
  assert.match(common, /^description: .*merge confirmation.*follow-up candidates/m);
  assert.match(localReview, /Apply worthwhile fixes and record a concise reason for each explained, duplicate, stale, pre-existing, or skipped finding\. Leave disputed material findings and design decisions open for the user\./);

  const additions = {
    "github-issue-delivery": [/`github-issue-create`/, /hosted review outcome/, /hosted limit reached with required work remaining/, /issue's actual closed state/],
    "azure-devops-work-item-delivery": [/`azure-devops-work-item-create`/, /proposed state-transition scope/, /`Merged; Work Item completion pending`/, /Work Item's verified completion/],
  };
  for (const [delivery, rules] of Object.entries(additions)) {
    const skill = flat(await read(delivery, "SKILL.md"));
    for (const rule of rules) assert.match(skill, rule, `${delivery}: ${rule}`);
    assert.match(skill, /Coordinate publication and show the tier under Delivery Completion's Before publication\./, `${delivery}: references Before publication`);
    for (const moved of [
      /classify them as temporary/,
      /Apply worthwhile fixes/,
      /Coordinate publication sequentially/,
      /hand off their (exact )?branch/,
      /Before publication, show the user the tier/,
      /Request confirmation (to merge|for) that specific PR/,
      /queued (or scheduled )?merge remains pending/,
      /Advance as soon as the completion criteria are met/,
      /progress repeatedly stalls|repeated non-progress/,
      /Independent local work may continue/,
      /Mark `Complete` only after/,
      /in a record outside the worktree being removed/,
      /create-or-drop recommendation/,
      /Pending candidates do not block/,
    ]) {
      assert.doesNotMatch(skill, moved, `${delivery} restates moved policy: ${moved}`);
    }
  }
});

test("delivery shows material self-closures before publication and at merge", async () => {
  const localRoot = path.join(repoRoot, "skills", "local");
  const read = (...parts) => readText(path.join(localRoot, ...parts));
  const localReview = flat(await read("delivery-common", "references", "local-review.md"));
  const completion = flat(await read("delivery-common", "references", "completion.md"));
  const github = flat(await read("github-issue-delivery", "SKILL.md"));
  const azure = flat(await read("azure-devops-work-item-delivery", "SKILL.md"));

  const selfClosures = localReview.match(/- \*\*Self-closures:\*\*.*?(?= Apply worthwhile fixes)/)?.[0];
  assert.ok(selfClosures, "Assess findings defines self-closures");
  for (const rule of [
    /Keep a self-closure list in the progress record/,
    /A `material` finding that ends without a verified fix and is not left open for the user, whatever its disposition: `explained`, `stale`, `skipped`, or `duplicate`\./,
    /A `duplicate` stays listed even when the earlier finding is `applied`, unless a later reviewer round verified that fix against this report\./,
    /Marked `downgraded`, a finding triaged `minor` whose reviewer label is `unknown` or at the blocking level: High from `change-review` or `change-adversarial-review`, P0 or P1 from a hosted reviewer\./,
    /Marked `reclassified`, a finding triaged `pre-existing` that its reviewer tagged `introduced` or `worsened`\./,
    /the finding, its source reviewer and round or thread, the reviewer's label and tag, the disposition, and the reason/,
    /Add the source of a later `duplicate` to the existing entry for the same finding\./,
    /Drop an entry once a later reviewer round checks the fix against this finding and confirms it, or re-triage leaves the finding open for the user; a hosted review with no findings does not count as that check\./,
    /publication and merge approval cover it, and a finding the user reopens is open again\./,
    /A `material` `change-security-review` finding, including any its reviewer tagged `introduced` or `worsened` whatever its triage here, stays under \[Risk Tier\]\(risk-tier\.md\): it never enters this list, and publication or merge approval never covers it\./,
    /A `pre-existing` Critical or High `change-security-review` finding is a follow-up candidate that the user also sees with this list\./,
  ]) {
    assert.match(selfClosures, rule, `local-review.md: ${rule}`);
  }
  assert.doesNotMatch(selfClosures, /Critical or High from `change-security-review`/, "security findings are never downgraded");

  assert.match(completion, /finding dispositions, the self-closure list under Local Review, follow-up candidates/);
  assert.match(completion, /Beside them, show the self-closure list under \[Local Review\]\(local-review\.md\), or `none` when it is empty, and any pre-existing Critical or High security findings\./);
  assert.match(completion, /user-accepted security findings, the self-closure list or `none`, any pre-existing Critical or High security findings, and the proposed repository-supported merge method/);

  assert.match(github, /Pass the progress record location to the cycle so that, before its Writeback, it persists the prepared record's items not `applied` \(the head Codex reviewed, thread, finding, reviewer label, triage class, disposition, and reason\) there\. When the cycle returns the items instead, record them there and confirm to the cycle\. Add their self-closures to the list under Local Review's Assess findings; on resume, use the persisted items for the current hosted-reviewed head\./);
  for (const [delivery, skill] of [["github-issue-delivery", github], ["azure-devops-work-item-delivery", azure]]) {
    assert.doesNotMatch(skill, /`none` when it is empty|`downgraded`|`reclassified`/, `${delivery} restates the self-closure policy`);
  }
});

test("delivery resume checks the recorded branch name", async () => {
  for (const delivery of ["github-issue-delivery", "azure-devops-work-item-delivery"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", delivery, "SKILL.md"));
    const resume = flat(skill.match(/\nOn resume, [\s\S]*?(?=\n\n)/)?.[0]);

    assert.ok(resume, `${delivery}: missing resume paragraph`);
    assert.match(resume, /Stop and report the recorded branch unless it is a \*\*safe branch name\*\*, using only `\[A-Za-z0-9\/._-\]`, before running any command with it\./, `${delivery}: recorded branch checked`);
  }
});

test("Codex review runs stop only the broker tree they started", async () => {
  const runtime = await readText(
    path.join(repoRoot, "skills", "local", "worktree-runtime-cleanup", "SKILL.md"),
  );
  const brokers = flat(runtime.match(/## Brokers Started by a Codex Review\n[\s\S]*?(?=\n## )/)?.[0]);

  assert.ok(brokers, "worktree-runtime-cleanup: missing Brokers Started by a Codex Review");
  assert.match(brokers, /stopping them needs no confirmation/);
  assert.match(brokers, /Before the run, record `scripts\/list-processes\.sh <worktree>`/);
  assert.match(brokers, /is a broker this run started only when it is absent from the first list, by PID and start time, and/);
  assert.match(brokers, /its `cwd` column in the second list equals exactly the target worktree root/);
  assert.match(brokers, /The `command` column is cut to 200 characters and never establishes ownership/);
  assert.match(brokers, /A missing, unreadable, or ` \(deleted\)` cwd is not an exact match/);
  assert.doesNotMatch(brokers, /`--cwd` argument, or its cwd when it has none/);
  assert.match(brokers, /prefix matching never establishes ownership here/);
  assert.match(brokers, /Report any other listed broker, whether pre-existing or under the target without equaling it, and leave it running\./);
  assert.match(brokers, /every listed process descending from it by `ppid`, with PID and start time/);
  assert.match(brokers, /Immediately before signaling, recheck each broker's PID and start time/);
  assert.match(brokers, /Never signal a process outside the recorded tree, and never use SIGKILL\./);
  assert.match(brokers, /Leftovers do not change the review result/);
  assert.match(brokers, /report the teardown as unverified and leave it to cleanup/);
  assert.match(flat(runtime), /Review skills that run Codex follow only \[Brokers Started by a Codex Review\]\(#brokers-started-by-a-codex-review\)/);

  const localReview = flat(await readText(
    path.join(repoRoot, "skills", "local", "delivery-common", "references", "local-review.md"),
  ));
  assert.match(localReview, /Run Codex-routed reviewers for one worktree one at a time; each stops the broker it starts\./);

  for (const cleanup of ["github-worktree-cleanup", "azure-devops-worktree-cleanup"]) {
    const skill = flat(await readText(path.join(repoRoot, "skills", "local", cleanup, "SKILL.md")));
    assert.match(skill, /Before removal, follow `\.\.\/worktree-runtime-cleanup\/SKILL\.md` for the/, cleanup);
  }
});
