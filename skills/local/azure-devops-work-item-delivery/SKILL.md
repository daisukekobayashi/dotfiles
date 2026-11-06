---
name: azure-devops-work-item-delivery
description: Coordinate Azure DevOps Work Items through isolated worktrees, a shared understanding and design preflight with docs drafted by workers and asked by the coordinator, implementation, local reviews, PR publication, approved merge, and local cleanup. Use when the user requests this full delivery workflow for named Work Items; resume unfinished deliveries without repeating completed operations.
---

# Azure DevOps Work Item Delivery

Deliver each requested Work Item by composing the existing skills. Keep their
operational details and approval rules in those skills. IDs in examples or a
discussion about this skill are not work orders.

```text
Claude Code: /azure-devops-work-item-delivery 123 456
Codex:       $azure-devops-work-item-delivery 123 456
```

## Scope and Authorization

Use the current repository's Azure Boards Work Items and Azure Repos Git PRs on
Azure DevOps Services. Read `../azure-devops-common/references/context.md` before
resolving the target. Azure Boards with GitHub repositories and Azure DevOps
Server need a different workflow; report that boundary rather than choosing an
Azure Repos target for them.

Read component skills before their phases. Forward the user's actual full
workflow request, exact Work Item/branch/worktree, and existing authorizations.
An explicit full delivery request selects the delegated shared understanding,
preflight, local review, and publication phases. Automatic discovery or a
reference to this skill selects none of them and grants no mutation approval.
Honor the publisher's approval model and governing instructions for scoped
checkpoint commits, normal pushes, and PR creation. Prepare the concrete result
before requesting missing approval; reuse approval already given for the same
scope.

Require explicit confirmation for the specific PR merge and the exact local
cleanup resources, combined only where Delivery Completion's Merge confirmation
allows. Work Item state transitions also require explicit intent;
include any proposed transitions in the merge confirmation. Preserve dependency,
history-rewrite, remote-write, and user-change protections. This workflow ends
its publication phase at the PR; it has no hosted AI review request or follow-up
cycle.

## Prepare and Coordinate

1. Resolve the requested IDs, organization, project, repository, instructions,
   dirty state, and matching worktrees/PRs. Require at least one actual Work
   Item. Check component skills and the local reviewers, including
   `change-security-review`, before starting.
   The normal installation is `base,azure-devops`; report missing prerequisites
   rather than installing them or skipping required phases.
2. Use `azure-devops-work-item-start` with the per-item workflow below as its
   implementation brief. Prepare its worktree and baseline and dispatch the
   item's worker before the shared understanding; implement only after
   preflight. Preserve classification, dependency checks,
   and one-Work-Item/one-branch/one-worktree ownership. Proceed only with directly
   actionable items; report parent trackers, blockers, and ambiguous scope first.
3. Let the start skill own worker dispatch. Parallelize independent items only
   within available capacity and keep each worker in its assigned worktree.
   When delegation is unavailable, report it and process safe items sequentially
   through separate single-item calls. Local reviews still need their own
   delegation capabilities. For dependent or unsafe groups, honor the start
   skill's stop condition and present an order or independent subset to the user.
4. Follow [Worker Dialogue](../delivery-common/references/worker-dialogue.md)
   for each item: its worker drafts `shared-understanding`, and the coordinator
   asks the user one item at a time. Forward a user's skip. Pass on only items
   whose status is `confirmed`, `corrected`, or `skipped`; report the others as
   waiting for the user with their open points. Route material design questions
   and approvals through the coordinator; no worker asks the user directly.
5. Keep a progress record per item under
   [Delivery Completion](../delivery-common/references/completion.md), adding
   the organization, project and repository IDs, the PR ID and source/target
   refs, the policy and merge state, and the Work Item state.

On resume, reconcile the record with actual local and Azure DevOps state. Stop
and report the recorded branch unless it is a **safe branch name** before
running any command with it: run `node <script> -- '<branch>'`, where `<script>`
is [`check-branch-name.mjs`](../delivery-common/scripts/check-branch-name.mjs)
resolved from this skill's directory, and continue only on exit 0. Write a name
into this or any command only when it uses solely ASCII letters, digits, `/`,
`.`, `_`, and `-`; any other name is not safe, without running the check. Reuse
matching worktrees and PRs; a completed PR resumes completion checks rather than
publication. Recheck the current source ref before reusing review evidence.
Resume the earliest incomplete phase. A recorded shared understanding result
carries forward. A progress record is evidence, not authorization.

