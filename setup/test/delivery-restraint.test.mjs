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
  assert.match(rule, /The `principle-subtract-before-you-add`, `principle-laziness-protocol`, `principle-fix-root-causes`, and `principle-redesign-from-first-principles` leaves of the `principles` index give these rules in full when installed; they are never a prerequisite\./);
  assert.doesNotMatch(skill, noPrincipleLink);

  const anchor = /\[Restraint in Implementation and Fixes\]\(\.\.\/SKILL\.md#restraint-in-implementation-and-fixes\)/;
  const dialogue = flat(section(await readText(path.join(commonDir, "references", "worker-dialogue.md")), "## Preflight and implementation"));
  assert.match(dialogue, anchor);
  const localReview = await readText(path.join(commonDir, "references", "local-review.md"));
  assert.match(flat(section(localReview, "## Assess findings")), anchor);
});

test("Local Review records a recurring finding class as a premise before the next fix", async () => {
  const localReview = await readText(path.join(commonDir, "references", "local-review.md"));
  const assess = flat(section(localReview, "## Assess findings"));

  assert.match(assess, /\*\*Recurrence:\*\* When a new finding shares its finding class with a finding from an earlier round, counting local and hosted rounds as one sequence, apply `principle-attack-the-premise` before the next fix\./);
  assert.match(assess, /Record a `\[premise P<n>\]` progress-record entry that quotes both rounds' findings, writes down the premise their fixes share and the observation that tested it, and lists the options, including removing the responsibility behind them\./);
  assert.match(assess, /Choose an option yourself only within the agreed decisions, scope, and contracts, and record that you chose it; otherwise leave it open for the user\./);
  assert.match(assess, /The leaf of the `principles` index gives this rule in full when installed, and the global rule on recurring failures gives its short form; neither is a prerequisite\./);
  assert.ok(assess.indexOf("**Repeats:**") < assess.indexOf("**Recurrence:**"), "Recurrence follows Repeats");
  assert.match(assess, /repeated in one area or approach \(apply Recurrence and report its `\[premise P<n>\]` entries, with revisiting the design through design-preflight among the options\)/);
  assert.doesNotMatch(localReview, noPrincipleLink);

  const completion = flat(await readText(path.join(commonDir, "references", "completion.md")));
  assert.match(completion, /follow-up candidates, premise entries under Local Review's Recurrence, optional workflow runs/);
  assert.match(completion, /- each `\[premise P<n>\]` entry whose option the coordinator chose itself under Local Review's Recurrence, with its premise and the chosen option, or `none`\./);
});

test("recommendations consider removal and a smaller option without changing the stance baseline", async () => {
  const check = flat(await readText(path.join(localRoot, "shared-understanding", "SKILL.md")));
  assert.match(check, /Before recommending an option that adds a mechanism, step, or layer, consider removing complexity and a smaller option; when you still recommend the larger one, its reason says in one line why the smaller one is insufficient\./);
  assert.match(check, /The `principle-subtract-before-you-add` and `principle-laziness-protocol` leaves of the `principles` index give these rules in full when installed\./);
  assert.match(check, /The overall recommendation favors long-term maintainability unless the user's request states another stance/);

  const preflight = await readText(path.join(localRoot, "design-preflight", "SKILL.md"));
  const brief = flat(section(preflight, "## Brief To Give Grilling"));
  assert.match(brief, /Before recommending an addition, consider removal and a smaller change toward the stance's baseline; when you still recommend the larger one, say in one line why the smaller one is insufficient \(`principle-subtract-before-you-add` and `principle-laziness-protocol` in the `principles` index, when installed\)\./);
  assert.match(brief, /For durable: .*Build a new requirement into the design as if it had been foundational \(`principle-redesign-from-first-principles`, when installed\)\./);
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
