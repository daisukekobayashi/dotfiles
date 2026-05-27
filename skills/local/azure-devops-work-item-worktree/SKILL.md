---
name: azure-devops-work-item-worktree
description: Use when the user wants to start implementation from one or more Azure DevOps Work Item IDs in the current repository.
---

# Azure DevOps Work Item Worktree

## Scope

Start Azure DevOps Work Item work from the current repository by creating
isolated worktrees. A single directly actionable Work Item gets one branch and
worktree. Multiple Work Items get separate worktrees only when they are safe to
parallelize.

Read `../azure-devops-common/references/context.md` before fetching Work Items.

## Workflow

1. Resolve the current Azure DevOps organization, project, repository, and parse
   every Work Item ID in the prompt.
2. Fetch Work Item metadata with `az boards work-item show --id <id> --expand all`.
3. Summarize and classify each Work Item:
   - directly actionable implementation work
   - parent/tracking item
   - blocked or dependent on another Work Item or PR
   - ambiguous and needing clarification
4. For each directly actionable Work Item, choose a branch name:
   - format: `type/<id>-<slug>`
   - use `fix` for bugs, `feat` for user-facing behavior, and `chore` for
     maintenance or internal cleanup.
5. If exactly one Work Item was provided:
   - Invoke `using-git-worktrees` once.
   - Continue in that worktree.
   - Use `execution-context-first-repo-onboarding` before choosing test, build,
     or dev commands when repo workflow is unclear.
6. If multiple Work Items were provided:
   - Stop before creating worktrees unless the set is safe to parallelize.
   - Treat items as safe only when they touch separate subsystems, have no
     ordering dependency, and do not require the same schema, config, workflow,
     or policy decision.
   - Create one worktree per safe Work Item and keep worker ownership separate.

## Guardrails

- Do not assume cross-project Work Items.
- If no Work Item ID is provided, stop and ask for one.
- Do not commit or push without explicit approval.
- Do not install dependencies or edit dependency manifests or lockfiles without
  explicit approval.
- If setup, tests, or worktree creation fails, stop and report the failure.
- Do not close, update, assign, tag, transition, or comment on Work Items unless
  the user explicitly asks.
