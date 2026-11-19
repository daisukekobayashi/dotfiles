#!/usr/bin/env node
// Check a reviewer or worker report handed off through a file.
//
// Usage:
//   node check-report-handoff.mjs --kind review --reviewer <skill> \
//     --base <sha> --head <sha> --round <round> --report <path> [--show] [--sha256 <hex>]
//   node check-report-handoff.mjs --kind worker [--draft su|preflight] \
//     --base <sha> --head <sha> --round <round> --report <path> [--show] [--sha256 <hex>]
//
// The report is the full report, the line `<!-- report-summary v1 -->`, and
// the summary, ending with the line `<!-- end-report-summary -->`, as
// references/report-handoff.md defines. The summary is the text from the last
// delimiter line. This script checks that:
// - the report is an absolute path of [A-Za-z0-9/._-], or on Windows a
//   drive-qualified one such as C:\\dir\\file.md of [A-Za-z0-9\\._-], in normal
//   form, a regular file, and not a symbolic link, and its parent directory is
//   its own real path, owned by the current user, and closed to group and
//   others (mode 700); on Windows, where this cannot be verified, the report
//   is invalid;
// - the full report is non-empty and, for a review, has the reviewer's Output
//   headings;
// - every summary label appears once, every required label appears, and no
//   unknown label appears;
// - Base, Head, Round, and Report equal the arguments, and the reviewer,
//   Completion, and Verdict take an allowed value;
// - every label has a value or indented items;
// - a review's summary Verdict equals the full report's, it lists as many
//   findings of each severity and tag as the full report, and, for
//   change-security-review, as many SECD IDs as deferred candidates; it does
//   not check which finding each item is;
// - each required Output section has content, and headings start at column 0;
// - a shared understanding draft has an Overview and a preflight draft a Tier;
// - with --sha256, the file still has the recorded hash.
//
// On success it prints `valid sha256=<hex> bytes=<size>` and, with --show, the
// summary after it. Record that line, and pass the hash with --sha256 before
// reopening the report.
//
// Exit status:
//   0  the report is valid
//   2  usage error
//   3  the report is missing or invalid; the reason is on stderr as
//      `invalid: <reason>`
// Any other status, including 1, which node uses for a missing script or an
// uncaught error, means the check could not run.

import { createHash } from "node:crypto";
import { lstatSync, readFileSync, realpathSync, statSync } from "node:fs";
import path from "node:path";

const DELIMITER = "<!-- report-summary v1 -->";
const END = "<!-- end-report-summary -->";
const POSIX_PATH = /^\/[A-Za-z0-9/._-]+$/;
const WIN32_PATH = /^[A-Za-z]:\\[A-Za-z0-9\\._-]+$/;

// Returns why a report path is unacceptable on the platform, or null.
function reportPathError(report, platform = process.platform) {
  const [pattern, flavor, form] = platform === "win32"
    ? [WIN32_PATH, path.win32, "a drive-qualified absolute path of [A-Za-z0-9\\._-] in normal form"]
    : [POSIX_PATH, path.posix, "an absolute path of [A-Za-z0-9/._-] in normal form"];
  return pattern.test(report) && flavor.normalize(report) === report ? null : `report path is not ${form}`;
}

const invalid = (reason) => {
  process.stderr.write(`invalid: ${reason}\n`);
  process.exit(3);
};

const REVIEWERS = {
  "change-review": {
    prefix: "CR",
    verdicts: ["Request changes", "Comment", "Approve"],
    headings: ["**Findings**", "**Review Target**", "**Test Gaps**", "**Coverage and Residual Risk**", "**Verdict**"],
    findings: "**Findings**",
  },
  "change-adversarial-review": {
    prefix: "ADV",
    verdicts: ["Do not ship", "Needs attention", "No material blocker found"],
    headings: ["**Verdict**", "**Review Target**", "**Material Findings**", "**Coverage and Residual Risk**"],
    findings: "**Material Findings**",
  },
  "change-security-review": {
    prefix: "SEC",
    verdicts: ["Block", "Needs attention", "No material security finding"],
    headings: ["**Verdict**", "**Findings**", "**Deferred Candidates**", "**Threat Model**", "**Review Target**", "**Coverage and Residual Risk**"],
    findings: "**Findings**",
    deferred: "**Deferred Candidates**",
  },
};

