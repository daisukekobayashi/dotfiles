# Delivery Completion

The calling workflow applies this policy to each delivery task, its issue or
Work Item, from the progress record through the final report. Where a rule says
"plus the calling workflow's additions", the calling workflow lists its
provider-specific items next to its link to this reference.

## Progress record

Before writing progress records, classify them as temporary and choose ignored
agent-work storage or `/tmp`. Keep a separate record per task: task URL and
scope, the shared understanding result and the latest worker drafts, worktree,
branch, base ref and SHA, current phase, accepted design decisions, risk tier
with its reasons and head, verification, the local review record under
[Local Review](local-review.md), PR and published head, finding dispositions,
the self-closure list under Local Review, follow-up candidates, blockers, and
next action, plus the calling workflow's additions. Report the resume path.
Keep durable definitions and decisions in the repository's normal docs.

## Decision summary

Show the user this summary before publication and in the merge confirmation,
keep it in the progress record, and keep it out of the PR body:

- the tier at the current head, the heaviest tier recorded in this delivery
  when it differs, and their main reasons;
- the recommended human review from the column
  [Risk Tier](risk-tier.md#tier-procedure) applies;
- any `change-security-review` deferred candidates on sensitive paths and
  user-accepted security findings under
  [Risk Tier](risk-tier.md#select-the-security-review);
- any `change-security-review` findings their reviewer tagged `pre-existing`
  and labelled Critical or High;
- the self-closure list under [Local Review](local-review.md), or `none` when
  it is empty.

## Before publication

Coordinate publication sequentially across targets. Workers hand off their
exact branch and worktree, task and spec, recorded base, verification, risk
tier, and local review evidence.

Before publication, show the user the [Decision summary](#decision-summary).

## Merge confirmation

Check the current PR head, base, required checks, required human approvals,
mergeability, and remaining review threads, plus the calling workflow's
additions. Pending, failed, or inaccessible required evidence leaves the task
waiting or blocked. Approval for one head does not cover an intervening
material change; reassess before proceeding.

Present the PR URL, task, reviewed and published head, base, checks, review
outcome including any security review, the [Decision summary](#decision-summary),
and the proposed repository-supported merge method, plus the calling workflow's
additions. Request confirmation to merge that
specific PR.

Combine the merge and cleanup confirmations only when every tier recorded in
this delivery, including the one for the merge head, is Low under
[Risk Tier](risk-tier.md#tier-procedure). Before presenting the merge, have the
calling workflow's cleanup skill preview the exact cleanup targets, and request
one confirmation for that PR merge and those targets. That confirmation approves
cleanup only when the user gives it in their own message, explicitly accepts the
cleanup targets, and, after the merge, every cleanup safety check passes and the
targets match the preview as the cleanup skill's Caller preview defines. A reply
that approves the merge without explicitly accepting the cleanup targets
approves the merge only; any other reply approves neither. A
changed head, a resume, or any other target difference requires a separate
cleanup confirmation. At every other tier, cleanup keeps its own confirmation after the
merge.

After approval, recheck the target and merge within that approval, keeping
checks and policies in force and the source branch in place. If the user merges
separately, verify that outcome instead. Confirm the actual merged state and
merge commit before cleanup; a queued or scheduled merge remains pending.

## Bounds

Advance as soon as the completion criteria are met. If progress repeatedly
stalls, a review times out, a required check fails, or a material human
decision is needed, preserve progress and report the next action, plus the
calling workflow's additions.

Keep the user informed while waiting. Stop further publication targets after a
publication failure; independent local work may continue when it does not
depend on the blocker. A wait or an unresolved approval stays open; report it
as such rather than as a successful completion.

## Report and complete

Report each task separately with task and PR links, branch and worktree or
their confirmed removal, verification and limitations, reviewed and published
head and review rounds, policy and merge state, task state, and the exact
pending decision or action. Use the states `In progress`, `Waiting for user`,
`Waiting for review/CI`, `Blocked`, `Merged; cleanup pending`, and `Complete`,
plus the calling workflow's additions.

Mark `Complete` only after acceptance criteria, current verification and
reviews, actual merge, task closure, and confirmed local cleanup have all been
verified; the calling workflow defines task closure. Overall completion
requires every requested task to meet that condition.

## Follow-up candidates

Before cleanup, keep this task's follow-up candidates in a record outside the
worktree being removed; move or copy them first when needed.

After the per-task reports, including a stopping report, list the follow-up
candidates from all targets with duplicates merged. Give each its source task
or PR and review round or thread, evidence, the creation criterion it meets or
`none`, and a create-or-drop recommendation. Recommend create only when the
candidate meets at least one criterion:

- it reproduces under supported use of the changed behavior;
- it is an exploitable security vulnerability;
- the user asked for it.

Otherwise recommend drop, including theoretical edge cases and tests that only
pin current behavior. Ask which to create, and pass only approved candidates
with their evidence and source links to the calling workflow's create skill.
Pending candidates do not block `Complete`; report them as a separate open list.
