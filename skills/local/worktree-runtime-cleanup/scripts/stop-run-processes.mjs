#!/usr/bin/env node
// Stop the process trees that one Codex review run, or one set of runs started
// together, started under its target worktree.
//
// Usage:
//   node stop-run-processes.mjs record <target> <record-file> [--writable <dir>]...
//   node stop-run-processes.mjs stop <target> <record-file> [--writable <dir>]... [--wait <seconds>]
//
// The record file
//   The record decides which processes existed before the run, so a Codex run
//   must not be able to edit it. Its directory must be owned by the current
//   user with no group or other access (mode 700), and must lie outside every
//   root a Codex `workspace-write` run of the set can write: the target, each
//   other worktree a run of the set gets as --cwd (pass each with
//   --writable), `/tmp`, `$TMPDIR` (with `os.tmpdir()`), and every
//   `writable_roots` entry in the Codex configuration files that apply:
//   `$CODEX_HOME/config.toml` (default `~/.codex/config.toml`),
//   `/etc/codex/config.toml`, `/etc/codex/managed_config.toml`, and
//   `.codex/config.toml` in the target and each directory above it, in any
//   table or profile. A configuration file that exists but cannot be read, or
//   a `writable_roots` value that is not an array of absolute paths in plain
//   strings, leaves the policy unknown: both subcommands exit 1. `record`
//   creates the file exclusively, without following a symbolic link, with
//   mode 0600; `stop` accepts only such a regular file in such a directory.
//
// record
//   Before the run, writes the target's real path, its own PID, and every
//   process's PID and start time, from one `ps` read, to <record-file>. It
//   holds no command lines.
//
// stop
//   After the run, whether it succeeded or failed, reads and checks the record
//   (its format; PIDs and start times exactly as ps prints them under
//   LC_ALL=C, such as "Sat Nov 21 16:21:27 2026"; entries for pid 1, with the
//   start time it has now, and for the process that wrote it; and the target),
//   lists the worktrees
//   registered below the target, takes a process table, lists the target with
//   list-processes.sh beside this script, and takes a second table. A process
//   is one the run started only when all of these hold:
//   - both tables and the listing give it the same start time, so its cwd
//     and its start time belong to one process even if its PID was reused
//     during the listing;
//   - it is absent from the record by PID and start time;
//   - list-processes.sh lists it with reason exactly "cwd under target" (a
//     --cwd argument alone never counts) and its cwd is an exact path at or
//     below the target: absolute and normalized, without a backslash (the
//     listing's escape) and without a " (deleted)" suffix;
//   - its cwd is not inside a worktree registered below the target;
//   - it has no tty;
//   - its parent is pid 1 or 0, or itself a process the run started.
//   A new process listed under the target whose cwd is not such an exact path,
//   such as a cwd with a " (deleted)" suffix or an ambiguous one, may be the
//   run's: it is reported "unverified" and never signaled, and counts as a
//   leftover. Any other listed process is reported "left" with the reason and
//   never signaled: one that existed before the run, one under a parent that did
//   (such as another session's shell, wherever its cwd is), and one under a
//   new parent outside the target. Ownership is read from the parent chain at
//   stop: a process another session starts in the target during the run
//   whose parent has exited counts as started by the run, so the callers keep
//   other work out of the target while the run lasts. On a host where an
//   orphan is reparented to a pre-existing subreaper rather than pid 1, its
//   tree is left and reported.
//   The tops of the started trees get SIGTERM first; each one's start time is
//   read again immediately before its signal, and a changed one is not
//   signaled. After --wait seconds (default 10), every started process still
//   running with the same start time, even reparented, gets SIGTERM once
//   more, and the script waits half as long again. Lookups while waiting are
//   bounded by the time left. The script signals no other process, except
//   its own lookups that run past their time bound, which get SIGTERM.
//
// Output of stop: one tab-separated line per listed process,
//   <status> <pid> <ppid> <started> <cwd> <reason>
// with <started> and <cwd> as list-processes.sh prints them under LC_ALL=C,
// then a last line "teardown <verified|none|leftovers>". Command lines are
// never printed. Statuses:
//   stopped        exited after its tree's first SIGTERM
//   stopped-retry  exited after the second SIGTERM
//   gone           exited before it was signaled
//   running        still running after the second SIGTERM
//   unverified     not signaled, or its exit not confirmed: its start time
//                  changed or differs between lookups, its cwd is not an
//                  exact live path, its parent was not found, or it could not
//                  be read or signaled
//   left           not started by the run; <reason> says why
//
// Exit status:
//   0  stop: every started process exited, or the run started none; record:
//      written
//   1  could not run, and nothing was signaled: list-processes.sh, ps, or git
//      failed, wrote to stderr, or ran past 120 seconds, the Codex sandbox
//      policy is unknown, or the record is unusable (place, mode, format, or
//      contents) or names another target. The teardown is unverified.
//   2  usage error: an unknown subcommand or option, a target that is not a
//      directory, or for record a path that exists or a directory that is not
//      a private one outside every root a Codex run of the set can write
//   3  stop: a started process is still running or unverified
// Leftovers never change a review's result; worktree cleanup handles them.
import { spawn } from "node:child_process";
import { closeSync, constants, fstatSync, lstatSync, openSync, readFileSync, realpathSync, statSync, writeSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";

const RECORD_VERSION = 1;
const LOOKUP_TIMEOUT_MS = 120_000;
const RECHECK_TIMEOUT_MS = 10_000;
const here = path.dirname(fileURLToPath(import.meta.url));
const listScript = path.join(here, "list-processes.sh");
const env = { ...process.env, LC_ALL: "C" };

const USAGE = [
  "usage: stop-run-processes.mjs record <target> <record-file> [--writable <dir>]...",
  "       stop-run-processes.mjs stop <target> <record-file> [--writable <dir>]... [--wait <seconds>]",
].join("\n");

class Usage extends Error {}
class Unavailable extends Error {}

// A PID and a start time exactly as ps prints them under LC_ALL=C, after
// normalize: "Sat Nov 21 16:21:27 2026".
const PID = /^[1-9]\d*$/;
const STARTED = /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([1-9]|[12]\d|3[01]) ([01]\d|2[0-3]):[0-5]\d:[0-5]\d \d{4}$/;

const under = (dir, root) => dir === root || dir.startsWith(root.endsWith("/") ? root : `${root}/`);
const normalize = (started) => started.trim().replace(/\s+/g, " ");

// Runs a lookup in its own process group and resolves { code, stdout, stderr }.
// Past timeoutMs it sends the group SIGTERM, stops waiting for its output, and
// rejects as unavailable.
const lookup = (label, command, args, timeoutMs) => new Promise((resolve, reject) => {
  let child;
  try {
    child = spawn(command, args, { env, detached: true, stdio: ["ignore", "pipe", "pipe"] });
  } catch (error) {
    reject(new Unavailable(`${label} could not start: ${error.code ?? error.message}`));
    return;
  }
  const out = [];
  const err = [];
  child.stdout.on("data", (chunk) => out.push(chunk));
  child.stderr.on("data", (chunk) => err.push(chunk));
  let settled = false;
  const timer = setTimeout(() => {
    if (settled) return;
    settled = true;
    try {
      process.kill(-child.pid, "SIGTERM");
    } catch {
      // The lookup ended meanwhile.
    }
    child.stdout.destroy();
    child.stderr.destroy();
    child.unref();
    reject(new Unavailable(`${label} did not finish within ${Math.round(timeoutMs / 100) / 10} seconds`));
  }, timeoutMs);
  child.on("error", (error) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    reject(new Unavailable(`${label} could not start: ${error.code ?? error.message}`));
  });
  child.on("close", (code, signal) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    resolve({
      code: code ?? signal,
      stdout: Buffer.concat(out).toString("utf8"),
      stderr: Buffer.concat(err).toString("utf8").trim(),
    });
  });
});

