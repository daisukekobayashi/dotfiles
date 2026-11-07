#!/usr/bin/env node
// Check the cleanup targets for the worktree cleanup skills.
//
// Usage:
//   node check-cleanup-targets.mjs remote <facts> [--preview]
//   node check-cleanup-targets.mjs manifest <facts> <targets> --out <file> [--preview]
//   node check-cleanup-targets.mjs compare <facts> <targets> --confirmed <file>
//
// <facts> are the provider facts the caller looked up; the script makes no
// gh, az, or API call. Every one is required:
//   --github <host> <owner>/<repo>    the PR's head repository, or
//   --azure <org> <project> <repo>    the PR's repository
//   --branch <branch>                 the PR's head (source) branch
//   --pr-state <state>                GitHub `state` (MERGED counts as merged)
//                                     or Azure `status` (completed counts)
//   --pr-head <sha>                   GitHub `headRefOid` or Azure
//                                     `lastMergeSourceCommit.commitId`
//   --cross-repo true|false           GitHub `isCrossRepository`, or whether
//                                     the Azure PR has a `forkSource`
//   --default-branch <branch>         the repository's default branch
//   --protected true|false            whether the branch is protected (GitHub)
//                                     or has branch policies (Azure)
//   --open-prs <n>                    open (active) PRs from the branch other
//                                     than this PR
//   [--remote <name>]                 a remote the user or caller named
//
// <targets>: `--worktree <path>` or `--no-worktree`, and `--temp <path>` once
// per run-owned temporary file the caller found from launch information.
//
// remote
//   The **remote branch deletion check**. The branch is kept when the PR's
//   head repository is a fork, when no remote is resolved by the push target
//   rule (`check-push-target.mjs resolve` with the head repository and any
//   named remote), when the PR is not merged (skipped with --preview, before
//   the merge), when the branch is the default branch, protected, or under
//   policy, when another open PR uses it, or when
//   `git ls-remote --heads <remote> refs/heads/<branch>` is not exactly
//   --pr-head (a later push means unmerged work). Prints one tab-separated
//   line: `proposed <remote> <sha>` with the SHA to lease against, `absent
//   <remote>` when the remote branch no longer exists, or `kept <remote|->`
//   with the reason on stderr.
//
// manifest
//   Builds the **cleanup target manifest**: the worktree, local branch, remote
//   branch result, processes from `list-processes.sh <worktree>`, Compose
//   projects from `list-stacks.sh <worktree>` with their volumes from
//   `docker volume ls`, and the temporary paths with their resolved targets.
//   The listings are the read-only scripts of worktree-runtime-cleanup, run
//   from this skill tree. Writes the manifest as JSON to --out, which must be
//   outside the worktree, and prints the targets. With --preview it is a
//   Caller preview for a combined merge and cleanup confirmation: the remote
//   check runs as before the merge, and a listing that cannot run fails the
//   check. Without --preview a listing that cannot run is recorded and printed
//   as unverified.
//
// compare
//   Builds the manifest again, after the merge, and compares it with the
//   confirmed manifest (the Caller preview when the confirmation was combined,
//   otherwise the manifest the user confirmed). Processes are compared by PID,
//   start time, and cwd; Compose projects by name, working_dir, and volumes;
//   temporary paths by path and resolved target; the rest exactly. The one
//   tolerated difference is a confirmed remote branch that no longer exists,
//   reported as already deleted by the host. A listing that cannot run is a
//   difference for a Caller preview, and for any other manifest unless it
//   could not run there either. On a match it prints the targets and, for a
//   proposed remote branch, `lease <remote> <sha>`.
//
// The script reads git, process, and Docker state only; it never deletes,
// stops, or signals anything.
//
// Exit status:
//   0  the check passed
//   2  usage error: an unknown subcommand or option, a missing or repeated
//      option, an unsafe branch or remote name, a malformed fact, a manifest
//      path inside the worktree or at a symlink, or an unreadable confirmed
//      manifest
//   3  the check failed: remote keeps the remote branch (cleanup continues
//      without it); manifest --preview has a listing that cannot run; compare
//      found a difference. The reasons are reported on stderr.
// Any other status, including 1, which node uses for a missing script or an
// uncaught error and this script uses when git or check-push-target.mjs cannot
// run, means the check could not run and stops the cleanup.

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Same pattern as check-branch-name.mjs, which exits on load and so cannot be
// imported; keep the two in step.
const SAFE_NAME = /^[A-Za-z0-9/._][A-Za-z0-9/._-]*$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const MANIFEST_VERSION = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const pushTargetScript = path.join(here, "check-push-target.mjs");
const runtimeScripts = path.join(here, "..", "..", "worktree-runtime-cleanup", "scripts");

