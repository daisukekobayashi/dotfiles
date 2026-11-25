import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(new URL("../../scripts/check-sensitive-changes.mjs", import.meta.url));
const repository = "example/dotfiles";
const defaultRef = "refs/heads/main";
const server = "https://github.com";
const marker = "synthetic-hostname.example.test";
const firstRef = "refs/heads/topic";
const realScanner = process.env.DOTFILES_TEST_REAL_BETTERLEAKS === "1";
const windows = process.platform === "win32";
const realFinding = ["ghp_", "xRFj6FBf8b6Yy3JZp6rDarxZcPs00UTAYCji"].join("");

function fixture(t) {
  const scratch = mkdtempSync(path.join(tmpdir(), "dotfiles-scan-test-"));
  t.after(() => rmSync(scratch, { recursive: true, force: true }));
  const cwd = path.join(scratch, "repo");
  const bin = path.join(scratch, "bin");
  mkdirSync(cwd);
  mkdirSync(bin);
  const env = Object.fromEntries(Object.entries(process.env)
    .filter(([name]) => !/^(GIT_|GITHUB_|DOTFILES_SCAN_|BETTERLEAKS_|GITLEAKS_)/i.test(name)));
  const originalPath = Object.entries(env).find(([name]) => name.toUpperCase() === "PATH");
  delete env[originalPath[0]];
  const fakeEnv = {
    ...env,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: process.platform === "win32" ? "NUL" : "/dev/null",
    GIT_AUTHOR_NAME: "Fixture Writer",
    GIT_AUTHOR_EMAIL: "fixture@example.test",
    GIT_COMMITTER_NAME: "Fixture Writer",
    GIT_COMMITTER_EMAIL: "fixture@example.test",
    DOTFILES_TEST_FAKE_NODE: process.execPath,
    DOTFILES_TEST_FAKE_PROGRAM: path.join(scratch, "fake.mjs"),
    PATH: `${bin}${path.delimiter}${originalPath[1]}`,
  };
  writeFileSync(path.join(bin, "betterleaks"), '#!/bin/sh\nexec "$DOTFILES_TEST_FAKE_NODE" "$DOTFILES_TEST_FAKE_PROGRAM" "$@"\n',
    { mode: 0o700 });
  writeFileSync(fakeEnv.DOTFILES_TEST_FAKE_PROGRAM, `
    import fs from "node:fs";
    if (process.argv[2] === "--version") {
      console.log(process.env.SCANNER_VERSION ?? "betterleaks version 1.10.1");
    } else {
      if (process.env.SCANNER_FAILURE) {
        console.error("synthetic-hostname.example.test");
        process.exit(8);
      }
      if (process.env.SCANNER_INVALID) process.exit(0);
      const input = fs.readFileSync(0);
      if (input.includes("SYNTHETIC_SECRET_SAMPLE")) {
        console.log(JSON.stringify([{ RuleID: "fixture", StartLine: 1, Match: "SYNTHETIC_SECRET_SAMPLE" }]));
        console.error("SYNTHETIC_SECRET_SAMPLE");
        process.exitCode = 21;
      } else {
        console.log("[]");
      }
    }
  `);
  const gitOnly = path.join(scratch, "git-only");
  if (!windows) {
    const installedGit = spawnSync("/bin/sh", ["-c", "command -v git"], { env: fakeEnv, encoding: "utf8", timeout: 5_000 });
    assert.equal(installedGit.status, 0);
    mkdirSync(gitOnly);
    symlinkSync(installedGit.stdout.trim(), path.join(gitOnly, "git"));
  }
  function git(...args) {
    const r = spawnSync("git", ["-c", "core.hooksPath=/dev/null", ...args], {
      cwd, env: fakeEnv, encoding: "utf8", timeout: 10_000,
    });
    assert.equal(r.status, 0, r.stderr);
    return r.stdout.trim();
  }
  function write(file, data) {
    const destination = path.join(cwd, file);
    mkdirSync(path.dirname(destination), { recursive: true });
    writeFileSync(destination, data);
  }
  function commit(msg) {
    git("add", "--all");
    git("commit", "-qm", msg);
    return git("rev-parse", "HEAD");
  }
  function scan(mode, options = {}) {
    const r = spawnSync(process.execPath, [script, mode], {
      cwd, env: { ...fakeEnv, ...options }, encoding: "utf8", timeout: 20_000,
    });
    assert.equal(r.error, undefined);
    return { code: r.status, output: `${r.stdout}${r.stderr}` };
  }
  function event(before, after, extras = {}, ref = defaultRef) {
    const eventFile = path.join(scratch, "event.json");
    writeFileSync(eventFile, JSON.stringify({
      ref, before, after, repository: { full_name: repository, default_branch: "main" }, ...extras,
    }));
    return {
      GITHUB_EVENT_NAME: "push",
      GITHUB_EVENT_PATH: eventFile,
      GITHUB_REF: ref,
      GITHUB_REPOSITORY: repository,
      GITHUB_SERVER_URL: server,
      GITHUB_SHA: after,
      GITHUB_WORKFLOW_SHA: after,
      GITHUB_WORKFLOW_REF: `${repository}/.github/workflows/sensitive-changes.yml@${ref}`,
    };
  }
  function denylist(file = path.join(scratch, "private.json")) {
    writeFileSync(file, JSON.stringify([{ category: "hostname", value: marker }]), { mode: 0o600 });
    return file;
  }
  git("init", "-q", "-b", "main");
  return { cwd, env: fakeEnv, gitOnly, git, write, commit, scan, event, denylist };
}

