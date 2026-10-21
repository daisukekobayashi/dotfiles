---
name: azure-devops-work-item-delivery
description: Coordinate Azure DevOps Work Items through isolated worktrees, design preflight with docs, implementation, local reviews, PR publication, approved merge, and local cleanup. Use when the user requests this full delivery workflow for named Work Items; resume unfinished deliveries without repeating completed operations.
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
An explicit full delivery request selects the delegated preflight, local review,
and publication phases. Automatic discovery or a reference to this skill selects
none of them and grants no mutation approval. Honor the publisher's approval
model and governing instructions for scoped checkpoint commits, normal pushes,
and PR creation. Prepare the concrete result before requesting missing approval;
reuse approval already given for the same scope.

Require separate confirmation for the specific PR merge and the exact local
cleanup resources. Work Item state transitions also require explicit intent;
include any proposed transitions in the merge confirmation. Preserve dependency,
history-rewrite, remote-write, and user-change protections. This workflow ends
its publication phase at the PR; it has no hosted AI review request or follow-up
cycle.

## Prepare and Coordinate

1. Resolve the requested IDs, organization, project, repository, instructions,
   dirty state, and matching worktrees/PRs. Require at least one actual Work
   Item. Check component skills and selected local reviewers before starting.
   The normal installation is `base,azure-devops`; report missing prerequisites
   rather than installing them or skipping required phases.
2. Use `azure-devops-work-item-start` with the per-item workflow below as its
   implementation brief. Prepare its worktree and baseline before preflight;
   implement only after preflight. Preserve classification, dependency checks,
   and one-Work-Item/one-branch/one-worktree ownership. Proceed only with directly
   actionable items; report parent trackers, blockers, and ambiguous scope first.
3. Let the start skill own worker dispatch. Parallelize independent items only
   within available capacity and keep each worker in its assigned worktree.
   When delegation is unavailable, report it and process safe items sequentially
   through separate single-item calls. Local reviews still need their own
   delegation capabilities. For dependent or unsafe groups, honor the start
   skill's stop condition and present an order or independent subset to the user.
   Route material design questions and approvals through the coordinator.
4. Before writing progress records, classify them as temporary and choose ignored
   agent-work storage or `/tmp`. Record separately per item: organization,
   project/repository IDs, Work Item URL and scope, branch/worktree, base ref/SHA,
   phase, accepted design, verification, reviewed head SHAs and local round
   count, PR ID/URL and source/target refs, published head, policy/merge state,
   Work Item state, finding dispositions, blockers, and next action. Report the
   resume path. Keep stable definitions and decisions in normal repository docs.

On resume, reconcile the record with actual local and Azure DevOps state. Reuse
matching worktrees and PRs; a completed PR resumes completion checks rather than
publication. Recheck the current source ref before reusing review evidence.
Resume the earliest incomplete phase. A progress record is evidence, not
authorization.

## Per-Work-Item Workflow

### 1. Preflight, implement, and verify

Use `design-preflight-with-docs` in the assigned worktree before implementation.
Forward the requested mode/question limit or use its default. Inherit its
completion and documentation criteria without a second interview. Carry forward
settled decisions on resume. Keep material unanswered decisions pending and
continue only work that does not depend on them.

Implement the Work Item's acceptance criteria and accepted design. Run focused
repository checks and record actual results and coverage limits; the baseline
alone is not implementation verification. Finish with an implementation and
verification evidence ready for review, or an explicit blocker.

### 2. Run both local reviews, assess, and repeat

Follow [Local Review](../delivery-common/references/local-review.md). Give both
read-only reviewers the same recorded base, Work Item/spec, and committed
snapshot. Wait for both results before the implementation owner edits.

Assess findings against the requirements, code, and evidence. Apply worthwhile
fixes; record concise reasons for explained, duplicate, stale, or skipped
findings. Keep disputed material findings and design decisions open for the user.
After fixes, verify and repeat both reviews on the new snapshot.

Advance only after both passes completed on the current implementation,
verification is current, and no material actionable finding or human decision
remains open. Failed, unavailable, empty, or partial output is not a pass.

### 3. Publish the PR

Coordinate publication sequentially across targets. Workers hand off their exact
branch/worktree, Work Item/spec, base, verification, and local review evidence.
Use `azure-devops-pr-publish`, forwarding the full request and existing approvals.
Honor its stop-on-failure behavior. Supply known Work Item IDs, completion scope,
and the user's state-transition intent; use structured PR links under the common
context rules.

Verify the returned PR's repository, source/target refs, and Work Item links.
Read the current remote source ref and compare its commit with the local reviewed
HEAD; a successful push or PR creation alone does not establish this match.
Record the PR and published head. If publication creates a different commit or
any later edit changes the implementation, invalidate affected review evidence,
return to local verification/review, and republish through the existing PR.

Advance when the exact published implementation has both completed local
reviews, current verification, and the intended Work Item links. An existing PR
does not need another creation, and an open PR is not a merged PR.

### 4. Confirm and perform the merge

Follow [Merge and Work Item State](references/merge-and-state.md) to check the
current source/target, required policies/CI, human approvals, discussion threads,
and mergeability. Pending, failed, or inaccessible required evidence leaves the
item waiting or blocked. Keep source-HEAD concurrency limits explicit.

Present the PR URL, Work Item, reviewed/published head, target, checks, local
review outcome, repository-supported merge method, and proposed state-transition
scope. Request confirmation for that specific PR. Recheck after approval;
material changes require reassessment. Complete the PR only within that approval
and without bypassing policies or deleting the remote branch. If the user merges
separately, verify the result instead. A queued merge remains pending.

### 5. Confirm cleanup and verify completion

After verifying actual PR completion and the merged source/merge commit, use
`azure-devops-worktree-cleanup` for the exact item branch/worktree. Pass merge
evidence and let it inspect runtimes, show exact local resources, obtain separate
confirmation, and perform its safety checks. Preserve dirty, busy, or otherwise
unsafe resources and report the blocker. Preserve remote branches unless their
deletion was separately requested.

Verify that confirmed local targets are gone. Read the Work Item's actual state
and verify completion under its process; PR completion does not prove Work Item
completion. Follow the reference for pending transitions. Report open Work Item
completion or cleanup as unfinished; do not silently update, assign, tag, or
comment on the Work Item.

## Bounds and Handoffs

Allow at most three local review rounds per item across this delivery, including
resumes; one round includes both reviewers. A clean result may advance
immediately. Honor lower user limits. At the limit, repeated non-progress, a
timeout, failed required check, or material human decision, preserve progress
and report the next action. Ask before extending the budget.

Check policies when reaching merge or resuming; avoid indefinite polling. If the
user asks to wait, use a bounded window and report its limit; otherwise report
`Waiting for review/CI`. Keep updates timely. Stop further publication targets
after a verification, commit, push, or PR failure. Independent local work may
continue when it does not depend on the blocker.

Report each item separately with Work Item/PR links, branch/worktree or confirmed
removal, verification and limits, reviewed/published head and local round count,
policy/merge state, Work Item state, and exact pending decision/action. Use
`In progress`, `Waiting for user`, `Waiting for review/CI`, `Blocked`,
`Merged; Work Item completion pending`, `Merged; cleanup pending`, or `Complete`.
Mark `Complete` only after acceptance criteria, current verification/local
reviews, actual merge, Work Item completion, and confirmed local cleanup have
all been verified. Overall completion requires every requested item to qualify.
