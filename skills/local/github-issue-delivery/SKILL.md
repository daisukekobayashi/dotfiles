---
name: github-issue-delivery
description: Coordinate GitHub issues through isolated worktrees, design preflight with docs, implementation, local reviews, PR Codex review and fixes, approved merge, and local cleanup. Use when the user requests this full delivery workflow for one or more issues; resume unfinished deliveries without repeating completed operations.
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
full workflow selects its delegated preflight, adversarial, and PR-cycle phases;
their instructions recognize this caller. Automatic discovery or a reference to
this file does not select those phases or grant mutation approval. If authorization
is missing, prepare the concrete result and request only the approval needed for
the next operation. Reuse authorization already given for the same scope.

The workflow includes both local review passes and the normal publication,
Codex review, and writeback cycle. It requires separate confirmation for the
specific PR merge and for the exact local cleanup resources. Preserve all
applicable dependency, history-rewrite, remote-write, and user-change protections.

## Prepare and Coordinate

1. Resolve issue numbers, repository instructions, dirty state, and existing
   worktrees/PRs. Require at least one actual issue target. Check that the
   component skills and the selected local reviewers are available. The normal
   installation is `base,github`; the GitHub profile alone does not supply the
   preflight and fallback review skills. Report a missing prerequisite rather
   than silently installing it or skipping a required phase.
2. Use `github-issue-start` with the per-issue workflow below as its implementation
   brief. Have it prepare the worktree and baseline before entering preflight;
   implementation begins only after preflight. Preserve its issue classification,
   dependency checks, and one-issue/one-branch/one-worktree ownership.
3. Let `github-issue-start` own worker dispatch; do not launch duplicate workers.
   Parallelize only independent issues and within the host's available capacity.
   When delegation is unavailable, report that limitation and handle safe issues
   sequentially, calling `github-issue-start` separately for each single issue
   instead of entering its multi-worker path. Local reviews still require their
   own delegation capabilities. For unsafe or dependent groups, honor the start
   skill's stop condition and present a proposed order or independent subset
   for the user.
   Route workers' material design questions and approval requests through the
   coordinator, with the affected issue clearly identified.
4. Before writing progress records, classify them as temporary and choose ignored
   agent-work storage or `/tmp`. Keep a separate record per issue: URL, scope,
   worktree, branch, base ref and SHA, current phase, accepted design decisions,
   verification, reviewed head SHAs, review round counts, PR and trigger/thread
   identifiers, dispositions, blockers, and next action. Report the resume path.
   Keep durable definitions and decisions in the repository's normal docs.

On resume, reconcile the record with actual local and GitHub state. Reuse matching
worktrees and PRs, preserve successful writebacks, and verify the current head
before reusing review evidence. Pass the PR/head/trigger record to the cycle and
resume its earliest incomplete phase. A pending review on the same head resumes
waiting rather than posting another trigger. A progress file is evidence, not
authorization.

## Per-Issue Workflow

### 1. Preflight, implement, and verify

Use `design-preflight-with-docs` for this issue in its worktree before editing the
implementation. Forward any requested mode or question limit; otherwise use its
default. Inherit its completion and documentation criteria without an additional
interview. Carry forward settled decisions on resume. Leave material unanswered
decisions pending and continue only work that does not depend on them.

Implement the issue's acceptance criteria, following the resulting design and
repository conventions. Run the smallest relevant checks. Record actual results
and material coverage limits; a successful baseline is not implementation
verification. Complete this phase only with an implementation and verification
evidence ready for review, or an explicit blocker.

### 2. Run both local reviews, assess, and repeat

Follow [Local Review](references/local-review.md) to select the host's reviewers
and give both the same base, issue, and implementation snapshot. Reviewers remain
read-only. Wait for both completed results before the implementation owner edits.

Assess each finding against the issue, code, and evidence. Apply worthwhile fixes;
record a concise reason for explained, duplicate, stale, or skipped findings.
Leave disputed material findings or design decisions open for the user. Avoid
scope expansion and speculative churn.

After fixes, run relevant checks and repeat both local reviews on the new
snapshot. Advance only when both passes completed on the current implementation,
verification is current, and no material actionable finding or human decision
remains open. Failed, unavailable, empty, or partial review output is not a pass.

### 3. Publish and complete hosted Codex review

Coordinate publication sequentially across issue targets; workers hand off their
branch, worktree, issue/spec, recorded base, verification, and local review
evidence. Use `github-pr-codex-review-cycle` for the exact issue branch/worktree. Honor its
publication approval model, actual-review completion criteria, Prepare -> publish
-> confirm remote head -> Writeback ordering, and stop-on-failure behavior.

Record the returned status, PR, published head, reviewed head, dispositions, and
unresolved items. An acknowledgement or an `eyes` reaction is not a completed
review. An open PR is not a merged PR.

If hosted follow-up changed the implementation, return to the local review phase
and obtain a fresh hosted Codex review for the resulting published head. Reuse
the existing PR and call the cycle again for that target; it does not request
another review automatically. If any other edit or new commit changes the head,
invalidate the affected review evidence. Advance only when the current published
head has completed both local reviews and hosted review, worthwhile fixes are
verified and published, and remaining thread dispositions clearly close them.

### 4. Confirm and perform the merge

Check the current PR head, base, required CI checks, required human approvals,
mergeability, and remaining review threads. Pending, failed, or inaccessible
required checks leave the issue waiting or blocked. Approval for one head does
not cover an intervening material change; reassess before proceeding.

Present the PR URL, issue, head SHA, base, checks, review outcome, and proposed
repository-supported merge method. Request confirmation to merge that specific
PR. After approval, recheck the target and merge through the available GitHub
tool or CLI without bypassing checks or requesting branch deletion. If the user
merges separately, verify that outcome instead. Confirm actual merged state and
merge commit before cleanup; a queued or scheduled merge remains pending.

### 5. Confirm cleanup and verify completion

Use `github-worktree-cleanup` for this issue's branch and worktree. Pass the
verified merge evidence. Let it inspect runtime resources, show exact local
targets, obtain confirmation, and perform its safety checks. Preserve remote
branches unless their deletion was separately requested. A merge confirmation
alone does not approve cleanup. Preserve a dirty, busy, or otherwise unsafe
worktree and report the blocker.

Verify the PR is merged and the confirmed local targets are gone. Read the issue
state and report whether it actually closed; do not silently close, label, or
comment on it. An open issue or unfinished cleanup remains an open item rather
than a fully completed issue delivery.

## Bounds and Handoffs

Default to at most three local review rounds and three hosted Codex review rounds
per issue across this delivery, including resumes. A local round runs both
reviewers; a hosted round requires actual output. A clean result may advance
immediately. User-specified lower limits take precedence. At the limit, repeated
non-progress, a timeout, a failed required check, or a material human decision,
preserve progress and report the next action. Ask before extending the budget or
retrying a timed-out external review; do not repeatedly post triggers.

Use the cycle's bounded waiting rules and keep the user informed. Stop further
publication targets after a cycle failure. Independent local work may continue
when it does not depend on the blocker. Never turn a wait or unresolved approval
into a successful completion claim.

Report each issue separately with issue/PR links, branch/worktree or confirmed
removal, verification and limitations, current reviewed head and review rounds,
merge state, issue state, and exact pending decision or action. Use states such
as `In progress`, `Waiting for user`, `Waiting for review/CI`, `Blocked`,
`Merged; cleanup pending`, and `Complete`. Mark `Complete` only after acceptance
criteria, current verification/reviews, actual merge, issue closure, and confirmed
local cleanup have all been verified. Overall completion requires every requested
issue to meet that condition.