const USAGE = [
  "usage: check-cleanup-targets.mjs remote <facts> [--preview]",
  "       check-cleanup-targets.mjs manifest <facts> <targets> --out <file> [--preview]",
  "       check-cleanup-targets.mjs compare <facts> <targets> --confirmed <file>",
  "facts: (--github <host> <owner>/<repo> | --azure <org> <project> <repo>) --branch <branch>",
  "       --pr-state <state> --pr-head <sha> --cross-repo true|false --default-branch <branch>",
  "       --protected true|false --open-prs <n> [--remote <name>]",
  "targets: (--worktree <path> | --no-worktree) [--temp <path>]...",
].join("\n");

const usage = (reason) => {
  process.stderr.write(`${reason ? `${reason}\n` : ""}${USAGE}\n`);
  process.exit(2);
};

const fail = (lines) => {
  process.stderr.write(`${lines.join("\n")}\n`);
  process.exit(3);
};

const cannotRun = (reason) => {
  process.stderr.write(`check could not run: ${reason}\n`);
  process.exit(1);
};

const FACTS = {
  "--github": 2,
  "--azure": 3,
  "--branch": 1,
  "--pr-state": 1,
  "--pr-head": 1,
  "--cross-repo": 1,
  "--default-branch": 1,
  "--protected": 1,
  "--open-prs": 1,
  "--remote": 1,
};
const TARGETS = { "--worktree": 1, "--no-worktree": 0, "--temp": 1 };
const REPEATABLE = new Set(["--temp"]);

// Parses `--name value...` options with fixed arity; anything else is a usage
// error. Repeatable options collect one array per occurrence.
const parseOptions = (args, spec) => {
  const options = {};
  for (let i = 0; i < args.length; ) {
    const name = args[i];
    const arity = Object.hasOwn(spec, name) ? spec[name] : undefined;
    if (arity === undefined) usage(`unknown argument: ${JSON.stringify(name)}`);
    if (name in options && !REPEATABLE.has(name)) usage(`repeated option: ${name}`);
    const values = args.slice(i + 1, i + 1 + arity);
    if (values.length !== arity) usage(`missing value for ${name}`);
    if (REPEATABLE.has(name)) (options[name] ??= []).push(values);
    else options[name] = values;
    i += 1 + arity;
  }
  return options;
};

const requireSafe = (kind, value) => {
  if (!SAFE_NAME.test(value)) usage(`unsafe ${kind} name: ${JSON.stringify(value)}`);
};

const parseBoolean = (name, value) => {
  if (value === "true") return true;
  if (value === "false") return false;
  return usage(`${name} must be true or false: ${JSON.stringify(value)}`);
};

