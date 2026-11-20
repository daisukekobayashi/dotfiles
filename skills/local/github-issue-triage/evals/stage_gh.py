#!/usr/bin/env python3
"""Stage the offline gh stand-in for one run, and collect its call ledger.

The coordinator runs this outside the candidate, after evaluate-skill's
prepare.py and before launch (`stage`), and after the run before deleting the
workspace (`collect`). It never starts a model.

stage: copies the prepared workspace's `bin/gh` and `.snapshot/issues.json`,
checked against the hashes in run.json, into a new absolute directory outside
the workspace and the run's temp directory, makes the copy read-only, and
prints the launch environment. PATH is fixed, never inherited: the staged
`bin`, then FIXED_PATH. Inherited Claude hooks run outside the sandbox with
the agent process's PATH, so this keeps every bare hook command and `gh` off
directories the candidate can write. GH_SNAPSHOT_LOG names the ledger in the
workspace. Because the agent CLI usually lives outside FIXED_PATH, stage also
resolves the prepared launch_argv's CLI to an absolute executable from the
caller's PATH, before the fixed PATH applies, checks it lies outside the
workspace, the temp directory, and the staging directory, and prints the
launch_argv to use for both the pre-run checks and the launch.

collect: within one deadline, opens `<workspace>/.snapshot/gh-calls.jsonl`
without blocking or following symbolic links, accepts only a single-link
regular file within a byte limit, validates each record as it reads it,
copies the bytes to a new evidence directory outside the workspace, and prints
the totals and the issues that successful `gh issue view` calls read in full.
It derives each record's form and issue from its arguments and exit status
with the stand-in's own command rules, loaded from the committed fixture, and
rejects a record whose stored form or detail disagrees; grading uses only the
derived values, and the byte totals are informational.
Any failure exits non-zero, and the run is then excluded.
"""

import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import sys
import types

STAGED = ("bin/gh", ".snapshot/issues.json")
LEDGER = ".snapshot/gh-calls.jsonl"
FIXED_PATH = ("/usr/bin", "/bin", "/usr/sbin", "/sbin")
MAX_BYTES = 4 * 1024 * 1024
MAX_LINE_BYTES = 64 * 1024
DEADLINE_SECONDS = 30
FORMS = {"repo view", "issue list", "pr list", "api blocked_by", "api sub_issues", "issue view", "pr view"}


def inside(path, root):
    """True when path is root or below it, compared by file identity.

    Comparing device and inode, not spelling, also catches aliases such as a
    different letter case on a case-insensitive file system.
    """
    try:
        target = os.stat(root)
    except FileNotFoundError:
        return False
    current = os.path.abspath(path)
    while True:
        try:
            if os.path.samestat(os.stat(current), target):
                return True
        except FileNotFoundError:
            pass
        parent = os.path.dirname(current)
        if parent == current:
            return False
        current = parent


