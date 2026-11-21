#!/usr/bin/env node
// Stop the process trees that one Codex review run, or one set of runs started
// together, started under its target worktree.
//
// Usage:
//   node stop-run-processes.mjs record <target> <record-file>
//   node stop-run-processes.mjs stop <target> <record-file> [--wait <seconds>]
//
// record
//   Before the run, writes the current process table, every process's PID,
//   parent PID, and start time, with the target's real path to <record-file>.
//   The file must not exist and must lie outside the target; it is created
//   exclusively with mode 0600 and holds no command lines.
//
// stop
//   After the run, whether it succeeded or failed, lists the target with
//   list-processes.sh beside this script and takes a new process table. A
//   process is one the run started only when all of these hold:
//   - its PID and start time are absent from the record;
//   - list-processes.sh lists it with reason exactly "cwd under target" (a
//     --cwd argument alone never counts) and a cwd without a backslash, which
//     the listing uses for escaped and ambiguous names;
//   - its cwd is not inside a worktree registered below the target, as
//     `git worktree list --porcelain -z` of the target reports;
//   - it has no tty;
//   - its parent is pid 1 or 0, or itself a process the run started.
//   Any other listed process is reported "left" with the reason and never
//   signaled: one that existed before the run, one under a parent that did
//   (such as another session's shell, wherever its cwd is), and one under a
//   new parent outside the target. On a host where an orphan is reparented to
//   a pre-existing subreaper rather than pid 1, its tree is left and reported.
//   The tops of the started trees get SIGTERM first; each one's start time is
//   read again immediately before its signal, and a changed one is not
//   signaled. After --wait seconds (default 10), every started process still
//   running with the same start time, even reparented, gets SIGTERM once
//   more, and the script waits half as long again. It sends no other signal.
//
// Output of stop: one tab-separated line per reported process,
//   <status> <pid> <ppid> <started> <cwd> <reason> <command>
// with <started>, <cwd>, and <command> as list-processes.sh prints them under
// LC_ALL=C, then a last line "teardown <verified|none|leftovers>". Statuses:
//   stopped        exited after its tree's first SIGTERM
//   stopped-retry  exited after the second SIGTERM
//   gone           exited before it was signaled
//   running        still running after the second SIGTERM
//   unverified     not signaled: its start time changed (PID reuse), its
//                  parent was not found, or it could not be read or signaled
//   left           not started by the run; <reason> says why
//
// Exit status:
//   0  stop: every started process exited, or the run started none; record:
//      written
//   1  could not run, and nothing was signaled: list-processes.sh, ps, or git
//      failed, wrote to stderr, or ran past 120 seconds, or the record is
//      unreadable or names another target. The teardown is unverified.
//   2  usage error: an unknown subcommand or option, a target that is not a
//      directory, or a record path that exists or lies inside the target
//   3  stop: a started process is still running or unverified
// Leftovers never change a review's result; worktree cleanup handles them.
import { spawnSync } from "node:child_process";
import { closeSync, constants, fstatSync, lstatSync, openSync, readFileSync, realpathSync, writeSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const RECORD_VERSION = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const listScript = path.join(here, "list-processes.sh");
const env = { ...process.env, LC_ALL: "C" };

const USAGE = [
  "usage: stop-run-processes.mjs record <target> <record-file>",
  "       stop-run-processes.mjs stop <target> <record-file> [--wait <seconds>]",
].join("\n");

class Unavailable extends Error {}

const usage = (message) => {
  if (message) process.stderr.write(`${message}\n`);
  process.stderr.write(`${USAGE}\n`);
  process.exit(2);
};

const unavailable = (message) => {
  process.stderr.write(`${message}; the teardown is unverified and nothing was signaled\n`);
  process.exit(1);
};

const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

const under = (dir, root) => dir === root || dir.startsWith(root.endsWith("/") ? root : `${root}/`);

// Runs a lookup and returns its stdout; a non-zero exit, any stderr, or a
// lookup still running after LOOKUP_TIMEOUT_MS means it cannot run, as in
// check-cleanup-targets.mjs.
const LOOKUP_TIMEOUT_MS = 120_000;
const run = (label, command, args) => {
  const result = spawnSync(command, args, { encoding: "utf8", env, maxBuffer: 64 * 1024 * 1024, timeout: LOOKUP_TIMEOUT_MS });
  const stderr = (result.stderr ?? "").trim();
  if (result.error?.code === "ETIMEDOUT") throw new Unavailable(`${label} did not finish within ${LOOKUP_TIMEOUT_MS / 1000} seconds`);
  if (result.status !== 0 || stderr !== "") {
    const reason = (stderr || result.error?.message || "").split("\n")[0];
    throw new Unavailable(`${label} ${result.status === 0 ? "reported an error" : `exited ${result.status ?? result.signal}`}${reason ? `: ${reason}` : ""}`);
  }
  return result.stdout;
};

// One ps read of every process: Map of pid -> { ppid, started }.
const processTable = () => {
  const table = new Map();
  for (const line of run("ps", "ps", ["-A", "-o", "pid=", "-o", "ppid=", "-o", "lstart="]).split("\n")) {
    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\S.*?)\s*$/);
    if (!match) {
      if (line.trim() !== "") throw new Unavailable(`ps printed an unexpected line: ${line}`);
      continue;
    }
    table.set(match[1], { ppid: match[2], started: normalize(match[3]) });
  }
  if (!table.has(String(process.pid))) throw new Unavailable("ps did not list this process");
  return table;
};

