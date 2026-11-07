#!/usr/bin/env node
// Check the push target rule for the publish skills.
//
// Push target rule: push only to the remote the user named, or to the single
// remote that names the repository, with an explicit
// `<branch>:refs/heads/<branch>` refspec. With more than one remote and none
// named, ask, even when exactly one of them names the repository: in a fork
// layout `gh repo view` can resolve the parent, and the one matching remote
// would then be the parent.
//
// Usage:
//   node check-push-target.mjs resolve --github <host> <owner>/<repo> [--remote <name>]
//   node check-push-target.mjs resolve --azure <org> <project> <repo> [--remote <name>]
//   node check-push-target.mjs pre --branch <branch> --remote <remote> --base <base>
//   node check-push-target.mjs post --branch <branch> --remote <remote>
//
// The caller passes the repository identity it resolved; this script reads
// only local git configuration and remote URLs, and makes no gh, az, or
// network call.
//
// resolve
//   Without --remote, the repository needs exactly one remote, and its fetch
//   URLs and every push URL (`git remote get-url --all` and `--push --all`,
//   after `insteadOf` rewriting) must name the given repository. With
//   --remote, the named remote must exist; for --github, its fetch and push
//   URLs must all name one `<owner>/<repo>` on <host>, which becomes the head
//   repository, and for --azure it is used as given.
//   Prints the remote on line 1 and, for --github, the head `<owner>/<repo>`
//   on line 2.
//   GitHub URLs: `https://[user@]<host>/<owner>/<repo>`, `ssh://` and `git://`
//   forms, and `[user@]<host>:<owner>/<repo>`; the scheme, user, port, letter
//   case, and a trailing `.git` or `/` are ignored. An SSH host alias names
//   another host and does not match.
//   Azure URLs: exactly the accepted remote URL shapes in
//   azure-devops-common/references/context.md, after decoding percent-encoding
//   and ignoring letter case, the `user@` part, and a trailing `.git` or `/`.
//
// pre
//   Reads `branch.<branch>.remote` and `branch.<branch>.merge` with
//   `--get-all`. Accepts no upstream, `refs/heads/<branch>` on <remote>, or
//   `refs/heads/<base>` on the local remote `.` or any other remote; for the
//   base it prints a note that the push replaces that upstream. Fails on more
//   than one value for either key and on any other upstream, which may back an
//   existing PR.
//
// post
//   Requires exactly `branch.<branch>.remote` = <remote> and
//   `branch.<branch>.merge` = `refs/heads/<branch>`.
//
// Exit status:
//   0  the check passed
//   2  usage error: an unknown subcommand or option, a missing or repeated
//      option, or a branch or remote name that is not a safe name
//   3  the check failed; the reason, and for resolve the candidate remotes,
//      are reported on stderr. For resolve the caller asks the user to name
//      the remote; for pre and post it stops and reports.
// Any other status, including 1, which node uses for a missing script or an
// uncaught error and this script uses when git cannot be read, means the
// check could not run.

import { execFileSync } from "node:child_process";

// Same pattern as check-branch-name.mjs, which exits on load and so cannot be
// imported; keep the two in step.
const SAFE_NAME = /^[A-Za-z0-9/._][A-Za-z0-9/._-]*$/;
// GitHub owner and repository names.
const SAFE_OWNER = /^[A-Za-z0-9][A-Za-z0-9-]*$/;
const SAFE_REPO = /^[A-Za-z0-9._-]+$/;

