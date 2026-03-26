---
name: git-workflow-guardrails
description: Use this skill when the task involves creating or switching branches or worktrees, staging files, preparing commits, writing commit messages, or pushing changes. Do not use it for read-only git inspection unless the user is explicitly asking for workflow guidance or an action that changes repository state.
---

# Git Workflow Guardrails

Follow this workflow for repository-changing git tasks.

## Inputs

- The requested git action, such as branch creation, staging, commit preparation, or push.
- Any ticket or work item ID that should appear in a branch name.

## Workflow

1. Inspect the repository state with read-only git commands before changing anything.
2. When creating a branch or worktree from `main`, run and verify this sequence in order:
   - `git fetch origin --prune`
   - `git switch main`
   - `git pull --ff-only`
   Stop immediately if any step fails, and report the reason before continuing.
3. Name branches with one of these prefixes: `feat/`, `fix/`, `refactor/`, `chore/`, or `test/`.
4. If a tracking issue exists, place its ID immediately after the slash. Example: `fix/47-description-of-change`.
5. Keep commits atomic. Do not mix unrelated refactors, formatting-only edits, or untracked files into the same commit.
6. Stage only files directly related to the requested change. Do not stage unrelated files, and never use `git add .` or `git add -A`.
7. Write commit messages using Conventional Commits: `<type>(<scope>): <subject>`.
8. Before running `git commit` or `git push`, summarize the staged changes and request explicit user approval.
9. If the worktree already contains unrelated user changes, do not revert them. Work around them or call out the conflict.

## Output

- A repository state that follows the branch naming, staging, and commit rules above.
- A short summary to the user before any commit or push.
