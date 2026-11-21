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
it for the worktree they are about to remove. Review skills that run Codex
follow only [Process Trees Started by a Codex Review](#process-trees-started-by-a-codex-review),
so a broker or sandboxed command tree found at cleanup is a leak to report.

A confirmation a cleanup skill obtained from its Caller preview covers only the
runtime resources listed there with the same identifiers: processes by PID,
start time, and cwd, Compose projects with their `working_dir` and volumes, and
temporary file paths. Get a separate confirmation for any other resource.

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
   process state. A non-zero exit means the listing is unavailable, never
   empty: report the processes as unverified. A row can contain invalid UTF-8.
   Run the script under the caller's locale, check its exit status, and only
   then apply `LC_ALL=C` to the tool that reads its saved output, as in
   `list="$(mktemp)" && list-processes.sh <path> >"$list" && LC_ALL=C cut -f1 "$list"`.
   - A worktree path given: `list-processes.sh <path>`.
   - No argument: `list-processes.sh` targets the current worktree root.
   - `--stale` given: `list-processes.sh --stale` lists processes whose cwd or
     `--cwd` argument no longer exists, such as runtimes left by a worktree
     already removed.
   Add dev servers/watchers known from existing launch information, tool
   sessions, or explicit user-provided targets. A cwd or `--cwd` under the
   target establishes ownership; a port or process name alone is insufficient.
   A row with reason `cwd ambiguous` or `--cwd ambiguous` never establishes
   ownership, because its cwd or `--cwd` may name another directory: report it
   as uncertain.
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

## Process Trees Started by a Codex Review

`change-review`, `change-adversarial-review`, and `change-security-review`
follow this section around each Codex companion run for a target worktree. The
run owns the process trees it starts under the target: the companion's
`app-server-broker.mjs` with its `codex app-server`, and the sandboxed commands
Codex runs, such as `codex-linux-sandbox -> node -> git hash-object --stdin`,
which can outlive the run, blocked on input, after their parent exits.
Stopping them needs no confirmation. `scripts/stop-run-processes.mjs` in this
skill's directory decides which processes the run started, sends them only
SIGTERM, and signals nothing else; its header states the rules. Runs started
together for one worktree as a set count as one run: record before any starts
and stop after all end.

1. Before the run, record the process table in a new directory outside the
   worktree:

   ```text
   dir="$(mktemp -d)" &&
     node <this skill>/scripts/stop-run-processes.mjs record <worktree> "$dir/record.json"
   ```

   A non-zero exit leaves no usable record: run the review, report the
   teardown as unverified, and skip step 2.
2. After the run, whether it succeeded or failed, run
   `node <this skill>/scripts/stop-run-processes.mjs stop <worktree> "$dir/record.json"`,
   then remove `$dir`. A process is one the run started only when it is absent
   from the record by PID and start time, `list-processes.sh` lists it with
   reason `cwd under target` and a cwd without a backslash, its cwd is outside
   every worktree registered below the target, it has no tty, and its parent is
   pid 1 or another process the run started. A `--cwd` argument alone, a
   process that existed before the run, and one under a parent that did or
   under a new parent outside the target never count: the script reports them
   as `left` and leaves them running. It sends SIGTERM to the top of each
   started tree after rechecking its PID and start time, waits about 10
   seconds, sends SIGTERM once more to each started process still running
   whose PID and start time match, even if reparented, and never sends SIGKILL.
3. Report its output with the review. Exit 0 means every started process
   exited, or the run started none; exit 3 means a started process is still
   running or unverified. Leftovers do not change the review result; cleanup
   under [Dev Servers, Watchers, and Tool Daemons](#dev-servers-watchers-and-tool-daemons)
   handles them before the worktree is removed.

Exit 1 means the teardown could not run and signaled nothing, such as when
`list-processes.sh` cannot run without bash, `/proc`, or a working `lsof`, or
when `ps` or git fails: its listing is unavailable, never empty. Report the
teardown as unverified and leave it to cleanup.

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