// A lookup whose non-zero exit or any stderr means it cannot run, as in
// check-cleanup-targets.mjs.
const run = async (label, command, args, timeoutMs = LOOKUP_TIMEOUT_MS) => {
  const result = await lookup(label, command, args, timeoutMs);
  if (result.code !== 0 || result.stderr !== "") {
    const reason = result.stderr.split("\n")[0];
    throw new Unavailable(`${label} ${result.code === 0 ? "reported an error" : `exited ${result.code}`}${reason ? `: ${reason}` : ""}`);
  }
  return result.stdout;
};

// One ps read of every process: Map of pid -> { ppid, started }.
const processTable = async (timeoutMs = LOOKUP_TIMEOUT_MS) => {
  const table = new Map();
  const out = await run("ps", "ps", ["-A", "-o", "pid=", "-o", "ppid=", "-o", "lstart="], timeoutMs);
  for (const line of out.split("\n")) {
    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\S.*?)\s*$/);
    if (!match) {
      if (line.trim() !== "") throw new Unavailable(`ps printed an unexpected line: ${line}`);
      continue;
    }
    const started = normalize(match[3]);
    if (!PID.test(match[1]) || !/^(0|[1-9]\d*)$/.test(match[2]) || !STARTED.test(started)) {
      throw new Unavailable(`ps printed an unexpected line: ${line}`);
    }
    table.set(match[1], { ppid: match[2], started });
  }
  if (!table.has(String(process.pid)) || !table.has("1")) throw new Unavailable("ps did not list this process and pid 1");
  return table;
};

