---
name: azure-devops-pr
description: Use only when the user explicitly invokes `$azure-devops-pr` or names `azure-devops-pr` for creating or resolving an Azure DevOps pull request from the current branch.
---

# Azure DevOps PR

## Scope

Use this skill to create or resolve an Azure DevOps pull request from the
current branch. This skill does not commit, push, request reviewers, vote,
complete, merge, or edit implementation files.

Read `../azure-devops-common/references/context.md` before resolving the target.

## Workflow

1. Resolve repository context.
   - Confirm `git status --short --branch`.
   - Resolve the current branch and default branch.
   - Resolve Azure DevOps organization, project, and repository.
   - Stop if the current branch is the default branch.
2. Find an optional PR template:
   - `docs/agents/azure-devops-pr-template.md`
   - `.azuredevops/PULL_REQUEST_TEMPLATE.md`
   - `.azuredevops/pull_request_template.md`
   - If no template exists, use a minimal body with summary and verification.
3. Build the PR body in a temporary file.
   - Preserve selected template headings and checklist structure.
   - Fill only facts supported by the current diff, commits, issue context, or
     verification logs.
   - Leave unknown fields as clear placeholders.
   - Apply the Work Item link and state-transition rules from the Azure DevOps
     common context. Link Work Items when appropriate, but use transition
     keywords such as `Fixes #123`, `Closes #123`, or `Resolves #123` only when
     the PR fully completes that Work Item and the user wants it to transition.
   - Use `Refs #123` for parent trackers, partial work, follow-ups, or
     context-only Work Items.
4. Avoid duplicate PRs.
   - Use `az repos pr list` to check for an active PR from the current source
     branch to the selected target branch.
   - If one exists, return it and do not create another.
5. Create the PR.
   - Use the repository default branch unless the user specifies another target.
   - Use `az repos pr create`.
   - Pass Work Item IDs through the Azure DevOps PR work-item link mechanism
     when the IDs are known and the PR implements them; do not rely only on body
     text when a structured PR Work Item link is available.
6. Verify with `az repos pr show` and report the PR URL and whether it was new
   or existing.

## Guardrails

- Do not commit, push, complete, merge, vote, approve, or request reviewers.
- Do not create duplicate PRs.
- Do not modify repository files while preparing the PR body.
- Stop if Azure DevOps target resolution is ambiguous.
