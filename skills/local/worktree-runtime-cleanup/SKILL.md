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

While the run lasts, keep other work out of the target worktree. The script
reads ownership from the parent chain when it stops, so a process another
session starts in the target during the run counts as started by the run once
its parent has exited, and is stopped.

1. Before the run, record the process table in a new `mktemp -d` directory
   outside the worktree:

   ```text
   dir="$(mktemp -d)" &&
     node <this skill>/scripts/stop-run-processes.mjs record <worktree> "$dir/record.json"
   ```

   It prints one line, `sha256 <hex>`. Take the hash only from that output, as
   you captured it, and pass it unchanged to step 2. Never write it to a file
   and read it back, including a progress record, a file beside the record, or
   anything a run could write: a Codex run may be able to write such files and
   the record's directory, and the hash, not the location, is what makes an
   edited record refuse to stop anything. If you no longer have the captured
   output, skip step 2 and report the teardown as unverified. When the runs of a
   set use different `--cwd` worktrees, such as the adversarial review's
   reviewed and disposable worktrees, keep one record and its hash per worktree.
   A non-zero exit leaves no usable record: run the review, report the teardown
   as unverified, and skip step 2.
2. After the run, whether it succeeded or failed, run
   `node <this skill>/scripts/stop-run-processes.mjs stop <worktree> "$dir/record.json" --sha256 <hex>`
   with the hash `record` printed for that worktree, then remove `$dir`. A
   record whose SHA-256 differs, or a missing or malformed hash, stops nothing
   (exit 1). A process is one the run started only when it is absent from the
   record by PID and start time, every lookup gives it the same start time,
   `list-processes.sh` lists it with reason `cwd under target` and an exact cwd
   (no backslash, no ` (deleted)` suffix) that still exists and whose canonical
   real path lies at or below the target's, that cwd is outside every worktree
   registered below the target, it has no tty, and its parent is pid 1 or
   another process the run started. Paths are compared as the file system spells
   them, folding case on a case-insensitive volume, so a case alias hides
   neither the target nor a nested worktree. The script reports a process that
   existed before the run, one in a nested worktree, one with a tty, and one
   matched only by a `--cwd` argument as `left`. It leaves them running.
   A new process under the target whose parent chain cannot establish ownership
   may be the run's. Examples include a child of a pre-existing parent, a child
   of a new parent absent from the listing, and a descendant of an unverified
   parent. The script reports it as `unverified`, a leftover, and never signals
   it. A new process under the target whose cwd is not an exact
   live path, such as one with a ` (deleted)` suffix, a removed one, or an
   ambiguous one, or one first seen during the teardown or in the listing it
   takes after its signals, may be the run's: the script reports it as
   `unverified`, a leftover, and never signals it. It sends SIGTERM to the top
   of each started tree after rechecking its PID and start time, waits about 10
   seconds, sends SIGTERM once more to each started process still running whose
   PID and start time match, even if reparented, and never sends SIGKILL.
3. Report its output with the review. Its rows omit command lines. Within the
   scope of the process listing, exit 0 means every process attributed to the run
   exited or none was found, and there are no unverified rows. The listing
   checks cwd and `--cwd` evidence for the target. Exit 3 means a process is
   still running or unverified, or the final check could not run. In that
   case report teardown as unverified. Leftovers do not change the
   review result; cleanup under
   [Dev Servers, Watchers, and Tool Daemons](#dev-servers-watchers-and-tool-daemons)
   handles them before the worktree is removed.

Exit 1 means the teardown could not run and signaled nothing, such as when
`list-processes.sh` cannot run without bash, `/proc`, or a working `lsof`, when
`ps` or git fails, or when the record is unusable or differs from its SHA-256:
its listing is unavailable, never empty. Report the teardown as unverified and
leave it to cleanup.

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
2. Show the listed stacks (project, running/total, `working_dir`, reason) and
   get explicit confirmation for each project to stop.
   - When the target is a primary checkout (the one that owns `.git`) or the
     list came from `--stale`, the stacks may belong to other sessions: list
     them and let the user choose, with no pre-selected default.
   - A stack is worktree-owned when the target is a linked worktree, the list
     came from a path, and the reason is exactly `under target`. For these,
     offer an exact volume deletion preview. For other stacks, offer it only
     when the user asks to delete their volume data.
   - When a provider passes a confirmed cleanup target manifest, use it as
     the confirmation for the stacks and the volumes marked for deletion.
     Keep using that same manifest on resume, even when its stack is gone
     and only its confirmed volume removals remain.
   - For standalone cleanup, run
     `node <volume-script> preview '<project>' '<working_dir>' '<file>'`,
     where `<volume-script>` is
     [`scripts/remove-compose-volumes.mjs`](scripts/remove-compose-volumes.mjs)
     and the file is a new absolute path under private agent-work storage
     outside the worktree. Show the delete and retain lists and confirm the
     exact delete names. To offer only a subset, repeat the preview with a
     new file and the selected volume names as separate arguments.
   - For a volume-only project, offer no default. When the user explicitly
     selects it, pass `-` for `working_dir` to preview project-labeled
     volumes and confirm their names. Show that the working directory is
     unknown and omit any volume already known to be external. The project
     label establishes membership in the selected project.
   - With no listed stacks and no outstanding confirmed volume removals,
     continue with temporary-file cleanup.
3. From each confirmed stack's working directory and with its known Compose
   invocation, run `docker compose -p <project> down --remove-orphans` with
   volumes left in place. A volume-only or already stopped project needs no
   stack stop. If a required stop fails, keep the volumes and report the
   blocker.
4. When the confirmation lists volume removals and the containers are gone, run
   `node <volume-script> apply '<confirmed-file>' '<worktree>'` with the
   same provider-confirmed manifest and exact worktree path, or pass the
   standalone confirmation and its project name instead. Supply each
   argument separately and use only the confirmation the user accepted.
   On Windows, run the apply step through WSL so the confirmation file's
   ownership and private mode can be checked.
   The script checks the approved names against current project membership,
   Docker daemon and volume identity, then removes eligible names one at a
   time. For a normal stack, the bundled YAML parser checks the single local
   configuration file recorded by its containers. Volumes stay when a
   direct non-external declaration and exact name cannot be verified.
   Multiple configurations, Compose includes or extends, and ambiguous YAML
   or interpolated volume names give no deletion candidates.
   A changed lookup, newly discovered project volume or
   failed removal stops the cleanup. The script skips only names already
   verified absent, and reports each successful removal. Use the same
   approval to retry confirmed work after an interruption. A legacy
   inventory-only manifest needs a fresh preview.
5. Re-run the same `list-stacks.sh` command and report stopped, retained,
   remaining and unverified targets.

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