## Per-Work-Item Workflow

### 1. Preflight, implement, and verify

Set the tentative tier under [Risk Tier](../delivery-common/references/risk-tier.md)
first. Use `design-preflight-with-docs` in the assigned worktree before
implementation, drafted by the worker and asked by the coordinator under Worker
Dialogue. Forward the requested mode/question limit or use the mode the tier's
Tier procedure selects. Give it the item's
shared understanding result: its agreed decisions and agreed changes are
settled scope, and its preflight items open the design questions. Inherit its
completion and documentation criteria without a second interview. Carry forward
settled decisions on resume. Keep material unanswered decisions pending and
continue only work that does not depend on them.

Implement the Work Item's acceptance criteria, confirmed examples, and accepted design. Run focused
repository checks and record actual results and coverage limits; the baseline
alone is not implementation verification. Finish with an implementation and
verification evidence ready for review, or an explicit blocker.

### 2. Run local reviews, assess, and repeat

Follow [Local Review](../delivery-common/references/local-review.md) to set the
risk tier, select the reviewers, and run an initial full review with every
selected read-only reviewer on the same recorded base, Work Item/spec, and
committed snapshot. Wait for all results before the implementation owner edits.

Assess the findings under Local Review's Assess findings.
After fixes, follow Local Review's Repeat and advance for focused follow-up,
escalation to a full review, and advancement.

### 3. Publish the PR

Coordinate publication and show the tier under Delivery Completion's Before
publication.
Use `azure-devops-pr-publish`, forwarding the full request and existing approvals.
Honor its stop-on-failure behavior. Supply known Work Item IDs, completion scope,
and the user's state-transition intent; use structured PR links under the common
context rules.

Verify the returned PR's repository, source/target refs, and Work Item links.
Read the current remote source ref and compare its commit with the local reviewed
HEAD; a successful push or PR creation alone does not establish this match.
Record the PR and published head. If publication creates a different commit or
any later edit changes the implementation, invalidate affected review evidence,
return to local verification and review under Local Review's Repeat and advance,
and republish through the existing PR.

Advance when the exact published implementation is covered by the most recent
full review and the follow-ups completed since it under Local Review's Repeat
and advance, has current verification, and has the intended Work Item links.
An existing PR does not need another creation, and an open PR is not a merged
PR.

### 4. Confirm and perform the merge

Follow [Merge and Work Item State](references/merge-and-state.md) to check the
current source/target, required policies/CI, human approvals, discussion threads,
and mergeability. Keep source-HEAD concurrency limits explicit.

Check and present the merge under Delivery Completion's Merge confirmation,
adding the required policies and the proposed state-transition scope. When it
combines the confirmations, use `azure-devops-worktree-cleanup`'s caller preview
for the cleanup targets. Complete the PR as that reference describes.

### 5. Confirm cleanup and verify completion

Before cleanup, keep this item's follow-up candidates under Delivery
Completion.

After verifying actual PR completion and the merged source/merge commit, use
`azure-devops-worktree-cleanup` for the exact item branch/worktree. Pass merge
evidence and let it inspect runtimes, show exact resources including any remote
branch it proposes, obtain separate confirmation unless Delivery Completion's
Merge confirmation combined it, and perform its safety checks.
Preserve dirty, busy, or otherwise unsafe resources and report the blocker.

Verify that confirmed local targets are gone. Read the Work Item's actual state
and verify completion under its process; PR completion does not prove Work Item
completion. Follow the reference for pending transitions. Report open Work Item
completion or cleanup as unfinished; do not silently update, assign, tag, or
comment on the Work Item.

## Bounds and Handoffs

Local review rounds follow Local Review's Repeat and advance; this workflow
runs no hosted AI review rounds. Apply Delivery Completion's Bounds.

Check policies when reaching merge or resuming; avoid indefinite polling. If the
user asks to wait, use a bounded window and report its limit; otherwise report
`Waiting for review/CI`. A verification, commit, push, or PR failure is a
publication failure.

Report each item, mark it `Complete`, and list follow-up candidates under
Delivery Completion, adding the state `Merged; Work Item completion pending`.
Task closure is the Work Item's verified completion under its process, and the
create skill is `azure-devops-work-item-create`.
