#!/usr/bin/env node
// Capture an optional workflow's inputs before a checkpoint commit.
//
// Usage (from a POSIX host such as WSL):
//   node write-phase-input-key.mjs preflight <worktree> <head> <output> <decisions> <shared-understanding>
//   node write-phase-input-key.mjs verification <worktree> <head> <output> <changed-paths>
//
// Pass the canonical worktree root and its full expected HEAD. Pass absolute,
// normalized paths to regular input files and an unused output in private task
// records outside the worktree. changed-paths is a list of exact repo-relative
// path bytes, each terminated with NUL, or an empty file. On success, write the
// input frame in a new mode-600 file and print only <phase>:<HEAD>:<Git blob ID>.
// On failure, print a diagnostic without input data and return no key.

import { execFileSync } from "node:child_process";
import { constants as bufferConstants } from "node:buffer";
import {
  closeSync, constants, fstatSync, lstatSync, openSync, readFileSync,
  readlinkSync, realpathSync, statSync, unlinkSync, writeFileSync,
} from "node:fs";
import path from "node:path";

function readRegularFile(file) {
  const fd = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = fstatSync(fd);
    if (!info.isFile()) throw new Error("input is not a regular file");
    // Git normalizes a regular file's mode using the owner execute bit.
    return { mode: (info.mode & constants.S_IXUSR) ? "100755" : "100644", content: readFileSync(fd) };
  } finally {
    closeSync(fd);
  }
}

function privateRecord(file, worktree) {
  if (!path.isAbsolute(file) || path.normalize(file) !== file) {
    throw new Error("records require absolute, normalized paths");
  }
  const parent = path.dirname(file);
  const relative = path.relative(worktree, parent);
  if (relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative)) {
    throw new Error("records must be outside the worktree");
  }
  if (realpathSync(parent) !== parent) throw new Error("records directory must be its own real path");
  const info = statSync(parent);
  if (!info.isDirectory() || info.uid !== process.getuid() || (info.mode & 0o077)) {
    throw new Error("records directory must be private and owned by the current user");
  }
}

function nulPaths(bytes) {
  const names = [];
  let start = 0;
  while (start < bytes.length) {
    const end = bytes.indexOf(0, start);
    if (end <= start) throw new Error("expected non-empty NUL-terminated paths");
    names.push(bytes.subarray(start, end));
    start = end + 1;
  }
  return names;
}

// Latin-1 preserves byte identity even for a filename outside UTF-8.
function pathParts(name) {
  const parts = name.toString("latin1").split("/");
  if (parts.some((part) => ["", ".", "..", ".git"].includes(part.toLowerCase()))) {
    throw new Error("expected exact repository-relative file paths");
  }
  return parts;
}

function fileParts(worktree, name) {
  let file = Buffer.from(worktree);
  const parts = pathParts(name);
  for (const part of parts.slice(0, -1)) {
    file = Buffer.concat([file, Buffer.from(`/${part}`, "latin1")]);
    if (!lstatSync(file).isDirectory()) throw new Error("file is outside a real worktree directory");
  }
  file = Buffer.concat([file, Buffer.from(`/${parts.at(-1)}`, "latin1")]);
  const { mode, content } = lstatSync(file).isSymbolicLink()
    ? { mode: "120000", content: readlinkSync(file, { encoding: "buffer" }) }
    : readRegularFile(file);
  return [Buffer.from(`file ${mode} ${name.length} ${content.length}\n`), name, content];
}

function gitInput(worktree, input, run, git) {
  const reported = new Set(nulPaths(input).map((name) => {
    pathParts(name);
    return name.toString("latin1");
  }));
  const diff = git(["diff", "--binary", "--no-ext-diff", "--no-textconv", "--no-color", "HEAD"]);
  const parts = [Buffer.from(`diff ${diff.length}\n`), diff];
  if (reported.size) {
    // The fixed Bash adapter passes raw path bytes through argv, including names
    // not representable by JavaScript strings. Every value remains one argument.
    const listed = run("bash", ["--noprofile", "--norc", "-c", [
      "paths=()",
      'while IFS= read -r -d "" path; do paths+=("$path"); done',
      'exec git --no-optional-locks -c core.fsmonitor=false --literal-pathspecs ls-files -z --others --exclude-standard -- "${paths[@]}"',
    ].join("\n")], input);
    for (const name of nulPaths(listed).filter((name) => reported.has(name.toString("latin1"))).sort(Buffer.compare)) {
      parts.push(...fileParts(worktree, name));
    }
  }
  return Buffer.concat(parts);
}

function writeRecord(output, frame) {
  const fd = openSync(output, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
  try {
    try {
      writeFileSync(fd, frame);
    } finally {
      closeSync(fd);
    }
  } catch (error) {
    unlinkSync(output);
    throw error;
  }
}

function main([phase, worktree, head, output, ...inputs]) {
  if ((phase !== "preflight" && phase !== "verification") || !worktree || !output
      || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(head ?? "")
      || inputs.length !== (phase === "preflight" ? 2 : 1)) {
    throw new Error("expected phase, canonical worktree, full HEAD, output and phase input files");
  }
  if (process.platform === "win32") throw new Error("private records require a POSIX host such as WSL");
  if (realpathSync(worktree) !== worktree) throw new Error("worktree must be its own real path");
  privateRecord(output, worktree);
  for (const input of inputs) privateRecord(input, worktree);

  const env = { ...process.env, LC_ALL: "C" };
  delete env.BASH_ENV;
  const run = (command, args, input) => {
    try {
      return execFileSync(command, args, {
        cwd: worktree, env, input, maxBuffer: bufferConstants.MAX_LENGTH,
        stdio: [input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
      });
    } catch {
      throw new Error(`${command} could not capture phase input`);
    }
  };
  const git = (args, input) => run("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", ...args], input);
  for (const variable of git(["rev-parse", "--local-env-vars"]).toString().trim().split("\n")) {
    delete env[variable];
  }
  const expected = () => git(["rev-parse", "--verify", "HEAD"]).toString().trim() === head;
  if (git(["rev-parse", "--show-prefix"]).toString() !== "\n"
      || git(["rev-parse", "--is-inside-work-tree"]).toString().trim() !== "true" || !expected()) {
    throw new Error("worktree root or HEAD does not match");
  }

  const bytes = inputs.map((file) => readRegularFile(file).content);
  const frame = phase === "preflight"
    ? Buffer.concat([Buffer.from(`decisions ${bytes[0].length}\n`), bytes[0],
      Buffer.from(`shared-understanding ${bytes[1].length}\n`), bytes[1]])
    : gitInput(worktree, bytes[0], run, git);
  const digest = git(["hash-object", "--stdin", "--no-filters"], frame).toString().trim();
  if (!expected()) throw new Error("HEAD changed during capture");
  writeRecord(output, frame);
  process.stdout.write(`${phase}:${head}:${digest}\n`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  // Filesystem errors can include the task's private paths.
  const reason = error.code ? `filesystem error (${error.code})` : error.message;
  process.stderr.write(`phase input unavailable: ${reason}\n`);
  process.exitCode = 1;
}
