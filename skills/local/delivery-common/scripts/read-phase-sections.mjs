import { readFileSync, realpathSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const skillRoot = realpathSync(fileURLToPath(new URL("../", import.meta.url)));
const phases = ["Prepare and dispatch", "Shared understanding and preflight"];

// The phase table and its references use ATX headings and inline links.
// Preserve the original lines for output and ignore Markdown inside code fences.
function readDocument(file) {
  const filename = path.join(skillRoot, file);
  if (realpathSync(filename) !== filename) throw new Error(`Unexpected path for ${file}`);

  const text = readFileSync(filename, "utf8");
  const lines = text.split(/\r?\n/);
  let fence;
  const prose = lines.map((line) => {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim()) {
        fence = undefined;
      }
      return "";
    }
    if (marker) {
      fence = marker[1];
      return "";
    }
    return line;
  });
  const headings = prose.flatMap((line, start) => {
    const match = line.match(/^ {0,3}(#{1,6})[ \t]+(.+?)\s*$/);
    return match ? [{ start, level: match[1].length, title: match[2].replace(/[ \t]+#+$/, "") }] : [];
  });
  const sections = headings.map((heading, index) => ({
    ...heading,
    end: headings.slice(index + 1).find(({ level }) => level <= heading.level)?.start ?? lines.length,
  }));
  return { file, text, lines, prose, sections };
}

function findSection(document, name, byAnchor = false) {
  const matches = document.sections.filter(({ title }) => {
    const label = byAnchor ? title.toLowerCase().replace(/[^a-z0-9_ -]/g, "").replaceAll(" ", "-") : title;
    return label === name;
  });
  if (matches.length !== 1) {
    const problem = matches.length ? "Ambiguous" : "Missing";
    throw new Error(`${problem} heading ${JSON.stringify(name)} in ${document.file}`);
  }
  return { document, ...matches[0] };
}

function renderPhase(phase) {
  const skill = readDocument("SKILL.md");
  const table = findSection(skill, "Phase sections");
  const rows = skill.prose.slice(table.start, table.end)
    .map((line) => line.match(/^\| ([^|]+?) \| (.+) \|$/))
    .filter((row) => row?.[1] === phase);
  if (rows.length !== 1) throw new Error(`Expected one phase row for ${JSON.stringify(phase)}`);

  const referenceLinks = [...skill.prose.slice(0, table.start).join("\n")
    .matchAll(/\[([^\]\n]+)\]\((references\/[a-z0-9-]+\.md)\)/g)];
  const documents = new Map();
  function reference(file) {
    if (!documents.has(file)) documents.set(file, readDocument(file));
    return documents.get(file);
  }

  const listed = rows[0][2].split("; ").flatMap((group) => {
    const [, label, selection] = group.match(/^([^:]+): (.+)$/) ?? [];
    const files = new Set(referenceLinks.filter((link) => link[1] === label).map((link) => link[2]));
    if (files.size !== 1) throw new Error(`Expected one reference link for ${JSON.stringify(label ?? group)}`);
    const document = reference([...files][0]);
    if (selection === "all") return [{ document, start: 0, end: document.lines.length }];
    return selection.split(", ").map((title) => findSection(document, title));
  });

  const selected = [...listed];
  for (const { document, title, start, end } of listed) {
    if (!title) continue;
    const prose = document.prose.slice(start, end).join("\n").replace(/(`+)[^\n]*?\1/g, "");
    for (const [, file, anchor] of prose.matchAll(/\]\((?:([a-z0-9-]+\.md))?#([a-z0-9_-]+)\)/g)) {
      const target = findSection(file ? reference(`references/${file}`) : document, anchor, true);
      const covered = selected.some((section) => section.document === target.document
        && section.start <= target.start && section.end >= target.end);
      if (!covered) selected.push(target);
    }
  }

  return selected.map(({ document, title, start, end }) => {
    const label = title ? `${document.file}#${title}` : document.file;
    const body = title ? document.lines.slice(start, end).join("\n").trimEnd() : document.text.trimEnd();
    return `<!-- ${label} -->\n${body}`;
  }).join("\n\n");
}

const [marker, phase, ...rest] = process.argv.slice(2);
if (marker !== "--" || !phases.includes(phase) || rest.length) {
  process.stderr.write(`usage: read-phase-sections.mjs -- ${phases.map((name) => JSON.stringify(name)).join(" | ")}\n`);
  process.exit(2);
}

try {
  process.stdout.write(`${renderPhase(phase)}\n`);
} catch (error) {
  process.stderr.write(`read-phase-sections: ${error.message}\n`);
  process.exitCode = 3;
}
