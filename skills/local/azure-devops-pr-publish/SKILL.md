---
name: azure-devops-pr-publish
description: Use only when the user explicitly requests azure-devops-pr-publish, or its publication phase through azure-devops-work-item-delivery, for specified local Azure DevOps branches or worktrees. Publish as a PR without requesting AI review.
---

# Azure DevOps PR Publish

## Scope

Use this orchestration skill to publish one or more local branches or worktrees
as Azure DevOps pull requests. It covers the normal path from local changes to a
remote PR: inspect state, verify, commit when needed, push, and create or reuse
the PR.

Read `../azure-devops-common/references/context.md` before resolving targets.

## Approval Model

An explicit publication request can arrive directly or through
`azure-devops-work-item-delivery`. A delegated caller must forward the actual
user request, exact target, and existing authorizations; a skill reference or
automatic selection is insufficient. Subject to governing approval instructions,
treat that request as approval for ordinary non-destructive commits and normal
pushes for the requested target branches. Prepare the verified publication target
before asking for any missing approval.

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
   - Before pushing, inspect any matching active PR for enabled auto-complete.
     If enabled, hold publication for an explicit decision: a push could merge
     the PR before separate merge approval. Do not silently disable it.
6. Commit when needed.
   - Use the `git-commit` skill.
   - Stage only files belonging to the requested work.
7. Push normally to the Azure DevOps remote for the current branch.
8. Use `azure-devops-pr-create` to create or resolve the PR.
   - Pass along the actual publication request, exact target, existing approvals,
     known Work Item IDs, completion scope, and the user's state-transition intent.
9. Verify with `az repos pr show` and report branch, commit, push target, PR URL,
   and verification result.

## Guardrails

- Do not continue to later targets after a verification, commit, push, or PR
  creation failure.
- Do not create PRs from the default branch.
- Do not force push, rewrite history, merge, complete, or clean up worktrees.
- Do not hardcode or print secrets while summarizing diffs, commits, or templates.