const LABELS = {
  review: ["Target", "Base", "Head", "Round", "Reviewer", "Completion", "Verdict", "Findings",
    "Deferred candidates", "Confirmed fixes", "Unverified coverage", "Report"],
  worker: ["Target", "Base", "Head", "Round", "Completion", "Tier", "Overview", "Files changed",
    "Verification", "Questions", "Defaults chosen", "Blockers", "Follow-ups", "Report"],
};

function main() {
const usage = () => {
  process.stderr.write("usage: check-report-handoff.mjs --kind review|worker [--reviewer <skill>] [--draft su|preflight] --base <sha> --head <sha> --round <round> --report <path> [--show] [--sha256 <hex>]\n");
  process.exit(2);
};

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const name = argv[i];
  if (name === "--show") { args.show = true; continue; }
  if (!["--kind", "--reviewer", "--draft", "--base", "--head", "--round", "--report", "--sha256"].includes(name)) usage();
  if (args[name.slice(2)] !== undefined || i + 1 >= argv.length) usage();
  args[name.slice(2)] = argv[++i];
}
if (!["review", "worker"].includes(args.kind) || !args.base || !args.head || !args.round || !args.report) usage();
if (args.kind === "review" ? !REVIEWERS[args.reviewer] || args.draft : args.reviewer) usage();
if (args.draft !== undefined && !["su", "preflight"].includes(args.draft)) usage();

const report = args.report;
const pathError = reportPathError(report);
if (pathError) invalid(pathError);
let info;
try {
  info = lstatSync(report);
} catch {
  invalid("missing file");
}
if (!info.isFile()) invalid("report is not a regular file");
if (process.platform === "win32") {
  invalid("report directory privacy cannot be verified on Windows; run the delivery on a POSIX host such as WSL");
} else {
  const parent = path.dirname(report);
  if (realpathSync(parent) !== parent) invalid("report directory is not its own real path");
  const dir = statSync(parent);
  if (dir.uid !== process.getuid()) invalid("report directory is not owned by the current user");
  if (dir.mode & 0o077) invalid("report directory is open to group or others; create it with mkdir -m 700");
}

const bytes = readFileSync(report);
const sha256 = createHash("sha256").update(bytes).digest("hex");
if (args.sha256 !== undefined && args.sha256 !== sha256) invalid("report changed since its hash was recorded");

const lines = bytes.toString("utf8").replace(/\r$/gm, "").split("\n");
if (lines.at(-1) === "") lines.pop();
if (lines.length === 0) invalid("empty file");
const start = lines.lastIndexOf(DELIMITER);
if (start < 0) invalid("no summary");
if (lines.at(-1) !== END) invalid("truncated");
const body = lines.slice(0, start);
const summary = lines.slice(start + 1, -1);
if (!body.some((line) => line.trim())) invalid("no full report");

// Parse the summary: top-level `- Label: value` lines own the indented lines after them.
const fields = new Map();
let current;
for (const line of summary) {
  const top = /^- ([A-Za-z][A-Za-z -]*):(?: (.*))?$/.exec(line);
  if (top) {
    const [, label, value = ""] = top;
    if (!LABELS[args.kind].includes(label)) invalid(`unknown label ${label}`);
    if (fields.has(label)) invalid(`duplicate label ${label}`);
    current = { value: value.trim(), children: [] };
    fields.set(label, current);
  } else if (/^\s+\S/.test(line) && current) {
    current.children.push(line);
  } else if (line.trim()) {
    invalid(`unexpected summary line ${JSON.stringify(line.slice(0, 80))}`);
  }
}
for (const label of LABELS[args.kind]) {
  if (!fields.has(label)) invalid(`missing ${label}`);
  const field = fields.get(label);
  if (!field.value && !field.children.some((child) => child.trim())) invalid(`empty ${label}`);
}
const value = (label) => fields.get(label).value;
const isNone = (field) => (field.value === "None" && field.children.length === 0)
  || (field.value === "" && field.children.length === 1 && /^\s+- None$/.test(field.children[0]));

for (const [label, expected] of [["Base", args.base], ["Head", args.head], ["Round", args.round], ["Report", report]]) {
  if (value(label) !== expected) invalid(`${label} is not ${expected}`);
}

