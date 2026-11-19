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

collect: opens `<workspace>/.snapshot/gh-calls.jsonl` without blocking and
without following symbolic links, accepts only a single-link regular file
within a byte limit, finishes within a deadline, copies the bytes to a new
evidence directory outside the workspace, and prints the byte totals and the
issues whose body or comments some call's output depended on. Any failure
exits non-zero, and the run is then excluded.

coverage: checks a text file of the tool results that reached the candidate,
extracted from its transcript by the grader, for every line of every open
issue's body and comments, and prints which issues it covers.
"""

import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import sys

STAGED = ("bin/gh", ".snapshot/issues.json")
LEDGER = ".snapshot/gh-calls.jsonl"
MAX_BYTES = 16 * 1024 * 1024
DEADLINE_SECONDS = 30


def inside(path, root):
    path, root = os.path.realpath(path), os.path.realpath(root)
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def trusted_path(value, untrusted):
    """Return the canonical absolute PATH entries outside every untrusted root, in order.

    An entry is emitted as its resolved path, so a symbolic link that resolves
    outside the roots now cannot be redirected later.
    """
    kept = []
    for entry in value.split(os.pathsep):
        if not entry or not os.path.isabs(entry):
            continue
        canonical = os.path.realpath(entry)
        if any(inside(canonical, root) for root in untrusted):
            continue
        if canonical not in kept:
            kept.append(canonical)
    return kept


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


def stage(run_json, dest, tmpdir, base_path):
    run = json.loads(Path(run_json).read_text())
    workspace = os.path.realpath(run["workspace"])
    untrusted = [workspace, os.path.realpath(tmpdir)]
    if not os.path.isabs(dest):
        raise ValueError("the staging directory must be an absolute path")
    dest = Path(os.path.realpath(dest))
    if any(inside(dest, root) or inside(root, dest) for root in untrusted):
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
    path = [str(dest / "bin"), *trusted_path(base_path, untrusted)]
    return {
        "PATH": os.pathsep.join(path),
        "GH_SNAPSHOT_LOG": os.path.join(workspace, LEDGER),
        "stand_in": str(dest / "bin/gh"),
    }


def collect(run_json, out, max_bytes=MAX_BYTES, seconds=DEADLINE_SECONDS):
    run = json.loads(Path(run_json).read_text())
    out = Path(os.path.realpath(out))
    if inside(out, run["workspace"]):
        raise ValueError("the evidence directory must be outside the workspace")
    with deadline(seconds):
        data = read_regular(run["workspace"], LEDGER, max_bytes)
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


def detail_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]


def seen(line, text):
    return line in text or json.dumps(line, ensure_ascii=False)[1:-1] in text


def coverage(run_json, tool_output):
    """Report which open issues' bodies and comments appear in the tool output."""
    run = json.loads(Path(run_json).read_text())
    suite = json.loads(Path(run["suite"]).read_text())
    case = next(item for item in suite["evals"] if item["id"] == run["case_id"])
    snapshot = json.loads((Path(run["suite"]).parent / case["overlay"] / ".snapshot/issues.json").read_text())
    text = Path(tool_output).read_text()
    issues = [issue for issue in snapshot["issues"] if issue["state"] == "open"]
    bodies = [i["number"] for i in issues if all(seen(line, text) for line in detail_lines(i["body"]))]
    comments = [i["number"] for i in issues if i["comments"] and all(
        seen(line, text) for comment in i["comments"] for line in detail_lines(comment["body"]))]
    scope = case.get("read_scope", {})
    covered = set(scope.get("text", [])) <= set(bodies) and set(scope.get("comments", [])) <= set(comments)
    return {"body_issues": bodies, "comment_issues": comments, "covers_read_scope": covered}


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
    checking = commands.add_parser("coverage")
    checking.add_argument("--run", required=True, help="run.json from prepare.py")
    checking.add_argument("--tool-output", required=True,
                          help="text of the tool results that reached the candidate, from its transcript")
    args = parser.parse_args()
    try:
        if args.command == "stage":
            result = stage(args.run, args.dest, args.tmpdir, os.environ.get("PATH", ""))
        elif args.command == "collect":
            result = collect(args.run, args.out)
        else:
            result = coverage(args.run, args.tool_output)
    except (OSError, ValueError, TimeoutError) as error:
        sys.stderr.write(f"stage_gh.py {args.command}: {error}\n")
        sys.exit(1)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
