import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const skillRoot = fileURLToPath(new URL("../../skills/local/delivery-common/", import.meta.url));
const script = path.join(skillRoot, "scripts/read-phase-sections.mjs");
const run = (command, phase, ...args) => spawnSync(process.execPath, [command, "--", phase, ...args], {
  cwd: tmpdir(),
  encoding: "utf8",
  timeout: 5000,
});

function sections(output) {
  return new Map([...output.matchAll(/^<!-- (references\/[^\n]+) -->\n([\s\S]*?)(?=^<!-- references\/|$(?![\s\S]))/gm)]
    .map(([, label, body]) => [label, body.trimEnd()]));
}

test("the documented commands limit the two previously observed whole-file reads", () => {
  const skill = readFileSync(path.join(skillRoot, "SKILL.md"), "utf8");
  const targets = [
    ["Prepare and dispatch", "worker-dialogue.md", ["Assign the worker"]],
    ["Shared understanding and preflight", "risk-tier.md", [
      "Set and update the tier", "Rate the dimensions", "Assign the tier",
      "Sensitive paths", "Tier procedure", "Select the security review",
    ]],
  ];

  for (const [phase, reference, expected] of targets) {
    assert.ok(skill.includes(`node "<script>" -- "${phase}"`));
    const { status, stdout, stderr } = run(script, phase);
    assert.equal(status, 0, stderr);
    const blocks = sections(stdout);
    assert.equal(blocks.has("references/local-review.md#Blast radius"), false, phase);
    assert.equal(blocks.has("references/local-review.md#Remaining proof work"), false, phase);
    const label = `references/${reference}`;
    assert.equal(blocks.has(label), false);
    const actual = [...blocks].filter(([name]) => name.startsWith(`${label}#`));
    assert.deepEqual(actual.map(([name]) => name.slice(label.length + 1)), expected);

    const before = readFileSync(path.join(skillRoot, label), "utf8");
    for (const [, body] of actual) assert.ok(before.includes(body));
    assert.ok(actual.reduce((count, [, body]) => count + body.length, 0) < before.length);

    if (phase === "Prepare and dispatch") {
      assert.ok(blocks.has("references/completion.md#Progress record"));
      assert.ok(blocks.has("references/completion.md#Resume"));
    } else {
      assert.ok(blocks.has("references/worker-dialogue.md#Draft and ask"));
      assert.ok(blocks.has("references/worker-dialogue.md#Worker defaults"));
      assert.ok(blocks.has("references/completion.md#Progress record"));
      assert.ok(blocks.has("references/completion.md#Decision summary"));
      assert.equal(blocks.get("references/optional-workflows.md"),
        readFileSync(path.join(skillRoot, "references/optional-workflows.md"), "utf8").trimEnd());
    }
  }
});

test("preflight can reuse the preparation output in the same context", () => {
  const prepare = "Prepare and dispatch";
  const preflight = "Shared understanding and preflight";
  const prepared = run(script, prepare);
  const full = run(script, preflight);
  const additional = run(script, preflight, "--after-prepare");
  for (const result of [prepared, full, additional]) assert.equal(result.status, 0, result.stderr);

  const earlier = sections(prepared.stdout);
  const required = sections(full.stdout);
  const remaining = sections(additional.stdout);
  const shared = [...required].filter(([label, body]) => earlier.get(label) === body);
  assert.ok(shared.length > 0);
  for (const [label] of shared) assert.equal(remaining.has(label), false, label);
  for (const [label, body] of required) {
    assert.equal(remaining.get(label) ?? earlier.get(label), body, label);
  }
  assert.ok(additional.stdout.length < full.stdout.length);
  assert.ok(remaining.has("references/completion.md#Decision summary"));

  const invalid = run(script, prepare, "--after-prepare");
  assert.equal(invalid.status, 2, invalid.stderr);
  assert.equal(invalid.stdout, "");
});

function fixture(t, notes, rules = "Explicit approval.") {
  const root = mkdtempSync(path.join(tmpdir(), "delivery-phase-sections-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(path.join(root, "scripts"));
  mkdirSync(path.join(root, "references"));
  const command = path.join(root, "scripts/read-phase-sections.mjs");
  copyFileSync(script, command);
  writeFileSync(path.join(root, "SKILL.md"), [
    "Use [Notes](references/notes.md) and [Rules](references/rules.md).",
    "## Phase sections",
    "| Prepare and dispatch | Notes: Start; Rules: all |",
  ].join("\n"));
  writeFileSync(path.join(root, "references/notes.md"), notes);
  writeFileSync(path.join(root, "references/rules.md"), `# Rules\n\n## Approval\n\n${rules}\n`);
  return command;
}

test("includes nested headings and follows linked headings without repeating cycles", (t) => {
  const command = fixture(t, [
    "# Notes", "## Start", "[approval](rules.md#approval) and [more](#details)",
    "### Child", "````markdown", "```", "## Start", "[example](#not-a-link)", "````", "## Details",
    "See [start](#start) and [finish](#finish).", "## Handoff", "Required by the whole reference.",
    "## Finish", "Required by the linked section.", "## Later", "Beyond this phase.",
  ].join("\r\n"), "See [handoff](notes.md#handoff).");
  const { status, stdout, stderr } = run(command, "Prepare and dispatch");
  assert.equal(status, 0, stderr);
  const blocks = sections(stdout);
  assert.deepEqual([...blocks.keys()], [
    "references/notes.md#Start", "references/rules.md", "references/notes.md#Details",
    "references/notes.md#Handoff", "references/notes.md#Finish",
  ]);
  assert.equal([...stdout.matchAll(/^<!-- references\//gm)].length, blocks.size);
  assert.match(blocks.get("references/notes.md#Start"), /^### Child$/m);
  assert.equal(blocks.get("references/notes.md#Finish"), "## Finish\nRequired by the linked section.");
  assert.doesNotMatch(stdout, /Beyond this phase/);
});

test("reports missing and ambiguous headings before emitting any instructions", (t) => {
  for (const [source, error, rules] of [
    ["## Other", /Missing heading "Start" in references\/notes\.md/],
    ["## Start\n## Start", /Ambiguous heading "Start" in references\/notes\.md/],
    ["## Start\n[missing](#gone)", /Missing heading "gone" in references\/notes\.md/],
    ["## Start\n[details](#details)\n## Details\n[missing](#gone)", /Missing heading "gone" in references\/notes\.md/],
    ["## Start\n[duplicate](#a-b)\n## A B\n## A B!", /Ambiguous heading "a-b" in references\/notes\.md/],
    ["## Start", /Missing heading "gone" in references\/notes\.md/, "See [missing](notes.md#gone)."],
  ]) {
    const { status, stdout, stderr } = run(fixture(t, source, rules), "Prepare and dispatch");
    assert.equal(status, 3, stderr);
    assert.equal(stdout, "");
    assert.match(stderr, error);
  }
});
