import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const {
  ancestorProblem,
  isInsideOrSame,
  isLocalAbsoluteTemp,
  privateSkillsBase,
  userPrivateGid,
} = require("../private-base.js");

const noTmpdir = () => assert.fail("tmpdir must not be read");
const noHomedir = () => assert.fail("homedir must not be read");

test("Windows TEMP must name a local drive", () => {
  for (const value of ["C:\\Users\\me\\AppData\\Local\\Temp", "c:/temp", "\\\\?\\C:\\Temp"]) {
    assert.equal(isLocalAbsoluteTemp(value, path.win32), true, value);
    assert.equal(privateSkillsBase({ TEMP: value }, "win32", path.win32, noTmpdir, noHomedir), value);
  }
  for (const value of [
    "\\\\server\\share\\temp",
    "//server/share/temp",
    "\\\\?\\UNC\\server\\share\\temp",
    "\\\\.\\C:\\Temp",
    "\\Temp",
    "/Temp",
    "C:Temp",
    "Temp",
  ]) {
    assert.equal(isLocalAbsoluteTemp(value, path.win32), false, value);
    assert.throws(
      () => privateSkillsBase({ TEMP: value }, "win32", path.win32, noTmpdir, noHomedir),
      /set TEMP to an absolute per-user directory/,
      value,
    );
  }
});

test("Windows TMP follows the same rule when TEMP is unset", () => {
  assert.equal(privateSkillsBase({ TMP: "D:\\Temp" }, "win32", path.win32, noTmpdir, noHomedir), "D:\\Temp");
  assert.throws(
    () => privateSkillsBase({ TMP: "\\\\server\\share" }, "win32", path.win32, noTmpdir, noHomedir),
    /set TEMP to an absolute per-user directory/,
  );
});

test("macOS refuses a relative temp directory", () => {
  assert.equal(privateSkillsBase({}, "darwin", path.posix, () => "/var/folders/x/T", noHomedir), "/var/folders/x/T");
  assert.throws(
    () => privateSkillsBase({}, "darwin", path.posix, () => "tmp", noHomedir),
    /set TMPDIR to an absolute per-user directory/,
  );
});

test("Linux keeps the XDG cache and home fallbacks", () => {
  assert.equal(privateSkillsBase({ XDG_CACHE_HOME: "/x/cache" }, "linux", path.posix, noTmpdir, noHomedir), "/x/cache");
  assert.equal(privateSkillsBase({ XDG_CACHE_HOME: "rel", HOME: "/home/me" }, "linux", path.posix, noTmpdir, noHomedir), "/home/me/.cache");
  assert.throws(
    () => privateSkillsBase({ HOME: "rel" }, "linux", path.posix, noTmpdir, noHomedir),
    /set HOME or XDG_CACHE_HOME to an absolute path/,
  );
});

test("the in-project check ignores letter case only on Windows", () => {
  assert.equal(isInsideOrSame("c:\\proj\\temp", "C:\\Proj", path.win32, "win32"), true);
  assert.equal(isInsideOrSame("C:\\PROJ", "c:\\proj", path.win32, "win32"), true);
  assert.equal(isInsideOrSame("C:\\Proj2\\temp", "C:\\Proj", path.win32, "win32"), false);
  assert.equal(isInsideOrSame("C:\\", "C:\\", path.win32, "win32"), true);
  assert.equal(isInsideOrSame("/home/me/proj/tmp", "/home/me/proj", path.posix, "linux"), true);
  assert.equal(isInsideOrSame("/home/me/Proj/tmp", "/home/me/proj", path.posix, "linux"), false);
  assert.equal(isInsideOrSame("/home/me/proj2", "/home/me/proj", path.posix, "linux"), false);
});

const passwd = [
  "root:x:0:0:root:/root:/bin/bash",
  "me:x:1000:1000:Me:/home/me:/bin/bash",
  "other:x:1001:100:Other:/home/other:/bin/bash",
  "",
].join("\n");
const group = [
  "root:x:0:",
  "users:x:100:",
  "me:x:1000:",
  "",
].join("\n");

test("a user-private group is the user's own primary group with no other members", () => {
  assert.equal(userPrivateGid(1000, 1000, "linux", passwd, group), 1000);
});

test("a group is not user-private when that cannot be shown", () => {
  const cases = {
    "macOS": [1000, 1000, "darwin", passwd, group],
    "missing passwd": [1000, 1000, "linux", undefined, group],
    "missing group": [1000, 1000, "linux", passwd, undefined],
    "shared primary group": [1001, 100, "linux", passwd, group],
    "listed member": [1000, 1000, "linux", passwd, group.replace("me:x:1000:", "me:x:1000:other")],
    "user listed in own group": [1000, 1000, "linux", passwd, group.replace("me:x:1000:", "me:x:1000:me")],
    "another user's primary group": [1000, 1000, "linux", `${passwd}guest:x:1002:1000::/home/guest:/bin/sh\n`, group],
    "group named differently": [1000, 1000, "linux", passwd, group.replace("me:x:1000:", "staff:x:1000:")],
    "group not listed": [1000, 1000, "linux", passwd, "root:x:0:\n"],
    "user not listed": [1000, 1000, "linux", "root:x:0:0:root:/root:/bin/bash\n", group],
    "process gid is not the primary group": [1000, 100, "linux", passwd, group],
    "duplicate uid": [1000, 1000, "linux", `${passwd}me2:x:1000:1000::/home/me2:/bin/sh\n`, group],
    "duplicate gid": [1000, 1000, "linux", passwd, `${group}me-too:x:1000:\n`],
    "NIS compat entry": [1000, 1000, "linux", passwd, `${group}+:::\n`],
    "malformed line": [1000, 1000, "linux", passwd, `${group}broken\n`],
  };
  for (const [name, args] of Object.entries(cases)) {
    assert.equal(userPrivateGid(...args), undefined, name);
  }
});

