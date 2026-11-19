#!/usr/bin/env node
// Check a reviewer or worker report handed off through a file.
//
// Usage:
//   node check-report-handoff.mjs --kind review --reviewer <skill> \
//     --base <sha> --head <sha> --round <round> --report <path> [--show] [--sha256 <hex>]
//   node check-report-handoff.mjs --kind worker [--draft su|preflight] \
//     --base <sha> --head <sha> --round <round> --report <path> [--show] [--sha256 <hex>]
//
// A report is the full report, a delimiter line, and a summary part, ending
// with the line `<!-- end-report-summary -->`, as references/report-handoff.md
// defines. The summary part is the text from the last delimiter line:
// - a review report uses `<!-- report-summary v2 -->` and a fenced json review
//   block; the check derives the review summary from the block and never reads
//   the full report's headings or bullets;
// - a worker report uses `<!-- report-summary v1 -->` and the worker summary.
// This script checks that:
// - the report is an absolute path of [A-Za-z0-9/._-], or on Windows a
//   drive-qualified one such as C:\\dir\\file.md of [A-Za-z0-9\\._-], in normal
//   form, a regular file, and not a symbolic link, and its parent directory is
//   its own real path, owned by the current user, and closed to group and
//   others (mode 700); on Windows, where this cannot be verified, the report
//   is invalid;
// - the full report is non-empty;
// - for a review, a v1 summary is rejected, and the block is one JSON object,
//   with no member repeated in any object, and exactly the block's keys, each
//   of its type; base, head, round,
//   report, and reviewer equal the arguments; completion is complete; the
//   verdict and each finding's severity are allowed for the reviewer; finding
//   IDs run <prefix>1..n in order, as SECD1..n for change-security-review's
//   deferred candidates, which other reviewers leave empty; every string is
//   one non-empty line without control characters; and no two findings, or
//   two deferred candidates, share a location and title;
// - for a worker, every summary label appears once, every required label
//   appears, no unknown label appears, every label has a value or indented
//   items, Base, Head, Round, and Report equal the arguments, Completion takes
//   an allowed value, and a shared understanding draft has an Overview and a
//   preflight draft a Tier;
// - with --sha256, the file still has the recorded hash.
//
// On success it prints `valid sha256=<hex> bytes=<size>` and, with --show, the
// summary after it: for a review, the summary derived from the block; for a
// worker, the summary part as written. Record that line, and pass the hash with
// --sha256 before reopening the report.
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

const WORKER_DELIMITER = "<!-- report-summary v1 -->";
const REVIEW_DELIMITER = "<!-- report-summary v2 -->";
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
    severities: ["High", "Medium", "Low"],
  },
  "change-adversarial-review": {
    prefix: "ADV",
    verdicts: ["Do not ship", "Needs attention", "No material blocker found"],
    severities: ["High", "Medium"],
  },
  "change-security-review": {
    prefix: "SEC",
    verdicts: ["Block", "Needs attention", "No material security finding"],
    severities: ["Critical", "High", "Medium", "Low"],
    deferred: "SECD",
  },
};
const TAGS = ["introduced", "worsened", "pre-existing"];
const COMPLETIONS = ["complete", "partial", "failed"];
const BLOCK_KEYS = ["target", "base", "head", "round", "reviewer", "route", "completion", "verdict",
  "findings", "deferredCandidates", "confirmedFixes", "unverifiedCoverage", "report"];
const FINDING_KEYS = ["id", "severity", "tag", "location", "title"];
const CANDIDATE_KEYS = ["id", "location", "title"];

const WORKER_LABELS = ["Target", "Base", "Head", "Round", "Completion", "Tier", "Overview", "Files changed",
  "Verification", "Questions", "Defaults chosen", "Blockers", "Follow-ups", "Report"];

// One non-empty line: no control characters, so a rendered value cannot add a summary line.
const isLine = (text) => typeof text === "string" && text.trim() !== "" && !/[\u0000-\u001f\u007f\u2028\u2029]/.test(text);

const isPlainObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

