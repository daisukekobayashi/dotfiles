---
name: github-pr-codex-review-cycle
description: Use only when the user explicitly invokes `$github-pr-codex-review-cycle` or names `github-pr-codex-review-cycle`.
---

# GitHub PR Codex Review Cycle

## Scope

Use this orchestration skill to run the normal end-to-end cycle after an
implementation is ready: publish the current work as a pull request, request
Codex review, wait for the actual review output, address worthwhile AI review
feedback, then commit, push, reply, and resolve the handled review threads.

This skill intentionally composes existing skills. Do not copy their detailed
workflows here.

Required sub-skills:
- `github-pr-publish`
- `github-pr-codex-review-request`
- `github-pr-ai-review-followup`

Use `github:gh-address-comments` whenever thread-level review state, inline
context, replies, or resolution matters.

This skill is not for:
- implementing feature work before publication
- Copilot review requests unless the user separately asks
- human review sweeps
- merging pull requests
- deleting branches or worktrees
- force pushing, rebasing, amending, or history rewriting

## Approval Model

Because this skill only runs when explicitly invoked, treat the invocation as
approval for the normal, non-destructive cycle on the requested feature branch:

- verification required by `github-pr-publish`
- ordinary commit of the requested implementation work
- normal push of the current feature branch
- pull request creation or reuse
- posting the `@codex review` trigger comment
- applying worthwhile Codex or Copilot review fixes
- ordinary commit and normal push for review-follow-up fixes
- short GitHub replies to the latest AI review threads
- resolving latest AI review threads with dispositions that clearly close them:
  `applied`, `stale`, `duplicate`, or fully answered `explained`

Still stop and ask before:
- publishing from the default branch
- staging secret-like files, credentials, local config, or unrelated changes
- force push, rebase, amend, reset, merge, branch deletion, or worktree removal
- dependency manifest or lockfile edits unless already explicitly part of the
  requested work
- resolving `needs-human-decision`, ambiguous, conflicting, risky, or still
  reasonably disputed review feedback
- broad formatting, generator, or snapshot changes not required for the review

## Workflow

1. Resolve the target branch or worktree.
   - If no target is specified, use the current worktree and branch.
   - For multiple targets, process sequentially and stop on the first failure.
2. Use `github-pr-publish`.
   - Preserve that skill's verification, staging, commit, push, and PR rules.
   - Capture the PR number, PR URL, branch, commit, and verification result.
3. Use `github-pr-codex-review-request` for the resolved PR.
   - Treat `Codex acknowledged` as acknowledgement only.
   - Treat `Codex request posted but not acknowledged` as a blocker unless the
     user explicitly asks to continue waiting or retry.
4. Wait for Codex review completion.
   - The exact `@codex review` trigger comment receiving an `eyes` reaction is
     not review completion.
   - Review completion requires actual Codex review output after the trigger:
     review threads, inline comments, or a review summary/comment that indicates
     the run finished.
   - Poll the PR comments/reviews/thread state at reasonable intervals and keep
     the user updated during long waits.
   - If no actual review output appears within a practical bound, report the PR,
     trigger comment, acknowledgement state, and last checked time. Do not run
     review follow-up against stale or absent output.
5. Use `github-pr-ai-review-followup` on the latest Codex review feedback.
   - Pass through that this cycle invocation already approves writeback for
     clearly closed latest AI review items.
   - Keep per-thread dispositions; do not flatten the review into silent edits.
   - Apply only worthwhile fixes.
6. If review fixes changed files, verify, commit, and push.
   - Run the smallest relevant verification for the changed files.
   - Stage only review-follow-up changes.
   - Use a normal commit and normal push of the same feature branch.
   - If verification fails, stop before commit, push, reply, or resolve.
7. Reply and resolve handled review threads.
   - Use thread-aware targets, not flat PR-comment guesses.
   - Reply briefly with outcome and verification.
   - Resolve only unresolved threads whose disposition clearly closes them under
     the Approval Model.
8. Verify final PR state when possible.
   - Re-read thread state after writeback.
   - Report unresolved, skipped, ambiguous, or human-decision items.

## Completion Criteria

The cycle is complete only when one of these is true:

- Codex review output was inspected, worthwhile fixes were handled, verification
  passed, needed commits/pushes were done, and clearly closed threads were
  replied to and resolved.
- Codex produced no actionable feedback, and final thread/comment state was
  checked.
- A blocker occurred and was reported with the exact next approval or external
  state needed.

## Final Report

Use this structure:

```markdown
**Cycle Complete**
- Branch: `<branch>`
- PR: <url>
- Publish: `<commit or no new commit>`; verification `<command>` passed
- Codex: `<acknowledged/completed/blocked summary>`
- Follow-up: `<applied/explained/skipped/stale/duplicate counts>`
- Review fix commit: `<sha>` or "No review-fix commit needed"
- Writeback: `<replied/resolved counts>`

**Open Items**
- <unresolved or human-decision items, or "None">
```