test("reads the staged index, handles an unborn HEAD and suppresses scanner internals", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write("settings.txt", "safe staged content\n");
  f.git("add", "settings.txt");
  f.write("settings.txt", "SYNTHETIC_SECRET_SAMPLE\n");
  const unstaged = f.scan("staged");
  assert.equal(unstaged.code, 0, unstaged.output);
  assert.match(unstaged.output, /private denylist unavailable/);
  f.git("add", "settings.txt");
  f.write("settings.txt", "clean after staging\n");
  const staged = f.scan("staged");
  assert.equal(staged.code, 21, staged.output);
  assert.match(staged.output, /finding secret:fixture staged "settings.txt":1/);
  assert.doesNotMatch(staged.output, /SYNTHETIC_SECRET_SAMPLE/);
});

test("missing, mismatched, failing and malformed scanner results stop the check", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write("settings.txt", "safe staged content\n");
  f.git("add", "settings.txt");
  const missing = f.scan("staged", { PATH: f.gitOnly });
  assert.equal(missing.code, 2, missing.output);
  assert.match(missing.output, /Betterleaks 1\.10\.1 is required/);
  for (const options of [
    { SCANNER_VERSION: "betterleaks version 1.10.0" },
    { SCANNER_FAILURE: "1" },
    { SCANNER_INVALID: "1" },
  ]) {
    const result = f.scan("staged", options);
    assert.equal(result.code, 2, result.output);
    assert.match(result.output, /incomplete/);
    assert.doesNotMatch(result.output, new RegExp(marker, "u"));
  }
});

test("the normal Git hook still checks the build and blocks publication of a finding", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write(".githooks/pre-commit", readFileSync(new URL("../../.githooks/pre-commit", import.meta.url)));
  f.write("scripts/check-sensitive-changes.mjs", readFileSync(script));
  f.write("scripts/check-skills-build.sh", "#!/bin/sh\nprintf '%s\\n' 'build check ran'\n");
  for (const file of [".githooks/pre-commit", "scripts/check-skills-build.sh"]) {
    chmodSync(path.join(f.cwd, file), 0o700);
  }
  function commitFromHook() {
    f.git("add", "--all");
    return spawnSync("git", ["-c", "core.hooksPath=.githooks", "commit", "-qm", "fixture"],
      { cwd: f.cwd, env: f.env, encoding: "utf8", timeout: 20_000 });
  }
  f.write("candidate.txt", "SYNTHETIC_SECRET_SAMPLE\n");
  const stopped = commitFromHook();
  assert.equal(stopped.status, 1, stopped.stdout + stopped.stderr);
  const output = stopped.stdout + stopped.stderr;
  assert.match(output, /build check ran/);
  assert.match(output, /finding secret:fixture staged "candidate.txt":1/);
  assert.ok(!output.includes("SYNTHETIC_SECRET_SAMPLE"));
  f.write("candidate.txt", "clean fixture\n");
  const allowed = commitFromHook();
  assert.equal(allowed.status, 0, allowed.stdout + allowed.stderr);
});