function checkKeys(object, keys, where) {
  if (!isPlainObject(object)) invalid(`${where} is not an object`);
  for (const key of Object.keys(object)) if (!keys.includes(key)) invalid(`${where} has unknown key ${key}`);
  for (const key of keys) if (!Object.hasOwn(object, key)) invalid(`${where} lacks ${key}`);
}

function checkLine(value, where) {
  if (!isLine(value)) invalid(`${where} is not one non-empty line of text`);
}

// Validates a list of findings or deferred candidates and returns it.
function checkItems(items, keys, prefix, where, check) {
  if (!Array.isArray(items)) invalid(`${where} is not an array`);
  const pairs = new Set();
  items.forEach((item, index) => {
    const at = `${where}[${index}]`;
    checkKeys(item, keys, at);
    for (const key of keys) checkLine(item[key], `${at}.${key}`);
    if (item.id !== `${prefix}${index + 1}`) invalid(`${at}.id is not ${prefix}${index + 1}`);
    check?.(item, at);
    const pair = JSON.stringify([item.location.trim(), item.title.trim()]);
    if (pairs.has(pair)) invalid(`${at} repeats the location and title of an earlier item`);
    pairs.add(pair);
  });
  return items;
}

// Returns the first member name repeated within one object of valid JSON text, or null.
// JSON.parse keeps only the last value of a repeated member, which would hide the others.
function repeatedMember(text) {
  const objects = [];
  let expectKey = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === "\"") {
      let end = i + 1;
      while (text[end] !== "\"") end += text[end] === "\\" ? 2 : 1;
      if (expectKey) {
        const key = JSON.parse(text.slice(i, end + 1));
        if (objects.at(-1).has(key)) return key;
        objects.at(-1).add(key);
        expectKey = false;
      }
      i = end;
    } else if (char === "{") {
      objects.push(new Set());
      expectKey = true;
    } else if (char === "[") {
      objects.push(null);
    } else if (char === "}" || char === "]") {
      objects.pop();
    } else if (char === ",") {
      expectKey = objects.at(-1) instanceof Set;
    }
  }
  return null;
}

// Validates the review block against the arguments and returns the summary derived from it.
function reviewSummary(part, args) {
  const reviewer = REVIEWERS[args.reviewer];
  if (part[0] !== "```json" || part.length < 2 || part.at(-1) !== "```") invalid("review block is not one fenced json block");
  const text = part.slice(1, -1).join("\n");
  let block;
  try {
    block = JSON.parse(text);
  } catch (error) {
    invalid(`review block is not valid JSON: ${error.message}`);
  }
  const repeated = repeatedMember(text);
  if (repeated !== null) invalid(`review block repeats member ${JSON.stringify(repeated)}`);
  checkKeys(block, BLOCK_KEYS, "review block");
  for (const key of ["target", "base", "head", "round", "reviewer", "route", "completion", "verdict", "report"]) {
    checkLine(block[key], key);
  }
  for (const [key, expected] of [["base", args.base], ["head", args.head], ["round", args.round], ["report", args.report], ["reviewer", args.reviewer]]) {
    if (block[key] !== expected) invalid(`${key} is not ${expected}`);
  }
  if (!COMPLETIONS.includes(block.completion)) invalid(`completion is not one of ${COMPLETIONS.join(", ")}`);
  if (block.completion !== "complete") invalid("completion is not complete");
  if (!reviewer.verdicts.includes(block.verdict)) invalid(`verdict is not one of ${reviewer.verdicts.join(", ")}`);
  const findings = checkItems(block.findings, FINDING_KEYS, reviewer.prefix, "findings", (item, at) => {
    if (!reviewer.severities.includes(item.severity)) invalid(`${at}.severity is not one of ${reviewer.severities.join(", ")}`);
    if (!TAGS.includes(item.tag)) invalid(`${at}.tag is not one of ${TAGS.join(", ")}`);
  });
  if (!reviewer.deferred && Array.isArray(block.deferredCandidates) && block.deferredCandidates.length) {
    invalid(`deferredCandidates must be empty for ${args.reviewer}`);
  }
  const candidates = checkItems(block.deferredCandidates, CANDIDATE_KEYS, reviewer.deferred ?? "", "deferredCandidates");
  for (const key of ["confirmedFixes", "unverifiedCoverage"]) {
    if (!Array.isArray(block[key])) invalid(`${key} is not an array`);
    block[key].forEach((text, index) => checkLine(text, `${key}[${index}]`));
  }

  const list = (label, lines) => (lines.length ? [`- ${label}:`, ...lines.map((line) => `  - ${line}`)] : [`- ${label}: None`]);
  return [
    `- Target: ${block.target}`,
    `- Base: ${block.base}`,
    `- Head: ${block.head}`,
    `- Round: ${block.round}`,
    `- Reviewer: ${block.reviewer}, ${block.route}`,
    `- Completion: ${block.completion}`,
    `- Verdict: ${block.verdict}`,
    ...list("Findings", findings.map((f) => `${f.id} [${f.severity}] ${f.tag} - ${f.location} - ${f.title}`)),
    ...list("Deferred candidates", candidates.map((c) => `${c.id} - ${c.location} - ${c.title}`)),
    ...list("Confirmed fixes", block.confirmedFixes),
    ...list("Unverified coverage", block.unverifiedCoverage),
    `- Report: ${block.report}`,
  ];
}

