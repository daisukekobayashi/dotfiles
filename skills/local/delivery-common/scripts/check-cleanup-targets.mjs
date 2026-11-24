#!/usr/bin/env node
// Check the cleanup targets for the worktree cleanup skills.
//
// Usage:
//   node check-cleanup-targets.mjs github-source --github <host> <base-owner>/<base-repo> --branch <branch> [--remote <name>]
//   node check-cleanup-targets.mjs verify-merge --github <host> <base-owner>/<base-repo> --branch <branch> [--remote <name>] < <pr-json>
//   node check-cleanup-targets.mjs verify-merge --azure <source-org> <source-project> <source-repo> --source-repository-id <id> --branch <branch> [--remote <name>] < <pr-json>
//   node check-cleanup-targets.mjs remote <facts> [--preview]
//   node check-cleanup-targets.mjs local <facts>
//   node check-cleanup-targets.mjs manifest <facts> <targets> --out <file> [--preview]
//   node check-cleanup-targets.mjs compare <facts> <targets> --confirmed <file> [--resume-stop | --after-stop | --after-worktree-removal --confirmed-sha256 <hex>]
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
// github-source
//   Prints the selected GitHub source repository as <owner>/<repo> for
//   standalone PR lookup. Uses only local Git configuration and URLs.
//
// verify-merge
//   The standalone merge evidence gate. Reads the provider PR response on
//   stdin. Selects the source remote independently from the named remote,
//   the branch's exact upstream, or the only remote. A conflicting or
//   incomplete upstream holds. Azure's source repository and ID must come
//   from the selected remote and a separate repository lookup.
//   Succeeds only for the exact source repository, ref, merged state, and
//   local tip, even if the remote branch was already deleted. Prints nothing.
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
//   `list-stacks.sh <worktree>` with volumes marked for deletion or retention,
//   and the temporary paths with their resolved targets.
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
//   as unverified. Standalone manifests also print a `manifest sha256` row
//   for the exact bytes written, for the original confirmation to include.
//
// compare
//   Builds the manifest again, after the merge, and compares it with the
//   confirmed manifest (the Caller preview when the confirmation was combined,
//   otherwise the manifest the user confirmed). Processes are compared by PID,
//   start time, and cwd; Compose projects by name, working_dir, ownership,
//   volume inventory and deletion plan;
//   temporary paths by path and resolved target; each list as a multiset of
//   identity tuples;
//   the local branch by status and SHA; the rest, including the PR head
//   repository, exactly. The tolerated differences are a confirmed remote
//   branch that no longer exists, reported as already deleted by the host, and
//   a confirmed local branch that no longer exists, reported as already
//   deleted. A local branch that is `unmerged` now is a difference. With
//   --resume-stop before resuming, or --after-stop after the stop, a confirmed process,
//   Compose project, or temporary path that is gone is also expected and
//   printed as `stopped as confirmed`; a new or changed item is still a
//   difference, while a confirmed item still listed unchanged passes, since
//   the runtime cleanup's own survivor check catches a failed stop and leaves
//   uncertain or declined targets running by design. A listing that cannot
//   run holds when it was listed at confirmation; one already unverified at
//   confirmation stays unverified and passes, as in the strict compare.
//   A process counts as gone only when no process has its PID (`kill -0`,
//   which sends no signal, finds none), since the listing drops a running
//   process whose cwd leaves the worktree; a reused PID also holds. A Compose
//   project counts as gone only when its volume inventory is verifiable and
//   no new volume exists. --resume-stop permits outstanding confirmed volumes
//   whose identities and eligibility match. --after-stop requires confirmed
//   removals to be absent but permits intentional keeps. A temporary path
//   counts as gone only when `lstat` finds no entry. Without either stop mode, a
//   confirmed item that is gone is a difference. A listing that cannot run is
//   a difference for a Caller preview, and for any other manifest unless it
//   could not run there either. On a match it prints the targets, for a
//   proposed local branch `local <branch> <sha>`, the SHA to delete it at, and
//   for a proposed remote branch `lease <remote> <sha>`.
//   --after-worktree-removal resumes standalone cleanup before local branch
//   deletion. Use the original confirmed manifest kept in private storage,
//   its exact canonical --worktree path, and the --confirmed-sha256 from the
//   original trusted confirmation. Pass fresh facts for the same PR from
//   the original repository. The script checks the digest of the same raw
//   file bytes it will parse, up to 16 MiB. The path and registration must
//   both be gone, and the branch must still be eligible locally. Runtime
//   listings at confirmation and now must
//   be verifiable. The current path-scoped listings must be empty, and the
//   checks for confirmed PIDs, Compose projects and volumes, temporary paths
//   and branch targets still apply. A Caller preview does not qualify.
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
import { createHash } from "node:crypto";
import { closeSync, constants, existsSync, fstatSync, lstatSync, openSync, readFileSync, readlinkSync, readSync, realpathSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Same pattern as check-branch-name.mjs, which exits on load and so cannot be
// imported; keep the two in step.
const SAFE_NAME = /^[A-Za-z0-9/._][A-Za-z0-9/._-]*$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const REPOSITORY_ID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const GITHUB_HOST = /^[A-Za-z0-9.-]+$/;
const GITHUB_REPOSITORY = /^[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9._-]+$/;
const GITHUB_PR_URL = /^https:\/\/([A-Za-z0-9.-]+)\/([^/]+\/[^/]+)\/pull\/[1-9][0-9]*$/;
const AZURE_COMPONENT = /^(?=.*[A-Za-z0-9])[A-Za-z0-9. _-]+$/;
// The runtime executor reads this format. Keep Git-only checks usable when
// the runtime skill is unavailable.
const MANIFEST_VERSION = 3;
const MAX_CONFIRMED_BYTES = 16 * 1024 * 1024;

const here = path.dirname(fileURLToPath(import.meta.url));
const pushTargetScript = path.join(here, "check-push-target.mjs");
const runtimeScripts = path.join(here, "..", "..", "worktree-runtime-cleanup", "scripts");
let volumeTools;

const USAGE = [
  "usage: check-cleanup-targets.mjs github-source --github <host> <base-owner>/<base-repo> --branch <branch> [--remote <name>]",
  "       check-cleanup-targets.mjs verify-merge --github <host> <base-owner>/<base-repo> --branch <branch> [--remote <name>] < <pr-json>",
  "       check-cleanup-targets.mjs verify-merge --azure <source-org> <source-project> <source-repo> --source-repository-id <id> --branch <branch> [--remote <name>] < <pr-json>",
  "       check-cleanup-targets.mjs remote <facts> [--preview]",
  "       check-cleanup-targets.mjs local <facts>",
  "       check-cleanup-targets.mjs manifest <facts> <targets> --out <file> [--preview]",
  "       check-cleanup-targets.mjs compare <facts> <targets> --confirmed <file> [--resume-stop | --after-stop | --after-worktree-removal --confirmed-sha256 <hex>]",
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

const runPushTargetCheck = (facts, literalAzureRepo = false) => {
  const args = [pushTargetScript, "resolve", `--${facts.provider}`, ...facts.repository];
  if (facts.remote !== undefined) args.push("--remote", facts.remote);
  if (literalAzureRepo) args.push("--azure-literal-repo-name");
  return spawnSync(process.execPath, args, { encoding: "utf8" });
};

// Resolves the remote by the push target rule; returns the remote, or null
// with the reason.
const resolveRemote = (facts, { quiet = false, literalAzureRepo = false } = {}) => {
  const result = runPushTargetCheck(facts, literalAzureRepo);
  const stderr = (result.stderr ?? "").trim();
  if (result.status === 0) {
    const [remote, head] = result.stdout.split("\n");
    // The push target rule binds a named Azure DevOps remote to the PR
    // repository; a named GitHub remote may name any repository on the host,
    // so bind it to the PR head repository here.
    if (facts.remote === undefined || facts.provider === "azure") return { remote };
    if (head?.toLowerCase() === facts.repository[1].toLowerCase()) return { remote };
    if (quiet) return { remote: null };
    return { remote: null, reason: `remote ${JSON.stringify(remote)} names ${head || "no repository"}, not the PR head repository ${facts.repository[1]}` };
  }
  if (quiet && result.status !== 3) return cannotRun("could not verify the source remote");
  if (quiet) return { remote: null };
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

// Runs git and returns { status, stdout, stderr }; a status other than those
// `allowed` means the check cannot run.
const gitStatus = (args, allowed) => {
  const result = spawnSync("git", args, { encoding: "utf8" });
  if (!allowed.includes(result.status)) {
    return cannotRun(`git ${args.join(" ")} exited ${result.status ?? result.signal}: ${(result.stderr || result.error?.message || "").toString().trim()}`);
  }
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
};

const worktreeFields = () => {
  const z = gitStatus(["worktree", "list", "--porcelain", "-z"], [0, 129]);
  if (z.status === 0) return { fields: z.stdout.split("\0"), nul: true, stderr: z.stderr };
  const lines = gitStatus(["worktree", "list", "--porcelain"], [0]);
  return { fields: lines.stdout.split("\n"), nul: false, stderr: lines.stderr };
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
  const { fields, nul } = worktreeFields();
  const known = /^(?:worktree .+|HEAD [0-9a-f]+|branch refs\/.+|detached|bare|locked(?: .*)?|prunable(?: .*)?|)$/;
  const branches = [];
  let worktree = null;
  for (const field of fields) {
    if (!nul && !known.test(field)) return `git worktree list printed a line that cannot be parsed: ${field}`;
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

const mergeEvidenceFailure = (reason) => fail([`standalone cleanup could not verify the merged PR: ${reason}`]);

const configValues = (key) => {
  const { status, stdout, stderr } = spawnSync("git", ["config", "--null", "--get-all", key], { encoding: "utf8" });
  if (status === 1 && !stdout && !stderr) return [];
  if (status !== 0 || stderr || !stdout.endsWith("\0")) return cannotRun("could not read the local branch upstream");
  return stdout.split("\0").slice(0, -1);
};

// An exact upstream can still identify the source after the host deletes it.
// Never select a remote based on the repository in the PR response.
const sourceRemote = (branch, named) => {
  const remotes = configValues(`branch.${branch}.remote`);
  const refs = configValues(`branch.${branch}.merge`);
  if (remotes.length === 0 && refs.length === 0) return named;
  if (remotes.length !== 1 || refs.length !== 1 || !SAFE_NAME.test(remotes[0]) ||
      remotes[0] === "." || refs[0] !== `refs/heads/${branch}` || (named !== undefined && named !== remotes[0])) {
    mergeEvidenceFailure("the named remote or branch upstream does not establish one exact source remote");
  }
  return remotes[0];
};

const validGithubRepository = (github) =>
  github !== undefined && GITHUB_HOST.test(github[0]) && GITHUB_REPOSITORY.test(github[1]);

const githubSourceCommand = (args) => {
  const options = parseOptions(args, { "--github": 2, "--branch": 1, "--remote": 1 });
  const repository = options["--github"];
  const branch = options["--branch"]?.[0];
  const named = options["--remote"]?.[0];
  if (!validGithubRepository(repository) || !branch || !SAFE_NAME.test(branch) ||
      (named !== undefined && !SAFE_NAME.test(named))) {
    usage("github-source requires a valid GitHub base repository, safe branch and optional safe remote");
  }
  let remote = sourceRemote(branch, named);
  if (remote === undefined) {
    const remotes = git(["remote"]).trimEnd().split("\n");
    if (remotes.length !== 1 || !SAFE_NAME.test(remotes[0])) {
      mergeEvidenceFailure("select one unambiguous local source remote before PR lookup");
    }
    [remote] = remotes;
  }
  // The named GitHub resolver derives the repository from all the remote's
  // effective URLs on the selected host. The base only scopes the host.
  const result = runPushTargetCheck({ provider: "github", repository, remote });
  if (result.status === 3) mergeEvidenceFailure("the selected remote does not identify one GitHub source repository");
  if (result.status !== 0 || result.stderr) cannotRun("could not read the GitHub source repository");
  const [resolved, source] = result.stdout.split("\n");
  if (resolved !== remote || !GITHUB_REPOSITORY.test(source ?? "")) cannotRun("could not read the GitHub source repository");
  process.stdout.write(`${source}\n`);
};

const pullRequest = () => {
  let pr;
  try {
    pr = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return mergeEvidenceFailure("the PR response is not a JSON object");
  }
  if (!pr || typeof pr !== "object" || Array.isArray(pr)) {
    return mergeEvidenceFailure("the PR response is not a JSON object");
  }
  return pr;
};

const githubSource = (pr, [host, base]) => {
  const owner = pr.headRepositoryOwner?.login;
  const name = pr.headRepository?.name;
  if (typeof owner !== "string" || typeof name !== "string" || !GITHUB_REPOSITORY.test(`${owner}/${name}`)) {
    return mergeEvidenceFailure("the GitHub PR does not identify its source repository");
  }
  const source = `${owner}/${name}`;
  const prUrl = typeof pr.url === "string" ? pr.url.match(GITHUB_PR_URL) : null;
  if (prUrl?.[1].toLowerCase() !== host.toLowerCase() || prUrl?.[2].toLowerCase() !== base.toLowerCase() ||
      pr.isCrossRepository !== (base.toLowerCase() !== source.toLowerCase())) {
    return mergeEvidenceFailure("the GitHub PR repository or fork metadata does not match the lookup");
  }
  return [host, source];
};

const isRepositoryId = (id) => typeof id === "string" && REPOSITORY_ID.test(id);

const verifyMergeCommand = (args) => {
  const options = parseOptions(args, {
    "--github": 2, "--azure": 3, "--source-repository-id": 1, "--branch": 1, "--remote": 1,
  });
  const github = options["--github"];
  const azure = options["--azure"];
  const expectedAzureId = options["--source-repository-id"]?.[0];
  const branch = options["--branch"]?.[0];
  const named = options["--remote"]?.[0];
  if (!branch || !SAFE_NAME.test(branch) || (named !== undefined && !SAFE_NAME.test(named))) {
    usage("verify-merge requires a safe branch and, when given, a safe remote");
  }
  if (Boolean(github) === Boolean(azure) ||
      (github && (!validGithubRepository(github) || expectedAzureId !== undefined)) ||
      (azure && (!azure.every((part) => AZURE_COMPONENT.test(part)) || !isRepositoryId(expectedAzureId)))) {
    usage("verify-merge requires a valid GitHub base repository or Azure DevOps source repository and ID");
  }
  const remote = sourceRemote(branch, named);
  const pr = pullRequest();
  let repository;
  let head;
  if (github) {
    if (pr.state !== "MERGED" || pr.headRefName !== branch) {
      mergeEvidenceFailure("the GitHub PR is not merged from the exact source branch");
    }
    repository = githubSource(pr, github);
    head = pr.headRefOid;
  } else {
    if (pr.status !== "completed" || pr.sourceRefName !== `refs/heads/${branch}`) {
      mergeEvidenceFailure("the Azure DevOps PR is not completed from the exact source ref");
    }
    const targetId = pr.repository?.id;
    const isFork = pr.forkSource != null;
    const sourceId = isFork ? pr.forkSource?.repository?.id : targetId;
    if (!Object.hasOwn(pr, "forkSource") || !isRepositoryId(targetId) || !isRepositoryId(sourceId) ||
        (pr.forkSource?.name != null && pr.forkSource.name !== pr.sourceRefName) ||
        (isFork && sourceId.toLowerCase() === targetId.toLowerCase()) ||
        sourceId.toLowerCase() !== expectedAzureId.toLowerCase()) {
      mergeEvidenceFailure("the Azure DevOps PR does not identify the expected source repository");
    }
    repository = azure;
    head = pr.lastMergeSourceCommit?.commitId;
  }
  const resolved = resolveRemote(
    { provider: github ? "github" : "azure", repository, remote },
    { quiet: true, literalAzureRepo: Boolean(azure) },
  );
  if (!resolved.remote) {
    mergeEvidenceFailure("the PR source repository does not match one exact local source remote");
  }
  const local = localRef(branch);
  if (typeof head !== "string" || !SHA.test(head) || !local || local.held || local.symref || local.sha !== head) {
    mergeEvidenceFailure("the PR source commit does not match the exact local branch tip");
  }
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

const readTargets = (options, afterWorktreeRemoval = false) => {
  const worktreeOption = options["--worktree"];
  if (Boolean(worktreeOption) === Boolean(options["--no-worktree"])) usage("exactly one of --worktree or --no-worktree is required");
  let worktree = null;
  if (worktreeOption) {
    if (!path.isAbsolute(worktreeOption[0])) usage(`--worktree is not an absolute path: ${JSON.stringify(worktreeOption[0])}`);
    worktree = afterWorktreeRemoval ? worktreeOption[0] : realpathOrNull(worktreeOption[0]);
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

// The approved path is already canonical. A missing or redirected parent,
// a dangling symlink at the target, and a failed lookup do not prove removal.
const checkWorktreePathAbsent = (worktree) => {
  const parent = path.dirname(worktree);
  try {
    if (realpathSync(parent) !== parent) fail([`the confirmed worktree parent changed: ${parent}`]);
  } catch (error) {
    return cannotRun(`cannot resolve the confirmed worktree parent ${parent}: ${error.message}`);
  }
  try {
    lstatSync(worktree);
  } catch (error) {
    if (error.code === "ENOENT") return;
    return cannotRun(`cannot check the confirmed worktree path ${worktree}: ${error.message}`);
  }
  fail([`the confirmed worktree path still exists: ${worktree}`]);
};

const checkWorktreeUnregistered = (worktree, branch) => {
  const { fields, stderr } = worktreeFields();
  const validField = /^(?:worktree .+|HEAD [0-9a-f]+|branch refs\/.+|detached|bare|locked(?: .*)?|prunable(?: .*)?|)$/s;
  if (stderr?.trim() || !fields[0]?.startsWith("worktree ") ||
      fields.at(-2) !== "" || fields.at(-1) !== "" ||
      fields.some((field) => !validField.test(field))) {
    cannotRun("git worktree list did not give a complete worktree inventory");
  }
  for (const field of fields) {
    if (field.startsWith("worktree ")) {
      const registered = field.slice("worktree ".length);
      if (!path.isAbsolute(registered)) cannotRun("git worktree list included a non-absolute or quoted path");
      const normalized = path.normalize(registered);
      if (normalized === worktree) {
        fail([`the confirmed worktree path is still registered: ${worktree}`]);
      }
      if (foldName(normalized) === foldName(worktree)) {
        const actual = realpathOrNull(registered);
        if (actual === null || actual === worktree) {
          fail([`a Git worktree registration may still refer to the confirmed path: ${registered}`]);
        }
      }
    }
    if (field.startsWith("branch ") && sameBranchName(field.slice("branch ".length), `refs/heads/${branch}`)) {
      fail([`the confirmed branch is checked out in a worktree: ${branch}`]);
    }
  }
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
    const names = volumes.stdout.split("\n").filter(Boolean).sort();
    const cause = reason.join("\t");
    const plan = cause === "under target" ? volumeTools?.planVolumeRemoval(project, workingDir, names) : null;
    items.push({
      project,
      counts,
      working_dir: workingDir,
      reason: cause,
      volumes: names,
      daemon: plan?.daemon ?? null,
      configFiles: plan?.configFiles ?? [],
      deleteVolumes: plan?.deleteVolumes ?? [],
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
    const deletion = item.deleteVolumes.map(({ name }) => name);
    const retained = item.volumes.filter((name) => !deletion.includes(name));
    lines.push(row("compose project", item.project, `working_dir ${item.working_dir}`,
      `delete volumes ${deletion.join(",") || "-"}`, `retain volumes ${retained.join(",") || "-"}`, item.reason));
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
const writeNewFile = (file, bytes) => {
  let fd;
  try {
    fd = openSync(file, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0), 0o600);
  } catch (error) {
    if (error.code === "EEXIST" || error.code === "ELOOP") usage(`--out already exists: ${JSON.stringify(file)}`);
    return cannotRun(`cannot create ${JSON.stringify(file)}: ${error.message}`);
  }
  try {
    writeFileSync(fd, bytes);
  } finally {
    closeSync(fd);
  }
};

const isInside = (child, parent) => child === parent || child.startsWith(`${parent}${path.sep}`);
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

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
  const bytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  writeNewFile(outReal, bytes);
  process.stdout.write(formatTargets(manifest));
  if (!preview) process.stdout.write(row("manifest sha256", sha256(bytes)) + "\n");
};

// Read a bounded snapshot from one descriptor. Private storage protects the
// inventory's confidentiality; the original digest binds its contents.
const readConfirmedBytes = (file) => {
  const uid = process.getuid?.();
  if (uid === undefined || constants.O_NOFOLLOW === undefined || constants.O_NONBLOCK === undefined) {
    throw new Error("private confirmation storage cannot be verified on this platform");
  }
  if (!path.isAbsolute(file) || path.normalize(file) !== file) {
    throw new Error("the private confirmation path must be canonical and absolute");
  }
  const parent = path.dirname(file);
  const directory = lstatSync(parent);
  if (!directory.isDirectory() || directory.uid !== uid || (directory.mode & 0o077) !== 0) {
    throw new Error("the confirmation directory must be owned by the current user and private (mode 700)");
  }
  if (realpathSync(parent) !== parent) throw new Error("the private confirmation directory must be its own real path");
  const named = lstatSync(file);
  if (!named.isFile()) throw new Error("the confirmation must be a regular file");
  const fd = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.dev !== named.dev || stat.ino !== named.ino) {
      throw new Error("the confirmation file changed while it was opened");
    }
    if (stat.uid !== uid || (stat.mode & 0o077) !== 0) {
      throw new Error("the confirmation must be owned by the current user and private (mode 600)");
    }
    if (stat.size > MAX_CONFIRMED_BYTES) throw new Error("the confirmation exceeds 16 MiB");
    const bytes = Buffer.alloc(stat.size);
    for (let offset = 0; offset < bytes.length;) {
      const count = readSync(fd, bytes, offset, bytes.length - offset, null);
      if (count === 0) throw new Error("the confirmation size changed during the read");
      offset += count;
    }
    const extra = Buffer.alloc(1);
    if (readSync(fd, extra, 0, extra.length, null) !== 0) throw new Error("the confirmation size changed during the read");
    return bytes;
  } finally {
    closeSync(fd);
  }
};

const readConfirmed = (file, expectedDigest) => {
  let manifest;
  try {
    if (expectedDigest === undefined) {
      manifest = JSON.parse(readFileSync(file, "utf8"));
    } else {
      const bytes = readConfirmedBytes(file);
      if (sha256(bytes) !== expectedDigest) throw new Error("the confirmed manifest does not match the original SHA-256");
      manifest = JSON.parse(bytes.toString("utf8"));
    }
  } catch (error) {
    return usage(`cannot read the confirmed manifest ${JSON.stringify(file)}: ${error.message}`);
  }
  if (manifest?.version !== MANIFEST_VERSION) {
    const next = expectedDigest === undefined ? "; preview and confirm again" : "";
    usage(`not a version ${MANIFEST_VERSION} cleanup target manifest${next}`);
  }
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

const compareRuntime = (section, confirmed, current, identity, label, differences, stopped, verifyGone) => {
  const before = confirmed[section];
  const after = current[section];
  if (after.status === "unavailable" || before.status === "unavailable") {
    // A section already unverified at confirmation stays unverified, as the
    // runtime cleanup reports it and continues; one listed at confirmation
    // must be listable to show the stop removed its targets.
    if (stopped && after.status === "unavailable" && before.status !== "unavailable") {
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

// A confirmed project may be gone while its volume cleanup is in progress.
// New project members hold, but intentional keeps may outlive the stack.
const composeStopIncomplete = (item, resume) => {
  const volumes = runLookup("docker volume ls", "docker", ["volume", "ls", "--filter", `label=com.docker.compose.project=${item.project}`, "--format", "{{.Name}}"]);
  if (volumes.unavailable) return `its volumes cannot be verified: ${volumes.unavailable}`;
  const listed = volumes.stdout.split("\n").filter((line) => line !== "");
  const added = listed.filter((volume) => !item.volumes.includes(volume));
  let remaining = [];
  try {
    if (item.deleteVolumes.length > 0) {
      if (!volumeTools) return "its confirmed volume removals cannot be verified: runtime volume helper unavailable";
      remaining = volumeTools.remainingVolumeRemovals(item, { verifyEligibility: resume });
    }
  } catch (error) {
    return `its volume removal targets cannot be verified: ${error.message}`;
  }
  const reasons = [];
  if (added.length > 0) reasons.push(`it has new volumes: ${added.join(", ")}`);
  if (!resume && remaining.length > 0) reasons.push(`confirmed volumes remain: ${remaining.map(({ name }) => name).join(", ")}`);
  return reasons.length > 0 ? reasons.join("; and ") : null;
};

// A Compose project with containers can disappear from the path-scoped
// listing when its working_dir label changes. Recheck confirmed names as well.
const composeWorktreeRemovalIncomplete = (item) => {
  const containers = runLookup("docker ps", "docker", ["ps", "-a", "--filter", `label=com.docker.compose.project=${item.project}`, "--format", "{{.ID}}"]);
  if (containers.unavailable) return `its containers cannot be verified: ${containers.unavailable}`;
  if (containers.stdout.trim() !== "") return "it still has containers";
  return composeStopIncomplete(item, false);
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
  const options = parseOptions(args, {
    ...FACTS, ...TARGETS, "--confirmed": 1, "--confirmed-sha256": 1,
    "--resume-stop": 0, "--after-stop": 0, "--after-worktree-removal": 0,
  });
  const resumeStop = Boolean(options["--resume-stop"]);
  const afterStop = Boolean(options["--after-stop"]);
  const afterWorktreeRemoval = Boolean(options["--after-worktree-removal"]);
  const modes = [resumeStop, afterStop, afterWorktreeRemoval].filter(Boolean);
  if (modes.length > 1) usage("choose one runtime comparison mode");
  const expectedDigest = options["--confirmed-sha256"]?.[0];
  if (afterWorktreeRemoval) {
    if (expectedDigest === undefined) usage("missing --confirmed-sha256 for worktree removal resume");
    if (expectedDigest.length !== 64 || !/^[0-9a-f]+$/.test(expectedDigest)) {
      usage("--confirmed-sha256 must be exactly 64 lowercase hex digits");
    }
  } else if (expectedDigest !== undefined) {
    usage("--confirmed-sha256 requires --after-worktree-removal");
  }
  // In a stop or removal mode, confirmed and now absent runtimes are expected.
  const stopped = modes.length > 0 ? [] : null;
  if (!options["--confirmed"]) usage("missing --confirmed");
  const facts = readFacts(options);
  const targets = readTargets(options, afterWorktreeRemoval);
  const confirmed = readConfirmed(options["--confirmed"][0], expectedDigest);
  if (afterWorktreeRemoval) {
    if (confirmed.preview !== false) fail(["worktree removal resume requires the original standalone confirmation"]);
    if (!targets.worktree || path.normalize(targets.worktree) !== targets.worktree || targets.worktree !== confirmed.worktree) {
      fail(["worktree removal resume requires the exact confirmed worktree path"]);
    }
    checkWorktreePathAbsent(targets.worktree);
  }
  const current = buildManifest(facts, targets, { preview: false });

  const differences = [];
  for (const field of ["provider", "repository", "worktree", "branch"]) {
    if (JSON.stringify(confirmed[field]) !== JSON.stringify(current[field])) differences.push(`${field}: confirmed ${JSON.stringify(confirmed[field])}, now ${JSON.stringify(current[field])}`);
  }

  let localDeleted = false;
  const localBefore = confirmed.local ?? {};
  const localAfter = current.local;
  if (afterWorktreeRemoval && localAfter.status !== "proposed") {
    differences.push(`the confirmed local branch must still be eligible for deletion: ${localAfter.reason ?? localAfter.status}`);
  } else if (localAfter.status === "absent" && localBefore.status === "proposed") {
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

  if (afterWorktreeRemoval) {
    for (const section of ["processes", "compose"]) {
      if (confirmed[section].status !== "ok" || current[section].status !== "ok") {
        differences.push(`${section}: worktree removal resume requires verified listings at confirmation and now`);
      } else if (current[section].items.length > 0) {
        differences.push(`${section}: resources are still listed under the removed worktree`);
      }
    }
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
    (item) => [item.project, item.working_dir, item.reason, item.volumes, item.daemon, item.configFiles, item.deleteVolumes],
    (item) => `compose project ${item.project} working_dir ${item.working_dir} volumes ${JSON.stringify(item.volumes)}`,
    differences,
    stopped,
    (item) => afterWorktreeRemoval ? composeWorktreeRemovalIncomplete(item) : composeStopIncomplete(item, resumeStop),
  );
  if (afterStop) {
    for (const item of confirmed.compose.items) {
      if (item.deleteVolumes.length > 0 && current.compose.items.some((live) => live.project === item.project)) {
        differences.push(`compose project ${item.project} still has containers and confirmed volume removals`);
      }
    }
  }
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
  if (afterWorktreeRemoval) {
    checkWorktreeUnregistered(targets.worktree, facts.branch);
    checkWorktreePathAbsent(targets.worktree);
  }
  process.stdout.write(formatTargets(afterWorktreeRemoval ? { ...current, worktree: null } : current));
  if (afterWorktreeRemoval) process.stdout.write(row("worktree already removed", targets.worktree) + "\n");
  const stopLabel = resumeStop ? "matched for resume" : "stopped as confirmed";
  for (const item of stopped ?? []) process.stdout.write(row(stopLabel, item) + "\n");
  if (localDeleted) process.stdout.write(`${row(`local branch already deleted: refs/heads/${current.branch}`)}\n`);
  if (hostDeleted) process.stdout.write(`${row(`remote branch already deleted by the host: ${after.remote} refs/heads/${current.branch}`)}\n`);
  // The authorization lines come last; branch, remote, and SHA are checked
  // safe names and SHAs, so they need no encoding.
  if (localAfter.status === "proposed") process.stdout.write(`local\t${current.branch}\t${localAfter.sha}\n`);
  if (after.status === "proposed") process.stdout.write(`lease\t${after.remote}\t${after.sha}\n`);
};

const [subcommand, ...rest] = process.argv.slice(2);
const subcommands = {
  "github-source": githubSourceCommand,
  "verify-merge": verifyMergeCommand,
  remote: remoteCommand,
  local: localCommand,
  manifest: manifestCommand,
  compare: compareCommand,
};
if (!Object.hasOwn(subcommands, subcommand ?? "")) usage(subcommand === undefined ? "" : `unknown subcommand: ${JSON.stringify(subcommand)}`);
if (subcommand === "manifest" || subcommand === "compare") {
  try {
    const helper = await import(pathToFileURL(path.join(runtimeScripts, "remove-compose-volumes.mjs")).href);
    if (helper.CLEANUP_MANIFEST_VERSION === MANIFEST_VERSION) volumeTools = helper;
  } catch {
    // An absent or incomplete runtime skill gives no deletion candidates.
    // A previously confirmed deletion holds when it can no longer be checked.
  }
}
subcommands[subcommand](rest);