const resolveTarget = (target) => {
  let real;
  try {
    real = realpathSync(target);
  } catch {
    throw new Usage(`not a directory: ${target}`);
  }
  if (!statSync(real).isDirectory()) throw new Usage(`not a directory: ${target}`);
  return real;
};

const realOrSelf = (dir) => {
  try {
    return realpathSync(dir);
  } catch {
    return path.resolve(dir);
  }
};

// Reads the writable_roots arrays of one Codex configuration file: every
// `writable_roots = [...]` in it, in any table or profile, counts. Returns
// [] for a missing file; throws Unavailable for a file it cannot read or a
// value it cannot parse, since the sandbox policy is then unknown.
const configRoots = (file) => {
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") return [];
    throw new Unavailable(`cannot read the Codex configuration ${file}: ${error.code ?? error.message}`);
  }
  const unknown = (why) => new Unavailable(`cannot establish the Codex sandbox writable roots from ${file}: ${why}`);
  const roots = [];
  let from = 0;
  for (;;) {
    const at = text.indexOf("writable_roots", from);
    if (at < 0) break;
    from = at + "writable_roots".length;
    const lineStart = text.lastIndexOf("\n", at) + 1;
    const before = text.slice(lineStart, at);
    if (/^\s*#/.test(before)) continue;
    // Only a key path or an inline table may come before the key on its line;
    // anything else, such as a string that names it, leaves the policy unknown.
    if (!/^[\s\w."'{=,-]*$/.test(before)) throw unknown("writable_roots appears where it cannot be read");
    let i = from;
    if (text[i] === '"' || text[i] === "'") i++;
    const assign = text.slice(i).match(/^[ \t]*=[ \t]*\[/);
    if (!assign) throw unknown("writable_roots is not an array");
    i += assign[0].length;
    for (;;) {
      while (i < text.length && /[\s,]/.test(text[i])) i++;
      if (text[i] === "#") {
        while (i < text.length && text[i] !== "\n") i++;
        continue;
      }
      if (text[i] === "]") break;
      let value;
      if (text.startsWith('"""', i) || text.startsWith("'''", i)) throw unknown("multi-line strings are not read");
      if (text[i] === "'") {
        const end = text.indexOf("'", i + 1);
        if (end < 0 || text.slice(i + 1, end).includes("\n")) throw unknown("an unterminated string");
        value = text.slice(i + 1, end);
        i = end + 1;
      } else if (text[i] === '"') {
        value = "";
        i++;
        for (;;) {
          const c = text[i];
          if (c === undefined || c === "\n") throw unknown("an unterminated string");
          if (c === '"') {
            i++;
            break;
          }
          if (c === "\\") {
            const e = text[i + 1];
            const simple = { "\\": "\\", '"': '"', n: "\n", t: "\t", r: "\r", b: "\b", f: "\f" }[e];
            if (simple !== undefined) {
              value += simple;
              i += 2;
            } else if (e === "u" && /^[0-9a-fA-F]{4}$/.test(text.slice(i + 2, i + 6))) {
              value += String.fromCodePoint(parseInt(text.slice(i + 2, i + 6), 16));
              i += 6;
            } else if (e === "U" && /^[0-9a-fA-F]{8}$/.test(text.slice(i + 2, i + 10))) {
              value += String.fromCodePoint(parseInt(text.slice(i + 2, i + 10), 16));
              i += 10;
            } else {
              throw unknown("an unknown escape");
            }
            continue;
          }
          value += c;
          i++;
        }
      } else {
        throw unknown("an element that is not a string");
      }
      if (value.startsWith("~/")) value = path.join(os.homedir(), value.slice(2));
      if (!path.isAbsolute(value)) throw unknown(`a relative root: ${value}`);
      roots.push(value);
    }
    from = i;
  }
  return roots;
};

// Every root a Codex workspace-write run may write beyond its --cwd, /tmp, and
// $TMPDIR: the writable_roots of the user, system, and project configuration
// files that apply to the target, in every profile.
const sandboxRoots = (target) => {
  const home = process.env.CODEX_HOME ? path.resolve(process.env.CODEX_HOME) : path.join(os.homedir(), ".codex");
  const files = [path.join(home, "config.toml"), "/etc/codex/config.toml", "/etc/codex/managed_config.toml"];
  for (let dir = target; ; dir = path.dirname(dir)) {
    files.push(path.join(dir, ".codex", "config.toml"));
    if (dir === path.dirname(dir)) break;
  }
  return files.flatMap(configRoots);
};

// The record's real path, after checking that its directory is private and
// outside every root a Codex run of the set can write: the target, the other
// worktrees given with --writable, /tmp, $TMPDIR, and the configured writable
// roots. Throws Fail for a bad place, and Unavailable when the configured
// roots cannot be read.
const recordPlace = (file, target, others, Fail) => {
  const abs = path.resolve(file);
  let parent;
  try {
    parent = realpathSync(path.dirname(abs));
  } catch {
    throw new Fail(`the record's directory does not exist: ${file}`);
  }
  const real = path.join(parent, path.basename(abs));
  const writable = [target, ...others, "/tmp", process.env.TMPDIR, os.tmpdir(), ...sandboxRoots(target)]
    .filter(Boolean)
    .flatMap((dir) => [path.resolve(dir), realOrSelf(dir)]);
  if (writable.some((root) => under(real, root))) {
    throw new Fail(`the record must lie outside the target, /tmp, $TMPDIR, and every root a Codex run can write: ${file}`);
  }
  const stat = statSync(parent);
  if (stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) {
    throw new Fail(`the record's directory must be yours alone (mode 700): ${path.dirname(abs)}`);
  }
  return real;
};

const record = async (target, file, others) => {
  const real = recordPlace(file, target, others, Usage);
  let exists = true;
  try {
    lstatSync(real);
  } catch {
    exists = false;
  }
  if (exists) throw new Usage(`the record already exists: ${file}`);
  const table = await processTable();
  const content = `${JSON.stringify({
    version: RECORD_VERSION,
    target,
    recorder: String(process.pid),
    processes: [...table].map(([pid, { started }]) => [pid, started]),
  })}\n`;
  let fd;
  try {
    fd = openSync(real, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  } catch (error) {
    throw new Usage(`cannot create the record ${file}: ${error.code ?? error.message}`);
  }
  try {
    writeSync(fd, content);
  } finally {
    closeSync(fd);
  }
};

const isPair = (entry) => Array.isArray(entry) && entry.length === 2
  && typeof entry[0] === "string" && PID.test(entry[0])
  && typeof entry[1] === "string" && STARTED.test(entry[1]);

// The record's pairs as a Map of pid -> started, or Unavailable.
const readRecord = (target, file, others) => {
  const real = recordPlace(file, target, others, Unavailable);
  let data;
  try {
    const fd = openSync(real, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const stat = fstatSync(fd);
      if (!stat.isFile()) throw new Error("not a regular file");
      if (stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) throw new Error("not a private file (mode 600)");
      data = JSON.parse(readFileSync(fd, "utf8"));
    } finally {
      closeSync(fd);
    }
  } catch (error) {
    throw new Unavailable(`cannot read the record ${file}: ${error.code ?? error.message}`);
  }
  if (data === null || typeof data !== "object" || Array.isArray(data)
    || data.version !== RECORD_VERSION || typeof data.target !== "string"
    || typeof data.recorder !== "string" || !PID.test(data.recorder) || data.recorder === "1"
    || !Array.isArray(data.processes) || data.processes.length === 0 || !data.processes.every(isPair)) {
    throw new Unavailable(`the record ${file} has an unknown format`);
  }
  if (data.target !== target) throw new Unavailable(`the record ${file} names another target`);
  const before = new Map(data.processes);
  if (before.size !== data.processes.length) throw new Unavailable(`the record ${file} lists a PID twice`);
  if (!before.has("1") || !before.has(data.recorder)) {
    throw new Unavailable(`the record ${file} does not list pid 1 and the process that wrote it`);
  }
  return before;
};

// The rows of list-processes.sh for the target, keyed by pid. The command
// column is dropped.
const listing = async (target) => {
  const rows = new Map();
  for (const line of (await run("list-processes.sh", "bash", [listScript, target])).split("\n")) {
    if (line === "") continue;
    const [pid, ppid, tty, started, cwd, reason, ...command] = line.split("\t");
    if (command.length === 0) throw new Unavailable("list-processes.sh printed a row with fewer than 7 columns");
    rows.set(pid, { pid, ppid, tty, started: normalize(started), cwd, reason });
  }
  return rows;
};

// Worktrees registered strictly below the target, by real path.
const nestedWorktrees = async (target) => {
  const out = await run("git worktree list", "git", ["--no-optional-locks", "-C", target, "worktree", "list", "--porcelain", "-z"]);
  const nested = [];
  for (const field of out.split("\0")) {
    if (!field.startsWith("worktree ")) continue;
    const dir = realOrSelf(field.slice("worktree ".length));
    if (dir !== target && under(dir, target)) nested.push(dir);
  }
  return nested;
};

// Why a listed cwd is not an exact path at or below the target, or "".
const cwdProblem = (cwd, target) => {
  if (cwd.includes("\\")) return "cwd ambiguous";
  if (cwd.endsWith(" (deleted)")) return "cwd deleted";
  if (!cwd.startsWith("/") || path.posix.normalize(cwd) !== cwd || !under(cwd, target)) return "cwd not an exact path under the target";
  return "";
};

// The start time of one process now: a string, "" when it is gone, or null
// when it cannot be read.
const startOf = async (pid) => {
  let result;
  try {
    result = await lookup("ps", "ps", ["-p", pid, "-o", "lstart="], RECHECK_TIMEOUT_MS);
  } catch {
    return null;
  }
  const started = normalize(result.stdout);
  if (result.code === 0 && started !== "") return started;
  try {
    process.kill(Number(pid), 0);
  } catch (error) {
    if (error.code === "ESRCH") return "";
  }
  return null;
};

// Sends SIGTERM to pid when its start time still matches; returns
// "signaled", "gone", or the reason it is unverified.
const terminate = async (pid, started) => {
  const now = await startOf(pid);
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
// running with the same start time, or null when ps fails or cannot answer
// within the time left (at least one second).
const waitFor = async (procs, ms) => {
  const deadline = Date.now() + ms;
  for (;;) {
    let table;
    try {
      table = await processTable(Math.max(1000, deadline - Date.now()));
    } catch {
      return null;
    }
    const alive = procs.filter((p) => table.get(p.pid)?.started === p.started);
    if (alive.length === 0 || Date.now() >= deadline) return alive;
    await delay(Math.min(500, Math.max(0, deadline - Date.now())));
  }
};

const stop = async (target, file, others, waitSeconds) => {
  // Everything that can make the teardown unavailable runs before any signal.
  const before = readRecord(target, file, others);
  const nested = await nestedWorktrees(target);
  const first = await processTable();
  if (first.get("1").started !== before.get("1")) {
    throw new Unavailable(`the record ${file} was not taken on this host since it last started`);
  }
  const rows = await listing(target);
  const table = await processTable();

  // Decide each listed process, walking its parents in the second table.
  const verdicts = new Map();
  const decide = (pid, seen = new Set()) => {
    if (verdicts.has(pid)) return verdicts.get(pid);
    const row = rows.get(pid);
    const now = table.get(pid);
    const then = first.get(pid);
    let verdict;
    const problem = row.reason === "cwd under target" ? cwdProblem(row.cwd, target) : "";
    const inNested = nested.find((dir) => under(row.cwd, dir));
    if (!now) verdict = { status: "gone", reason: "exited before the teardown" };
    else if (!then) verdict = { status: "left", reason: "started during the teardown" };
    else if (then.started !== row.started || now.started !== row.started) verdict = { status: "unverified", reason: "start time differs between lookups" };
    else if (before.get(pid) === now.started) verdict = { status: "left", reason: "existed before the run" };
    else if (row.reason === "cwd ambiguous") verdict = { status: "unverified", reason: "cwd ambiguous" };
    else if (row.reason !== "cwd under target") verdict = { status: "left", reason: row.reason === "--cwd under target" ? "only its --cwd argument is under the target" : row.reason };
    else if (problem) verdict = { status: "unverified", reason: problem };
    else if (inNested) verdict = { status: "left", reason: `in nested worktree ${inNested}` };
    else if (row.tty !== "?") verdict = { status: "left", reason: `has tty ${row.tty}` };
    else {
      const ppid = now.ppid;
      const parent = table.get(ppid);
      if (ppid === "0" || ppid === "1") verdict = { status: "start" };
      else if (!parent) verdict = { status: "unverified", reason: `parent ${ppid} not found` };
      else if (before.get(ppid) === parent.started) verdict = { status: "left", reason: `parent ${ppid} existed before the run` };
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
    const result = await terminate(root.pid, root.started);
    if (result === "gone") outcome.set(root.pid, { status: "gone", reason: "exited before its signal" });
    else if (result !== "signaled") outcome.set(root.pid, { status: "unverified", reason: result });
  }
  let pending = started.filter((p) => !outcome.has(p.pid));
  const alive = pending.length ? await waitFor(pending, waitSeconds * 1000) : [];
  if (alive === null) {
    for (const p of pending) outcome.set(p.pid, { status: "unverified", reason: "ps failed while waiting" });
  } else {
    const aliveSet = new Set(alive.map((p) => p.pid));
    for (const p of pending) if (!aliveSet.has(p.pid)) outcome.set(p.pid, { status: "stopped", reason: "" });
    for (const p of alive) {
      const result = await terminate(p.pid, p.started);
      if (result === "gone") outcome.set(p.pid, { status: "stopped", reason: "" });
      else if (result !== "signaled") outcome.set(p.pid, { status: "unverified", reason: result });
    }
    pending = alive.filter((p) => !outcome.has(p.pid));
    const still = pending.length ? await waitFor(pending, (waitSeconds * 1000) / 2) : [];
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
    lines.push([result.status, pid, table.get(pid)?.ppid ?? row.ppid, row.started, row.cwd, result.reason || row.reason].join("\t"));
  }
  const state = leftover ? "leftovers" : started.length ? "verified" : "none";
  lines.push(`teardown\t${state}`);
  process.stdout.write(`${lines.join("\n")}\n`);
  return leftover ? 3 : 0;
};

const main = async (argv) => {
  const [subcommand, ...args] = argv;
  if (subcommand !== "record" && subcommand !== "stop") throw new Usage("");
  let wait = 10;
  const others = [];
  const positional = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--wait" && subcommand === "stop") {
      const value = args[++i];
      if (!/^\d+(\.\d+)?$/.test(value ?? "") || Number(value) > 60) throw new Usage("--wait takes seconds from 0 to 60");
      wait = Number(value);
    } else if (args[i] === "--writable") {
      const value = args[++i];
      if (!value) throw new Usage("--writable takes a directory");
      others.push(path.resolve(value));
    } else if (args[i].startsWith("-")) {
      throw new Usage(`unknown option: ${args[i]}`);
    } else {
      positional.push(args[i]);
    }
  }
  if (positional.length !== 2) throw new Usage("");
  const target = resolveTarget(positional[0]);
  if (subcommand === "record") {
    await record(target, positional[1], others);
    return 0;
  }
  return stop(target, positional[1], others, wait);
};

// Exit codes are set, never forced, so stdout and stderr drain before exit.
main(process.argv.slice(2)).then((code) => {
  process.exitCode = code;
}, (error) => {
  if (error instanceof Usage) {
    process.stderr.write(`${error.message ? `${error.message}\n` : ""}${USAGE}\n`);
    process.exitCode = 2;
  } else if (error instanceof Unavailable) {
    process.stderr.write(`${error.message}; the teardown is unverified and nothing was signaled\n`);
    process.exitCode = 1;
  } else {
    process.stderr.write(`${error.stack ?? error}\n`);
    process.exitCode = 1;
  }
});
