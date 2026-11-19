#!/usr/bin/env python3
"""Stage the offline gh stand-in for one run, and collect its call ledger.

The coordinator runs this outside the candidate, after evaluate-skill's
prepare.py and before launch (`stage`), and after the run before deleting the
workspace (`collect`). It never starts a model.

stage: copies the prepared workspace's `bin/gh` and `.snapshot/issues.json`,
checked against the hashes in run.json, into a new directory outside the
workspace and the run's temp directory, makes the copy read-only, and prints
the environment for the launch: PATH with the staged `bin` first followed by
the caller's PATH without empty, relative, or candidate-writable entries, and
GH_SNAPSHOT_LOG naming the ledger in the workspace. Inherited Claude hooks run
outside the sandbox with the Claude process's PATH, so no PATH entry may be a
directory the candidate can write.

collect: opens `<workspace>/.snapshot/gh-calls.jsonl` only as a regular file
reached without symbolic links, copies its bytes to a new evidence directory
outside the workspace, and prints the byte totals and the issues whose text the
run received.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys

STAGED = ("bin/gh", ".snapshot/issues.json")
LEDGER = ".snapshot/gh-calls.jsonl"


def inside(path, root):
    path, root = os.path.realpath(path), os.path.realpath(root)
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def trusted_path(value, untrusted):
    """Keep absolute PATH entries outside every untrusted root, in order."""
    kept = []
    for entry in value.split(os.pathsep):
        if not entry or not os.path.isabs(entry):
            continue
        if any(inside(entry, root) for root in untrusted):
            continue
        if entry not in kept:
            kept.append(entry)
    return kept


def read_regular(root, relative):
    """Read root/relative without following a symbolic link at any level."""
    root = os.path.realpath(root)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        parts = relative.split("/")
        for part in parts[:-1]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        file_fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
    finally:
        os.close(fd)
    with os.fdopen(file_fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ValueError(f"not a regular file: {relative}")
        return handle.read()


def stage(run_json, dest, tmpdir, base_path):
    run = json.loads(Path(run_json).read_text())
    workspace = run["workspace"]
    untrusted = [workspace, tmpdir]
    if any(inside(dest, root) or inside(root, dest) for root in untrusted):
        raise ValueError("the staging directory must be outside the workspace and the run's temp directory")
    dest = Path(dest)
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
    path = [str(dest / "bin"), *trusted_path(base_path, untrusted)]
    return {
        "PATH": os.pathsep.join(path),
        "GH_SNAPSHOT_LOG": os.path.join(os.path.realpath(workspace), LEDGER),
        "stand_in": str((dest / "bin/gh").resolve()),
    }


def collect(run_json, out):
    run = json.loads(Path(run_json).read_text())
    out = Path(out)
    if inside(out, run["workspace"]):
        raise ValueError("the evidence directory must be outside the workspace")
    data = read_regular(run["workspace"], LEDGER)
    out.mkdir(mode=0o700)
    with open(out / "gh-calls.jsonl", "xb") as handle:
        handle.write(data)
    entries = [json.loads(line) for line in data.decode().splitlines() if line.strip()]
    by_kind = {}
    for entry in entries:
        by_kind[entry["kind"]] = by_kind.get(entry["kind"], 0) + entry["stdout_bytes"]
    ok = [entry for entry in entries if entry["exit"] == 0]
    return {
        "calls": len(entries),
        "gh_bytes": sum(entry["stdout_bytes"] for entry in entries),
        "gh_bytes_by_kind": by_kind,
        "text_issues": sorted({n for entry in ok for n in entry["text"]}),
        "comment_issues": sorted({n for entry in ok for n in entry["comments"]}),
        "stand_ins": sorted({entry["exe"] for entry in entries}),
        "ledger": str(out / "gh-calls.jsonl"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    staging = commands.add_parser("stage")
    staging.add_argument("--run", required=True, help="run.json from prepare.py")
    staging.add_argument("--dest", required=True, help="new directory for the read-only stand-in")
    staging.add_argument("--tmpdir", required=True, help="the run's fresh temp directory")
    collecting = commands.add_parser("collect")
    collecting.add_argument("--run", required=True, help="run.json from prepare.py")
    collecting.add_argument("--out", required=True, help="new evidence directory outside the workspace")
    args = parser.parse_args()
    if args.command == "stage":
        result = stage(args.run, args.dest, args.tmpdir, os.environ.get("PATH", ""))
    else:
        result = collect(args.run, args.out)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
