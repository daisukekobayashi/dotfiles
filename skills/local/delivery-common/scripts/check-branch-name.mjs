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
// Callers write a name into this or any command only when it uses solely
// ASCII letters, digits, `/`, `.`, `_`, and `-`, and single-quote it; any other
// name is unsafe without running this script. Some shells treat more than
// `'` as a quote, such as PowerShell with U+2018-U+201B, so a name with such a
// character could end the quoting before this script ever sees it. This script
// stays the authority for the leading `-` and any later rule.
//
// Every argument after the leading `--` is a name; the `--` is required so
// that a host shell which drops it fails here instead of checking fewer names.
//
// Exit status:
//   0  every name is safe
//   2  usage error: the first argument is not `--`, or no name follows it
//   3  at least one name is unsafe; each one is reported on stderr as
//      `unsafe branch name: <JSON string>`
// Any other status, including 1, which node uses for a missing script or an
// uncaught error, means the check could not run.

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

process.exit(unsafe ? 3 : 0);
