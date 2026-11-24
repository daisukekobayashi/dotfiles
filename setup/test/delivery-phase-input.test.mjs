import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync,
  rmSync, statSync, symlinkSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { repoRoot } from "./skills-helpers.mjs";

const script = path.join(repoRoot, "skills/local/delivery-common/scripts/write-phase-input-key.mjs");
const posix = { skip: process.platform === "win32" && "private delivery records require a POSIX host" };

function fixture(t) {
  const records = mkdtempSync(path.join(realpathSync(tmpdir()), "phase-input-"));
  t.after(() => rmSync(records, { recursive: true, force: true }));
  const worktree = path.join(records, "worktree");
  mkdirSync(worktree);
  const env = { ...process.env, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null" };
  const git = (args, input) => execFileSync("git", ["--no-optional-locks", ...args], { cwd: worktree, env, input });
  const write = (name, content) => writeFileSync(path.join(worktree, name), content);
  git(["init", "--quiet", "--template="]);
  write("tracked.txt", "original\n");
  write(".gitignore", "ignored.txt\n");
  git(["add", "--", "tracked.txt", ".gitignore"]);
  git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Fixture base"]);
  const head = git(["rev-parse", "HEAD"]).toString().trim();
  const record = (name, content) => {
    const file = path.join(records, name);
    writeFileSync(file, content);
    return file;
  };
  const paths = (...names) => record("changed-paths", Buffer.concat(names.flatMap((name) => [Buffer.from(name), Buffer.of(0)])));
  const capture = (phase, output, inputs, extraEnv = {}) => spawnSync(process.execPath,
    [script, phase, worktree, head, output, ...inputs],
    { env: { ...env, ...extraEnv }, encoding: "utf8", timeout: 10_000 });
  const assertRecord = (run, output, phase, bytes) => {
    const digest = git(["hash-object", "--stdin", "--no-filters"], bytes).toString().trim();
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, `${phase}:${head}:${digest}\n`);
    assert.deepEqual(readFileSync(output), bytes);
    assert.equal(statSync(output).mode & 0o777, 0o600);
    return digest;
  };
  return { records, worktree, head, git, write, record, paths, capture, assertRecord };
}

test("preflight key keeps the existing byte framing and writes no Git object", posix, (t) => {
  const f = fixture(t);
  const decisions = Buffer.from("decision あ\n\0");
  const understanding = Buffer.from([0xff, 0x0a]);
  const inputs = [f.record("decisions", decisions), f.record("shared-understanding", understanding)];
  const output = path.join(f.records, "preflight-input");
  const frame = Buffer.concat([Buffer.from(`decisions ${decisions.length}\n`), decisions,
    Buffer.from("shared-understanding 2\n"), understanding]);
  const run = f.capture("preflight", output, inputs);
  const digest = f.assertRecord(run, output, "preflight", frame);
  const object = spawnSync("git", ["cat-file", "-e", digest], { cwd: f.worktree });
  assert.equal(object.status, 1);
  assert.equal(f.capture("preflight", output, inputs).status, 1);
  assert.deepEqual(readFileSync(output), frame);
});