test("ancestors allow group write only for the user's private group on a directory the user owns", () => {
  const owner = { uid: 1000, privateGid: 1000 };
  assert.equal(ancestorProblem({ uid: 1000, gid: 1000, mode: 0o40755 }, owner), undefined);
  assert.equal(ancestorProblem({ uid: 0, gid: 0, mode: 0o40755 }, owner), undefined);
  assert.equal(ancestorProblem({ uid: 1000, gid: 1000, mode: 0o40775 }, owner), undefined);
  assert.equal(ancestorProblem({ uid: 1000, gid: 100, mode: 0o40775 }, owner), "group");
  assert.equal(ancestorProblem({ uid: 1000, gid: 1000, mode: 0o40775 }, { uid: 1000 }), "group");
  assert.equal(ancestorProblem({ uid: 0, gid: 1000, mode: 0o40775 }, owner), "group");
  assert.equal(ancestorProblem({ uid: 0, gid: 0, mode: 0o40775 }, owner), "group");
  assert.equal(ancestorProblem({ uid: 1001, gid: 1000, mode: 0o40755 }, owner), "owner");
  assert.equal(ancestorProblem({ uid: 1000, gid: 1000, mode: 0o40757 }, owner), "owner");
  assert.equal(ancestorProblem({ uid: 0, gid: 0, mode: 0o41777 }, owner), "owner");
});

test("Windows refuses a TEMP whose real path is not on a local drive", () => {
  const { localRealPath } = require("../private-base.js");
  const resolved = {
    "Z:\\Temp": "\\\\server\\share\\Temp",
    "Y:\\Temp": "\\\\?\\UNC\\server\\share\\Temp",
    "S:\\Temp": "C:\\Users\\me\\Temp",
    "C:\\Temp": "C:\\Temp",
  };
  const realpath = (value) => resolved[value];
  assert.equal(localRealPath("S:\\Temp", realpath, path.win32, "win32"), "C:\\Users\\me\\Temp");
  assert.equal(localRealPath("C:\\Temp", realpath, path.win32, "win32"), "C:\\Temp");
  for (const value of ["Z:\\Temp", "Y:\\Temp"]) {
    assert.throws(
      () => localRealPath(value, realpath, path.win32, "win32"),
      /set TEMP to an absolute per-user directory/,
      value,
    );
  }
  assert.equal(localRealPath("/srv/share", () => "/srv/share", path.posix, "linux"), "/srv/share");
});

// Keep these directories under the ignored setup/node_modules, like the runtime
// fixtures: a shared temp directory such as /tmp is refused.
function privateScratch(t) {
  const cache = path.join(import.meta.dirname, "..", "node_modules", ".cache");
  fs.mkdirSync(cache, { recursive: true });
  const root = fs.mkdtempSync(path.join(cache, "private-base-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return fs.realpathSync.native(root);
}

test("a directory another run creates between plan and creation is kept as existing", { skip: process.platform === "win32" }, (t) => {
  const { createPrivateDirs, planPrivateDir } = require("../private-base.js");
  const root = privateScratch(t);
  const shared = path.join(root, "base", "dotfiles-skills-npm-cache");
  const ours = path.join(root, "ours");
  const elsewhere = path.join(root, "elsewhere");
  const swapped = path.join(root, "swapped");
  fs.mkdirSync(elsewhere, { mode: 0o700 });
  const plans = [planPrivateDir(shared, "the skills npm cache"), planPrivateDir(ours, "ours"), planPrivateDir(swapped, "swapped")];
  const racing = (directory) => {
    // Another run wins the race for the shared directories, and swaps one for a link.
    if (directory === path.dirname(shared) || directory === shared) {
      fs.mkdirSync(directory, { mode: 0o700 });
    }
    if (directory === swapped) {
      fs.symlinkSync(elsewhere, directory);
    }
    fs.mkdirSync(directory, { mode: 0o700 });
  };

  createPrivateDirs(plans.slice(0, 2), undefined, racing);
  assert.equal(fs.statSync(shared).isDirectory(), true);
  assert.equal(fs.statSync(ours).isDirectory(), true);

  fs.rmdirSync(ours);
  assert.throws(() => createPrivateDirs(plans, undefined, racing), /swapped .*changed while it was created/);
  // The refusal removes only what this call created, not what the other run created.
  assert.equal(fs.statSync(shared).isDirectory(), true);
  assert.equal(fs.existsSync(ours), false);
});
