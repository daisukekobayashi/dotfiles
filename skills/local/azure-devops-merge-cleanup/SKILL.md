---
name: azure-devops-merge-cleanup
description: Use when the user says Azure DevOps work is already merged or complete and wants to safely clean up the local feature branch and worktree.
---

# Azure DevOps Merge Cleanup

## Scope

Clean up only local branch and local worktree state after Azure DevOps work is
complete. This skill does not remove remote branches.

Read `../azure-devops-common/references/context.md` before checking PR status.

## Workflow

1. Resolve the cleanup target.
   - Prefer an explicitly named branch.
   - Otherwise use the current feature branch.
   - If the current branch is the default branch and no target is specified,
     stop and ask for the branch.
2. Detect whether the target checkout has an associated git worktree and record
   the path if present.
3. Verify cleanup safety.
   - Check local git state first.
   - If local state is not enough, confirm PR completed/merged status with
     `az repos pr show`.
4. If the branch is not merged or completion is unclear, stop and explain why
   cleanup is unsafe.
5. Show the exact local resources that would be removed and require explicit
   confirmation.
6. Remove the local worktree first when one exists. If you are inside it, change
   to a safe location before removal.
7. Delete the local branch after the worktree is removed.
8. Summarize what was removed and what remains.

## Guardrails

- Treat cleanup as destructive and require explicit confirmation.
- Never delete an unmerged branch.
- Never remove a remote branch unless the user explicitly asks.
- Never assume the current branch is disposable just because the prompt says
  "merged" or "completed."
- If git refuses removal because the worktree is busy or dirty, stop and report
  the exact blocker.
