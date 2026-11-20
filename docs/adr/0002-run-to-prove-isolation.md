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

- **Location.** Each run gets a detached `git worktree` at the reviewed head,
  beside the review report in the task's ignored, mode-700 records directory,
  or in a `mktemp -d` directory without a report. Only a real checkout runs a
  repository's documented checks.
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
- **Boundary.** Commands whose effects stay inside the disposable worktree run
  automatically, including lockfile-respecting dependency restoration, with
  `TMPDIR` and package-manager caches pointed inside it. Commands with effects
  outside it, such as Docker, home or global configuration, privilege, remote
  writes, shared ports or processes, or opt-in end-to-end suites, are not run
  by the reviewer: the finding is reported `unproven: needs approval` with the
  exact command, and the parent runs it only after the user approves it.
- **Enforcement.** The boundary is kept by instruction. The Codex route runs
  with `--write --cwd <disposable worktree>`; Codex 0.171.0's `workspace-write`
  sandbox protects `.git` and a linked worktree's gitdir but also allows
  `/tmp`, `$TMPDIR`, and the network that the user's Codex configuration
  enables, and the companion cannot override that per run. The subagent route
  has only the host's permission mode. Every review reports this residual
  scope.
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
  excerpt are copied beside the report before the worktree is removed. The
  review block gains a required per-finding `proof`; `change-review` and
  `change-security-review` write `not requested`. The block moves to the
  `<!-- report-summary v3 -->` delimiter, and the check accepts a v2 block only
  on a `--sha256` recheck of a report recorded before the switch.
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
- `blast-radius` in High-tier delivery (#253) links the same reference.
