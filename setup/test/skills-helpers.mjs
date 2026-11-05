import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

export const repoRoot = path.resolve(import.meta.dirname, "..", "..");
export const skillsRuntime = path.join(repoRoot, "setup", "skills.js");

// Project installs refuse a staging directory with an ancestor that others can
// write, such as /tmp, so keep fixtures in the ignored setup/node_modules.
const fixtureCache = path.join(repoRoot, "setup", "node_modules", ".cache");
mkdirSync(fixtureCache, { recursive: true });
const fixtureBase = mkdtempSync(path.join(fixtureCache, "skills-tests-"));
process.on("exit", () => rmSync(fixtureBase, { recursive: true, force: true }));

export async function writeExecutable(filePath, content) {
  await writeFile(filePath, content, { mode: 0o755 });
}

export async function createFixture(options = {}) {
  const root = await mkdtemp(path.join(fixtureBase, "skills-node-test."));
  const home = path.join(root, "home");
  const tmp = path.join(root, "tmp");
  const dotfiles = path.join(root, "dotfiles");
  const bin = path.join(root, options.binName ?? "bin");
  const project = path.join(root, "project");
  const log = path.join(root, "skills.log");

  await mkdir(home, { recursive: true, mode: 0o755 });
  await mkdir(tmp, { recursive: true });
  const userTemp = path.join(root, "user-temp");
  await mkdir(userTemp, { recursive: true });
  await mkdir(bin, { recursive: true });
  await mkdir(project, { recursive: true });
  await mkdir(path.join(dotfiles, "skills", "local", "local-one"), { recursive: true });
  await mkdir(path.join(dotfiles, "skills", "profiles"), { recursive: true });

  await writeFile(
    path.join(dotfiles, "skills", "local", "local-one", "SKILL.md"),
    "---\nname: local-one\ndescription: Test local skill\n---\n\nLocal skill.\n",
  );
  await writeFile(
    path.join(dotfiles, "skills", "profiles", "base.json"),
    JSON.stringify(
      {
        description: "Base test profile",
        external: [{ source: "vercel-labs/skills", skills: ["find-skills"] }],
        local: ["local-one"],
      },
      null,
      2,
    ) + "\n",
  );
  await writeFile(
    path.join(dotfiles, "skills", "profiles", "office.json"),
    JSON.stringify(
      {
        description: "Office test profile",
        includes: ["base"],
        external: [{ source: "anthropics/skills", skills: ["docx", "pdf"] }],
        local: [],
      },
      null,
      2,
    ) + "\n",
  );

  const npxBody =
    options.npxBody ??
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "\${TEST_SKILLS_LOG}"
if [ "$#" -lt 3 ] || [ "$1" != "skills" ] || [ "$2" != "add" ]; then
  printf 'unexpected npx invocation: %s\\n' "$*" >&2
  exit 1
fi
shift 2
source_name="$1"
shift
agents=()
skills=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)
      agents+=("$2")
      shift 2
      ;;
    --skill)
      skills+=("$2")
      shift 2
      ;;
    --copy|--yes)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p .agents/skills .claude/skills
printf '{"version":3,"source":"%s"}\\n' "\${source_name}" > skills-lock.json
for skill_name in "\${skills[@]}"; do
  if [ "\${#agents[@]}" -eq 0 ]; then
    agents=(codex)
  fi
  for agent_name in "\${agents[@]}"; do
    case "\${agent_name}" in
      codex)
        mkdir -p ".agents/skills/\${skill_name}"
        printf '%s\\n' "\${skill_name}" > ".agents/skills/\${skill_name}/SKILL.md"
        ;;
      claude-code)
        mkdir -p ".claude/skills/\${skill_name}"
        printf '%s\\n' "\${skill_name}" > ".claude/skills/\${skill_name}/SKILL.md"
        ;;
    esac
  done
done
${options.npxSuffix ?? ""}`;
  await writeExecutable(path.join(bin, options.npxName ?? "npx"), npxBody);

  if (options.withWindowsWhere) {
    await writeExecutable(
      path.join(bin, "where"),
      `#!/bin/bash
set -euo pipefail
command_name="$1"
found=0
# Like where.exe, search the current directory before PATH.
IFS=':' read -ra path_entries <<< "\${PWD}:\${PATH}"
for path_entry in "\${path_entries[@]}"; do
  if [ -x "\${path_entry}/\${command_name}" ]; then
    printf '%s\\n' "\${path_entry}/\${command_name}"
    found=1
  fi
  if [ -x "\${path_entry}/\${command_name}.exe" ]; then
    printf '%s\\n' "\${path_entry}/\${command_name}.exe"
    found=1
  fi
  if [ -x "\${path_entry}/\${command_name}.cmd" ]; then
    printf '%s\\n' "\${path_entry}/\${command_name}.cmd"
    found=1
  fi