const readFacts = (options) => {
  const github = options["--github"];
  const azure = options["--azure"];
  if (Boolean(github) === Boolean(azure)) usage("exactly one of --github or --azure is required");
  for (const name of ["--branch", "--pr-state", "--pr-head", "--cross-repo", "--default-branch", "--protected", "--open-prs"]) {
    if (!options[name]) usage(`missing ${name}`);
  }
  const [branch] = options["--branch"];
  const [defaultBranch] = options["--default-branch"];
  const [state] = options["--pr-state"];
  const [head] = options["--pr-head"];
  const [openPrs] = options["--open-prs"];
  const remote = options["--remote"]?.[0];
  requireSafe("branch", branch);
  requireSafe("default branch", defaultBranch);
  if (remote !== undefined) requireSafe("remote", remote);
  if (!/^[A-Za-z]+$/.test(state)) usage(`malformed --pr-state: ${JSON.stringify(state)}`);
  if (!SHA.test(head)) usage(`--pr-head is not a full lower-case SHA: ${JSON.stringify(head)}`);
  if (!/^(?:0|[1-9][0-9]*)$/.test(openPrs)) usage(`--open-prs is not a count: ${JSON.stringify(openPrs)}`);
  return {
    provider: github ? "github" : "azure",
    repository: github ?? azure,
    branch,
    merged: github ? state.toUpperCase() === "MERGED" : state.toLowerCase() === "completed",
    head,
    crossRepo: parseBoolean("--cross-repo", options["--cross-repo"][0]),
    defaultBranch,
    protectedBranch: parseBoolean("--protected", options["--protected"][0]),
    openPrs: Number(openPrs),
    remote,
  };
};

// Resolves the remote by the push target rule; returns the remote, or null
// with the reason.
const resolveRemote = (facts) => {
  const args = [pushTargetScript, "resolve", `--${facts.provider}`, ...facts.repository];
  if (facts.remote !== undefined) args.push("--remote", facts.remote);
  const result = spawnSync(process.execPath, args, { encoding: "utf8" });
  const stderr = (result.stderr ?? "").trim();
  if (result.status === 0) return { remote: result.stdout.split("\n")[0] };
  if (result.status === 3) return { remote: null, reason: `no remote resolved by the push target rule: ${stderr}` };
  if (result.status === 2) usage(`check-push-target.mjs: ${stderr}`);
  return cannotRun(`check-push-target.mjs exited ${result.status ?? result.signal}: ${stderr || result.error?.message || ""}`);
};

// Returns the SHA refs/heads/<branch> has on the remote, or null when absent.
const lsRemote = (remote, branch) => {
  const ref = `refs/heads/${branch}`;
  let out;
  try {
    out = execFileSync("git", ["ls-remote", "--heads", remote, ref], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
    });
  } catch (error) {
    return cannotRun(`git ls-remote --heads ${remote} ${ref}: ${(error.stderr || error.message || "").toString().trim()}`);
  }
  const shas = out.split("\n").filter((line) => line.endsWith(`\t${ref}`)).map((line) => line.split("\t")[0]);
  if (shas.length === 0) return null;
  if (shas.length > 1 || !SHA.test(shas[0])) cannotRun(`unexpected git ls-remote output for ${ref}`);
  return shas[0];
};

// The remote branch deletion check; never exits on an unmet condition.
const checkRemote = (facts, { preview }) => {
  const kept = (remote, reason) => ({ status: "kept", remote, reason });
  if (facts.crossRepo) return kept(null, "the PR's head repository is a fork");
  const resolved = resolveRemote(facts);
  if (!resolved.remote) return kept(null, resolved.reason);
  const { remote } = resolved;
  const sha = lsRemote(remote, facts.branch);
  if (sha === null) return { status: "absent", remote };
  if (!preview && !facts.merged) return kept(remote, facts.provider === "github" ? "the PR is not merged" : "the PR is not completed");
  if (facts.branch === facts.defaultBranch) return kept(remote, "the branch is the default branch");
  if (facts.protectedBranch) return kept(remote, facts.provider === "github" ? "the branch is protected" : "the branch has branch policies");
  if (facts.openPrs > 0) return kept(remote, `${facts.openPrs} other open PR(s) use the branch`);
  if (sha !== facts.head) return kept(remote, `the remote branch is at ${sha}, not the PR head ${facts.head}; a later push means unmerged work`);
  return { status: "proposed", remote, sha };
};

