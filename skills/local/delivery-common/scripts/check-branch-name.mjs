#!/usr/bin/env node
// Check that branch names are safe to put into git, gh, and az commands.
//
// Usage:
//   node check-branch-name.mjs -- '<name>' ['<name>' ...]
//
// A safe branch name is non-empty, uses only [A-Za-z0-9/._-], and does not
// start with `-`. The charset leaves out whitespace, quotes, `$`, `;`, `=`,
// and `+`, so a name cannot add shell syntax, an option value, or a leading
// `+` that would turn a push refspec into a force push. The leading `-` rule
// keeps a name from being parsed as an option such as `--force`.
//
// Callers single-quote each name and never write a name containing `'` or a
// newline into a command; they treat such a name as unsafe without running
// this script.
//
// Every argument after the leading `--` is a name; the `--` is required so
// that a host shell which drops it fails here instead of checking fewer names.
//
// Exit status:
//   0  every name is safe
//   1  at least one name is unsafe; each one is reported on stderr as
//      `unsafe branch name: <JSON string>`
//   2  usage error: the first argument is not `--`, or no name follows it
// Any other failure, such as a missing script or node, means the check could
// not run.

const SAFE_BRANCH_NAME = /^[A-Za-z0-9/._][A-Za-z0-9/._-]*$/;

const [marker, ...names] = process.argv.slice(2);

if (marker !== "--" || names.length === 0) {
  process.stderr.write("usage: check-branch-name.mjs -- '<name>' ['<name>' ...]\n");
  process.exit(2);
}

let unsafe = false;
for (const name of names) {
  if (!SAFE_BRANCH_NAME.test(name)) {
    process.stderr.write(`unsafe branch name: ${JSON.stringify(name)}\n`);
    unsafe = true;
  }
}

process.exit(unsafe ? 1 : 0);
