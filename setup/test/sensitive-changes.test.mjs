import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
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
const realStaged = process.env.DOTFILES_TEST_REAL_STAGED_SCANNER === "1";
const stagedCommand = "dotfiles-betterleaks-staged";
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
  writeFileSync(path.join(bin, stagedCommand),
    '#!/bin/sh\nDOTFILES_TEST_BACKEND=staged exec "$DOTFILES_TEST_FAKE_NODE" "$DOTFILES_TEST_FAKE_PROGRAM" "$@"\n',
    { mode: 0o700 });
  writeFileSync(fakeEnv.DOTFILES_TEST_FAKE_PROGRAM, `
    import fs from "node:fs";
    const staged = process.env.DOTFILES_TEST_BACKEND === "staged";
    if (process.argv[2] === "--version") {
      const version = staged ? "dotfiles-betterleaks-staged protocol 1 engine v1.10.1" : "betterleaks version 1.10.1";
      console.log(process.env.SCANNER_VERSION ?? version);
    } else {
      if (staged && process.argv.length !== 2) process.exit(8);
      if (process.argv.some((arg) => arg.startsWith("path=") && arg.includes("synthetic-hostname.example.test"))) {
        process.exit(8);
      }
      if (process.env.SCANNER_FAILURE) {
        console.error("synthetic-hostname.example.test");
        process.exit(8);
      }
      if (process.env.SCANNER_INVALID) process.exit(0);
      const input = fs.readFileSync(0);
      const blob = staged ? input.subarray(8 + input.readUInt32BE(0)) : input;
      if (blob.includes("SYNTHETIC_SECRET_SAMPLE")) {
        console.log(JSON.stringify([{ RuleID: "fixture", StartLine: 1, Match: "SYNTHETIC_SECRET_SAMPLE" }]));
        console.error("SYNTHETIC_SECRET_SAMPLE");
        process.exitCode = 21;
      } else {
        console.log("[]");
      }
    }
  `);
  // A remote helper answers `ls-remote` as the test configures it.
  writeFileSync(path.join(bin, "git-remote-fixture"), `#!/bin/sh
[ -z "$DOTFILES_TEST_REMOTE_FAIL" ] || exit 1
while read -r line; do
  case "$line" in
    capabilities) printf 'list\\n\\n' ;;
    list*) printf '@%s HEAD\\n%s %s\\n\\n' "$DOTFILES_TEST_REMOTE_HEAD" "$DOTFILES_TEST_REMOTE_OID" "$DOTFILES_TEST_REMOTE_HEAD" ;;
    *) exit 0 ;;
  esac
done
`, { mode: 0o700 });
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
  assert.match(staged.output, /finding secret:fixture staged "\[redacted path\]":1/);
  assert.doesNotMatch(staged.output, /SYNTHETIC_SECRET_SAMPLE/);
});

