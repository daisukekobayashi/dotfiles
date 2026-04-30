---
name: github-pr-publish-and-ai-review
description: Use only when the user explicitly invokes `$github-pr-publish-and-ai-review` or names `github-pr-publish-and-ai-review`. Do not use for generic commit, push, PR creation, or review requests.
---

# GitHub PR Publish And AI Review

## Scope

Use this orchestration skill to publish one or more local branches or worktrees
as pull requests, then request both Copilot and Codex review through the
existing AI review wrapper.

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
2. For each target, inspect local state before changing anything.
   - Run `git status --short`.
   - Run `git diff --stat`.
   - Run `git diff --check`.
   - Look for untracked or modified secret-like files such as `.env`, credentials, tokens, private keys, or local config. Do not stage them; stop or ask before continuing when they affect the requested commit.
3. Confirm recent verification.
   - If the current conversation already has a successful verification log after the target's latest code changes, use it.
   - Otherwise determine the repository's required verification command from local guidance and run it before committing.
   - If verification fails, stop that target and report the likely cause without continuing to later targets.
4. Commit when needed.
   - If the user explicitly asked to commit, treat commit approval as given for non-destructive commits covering the requested work.
   - If commit intent is ambiguous, preview the target, candidate files, and commit direction, then ask before committing.
   - Use the `git-commit` skill for staging and commit message generation.
   - Never stage secrets or unrelated local files.
5. Push the branch.
   - If the user explicitly asked to push, treat push approval as given for a normal push of the target branch.
   - If push intent is ambiguous, preview the target remote and branch, then ask before pushing.
   - Use a normal push only. Do not force push, delete remote branches, or rewrite history unless the user separately and explicitly approves that operation.
6. Create or resolve the PR.
   - Use the `github-pr-from-template` skill for each target branch.
   - Reuse an existing PR when one already exists for the branch.
7. Request AI review.
   - Use the existing `github-ai-review-request` skill for the resolved PR.
   - Keep Copilot and Codex outcomes separate.
   - If only one review request succeeds, report the partial success and the failure reason.

## Guardrails

- Do not proceed to PR creation until verification has succeeded for the target's latest changes.
- Do not continue to later targets after a commit, push, PR creation, or verification failure.
- Do not force push, merge, delete remote branches, or clean up worktrees.
- Do not edit dependency manifests, lockfiles, or install dependencies unless the user explicitly asks.
- Do not hide partial AI review failures.
- Keep a per-target record of verification, commit, push, PR URL, Copilot request status, and Codex request status for the final report.
