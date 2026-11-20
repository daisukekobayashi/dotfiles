# Repro Runs

A repro run backs a review finding with a run against the real code: a failing
test, a repro script, or command output that shows the wrong behavior, run in a
disposable worktree at the reviewed head. `change-adversarial-review` asks for
one for each finding where a run is possible, in delivery and when invoked
directly. Any other skill that runs commands at a reviewed head links this
reference for the same location, boundary, bounds, evidence, and cleanup.
Everything here applies to GitHub and Azure DevOps delivery alike.

## Roles

- **Launcher:** the session that starts the reviewer under the review skill's
  Run the Reviewer: the coordinator in delivery, the invoking session when the
  skill is called directly. Only the launcher creates and removes disposable
  worktrees.
- **Reviewer:** runs repros only inside the disposable worktree the launcher
  gives it. It never runs `git worktree` or any command that writes refs.
- **Parent:** the caller that acts on the findings, the same session as the
  launcher. It reruns each proving command before acting on the finding under
  [Parent rerun](#parent-rerun).

## Disposable worktree

Create one for the reviewer before it starts, and one for each parent rerun:

1. Choose the path. With `--report <path>`, use the report path without its
   `.md` suffix plus `.repro` for the reviewer, or `.rerun-<finding ID>` for a
   rerun, in the report's mode-700 directory, which lies in the ignored records
   root under [Report Handoff](report-handoff.md#report-path). Without
   `--report`, create a new directory with `mktemp -d` outside the repository
   and use `<that directory>/wt`.
2. Run `git -C <reviewed worktree> worktree add --detach <path> <reviewed head SHA>`
   and record the path and the head. Never create a branch. Uncommitted
   changes in the reviewed worktree are not part of the run; the review covers
   the committed head.
3. When the target has no git checkout or no commit for the reviewed head,
   create none and report every finding `unproven: no checkout`.

Run every command in it with `TMPDIR=<path>/.repro/tmp` and package-manager
caches under `<path>/.repro/cache`, such as `npm_config_cache`, so that the
allowed effects stay inside the worktree.

### Remove

After the run ends, whether it completed, failed, or reached a bound:

1. For a Codex run, follow `../../worktree-runtime-cleanup/SKILL.md`
   "Brokers Started by a Codex Review" with the disposable worktree as its
   target worktree.
2. Copy the evidence under [Evidence](#evidence).
3. Check that `git worktree list --porcelain` lists exactly the recorded path.
   Report a `HEAD` that is no longer the recorded head as a boundary breach.
4. Run `git -C <reviewed worktree> worktree remove --force <path>`, then
   remove the `mktemp -d` directory when step 1 of Disposable worktree made one.

The user's request for the review authorizes the launcher to remove, without
confirmation, only a disposable worktree it created for that run. Every other
removal keeps its confirmation. When the recorded path is not listed, remove
nothing and report it.

## Boundary

A reviewer runs a command automatically only when its effects stay inside the
disposable worktree. Lockfile-respecting dependency restoration into it, such
as `npm --prefix setup ci`, is allowed.

It does not run a command with effects outside the worktree, such as Docker
images, containers, or volumes; writes to the home directory, global
configuration, or the system; privilege such as `sudo` or `SYS_PTRACE`; remote
writes; shared ports or processes; or an opt-in end-to-end suite. It names the
exact command and reports the finding `unproven: needs approval`. The parent
presents that command to the user and runs it only after the user approves it.

It never edits the reviewed worktree, its branch, any ref, or the shared
`.git`: no commit, checkout, branch, stash, or worktree command.

The boundary is kept by instruction. The Codex `workspace-write` sandbox lets
a run write the worktree, `/tmp`, and `$TMPDIR`, protects `.git` and the
worktree's gitdir, and uses the network as the user's Codex configuration
sets; the subagent route has only the host's permission mode. Every review
states this residual scope in its Coverage and Residual Risk.

## Bounds

Runs follow the rules of
[Shared bounds](optional-workflows.md#shared-bounds), with these numbers. They
are part of the reviewer, not an optional workflow, and have no registry entry.

- Each proving command: 10 minutes.
- All repro runs of one review: 30 minutes, including creating the disposable
  worktree and restoring dependencies.
- One retry per finding, after fixing the repro itself.
- At most 5 findings proven by a run per review; report later findings
  `unproven: cap reached`.
- Each parent rerun: 10 minutes per command, outside the review's total.
- Each output excerpt: at most 50 lines and 8 KB. The finding cap and the
  excerpts bound the tokens a run adds.

Run each command under [Foreground Checks](../SKILL.md#foreground-checks).
Runs belong to the review's local round and never add one. A run that reaches
its bound is `stopped: time bound` and is never proof. A limit or opt-out in the
user's request takes precedence: a shorter bound applies as given, and an
opt-out makes every finding `unproven: opted out`.

## Proof

Each finding has one proof status:

- `ran`: its command ran in the disposable worktree within its bound, and the
  output shows the failure;
- `unproven: <reason>`: no run shows it, such as a design or instruction flaw,
  a docs-only change, an unreachable environment, `no checkout`,
  `cap reached`, `opted out`, or `needs approval` with the exact command;
- `stopped: time bound`: the run reached its bound;
- `failed: <reason>`: the repro itself did not run, such as on a setup error.

Only `ran` counts as proof. Reviewers that do not run repros, `change-review`
and `change-security-review`, write `not requested`.

## Evidence

The reviewer writes each finding's repro files under `.repro/<finding ID>/`
in its worktree, using the final finding IDs, with `command` (the exact
command and its directory relative to the worktree root), `exit-status`, and
`output` (the bounded excerpt). Its finding gives the same command, the output
excerpt, and the output the intent requires.

Before removal, the launcher copies each `.repro/<finding ID>/` directory to
`<report path without .md>.evidence/<finding ID>/`, creating the evidence
directory with `mkdir -m 700`. Without `--report`, nothing is retained beyond
the finding text in the Output.

## Parent rerun

Before acting on a finding whose proof is `ran`, such as fixing it, recording a
disposition, or treating `Do not ship` as a blocker, the parent:

1. creates a fresh disposable worktree at the reviewed head;
2. copies the finding's retained repro files into it at their relative paths;
3. runs the recorded command under the environment, boundary, and bounds above;
4. compares the exit status and output with the evidence: `reproduced`,
   `not reproduced`, `stopped: time bound`, or `failed: <reason>`;
5. removes the worktree under [Remove](#remove).

In delivery, record the result with the finding's disposition in the progress
record; when called directly, report it with the findings. A finding that is
not reproduced is assessed as `unproven`. For `unproven: needs approval`, ask
the user about the exact command and, once approved, run it as a rerun. A
focused follow-up reruns the retained command on the new head to confirm a fix.
