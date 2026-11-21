---
status: accepted
---

# Stop the process trees a Codex review run started, by ownership

[日本語](0003-stop-process-trees-a-review-run-started.ja.md)

## Context

The Codex-routed local reviews (`change-review`, `change-adversarial-review`,
`change-security-review`) run `codex-companion.mjs task` for a target
worktree. Since [#99](https://github.com/daisukekobayashi/dotfiles/pull/99),
the review stopped the companion's `app-server-broker.mjs` tree that the run
started, by comparing two `list-processes.sh` listings taken around the run.
The rule selected processes running `app-server-broker.mjs` whose cwd equaled
the target root, together with their descendants at the second listing.

In the #249 delivery, sandboxed command trees such as
`codex-linux-sandbox -> node -> git hash-object --stdin` stayed alive after
the run, blocked on input, and surfaced only in the worktree cleanup manifest
([#262](https://github.com/daisukekobayashi/dotfiles/issues/262)). By the time
the second listing is taken, such a tree is no longer under a broker: the
companion falls back to a direct `codex app-server` child when the shared
broker is busy and sends SIGTERM only to that app-server at exit, and a
command whose shell or app-server exited first is reparented. The
broker-only rule could not see these trees. Codex's wrapper names also differ
by platform; on macOS the Seatbelt wrapper is not expected to stay visible as
a parent process.

On this kind of host, other agent sessions run commands in sibling or even the
same worktrees, and an agent's tool shell has no tty. The review stops
processes without asking, so the rule that decides what the run started is the
boundary that keeps it from stopping another session's work.

## Decision

One rule covers every process tree a review run started, with brokers as one
case of it, and a script implements it:
`skills/local/worktree-runtime-cleanup/scripts/stop-run-processes.mjs`, which
the section "Process Trees Started by a Codex Review" of
`worktree-runtime-cleanup` calls and the review skills and `repro-runs.md`
link.

- **Record and stop.** Before the run, or before a set of runs started together
  for one worktree, `record` writes every process's PID and start time to a new
  mode-0600 file. After the run, `stop` lists the target with
  `list-processes.sh` between two process tables.
- **A record bound by its hash.** The record decides what existed before the
  run, and a Codex `workspace-write` run may be able to write where it lives.
  `record` prints the SHA-256 of what it wrote; the launcher takes that value
  only from the output it captured, never from a file it wrote and read back,
  and passes it to `stop` with `--sha256`. `stop` checks with `lstat` that the
  record is a regular file, reads it once without blocking, and signals
  nothing unless that read has the same hash; a missing hash signals nothing
  too, and a launcher that lost it does not run `stop`. A
  set whose runs use different `--cwd` worktrees keeps one record and hash per
  worktree. `stop` also refuses a record that is malformed (PIDs and start
  times not exactly as `ps` prints them), for another target, missing pid 1
  or the process that wrote it, or whose pid 1 start time differs from the
  current one. The record still lies outside the target, in a mode-700
  directory, as a mode-0600 regular file.
- **Ownership.** A process is one the run started only when it is absent from
  the record by PID and start time, both tables and the listing give it the
  same start time (so its cwd and start time belong to one process), it is
  listed with reason `cwd under target` and an exact cwd at or below the
  target (normalized, with no backslash and no ` (deleted)` suffix), it lies
  outside every worktree registered below the target, it has no tty, and it
  has pid 1 or 0, or another process the run started, as its parent.
  Ownership comes from timing and location, never from process names. Paths
  are compared by canonical real path as the file system spells them, folding
  case on a case-insensitive volume, and a cwd counts only while it still
  exists. A new process under the target whose cwd is not an exact live path
  (a Linux ` (deleted)` suffix, a cwd macOS still names after its removal, or
  an ambiguous one), one first seen during the teardown, and one a listing
  after the signals first shows, such as a child forked meanwhile, may be the
  run's: each is reported `unverified`, counts as a leftover, and is never
  signaled.
- **Ancestry over the whole table.** A process under a parent that existed
  before the run, wherever that parent's cwd is, or under a new parent outside
  the target, is reported `left` and never signaled. Only pid 1 and 0 end the
  chain without counting as pre-existing, because the run's leftovers are
  orphans reparented there.
- **Signals.** SIGTERM to the top of each started tree after rechecking its
  start time, then, after about 10 seconds, one more SIGTERM to each started
  process still running with the same start time, even reparented. Never
  SIGKILL, and never a process outside the started trees. Stops need no
  confirmation, since the run owns what it started.
- **Failure.** When `list-processes.sh`, `ps`, or git cannot run or runs past
  its time bound, or the record is unusable, the script exits 1 and signals
  nothing; the teardown is reported unverified and left to worktree cleanup.
  Leftovers never change the review result. The report carries no command
  lines, which may hold another session's secrets.
- **Operating assumption.** Ownership is read from the parent chain at `stop`;
  the chain of a process whose parent has exited is lost. While a review run
  lasts, no other work runs in the target worktree. A process another session
  starts there during the run counts as started by the run once its parent
  has exited, and is stopped. The user accepted this risk in #262 rather than
  tracking lineage during the run.

## Considered Options

- **Match sandbox wrapper names** such as `codex-linux-sandbox`. It is the
  smallest change, but it tracks Codex's internal names, misses macOS, and
  misses trees whose wrapper already exited.
- **Ancestry over the listed processes only.** It needs a smaller record, but
  a command another session runs in the target during the run has an owner
  outside the listing and would be stopped.
- **Treat known subreapers, such as `systemd --user`, as pid 1.** It covers
  more Linux hosts, but it decides ownership by process names again.
- **Keep the record where no run can write.** Round 1 and 2 of #262 placed
  the record outside the target, `/tmp`, `$TMPDIR`, and then the
  `writable_roots` read from every Codex configuration file and profile. Each
  review found another way the effective sandbox policy could differ from what
  the script read (configuration layers, profiles, runtime overrides), so
  the protection rested on a model of Codex's configuration. A hash the
  launcher keeps does not depend on where a run can write.
- **Keep the rules as prose the review agent follows.** The selection, recheck,
  and escaping rules are mechanical, their prose needed repeated fixes, and
  only a run of the stop can show a tree being stopped.
- **A Bash script beside `list-processes.sh`.** It keeps one language in the
  skill's scripts, but the ancestry walk and record handling need maps that
  Bash 3.2 lacks; node is present wherever the Codex route runs, since the
  companion is node.

## Consequences

- A review stops, without asking, every tree its run started under the target,
  not only brokers.
- On a host where orphans are reparented to a pre-existing subreaper rather
  than pid 1, the run's leftovers are reported `left` and reach worktree
  cleanup, as before.
- A process another session starts in the target during the run is left
  while its parent lives; once that parent exits, such as a background command
  whose shell ended or a detached daemon, it is stopped. Callers keep other
  work out of the target during a review run.
- Worktree cleanup (`github-worktree-cleanup`, `azure-devops-worktree-cleanup`)
  keeps its own confirmed stop; it may adopt the script later.