const USAGE = [
  "usage: check-push-target.mjs resolve --github <host> <owner>/<repo> [--remote <name>]",
  "       check-push-target.mjs resolve --azure <org> <project> <repo> [--remote <name>]",
  "       check-push-target.mjs pre --branch <branch> --remote <remote> --base <base>",
  "       check-push-target.mjs post --branch <branch> --remote <remote>",
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

// Parses `--name value...` options with fixed arity; anything else is a usage
// error.
const parseOptions = (args, spec) => {
  const options = {};
  for (let i = 0; i < args.length; ) {
    const name = args[i];
    const arity = spec[name];
    if (arity === undefined) usage(`unknown argument: ${JSON.stringify(name)}`);
    if (name in options) usage(`repeated option: ${name}`);
    const values = args.slice(i + 1, i + 1 + arity);
    if (values.length !== arity) usage(`missing value for ${name}`);
    options[name] = values;
    i += 1 + arity;
  }
  return options;
};

const requireSafe = (kind, value) => {
  if (!SAFE_NAME.test(value)) usage(`unsafe ${kind} name: ${JSON.stringify(value)}`);
};

// Runs git and returns its output lines. With allowMissing, git's exit 1 (as
// from `git config --get-all` for an unset key) means no lines.
const git = (args, { allowMissing = false } = {}) => {
  try {
    const out = execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    return out.split("\n").filter((line) => line !== "");
  } catch (error) {
    if (allowMissing && error.status === 1) return [];
    cannotRun(`git ${args.join(" ")}: ${(error.stderr || error.message || "").toString().trim()}`);
  }
};

const stripSuffix = (path) => path.replace(/\/+$/, "").replace(/\.git$/i, "");

// Splits a remote URL into a lower-cased host and its path, or null.
const splitUrl = (url) => {
  const scheme = url.match(/^([a-z][a-z0-9+.-]*):\/\/(?:[^@/]*@)?([^/:]+)(?::\d*)?\/(.*)$/i);
  if (scheme) return { host: scheme[2].toLowerCase(), path: scheme[3] };
  const scp = url.match(/^(?:[^@/:]+@)?([^/:]+):(?!\/\/)(.*)$/);
  if (scp) return { host: scp[1].toLowerCase(), path: scp[2] };
  return null;
};

// Returns { host, owner, repo } for a GitHub-style URL, or null.
const parseGithub = (url) => {
  const parts = splitUrl(url);
  if (!parts) return null;
  const segments = stripSuffix(parts.path).split("/");
  if (segments.length !== 2) return null;
  const [owner, repo] = segments;
  if (!SAFE_OWNER.test(owner) || !SAFE_REPO.test(repo)) return null;
  return { host: parts.host, owner, repo };
};

const decode = (text) => {
  try {
    return decodeURIComponent(text);
  } catch {
    return null;
  }
};

// Returns the lower-cased, decoded "org/project/repo" an Azure URL names, or
// null. Accepts exactly the shapes in azure-devops-common context.md.
const parseAzure = (url) => {
  const parts = splitUrl(url);
  if (!parts) return null;
  const segments = stripSuffix(parts.path).split("/");
  let named;
  if (/^https:\/\//i.test(url) && parts.host === "dev.azure.com" && segments.length === 4 && segments[2].toLowerCase() === "_git") {
    named = [segments[0], segments[1], segments[3]];
  } else if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(url) && parts.host === "ssh.dev.azure.com" && segments.length === 4 && segments[0].toLowerCase() === "v3") {
    named = segments.slice(1);
  } else {
    return null;
  }
  const decoded = named.map(decode);
  if (decoded.some((part) => !part)) return null;
  return decoded.join("/").toLowerCase();
};

const remoteUrls = (remote) => [
  ...git(["remote", "get-url", "--all", remote]),
  ...git(["remote", "get-url", "--push", "--all", remote]),
];

// Returns the single `<owner>/<repo>` every URL names on host, or null.
const githubRepoOf = (urls, host) => {
  const named = new Set();
  let display = null;
  for (const url of urls) {
    const parsed = parseGithub(url);
    if (!parsed || parsed.host !== host) return null;
    display ??= `${parsed.owner}/${parsed.repo}`;
    named.add(`${parsed.owner}/${parsed.repo}`.toLowerCase());
  }
  return named.size === 1 ? display : null;
};