// Validates a worker summary part against the arguments.
function checkWorkerSummary(summary, args) {
  // Top-level `- Label: value` lines own the indented lines after them.
  const fields = new Map();
  let current;
  for (const line of summary) {
    const top = /^- ([A-Za-z][A-Za-z -]*):(?: (.*))?$/.exec(line);
    if (top) {
      const [, label, value = ""] = top;
      if (!WORKER_LABELS.includes(label)) invalid(`unknown label ${label}`);
      if (fields.has(label)) invalid(`duplicate label ${label}`);
      current = { value: value.trim(), children: [] };
      fields.set(label, current);
    } else if (/^\s+\S/.test(line) && current) {
      current.children.push(line);
    } else if (line.trim()) {
      invalid(`unexpected summary line ${JSON.stringify(line.slice(0, 80))}`);
    }
  }
  for (const label of WORKER_LABELS) {
    if (!fields.has(label)) invalid(`missing ${label}`);
    const field = fields.get(label);
    if (!field.value && !field.children.some((child) => child.trim())) invalid(`empty ${label}`);
  }
  const value = (label) => fields.get(label).value;
  const isNone = (field) => (field.value === "None" && field.children.length === 0)
    || (field.value === "" && field.children.length === 1 && /^\s+- None$/.test(field.children[0]));

  for (const [label, expected] of [["Base", args.base], ["Head", args.head], ["Round", args.round], ["Report", args.report]]) {
    if (value(label) !== expected) invalid(`${label} is not ${expected}`);
  }
  if (!["complete", "question", "blocked"].includes(value("Completion"))) invalid("Completion is not complete, question, or blocked");
  if (args.draft === "su" && isNone(fields.get("Overview"))) invalid("shared understanding draft has no Overview");
  if (args.draft === "preflight" && isNone(fields.get("Tier"))) invalid("preflight draft has no Tier");
}

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
  if (args.kind === "review" ? !Object.hasOwn(REVIEWERS, args.reviewer) || args.draft : args.reviewer) usage();
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
  const delimiter = args.kind === "review" ? REVIEW_DELIMITER : WORKER_DELIMITER;
  const start = lines.lastIndexOf(delimiter);
  if (start < 0) {
    if (args.kind === "review" && lines.includes(WORKER_DELIMITER)) invalid(`review summary is v1; a review report ends with ${REVIEW_DELIMITER} and a review block`);
    invalid("no summary");
  }
  if (lines.at(-1) !== END) invalid("truncated");
  const body = lines.slice(0, start);
  const part = lines.slice(start + 1, -1);
  if (!body.some((line) => line.trim())) invalid("no full report");

  let summary;
  if (args.kind === "review") {
    summary = reviewSummary(part, args);
  } else {
    checkWorkerSummary(part, args);
    summary = [WORKER_DELIMITER, ...part, END];
  }

  process.stdout.write(`valid sha256=${sha256} bytes=${bytes.length}\n`);
  if (args.show) process.stdout.write(`${summary.join("\n")}\n`);
}

// Always validate: this file is only ever run as a command, however it is invoked.
main();
