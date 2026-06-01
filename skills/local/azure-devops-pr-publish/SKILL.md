---
name: azure-devops-pr-publish
description: Use only when the user explicitly invokes `$azure-devops-pr-publish` or names `azure-devops-pr-publish` for publishing local Azure DevOps branch or worktree changes as a pull request.
---

# Azure DevOps PR Publish

## Scope

Use this orchestration skill to publish one or more local branches or worktrees
as Azure DevOps pull requests. It covers the normal path from local changes to a
remote PR: inspect state, verify, commit when needed, push, and create or reuse
the PR.

Read `../azure-devops-common/references/context.md` before resolving targets.

## Approval Model

Because this skill only runs when explicitly invoked or named, treat that
request as approval for ordinary non-destructive commits and normal pushes for
the requested target branches.

Still stop and ask before:

- force push, branch deletion, reset, rebase, amend, or merge
- staging secret-like files, credentials, private keys, or local-only config
- staging unrelated files
- staging or publishing dependency manifests or lockfiles without explicit
  approval
- publishing from the default branch
- completing PRs, enabling auto-complete, changing policies, voting, approving,
  or requesting reviewers

## Workflow

1. Resolve targets from the user request. If none is specified, use the current
   worktree and branch.
2. Resolve Azure DevOps organization, project, repository, default branch, and
   current branch for each target.
3. Inspect local state:
   - `git status --short --branch`
   - `git diff --stat`
   - `git diff --check`
   - `git log --oneline <default-branch>..HEAD` when available
4. Stop if there is no publishable work.
5. Confirm recent verification.
   - Use a successful verification log from the current conversation only if it
     happened after the latest changes.
   - Otherwise determine and run the repository's required verification command.
   - Stop if verification fails.
6. Commit when needed.
   - Use the `git-commit` skill.
   - Stage only files belonging to the requested work.
7. Push normally to the Azure DevOps remote for the current branch.
8. Use `azure-devops-pr` to create or resolve the PR.
   - That skill should apply the Azure DevOps common Work Item link and
     state-transition rules: structured Work Item links for implemented Work
     Items, transition keywords only for fully completed Work Items, and
     `Refs #123` for parent trackers, partial work, follow-ups, or context.
9. Verify with `az repos pr show` and report branch, commit, push target, PR URL,
   and verification result.

## Guardrails

- Do not continue to later targets after a verification, commit, push, or PR
  creation failure.
- Do not create PRs from the default branch.
- Do not force push, rewrite history, merge, complete, or clean up worktrees.
- Do not hardcode or print secrets while summarizing diffs, commits, or templates.
