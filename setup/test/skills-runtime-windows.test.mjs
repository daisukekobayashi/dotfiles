import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import {
  writeExecutable,
  createFixture as createBaseFixture,
  runSkillsAsWindows,
  readText,
} from "./skills-helpers.mjs";

// The runtime passes cmd.exe by absolute path. Node gives it /d /s /c when the
// path ends in \cmd.exe and -c otherwise, which is what a POSIX path gets here.
const cmdShell = `#!/bin/bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in
    /d|/D|/s|/S)
      shift
      ;;
    /c|/C|-c)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done
if [ "$#" -eq 0 ]; then
  exit 0
fi
command_line="$*"
if [[ "\${command_line}" == \\"*\\" ]]; then
  command_line="\${command_line:1:\${#command_line}-2}"
fi
eval "exec \${command_line}"
`;

async function createFixture(options = {}) {
  const fixture = await createBaseFixture(options);
  // Under win32, os.tmpdir() reads %TEMP%, the per-user dir that stages project installs.
  fixture.userTemp = path.join(fixture.root, "user-temp");
  await mkdir(fixture.userTemp, { recursive: true });
  fixture.env.TEMP = fixture.userTemp;
  if (options.withWindowsWhere) {
    fixture.env.ComSpec = path.join(fixture.bin, "cmd.exe");
    await writeExecutable(fixture.env.ComSpec, cmdShell);
  }
  return fixture;
}

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

// A batch shim without npx-cli.js next to it (for example a mise shim) runs a
// bare `node`. Like cmd.exe, the stub searches the current directory before PATH.
async function createWindowsBatchShimFixture() {
  const fixture = await createFixture({
    npxName: "npx.cmd",
    npxBody: `#!/bin/bash
set -euo pipefail
IFS=':' read -ra search_dirs <<< "\${PWD}:\${PATH}"
for dir in "\${search_dirs[@]}"; do
  if [ -x "\${dir}/node.exe" ]; then
    exec "\${dir}/node.exe" "$@"
  fi
done
printf 'node not found\\n' >&2
exit 127
`,
    isolatedPath: true,
    withWindowsWhere: true,
  });
  await writeExecutable(
    path.join(fixture.bin, "node.exe"),
    `#!/bin/bash
set -euo pipefail
PATH="/bin:\${PATH}"
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
printf '%s\\n' "\${PWD}" > "\${TEST_SKILLS_LOG}.cwd"
ls -ld "\${PWD}" | cut -c1-10 > "\${TEST_SKILLS_LOG}.mode"
if [ -n "\${TEST_NPX_EXIT:-}" ]; then
  exit "\${TEST_NPX_EXIT}"
fi
printf '{"version":3,"source":"%s"}\\n' "$3" > skills-lock.json
mkdir -p .agents/skills/find-skills
printf '%s\\n' "find-skills" > .agents/skills/find-skills/SKILL.md
`,
  );
  const gitPath = spawnSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).stdout.trim();
  await writeExecutable(path.join(fixture.bin, "git.exe"), `#!/bin/sh\nexec ${gitPath} "$@"\n`);
  return fixture;
}

async function plantProjectBinaries(fixture) {
  const planted = `#!/bin/sh\nprintf 'planted %s\\n' "$0" >> "\${TEST_SKILLS_LOG}.planted"\nexit 99\n`;
  await writeExecutable(path.join(fixture.project, "node.exe"), planted);
  await writeExecutable(path.join(fixture.project, "cmd.exe"), planted);
}

async function writeTrustedShell(filePath, fixture) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeExecutable(
    filePath,
    `#!/bin/bash\nprintf 'trusted shell\\n' >> "\${TEST_SKILLS_LOG}.shell"\nexec "${path.join(fixture.bin, "cmd.exe")}" "$@"\n`,
  );
}

test("Windows project scope batch fallback ignores node.exe and cmd.exe planted in the project", async () => {
  const fixture = await createWindowsBatchShimFixture();
  try {
    await plantProjectBinaries(fixture);
    await writeFile(path.join(fixture.project, "skills-lock.json"), "previous lock\n");

    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(existsSync(`${fixture.log}.planted`), false);
    assert.match(await readText(fixture.log), /skills add vercel-labs\/skills/);
    assert.equal(await readText(path.join(fixture.project, ".agents", "skills", "find-skills", "SKILL.md")), "find-skills\n");
    assert.equal(await readText(path.join(fixture.project, "skills-lock.json")), '{"version":3,"source":"vercel-labs/skills"}\n');
  } finally {
    await fixture.cleanup();
  }
});

test("Windows batch fallback runs the absolute ComSpec shell", async () => {
  const fixture = await createWindowsBatchShimFixture();
  try {
    await plantProjectBinaries(fixture);
    fixture.env.ComSpec = path.join(fixture.root, "comspec", "cmd.exe");
    await writeTrustedShell(fixture.env.ComSpec, fixture);

    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readText(`${fixture.log}.shell`), "trusted shell\n");
    assert.equal(existsSync(`${fixture.log}.planted`), false);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows batch fallback uses SystemRoot cmd.exe when ComSpec is unset", async () => {
  const fixture = await createWindowsBatchShimFixture();
  try {
    await plantProjectBinaries(fixture);
    delete fixture.env.ComSpec;
    delete fixture.env.COMSPEC;
    delete fixture.env.comspec;
    fixture.env.SystemRoot = path.join(fixture.root, "Windows");
    await writeTrustedShell(path.join(fixture.env.SystemRoot, "System32", "cmd.exe"), fixture);

    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await readText(`${fixture.log}.shell`), "trusted shell\n");
    assert.equal(existsSync(`${fixture.log}.planted`), false);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows project scope stages each install in a private directory under the user temp dir", async () => {
  const fixture = await createWindowsBatchShimFixture();
  try {
    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const staging = (await readText(`${fixture.log}.cwd`)).trim();
    assert.equal(path.dirname(staging), fixture.userTemp);
    assert.match(path.basename(staging), /^dotfiles-skills-.+/);
    assert.equal((await readText(`${fixture.log}.mode`)).trim(), "drwx------");
    assert.equal(existsSync(staging), false);
    assert.equal(existsSync(path.join(fixture.tmp, "dotfiles-skills")), false);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows project scope removes the staging directory after a failed install", async () => {
  const fixture = await createWindowsBatchShimFixture();
  fixture.env.TEST_NPX_EXIT = "42";
  try {
    const result = runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.equal(result.status, 1, result.stderr || result.stdout);
    assert.match(result.stderr, /failed with exit 42/);
    const staging = (await readText(`${fixture.log}.cwd`)).trim();
    assert.equal(path.dirname(staging), fixture.userTemp);
    assert.equal(existsSync(staging), false);
  } finally {
    await fixture.cleanup();
  }
});

test("Windows batch fallback resolves node from the project when PATH lists it explicitly", async () => {
  const fixture = await createWindowsBatchShimFixture();
  try {
    await plantProjectBinaries(fixture);
    fixture.env.PATH = `${fixture.project}${path.delimiter}${fixture.env.PATH}`;

    runSkillsAsWindows(
      ["--scope", "project", "--profile", "base", "--agent", "codex"],
      fixture,
      { cwd: fixture.project },
    );

    assert.match(await readText(`${fixture.log}.planted`), /node\.exe/);
  } finally {
    await fixture.cleanup();
  }
});
