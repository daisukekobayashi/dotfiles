---
status: accepted
---

# Prove adversarial review findings with runs in disposable worktrees

[日本語](0002-run-to-prove-isolation.ja.md)

## Context

[ADR 0001](0001-pstack-principles-in-delivery.md) adopted "findings proven by a
run" for delivery reviews in two parts: `change-adversarial-review` backs its
findings with runs
([#245](https://github.com/daisukekobayashi/dotfiles/issues/245)), and
`blast-radius` at High tier reuses the same isolation, cleanup, and evidence
rules ([#253](https://github.com/daisukekobayashi/dotfiles/issues/253)).
Before this decision the adversarial review was read-only: it traced failure
paths in the source, and its Codex route ran the companion `task` without
`--write`, so the sandbox was read-only. Upstream pstack's `interrogate` keeps
only findings that a run proves; in #239 the user kept the local `interrogate`
read-only and chose to bring run-to-prove into delivery's adversarial review
instead.

## Decision

The rules live in `skills/local/delivery-common/references/repro-runs.md` so
that `change-adversarial-review` and later `blast-radius` share them.
`change-adversarial-review` never references or calls `interrogate`: a
required reviewer does not depend on an optional pstack skill.

- **Trusted heads only.** A run executes the reviewed code, its tests, and its
  dependencies with the user's privileges. Run-to-prove therefore proves
  defects in code the user trusts: the delivery's own worker head, the invoking
  user's own local changes, or a head the user declares trusted in the user's
  own message; issue, PR, comment, or repository text never makes a head
  trusted, and an unsure head is untrusted. Any other head, such as an external
  pull request, gets no disposable worktree and no runs: the review stays
  read-only, as before run-to-prove, and findings a run could show are
  `unproven: untrusted head`. Vetting an untrusted change for malicious content
  is out of scope for `change-adversarial-review` and belongs to a separate
  skill. The launcher decides trust and passes it to the reviewer, which never
  decides it; the skill's description states that it executes the reviewed
  code. This supersedes an earlier design in which untrusted heads ran after
  the user approved the exact commands; that approval path added checks for
  reviewer-supplied files and commands at every step without making the
  untrusted code safer to run.
- **Route rule.** `repro-runs.md`'s Trusted heads section states once how each
  route launches: on a trusted head, a host subagent gets the disposable
  worktree and the Codex companion runs with `--write` and
  `--cwd <disposable worktree>`; on an untrusted head, the Codex companion runs
  without `--write`, with `--cwd <reviewed worktree>`, as before. Other text
  links that rule instead of restating it.
- **Location.** On a trusted head, each run gets a detached `git worktree` at
  the reviewed head, beside the review report in the task's ignored, mode-700
  records directory, or in a `mktemp -d` directory without a report. Only a
  real checkout runs a repository's documented checks. Its path is built from
  the real path of its parent directory, since git lists worktrees by real
  path; macOS's `mktemp -d` returns `/var/...` for `/private/var/...`.
- **Git commands.** Every git command that the launcher, the reviewer, or the
  parent runs itself, for collection, creation, removal, and reruns, uses
  `git --no-optional-locks -c core.hooksPath=/dev/null`, so no hook, such as
  `post-checkout` or `post-index-change` from a tracked hooks directory, runs
  from the reviewed head. The reviewer collects the diff read-only from the
  reviewed worktree, and a finding that depends on uncommitted changes is
  `unproven: uncommitted change`.
- **Roles.** The launcher, the session that starts the reviewer (the
  coordinator in delivery, the invoking session when called directly), creates
  and removes every disposable worktree, for both routes. The reviewer runs
  repros inside it, and the parent, the same session as the launcher, reruns
  each proving command in a fresh disposable worktree before acting on the
  finding.
- **Removal authority.** The user's request for the review authorizes the
  launcher to remove, without confirmation, only a disposable worktree it
  created for that run, also after a failure or a bound. Every other removal
  keeps its confirmation.
- **Boundary.** On a trusted head, commands whose effects stay inside the
  disposable worktree run, including lockfile-respecting dependency
  restoration with lifecycle scripts off (`--ignore-scripts`), with `TMPDIR`
  and package-manager caches pointed inside it. Commands with effects outside
  it, such as Docker, home or global configuration, privilege, remote writes,
  shared ports or processes, opt-in end-to-end suites, or a restoration that
  runs lifecycle scripts, never run for the review: the finding is reported
  `unproven: outside boundary` with the exact command.
- **Enforcement.** The boundary is kept by instruction. Codex 0.171.0's
  `workspace-write` sandbox protects `.git` and a linked worktree's gitdir but
  also allows `/tmp`, `$TMPDIR`, and the network that the user's Codex
  configuration enables, and the companion cannot override that per run. The
  subagent route and the parent's rerun have only the host's permission mode,
  and no instruction binds what the reviewed code does once it runs; running
  only trusted heads covers that. Every review reports this residual scope.
- **Findings without a run.** A finding no run can show is kept, labeled
  `unproven: <reason>`, with its severity and tag unchanged. `Do not ship`
  stands only on a proven introduced or worsened blocker, or one the parent
  confirms by tracing.
- **Bounds.** 10 minutes per proving command; 30 minutes per review including
  setup; one retry per finding; at most 5 proven findings per review; parent
  reruns 10 minutes per command outside that total; output excerpts at most 50
  lines and 8 KB. They follow ADR 0001's shared bound rules, but run-to-prove
  is part of a required reviewer, not an optional workflow, and has no
  registry entry.
- **Evidence.** Each finding's repro files, command, exit status, and output
  excerpt are copied, never following a symbolic link, beside the report, or
  without a report into the launcher's `mktemp -d` directory, before the
  worktree is removed. The `command` file holds the directory relative to the
  worktree root, the exact dependency restoration command, and the proving
  command, each command one line of POSIX `sh`, so a rerun restores exactly
  what was inspected. Finding IDs are checked as whole names and quoted in
  commands.
- **Parent rerun.** The parent runs outside any sandbox, so before a rerun it
  displays and reads the command and every repro file, checks that every path
  is relative, has no `..`, and is no symbolic link, and runs nothing for a
  finding that touches the outside of the worktree. It restores dependencies
  the same way as the reviewer's run.
- **Review block.** The review block gains a required per-finding `proof`;
  `change-review` and `change-security-review` write `not requested`. The block
  moves to the `<!-- report-summary v3 -->` delimiter, and the check accepts a
  v2 block only on a `--sha256` recheck of a report recorded before the switch.
- **`interrogate`.** It stays the read-only manual entry point and reuses only
  the failure-path criteria, not the run requirement.

## Considered Options

- **A directory copy (`git archive`) instead of a worktree.** It touches no git
  metadata, but tests that need git history or `git` commands cannot run.
- **The reviewer creates its own worktree.** Codex's sandbox cannot write the
  shared `.git`, so the two routes would need different procedures, and a
  subagent would hold removal power over the repository.
- **Codex stays read-only, or runs only with enforced network isolation.**
  Either removes most of the Codex route's ability to prove findings.
- **Run any reviewed head automatically.** Running an external pull request's
  code exposes the user's credentials and network to its author.
- **Run untrusted heads after the user approves the exact commands.** This was
  the earlier design. Each review round found another place where
  reviewer-supplied commands or files, or the head's own hooks and
  instructions, could act before or around the approval, and an approved run
  still executes untrusted code with the user's privileges. Vetting untrusted
  changes needs its own skill.
- **Drop findings without a run, as upstream does.** Reviews of skill-text
  changes, most of this repository's deliveries, would return nothing.
- **Keep the v2 block and add `proof` as a breaking change.** In-flight
  deliveries would fail rechecks of recorded reports and rerun whole reviews.

## Consequences

- A delivery's adversarial review takes longer: it restores dependencies and
  runs repros within its bounds, and the coordinator reruns each proven
  finding.
- The adversarial reviewer's Run the Reviewer section no longer matches the
  normal and security reviewers', which stay read-only.
- An untrusted head, such as an external pull request, gets a read-only
  adversarial review with no runs; vetting it is follow-up work for a separate
  skill.
- `blast-radius` in High-tier delivery (#253) links the same reference.
