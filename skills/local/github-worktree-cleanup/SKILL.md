---
name: github-worktree-cleanup
description: Use when the user says the work is already merged or otherwise complete and wants to safely clean up the local feature branch and worktree that were used for that task in the current repository.
---

# GitHub Worktree Cleanup

## Workflow

1. Resolve the cleanup target.
   - Prefer an explicitly named branch.
   - Otherwise use the current feature branch.
   - If the current branch is the default branch and no target is specified, stop and ask for the branch to clean up.
2. Detect whether the target checkout has an associated git worktree and record the path if present.
3. Verify that cleanup is safe.
   - Check local git state first.
   - If local state is not enough, confirm merged status through the GitHub plugin.
4. If the branch is not merged or completion is unclear, stop and explain why cleanup is unsafe.
5. Check the remote branch. Propose deleting it only when all of these hold; otherwise keep it and report the unmet condition:
   - The PR for this branch is merged, and its head repository is the remote you push to, not a fork owned by someone else.
   - `git ls-remote --heads <remote> <branch>` returns exactly the PR's merged `headRefOid`. A later push means unmerged work.
   - The branch is not the default branch and is not protected.
   - `gh pr list --head <branch> --state open` returns no other PR.
   If the remote branch no longer exists, report that and skip it.
6. Show the exact resources that would be removed, including any proposed remote branch with its remote and SHA, and require explicit confirmation.
7. Remove the local worktree first when one exists. If you are inside it, change to a safe location before removal.
   - Before removal, follow `../worktree-runtime-cleanup/SKILL.md` for the worktree path. If that file is absent, say so in the summary.
8. Delete the local branch after the worktree is removed.
9. Delete the confirmed remote branch last, conditioned on the checked SHA:
   `git push --force-with-lease=refs/heads/<branch>:<sha> <remote> :refs/heads/<branch>`.
   If the lease is rejected, keep the branch and report that it changed.
10. Summarize what was removed and what remains.

## Guardrails

- Treat cleanup as destructive and require explicit confirmation.
- Never delete an unmerged branch.
- Remove a remote branch only when step 5 proposed it and the user confirmed it, or when the user explicitly asks.
- This skill cleans up only the local branch, the local worktree, the remote branch confirmed in step 6, and confirmed runtime resources covered by `../worktree-runtime-cleanup/SKILL.md`.
- Never assume the current branch is disposable just because the prompt says "merged."
- If git refuses removal because the worktree is busy or dirty, stop and report the exact blocker.
