import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const skillRoot = fileURLToPath(new URL("../../skills/local/delivery-common/", import.meta.url));
const script = path.join(skillRoot, "scripts/read-phase-sections.mjs");
const run = (command, phase) => spawnSync(process.execPath, [command, "--", phase], {
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
      assert.equal(blocks.get("references/optional-workflows.md"),
        readFileSync(path.join(skillRoot, "references/optional-workflows.md"), "utf8").trimEnd());
    }
  }
});

function fixture(t, notes) {
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
  writeFileSync(path.join(root, "references/rules.md"), "# Rules\n\n## Approval\n\nExplicit approval.\n");
  return command;
}

test("includes nested headings and deduplicates links to sections already selected", (t) => {
  const command = fixture(t, [
    "# Notes", "## Start", "[approval](rules.md#approval) and [more](#details)",
    "### Child", "````markdown", "```", "## Start", "[example](#not-a-link)", "````", "## Details",
    "Required by the start step.", "## Later", "Beyond this phase.",
  ].join("\r\n"));
  const { status, stdout, stderr } = run(command, "Prepare and dispatch");
  assert.equal(status, 0, stderr);
  const blocks = sections(stdout);
  assert.deepEqual([...blocks.keys()], ["references/notes.md#Start", "references/rules.md", "references/notes.md#Details"]);
  assert.match(blocks.get("references/notes.md#Start"), /^### Child$/m);
  assert.equal(blocks.get("references/notes.md#Details"), "## Details\nRequired by the start step.");
  assert.doesNotMatch(stdout, /Beyond this phase/);
});

test("reports missing and ambiguous headings before emitting any instructions", (t) => {
  for (const [source, error] of [
    ["## Other", /Missing heading "Start" in references\/notes\.md/],
    ["## Start\n## Start", /Ambiguous heading "Start" in references\/notes\.md/],
    ["## Start\n[missing](#gone)", /Missing heading "gone" in references\/notes\.md/],
    ["## Start\n[duplicate](#a-b)\n## A B\n## A B!", /Ambiguous heading "a-b" in references\/notes\.md/],
  ]) {
    const { status, stdout, stderr } = run(fixture(t, source), "Prepare and dispatch");
    assert.equal(status, 3, stderr);
    assert.equal(stdout, "");
    assert.match(stderr, error);
  }
});