test("verification captures the diff and only exact, literal reported untracked paths", posix, (t) => {
  const f = fixture(t);
  f.write("tracked.txt", "staged\n");
  f.git(["add", "--", "tracked.txt"]);
  f.write("tracked.txt", "staged\nunstaged\n");
  const diff = f.git(["diff", "--binary", "--no-ext-diff", "--no-textconv", "--no-color", "HEAD"]);
  const diffFrame = Buffer.concat([Buffer.from(`diff ${diff.length}\n`), diff]);
  f.write("unrelated.txt", "exclude");
  f.write("ignored.txt", "exclude");
  mkdirSync(path.join(f.worktree, "dir"));
  f.write("dir/also-unrelated.txt", "exclude");
  f.write("[ab]*.txt", "literal");
  f.write("a1.txt", "exclude the glob match");
  f.write("count\nme", "on a new line");
  symlinkSync("../not-read", path.join(f.worktree, "link"));

  const trace = path.join(f.records, "trace");
  const empty = path.join(f.records, "empty");
  f.assertRecord(f.capture("verification", empty, [f.paths()], { GIT_TRACE2_EVENT: trace }), empty, "verification", diffFrame);
  assert.doesNotMatch(readFileSync(trace, "utf8"), /"name":"ls-files"/);

  const entries = [
    [Buffer.from("[ab]*.txt"), "100644", Buffer.from("literal")],
    [Buffer.from("count\nme"), "100644", Buffer.from("on a new line")],
    [Buffer.from("link"), "120000", Buffer.from("../not-read")],
  ];
  if (process.platform === "linux") {
    const raw = Buffer.from([0xff]);
    writeFileSync(Buffer.concat([Buffer.from(`${f.worktree}/`), raw]), Buffer.of(1, 2));
    entries.push([raw, "100644", Buffer.of(1, 2)]);
  }
  const input = f.paths(...entries.map(([name]) => name).reverse(), "dir", "ignored.txt", "tracked.txt", "[ab]*.txt");
  const expected = (parts) => Buffer.concat([diffFrame, ...parts.flatMap(([name, mode, content]) =>
    [Buffer.from(`file ${mode} ${name.length} ${content.length}\n`), name, content])]);
  const first = path.join(f.records, "verification-input");
  const before = f.assertRecord(f.capture("verification", first, [input]), first, "verification", expected(entries));

  f.write("unrelated.txt", "still unrelated");
  const repeat = path.join(f.records, "repeat");
  assert.equal(f.assertRecord(f.capture("verification", repeat, [input]), repeat, "verification", expected(entries)), before);
  chmodSync(path.join(f.worktree, "[ab]*.txt"), 0o755);
  entries[0][1] = "100755";
  const chmod = path.join(f.records, "chmod");
  assert.notEqual(f.assertRecord(f.capture("verification", chmod, [input]), chmod, "verification", expected(entries)), before);
  // Group and other execute bits do not make a file executable in Git.
  chmodSync(path.join(f.worktree, "[ab]*.txt"), 0o655);
  entries[0][1] = "100644";
  const groupExecutable = path.join(f.records, "group-executable");
  assert.equal(f.assertRecord(f.capture("verification", groupExecutable, [input]), groupExecutable,
    "verification", expected(entries)), before);
});

test("phase input fails without a key or output for unsafe or ambiguous inputs", posix, (t) => {
  const f = fixture(t);
  const output = path.join(f.records, "unwritten");
  for (const data of ["dir/../other\0", "/absolute\0", "not-terminated", "\0"]) {
    const run = f.capture("verification", output, [f.record("bad-input", data)]);
    assert.equal(run.status, 1);
    assert.equal(run.stdout, "");
    assert.equal(existsSync(output), false);
  }
  const input = f.paths("task.txt");
  const wrongHead = spawnSync(process.execPath, [script, "verification", f.worktree, "0".repeat(f.head.length), output, input],
    { encoding: "utf8", timeout: 10_000 });
  assert.equal(wrongHead.status, 1);
  assert.equal(wrongHead.stdout, "");
  assert.equal(existsSync(output), false);

  const shared = path.join(f.records, "group-readable");
  mkdirSync(shared, { mode: 0o755 });
  chmodSync(shared, 0o755);
  const publicOutput = path.join(shared, "output");
  const publicRun = f.capture("verification", publicOutput, [input]);
  assert.equal(publicRun.status, 1);
  assert.equal(publicRun.stdout, "");
  assert.equal(existsSync(publicOutput), false);

  const linkedInput = path.join(f.records, "linked-input");
  symlinkSync(input, linkedInput);
  assert.equal(f.capture("verification", output, [linkedInput]).status, 1);
  assert.equal(existsSync(output), false);
});