const normalize = (started) => started.trim().replace(/\s+/g, " ");

const resolveTarget = (target) => {
  try {
    const real = realpathSync(target);
    if (!lstatSync(real).isDirectory()) usage(`not a directory: ${target}`);
    return real;
  } catch {
    usage(`not a directory: ${target}`);
  }
};

const record = (target, file) => {
  let parent;
  try {
    parent = realpathSync(path.dirname(path.resolve(file)));
  } catch {
    usage(`the record's directory does not exist: ${file}`);
  }
  const real = path.join(parent, path.basename(file));
  if (under(real, target)) usage(`the record must lie outside the target: ${file}`);
  let exists = true;
  try {
    lstatSync(real);
  } catch {
    exists = false;
  }
  if (exists) usage(`the record already exists: ${file}`);
  let table;
  try {
    table = processTable();
  } catch (error) {
    if (error instanceof Unavailable) unavailable(error.message);
    throw error;
  }
  const content = `${JSON.stringify({
    version: RECORD_VERSION,
    target,
    processes: [...table].map(([pid, { started }]) => [pid, started]),
  })}\n`;
  let fd;
  try {
    fd = openSync(real, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  } catch (error) {
    usage(`cannot create the record ${file}: ${error.code ?? error.message}`);
  }
  writeSync(fd, content);
  closeSync(fd);
};

const readRecord = (target, file) => {
  let data;
  try {
    const fd = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      if (!fstatSync(fd).isFile()) throw new Error("not a regular file");
      data = JSON.parse(readFileSync(fd, "utf8"));
    } finally {
      closeSync(fd);
    }
  } catch (error) {
    throw new Unavailable(`cannot read the record ${file}: ${error.code ?? error.message}`);
  }
  if (data?.version !== RECORD_VERSION || !Array.isArray(data.processes)) {
    throw new Unavailable(`the record ${file} has an unknown format`);
  }
  if (data.target !== target) throw new Unavailable(`the record ${file} names another target`);
  return new Set(data.processes.map(([pid, started]) => `${pid} ${started}`));
};

// The rows of list-processes.sh for the target, keyed by pid.
const listing = (target) => {
  const rows = new Map();
  for (const line of run("list-processes.sh", "bash", [listScript, target]).split("\n")) {
    if (line === "") continue;
    const [pid, ppid, tty, started, cwd, reason, ...command] = line.split("\t");
    if (command.length === 0) throw new Unavailable("list-processes.sh printed a row with fewer than 7 columns");
    rows.set(pid, { pid, ppid, tty, started: normalize(started), cwd, reason, command: command.join("\t") });
  }
  return rows;
};