test("missing, mismatched, failing and malformed scanner results stop the check", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write("settings.txt", "safe staged content\n");
  f.git("add", "settings.txt");
  const missing = f.scan("staged", { PATH: f.gitOnly });
  assert.equal(missing.code, 2, missing.output);
  assert.match(missing.output, /The pinned staged scanner/);
  for (const options of [
    { SCANNER_VERSION: "dotfiles-betterleaks-staged protocol 2 engine v1.10.1" },
    { SCANNER_VERSION: "dotfiles-betterleaks-staged protocol 1 engine v1.10.0" },
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
  assert.match(output, /finding secret:fixture staged "\[redacted path\]":1/);
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
      [System.IO.File]::SetAccessControl($file, $acl)
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
    assert.match(allowed.output, /The pinned staged scanner/);
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
  // GitHub reports a branch creation with an all-zero before and a compare
  // URL that names no commits. The scan ignores that URL.
  const created = { created: true, compare: `${server}/${repository}/compare/topic` };
  f.git("remote", "add", "origin", "fixture::origin");
  const remote = { DOTFILES_TEST_REMOTE_HEAD: defaultRef, DOTFILES_TEST_REMOTE_OID: base };
  const firstPush = (extras = {}) => f.scan("ci", { ...f.event("0".repeat(40), head, created, firstRef), ...remote, ...extras });
  f.git("update-ref", "refs/remotes/origin/main", base);
  const output = firstPush();
  assert.equal(output.code, 21, output.output);
  assert.ok(output.output.includes(`finding secret:fixture ${middle}`));
  for (const extras of [{ DOTFILES_TEST_REMOTE_HEAD: "refs/heads/topic" }, { DOTFILES_TEST_REMOTE_FAIL: "1" }]) {
    const unmatched = firstPush(extras);
    assert.equal(unmatched.code, 2, unmatched.output);
    assert.match(unmatched.output, /remote default branch to match the event/);
  }
  for (const [extras, ref, reason] of [
    [{ compare: created.compare }, firstRef, /must be a branch creation/],
    [created, defaultRef, /first push of the default branch/],
  ]) {
    const invalid = f.scan("ci", f.event("0".repeat(40), head, extras, ref));
    assert.equal(invalid.code, 2, invalid.output);
    assert.match(invalid.output, reason);
  }
  f.git("update-ref", "-d", "refs/remotes/origin/main");
  const unfetched = firstPush();
  assert.equal(unfetched.code, 2, unfetched.output);
  assert.match(unfetched.output, /needs the fetched default branch/);
  // A revision lookup of the missing ref would resolve this tag and find nothing to scan.
  f.git("update-ref", "refs/tags/refs/remotes/origin/main", head);
  const substitute = firstPush();
  assert.equal(substitute.code, 2, substitute.output);
  assert.match(substitute.output, /needs the fetched default branch/);
  f.git("update-ref", "-d", "refs/tags/refs/remotes/origin/main");
  f.git("update-ref", "refs/remotes/origin/main", head);
  const merged = firstPush();
  assert.equal(merged.code, 0, merged.output);
  assert.match(merged.output, /sensitive changes: clean/);

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

test("CI requires the exact allowlist ref for ordinary branch pushes and pull requests", { skip: windows }, (t) => {
  const f = fixture(t);
  const ref = "refs/remotes/origin/main";
  f.write("base.txt", "baseline\n");
  const base = f.commit("baseline");
  const content = "SYNTHETIC_SECRET_SAMPLE\n";
  f.write("candidate.txt", content);
  const head = f.commit("candidate");
  const scanPush = () => f.scan("ci", f.event(base, head, {}, firstRef));
  const scanPr = () => f.scan("ci", {
    ...f.event(base, head, { pull_request: {
      base: { sha: base, repo: { full_name: repository } },
      head: { sha: head },
    } }),
    GITHUB_EVENT_NAME: "pull_request",
  });
  for (const scan of [scanPush, scanPr]) {
    const missing = scan();
    assert.equal(missing.code, 2, missing.output);
    assert.match(missing.output, /The reviewed allowlist revision could not be read/);
  }
  f.git("update-ref", `refs/tags/${ref}`, base);
  for (const scan of [scanPush, scanPr]) {
    const missing = scan();
    assert.equal(missing.code, 2, missing.output);
    assert.match(missing.output, /The reviewed allowlist revision could not be read/);
  }
  f.git("switch", "-qc", "approved-policy", base);
  f.write("scripts/sensitive-scan-allowlist.json", JSON.stringify([{
    path: "candidate.txt", rule: "secret:fixture", line: 1,
    contentSha256: createHash("sha256").update(content).digest("hex"),
    reason: "Approved synthetic fixture",
  }]));
  f.git("update-ref", ref, f.commit("approve exact finding"));
  for (const scan of [scanPush, scanPr]) {
    const approved = scan();
    assert.equal(approved.code, 0, approved.output);
  }
});

test("CI checks merge resolutions for secrets and ignores local denylist inputs", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write("base.txt", "baseline\n");
  const base = f.commit("baseline");
  f.git("switch", "-qc", "topic");
  f.write("topic.txt", "nonconflicting branch input\n");
  const topic = f.commit("topic");
  f.git("switch", "main");
  f.git("merge", "--no-ff", "--no-commit", topic);
  f.write("resolution.txt", `SYNTHETIC_SECRET_SAMPLE\n${marker}\n`);
  const merge = f.commit("merge resolution");
  const event = f.event(base, merge);
  const extra = {
    DOTFILES_SCAN_DENYLIST_FILE: f.denylist(),
    DOTFILES_SCAN_PRIVATE_DENYLIST: JSON.stringify([{ category: "hostname", value: marker }]),
  };
  const ci = f.scan("ci", event);
  assert.equal(ci.code, 21, ci.output);
  assert.ok(ci.output.includes(`finding secret:fixture ${merge} "[redacted path]":1`));
  assert.deepEqual(f.scan("ci", { ...event, ...extra }), ci);
  assert.ok(!ci.output.includes(marker));
  assert.doesNotMatch(ci.output, /personal|resolution\.txt/);
  assert.equal(f.scan("private-ci", { ...event, ...extra }).code, 2);
});

test("Git's submodule ignore configuration cannot hide a staged gitlink name", { skip: windows }, (t) => {
  const f = fixture(t);
  f.write("base.txt", "baseline\n");
  const base = f.commit("baseline");
  f.git("config", "diff.ignoreSubmodules", "all");
  f.git("update-index", "--add", "--cacheinfo", `160000,${base},${marker}`);
  const result = f.scan("staged", { DOTFILES_SCAN_DENYLIST_FILE: f.denylist() });
  assert.equal(result.code, 21, result.output);
  assert.match(result.output, /finding personal:hostname staged "\[redacted path\]":0/);
  assert.ok(!result.output.includes(marker));
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
  const approved = f.git("rev-parse", "HEAD");
  f.git("update-ref", "refs/remotes/origin/main", approved);
  f.git("add", "example.txt");
  assert.equal(f.scan("staged").code, 0);
  f.git("update-ref", "refs/tags/refs/remotes/origin/main", approved);
  f.git("update-ref", "-d", "refs/remotes/origin/main");
  assert.equal(f.scan("staged").code, 21);
  f.git("update-ref", "refs/remotes/origin/main", approved);
  f.write("example.txt", `${content}new content\n`);
  f.git("add", "example.txt");
  assert.equal(f.scan("staged").code, 21);
});

test("staged rejects invalid allowlist refs and uses older Git when the exact ref is valid", { skip: windows }, (t) => {
  const f = fixture(t);
  const ref = "refs/remotes/origin/main";
  f.write("base.txt", "baseline\n");
  const base = f.commit("baseline");
  f.write("candidate.txt", "safe candidate input\n");
  f.git("add", "candidate.txt");

  const legacyBin = path.join(path.dirname(f.gitOnly), "legacy-bin");
  mkdirSync(legacyBin);
  writeFileSync(path.join(legacyBin, "git"), `#!/bin/sh
for arg in "$@"; do
  [ "$arg" != --exists ] || exit 129
done
exec "$DOTFILES_TEST_INSTALLED_GIT" "$@"
`, { mode: 0o700 });
  const legacy = {
    PATH: `${legacyBin}${path.delimiter}${f.env.PATH}`,
    DOTFILES_TEST_INSTALLED_GIT: path.join(f.gitOnly, "git"),
  };
  const noRef = f.scan("staged", legacy);
  assert.equal(noRef.code, 2, noRef.output);
  assert.match(noRef.output, /The reviewed allowlist revision could not be read/);

  f.git("update-ref", ref, base);
  const valid = f.scan("staged", legacy);
  assert.equal(valid.code, 0, valid.output);

  f.git("update-ref", ref, f.git("rev-parse", `${base}^{tree}`));
  const noncommit = f.scan("staged");
  assert.equal(noncommit.code, 2, noncommit.output);
  assert.match(noncommit.output, /does not identify a commit/);

  f.git("symbolic-ref", ref, "refs/heads/missing");
  const dangling = f.scan("staged");
  assert.equal(dangling.code, 2, dangling.output);
  assert.match(dangling.output, /The reviewed allowlist revision could not be read/);
});

test("official CI scans prefiltered paths, binary and encoded blobs, and path-based rules", { skip: !realScanner }, (t) => {
  const f = fixture(t);
  const opts = { PATH: process.env.PATH };
  f.write("base.txt", "baseline");
  const base = f.commit("baseline");
  f.write(".gitattributes", "*.bin -diff\n");
  f.write("binary.bin", Buffer.concat([Buffer.from([0, 255, 0]), Buffer.from(`\n${realFinding}\n`)]));
  f.write("document.pdf", `\n\n${realFinding}\n`);
  f.write("package-lock.json", `\n\n\n${realFinding}\n`);
  f.write("encoded.txt", Buffer.from(realFinding).toString("base64"));
  f.write("container.pfx", "Inert path-only fixture, no certificate.\n");
  const head = f.commit("candidate");
  const result = f.scan("ci", { ...opts, ...f.event(base, head) });
  assert.equal(result.code, 21, result.output);
  for (const line of [1, 2, 3, 4]) {
    assert.ok(result.output.includes(`finding secret:github-pat ${head} "[redacted path]":${line}\n`), result.output);
  }
  assert.ok(result.output.includes(`finding secret:pkcs12-file ${head} "[redacted path]":0`));
  assert.ok(!result.output.includes(realFinding));
});

test("official CI dotted rule IDs report findings and honor exact scope exceptions", { skip: !realScanner }, (t) => {
  const f = fixture(t);
  const opts = { PATH: process.env.PATH };
  const file = "service.conf";
  const generated = createHash("sha512").update("inert sample for a dotted scanner rule").digest("hex").slice(0, 80);
  const content = `abuseipdb_api_key = "${generated}"\n`;
  f.write("base.txt", "baseline");
  const base = f.commit("baseline");
  f.write(file, content);
  const head = f.commit("candidate");
  const initial = f.scan("ci", { ...opts, ...f.event(base, head) });
  assert.equal(initial.code, 21, initial.output);
  assert.ok(initial.output.includes(`finding secret:abuseipdb-api-key.1 ${head} "[redacted path]":1`));
  assert.ok(!initial.output.includes(generated));

  f.git("switch", "-qc", "approved-policy", base);
  f.write("scripts/sensitive-scan-allowlist.json", JSON.stringify([{
    path: file, rule: "secret:abuseipdb-api-key.1", line: 1,
    contentSha256: createHash("sha256").update(content).digest("hex"),
    reason: "Approved synthetic fixture",
  }]));
  const policy = f.commit("approve exact finding");
  f.write(file, content);
  const allowedHead = f.commit("known fixture");
  const allowed = f.scan("ci", { ...opts, ...f.event(policy, allowedHead) });
  assert.equal(allowed.code, 0, allowed.output);
  f.write(file, `${content}changed blob\n`);
  const changedHead = f.commit("alter blob");
  const changed = f.scan("ci", { ...opts, ...f.event(allowedHead, changedHead) });
  assert.equal(changed.code, 21, changed.output);
});

test("official CI content matches are never disclosed in diagnostic filenames", { skip: !realScanner }, (t) => {
  const f = fixture(t);
  const opts = { PATH: process.env.PATH };
  const value = "Synthetic-Only-57Kx8-evaluate";
  f.write("base.txt", "baseline\n");
  const base = f.commit("baseline");
  f.write(`backup-${value}.tf`, `password = "${value}"\n`);
  const head = f.commit("candidate");
  const ci = f.scan("ci", { ...opts, ...f.event(base, head) });
  assert.equal(ci.code, 21, ci.output);
  assert.ok(ci.output.includes(`finding secret:generic-password ${head} "[redacted path]":1`));
  assert.ok(!ci.output.includes(value));
});

function stagedFrame(file, blob) {
  const name = Buffer.from(file);
  const content = Buffer.from(blob);
  const header = Buffer.alloc(8);
  header.writeUInt32BE(name.length, 0);
  header.writeUInt32BE(content.length, 4);
  return Buffer.concat([header, name, content]);
}

test("staged adapter matches official detection, exclusions, and raw blob behavior", { skip: !realScanner || !realStaged }, (t) => {
  const f = fixture(t);
  const config = path.join(f.cwd, "fixed.toml");
  writeFileSync(config, 'prefilter = "false"\n\n[extend]\nuseDefault = true\n');
  const opts = { cwd: f.cwd, env: { ...f.env, PATH: process.env.PATH }, encoding: "utf8", timeout: 10_000 };
  const fixtures = [
    ["archive.zip", realFinding, 21],
    ["@octokit/auth-token/README.md", realFinding, 0],
    ["container.p12", "inert content", 21],
    ["empty.p12", "", 0],
    ["--format=other/受理.p12", "inert content", 21],
    [".betterleaksignore", realFinding, 21],
    ["literal.txt", realFinding + " # betterleaks:allow", 21],
    ["document.pdf", `%PDF-1.7\n${realFinding}`, 0],
    ["binary.bin", Buffer.concat([Buffer.from([0, 255, 0]), Buffer.from(`\n${realFinding}\n`)]), 21],
    ["encoded.txt", Buffer.from(realFinding).toString("base64"), 21],
    ["safe.txt", "ordinary text", 0],
  ];
  for (const [file, blob, expected] of fixtures) {
    const baseline = spawnSync("betterleaks", [
      "stdin", "--config", config, "--set-attr", `path=${file}`, "--no-banner", "--no-color", "--redact=100",
      "--log-level", "error", "--ignore-gitleaks-allow", "--max-decode-depth", "2",
      "--report-format", "json", "--report-path", "-", "--exit-code", "21",
    ], { ...opts, input: blob });
    const staged = spawnSync(stagedCommand, [], { ...opts, input: stagedFrame(file, blob) });
    assert.equal(baseline.error, undefined);
    assert.equal(staged.error, undefined);
    assert.equal(baseline.status, expected, file);
    assert.equal(staged.status, expected, file);
    const project = (rows) => rows.map(({ RuleID, StartLine }) => ({ RuleID, StartLine }));
    assert.deepEqual(JSON.parse(staged.stdout), project(JSON.parse(baseline.stdout)), file);
    assert.ok(!staged.stdout.includes(file) && !staged.stdout.includes(realFinding));
    assert.equal(staged.stderr, "");
  }
  const frame = stagedFrame("private-metadata.example.test", "ordinary text");
  const oversizedName = Buffer.from(frame);
  oversizedName.writeUInt32BE(64 * 1024 + 1, 0);
  const oversizedBlob = Buffer.from(frame);
  oversizedBlob.writeUInt32BE(64 * 1024 * 1024 + 1, 4);
  const malformed = [
    frame.subarray(0, frame.length - 1), oversizedName, oversizedBlob,
    stagedFrame(Buffer.from([0xff]), ""), stagedFrame("name\0end", ""),
    Buffer.concat([frame, Buffer.from([0])]),
  ];
  for (const input of malformed) {
    const result = spawnSync(stagedCommand, [], { ...opts, input });
    assert.equal(result.status, 2);
    assert.equal(result.stdout, "");
    assert.equal(result.stderr.trim(), "Staged scanner could not complete the scan.");
  }
});

test("staged adapter preserves private path context and blocks the real Git hook", { skip: !realStaged || windows }, (t) => {
  const f = fixture(t);
  const file = `bundle-${marker}.p12`;
  const content = "inert file-only fixture";
  f.write("scripts/sensitive-scan-allowlist.json", JSON.stringify([{
    path: file, rule: "personal:hostname", line: 0,
    contentSha256: createHash("sha256").update(content).digest("hex"),
    reason: "Approved synthetic path only",
  }]));
  const policy = f.commit("approve exact private-path exception");
  f.git("update-ref", "refs/remotes/origin/main", policy);
  f.write(".githooks/pre-commit", readFileSync(new URL("../../.githooks/pre-commit", import.meta.url)));
  f.write("scripts/check-sensitive-changes.mjs", readFileSync(script));
  f.write("scripts/check-skills-build.sh", "#!/bin/sh\nprintf '%s\\n' 'build check ran'\n");
  for (const file of [".githooks/pre-commit", "scripts/check-skills-build.sh"]) {
    chmodSync(path.join(f.cwd, file), 0o700);
  }
  f.write(file, content);
  f.git("add", file);
  const env = { ...f.env, PATH: process.env.PATH, DOTFILES_SCAN_DENYLIST_FILE: f.denylist() };
  const result = spawnSync("git", ["-c", "core.hooksPath=.githooks", "commit", "-qm", "candidate"],
    { cwd: f.cwd, env, encoding: "utf8", timeout: 15_000 });
  assert.equal(result.error, undefined);
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 1, output);
  assert.match(output, /build check ran/);
  assert.match(output, /finding secret:pkcs12-file staged "\[redacted path\]":0/);
  assert.doesNotMatch(output, /finding personal:hostname/);
  assert.ok(!output.includes(marker));
  assert.equal(f.git("rev-parse", "HEAD"), policy);
});

test("staged adapter leaves private filename data out of the OS command line", {
  skip: !realStaged || process.platform !== "linux",
  timeout: 15_000,
}, async (t) => {
  const value = "Synthetic-Only-57Kx8-evaluate";
  const filename = `backup-${value}.tf`;
  const blob = Buffer.concat([Buffer.from(`password = "${value}"\n`), Buffer.alloc(1024 * 1024, 10)]);
  const frame = stagedFrame(filename, blob);
  const child = spawn(stagedCommand, [], { stdio: ["pipe", "pipe", "pipe"] });
  t.after(() => child.kill());
  try {
    let output = "";
    let errors = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { output += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { errors += chunk; });
    const closed = once(child, "close");
    await once(child, "spawn");
    // Hold the child open after feeding the private path and most of the blob.
    const lastByte = frame.length - 1;
    await new Promise((resolve, reject) => {
      child.stdin.write(frame.subarray(0, lastByte), (error) => error ? reject(error) : resolve());
    });
    const argv = readFileSync(`/proc/${child.pid}/cmdline`).toString().split("\0").filter(Boolean);
    assert.deepEqual(argv, [stagedCommand]);
    child.stdin.end(frame.subarray(lastByte));
    const [code] = await closed;
    assert.equal(code, 21, errors);
    assert.ok(JSON.parse(output).some(({ RuleID }) => RuleID === "generic-password"));
    assert.ok(!(output + errors).includes(value));
  } finally {
    child.kill();
  }
});
