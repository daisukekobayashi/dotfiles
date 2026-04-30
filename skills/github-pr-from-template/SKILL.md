---
name: github-pr-from-template
description: Use only when the user explicitly invokes `$github-pr-from-template` or names `github-pr-from-template`. Do not use for generic PR creation, commit, push, or review requests.
---

# GitHub PR From Template

## Scope

Use this skill to create a GitHub pull request from the current branch while
respecting the repository's pull request template.

This skill is not for:
- committing changes
- pushing branches
- requesting AI, Copilot, Codex, or human review
- merging pull requests
- editing implementation files

## Workflow

1. Resolve repository context.
   - Confirm the working directory is inside a git repository.
   - Resolve the current branch with `git branch --show-current`.
   - Resolve the remote repository with `gh repo view --json nameWithOwner,defaultBranchRef`.
   - Stop if the current branch is the default branch.
2. Find the pull request template.
   - Check these paths in order:
     - `.github/pull_request_template.md`
     - `.github/PULL_REQUEST_TEMPLATE.md`
     - `.github/PULL_REQUEST_TEMPLATE/*.md`
   - If multiple files exist under `.github/PULL_REQUEST_TEMPLATE/` and the right one is not obvious from the user request, stop and ask which template to use.
   - If no template exists, use a minimal generic body with summary and test sections.
3. Build the PR body in a temporary file.
   - Preserve the selected template headings and checklist structure.
   - Fill only facts supported by the current diff, commits, or verification logs.
   - Leave unknown template fields as clear placeholders instead of inventing details.
4. Avoid duplicate PRs.
   - Run `gh pr view --json number,url,state,headRefName,baseRefName` on the current branch.
   - If a PR already exists, return that PR and do not create another one.
5. Create the PR.
   - Use the repository default branch as the base unless the user specifies another base.
   - Use `gh pr create --base <base> --head <branch> --body-file <tmp-file>`.
   - If a title is not provided, derive a concise title from the branch name and recent commits.
6. Verify the result.
   - Run `gh pr view --json number,url,title,state,baseRefName,headRefName`.
   - Report the PR URL and whether it was newly created or already existed.

## Guardrails

- Do not commit, push, merge, or request reviews.
- Do not create a duplicate PR for a branch that already has one.
- Do not hardcode or print secrets while summarizing diffs or templates.
- Do not modify repository files while preparing the PR body.
- If GitHub authentication, permissions, or branch publication blocks PR creation, report the blocker and stop.