// Worktrees registered strictly below the target, by real path.
const nestedWorktrees = (target) => {
  const out = run("git worktree list", "git", ["--no-optional-locks", "-C", target, "worktree", "list", "--porcelain", "-z"]);
  const nested = [];
  for (const field of out.split("\0")) {
    if (!field.startsWith("worktree ")) continue;
    let dir = field.slice("worktree ".length);
    try {
      dir = realpathSync(dir);
    } catch {
      // A missing worktree keeps its registered path.
    }
    if (dir !== target && under(dir, target)) nested.push(dir);
  }
  return nested;
};

// The start time of one process now: a string, "" when it is gone, or null
// when it cannot be read.
const startOf = (pid) => {
  const result = spawnSync("ps", ["-p", pid, "-o", "lstart="], { encoding: "utf8", env, timeout: 10_000 });
  const started = normalize(result.stdout ?? "");
  if (result.status === 0 && started !== "") return started;
  try {
    process.kill(Number(pid), 0);
  } catch (error) {
    if (error.code === "ESRCH") return "";
  }
  return null;
};

// Sends SIGTERM to pid when its start time still matches; returns
// "signaled", "gone", or the reason it is unverified.
const terminate = (pid, started) => {
  const now = startOf(pid);
  if (now === "") return "gone";
  if (now === null) return "start time unreadable";
  if (now !== started) return "start time changed";
  try {
    process.kill(Number(pid), "SIGTERM");
  } catch (error) {
    if (error.code === "ESRCH") return "gone";
    return `signal failed: ${error.code ?? error.message}`;
  }
  return "signaled";
};

// Waits up to ms for the given processes to exit; returns those still
// running with the same start time, or null when ps fails.
const waitFor = (procs, ms) => {
  const deadline = Date.now() + ms;
  for (;;) {
    let table;
    try {
      table = processTable();
    } catch {
      return null;
    }
    const alive = procs.filter((p) => table.get(p.pid)?.started === p.started);
    if (alive.length === 0 || Date.now() >= deadline) return alive;
    sleep(Math.min(500, Math.max(0, deadline - Date.now())));
  }
};

