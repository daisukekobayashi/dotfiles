#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  closeSync, constants, fstatSync, lstatSync, mkdtempSync, openSync, readFileSync,
  realpathSync, rmSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const scannerVersion = "1.10.1";
const stagedCommand = "dotfiles-betterleaks-staged";
const stagedVersion = `${stagedCommand} protocol 1 engine v${scannerVersion}`;
const stagedRequired = `The pinned staged scanner (${stagedVersion}) is required. See docs/testing.md.`;
const findingExit = 21;
const byteLimit = 64 * 1024 * 1024;
const inputLimit = 64 * 1024;
const allowlistPath = "scripts/sensitive-scan-allowlist.json";
const sha = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const categoryNames = new Set(["identifier", "organization", "hostname", "path"]);
const utf8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const commandEnv = { ...process.env, GIT_OPTIONAL_LOCKS: "0", GIT_NO_REPLACE_OBJECTS: "1" };
for (const name of Object.keys(commandEnv)) {
  if (/^(DOTFILES_SCAN_|BETTERLEAKS_|GITLEAKS_|GIT_TRACE)/i.test(name)) delete commandEnv[name];
}

class Incomplete extends Error {}

function expect(condition, reason) {
  if (!condition) throw new Incomplete(reason);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    env: commandEnv, maxBuffer: byteLimit, timeout: 60_000, windowsHide: true,
    ...options,
  });
  expect(!result.error && result.status !== null, command === "git"
    ? "Git failed, timed out, or exceeded the input limit."
    : command === stagedCommand ? stagedRequired
      : `Betterleaks ${scannerVersion} is required and must finish without errors.`);
  return result;
}

function gitResult(args) {
  return run("git", ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", ...args]);
}

function git(args) {
  const result = gitResult(args);
  expect(result.status === 0, "Git could not read the selected changes.");
  return result.stdout;
}

function text(buffer) {
  try {
    return utf8.decode(buffer);
  } catch {
    throw new Incomplete("A Git path or scan configuration is not valid UTF-8.");
  }
}

const remoteProtocols = ["-c", "protocol.file.allow=never", "-c", "protocol.ext.allow=never"];

function oid(value) {
  expect(typeof value === "string" && sha.test(value), "The event does not contain a valid Git object ID.");
  return value;
}

function readCommit(value, { fetch = false, label = "An event commit" } = {}) {
  const id = oid(value);
  let result = gitResult(["cat-file", "-t", id]);
  if (result.status !== 0 && fetch) {
    const fetched = gitResult([...remoteProtocols, "fetch", "--no-tags", "--no-write-fetch-head", "origin", id]);
    if (fetched.status === 0) result = gitResult(["cat-file", "-t", id]);
  }
  expect(result.status === 0 && result.stdout.toString().trim() === "commit",
    `${label} is missing or does not identify a commit.`);
  return id;
}

function readAllowlistCommit(ref, { allowMissing = false } = {}) {
  const resolved = gitResult(["show-ref", "--verify", "--hash", ref]);
  if (resolved.status === 0) {
    return readCommit(resolved.stdout.toString().trim(), { label: "The reviewed allowlist revision" });
  }
  // Git reports an absent ref separately from other lookup failures.
  if (allowMissing && gitResult(["show-ref", "--exists", ref]).status === 2) return null;
  throw new Incomplete("The reviewed allowlist revision could not be read.");
}

function eventSelection() {
  const eventName = process.env.GITHUB_EVENT_NAME;
  let event;
  try {
    event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, "utf8"));
  } catch {
    throw new Incomplete("The GitHub event could not be read.");
  }
  const repository = process.env.GITHUB_REPOSITORY;
  const branch = event?.repository?.default_branch;
  expect(typeof repository === "string" && /^[\w.-]+\/[\w.-]+$/.test(repository)
    && event?.repository?.full_name === repository
    && typeof branch === "string" && gitResult(["check-ref-format", `refs/heads/${branch}`]).status === 0,
  "The GitHub event does not identify this repository and its default branch.");
  const defaultRef = `refs/heads/${branch}`;

  let base;
  let head;
  let firstPush = false;
  let workflowCommit;
  if (eventName === "pull_request_target") {
    const pull = event.pull_request;
    expect(pull?.base?.repo?.full_name === repository, "The pull request base repository does not match.");
    base = oid(pull.base.sha);
    head = oid(pull.head?.sha);
    workflowCommit = readCommit(process.env.GITHUB_WORKFLOW_SHA, { label: "The reviewed workflow revision" });
    expect(git(["rev-parse", "HEAD"]).toString().trim() === workflowCommit,
      "The checkout does not match the reviewed workflow revision.");
  } else {
    expect(eventName === "push" && typeof event.ref === "string" && event.ref.startsWith("refs/heads/")
      && event.ref === process.env.GITHUB_REF, "The scan requires a trusted pull request or branch push event.");
    if (event.deleted === true) {
      expect(/^0{40}$|^0{64}$/.test(event.after), "The branch deletion has inconsistent event identities.");
      return { commits: [], policyCommit: null };
    }
    head = oid(event.after);
    expect(head === process.env.GITHUB_SHA, "The push head does not match the event SHA.");
    base = oid(event.before);
    if (/^0+$/.test(base)) {
      expect(event.created === true, "A push without a previous head must be a branch creation.");
      // The fetched default branch is already scanned. Its own first push has no such base.
      expect(event.ref !== defaultRef, "A first push of the default branch has no scanned comparison base.");
      firstPush = true;
    }
  }

  expect(git(["rev-parse", "--is-shallow-repository"]).toString().trim() === "false",
    "A shallow checkout cannot establish the complete event range.");
  head = readCommit(head, { fetch: true });
  if (firstPush) {
    // The event's default branch must still be the remote's, so its fetched
    // ref is the branch whose pushes were scanned.
    const remote = gitResult([...remoteProtocols, "ls-remote", "--symref", "origin", "HEAD"]);
    expect(remote.status === 0 && remote.stdout.toString().split("\n").includes(`ref: ${defaultRef}\tHEAD`),
      "A first branch push needs the remote default branch to match the event.");
    // Read the exact ref. A revision lookup can resolve a same-named tag instead.
    const resolved = gitResult(["show-ref", "--verify", "--hash", `refs/remotes/origin/${branch}`]);
    expect(resolved.status === 0,
      "A first branch push needs the fetched default branch as its comparison base.");
    base = readCommit(resolved.stdout.toString().trim());
  }
  base = readCommit(base, { fetch: true });
  const commits = git(["rev-list", "--reverse", "--topo-order", "--parents", head, `^${base}`])
    .toString().trim().split("\n").filter(Boolean).map((line) => line.split(" ").map(oid));
  const policyCommit = workflowCommit ?? (firstPush || event.ref === defaultRef
    ? base : readAllowlistCommit(`refs/remotes/origin/${branch}`));
  return { commits, policyCommit };
}