// Lines of one bold-headed section of the full report. A heading starts at
// column 0, so an indented quote of a heading inside a finding is content.
const isHeading = (line) => /^\*\*[^*]+\*\*$/.test(line.trimEnd());
const sectionLines = (heading) => {
  const begin = body.findIndex((line) => line.trimEnd() === heading);
  if (begin < 0) return [];
  const rest = body.slice(begin + 1);
  const end = rest.findIndex(isHeading);
  return end < 0 ? rest : rest.slice(0, end);
};
const section = (heading) => sectionLines(heading).filter((line) => line.startsWith("- "));
const plain = (text) => text.replaceAll("*", "").trim();
const ids = (field, pattern) => {
  if (isNone(field)) return [];
  if (field.value) invalid(`list value must be None or indented items: ${JSON.stringify(field.value.slice(0, 80))}`);
  const seen = new Map();
  for (const child of field.children) {
    const match = pattern.exec(child);
    if (!match) invalid(`malformed item ${JSON.stringify(child.trim().slice(0, 80))}`);
    if (seen.has(match[1])) invalid(`duplicate ID ${match[1]}`);
    seen.set(match[1], match.slice(1));
  }
  return [...seen.values()];
};

if (args.kind === "review") {
  const reviewer = REVIEWERS[args.reviewer];
  for (const heading of reviewer.headings) {
    if (!body.some((line) => line.trimEnd() === heading)) invalid(`full report lacks ${heading}`);
    if (!sectionLines(heading).some((line) => line.trim())) invalid(`full report section ${heading} is empty`);
  }
  if (value("Reviewer") !== args.reviewer && !value("Reviewer").startsWith(`${args.reviewer},`)) invalid(`Reviewer is not ${args.reviewer}`);
  if (value("Completion") !== "complete") invalid("Completion is not complete");
  if (!reviewer.verdicts.includes(plain(value("Verdict")))) invalid(`Verdict is not one of ${reviewer.verdicts.join(", ")}`);
  const bodyVerdict = section("**Verdict**")[0];
  if (!bodyVerdict || plain(bodyVerdict.slice(2)) !== plain(value("Verdict"))) invalid("summary Verdict differs from the full report");
  const findingPattern = new RegExp(`^\\s+- (${reviewer.prefix}\\d+) \\[(Critical|High|Medium|Low)\\] (introduced|worsened|pre-existing) - (.+)$`);
  const findings = ids(fields.get("Findings"), findingPattern);
  const reported = section(reviewer.findings).filter((line) => /^- (?:\*\*)?\[(?:Critical|High|Medium|Low)\]/.test(line));
  // Counts per severity and tag; which finding each summary item is stays unchecked.
  const count = (pairs) => pairs.reduce((map, key) => map.set(key, (map.get(key) ?? 0) + 1), new Map());
  const summaryCounts = count(findings.map(([, severity, tag]) => `[${severity}] ${tag}`));
  const bodyCounts = count(reported.map((line) => {
    const severity = /\[(Critical|High|Medium|Low)\]/.exec(line)[1];
    const tag = [...line.matchAll(/\b(introduced|worsened|pre-existing)\b/g)].at(-1)?.[1] ?? "no tag";
    return `[${severity}] ${tag}`;
  }));
  for (const key of new Set([...summaryCounts.keys(), ...bodyCounts.keys()])) {
    const listed = summaryCounts.get(key) ?? 0;
    const found = bodyCounts.get(key) ?? 0;
    if (listed !== found) invalid(`summary lists ${listed} ${key} findings; the full report has ${found}`);
  }
  const deferred = ids(fields.get("Deferred candidates"), /^\s+- (SECD\d+) - \S/);
  const candidates = reviewer.deferred ? section(reviewer.deferred).filter((line) => / [-—] /.test(line)).length : 0;
  if (deferred.length !== candidates) invalid(`summary lists ${deferred.length} deferred candidates; the full report has ${candidates}`);
} else {
  if (!["complete", "question", "blocked"].includes(value("Completion"))) invalid("Completion is not complete, question, or blocked");
  if (args.draft === "su" && isNone(fields.get("Overview"))) invalid("shared understanding draft has no Overview");
  if (args.draft === "preflight" && isNone(fields.get("Tier"))) invalid("preflight draft has no Tier");
}

process.stdout.write(`valid sha256=${sha256} bytes=${bytes.length}\n`);
if (args.show) process.stdout.write(`${[DELIMITER, ...summary, END].join("\n")}\n`);
}

// Always validate: this file is only ever run as a command, however it is invoked.
main();