@contextlib.contextmanager
def deadline(seconds):
    """Raise TimeoutError if the block runs longer than seconds."""
    def expire(signum, frame):
        raise TimeoutError(f"collection exceeded {seconds} seconds")

    previous = signal.signal(signal.SIGALRM, expire)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def read_regular(root, relative, max_bytes=MAX_BYTES):
    """Read root/relative as a single-link regular file of at most max_bytes.

    No open blocks or follows a symbolic link at any level, and the file type,
    link count, and size are checked on the descriptor before reading.
    """
    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW
    fd = os.open(os.path.realpath(root), os.O_RDONLY | os.O_DIRECTORY)
    try:
        parts = relative.split("/")
        for part in parts[:-1]:
            next_fd = os.open(part, flags | os.O_DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        file_fd = os.open(parts[-1], flags, dir_fd=fd)
    finally:
        os.close(fd)
    with os.fdopen(file_fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ValueError(f"not a regular file: {relative}")
        if info.st_nlink != 1:
            raise ValueError(f"has {info.st_nlink} hard links: {relative}")
        if info.st_size > max_bytes:
            raise ValueError(f"larger than {max_bytes} bytes: {relative}")
        data = handle.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise ValueError(f"larger than {max_bytes} bytes: {relative}")
    return data


def resolve_outside(name, caller_path, untrusted):
    """Return the absolute path where name was found on the caller's PATH.

    The path is kept as found, not resolved, so a shim that dispatches on its
    own name, such as a mise `node` link to the `mise` binary, still works.
    Both that path and its resolved target must lie outside the untrusted roots.
    """
    found = shutil.which(name, path=caller_path)
    if found is None:
        raise ValueError(f"cannot resolve {name} on the caller's PATH")
    found = os.path.abspath(found)
    for path in (found, os.path.realpath(found)):
        if any(inside(path, root) for root in untrusted):
            raise ValueError(f"{path} lies in a directory the candidate can write")
    return found


def trusted_executable(name, caller_path, untrusted):
    """Return the argv prefix that runs name without a PATH lookup at launch.

    A launcher whose shebang is `#!/usr/bin/env <interpreter>` would look the
    interpreter up on the fixed PATH, so the interpreter is resolved here too
    and placed first. Any other env shebang, such as one with options, is
    refused; a shebang that names an absolute interpreter needs no lookup.
    """
    launcher = resolve_outside(name, caller_path, untrusted)
    with open(launcher, "rb") as handle:
        first = handle.read(256).split(b"\n", 1)[0]
    if not first.startswith(b"#!"):
        return [launcher]
    words = first[2:].decode(errors="replace").split()
    if not words or os.path.basename(words[0]) != "env":
        return [launcher]
    if len(words) != 2 or words[1].startswith("-"):
        raise ValueError(f"unsupported env shebang in {launcher}: {first.decode(errors='replace')}")
    return [resolve_outside(words[1], caller_path, untrusted), launcher]


def stage(run_json, dest, tmpdir, caller_path=None):
    run = json.loads(Path(run_json).read_text())
    caller_path = os.environ.get("PATH", "") if caller_path is None else caller_path
    workspace = os.path.realpath(run["workspace"])
    if not os.path.isabs(dest):
        raise ValueError("the staging directory must be an absolute path")
    dest = Path(os.path.realpath(dest))
    if os.pathsep in str(dest):
        raise ValueError(f"the staging directory must not contain {os.pathsep!r}")
    # dest is new, so neither root can lie below it; only the other direction needs a check.
    if any(inside(dest, root) for root in (workspace, tmpdir)):
        raise ValueError("the staging directory must be outside the workspace and the run's temp directory")
    launcher = trusted_executable(run["launch_argv"][0], caller_path, (workspace, tmpdir, dest))
    dest.mkdir(mode=0o700)
    for relative in STAGED:
        data = read_regular(workspace, relative)
        if hashlib.sha256(data).hexdigest() != run["initial_files"].get(relative):
            raise ValueError(f"{relative} differs from the prepared workspace")
        target = dest / relative
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o555 if relative == "bin/gh" else 0o444)
    for directory in (dest / "bin", dest / ".snapshot", dest):
        directory.chmod(0o555)
    return {
        "PATH": os.pathsep.join([str(dest / "bin"), *FIXED_PATH]),
        "GH_SNAPSHOT_LOG": os.path.join(workspace, LEDGER),
        "stand_in": str(dest / "bin/gh"),
        "launch_argv": [*launcher, *run["launch_argv"][1:]],
    }


def record(line):
    """Validate one ledger line and return it as a dict."""
    if len(line) > MAX_LINE_BYTES:
        raise ValueError("ledger line too long")
    entry = json.loads(line)
    if not isinstance(entry, dict) or set(entry) != {
            "argv", "form", "exit", "stdout_bytes", "stderr_bytes", "detail", "exe"}:
        raise ValueError("ledger line has unexpected keys")
    if not (isinstance(entry["argv"], list) and all(isinstance(arg, str) for arg in entry["argv"])
            and (entry["form"] is None or entry["form"] in FORMS)
            and entry["exit"] in (0, 1)
            and all(isinstance(entry[k], int) and not isinstance(entry[k], bool) and entry[k] >= 0
                    for k in ("stdout_bytes", "stderr_bytes"))
            and (entry["detail"] is None or (isinstance(entry["detail"], int) and entry["form"] == "issue view"))
            and isinstance(entry["exe"], str)
            and (entry["exit"] == 0) == (entry["form"] is not None)):
        raise ValueError("ledger line has invalid values")
    return entry


def stand_in_rules():
    """Load the committed stand-in, never the workspace copy, for its command rules.

    The source is compiled in memory, so no bytecode is written into the fixture,
    which prepare.py would otherwise copy into every workspace.
    """
    source = Path(__file__).resolve().parent / "files/tasklet/bin/gh"
    module = types.ModuleType("gh_stand_in")
    module.__file__ = str(source)
    exec(compile(source.read_text(), str(source), "exec"), module.__dict__)
    return module


def derive(entry, rules, snapshot):
    """Return the (form, detail) the arguments and exit status imply, or raise ValueError."""
    try:
        form, number = rules.match(entry["argv"], snapshot["repository"])
    except rules.Refusal:
        form, number = None, None
    if entry["exit"] == 0:
        if form is None:
            raise ValueError("a successful record names an undocumented call")
        items = snapshot["pull_requests"] if form == "pr view" else snapshot["issues"]
        if number is not None and number not in {item["number"] for item in items}:
            raise ValueError("a successful record names an unknown number")
        derived = (form, number if form == "issue view" else None)
    else:
        derived = (None, None)
    if (entry["form"], entry["detail"]) != derived:
        raise ValueError("a ledger record's form or detail disagrees with its arguments")
    return derived


def summarize(data, snapshot):
    """Validate the ledger line by line, keeping only running totals of derived values."""
    rules = stand_in_rules()
    calls, total, by_form, detail, stand_ins = 0, 0, {}, set(), set()
    for raw in io.BytesIO(data):
        if not raw.strip():
            continue
        entry = record(raw)
        form, number = derive(entry, rules, snapshot)
        calls += 1
        total += entry["stdout_bytes"]
        key = form or "refused"
        by_form[key] = by_form.get(key, 0) + entry["stdout_bytes"]
        if number is not None:
            detail.add(number)
        stand_ins.add(entry["exe"])
    return {"calls": calls, "gh_bytes": total, "gh_bytes_by_form": by_form,
            "detail_issues": sorted(detail), "stand_ins": sorted(stand_ins)}


def case_snapshot(run):
    """Read the case's snapshot from the committed suite, not the workspace."""
    suite_path = Path(run["suite"])
    suite = json.loads(suite_path.read_text())
    case = next(item for item in suite["evals"] if item["id"] == run["case_id"])
    return json.loads((suite_path.parent / case["overlay"] / ".snapshot/issues.json").read_text())


def collect(run_json, out, max_bytes=MAX_BYTES, seconds=DEADLINE_SECONDS):
    run = json.loads(Path(run_json).read_text())
    out = Path(os.path.realpath(out))
    if inside(out, run["workspace"]):
        raise ValueError("the evidence directory must be outside the workspace")
    with deadline(seconds):
        data = read_regular(run["workspace"], LEDGER, max_bytes)
        summary = summarize(data, case_snapshot(run))
        out.mkdir(mode=0o700)
        with open(out / "gh-calls.jsonl", "xb") as handle:
            handle.write(data)
    summary["ledger"] = str(out / "gh-calls.jsonl")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    staging = commands.add_parser("stage")
    staging.add_argument("--run", required=True, help="run.json from prepare.py")
    staging.add_argument("--dest", required=True, help="new absolute directory for the read-only stand-in")
    staging.add_argument("--tmpdir", required=True, help="the run's fresh temp directory")
    collecting = commands.add_parser("collect")
    collecting.add_argument("--run", required=True, help="run.json from prepare.py")
    collecting.add_argument("--out", required=True, help="new evidence directory outside the workspace")
    args = parser.parse_args()
    try:
        if args.command == "stage":
            result = stage(args.run, args.dest, args.tmpdir)
        else:
            result = collect(args.run, args.out)
    except (OSError, ValueError, TimeoutError) as error:
        sys.stderr.write(f"stage_gh.py {args.command}: {error}\n")
        sys.exit(1)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
