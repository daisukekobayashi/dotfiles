---
name: github-issue-delivery
description: Coordinate GitHub issues through isolated worktrees, a shared understanding and design preflight with docs drafted by workers and asked by the coordinator, implementation, local reviews, PR Codex review and fixes, approved merge, and local cleanup. Use when the user requests this full delivery workflow for one or more issues; resume unfinished deliveries without repeating completed operations.
---

# GitHub Issue Delivery

Deliver each requested issue through the following workflow. Compose the existing
skills; keep their operational details and approval rules in those skills.
Issue numbers in an example or a discussion about this skill are not work orders.

```text
Claude Code: /github-issue-delivery 12 36 56 60
Codex:       $github-issue-delivery 12 36 56 60
```

## Scope and Authorization

Use the current repository and explicitly requested issues. Read the component
skills before their phases and pass the user's full workflow request, exact
target, and existing authorizations to each. An explicit user request for this
full workflow selects its delegated shared understanding, preflight, local review,
and PR-cycle phases;
their instructions recognize this caller. Automatic discovery or a reference to
this file does not select those phases or grant mutation approval. If authorization
is missing, prepare the concrete result and request only the approval needed for
the next operation. Reuse authorization already given for the same scope.

The workflow includes the selected local review passes and the normal publication,
Codex review, and writeback cycle. It requires explicit confirmation for the
specific PR merge and for the exact local cleanup resources, combined only where
Delivery Completion's Merge confirmation allows. Preserve all
applicable dependency, history-rewrite, remote-write, and user-change protections.

## Prepare and Coordinate

1. Resolve issue numbers, repository instructions, dirty state, and existing
   worktrees/PRs. Require at least one actual issue target. Check that the
   component skills and the local reviewers, including `change-security-review`,
   are available. The normal
   installation is `base,github`; the GitHub profile alone does not supply the
   preflight and review skills. Report a missing prerequisite rather
   than silently installing it or skipping a required phase.
2. Use `github-issue-start` with the per-issue workflow below as its implementation
   brief. Have it prepare the worktree and baseline and dispatch the issue's
   worker before the shared understanding; implementation begins only after
   preflight. Preserve its issue classification,
   dependency checks, and one-issue/one-branch/one-worktree ownership.
3. Let `github-issue-start` own worker dispatch; do not launch duplicate workers.
   Parallelize only independent issues and within the host's available capacity.
   When delegation is unavailable, report that limitation and handle safe issues
   sequentially, calling `github-issue-start` separately for each single issue
   instead of entering its multi-worker path. Local reviews still require their
   own delegation capabilities. For unsafe or dependent groups, honor the start
   skill's stop condition and present a proposed order or independent subset
   for the user.
4. Follow [Worker Dialogue](../delivery-common/references/worker-dialogue.md)
   for each issue: its worker drafts `shared-understanding`, and the coordinator
   asks the user one issue at a time. Forward a user's skip. Pass on only issues
   whose status is `confirmed`, `corrected`, or `skipped`; report the others as
   waiting for the user with their open points. Route workers' material design
   questions and approval requests through the coordinator, with the affected
   issue clearly identified; no worker asks the user directly.
5. Keep a progress record per issue under
   [Delivery Completion](../delivery-common/references/completion.md), adding
   the hosted review round count and the PR trigger and thread identifiers.

On resume, reconcile the record with actual local and GitHub state. Stop and
report the recorded branch unless it is a **safe branch name** before running
any command with it: run `node <script> -- '<branch>'`, where `<script>` is
[`check-branch-name.mjs`](../delivery-common/scripts/check-branch-name.mjs)
resolved from this skill's directory, and continue only on exit 0. Write a name
into this or any command only when it uses solely ASCII letters, digits, `/`,
`.`, `_`, and `-`; any other name is not safe, without running the check. Reuse
matching worktrees and PRs, preserve successful writebacks, and verify the
current head before reusing review evidence. Pass the PR/head/trigger record to
the cycle and resume its earliest incomplete phase. A pending review on the same
head resumes waiting rather than posting another trigger. A recorded
understanding check result carries forward. A progress file is evidence, not
authorization.

## Per-Issue Workflow

### 1. Preflight, implement, and verify

Set the tentative tier under [Risk Tier](../delivery-common/references/risk-tier.md)
first. Use `design-preflight-with-docs` for this issue in its worktree before editing the
implementation, drafted by the worker and asked by the coordinator under Worker
Dialogue. Forward any requested mode or question limit; otherwise use the mode
the tier's Tier procedure selects. Give it the issue's
shared understanding result: its agreed decisions and agreed issue changes are settled scope, and its preflight items open the
design questions. Inherit its completion and documentation criteria without an additional
interview. Carry forward settled decisions on resume. Leave material unanswered
decisions pending and continue only work that does not depend on them.