function configuredRules(value) {
  let records;
  try {
    records = JSON.parse(value);
  } catch {
    throw new Incomplete("The configured private denylist is not valid JSON.");
  }
  expect(Array.isArray(records) && records.length > 0 && records.every((record) =>
    categoryNames.has(record?.category) && typeof record.value === "string" &&
    record.value.length > 0 && !/[\u0000\r\n]/.test(record.value)
    && record.value.isWellFormed()),
  "The configured private denylist must contain valid category and literal records.");
  return records.sort((left, right) => right.value.length - left.value.length);
}

function verifyWindowsPrivateFile(file) {
  const powershell = path.join(process.env.SystemRoot ?? "C:\\Windows",
    "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const check = `
    $ErrorActionPreference = 'Stop'
    $sections = [System.Security.AccessControl.AccessControlSections]'Access, Owner'
    $acl = [System.IO.File]::GetAccessControl($env:DOTFILES_ACL_FILE, $sections)
    $sidType = [System.Security.Principal.SecurityIdentifier]
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($acl.GetOwner($sidType).Value -cne $owner.Value) { exit 1 }
    $allowed = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    $ownerRead = $false
    foreach ($ace in $acl.GetAccessRules($true, $true, $sidType)) {
      if ($ace.AccessControlType -ne 'Allow') { continue }
      if ($allowed -notcontains $ace.IdentityReference.Value) { exit 1 }
      if ($ace.IdentityReference.Value -eq $owner.Value -and ($ace.FileSystemRights -band 1)) {
        $ownerRead = $true
      }
    }
    if (-not $ownerRead) { exit 1 }
  `;
  const result = spawnSync(powershell, ["-NoProfile", "-NonInteractive", "-Command", check], {
    env: { ...commandEnv, DOTFILES_ACL_FILE: file }, timeout: 15_000, windowsHide: true,
  });
  expect(result.status === 0, "The local denylist owner and Windows access rules could not be verified.");
}

function outsideWorktrees(file, root) {
  const worktrees = text(git(["worktree", "list", "--porcelain", "-z"])).split("\0")
    .filter((entry) => entry.startsWith("worktree ")).map((entry) => entry.slice(9));
  return [root, ...worktrees].every((checkout) => {
    let canonical;
    try {
      canonical = realpathSync(checkout);
    } catch (error) {
      if (!["ENOENT", "ENOTDIR"].includes(error.code)) throw error;
      canonical = path.resolve(checkout);
    }
    const relative = path.relative(canonical, file);
    return relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative);
  });
}

function localRules(root) {
  const file = process.env.DOTFILES_SCAN_DENYLIST_FILE;
  if (!file) return [];
  expect(path.isAbsolute(file), "The local denylist path must be absolute.");
  let fd;
  try {
    expect(!lstatSync(file).isSymbolicLink(), "The local denylist must be a regular file outside the checkout.");
    const canonical = realpathSync(file);
    expect(outsideWorktrees(canonical, root), "The local denylist must be outside the repository worktrees.");
    fd = openSync(canonical, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const info = fstatSync(fd);
    expect(info.isFile() && info.nlink === 1 && info.size <= inputLimit,
      "The local denylist must be a regular file with one link and within the size limit.");
    if (process.platform === "win32") {
      verifyWindowsPrivateFile(canonical);
    } else {
      expect(info.uid === process.getuid() && (info.mode & 0o777) === 0o600,
        "The local denylist must be owned by the current user and have mode 0600.");
    }
    const input = readFileSync(fd);
    expect(input.length <= inputLimit, "The configured private denylist exceeds the size limit.");
    return configuredRules(text(input));
  } catch (error) {
    if (error instanceof Incomplete) throw error;
    throw new Incomplete("The configured private denylist could not be read.");
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function allowlist(commit) {
  if (commit === null) return [];
  const entries = git(["ls-tree", "-z", commit, "--", allowlistPath]);
  if (!entries.length) return [];
  expect(/^100(?:644|755) blob /.test(entries.toString()), "The reviewed allowlist must be a regular file.");
  let rules;
  try {
    rules = JSON.parse(text(git(["cat-file", "blob", `${commit}:${allowlistPath}`])));
  } catch {
    throw new Incomplete("The reviewed allowlist could not be read.");
  }
  expect(Array.isArray(rules) && rules.every((entry) =>
    typeof entry?.path === "string" && typeof entry.rule === "string"
    && /^[0-9a-f]{64}$/.test(entry.contentSha256) && Number.isSafeInteger(entry.line) && entry.line >= 0
    && typeof entry.reason === "string" && entry.reason.trim()),
  "The reviewed allowlist contains an invalid exception.");
  return rules;
}

function changedBlobs(args) {
  const records = text(git(args)).split("\0");
  expect(records.pop() === "" && records.length % 2 === 0, "Git produced an incomplete change list.");
  const blobs = [];
  for (let index = 0; index < records.length; index += 2) {
    const [oldMode, newMode, , id, status] = records[index].split(" ");
    expect(/^:[0-7]{6}$/.test(oldMode) && /^[AMT]$/.test(status), "Git produced an invalid change entry.");
    expect(["100644", "100755", "120000", "160000"].includes(newMode), "Git reported an unsupported object mode.");
    blobs.push({ file: records[index + 1], id: oid(id), submodule: newMode === "160000" });
  }
  return blobs;
}

function* selection(mode, commits) {
  const options = ["--raw", "--no-abbrev", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", "--ignore-submodules=none", "--diff-filter=AMT"];
  if (mode === "staged") {
    expect(!git(["ls-files", "--unmerged", "-z"]).length, "The Git index contains unresolved entries.");
    for (const item of changedBlobs(["diff", "--cached", ...options, "--"])) yield { ...item, commit: "staged" };
    return;
  }
  for (const [commit, firstParent] of commits) {
    const revisions = firstParent ? [firstParent, commit] : ["--root", commit];
    for (const item of changedBlobs(["diff-tree", "-r", "--no-commit-id", ...options, ...revisions, "--"])) {
      yield { ...item, commit };
    }
  }
}

function stagedInput(blob, file) {
  const name = Buffer.from(file, "utf8");
  expect(name.length > 0 && name.length <= inputLimit && blob.length <= byteLimit,
    "A staged scanner input exceeds the protocol limit.");
  const header = Buffer.alloc(8);
  header.writeUInt32BE(name.length, 0);
  header.writeUInt32BE(blob.length, 4);
  return Buffer.concat([header, name, blob]);
}

function scanner(cwd, mode) {
  const staged = mode === "staged";
  const command = staged ? stagedCommand : "betterleaks";
  const expectedVersion = staged ? stagedVersion : `betterleaks version ${scannerVersion}`;
  const version = run(command, ["--version"], { cwd });
  expect(version.status === 0 && version.stdout.toString().trim() === expectedVersion,
    staged ? stagedRequired : `Betterleaks ${scannerVersion} is required. See docs/testing.md.`);
  // Match the staged scanner policy. Retain the pinned rules and per-match
  // filters, while scanning blobs already selected by Git.
  const config = path.join(cwd, "scan.toml");
  if (!staged) {
    writeFileSync(config, 'prefilter = "false"\n\n[extend]\nuseDefault = true\n', { mode: 0o600 });
  }
  return (blob, file) => {
    const result = staged
      ? run(command, [], { cwd, input: stagedInput(blob, file) })
      : run(command, [
        "stdin", "--config", config, "--set-attr", `path=${file}`, "--no-banner", "--no-color", "--redact=100",
        "--log-level", "error", "--ignore-gitleaks-allow", "--max-decode-depth", "2",
        "--report-format", "json", "--report-path", "-", "--exit-code", String(findingExit),
      ], { cwd, input: blob });
    expect(result.status === 0 || result.status === findingExit, "Betterleaks returned an incomplete scan.");
    let rows;
    try {
      rows = JSON.parse(result.stdout);
    } catch {
      throw new Incomplete("Betterleaks returned an invalid findings report.");
    }
    expect(Array.isArray(rows) && (result.status === findingExit) === (rows.length > 0) && rows.every((row) =>
      typeof row?.RuleID === "string" && /^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*$/.test(row.RuleID)
      && Number.isSafeInteger(row.StartLine) && row.StartLine >= 0),
    "Betterleaks returned an invalid findings report.");
    return rows.map((row) => ({ rule: row.RuleID, line: row.StartLine }));
  };
}

function personalFindings(buffer, rules) {
  const rows = [];
  for (const { category, value } of rules) {
    const needle = Buffer.from(value);
    let line = 1;
    let cursor = 0;
    let previousLine = 0;
    for (let offset = buffer.indexOf(needle); offset >= 0; offset = buffer.indexOf(needle, offset + needle.length)) {
      while (cursor < offset) {
        if (buffer[cursor] === 10) line += 1;
        cursor += 1;
      }
      if (previousLine !== line) rows.push({ rule: category, line });
      previousLine = line;
    }
  }
  return rows;
}

function main(mode) {
  expect(["staged", "ci"].includes(mode), "Use staged or ci.");
  const root = realpathSync(text(git(["rev-parse", "--show-toplevel"])).replace(/\r?\n$/, ""));
  const rules = mode === "staged" ? localRules(root) : [];
  const { commits, policyCommit } = mode === "staged"
    ? { commits: [], policyCommit: readAllowlistCommit("refs/remotes/origin/main", { allowMissing: true }) }
    : eventSelection();
  const exceptions = allowlist(policyCommit);
  const scratch = mkdtempSync(path.join(tmpdir(), "dotfiles-sensitive-scan-"));
  try {
    const detectSecrets = scanner(scratch, mode);
    const seen = new Set();
    let found = false;
    for (const { file, id, submodule, commit } of selection(mode, commits)) {
      const key = `${id}:${file}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const blob = submodule ? Buffer.alloc(0) : git(["cat-file", "blob", id]);
      const digest = createHash("sha256").update(blob).digest("hex");
      const fileBytes = Buffer.from(file);
      const secretPath = detectSecrets(fileBytes, "path.txt");
      const findings = [
        ...secretPath.map(({ rule }) => ({ kind: "secret", rule, line: 0 })),
        ...detectSecrets(blob, file).map((row) => ({ kind: "secret", ...row })),
        ...personalFindings(fileBytes, rules).map(({ rule }) => ({ kind: "personal", rule, line: 0 })),
        ...personalFindings(blob, rules).map((row) => ({ kind: "personal", ...row })),
      ];
      for (const { kind, rule, line } of findings) {
        if (exceptions.some((entry) =>
          entry.path === file && entry.rule === `${kind}:${rule}`
          && entry.line === line && entry.contentSha256 === digest)) continue;
        found = true;
        console.log(`finding ${kind}:${rule} ${commit} "[redacted path]":${line}`);
      }
    }
    if (mode === "staged" && !rules.length) console.log("personal information: skipped (private denylist unavailable)");
    if (found) return findingExit;
    console.log("sensitive changes: clean");
    return 0;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

try {
  process.exitCode = main(process.argv[2]);
} catch (error) {
  console.error(`sensitive changes: incomplete. ${error instanceof Incomplete ? error.message : "Unable to finish the scan."}`);
  process.exitCode = 2;
}