const describeRemote = (result) => {
  if (result.status === "proposed") return `proposed\t${result.remote}\t${result.sha}`;
  if (result.status === "absent") return `absent\t${result.remote}`;
  return `kept\t${result.remote ?? "-"}`;
};

const remoteCommand = (args) => {
  const options = parseOptions(args, { ...FACTS, "--preview": 0 });
  const facts = readFacts(options);
  const result = checkRemote(facts, { preview: Boolean(options["--preview"]) });
  process.stdout.write(`${describeRemote(result)}\n`);
  if (result.status === "kept") fail([`remote branch kept: ${result.reason}`]);
};

const lstatOrNull = (target) => {
  try {
    return lstatSync(target);
  } catch {
    return null;
  }
};

const realpathOrNull = (target) => {
  try {
    return realpathSync(target);
  } catch {
    return null;
  }
};

const readTargets = (options) => {
  const worktreeOption = options["--worktree"];
  if (Boolean(worktreeOption) === Boolean(options["--no-worktree"])) usage("exactly one of --worktree or --no-worktree is required");
  let worktree = null;
  if (worktreeOption) {
    if (!path.isAbsolute(worktreeOption[0])) usage(`--worktree is not an absolute path: ${JSON.stringify(worktreeOption[0])}`);
    worktree = realpathOrNull(worktreeOption[0]);
    if (!worktree) usage(`--worktree not found: ${JSON.stringify(worktreeOption[0])}`);
  }
  const temps = (options["--temp"] ?? []).map(([given]) => {
    if (!path.isAbsolute(given)) usage(`--temp is not an absolute path: ${JSON.stringify(given)}`);
    return { path: given, resolved: realpathOrNull(given) };
  });
  return { worktree, temps };
};

// Runs a read-only listing script of worktree-runtime-cleanup and returns its
// rows split at tabs, or { unavailable } when it cannot run or prints a row
// with fewer than `columns` fields.
const runListing = (name, worktree, columns) => {
  const script = path.join(runtimeScripts, name);
  if (!existsSync(script)) return { unavailable: `${name} not found` };
  const result = spawnSync("bash", [script, worktree], { encoding: "utf8" });
  if (result.status !== 0) {
    const reason = (result.stderr || result.error?.message || "").trim().split("\n")[0];
    return { unavailable: `${name} exited ${result.status ?? result.signal}${reason ? `: ${reason}` : ""}` };
  }
  const rows = result.stdout.split("\n").filter((line) => line !== "").map((line) => line.split("\t"));
  if (rows.some((row) => row.length < columns)) return { unavailable: `${name} printed a row with fewer than ${columns} columns` };
  return { rows };
};

const listProcesses = (worktree) => {
  const listing = runListing("list-processes.sh", worktree, 7);
  if (listing.unavailable) return { status: "unavailable", reason: listing.unavailable, items: [] };
  // <pid> <ppid> <tty> <started> <cwd> <reason> <command>; the command may
  // contain tabs.
  const items = listing.rows.map(([pid, ppid, tty, started, cwd, reason, ...command]) => ({
    pid, ppid, tty, started, cwd, reason, command: command.join("\t"),
  }));
  return { status: "ok", items };
};

const listCompose = (worktree) => {
  const listing = runListing("list-stacks.sh", worktree, 4);
  if (listing.unavailable) return { status: "unavailable", reason: listing.unavailable, items: [] };
  const items = [];
  // <project> <running>/<total> <working_dir> <reason>
  for (const [project, counts, workingDir, ...reason] of listing.rows) {
    const volumes = spawnSync("docker", ["volume", "ls", "--filter", `label=com.docker.compose.project=${project}`, "--format", "{{.Name}}"], { encoding: "utf8" });
    if (volumes.status !== 0) {
      const why = (volumes.stderr || volumes.error?.message || "").trim().split("\n")[0];
      return { status: "unavailable", reason: `docker volume ls exited ${volumes.status ?? volumes.signal}${why ? `: ${why}` : ""}`, items: [] };
    }
    items.push({
      project,
      counts,
      working_dir: workingDir,
      reason: reason.join("\t"),
      volumes: volumes.stdout.split("\n").filter((line) => line !== "").sort(),
    });
  }
  return { status: "ok", items };
};

