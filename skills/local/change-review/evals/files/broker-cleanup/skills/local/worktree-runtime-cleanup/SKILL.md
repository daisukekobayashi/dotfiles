---
name: worktree-runtime-cleanup
description: Stop a worktree's Compose stacks and confirmed dev servers, watchers, and tool daemons, then clean up temporary files created by those runs.
disable-model-invocation: true
---

# Worktree Runtime Cleanup

Dev servers, watchers, tool daemons, and Compose dependencies can outlive their
worktree or launcher. Tie cleanup to confirmed runtime ownership and retain
verification evidence.

Worktree cleanup skills (`github-worktree-cleanup`,
`azure-devops-worktree-cleanup`, `beads-merge-cleanup`) read this file and run
it for the worktree they are about to remove.

Run this before `git worktree remove`: the live worktree helps establish runtime
ownership, and Compose stacks can be matched by path rather than the weaker
`--stale` reasons.

## Dev Servers, Watchers, and Tool Daemons

Tools can launch detached processes in a worktree that survive the session
that started them: Codex plugin brokers (`app-server-broker.mjs --cwd
<worktree>`) with their `codex app-server`, MCP servers such as Serena, and
language servers such as Expert. No launch information for them exists in the
cleanup session, so discover them from process state.

1. Resolve the target worktree and list candidates with
   `scripts/list-processes.sh` in this skill's directory. The script only reads
   process state.
   - A worktree path given: `list-processes.sh <path>`.
   - No argument: `list-processes.sh` targets the current worktree root.
   - `--stale` given: `list-processes.sh --stale` lists processes whose cwd or
     `--cwd` argument no longer exists, such as runtimes left by a worktree
     already removed.
   Add dev servers/watchers known from existing launch information, tool
   sessions, or explicit user-provided targets. A cwd or `--cwd` under the
   target establishes ownership; a port or process name alone is insufficient.
   Interactive shells, terminal panes, and agent sessions with a tty (such as
   `zsh`, `claude`, or `codex` TUIs) are not runtimes: report them and leave them
   running. Report other uncertain candidates and leave them running too.
2. Group the candidates into trees by `ppid` and stop each tree from its
   topmost listed process, so the owner shuts down its children. Codex plugin
   brokers handle SIGTERM by closing their `codex app-server` and removing their
   socket and PID file. Preview the exact processes and owned children to stop.
   Obtain any required approval, honoring authorization already given for those
   targets. Immediately before stopping, recheck PID, start time, and launch
   context to detect PID reuse. If they no longer match, leave the process
   untouched and report it as unverified.
3. Prefer the documented shutdown command or owning tool session; otherwise use
   graceful termination. Include children only when their ownership is established,
   and signal a process group only when it is dedicated to this runtime. If shutdown
   fails, report what remains; obtain any additional approval needed for a forceful
   stop.
4. Verify that the owned processes and their listeners have exited by re-running
   the same `list-processes.sh` command. Sending a signal or ending the launcher
   alone does not establish cleanup. Report remaining processes and unverified
   ownership explicitly.

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
     It also lists projects left with only volumes (`working_dir` shown as
     `-`), whose owner cannot be determined from Docker state.
     This discovers Compose stacks only; native processes still require known
     launch context.
2. If nothing is listed, report that and continue with temporary-file cleanup.
3. Show the listed stacks (project, running/total, `working_dir`, reason) and
   get explicit confirmation for each project to stop.
   - When the target is a primary checkout (the one that owns `.git`) or the
     list came from `--stale`, the stacks may belong to other sessions: list
     them and let the user choose, with no pre-selected default.
   - A stack is worktree-owned when the target is a linked worktree, the list
     came from a path, and the reason is exactly `under target`. For these,
     also preview the volumes from
     `docker volume ls --filter label=com.docker.compose.project=<project>`;
     the confirmation covers deleting them, because they are unreachable once
     the worktree is gone.
4. Run `docker compose -p <project> down --remove-orphans` for each confirmed
   project, adding `--volumes` for worktree-owned stacks. For other stacks,
   volumes stay; add `--volumes` only when the user asks to delete data.
   Volumes marked `external` survive `--volumes` either way.
   - A volume-only project has nothing to bring down. Delete its volumes only
     when the user chooses that project: preview the names from
     `docker volume ls --filter label=com.docker.compose.project=<project>`,
     then run `docker volume rm` on exactly those names.
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
