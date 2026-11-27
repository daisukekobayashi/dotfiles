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
// Named, not linked: a link would make the export add the index or a leaf as a required dependency.
const noPrincipleLink = /\]\([^)]*principles?(-[a-z-]+)?\/SKILL\.md/;

test("delivery-common applies the restraining principles to implementation and fixes", async () => {
  const skill = await readText(path.join(commonDir, "SKILL.md"));
  const rule = flat(section(skill, "## Restraint in Implementation and Fixes"));

  assert.match(rule, /In the implementation and in each fix of a local or hosted finding, remove before you add and make the smallest diff that solves the problem, within the task's scope; a removal outside the requested change becomes a follow-up candidate\./);
  assert.match(rule, /For each mechanism, step, or guard the work adds, the full report gives one line on why removal or a smaller change was insufficient, and the coordinator checks those lines as it checks listed defaults\./);
  assert.match(rule, /Fix a material finding or a failed verification at the first place the system went wrong, not where it surfaced, and fix its whole class under Local Review's Bug class rule\./);
  assert.match(rule, /Under the `durable` stance, build a new requirement into the design as if it had been foundational; under `conservative`, record that design as a follow-up proposal\./);
  assert.match(rule, /When the `principles` index is installed, read the applicable leaf in full \(`principle-subtract-before-you-add`, `principle-laziness-protocol`, `principle-fix-root-causes`, or `principle-redesign-from-first-principles`\) and name the principle on the line that reports the decision it changed; these rules hold without it, and it is never a prerequisite\./);
  assert.doesNotMatch(skill, noPrincipleLink);

  const anchor = /\[Restraint in Implementation and Fixes\]\(\.\.\/SKILL\.md#restraint-in-implementation-and-fixes\)/;
  const dialogue = flat(section(await readText(path.join(commonDir, "references", "worker-dialogue.md")), "## Preflight and implementation"));
  assert.match(dialogue, anchor);
  const delegation = flat(await readText(path.join(commonDir, "references", "phase-delegation.md")));
  // The check runs once on what the cycle applied, not at each in-cycle edit point.
  assert.match(delegation, /and the \[restraint lines\]\(\.\.\/SKILL\.md#restraint-in-implementation-and-fixes\) of the fixes the cycle applied\. It compares them with the additions in the delta the cycle pushed, read from Git, and assesses each added mechanism, step, or guard without an adequate line as a local finding under Local Review's Assess findings\./);
  assert.match(delegation, /its full report holds the component skill's unchanged final report or output, plus a hosted cycle's restraint lines\./);
  assert.doesNotMatch(delegation, /in a prepared report, the restraint lines/);
  const localReview = await readText(path.join(commonDir, "references", "local-review.md"));
  assert.match(flat(section(localReview, "## Assess findings")), anchor);
});

test("Local Review records a recurring finding class as a premise before the next fix", async () => {
  const localReview = await readText(path.join(commonDir, "references", "local-review.md"));
  const assess = flat(section(localReview, "## Assess findings"));

  assert.match(assess, /\*\*Recurrence:\*\* When a new finding shares its finding class with a finding from an earlier round, counting local and hosted rounds as one sequence, apply `principle-attack-the-premise` before the next fix\./);
  assert.match(assess, /Record a `\[premise P<n>\]` progress-record entry with both findings' round, finding, and disposition ids and quotes, the finding class, the premise their fixes share \(or, when the earlier finding had no fix, the premise of the approach they share, from the available evidence\), the observation that tested it and its result, the options, including removing the responsibility behind them, and the chosen option and who chose it\./);
  assert.match(assess, /The affected dispositions reference its id, and an update reuses it\./);
  assert.match(assess, /Choose an option yourself only within the agreed decisions, scope, and contracts; otherwise leave it open for the user\./);
  assert.match(assess, /When the `principles` index is installed, read the leaf in full and name the principle on the line that reports the decision it changed; the global rule on recurring failures gives the short form, and neither is a prerequisite\./);
  // Both bullets must exist before their order means anything.
  const repeats = assess.indexOf("**Repeats:** A finding already dispositioned in an earlier round is a `duplicate`");
  const recurrence = assess.indexOf("**Recurrence:**");
  assert.ok(repeats !== -1 && recurrence !== -1, "Assess findings keeps both Repeats and Recurrence");
  assert.ok(repeats < recurrence, "Recurrence follows Repeats");
  const limit = flat(localReview.slice(localReview.indexOf("At the round limit")));
  assert.match(limit, /repeated in one area or approach, under the same condition as Recurrence \(apply it and report its `\[premise P<n>\]` entries, with revisiting the design through design-preflight among the options; still-open duplicates keep their dispositions\)/);
  const delegation = flat(await readText(path.join(commonDir, "references", "phase-delegation.md")));
  assert.match(delegation, /applying its Recurrence first, and sends the settled dispositions\. A prepared fix for a finding in a recurring class is not settled as `applied`; the worker removes its edit, and the fix is redone only after the `\[premise P<n>\]` decision\./);
  assert.doesNotMatch(localReview, noPrincipleLink);

  const completion = flat(await readText(path.join(commonDir, "references", "completion.md")));
  assert.match(completion, /follow-up candidates, premise entries under Local Review's Recurrence, optional workflow runs/);
  assert.match(completion, /- each `\[premise P<n>\]` entry whose option the coordinator chose itself under Local Review's Recurrence, with its premise and the chosen option, or `none`\./);
});

test("Follow-up candidates recommend a structural safeguard for a recurring finding class", async () => {
  const completion = await readText(path.join(commonDir, "references", "completion.md"));
  const followUps = flat(section(completion, "## Follow-up candidates"));

  assert.match(followUps, /- it is an exploitable security vulnerability; - the same finding class recurred at least twice across rounds or deliveries, shown by a `\[premise P<n>\]` entry or a cited earlier issue, PR, or record, and the candidate proposes a structural safeguard outside this task's scope: where it goes, removing the mechanism behind the failure before adding a small safeguard near its cause, such as a type, boundary check, test, or lint rule, and how it would reject the observed case\./);
  assert.match(followUps, /When the `principles` index is installed, read its `principle-encode-lessons-in-structure` leaf in full to shape the proposal and name the principle on the line that gives the recommendation; the criterion holds without it, and it is never a prerequisite; - the user asked for it\./);
  // Delivery only proposes the safeguard; it never runs `correct` or creates an unapproved candidate.
  assert.match(followUps, /Ask which to create, and pass only approved candidates with their evidence and source links to the calling workflow's create skill\./);
  assert.doesNotMatch(followUps, /`correct`/);
  assert.doesNotMatch(completion, noPrincipleLink);
});

test("recommendations consider removal and a smaller option without changing the stance baseline", async () => {
  const check = flat(await readText(path.join(localRoot, "shared-understanding", "SKILL.md")));
  assert.match(check, /Compare every recommended option with removal and a smaller option, keeping the baseline above; when you still recommend the larger one, its reason says in one line why the smaller one is insufficient\./);
  assert.match(check, /When the `principles` index is installed, read its `principle-subtract-before-you-add` and `principle-laziness-protocol` leaves in full and name the principle in the reason it changed\./);
  assert.match(check, /The overall recommendation favors long-term maintainability unless the user's request states another stance/);

  const preflight = await readText(path.join(localRoot, "design-preflight", "SKILL.md"));
  const brief = flat(section(preflight, "## Brief To Give Grilling"));
  assert.match(brief, /Compare every recommended answer with removal and a smaller change toward the stance's baseline; when you still recommend the larger one, say in one line why the smaller one is insufficient\. When the `principles` index is installed, read its `principle-subtract-before-you-add` and `principle-laziness-protocol` leaves in full and name the principle in the reason it changed\./);
  assert.match(brief, /For durable: .*Build a new requirement into the design as if it had been foundational; when the `principles` index is installed, read its `principle-redesign-from-first-principles` leaf in full and name it in the reason it changed\./);
  assert.match(preflight, /"Simplest" means the simplest end state, not the smallest diff\./);
  for (const text of [check, preflight]) assert.doesNotMatch(text, noPrincipleLink);
});

test("ADR 0001 maps the restraining principles to their delivery phases in both languages", async () => {
  const adr = await readText(path.join(repoRoot, "docs", "adr", "0001-pstack-principles-in-delivery.md"));
  const adrJa = await readText(path.join(repoRoot, "docs", "adr", "0001-pstack-principles-in-delivery.ja.md"));
  for (const phase of [
    "Shared understanding and preflight recommendations",
    "Preflight under `durable`, and implementation",
    "Implementation and fixes",
    "Review assessment",
  ]) assert.match(adr, new RegExp(`^\\| ${phase.replace(/[.*+?^${}()|[\]\\`]/g, "\\$&")} \\|`, "m"), phase);
  for (const phase of ["Shared understanding と preflight の推奨", "`durable` の preflight と実装", "実装と修正", "レビューの評価"]) {
    assert.match(adrJa, new RegExp(`^\\| ${phase.replace(/[.*+?^${}()|[\]\\`]/g, "\\$&")} \\|`, "m"), phase);
  }
  const rows = (text) => text.split("\n").filter((line) => line.startsWith("| ")).length;
  assert.equal(rows(adr), rows(adrJa), "the English and Japanese phase mappings have the same rows");
});
