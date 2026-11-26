---
name: delivery-common
description: Shared worker dialogue, verification, local review procedure, risk tier, and completion policy for GitHub issue and Azure DevOps Work Item delivery. Read when a delivery workflow dispatches workers through its start skill, has workers draft the shared understanding and design preflight for the coordinator to ask, hands the settled scope to preflight and implementation, verifies implementation or fixes and classifies the results, sets a change's risk tier, requires normal, adversarial, and security reviews, selects focused follow-up of a committed implementation, decides whether local reviews repeat or advance, keeps a progress record, resumes a delivery, checks the published head before advancing, prepares a merge confirmation, delegates publication, hosted review, and cleanup calls to agents, stops at a bound or a missing prerequisite, runs or reports an optional workflow, explains a claimed performance number before reporting it, handles an agent that went idle waiting on a background job, or reports completion and follow-up candidates. Also states the delegated authorization rule that the PR, review request, and delivery skills link.
---

# Delivery Common

Use [Worker Dialogue](references/worker-dialogue.md) for worker dispatch through
the start skill and for each target's shared understanding, design preflight,
and implementation: workers draft, and the coordinator asks the user. Use
[Project verification](references/worker-dialogue.md#project-verification) and
[Classified verification](references/report-handoff.md#classified-verification)
to verify implementation and fixes and hand off the results. Use
[Phase Delegation](references/phase-delegation.md) for every component-skill
call after implementation: publication, the hosted review cycle, the cleanup
preview, and cleanup. Use
[Local Review](references/local-review.md) when a delivery workflow
reaches its local reviews or selects focused follow-up, and apply its Assess
findings to local and hosted findings. Use
[Repro Runs](references/repro-runs.md) when a review backs its findings with
runs: the disposable worktree, its boundary and bounds, the evidence, and the
parent's rerun. Use [Risk Tier](references/risk-tier.md)
to set the tier before preflight and on each reviewed head, and to select the
tier's review procedure, including the security reviewer and the recommended
human review. Local Review also sets local review
escalation, advancement, and round limits. Use
[Delivery Completion](references/completion.md) for the progress record,
resume, the decision summary shown before publication and at merge, the
published-head check and advance after publication, the merge confirmation,
bounds, the final report and `Complete` rule, and follow-up candidates. Use
[Optional Workflows](references/optional-workflows.md) whenever a phase reaches
an optional workflow: when it runs, how it is reported as not run, and its
shared bounds. Apply
[Missing Prerequisites](#missing-prerequisites) whenever a phase lacks what it
needs, and [Foreground Checks](#foreground-checks) to every delegated worker
and reviewer and to each result they return. Apply
[Performance Claims](#performance-claims) to every performance number a
delivery claims. The coordinator reads these references by
[Phase sections](#phase-sections).

The calling workflow owns implementation, assessment decisions, how its hosted
review runs, publication, and approvals;
[Delegated Authorization](#delegated-authorization) says how those approvals
pass to the skills it calls. Where shared text names the calling workflow's
additions, the calling workflow lists its provider-specific items next to its
link. Return the completed results, review scope, reviewed snapshot, and tier
to that caller.

## Phase sections

When a phase starts, the coordinator reads the reference sections listed for
it below that are not already in its context, each from its heading through
the line before the next heading of the same or higher level. A section that a
listed section links to by its heading anchor joins the list. Read Delivery
Completion's Bounds whenever a phase stops or stalls.

When entering either phase below, run the corresponding command if its
reference reads are still due in this context. Resolve `<script>` from this
skill's directory as [`read-phase-sections.mjs`](scripts/read-phase-sections.mjs).

```text
node "<script>" -- "Prepare and dispatch"
node "<script>" -- "Shared understanding and preflight"
```

For preflight, append `--after-prepare` when the complete preparation output
is still in context and the skill files are unchanged since that read. The
flag skips sections covered by that output.

The helper starts with the row's entries, using the full reference for `all`.
It follows heading links within `references/` until all their targets are
covered.
If the command is unavailable or fails, locate and read every required
heading directly before continuing.

| Phase | Sections |
| --- | --- |
| Prepare and dispatch | Worker Dialogue: Assign the worker; Delivery Completion: Progress record |
| Shared understanding and preflight | Worker Dialogue: Draft and ask, Worker defaults; Risk Tier: Set and update the tier, Rate the dimensions, Assign the tier, Sensitive paths, Tier procedure; Optional Workflows: all |
| Implementation | Worker Dialogue: Preflight and implementation, Worker defaults; Optional Workflows: all |
| Local reviews and focused follow-up | Local Review: all; Repro Runs: all; Risk Tier: Set and update the tier, Rate the dimensions, Assign the tier, Sensitive paths, Select the security review, Tier procedure; Optional Workflows: all |
| Publication | Phase Delegation: all; Delivery Completion: Decision summary, Before publication, After publication; Local Review (when assessing hosted findings): Triage classes, Assess findings, Repeat and advance; Risk Tier: Select the security review, Tier procedure, Recommend human review |
| Merge | Phase Delegation: Choose the agent, Brief the agent, Return to the coordinator, Report path; Delivery Completion: Decision summary, After publication, Merge confirmation; Risk Tier: Recommend human review |
| Report and cleanup | Phase Delegation: all; Delivery Completion: Merge confirmation, Report and complete, Follow-up candidates; Optional Workflows: Run or report, Record and report |
| Resume, including after context compaction | Delivery Completion: Progress record, Resume, Merge confirmation; Phase Delegation: Resume a delegated phase; Risk Tier: Select the security review; Optional Workflows: Record and report; then the sections of the phase the task's state file names |

## Delegated Authorization

A delegated call carries the user's actual request, the exact target, and the
existing approvals. The caller forwards them to each skill it calls; the called
skill acts only within them and, before an action they do not cover, prepares
the concrete result and asks for the missing approval. A skill reference,
automatic selection, or automatic discovery authorizes nothing. Reuse approval
already given for the same scope instead of asking again. Each called skill
keeps its own approval model: what an explicit request approves and what still
needs asking.

The PR, review request, and Codex review cycle skills and the delivery skills
of both providers link this section instead of restating it.

## Missing Prerequisites

A missing prerequisite, such as a component skill, a required reviewer, or a
tool a step runs, stops the phase that needs it for the affected targets.
Report it as a blocker, naming what is missing and, for a skill, the profile
that installs it, such as `base,github`. Never install it, substitute another
skill or an informal check for it, or skip the phase. Independent work that
does not depend on it continues under Delivery Completion's
[Bounds](references/completion.md#bounds). The only exception is an optional
workflow: one that is not installed, not triggered, or unavailable is reported
as not run and the phase continues, under
[Optional Workflows](references/optional-workflows.md). The delivery skills of
both providers and [Local Review](references/local-review.md) link this section
instead of restating it.

## Foreground Checks

A delegated worker or reviewer runs every command whose result it awaits,
including tests, builds, watchers, and review tool runs, in the foreground with
a time bound, and never ends its turn waiting on a background job. It ends a
turn only with a completed result, a question, or a blocker; a command that
reaches its time bound is a failed check to report.

The coordinator acts on each agent's turn-end notice when it arrives instead of
deferring it to a later check. An idle agent whose last message says it is
waiting has returned no result: check whether the job it names is running, then
resume the agent once, telling it to finish the command in the foreground with a
time bound and return the result. If it ends its turn waiting again, or the job
is hung, report the target as `Blocked` under Delivery Completion's
[Bounds](references/completion.md#bounds). Where the host gives no notice when
an agent's turn ends, report that limitation and do not end your own turn while
an agent is outstanding.

The start skills' worker rules, [Worker Dialogue](references/worker-dialogue.md),
and [Local Review](references/local-review.md) link this section instead of
restating it.

## Performance Claims

A claimed number is a measured comparison, before and after or between
options, of time (wall time, latency, throughput, or a percentage or factor
faster or slower) or of resource consumption (memory, CPU, size, or token or
context consumption). A test count or a pass or fail check result is never
one. It is claimed when it appears in the delivery's own output: a worker
report or summary, a commit message, the PR title or body, the decision
summary or final report, or text the task diff adds.

Explain a claimed number before reporting it: keep the run count, the spread,
and the limiter with it, and rule out with evidence what else it could be
measuring. `explain-the-number` gives these rules in full when installed;
it is never a prerequisite. A number that cannot be explained stays where it
was written, labeled `inconclusive` with each unchecked item named as a gap;
it never blocks the delivery. A worker records its claim's explanation in its
`Verification:` rows under
[Classified verification](references/report-handoff.md#classified-verification).
The decision summary and the final report show each claim with its
explanation or gaps, and the latest `benchmark-checklist` status.

[Performance claims](references/local-review.md#performance-claims) in Local
Review runs `benchmark-checklist` on the claims at the pinned worker head as an
optional workflow. A claim first written after that step, such as in the PR
body, gets only this rule: cite that head's evidence or label it
`inconclusive`; it launches no run. A delivery with no claimed number never
runs it. [Worker Dialogue](references/worker-dialogue.md) and Local Review link
this section instead of restating it.

## Shared Scripts

[`scripts/check-branch-name.mjs`](scripts/check-branch-name.mjs) is the shared
**safe branch name** check. The start, delivery, PR, and cleanup skills of every
provider, including Beads, run it from their own step; its header gives the
usage and exit codes.

[`scripts/check-push-target.mjs`](scripts/check-push-target.mjs) is the shared
**push target rule** check. The PR publish skills of both providers, and
`github-pr-create` and `github-pr-codex-review-cycle`, run it to resolve the push
remote and to check the upstream before and after the push; its header gives the
usage and exit codes.

[`scripts/check-cleanup-targets.mjs`](scripts/check-cleanup-targets.mjs) is the
shared **remote branch deletion check** and **cleanup target manifest**. The
worktree cleanup skills of both providers run it to decide whether to delete the
remote branch, to prove the local branch merged from the PR's merge evidence, to
build the targets the user confirms or a Caller preview, and to compare them
right before any removal and again after the confirmed runtime stop; its header
gives the usage and exit codes.

[`scripts/check-report-handoff.mjs`](scripts/check-report-handoff.mjs) is the
shared **report handoff check**. Delivery coordinators and Codex-routed review
callers run it on each report under
[Report Handoff](references/report-handoff.md#check-a-handoff); its header
gives the usage, checks, and exit codes.

[`scripts/write-phase-input-key.mjs`](scripts/write-phase-input-key.mjs)
captures the exact pre-checkpoint inputs for design preflight and verification
under [Optional Workflows](references/optional-workflows.md#keys).