Implement the issue's acceptance criteria and confirmed examples, following the resulting design and
repository conventions. Run the smallest relevant checks. Record actual results
and material coverage limits; a successful baseline is not implementation
verification. Complete this phase only with an implementation and verification
evidence ready for review, or an explicit blocker.

### 2. Run local reviews and verify fixes

Follow [Local Review](../delivery-common/references/local-review.md) to set the
risk tier, select the host's reviewers, and run an initial full review with every
selected reviewer on the same base, issue, and implementation snapshot. Reviewers
remain read-only. Wait for all completed results before the implementation owner
edits.

Assess the findings under Local Review's Assess findings.
After fixes, follow Local Review's Repeat and advance for focused follow-up,
escalation to a full review, and advancement.

### 3. Publish and complete hosted Codex review

Coordinate publication and show the tier under Delivery Completion's Before
publication.
Use `github-pr-codex-review-cycle` for the exact issue branch/worktree. Honor its
publication approval model, actual-review completion criteria, Prepare -> publish
-> confirm remote head -> Writeback ordering, and stop-on-failure behavior.
Pass the earlier local and hosted dispositions from the progress record, and
have its follow-up assess hosted findings with Local Review's Assess findings.

Pass the progress record location to the cycle so that, before its Writeback,
it persists the prepared record's items not `applied` (the head Codex reviewed,
thread, finding, reviewer label, triage class, disposition, and reason) there.
When the cycle returns the items instead, record them there and confirm to the
cycle. Add their self-closures to the list under Local Review's Assess
findings; on resume, use the persisted items for the current hosted-reviewed
head. Record the returned status, PR, published head, reviewed head,
dispositions, and unresolved items. An acknowledgement or an `eyes` reaction is
not a completed review. An open PR is not a merged PR.

If hosted follow-up changed the implementation, return to the local review phase
for focused follow-up or a full review under Local Review's Repeat and advance.
Within the hosted rounds the Risk Tier's Tier procedure sets, obtain a fresh
hosted Codex review when the delta from the last hosted-reviewed head to the
published head contains a material change under Local Review's Triage, whether
it came from hosted or local follow-up; when uncertain, request it. Otherwise,
local focused follow-up covering the new head is sufficient; record the head the
hosted review covered and why the remaining delta did not need another hosted
round. To request another review,
reuse the existing PR and call the cycle again for that target; it does not
request another review automatically. If any other edit or new commit changes
the head, refresh the affected review coverage. Advance only when the current
published head is covered by the most recent full review and the follow-ups
completed since it under Local Review's Repeat and advance, has completed hosted
review or the recorded non-material delta above, worthwhile fixes are verified
and published, and remaining thread dispositions clearly close them.

### 4. Confirm and perform the merge

Check and present the merge under Delivery Completion's Merge confirmation,
adding the hosted review outcome and its remaining review threads. When it
combines the confirmations, use `github-worktree-cleanup`'s caller preview for
the cleanup targets. After approval, merge through the available GitHub tool or
CLI.

### 5. Confirm cleanup and verify completion

Before cleanup, keep this issue's follow-up candidates under Delivery
Completion.

Use `github-worktree-cleanup` for this issue's branch and worktree. Pass the
verified merge evidence. Let it inspect runtime resources, show exact
targets including any remote branch it proposes, obtain confirmation, and
perform its safety checks. Pass a combined confirmation only as Delivery
Completion's Merge confirmation allows; otherwise a merge confirmation alone
does not approve cleanup. Preserve a dirty, busy, or otherwise unsafe
worktree and report the blocker.

Verify the PR is merged and the confirmed local targets are gone. Read the issue
state and report whether it actually closed; do not silently close, label, or
comment on it. An open issue or unfinished cleanup remains an open item rather
than a fully completed issue delivery.

## Bounds and Handoffs

Local review rounds follow Local Review's Repeat and advance; hosted-fix
follow-ups use the same local budget. Hosted Codex review rounds per issue
follow the Risk Tier's Tier procedure across this delivery, including resumes.
A hosted round requires actual output. Apply
Delivery Completion's Bounds, adding a hosted limit reached with required work
remaining as a stop condition. At a hosted limit, include the remaining-findings
classification from Local Review's Assess findings. Ask before extending the
hosted budget or retrying a timed-out external review; do not repeatedly post
triggers.

Use the cycle's bounded waiting rules. A cycle failure is a publication failure.

Report each issue, mark it `Complete`, and list follow-up candidates under
Delivery Completion. Task closure is the issue's actual closed state, and the
create skill is `github-issue-create`.
