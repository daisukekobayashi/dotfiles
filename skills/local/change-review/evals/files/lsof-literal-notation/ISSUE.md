# fix(skills): escape control characters in list-processes.sh output

## Summary
Escape or reject control characters in the `cwd` values that `skills/local/worktree-runtime-cleanup/scripts/list-processes.sh` prints, so a directory name cannot forge an output row.

## Background
Found in the #101 local review (round 1, security, PR #105) as a pre-existing deferred candidate.
- `list-processes.sh` prints `readlink /proc/<pid>/cwd` (or the lsof value) unescaped in its TSV output (`list_cwds` at line 53 and the row `printf` at line 137).
- A directory below the target whose name contains a newline or tab, used as the cwd of a same-user process, can produce an extra row whose `cwd` column equals the target root and whose command looks like `app-server-broker.mjs`.
- After #101, step 2 of "Brokers Started by a Codex Review" decides ownership from the `cwd` column, so this row format is the ownership input.
- Impact is limited: step 4 rechecks PID and start time before signaling, only same-user processes are listed, and the stop sends SIGTERM only. The base had the same exposure.

## Acceptance Criteria
- A cwd containing a newline, tab, or other control character is either escaped so it cannot split or add a row, or the process is omitted and reported, consistently on Linux (`/proc`) and macOS (`lsof`).
- The documented column format in `list-processes.sh` and `worktree-runtime-cleanup/SKILL.md` stays accurate.
- A test creates such a directory and shows that no forged row appears.

## Touched Areas (estimate)
- `skills/local/worktree-runtime-cleanup/scripts/list-processes.sh`
- `skills/local/worktree-runtime-cleanup/SKILL.md` (only if the output contract changes)
- a test under `tests/` or `setup/test/` for the script

## Dependencies
None.

## Parallelization
Independent of the other follow-ups from #96, #78, and #102.