const buildManifest = (facts, targets, { preview }) => {
  const none = { status: "none", reason: "no worktree", items: [] };
  return {
    version: MANIFEST_VERSION,
    preview,
    provider: facts.provider,
    worktree: targets.worktree,
    branch: facts.branch,
    remote: checkRemote(facts, { preview }),
    processes: targets.worktree ? listProcesses(targets.worktree) : none,
    compose: targets.worktree ? listCompose(targets.worktree) : none,
    temps: targets.temps,
  };
};

const unavailableSections = (manifest) =>
  ["processes", "compose"].filter((section) => manifest[section].status === "unavailable");

const formatTargets = (manifest) => {
  const lines = [`worktree\t${manifest.worktree ?? "-"}`, `local branch\t${manifest.branch}`];
  const remote = manifest.remote;
  if (remote.status === "proposed") lines.push(`remote branch\tdelete ${remote.remote} refs/heads/${manifest.branch} at ${remote.sha}`);
  else if (remote.status === "absent") lines.push(`remote branch\talready absent on ${remote.remote}`);
  else lines.push(`remote branch\tkept: ${remote.reason}`);
  for (const item of manifest.processes.items) {
    lines.push(`process\tpid ${item.pid}\tstarted ${item.started}\tcwd ${item.cwd}\t${item.reason}\t${item.command}`);
  }
  for (const item of manifest.compose.items) {
    lines.push(`compose project\t${item.project}\tworking_dir ${item.working_dir}\tvolumes ${item.volumes.join(",") || "-"}\t${item.reason}`);
  }
  for (const section of unavailableSections(manifest)) {
    lines.push(`${section}\tunverified: ${manifest[section].reason}`);
  }
  for (const temp of manifest.temps) {
    lines.push(`temporary path\t${temp.path}${temp.resolved && temp.resolved !== temp.path ? ` -> ${temp.resolved}` : ""}${temp.resolved ? "" : " (missing)"}`);
  }
  return `${lines.join("\n")}\n`;
};

const isInside = (child, parent) => child === parent || child.startsWith(`${parent}${path.sep}`);

const manifestCommand = (args) => {
  const options = parseOptions(args, { ...FACTS, ...TARGETS, "--out": 1, "--preview": 0 });
  if (!options["--out"]) usage("missing --out");
  const facts = readFacts(options);
  const targets = readTargets(options);
  const [out] = options["--out"];
  if (!path.isAbsolute(out)) usage(`--out is not an absolute path: ${JSON.stringify(out)}`);
  const outDir = realpathOrNull(path.dirname(out));
  if (!outDir) usage(`--out directory not found: ${JSON.stringify(path.dirname(out))}`);
  const outReal = path.join(outDir, path.basename(out));
  if (targets.worktree && isInside(outReal, targets.worktree)) usage(`--out is inside the worktree: ${JSON.stringify(out)}`);
  // A symlink could point the write into the worktree or elsewhere.
  if (lstatOrNull(outReal)?.isSymbolicLink()) usage(`--out is a symlink: ${JSON.stringify(out)}`);

  const preview = Boolean(options["--preview"]);
  const manifest = buildManifest(facts, targets, { preview });
  const unavailable = unavailableSections(manifest);
  if (preview && unavailable.length > 0) {
    fail(unavailable.map((section) => `${section} cannot be listed for a Caller preview: ${manifest[section].reason}`));
  }
  writeFileSync(outReal, `${JSON.stringify(manifest, null, 2)}\n`);
  process.stdout.write(formatTargets(manifest));
};

const readConfirmed = (file) => {
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    return usage(`cannot read the confirmed manifest ${JSON.stringify(file)}: ${error.message}`);
  }
  if (manifest?.version !== MANIFEST_VERSION) usage(`not a version ${MANIFEST_VERSION} cleanup target manifest: ${JSON.stringify(file)}`);
  return manifest;
};

