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
workspace.

collect: within one deadline, opens `<workspace>/.snapshot/gh-calls.jsonl`
without blocking or following symbolic links, accepts only a single-link
regular file within a byte limit, validates each record as it reads it,
copies the bytes to a new evidence directory outside the workspace, and prints
the totals and the issues that successful `gh issue view` calls read in full.
Any failure exits non-zero, and the run is then excluded.
"""

import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import signal
import stat
import sys

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


def stage(run_json, dest, tmpdir):
    run = json.loads(Path(run_json).read_text())
    workspace = os.path.realpath(run["workspace"])
    if not os.path.isabs(dest):
        raise ValueError("the staging directory must be an absolute path")
    dest = Path(os.path.realpath(dest))
    if os.pathsep in str(dest):
        raise ValueError(f"the staging directory must not contain {os.pathsep!r}")
    # dest is new, so neither root can lie below it; only the other direction needs a check.
    if any(inside(dest, root) for root in (workspace, tmpdir)):
        raise ValueError("the staging directory must be outside the workspace and the run's temp directory")
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


def summarize(data):
    """Validate the ledger line by line, keeping only running totals."""
    calls, total, by_form, detail, stand_ins = 0, 0, {}, set(), set()
    for raw in io.BytesIO(data):
        if not raw.strip():
            continue
        entry = record(raw)
        calls += 1
        total += entry["stdout_bytes"]
        key = entry["form"] or "refused"
        by_form[key] = by_form.get(key, 0) + entry["stdout_bytes"]
        if entry["detail"] is not None:
            detail.add(entry["detail"])
        stand_ins.add(entry["exe"])
    return {"calls": calls, "gh_bytes": total, "gh_bytes_by_form": by_form,
            "detail_issues": sorted(detail), "stand_ins": sorted(stand_ins)}


def collect(run_json, out, max_bytes=MAX_BYTES, seconds=DEADLINE_SECONDS):
    run = json.loads(Path(run_json).read_text())
    out = Path(os.path.realpath(out))
    if inside(out, run["workspace"]):
        raise ValueError("the evidence directory must be outside the workspace")
    with deadline(seconds):
        data = read_regular(run["workspace"], LEDGER, max_bytes)
        summary = summarize(data)
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
