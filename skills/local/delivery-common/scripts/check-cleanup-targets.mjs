#!/usr/bin/env node
// Check the cleanup targets for the worktree cleanup skills.
//
// Usage:
//   node check-cleanup-targets.mjs remote <facts> [--preview]
//   node check-cleanup-targets.mjs local <facts>
//   node check-cleanup-targets.mjs manifest <facts> <targets> --out <file> [--preview]
//   node check-cleanup-targets.mjs compare <facts> <targets> --confirmed <file> [--after-stop]
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
// per run-owned temporary file the caller found from launch information; a
// repeated --temp path is a usage error.
//
// remote
//   The **remote branch deletion check**. The branch is kept when the PR's
//   head repository is a fork, when no remote is resolved by the push target
//   rule (`check-push-target.mjs resolve` with the head repository and any
//   named remote), when a named remote does not name the PR head repository
//   (for GitHub, the `<owner>/<repo>` its URLs name; for Azure DevOps, the
//   push target rule checks it), when the PR is not merged (skipped with --preview, before
//   the merge), when the branch is the default branch, protected, or under
//   policy, when another open PR uses it, or when
//   `git ls-remote --heads <remote> refs/heads/<branch>` is not exactly
//   --pr-head (a later push means unmerged work). Prints one tab-separated
//   line: `proposed <remote> <sha>` with the SHA to lease against, `absent
//   <remote>` when the remote branch no longer exists, or `kept <remote|->`
//   with the reason on stderr.
//
// local
//   Rechecks the local branch right before `git branch -D` deletes it, with
//   the same rule as manifest below. Prints one tab-separated line: `proposed
//   <sha>`, `absent`, or `unmerged <sha|->` with the reason on stderr.
//
// manifest
//   Builds the **cleanup target manifest**: the worktree, the local branch
//   result, the remote branch result, processes from
//   `list-processes.sh <worktree>`, Compose projects from
//   `list-stacks.sh <worktree>` with their volumes from
//   `docker volume ls`, and the temporary paths with their resolved targets.
//   The listings are the read-only scripts of worktree-runtime-cleanup, run
//   from this skill tree. A lookup that exits non-zero or writes to stderr
//   cannot run; it never counts as an empty listing. The manifest also
//   records the PR head repository.
//   The local branch is `proposed <sha>` when `refs/heads/<branch>` is a
//   direct ref that `git for-each-ref` lists under exactly that name, no ref
//   it lists and no branch `git worktree list` reports checked out differs
//   from that name only by case (compared after NFKC normalization and
//   lower-casing), the PR is merged (skipped with --preview, before the
//   merge), the branch is not the default branch in any letter case, and its
//   tip equals --pr-head, for any merge method. It is `absent` when no ref is
//   listed under the name and neither `git symbolic-ref` nor `git rev-parse
//   --verify` finds one, so a ref git omits from its listing, such as a
//   dangling symbolic ref, is never absent. Otherwise it is `unmerged`, which
//   fails the check with the reason on stderr and writes no manifest. The
//   merged state comes from the provider facts, never from the local default
//   branch, which can lag its remote. Whether a checkout still uses the
//   branch under its exact name (checked out, rebasing including
//   `--update-refs`, or bisecting) is left to `git branch -D`, which refuses
//   such a branch. On Git before 2.36, which has no `worktree list -z`, the
//   line output counts only when every line is a known field.
//   Writes the manifest as JSON to --out, a new file outside the worktree
//   created with mode 0600 (an existing path, including a symlink, is a usage
//   error), and prints the targets. With --preview it is a
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
//   temporary paths by path and resolved target; each list as a multiset of
//   identity tuples;
//   the local branch by status and SHA; the rest, including the PR head
//   repository, exactly. The tolerated differences are a confirmed remote
//   branch that no longer exists, reported as already deleted by the host, and
//   a confirmed local branch that no longer exists, reported as already
//   deleted. A local branch that is `unmerged` now is a difference. With
//   --after-stop, run after the confirmed runtime stop, a confirmed process,
//   Compose project, or temporary path that is gone is also expected and
//   printed as `stopped as confirmed`; a new or changed item is still a
//   difference, and a listing that cannot run holds. A process counts as gone
//   only when no process has its PID (`kill -0`, which sends no signal, finds
//   none), since the listing drops a running process whose cwd leaves the
//   worktree; a reused PID also holds. A Compose project counts as gone only
//   when `docker volume ls` runs and lists no volume of the project that the
//   confirmed manifest did not have and, for a worktree-owned project (reason
//   exactly `under target`, whose stop deletes its volumes), none of its
//   confirmed volumes. An external volume the stop keeps by design also holds
//   here, since Docker records no external flag and the check never evaluates
//   the checkout's Compose configuration; a manifest rebuilt after the stop no
//   longer lists the project, so the user's fresh confirmation continues with
//   the volume in place. A temporary path counts as gone only when `lstat`
//   finds no entry at the path. Without --after-stop, a
//   confirmed item that is gone is a difference. A listing that cannot run is
//   a difference for a Caller preview, and for any other manifest unless it
//   could not run there either. On a match it prints the targets, for a
//   proposed local branch `local <branch> <sha>`, the SHA to delete it at, and
//   for a proposed remote branch `lease <remote> <sha>`.
//
// Every displayed value, such as a path or command, is printed with control
// characters encoded as \xNN, so no target can print a line of its own; the
// `local` and `lease` lines are the only lines that start with those words.
// A --temp path is missing only when `lstat` finds no entry at it (ENOENT or
// ENOTDIR); a dangling symbolic link still occupies the path, and it or any
// other resolution failure, such as a symlink loop, means the check cannot
// run.
//
// The script reads git, process, and Docker state only; it never deletes,
// stops, or signals anything.
//
// Exit status:
//   0  the check passed
//   2  usage error: an unknown subcommand or option, a missing or repeated
//      option, an unsafe branch or remote name, a malformed fact, a manifest
//      path inside the worktree or that already exists, or an unreadable
//      confirmed manifest, including one of an earlier manifest version
//   3  the check failed: remote keeps the remote branch (cleanup continues
//      without it); local or manifest finds the local branch unmerged; manifest
//      --preview has a listing that cannot run; compare found a difference. The reasons are reported on stderr.
// Any other status, including 1, which node uses for a missing script or an
// uncaught error and this script uses when git or check-push-target.mjs cannot
// run or --out cannot be created, means the check could not run and stops the cleanup.