const resolve = (args) => {
  const options = parseOptions(args, { "--github": 2, "--azure": 3, "--remote": 1 });
  const github = options["--github"];
  const azure = options["--azure"];
  if (Boolean(github) === Boolean(azure)) usage("resolve needs exactly one of --github or --azure");
  const named = options["--remote"]?.[0];
  if (named !== undefined) requireSafe("remote", named);

  let host;
  let expected;
  if (github) {
    host = github[0].toLowerCase();
    const repo = parseGithub(`https://${host}/${github[1]}`);
    if (!host || !repo) usage(`not a GitHub repository: ${JSON.stringify(`${github[0]} ${github[1]}`)}`);
    expected = `${repo.owner}/${repo.repo}`;
  } else {
    if (azure.some((part) => part === "")) usage("empty Azure DevOps organization, project, or repository");
    expected = azure.join("/").toLowerCase();
  }

  const remotes = git(["remote"]);

  if (named !== undefined) {
    if (!remotes.includes(named)) fail([`remote not found: ${JSON.stringify(named)}`]);
    if (azure) {
      process.stdout.write(`${named}\n`);
      return;
    }
    const head = githubRepoOf(remoteUrls(named), host);
    if (!head) fail([`remote ${JSON.stringify(named)} does not name one <owner>/<repo> on ${host} in its fetch and push URLs`]);
    process.stdout.write(`${named}\n${head}\n`);
    return;
  }

  const candidates = remotes.map((remote) => `candidate remote: ${JSON.stringify(remote)}`);
  if (remotes.length === 0) fail(["no remote; name the remote to push to"]);
  if (remotes.length > 1) fail(["more than one remote and none named; name the remote to push to", ...candidates]);

  const [remote] = remotes;
  if (!SAFE_NAME.test(remote)) fail([`remote name is not a safe name: ${JSON.stringify(remote)}`, ...candidates]);
  const urls = remoteUrls(remote);
  const matches = github
    ? githubRepoOf(urls, host)?.toLowerCase() === expected.toLowerCase()
    : urls.every((url) => parseAzure(url) === expected);
  if (!matches) fail([`remote ${JSON.stringify(remote)} does not name ${github ? `${host}/${expected}` : expected} in its fetch and every push URL`, ...candidates]);
  process.stdout.write(github ? `${remote}\n${expected}\n` : `${remote}\n`);
};

const readUpstream = (branch) => {
  const remotes = git(["config", "--get-all", `branch.${branch}.remote`], { allowMissing: true });
  const merges = git(["config", "--get-all", `branch.${branch}.merge`], { allowMissing: true });
  if (remotes.length > 1 || merges.length > 1) {
    fail([`branch ${JSON.stringify(branch)} has more than one upstream value: remote ${JSON.stringify(remotes)}, merge ${JSON.stringify(merges)}`]);
  }
  return { remote: remotes[0], merge: merges[0] };
};

const describe = ({ remote, merge }) => `remote ${JSON.stringify(remote ?? null)}, merge ${JSON.stringify(merge ?? null)}`;

const pre = (args) => {
  const options = parseOptions(args, { "--branch": 1, "--remote": 1, "--base": 1 });
  if (!options["--branch"] || !options["--remote"] || !options["--base"]) usage("pre needs --branch, --remote, and --base");
  const [branch] = options["--branch"];
  const [remote] = options["--remote"];
  const [base] = options["--base"];
  requireSafe("branch", branch);
  requireSafe("remote", remote);
  requireSafe("base branch", base);

  const upstream = readUpstream(branch);
  if (upstream.remote === undefined && upstream.merge === undefined) return;
  if (upstream.remote === remote && upstream.merge === `refs/heads/${branch}`) return;
  if (upstream.remote !== undefined && upstream.merge === `refs/heads/${base}`) {
    process.stdout.write(`upstream is the PR base branch (${describe(upstream)}); the push replaces it with ${remote}/${branch}\n`);
    return;
  }
  fail([`branch ${JSON.stringify(branch)} tracks another upstream (${describe(upstream)}); it may back an existing PR`]);
};

const post = (args) => {
  const options = parseOptions(args, { "--branch": 1, "--remote": 1 });
  if (!options["--branch"] || !options["--remote"]) usage("post needs --branch and --remote");
  const [branch] = options["--branch"];
  const [remote] = options["--remote"];
  requireSafe("branch", branch);
  requireSafe("remote", remote);

  const upstream = readUpstream(branch);
  if (upstream.remote === remote && upstream.merge === `refs/heads/${branch}`) return;
  fail([`after the push, branch ${JSON.stringify(branch)} tracks ${describe(upstream)}, not ${remote} refs/heads/${branch}`]);
};

const [subcommand, ...rest] = process.argv.slice(2);
const subcommands = { resolve, pre, post };
if (!Object.hasOwn(subcommands, subcommand ?? "")) usage(subcommand === undefined ? "" : `unknown subcommand: ${JSON.stringify(subcommand)}`);
subcommands[subcommand](rest);