test("native Windows denylist ACL admits the owner and rejects an unrelated principal", { skip: !windows }, (t) => {
  const f = fixture(t);
  const privateFile = f.denylist();
  f.write("settings.txt", marker);
  f.git("add", "--all");
  function ownerAcl(extra) {
    const powershell = path.join(process.env.SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    const result = spawnSync(powershell, ["-NoProfile", "-NonInteractive", "-Command", `
      $ErrorActionPreference = 'Stop'
      $file = $env:DOTFILES_TEST_ACL_FILE
      $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
      $acl = New-Object System.Security.AccessControl.FileSecurity
      $acl.SetOwner($me)
      $acl.SetAccessRuleProtection($true, $false)
      $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($me, 'FullControl', 'Allow'))
      if ($env:DOTFILES_TEST_ACL_OTHER -eq 'yes') {
        $other = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-11')
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($other, 'Read', 'Allow'))
      }
      Set-Acl -LiteralPath $file -AclObject $acl
    `], {
      env: { ...f.env, DOTFILES_TEST_ACL_FILE: privateFile, DOTFILES_TEST_ACL_OTHER: extra },
      encoding: "utf8", timeout: 20_000,
    });
    assert.equal(result.status, 0, result.stderr);
  }
  ownerAcl("no");
  const opts = { DOTFILES_SCAN_DENYLIST_FILE: privateFile };
  const allowed = f.scan("staged", opts);
  if (allowed.code === 21) {
    assert.match(allowed.output, /finding personal:hostname/);
  } else {
    assert.equal(allowed.code, 2, allowed.output);
    assert.match(allowed.output, /Betterleaks 1\.10\.1 is required/);
  }
  ownerAcl("yes");
  const rejected = f.scan("staged", opts);
  assert.equal(rejected.code, 2, rejected.output);
  assert.match(rejected.output, /Windows access rules could not be verified/);
  assert.ok(!rejected.output.includes(marker));
});

test("external denylist is private, suppresses matching filenames and rejects unsafe input", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write(`${marker}.txt`, `line one\n${marker}\n`);
  f.git("add", "--all");
  const file = f.denylist();
  const configured = f.scan("staged", { DOTFILES_SCAN_DENYLIST_FILE: file });
  assert.equal(configured.code, 21, configured.output);
  assert.match(configured.output, /finding personal:hostname staged "\[redacted path\]":0/);
  assert.match(configured.output, /finding personal:hostname staged "\[redacted path\]":2/);
  assert.ok(!configured.output.includes(marker));
  chmodSync(file, 0o644);
  const mode = f.scan("staged", { DOTFILES_SCAN_DENYLIST_FILE: file });
  assert.equal(mode.code, 2, mode.output);
  const inRepo = f.denylist(path.join(f.cwd, "private.json"));
  const inside = f.scan("staged", { DOTFILES_SCAN_DENYLIST_FILE: inRepo });
  assert.equal(inside.code, 2, inside.output);
  writeFileSync(file, marker, { mode: 0o600 });
  chmodSync(file, 0o600);
  const invalid = f.scan("staged", { DOTFILES_SCAN_DENYLIST_FILE: file });
  assert.equal(invalid.code, 2, invalid.output);
  assert.ok(!invalid.output.includes(marker));
});

test("branch pushes and fork PRs scan removed intermediate commits with exact baselines", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write("payload.txt", "baseline\n");
  const base = f.commit("baseline");
  f.write("payload.txt", "SYNTHETIC_SECRET_SAMPLE\n");
  const middle = f.commit("middle");
  f.write("payload.txt", "visible final state\n");
  const head = f.commit("head");
  f.git("update-ref", "refs/remotes/origin/main", head);
  const first = f.event("0".repeat(40), head, {
    created: true, compare: `${server}/${repository}/compare/${base}...${head}`,
  }, firstRef);
  const output = f.scan("ci", first);
  assert.equal(output.code, 21, output.output);
  assert.ok(output.output.includes(`finding secret:fixture ${middle}`));
  const bad = f.scan("ci", f.event("0".repeat(40), head, { created: true, compare: `${server}/${repository}/commit/${head}` }, firstRef));
  assert.equal(bad.code, 2, bad.output);
  assert.match(bad.output, /no exact comparison base/);

  const pr = f.event(base, head, { pull_request: {
    base: { sha: base, repo: { full_name: repository } },
    head: { sha: head, repo: { full_name: "contributor/fork" } },
  } });
  const fork = f.scan("ci", { ...pr, GITHUB_EVENT_NAME: "pull_request", DOTFILES_SCAN_PRIVATE_DENYLIST: marker });
  assert.equal(fork.code, 21, fork.output);
  assert.ok(fork.output.includes(middle));
  assert.ok(!fork.output.includes(marker));

  const forced = f.scan("ci", f.event(base, head, { forced: true }, firstRef));
  assert.equal(forced.code, 21, forced.output);
  const missing = f.scan("ci", f.event("1".repeat(40), head, {}, firstRef));
  assert.equal(missing.code, 2, missing.output);
  assert.match(missing.output, /event commit is missing/);
});

