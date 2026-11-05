import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import {
  writeExecutable,
  createFixture,
  runSkillsAsWindows,
  readText,
} from "./skills-helpers.mjs";

test("Windows user scope runs npx.cmd when npx resolves through PATHEXT", async () => {
  const fixture = await createFixture({
    npxName: "npx.cmd",
    npxBody: `#!/bin/bash
set -euo pipefail
PATH="/bin:\${PATH}"
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
mkdir -p .agents/skills
printf '{"version":3,"source":"%s"}\\n' "$3" > skills-lock.json
mkdir -p .agents/skills/find-skills
printf '%s\\n' "find-skills" > .agents/skills/find-skills/SKILL.md
`,
    isolatedPath: true,
    withWindowsWhere: true,
  });
  try {
    const result = runSkillsAsWindows(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(await readText(fixture.log), /skills add vercel-labs\/skills/);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows user scope prefers executable npx shim over extensionless npx", async () => {
  const fixture = await createFixture({
    npxName: "npx",
    npxBody: `#!/bin/bash
printf 'extensionless npx should not run\\n' >&2
exit 99
`,
    isolatedPath: true,
    withWindowsWhere: true,
  });
  try {
    await writeExecutable(
      path.join(fixture.bin, "npx.exe"),
      `#!/bin/bash
set -euo pipefail
PATH="/bin:\${PATH}"
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
mkdir -p .agents/skills
printf '{"version":3,"source":"%s"}\\n' "$3" > skills-lock.json
mkdir -p .agents/skills/find-skills
printf '%s\\n' "find-skills" > .agents/skills/find-skills/SKILL.md
`,
    );

    const result = runSkillsAsWindows(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(await readText(fixture.log), /skills add vercel-labs\/skills/);
  } finally {
    await fixture.cleanup();
  }
});

const fakeNpxCli = `const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
fs.appendFileSync(process.env.TEST_SKILLS_LOG, JSON.stringify(args) + "\\n");
if (process.env.TEST_NPX_EXIT) {
  process.exit(Number(process.env.TEST_NPX_EXIT));
}
const agents = [];
const skills = [];
for (let index = 3; index < args.length; index += 1) {
  if (args[index] === "--agent") agents.push(args[++index]);
  else if (args[index] === "--skill") skills.push(args[++index]);
}
const agentDirs = { codex: path.join(".agents", "skills"), "claude-code": path.join(".claude", "skills") };
for (const agent of agents.length > 0 ? agents : ["codex"]) {
  for (const skill of skills) {
    const skillDir = path.join(agentDirs[agent], skill);
    fs.mkdirSync(skillDir, { recursive: true });
    fs.writeFileSync(path.join(skillDir, "SKILL.md"), skill + "\\n");
  }
}
`;

async function createWindowsNodeInstallFixture() {
  const fixture = await createFixture({
    binName: "Program Files",
    npxName: "npx.cmd",
    npxBody: `#!/bin/bash
printf 'npx.cmd should not run when npx-cli.js is available\\n' >&2
exit 99
`,
    isolatedPath: true,
    withWindowsWhere: true,
  });
  const npmBin = path.join(fixture.bin, "node_modules", "npm", "bin");
  await mkdir(npmBin, { recursive: true });
  await writeFile(path.join(npmBin, "npx-cli.js"), fakeNpxCli);
  const gitPath = spawnSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).stdout.trim();
  await writeExecutable(path.join(fixture.bin, "git.exe"), `#!/bin/sh\nexec ${gitPath} "$@"\n`);
  return fixture;
}

test("Windows user scope quotes an npx.cmd path that contains spaces", async () => {
  const fixture = await createFixture({
    binName: "Program Files",
    npxName: "npx.cmd",
    npxBody: `#!/bin/bash
set -euo pipefail
PATH="/bin:\${PATH}"
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
mkdir -p .agents/skills/find-skills
printf '%s\\n' "find-skills" > .agents/skills/find-skills/SKILL.md
`,
    isolatedPath: true,
    withWindowsWhere: true,
  });
  try {
    const result = runSkillsAsWindows(["--scope", "user", "--profile", "base"], fixture);

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(await readText(fixture.log), /skills add vercel-labs\/skills/);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows project scope runs npx-cli.js next to npx.cmd with node", async () => {
  const fixture = await createWindowsNodeInstallFixture();
  try {
    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex", "--agent", "claude-code"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const invocations = (await readText(fixture.log)).trim().split("\n").map((line) => JSON.parse(line));
    assert.deepEqual(invocations, [
      ["skills", "add", "vercel-labs/skills", "--copy", "--yes", "--agent", "codex", "--agent", "claude-code", "--skill", "find-skills"],
    ]);
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "find-skills", "SKILL.md")), "find-skills\n");
    assert.equal(await readText(path.join(fixture.project, ".claude", "skills", "find-skills", "SKILL.md")), "find-skills\n");
  } finally {
    await fixture.cleanup();
  }
});

test("Windows project scope ignores git.exe and npx.cmd planted in the current directory", async () => {
  const fixture = await createWindowsNodeInstallFixture();
  const planted = `#!/bin/sh\nprintf 'planted %s\\n' "$0" >> "\${TEST_SKILLS_LOG}.planted"\nexit 99\n`;
  try {
    await writeExecutable(path.join(fixture.project, "git.exe"), planted);
    await writeExecutable(path.join(fixture.project, "npx.cmd"), planted);

    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(`${fixture.log}.planted`), false);
    assert.match(await readText(fixture.log), /"skills","add","vercel-labs\/skills"/);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows project scope uses the current directory when PATH lists it explicitly", async () => {
  const fixture = await createWindowsNodeInstallFixture();
  try {
    await writeExecutable(
      path.join(fixture.project, "npx.cmd"),
      `#!/bin/sh\nprintf 'explicit %s\\n' "$*" >> "\${TEST_SKILLS_LOG}.explicit"\nexit 0\n`,
    );
    fixture.env.PATH = `${fixture.project}${path.delimiter}${fixture.env.PATH}`;

    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.match(await readText(`${fixture.log}.explicit`), /skills add vercel-labs\/skills/);
    assert.equal(existsSync(fixture.log), false, result.stderr || result.stdout);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows project scope restores existing outputs when npx-cli.js fails", async () => {
  const fixture = await createWindowsNodeInstallFixture();
  fixture.env.TEST_NPX_EXIT = "42";
  try {
    await mkdir(path.join(fixture.project, ".agents", "skills", "old-agent"), { recursive: true });
    await writeFile(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md"), "old-agent\n");

    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 1, result.stderr || result.stdout);
    assert.match(result.stderr, /npx-cli\.js skills add vercel-labs\/skills .* failed with exit 42/);
    assert.match(result.stderr, /Restored previous project skills after failed install/);
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "old-agent", "SKILL.md")), "old-agent\n");
  } finally {
    await fixture.cleanup();
  }
});