import { execFileSync, spawnSync } from "node:child_process";
import { closeSync, constants, existsSync, lstatSync, openSync, readFileSync, readlinkSync, realpathSync, writeSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Same pattern as check-branch-name.mjs, which exits on load and so cannot be
// imported; keep the two in step.
const SAFE_NAME = /^[A-Za-z0-9/._][A-Za-z0-9/._-]*$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const MANIFEST_VERSION = 2;

const here = path.dirname(fileURLToPath(import.meta.url));
const pushTargetScript = path.join(here, "check-push-target.mjs");
const runtimeScripts = path.join(here, "..", "..", "worktree-runtime-cleanup", "scripts");

const USAGE = [
  "usage: check-cleanup-targets.mjs remote <facts> [--preview]",
  "       check-cleanup-targets.mjs local <facts>",
  "       check-cleanup-targets.mjs manifest <facts> <targets> --out <file> [--preview]",
  "       check-cleanup-targets.mjs compare <facts> <targets> --confirmed <file> [--after-stop]",
  "facts: (--github <host> <owner>/<repo> | --azure <org> <project> <repo>) --branch <branch>",
  "       --pr-state <state> --pr-head <sha> --cross-repo true|false --default-branch <branch>",
  "       --protected true|false --open-prs <n> [--remote <name>]",
  "targets: (--worktree <path> | --no-worktree) [--temp <path>]...",
].join("\n");

// Encodes control characters, including tab and line breaks, so a displayed
// value always stays within its own field and line.
const display = (value) =>
  String(value).replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, (c) => {
    const code = c.charCodeAt(0);
    return code > 0xff ? `\\u${code.toString(16).padStart(4, "0")}` : `\\x${code.toString(16).padStart(2, "0")}`;
  });

// One output line of tab-separated fields, each displayed.
const row = (...fields) => fields.map(display).join("\t");

const usage = (reason) => {
  process.stderr.write(`${reason ? `${display(reason)}\n` : ""}${USAGE}\n`);
  process.exit(2);
};

const fail = (lines) => {
  process.stderr.write(`${lines.map(display).join("\n")}\n`);
  process.exit(3);
};

