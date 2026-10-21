---
name: azure-devops-pr-create
description: Use only when the user explicitly requests azure-devops-pr-create, or azure-devops-pr-publish delegates PR creation for an explicitly user-requested publication workflow. Create or resolve an Azure DevOps PR without committing, pushing, or requesting review.
---

# Azure DevOps PR Create

## Scope

Use this skill to create or resolve an Azure DevOps pull request from the
current branch. This skill does not commit, push, request reviewers, vote,
complete, merge, or edit implementation files.

Read `../azure-devops-common/references/context.md` before resolving the target.

A delegated caller must forward the user's actual publication request, exact
target, and existing authorizations. A reference to this skill alone does not
authorize PR creation or updates.

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
   - Apply [Work Item Links And State Transitions](../azure-devops-common/references/context.md#work-item-links-and-state-transitions)
     when preparing the body and selecting Work Item links.
4. Avoid duplicate PRs.
   - Use `az repos pr list` to check for an active PR from the current source
     branch to the selected target branch in the resolved repository.
   - If one exists, verify it with `az repos pr show`, check its Work Item links,
     and add only missing links authorized by this publication request. Preserve
     existing content and unrelated links; return the PR without creating another.
   - If multiple PRs match, stop and report the ambiguity.
   - After an uncertain create result, search again before retrying creation.
5. Create the PR.
   - Use the repository default branch unless the user specifies another target.
   - Use `az repos pr create`, applying the Work Item links selected in step 3.
6. Verify with `az repos pr show` and report the PR URL and whether it was new
   or existing.

## Guardrails

- Do not commit, push, complete, merge, vote, approve, or request reviewers.
- Do not create duplicate PRs.
- Do not modify repository files while preparing the PR body.
- Stop if Azure DevOps target resolution is ambiguous.
