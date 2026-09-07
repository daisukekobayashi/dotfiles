---
name: github-pr-publish-and-ai-review-request
description: Use only when the user explicitly invokes `$github-pr-publish-and-ai-review-request` or names `github-pr-publish-and-ai-review-request` for publishing local GitHub changes as a pull request and requesting AI review.
---

# GitHub PR Publish And AI Review Request

## Scope

Use this orchestration skill to publish one or more local branches or worktrees
as pull requests, then request both Copilot and Codex review through the
existing PR AI review request wrapper.

This skill is not for:
- implementing feature changes before publication
- applying review feedback
- merging pull requests
- deleting branches or worktrees
- force pushing
- cleaning up after merge

## Workflow

1. Resolve targets.
   - Identify each branch or worktree requested by the user.
   - If no target is specified, use the current worktree and branch.
   - For multiple targets, process them sequentially and stop on the first failure.
2. Use `github-pr-publish` for the target.
   - Delegate repository checks, verification, staging, commit, push, and PR
     creation or reuse to that skill; do not maintain a second publication workflow.
   - Apply its approval model to the requested publication, subject to governing
     instructions and the user's actual authorization. Pass through existing
     authorization rather than asking again for the same operation.
   - Capture the branch, commit, push target, PR number/URL, and verification result.
   - If publication fails or is blocked, stop before requesting review or moving
     to another target.
3. Use `github-pr-review-request` with provider `both` for that exact PR.
   - An explicit request to run this combined workflow includes requesting both
     reviews, subject to governing approval rules.
   - Let that skill handle both requests and their separate verification.
   - Report partial success; if either request fails or remains unacknowledged,
     stop before moving to another target. Do not repeat publication or a
     successful review request to recover the other request.

## Guardrails

- Do not force push, merge, delete remote branches, or clean up worktrees.
- Do not hide partial AI review failures.
- Keep a per-target record of verification, commit, push, PR URL, Copilot request status, and Codex request status for the final report.
