import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { readText, repoRoot } from "./skills-helpers.mjs";

const localRoot = path.join(repoRoot, "skills", "local");
const commonDir = path.join(localRoot, "delivery-common");
const flat = (text) => text.replace(/\s+/g, " ");
const section = (text, heading) => {
  const start = text.indexOf(`\n${heading}\n`);
  assert.notEqual(start, -1, `missing ${heading}`);
  const level = heading.match(/^#+/)[0];
  const rest = text.slice(start + heading.length + 2);
  const end = rest.search(new RegExp(`^#{1,${level.length}} `, "m"));
  return end === -1 ? rest : rest.slice(0, end);
};

test("delivery-common states which numbers are claimed and how a claimed number is reported", async () => {
  const skill = await readText(path.join(commonDir, "SKILL.md"));
  assert.match(skill, /^description: .*explains a claimed performance number before reporting it/m);
  const rule = flat(section(skill, "## Performance Claims"));

  // The trigger: time or resource-consumption comparisons, never test counts or check results.
  assert.match(rule, /A claimed number is a measured comparison, before and after or between options, of time \(wall time, latency, throughput, or a percentage or factor faster or slower\) or of resource consumption \(memory, CPU, size, or token or context consumption\)\./);
  assert.match(rule, /A test count or a pass or fail check result is never one\./);
  assert.match(rule, /It is claimed when it appears in the delivery's own output: a worker report or summary, a commit message, the PR title or body, the decision summary or final report, or text the task diff adds\./);

  // The inline rule holds without any optional skill and never blocks the delivery.
  assert.match(rule, /Explain a claimed number before reporting it: keep the run count, the spread, and the limiter with it/);
  // Named, not linked: a link would make the export add the principle as a required dependency.
  assert.match(rule, /`explain-the-number` gives these rules in full when installed; it is never a prerequisite\./);
  assert.doesNotMatch(skill, /\]\(\.\.\/(explain-the-number|benchmark-checklist)\//);
  assert.match(rule, /A number that cannot be explained stays where it was written, labeled `inconclusive` with each unchecked item named as a gap; it never blocks the delivery\./);
  assert.match(rule, /`Verification:` rows under \[Classified verification\]\(references\/report-handoff\.md#classified-verification\)/);
  assert.match(rule, /The decision summary and the final report show each claim with its explanation or gaps, and the latest `benchmark-checklist` status\./);

  // A late claim gets the rule only, and no claim means no run.
  assert.match(rule, /A claim first written after that step, such as in the PR body, gets only this rule: cite that head's evidence or label it `inconclusive`; it launches no run\./);
  assert.match(rule, /A delivery with no claimed number never runs it\./);

  // Workers reach the rule from their verification step without a restatement.
  const dialogue = flat(await readText(path.join(commonDir, "references", "worker-dialogue.md")));
  assert.match(dialogue, /Apply \[Performance Claims\]\(\.\.\/SKILL\.md#performance-claims\) to any number the report claims\./);
});

test("benchmark-checklist is a registered optional workflow on the reviewed head at every tier", async () => {
  const frame = await readText(path.join(commonDir, "references", "optional-workflows.md"));
  const registry = frame.match(/\n## Registry\n[\s\S]*$/)?.[0] ?? "";
  const row = registry.split("\n").find((line) => line.startsWith("| `benchmark-checklist` |"));
  assert.ok(row, "the registry contains a benchmark-checklist entry");
  const cells = row.slice(2, -2).split(" | ");
  assert.equal(cells.length, 8);
  assert.match(cells[1], /^\*\*Performance claims\*\* in \[Local Review\]\(local-review\.md#performance-claims\), on the pinned worker head after final tier selection$/);
  assert.match(cells[2], /^A claimed number under \[Performance Claims\]\(\.\.\/SKILL\.md#performance-claims\)/);
  assert.equal(cells[3], "All tiers");
  assert.match(cells[4], /^30 minutes per reviewed head, shared by worktree creation for both sides/);
  assert.equal(cells[5], "Reviewed head: full SHA");
  assert.match(cells[6], /^The coordinator explicitly invokes `benchmark-checklist` \(an explicit `\$benchmark-checklist` mention on Codex, the skill call on Claude Code\) in full mode, forwarding the user's delivery request, exact target/);
  assert.match(cells[7], /`inconclusive` with named gaps, in the verification record, plus the latest optional status$/);

  // explain-the-number is a principle linked by the rule, not a registry entry.
  assert.doesNotMatch(registry, /^\| `explain-the-number` \|/m);
});

test("Local Review runs benchmark-checklist on the claims with both sides isolated and asks nothing mid-run", async () => {
  const review = await readText(path.join(commonDir, "references", "local-review.md"));
  assert.match(flat(review), /Apply \[Performance claims\]\(#performance-claims\) before advancing from the round\./);
  const step = flat(section(review, "## Performance claims"));
  assert.match(step, /applies the `benchmark-checklist` entry of the \[Optional Workflows registry\]\(optional-workflows\.md#registry\)/);
  assert.match(step, /\[Reconcile existing intents\]\(optional-workflows\.md#record-and-report\) before evaluating eligibility\./);
  assert.match(step, /the commit messages from the recorded base to the head \(`git log --format=%B <base>\.\.<head>`\), and the lines the task diff adds/);
  assert.match(step, /With no claim, record `not run: trigger not met`\./);
  assert.match(step, /Require the delivery's own \[trusted worker head\]\(repro-runs\.md#trusted-heads\)\. For this step only, the recorded base that head was built on runs as the before side under the same trust\./);
  assert.match(step, /Create one disposable worktree at the pinned head and one at the recorded base under \[Disposable worktree\]\(repro-runs\.md#disposable-worktree\)/);
  assert.match(step, /Invoke `benchmark-checklist` explicitly in full mode/);
  assert.match(step, /The request authorizes running only the existing measurement and installed, unprivileged profilers locally in those worktrees\./);
  assert.match(step, /is not done and is reported as a gap\./);
  assert.match(step, /Never remove or rewrite a claim\. Never invoke the skill again on that key, or use its result on another head\./);
  // The step links the registry instead of restating its bound.
  assert.doesNotMatch(step, /30 minutes/);
});

test("benchmark-checklist gains only the scoped delivery exception and is a delivery sensitive path", async () => {
  const root = path.join(localRoot, "benchmark-checklist");
  const skill = await readText(path.join(root, "SKILL.md"));
  const frontmatter = skill.match(/^---\n([\s\S]*?)\n---/)[1];
  assert.doesNotMatch(frontmatter, /disable-model-invocation/);
  assert.match(await readText(path.join(root, "agents", "openai.yaml")), /^policy:\n  allow_implicit_invocation: false$/m);
  assert.match(frontmatter, /^description: Use only when the user explicitly invokes benchmark-checklist .*, or as the Local Review performance-claims step of an explicitly user-requested `github-issue-delivery` or `azure-devops-work-item-delivery` workflow for named issues or Work Items\./m);
  const body = flat(skill);
  assert.match(body, /Run only when the user explicitly invokes `benchmark-checklist`, such as `\$benchmark-checklist` in Codex or `\/benchmark-checklist` in Claude Code, or through the user's explicit request for the full `github-issue-delivery` or `azure-devops-work-item-delivery` workflow for named issues or Work Items, as its Local Review performance-claims step\. A caller must forward that request and exact target/);
  assert.match(body, /A generic performance question or a reference from another skill, including \[explain-the-number\]\(\.\.\/explain-the-number\/SKILL\.md\), does not activate this workflow\./);
  assert.match(body, /As the delivery step, use full mode\. The trusted code is the delivery's own worker head and the recorded base it was built on/);
  assert.match(body, /The run cannot ask the user, so it does none of the items above that need asking and reports each one it needed as a gap\./);

  // The delivery exception is an authority rule in a file that skills/**/*.md excludes, so AGENTS.md adds it back.
  const agents = await readText(path.join(repoRoot, "AGENTS.md"));
  assert.match(section(agents, "## Delivery sensitive paths"), /^- add `skills\/local\/benchmark-checklist\/SKILL\.md`$/m);

  // ADR 0001 lists the skill with the other delivery exceptions, in both languages.
  const adr = flat(await readText(path.join(repoRoot, "docs", "adr", "0001-pstack-principles-in-delivery.md")));
  assert.match(adr, /Delivery invokes `arena`, `blast-radius`, `evaluate-skill`, and `benchmark-checklist` the way it already invokes `change-\*review`/);
  const adrJa = flat(await readText(path.join(repoRoot, "docs", "adr", "0001-pstack-principles-in-delivery.ja.md")));
  assert.match(adrJa, /delivery は `arena`、`blast-radius`、`evaluate-skill`、`benchmark-checklist` を/);
});