const sameSet = (a, b) => a.length === b.length && a.every((key) => b.includes(key));

const compareRuntime = (section, confirmed, current, keyOf, differences) => {
  const before = confirmed[section];
  const after = current[section];
  if (after.status === "unavailable" || before.status === "unavailable") {
    if (confirmed.preview) {
      differences.push(`${section} cannot be listed and the confirmation came from a Caller preview: ${(after.status === "unavailable" ? after : before).reason}`);
    } else if (after.status !== before.status) {
      differences.push(`${section} was ${before.status === "unavailable" ? "unverified" : "listed"} at confirmation and is ${after.status === "unavailable" ? "unverified" : "listed"} now`);
    }
    return;
  }
  const beforeKeys = before.items.map(keyOf);
  const afterKeys = after.items.map(keyOf);
  for (const key of afterKeys.filter((k) => !beforeKeys.includes(k))) differences.push(`${section}: new or changed ${key}`);
  for (const key of beforeKeys.filter((k) => !afterKeys.includes(k))) differences.push(`${section}: confirmed ${key} is gone or changed`);
};

const compareCommand = (args) => {
  const options = parseOptions(args, { ...FACTS, ...TARGETS, "--confirmed": 1 });
  if (!options["--confirmed"]) usage("missing --confirmed");
  const facts = readFacts(options);
  const targets = readTargets(options);
  const confirmed = readConfirmed(options["--confirmed"][0]);
  const current = buildManifest(facts, targets, { preview: false });

  const differences = [];
  for (const field of ["provider", "worktree", "branch"]) {
    if (confirmed[field] !== current[field]) differences.push(`${field}: confirmed ${JSON.stringify(confirmed[field])}, now ${JSON.stringify(current[field])}`);
  }

  let hostDeleted = false;
  const before = confirmed.remote ?? {};
  const after = current.remote;
  if (after.status === "absent" && before.status !== "absent" && (before.remote === null || before.remote === after.remote)) {
    hostDeleted = true;
  } else if (
    before.status !== after.status ||
    (after.status !== "kept" && before.remote !== after.remote) ||
    (after.status === "proposed" && before.sha !== after.sha)
  ) {
    differences.push(`remote branch: confirmed ${JSON.stringify(describeRemote(before))}, now ${JSON.stringify(describeRemote(after))}${after.reason ? ` (${after.reason})` : ""}`);
  }

  compareRuntime("processes", confirmed, current, (item) => `process pid ${item.pid} started ${item.started} cwd ${item.cwd}`, differences);
  compareRuntime("compose", confirmed, current, (item) => `compose project ${item.project} working_dir ${item.working_dir} volumes ${item.volumes.join(",") || "-"}`, differences);
  const tempKey = (temp) => `${temp.path} -> ${temp.resolved ?? "(missing)"}`;
  if (!sameSet((confirmed.temps ?? []).map(tempKey), current.temps.map(tempKey))) {
    differences.push(`temporary paths: confirmed ${JSON.stringify((confirmed.temps ?? []).map(tempKey))}, now ${JSON.stringify(current.temps.map(tempKey))}`);
  }

  if (differences.length > 0) fail(["the cleanup targets differ from the confirmed manifest:", ...differences]);
  process.stdout.write(formatTargets(current));
  if (hostDeleted) process.stdout.write(`remote branch already deleted by the host: ${after.remote} refs/heads/${current.branch}\n`);
  if (after.status === "proposed") process.stdout.write(`lease\t${after.remote}\t${after.sha}\n`);
};

const [subcommand, ...rest] = process.argv.slice(2);
const subcommands = { remote: remoteCommand, manifest: manifestCommand, compare: compareCommand };
if (!Object.hasOwn(subcommands, subcommand ?? "")) usage(subcommand === undefined ? "" : `unknown subcommand: ${JSON.stringify(subcommand)}`);
subcommands[subcommand](rest);