done
exit $((found == 0))
`,
    );
    await writeExecutable(
      path.join(bin, "cmd.exe"),
      `#!/bin/bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in
    /d|/D|/s|/S)
      shift
      ;;
    /c|/C)
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
`,
    );
  }

  spawnSync("git", ["init", "-q"], { cwd: project });

  const env = {
    ...process.env,
    HOME: home,
    SETUP_HOME: home,
    SETUP_TMPDIR: tmp,
    SETUP_DOTFILES_ROOT: dotfiles,
    PATH: options.isolatedPath ? bin : `${bin}${path.delimiter}${process.env.PATH}`,
    TMPDIR: userTemp,
    TEST_SKILLS_LOG: log,
  };
  delete env.XDG_CACHE_HOME;

  return {
    root,
    home,
    tmp,
    dotfiles,
    bin,
    project,
    log,
    env,
    cleanup: () => rm(root, { recursive: true, force: true }),
  };
}

export function runSkills(args, fixture, options = {}) {
  return spawnSync(process.execPath, [skillsRuntime, ...args], {
    cwd: options.cwd ?? repoRoot,
    env: fixture.env,
    encoding: "utf8",
  });
}

export function runSkillsWithSymlinkError(args, fixture, options = {}) {
  const launcher = `
const fs = require("node:fs");
fs.symlinkSync = () => {
  const error = new Error("EPERM: operation not permitted, symlink");
  error.code = "EPERM";
  throw error;
};
const runtime = process.argv[1];
const args = process.argv.slice(2);
process.argv = [process.execPath, runtime, ...args];
require(runtime);
`;
  return spawnSync(process.execPath, ["-e", launcher, skillsRuntime, ...args], {
    cwd: options.cwd ?? repoRoot,
    env: fixture.env,
    encoding: "utf8",
  });
}

export function runSkillsWithCrossDeviceBackupRenameError(args, fixture, options = {}) {
  const launcher = `
const fs = require("node:fs");
const path = require("node:path");
const runtime = process.argv[1];
const args = process.argv.slice(2);
const backupRoot = path.resolve(process.env.SETUP_TMPDIR, "dotfiles-skills-backup");
const originalRenameSync = fs.renameSync;
function underBackupRoot(candidate) {
  const resolved = path.resolve(candidate);
  return resolved === backupRoot || resolved.startsWith(backupRoot + path.sep);
}
fs.renameSync = (oldPath, newPath) => {
  if (underBackupRoot(oldPath) || underBackupRoot(newPath)) {
    const error = new Error("EXDEV: cross-device link not permitted, rename");
    error.code = "EXDEV";
    throw error;
  }
  return originalRenameSync(oldPath, newPath);
};
process.argv = [process.execPath, runtime, ...args];
require(runtime);
`;
  return spawnSync(process.execPath, ["-e", launcher, skillsRuntime, ...args], {
    cwd: options.cwd ?? repoRoot,
    env: fixture.env,
    encoding: "utf8",
  });
}

export function runSkillsAsWindows(args, fixture, options = {}) {
  const launcher = `
const runtime = process.argv[1];
const args = process.argv.slice(2);
Object.defineProperty(process, "platform", { value: "win32" });
process.argv = [process.execPath, runtime, ...args];
require(runtime);
`;
  return spawnSync(process.execPath, ["-e", launcher, skillsRuntime, ...args], {
    cwd: options.cwd ?? repoRoot,
    env: fixture.env,
    encoding: "utf8",
  });
}

export async function readText(filePath) {
  return readFile(filePath, "utf8");
}

export async function createClaudeEnvironment(fixture, name = "acme") {
  const environment = path.join(fixture.home, ".claude-envs", name);
  await mkdir(path.join(environment, "skills"), { recursive: true });
  await writeFile(path.join(environment, ".claude-pick"), "1\n");
  await writeFile(path.join(environment, "settings.json"), '{"theme":"local"}\n');
  return environment;
}

export async function readRepoProfile(name) {
  return JSON.parse(await readText(path.join(repoRoot, "skills", "profiles", `${name}.json`)));
}

export function skillsForSource(profile, source) {
  return profile.external.find((entry) => entry.source === source)?.skills ?? [];
}