const stop = (target, file, waitSeconds) => {
  let before, rows, nested, table;
  try {
    before = readRecord(target, file);
    rows = listing(target);
    nested = nestedWorktrees(target);
    table = processTable();
  } catch (error) {
    if (error instanceof Unavailable) unavailable(error.message);
    throw error;
  }

  // Decide each listed process, walking its parents in the new table.
  const verdicts = new Map();
  const decide = (pid, seen = new Set()) => {
    if (verdicts.has(pid)) return verdicts.get(pid);
    const row = rows.get(pid);
    const now = table.get(pid);
    let verdict;
    if (!now) verdict = { status: "gone", reason: "exited before the teardown" };
    else if (now.started !== row.started) verdict = { status: "unverified", reason: "start time changed during the listing" };
    else if (before.has(`${pid} ${now.started}`)) verdict = { status: "left", reason: "existed before the run" };
    else if (row.reason !== "cwd under target") verdict = { status: "left", reason: row.reason === "--cwd under target" ? "only its --cwd argument is under the target" : row.reason };
    else if (row.cwd.includes("\\")) verdict = { status: "left", reason: "cwd ambiguous" };
    else if (nested.some((dir) => under(row.cwd, dir))) verdict = { status: "left", reason: `in nested worktree ${nested.find((dir) => under(row.cwd, dir))}` };
    else if (row.tty !== "?") verdict = { status: "left", reason: `has tty ${row.tty}` };
    else {
      const ppid = now.ppid;
      const parent = table.get(ppid);
      if (ppid === "0" || ppid === "1") verdict = { status: "start" };
      else if (!parent) verdict = { status: "unverified", reason: `parent ${ppid} not found` };
      else if (before.has(`${ppid} ${parent.started}`)) verdict = { status: "left", reason: `parent ${ppid} existed before the run` };
      else if (!rows.has(ppid)) verdict = { status: "left", reason: `parent ${ppid} is a new process outside the target` };
      else if (seen.has(pid)) verdict = { status: "unverified", reason: "parent cycle" };
      else {
        seen.add(pid);
        const up = decide(ppid, seen);
        verdict = up.status === "start" ? { status: "start" } : { status: "left", reason: `parent ${ppid} not stopped: ${up.reason ?? up.status}` };
      }
    }
    verdicts.set(pid, verdict);
    return verdict;
  };
  for (const pid of rows.keys()) decide(pid);

  const started = [...rows.keys()].filter((pid) => verdicts.get(pid).status === "start")
    .map((pid) => ({ pid, started: table.get(pid).started, ppid: table.get(pid).ppid }));
  const startedSet = new Set(started.map((p) => p.pid));
  const roots = started.filter((p) => !startedSet.has(p.ppid));

  const outcome = new Map();
  for (const root of roots) {
    const result = terminate(root.pid, root.started);
    if (result === "gone") outcome.set(root.pid, { status: "gone", reason: "exited before its signal" });
    else if (result !== "signaled") outcome.set(root.pid, { status: "unverified", reason: result });
  }
  let pending = started.filter((p) => !outcome.has(p.pid));
  let alive = pending.length ? waitFor(pending, waitSeconds * 1000) : [];
  const finish = (procs, status) => {
    for (const p of procs) if (!outcome.has(p.pid)) outcome.set(p.pid, { status, reason: "" });
  };
  if (alive === null) {
    finish(pending, "unverified");
    for (const p of pending) outcome.get(p.pid).reason = "ps failed while waiting";
  } else {
    const aliveSet = new Set(alive.map((p) => p.pid));
    finish(pending.filter((p) => !aliveSet.has(p.pid)), "stopped");
    for (const p of alive) {
      const result = terminate(p.pid, p.started);
      if (result === "gone") outcome.set(p.pid, { status: "stopped", reason: "" });
      else if (result !== "signaled") outcome.set(p.pid, { status: "unverified", reason: result });
    }
    pending = alive.filter((p) => !outcome.has(p.pid));
    const still = pending.length ? waitFor(pending, (waitSeconds * 1000) / 2) : [];
    if (still === null) {
      for (const p of pending) outcome.set(p.pid, { status: "unverified", reason: "ps failed while waiting" });
    } else {
      const stillSet = new Set(still.map((p) => p.pid));
      for (const p of pending) {
        outcome.set(p.pid, stillSet.has(p.pid)
          ? { status: "running", reason: "still running after the second SIGTERM" }
          : { status: "stopped-retry", reason: "" });
      }
    }
  }

  const lines = [];
  let leftover = false;
  for (const [pid, row] of rows) {
    const verdict = verdicts.get(pid);
    const result = verdict.status === "start" ? outcome.get(pid) : verdict;
    if (result.status === "running" || result.status === "unverified") leftover = true;
    const fields = [result.status, pid, table.get(pid)?.ppid ?? row.ppid, row.started, row.cwd, result.reason || row.reason, row.command];
    lines.push(fields.join("\t"));
  }
  const state = leftover ? "leftovers" : started.length ? "verified" : "none";
  lines.push(`teardown\t${state}`);
  process.stdout.write(`${lines.join("\n")}\n`);
  process.exit(leftover ? 3 : 0);
};

const [subcommand, ...args] = process.argv.slice(2);
if (subcommand === "record") {
  if (args.length !== 2) usage();
  record(resolveTarget(args[0]), args[1]);
} else if (subcommand === "stop") {
  let wait = 10;
  const positional = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--wait") {
      const value = args[++i];
      if (!/^\d+(\.\d+)?$/.test(value ?? "") || Number(value) > 60) usage("--wait takes seconds from 0 to 60");
      wait = Number(value);
    } else if (args[i].startsWith("-")) {
      usage(`unknown option: ${args[i]}`);
    } else {
      positional.push(args[i]);
    }
  }
  if (positional.length !== 2) usage();
  stop(resolveTarget(positional[0]), positional[1], wait);
} else {
  usage();
}
