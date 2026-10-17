---
name: worktree-runtime-cleanup
description: Stop a worktree's Compose stacks and confirmed dev servers/watchers, then clean up temporary files created by those runs.
disable-model-invocation: true
---

# Worktree Runtime Cleanup

Dev servers, watchers, and Compose dependencies can outlive their worktree or
launcher. Tie cleanup to confirmed runtime ownership and retain verification
evidence.

Worktree cleanup skills (`github-worktree-cleanup`,
`azure-devops-worktree-cleanup`, `beads-merge-cleanup`) read this file and run
it for the worktree they are about to remove.

Run this before `git worktree remove`: the live worktree helps establish runtime
ownership, and Compose stacks can be matched by path rather than the weaker
`--stale` reasons.

## Dev Servers and Watchers

1. Resolve the target worktree and identify its dev servers/watchers from existing
   launch information, tool sessions, or explicit user-provided targets. Confirm
   ownership using the worktree path and launch context; a port or process name
   alone is insufficient. Report uncertain candidates and leave them running.
2. Preview the exact processes and owned children to stop. Obtain any required
   approval, honoring authorization already given for those targets. Immediately
   before stopping, recheck PID, start time, and launch context to detect PID reuse.
   If they no longer match, leave the process untouched and report it as unverified.
3. Prefer the documented shutdown command or owning tool session; otherwise use
   graceful termination. Include children only when their ownership is established,
   and signal a process group only when it is dedicated to this runtime. If shutdown
   fails, report what remains; obtain any additional approval needed for a forceful
   stop.
4. Verify that the owned processes and their listeners have exited. Sending a
   signal or ending the launcher alone does not establish cleanup. Report remaining
   processes and unverified ownership explicitly.

## Compose Stacks

`docker compose run --rm` leaves `depends_on` services up, and a wrapper killed
by a tool timeout may never reach its `down` trap.

1. Resolve the target and list its stacks with `scripts/list-stacks.sh` in this
   skill's directory. The script only reads Docker state. If Docker is unavailable,
   report Compose cleanup as unverified and continue with the remaining checks.
   - A worktree path given: `list-stacks.sh <path>`.
   - No argument: `list-stacks.sh` targets the current worktree root.
   - `--stale` given: `list-stacks.sh --stale` lists stacks whose `working_dir`
     is missing or is not a registered worktree, across every repository.
     This discovers Compose stacks only; native processes still require known
     launch context.
2. If nothing is listed, report that and continue with temporary-file cleanup.
3. Show the listed stacks (project, running/total, `working_dir`, reason) and
   get explicit confirmation for each project to stop.
   - When the target is a primary checkout (the one that owns `.git`) or the
     list came from `--stale`, the stacks may belong to other sessions: list
     them and let the user choose, with no pre-selected default.
4. Run `docker compose -p <project> down --remove-orphans` for each confirmed
   project. Volumes stay; add `--volumes` only when the user asks to delete
   data.
5. Re-run the same `list-stacks.sh` command and report what stopped and what
   remains.

## Temporary Runtime Files

1. Identify exact sockets, PID files, temporary override configuration, or other
   temporary files created by those runs using existing launch information. Include
   the paths and ownership evidence in the cleanup preview and follow applicable
   deletion approvals. Resolve symlinks before deletion to establish the real target.
2. Remove only confirmed run-owned temporary files after the associated runtime
   has stopped. Leave files in place when runtime state or ownership is uncertain.
   Preserve shared or user-owned files, persistent data, and verification evidence
   such as logs, screenshots, and test output, even when stored in a temporary
   directory.
3. Verify removal and report stopped, remaining, and unverified runtimes, removed
   temporary paths, and retained evidence locations.

If a confirmed runtime remains running, report a cleanup blocker and leave its
temporary files and worktree intact.
