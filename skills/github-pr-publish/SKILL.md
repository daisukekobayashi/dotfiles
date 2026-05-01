---
name: github-pr-publish
description: Use only when the user explicitly invokes `$github-pr-publish` or names `github-pr-publish` for publishing local GitHub branch or worktree changes as a pull request without requesting AI review.
---

# GitHub PR Publish

## Scope

Use this orchestration skill to publish one or more local branches or worktrees
as GitHub pull requests. It covers the normal path from local changes to a
remote PR: inspect state, verify, commit when needed, push, and create or reuse
the PR. Pull request templates are optional; use them when present and fall
back to a minimal generic PR body when absent.

This skill is not for:
- implementing feature changes before publication
- applying review feedback
- requesting AI, Copilot, Codex, or human review
- merging pull requests
- deleting branches or worktrees
- force pushing
- cleaning up after merge

## Approval Model

Because this skill only runs when the user explicitly invokes or names it,
treat that request as approval for ordinary non-destructive commits and normal
pushes for the requested target branches.

Still stop and ask before any action outside that narrow scope, including:

- force push, branch deletion, reset, rebase, amend, or merge
- staging secret-like files, credentials, tokens, private keys, or local-only config
- staging unrelated files that are not part of the requested work
- staging or publishing dependency manifests or lockfiles when the user did not explicitly ask for those changes
- publishing from the default branch

## Workflow

1. Resolve targets.
   - Identify each branch or worktree requested by the user.
   - If no target is specified, use the current worktree and branch.
   - For multiple targets, process them sequentially and stop on the first failure.
2. Resolve repository context for each target.
   - Confirm the target is inside a git repository.
   - Resolve the current branch with `git branch --show-current`.
   - Resolve the remote repository with `gh repo view --json nameWithOwner,url,defaultBranchRef`.
   - Stop if the current branch is the default branch.
3. Inspect local state before changing anything.
   - Run `git status --short --branch`.
   - Run `git diff --stat`.
   - Run `git diff --check`.
   - If `git diff --check` fails, stop and report the whitespace or conflict-marker problem.
   - Run `git log --oneline <default-branch>..HEAD` when the default branch is available locally.
   - Look for untracked or modified secret-like files such as `.env`, credentials, tokens, private keys, or local config. Do not stage them; stop or ask when they affect the requested commit.
   - Separate requested work from unrelated local changes. Do not stage unrelated files.
4. Confirm there is publishable work.
   - If the branch has no commits ahead of the base and no working tree changes for the requested work, stop and report that there is nothing to publish.
   - If there are working tree changes for the requested work, plan one logical commit from the implementation diff and the current conversation context.
   - If the branch already has suitable commits and no requested working tree changes, skip committing.
5. Confirm recent verification.
   - If the current conversation already has a successful verification log after the target's latest code changes, use it.
   - Otherwise determine the repository's required verification command from local guidance and run it before committing.
   - If the required verification command is not discoverable, ask the user which command to run before publishing.
   - If verification fails, stop that target and report the likely cause without committing, pushing, or creating a PR.
6. Commit when needed.
   - Use the `git-commit` skill for staging and commit message generation.
   - Stage only files belonging to the requested work.
   - Derive the commit message from the implementation diff, issue context, branch name, and current conversation.
   - Never stage secrets or unrelated local files.
7. Push the branch.
   - Use a normal push to the repository remote for the current branch.
   - If no upstream exists, set upstream for the same branch name.
   - Do not force push, delete remote branches, or rewrite history.
8. Create or resolve the PR.
   - Use the `github-pr` skill for the target branch.
   - That skill should use a pull request template when present and a minimal generic body when no template exists.
   - Reuse an existing PR when one already exists for the branch.
9. Verify and report the result.
   - Run `gh pr view --json number,url,title,state,baseRefName,headRefName`.
   - Report the branch, commit SHA if one was created, push target, PR URL, whether the PR was new or existing, and the verification command/result.

## Output Format

Use this structure:

```markdown
**Published**
- Branch: `<branch>`
- Commit: `<sha>` or "No new commit needed"
- Push: `<remote>/<branch>`
- PR: <url>
- Verification: `<command>` passed

**Notes**
- <any skipped files, existing PR reuse, or follow-up needed>
```

For multiple targets, repeat the same fields per target.

## Guardrails

- Do not proceed to commit, push, or PR creation until verification has succeeded for the target's latest changes.
- Do not continue to later targets after a verification, commit, push, or PR creation failure.
- Do not create a PR from the default branch.
- Do not create duplicate PRs for a branch that already has one.
- Do not force push, merge, delete remote branches, rewrite history, or clean up worktrees.
- Do not stage dependency manifests or lockfiles, edit them, or install dependencies unless the user explicitly asks.
- Do not hardcode or print secrets while summarizing diffs, commits, or templates.
- Do not request AI, Copilot, Codex, or human review.