const cannotRun = (reason) => {
  process.stderr.write(`check could not run: ${display(reason)}\n`);
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

// A name compared without case, so names a case-insensitive ref store
// resolves to one loose ref file compare equal.
const foldName = (name) => name.normalize("NFKC").toLowerCase();

// Branch names that a case-insensitive ref store could treat as one.
const sameBranchName = (a, b) => foldName(a) === foldName(b);

// Resolves the remote by the push target rule; returns the remote, or null
// with the reason.
const resolveRemote = (facts) => {
  const args = [pushTargetScript, "resolve", `--${facts.provider}`, ...facts.repository];
  if (facts.remote !== undefined) args.push("--remote", facts.remote);
  const result = spawnSync(process.execPath, args, { encoding: "utf8" });
  const stderr = (result.stderr ?? "").trim();
  if (result.status === 0) {
    const [remote, head] = result.stdout.split("\n");
    // The push target rule binds a named Azure DevOps remote to the PR
    // repository; a named GitHub remote may name any repository on the host,
    // so bind it to the PR head repository here.
    if (facts.remote === undefined || facts.provider === "azure") return { remote };
    if (head?.toLowerCase() === facts.repository[1].toLowerCase()) return { remote };
    return { remote: null, reason: `remote ${JSON.stringify(remote)} names ${head || "no repository"}, not the PR head repository ${facts.repository[1]}` };
  }
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
  if (sameBranchName(facts.branch, facts.defaultBranch)) return kept(remote, "the branch is the default branch");
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

const git = (args) => {
  const result = spawnSync("git", args, { encoding: "utf8" });
  if (result.status !== 0) {
    return cannotRun(`git ${args.join(" ")} exited ${result.status ?? result.signal}: ${(result.stderr || result.error?.message || "").toString().trim()}`);
  }
  return result.stdout;
};

// Runs git and returns { status, stdout }; a status other than those
// `allowed` means the check cannot run.
const gitStatus = (args, allowed) => {
  const result = spawnSync("git", args, { encoding: "utf8" });
  if (!allowed.includes(result.status)) {
    return cannotRun(`git ${args.join(" ")} exited ${result.status ?? result.signal}: ${(result.stderr || result.error?.message || "").toString().trim()}`);
  }
  return { status: result.status, stdout: result.stdout };
};

// Looks up refs/heads/<branch> as git enumerates it. Returns { sha, symref }
// for a ref listed under exactly that name, { ambiguous } when another listed
// ref, loose or packed, has a case-equivalent name, { unresolved } when git
// omits the ref from the listing but it still exists, such as a dangling
// symbolic ref, and null only when absence is established independently.
// The worktrees and branches `git worktree list` reports checked out, or
// the reason its output cannot be trusted. Git before 2.36 has no -z: its
// line output counts only when every line is a known field, so a path that
// breaks a line holds the deletion.
const checkedOutBranches = () => {
  const z = gitStatus(["worktree", "list", "--porcelain", "-z"], [0, 129]);
  const fields = z.status === 0 ? z.stdout.split("\0") : git(["worktree", "list", "--porcelain"]).split("\n");
  const known = /^(?:worktree .+|HEAD [0-9a-f]+|branch refs\/.+|detached|bare|locked(?: .*)?|prunable(?: .*)?|)$/;
  const branches = [];
  let worktree = null;
  for (const field of fields) {
    if (z.status !== 0 && !known.test(field)) return `git worktree list printed a line that cannot be parsed: ${field}`;
    if (field.startsWith("worktree ")) worktree = field.slice("worktree ".length);
    else if (field.startsWith("branch ")) branches.push([worktree, field.slice("branch ".length)]);
  }
  return branches;
};

// Looks up refs/heads/<branch> from git's own output. Returns { sha, symref }
// for a ref listed under exactly that name, { held } when a listed ref or a
// checked-out branch differs from the name only by case, or when git omits
// the ref from its listing but it still resolves, such as a dangling
// symbolic ref, and null when no ref exists.
const localRef = (branch) => {
  const ref = `refs/heads/${branch}`;
  const variant = (name) => name !== ref && foldName(name) === foldName(ref);
  const rows = git(["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"])
    .split("\n").filter((line) => line !== "").map((line) => line.split("\0"));
  const variants = rows.map(([name]) => name).filter(variant);
  if (variants.length > 0) return { held: `a case-equivalent ref exists: ${variants.join(", ")}` };
  const checkedOut = checkedOutBranches();
  if (typeof checkedOut === "string") return { held: checkedOut };
  const used = checkedOut.find(([, name]) => variant(name));
  if (used) return { held: `the worktree at ${used[0]} has the case-equivalent ${used[1]} checked out` };

  const matches = rows.filter(([name]) => name === ref);
  if (matches.length > 1 || (matches.length === 1 && !SHA.test(matches[0][1]))) cannotRun(`unexpected git for-each-ref output for ${ref}`);
  if (matches.length === 1) return { sha: matches[0][1], symref: matches[0][2] };
  const symbolic = gitStatus(["symbolic-ref", "-q", ref], [0, 1]);
  if (symbolic.status === 0) return { held: `the local branch is a symbolic ref to ${symbolic.stdout.trim()} that git does not list` };
  const verify = gitStatus(["rev-parse", "--verify", "--quiet", ref], [0, 1]);
  if (verify.status === 0 || verify.stdout.trim() !== "") return { held: "the local branch is a ref git resolves but does not list under that name" };
  return null;
};

// Whether the local branch is proven merged by the provider facts; never
// exits on an unmet condition. A checkout that still uses the branch is left
// to `git branch -D`, which refuses it.
const checkLocal = (facts, { preview }) => {
  const found = localRef(facts.branch);
  if (found === null) return { status: "absent" };
  if (found.held) return { status: "unmerged", sha: null, reason: found.held };
  const { sha } = found;
  const unmerged = (reason) => ({ status: "unmerged", sha, reason });
  if (found.symref) return unmerged(`the local branch is a symbolic ref to ${found.symref}`);
  if (!preview && !facts.merged) return unmerged(facts.provider === "github" ? "the PR is not merged" : "the PR is not completed");
  if (sameBranchName(facts.branch, facts.defaultBranch)) return unmerged("the branch is the default branch");
  if (sha !== facts.head) return unmerged(`the local branch is at ${sha}, not the PR head ${facts.head}`);
  return { status: "proposed", sha };
};

const describeLocal = (result) => (result.status === "absent" ? "absent" : `${result.status}\t${result.sha ?? "-"}`);

const localCommand = (args) => {
  const facts = readFacts(parseOptions(args, FACTS));
  const result = checkLocal(facts, { preview: false });
  process.stdout.write(`${describeLocal(result)}\n`);
  if (result.status === "unmerged") fail([`local branch refs/heads/${facts.branch} cannot be deleted: ${result.reason}`]);
};

const realpathOrNull = (target) => {
  try {
    return realpathSync(target);
  } catch {
    return null;
  }
};

// A temporary path's real target, or null only when no entry exists at the
// path: a dangling symbolic link still occupies it.
const resolveTemp = (given) => {
  try {
    return realpathSync(given);
  } catch (error) {
    if (error.code !== "ENOENT" && error.code !== "ENOTDIR") return cannotRun(`cannot resolve --temp ${given}: ${error.code ?? error.message}`);
  }
  try {
    lstatSync(given);
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") return null;
    return cannotRun(`cannot resolve --temp ${given}: ${error.code ?? error.message}`);
  }
  return cannotRun(`cannot resolve --temp ${given}: a dangling symbolic link occupies the path`);
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
  const seen = new Set();
  const temps = (options["--temp"] ?? []).map(([given]) => {
    if (!path.isAbsolute(given)) usage(`--temp is not an absolute path: ${JSON.stringify(given)}`);
    if (seen.has(given)) usage(`repeated --temp: ${JSON.stringify(given)}`);
    seen.add(given);
    return { path: given, resolved: resolveTemp(given) };
  });
  return { worktree, temps };
};

// Runs a read-only listing script of worktree-runtime-cleanup and returns its
// rows split at tabs, or { unavailable } when it cannot run or prints a row
// with fewer than `columns` fields.
// Runs a read-only lookup and returns its stdout, or { unavailable }. Any
// output on stderr also makes it unavailable: a lookup that reports an error
// there but exits 0 never counts as finding nothing.
const runLookup = (label, command, args) => {
  const result = spawnSync(command, args, { encoding: "utf8" });
  const stderr = (result.stderr ?? "").trim();
  if (result.status !== 0 || stderr !== "") {
    const reason = (stderr || result.error?.message || "").split("\n")[0];
    return { unavailable: `${label} ${result.status === 0 ? "reported an error" : `exited ${result.status ?? result.signal}`}${reason ? `: ${reason}` : ""}` };
  }
  return { stdout: result.stdout };
};

const runListing = (name, worktree, columns) => {
  const script = path.join(runtimeScripts, name);
  if (!existsSync(script)) return { unavailable: `${name} not found` };
  const result = runLookup(name, "bash", [script, worktree]);
  if (result.unavailable) return result;
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
    const volumes = runLookup("docker volume ls", "docker", ["volume", "ls", "--filter", `label=com.docker.compose.project=${project}`, "--format", "{{.Name}}"]);
    if (volumes.unavailable) return { status: "unavailable", reason: volumes.unavailable, items: [] };
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

// The PR head repository as compared across manifests.
const repositoryOf = (facts) => facts.repository.map((part) => part.toLowerCase());

const buildManifest = (facts, targets, { preview }) => {
  const none = { status: "none", reason: "no worktree", items: [] };
  return {
    version: MANIFEST_VERSION,
    preview,
    provider: facts.provider,
    repository: repositoryOf(facts),
    worktree: targets.worktree,
    branch: facts.branch,
    local: checkLocal(facts, { preview }),
    remote: checkRemote(facts, { preview }),
    processes: targets.worktree ? listProcesses(targets.worktree) : none,
    compose: targets.worktree ? listCompose(targets.worktree) : none,
    temps: targets.temps,
  };
};

const unavailableSections = (manifest) =>
  ["processes", "compose"].filter((section) => manifest[section].status === "unavailable");

const formatTargets = (manifest) => {
  const lines = [row("worktree", manifest.worktree ?? "-")];
  const local = manifest.local;
  if (local.status === "proposed") lines.push(row("local branch", `delete refs/heads/${manifest.branch} at ${local.sha}`));
  else if (local.status === "absent") lines.push(row("local branch", `already absent: refs/heads/${manifest.branch}`));
  else lines.push(row("local branch", `unmerged: ${local.reason}`));
  const remote = manifest.remote;
  if (remote.status === "proposed") lines.push(row("remote branch", `delete ${remote.remote} refs/heads/${manifest.branch} at ${remote.sha}`));
  else if (remote.status === "absent") lines.push(row("remote branch", `already absent on ${remote.remote}`));
  else lines.push(row("remote branch", `kept: ${remote.reason}`));
  for (const item of manifest.processes.items) {
    lines.push(row("process", `pid ${item.pid}`, `started ${item.started}`, `cwd ${item.cwd}`, item.reason, item.command));
  }
  for (const item of manifest.compose.items) {
    lines.push(row("compose project", item.project, `working_dir ${item.working_dir}`, `volumes ${item.volumes.join(",") || "-"}`, item.reason));
  }
  for (const section of unavailableSections(manifest)) {
    lines.push(row(section, `unverified: ${manifest[section].reason}`));
  }
  for (const temp of manifest.temps) {
    lines.push(row("temporary path", `${temp.path}${temp.resolved && temp.resolved !== temp.path ? ` -> ${temp.resolved}` : ""}${temp.resolved ? "" : " (missing)"}`));
  }
  return `${lines.join("\n")}\n`;
};

const isSymlinkPath = (target) => {
  try {
    return readlinkSync(target) !== undefined;
  } catch {
    return false;
  }
};

// Creates the file exclusively with mode 0600 and writes through that
// descriptor, so a symlink or file planted at the path, even after the checks
// above, is never followed or overwritten.
const writeNewFile = (file, text) => {
  let fd;
  try {
    fd = openSync(file, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0), 0o600);
  } catch (error) {
    if (error.code === "EEXIST" || error.code === "ELOOP") usage(`--out already exists: ${JSON.stringify(file)}`);
    return cannotRun(`cannot create ${JSON.stringify(file)}: ${error.message}`);
  }
  try {
    writeSync(fd, text);
  } finally {
    closeSync(fd);
  }
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
  if (existsSync(outReal) || isSymlinkPath(outReal)) usage(`--out already exists: ${JSON.stringify(out)}`);

  const preview = Boolean(options["--preview"]);
  const manifest = buildManifest(facts, targets, { preview });
  if (manifest.local.status === "unmerged") fail([`local branch refs/heads/${manifest.branch} cannot be deleted: ${manifest.local.reason}`]);
  const unavailable = unavailableSections(manifest);
  if (preview && unavailable.length > 0) {
    fail(unavailable.map((section) => `${section} cannot be listed for a Caller preview: ${manifest[section].reason}`));
  }
  writeNewFile(outReal, `${JSON.stringify(manifest, null, 2)}\n`);
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

// Items of a not matched one for one in b, so duplicates count. Items match
// when the JSON of their identity tuples is equal, so no delimiter inside a
// field can make two different tuples collide.
const unmatched = (a, b, identity) => {
  const rest = b.map((item) => JSON.stringify(identity(item)));
  return a.filter((item) => {
    const i = rest.indexOf(JSON.stringify(identity(item)));
    if (i === -1) return true;
    rest.splice(i, 1);
    return false;
  });
};

const compareRuntime = (section, confirmed, current, identity, label, differences, stopped, verifyGone = () => null) => {
  const before = confirmed[section];
  const after = current[section];
  if (after.status === "unavailable" || before.status === "unavailable") {
    if (stopped && after.status === "unavailable") {
      differences.push(`${section} cannot be listed after the stop, so the stop is unverified: ${after.reason}`);
    } else if (confirmed.preview) {
      differences.push(`${section} cannot be listed and the confirmation came from a Caller preview: ${(after.status === "unavailable" ? after : before).reason}`);
    } else if (after.status !== before.status) {
      differences.push(`${section} was ${before.status === "unavailable" ? "unverified" : "listed"} at confirmation and is ${after.status === "unavailable" ? "unverified" : "listed"} now`);
    }
    return;
  }
  for (const item of unmatched(after.items, before.items, identity)) differences.push(`${section}: new or changed ${label(item)}`);
  for (const item of unmatched(before.items, after.items, identity)) {
    const remains = stopped ? verifyGone(item) : null;
    if (stopped && remains === null) stopped.push(label(item));
    else if (stopped) differences.push(`${section}: confirmed ${label(item)} is gone but ${remains}`);
    else differences.push(`${section}: confirmed ${label(item)} is gone or changed`);
  }
};

// For a Compose project that is gone, why its stop is not proven complete,
// or null. The project label still lists its volumes: a volume the
// confirmed manifest did not have is a new target, and for a worktree-owned
// project (reason exactly `under target`), whose stop deletes its volumes, a
// confirmed volume that remains means the stop did not finish. Projects with
// another reason keep their volumes by design.
const composeStopIncomplete = (item) => {
  const volumes = runLookup("docker volume ls", "docker", ["volume", "ls", "--filter", `label=com.docker.compose.project=${item.project}`, "--format", "{{.Name}}"]);
  if (volumes.unavailable) return `its volumes cannot be verified: ${volumes.unavailable}`;
  const listed = volumes.stdout.split("\n").filter((line) => line !== "");
  const added = listed.filter((volume) => !item.volumes.includes(volume));
  const remaining = item.reason === "under target" ? item.volumes.filter((volume) => listed.includes(volume)) : [];
  // Docker records no external flag, and this check never evaluates the
  // checkout's Compose configuration, so an external volume that the stop
  // keeps by design also holds here, and the user confirms fresh targets.
  const reasons = [];
  if (added.length > 0) reasons.push(`it has new volumes: ${added.join(", ")}`);
  if (remaining.length > 0) reasons.push(`its volumes remain: ${remaining.join(", ")}; one may be an external volume the stop keeps by design, so confirm the targets again at step 6 to continue with it in place`);
  return reasons.length > 0 ? reasons.join("; and ") : null;
};

// For a process that is gone from the listing, why it may still run, or
// null. The listing covers only processes tied to the worktree, so a process
// whose cwd moved away drops out while it keeps running: it is gone only when
// no process has its PID. A reused PID also holds; a fresh confirmation at
// step 6 continues.
const processSurvives = (item) => {
  if (!/^[1-9][0-9]*$/.test(String(item.pid))) return `its PID ${item.pid} cannot be checked`;
  try {
    process.kill(Number(item.pid), 0);
  } catch (error) {
    if (error.code === "ESRCH") return null;
    if (error.code !== "EPERM") return `its PID cannot be checked: ${error.message}`;
  }
  return `a process with PID ${item.pid} still runs`;
};

const compareCommand = (args) => {
  const options = parseOptions(args, { ...FACTS, ...TARGETS, "--confirmed": 1, "--after-stop": 0 });
  // After the confirmed runtime stop, a confirmed runtime resource that is
  // gone is expected and collected here instead of counting as a difference.
  const stopped = options["--after-stop"] ? [] : null;
  if (!options["--confirmed"]) usage("missing --confirmed");
  const facts = readFacts(options);
  const targets = readTargets(options);
  const confirmed = readConfirmed(options["--confirmed"][0]);
  const current = buildManifest(facts, targets, { preview: false });

  const differences = [];
  for (const field of ["provider", "repository", "worktree", "branch"]) {
    if (JSON.stringify(confirmed[field]) !== JSON.stringify(current[field])) differences.push(`${field}: confirmed ${JSON.stringify(confirmed[field])}, now ${JSON.stringify(current[field])}`);
  }

  let localDeleted = false;
  const localBefore = confirmed.local ?? {};
  const localAfter = current.local;
  if (localAfter.status === "absent" && localBefore.status === "proposed") {
    localDeleted = true;
  } else if (localAfter.status === "unmerged") {
    differences.push(`local branch refs/heads/${current.branch} cannot be deleted: ${localAfter.reason}`);
  } else if (localBefore.status !== localAfter.status || localBefore.sha !== localAfter.sha) {
    differences.push(`local branch: confirmed ${JSON.stringify(describeLocal(localBefore))}, now ${JSON.stringify(describeLocal(localAfter))}`);
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

  compareRuntime(
    "processes", confirmed, current,
    (item) => [item.pid, item.started, item.cwd],
    (item) => `process pid ${item.pid} started ${item.started} cwd ${item.cwd}`,
    differences,
    stopped,
    processSurvives,
  );
  compareRuntime(
    "compose", confirmed, current,
    (item) => [item.project, item.working_dir, item.volumes],
    (item) => `compose project ${item.project} working_dir ${item.working_dir} volumes ${JSON.stringify(item.volumes)}`,
    differences,
    stopped,
    composeStopIncomplete,
  );
  const tempIdentity = (temp) => [temp.path, temp.resolved];
  const confirmedTemps = confirmed.temps ?? [];
  // After the stop, a temporary path that no longer resolves stands for the
  // confirmed path it removed, one for one.
  let currentTemps = current.temps;
  const removedTemps = [];
  if (stopped) {
    const pool = [...confirmedTemps];
    currentTemps = current.temps.map((temp) => {
      if (temp.resolved !== null) return temp;
      const i = pool.findIndex((item) => item.path === temp.path && item.resolved !== null);
      if (i === -1) return temp;
      const [removed] = pool.splice(i, 1);
      removedTemps.push(removed);
      return removed;
    });
  }
  if (unmatched(confirmedTemps, currentTemps, tempIdentity).length > 0 || unmatched(currentTemps, confirmedTemps, tempIdentity).length > 0) {
    differences.push(`temporary paths: confirmed ${JSON.stringify(confirmedTemps.map(tempIdentity))}, now ${JSON.stringify(current.temps.map(tempIdentity))}`);
  }
  for (const temp of removedTemps) stopped.push(`temporary path ${temp.path}`);

  if (differences.length > 0) fail(["the cleanup targets differ from the confirmed manifest:", ...differences]);
  process.stdout.write(formatTargets(current));
  for (const item of stopped ?? []) process.stdout.write(`${row("stopped as confirmed", item)}\n`);
  if (localDeleted) process.stdout.write(`${row(`local branch already deleted: refs/heads/${current.branch}`)}\n`);
  if (hostDeleted) process.stdout.write(`${row(`remote branch already deleted by the host: ${after.remote} refs/heads/${current.branch}`)}\n`);
  // The authorization lines come last; branch, remote, and SHA are checked
  // safe names and SHAs, so they need no encoding.
  if (localAfter.status === "proposed") process.stdout.write(`local\t${current.branch}\t${localAfter.sha}\n`);
  if (after.status === "proposed") process.stdout.write(`lease\t${after.remote}\t${after.sha}\n`);
};

const [subcommand, ...rest] = process.argv.slice(2);
const subcommands = { remote: remoteCommand, local: localCommand, manifest: manifestCommand, compare: compareCommand };
if (!Object.hasOwn(subcommands, subcommand ?? "")) usage(subcommand === undefined ? "" : `unknown subcommand: ${JSON.stringify(subcommand)}`);
subcommands[subcommand](rest);
