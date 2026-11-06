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
   - Stop and report the branch unless it is a **safe branch name**, using only `[A-Za-z0-9/._-]`, before running any command with it.
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
6. Show the exact resources that would be removed, including any proposed remote branch with its remote and SHA, and require explicit confirmation. A caller's combined confirmation from [Caller preview](#caller-preview) counts only when the user gave it in their own message for exactly these resources; on any difference, show them and ask again.
7. Remove the local worktree first when one exists. If you are inside it, change to a safe location before removal.
   - Before removal, follow `../worktree-runtime-cleanup/SKILL.md` for the worktree path. If that file is absent, say so in the summary.
8. Delete the local branch after the worktree is removed.
9. Delete the confirmed remote branch last, conditioned on the checked SHA:
   `git push --force-with-lease=refs/heads/<branch>:<sha> <remote> :refs/heads/<branch>`.
   If the lease is rejected, keep the branch and report that it changed.
10. Summarize what was removed and what remains.

## Caller preview

When a delivery caller combines the merge and cleanup confirmations, it asks for a preview before the merge. Run steps 1-2, list the runtime resources `../worktree-runtime-cleanup/SKILL.md` would stop for the worktree path using only its read-only listing, and check step 5's conditions other than the merged state, taking the PR head SHA to be merged as the expected remote SHA. Return the worktree path, local branch, proposed remote branch with its remote and expected SHA, and runtime resources. Remove and stop nothing. After the merge, run the full workflow; the resources step 6 shows must match the preview exactly, and the remote SHA must equal both the expected SHA and the PR's merged `headRefOid`.

## Guardrails

- Treat cleanup as destructive and require explicit confirmation.
- Never delete an unmerged branch.
- Remove a remote branch only when step 5 proposed it and the user confirmed it, or when the user explicitly asks.
- This skill cleans up only the local branch, the local worktree, the remote branch confirmed in step 6, and confirmed runtime resources covered by `../worktree-runtime-cleanup/SKILL.md`.
- Never assume the current branch is disposable just because the prompt says "merged."
- If git refuses removal because the worktree is busy or dirty, stop and report the exact blocker.