test("trusted CI checks merge resolutions with only private input", (t) => {
  const f = fixture(t);
  f.write("base.txt", "baseline\n");
  const base = f.commit("baseline");
  f.git("switch", "-qc", "topic");
  f.write("topic.txt", "nonconflicting branch input\n");
  const topic = f.commit("topic");
  f.git("switch", "main");
  f.git("merge", "--no-ff", "--no-commit", topic);
  const sensitiveFilename = `${realFinding}.txt`;
  f.write(sensitiveFilename, marker);
  const merge = f.commit("merge resolution");
  const extra = { DOTFILES_SCAN_PRIVATE_DENYLIST: JSON.stringify([{ category: "hostname", value: marker }]) };
  const trusted = f.scan("private-ci", { ...f.event(base, merge), ...extra });
  assert.equal(trusted.code, 21, trusted.output);
  assert.ok(!trusted.output.includes(sensitiveFilename), "private CI must suppress every filename");
  assert.ok(trusted.output.includes(`finding personal:hostname ${merge} "[redacted path]":1`));
  assert.ok(!trusted.output.includes(marker));
  const notTrusted = f.scan("private-ci", { ...f.event(base, merge, {}, firstRef), ...extra });
  assert.equal(notTrusted.code, 2, notTrusted.output);
  assert.ok(!notTrusted.output.includes(marker));
  const foreignWorkflow = f.scan("private-ci", {
    ...f.event(base, merge), ...extra, GITHUB_WORKFLOW_SHA: base,
  });
  assert.equal(foreignWorkflow.code, 2, foreignWorkflow.output);
  const optional = f.scan("private-ci");
  assert.equal(optional.code, 0, optional.output);
  assert.match(optional.output, /private denylist unavailable/);
});

test("a staged ignore file or unreviewed allowlist cannot exempt a finding", { skip: windows }, (t) => {
  const f = fixture(t);
  const content = "SYNTHETIC_SECRET_SAMPLE\n";
  const policy = JSON.stringify([{
    path: "example.txt", rule: "secret:fixture", line: 1,
    contentSha256: createHash("sha256").update(content).digest("hex"),
    reason: "Known synthetic fixture",
  }]);
  f.write("base.txt", "initial content");
  const base = f.commit("baseline");
  f.git("update-ref", "refs/remotes/origin/main", base);
  f.write("scripts/sensitive-scan-allowlist.json", policy);
  f.write(".betterleaksignore", "fixture\n");
  f.write("example.txt", content);
  f.git("add", "--all");
  assert.equal(f.scan("staged").code, 21);
  f.git("reset", "--quiet", "--", "example.txt", ".betterleaksignore");
  f.git("commit", "-qm", "approve narrowly scoped exception");
  f.git("update-ref", "refs/remotes/origin/main", f.git("rev-parse", "HEAD"));
  f.git("add", "example.txt");
  assert.equal(f.scan("staged").code, 0);
  f.write("example.txt", `${content}new content\n`);
  f.git("add", "example.txt");
  assert.equal(f.scan("staged").code, 21);
});

test("pinned Betterleaks runs on retained binary and encoded staged content", { skip: !realScanner }, (t) => {
  const f = fixture(t);
  const opts = { PATH: process.env.PATH };
  f.write(".gitattributes", "*.data -diff\n");
  f.write("binary.data", Buffer.concat([Buffer.from([0, 255, 0]), Buffer.from(`\n${realFinding}\n`)]));
  f.write("encoded.txt", Buffer.from(realFinding).toString("base64"));
  f.git("add", "--all");
  const result = f.scan("staged", opts);
  assert.equal(result.code, 21, result.output);
  assert.match(result.output, /finding secret:github-pat staged "binary\.data"/);
  assert.match(result.output, /finding secret:github-pat staged "encoded\.txt"/);
  assert.ok(!result.output.includes(realFinding));
});
