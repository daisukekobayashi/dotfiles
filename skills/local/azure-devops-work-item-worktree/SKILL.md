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
   - Follow **Worktree Preparation** below, then implement in that worktree.
6. If multiple Work Items were provided:
   - Stop before creating worktrees unless the set is safe to parallelize.
   - Treat items as safe only when they touch separate subsystems, have no
     ordering dependency, and do not require the same schema, config, workflow,
     or policy decision.
   - Follow **Worktree Preparation** for each safe Work Item, keeping one branch
     and worktree per item with separate worker ownership.
7. Report each Work Item summary, branch, worktree path, base commit, baseline
   command/result, worker assignment when applicable, and next implementation step.

## Worktree Preparation

Use available worktree tools or Git directly; no separate worktree skill is required.

1. Inspect `git status --short` and `git worktree list --porcelain` before changing
   state. Reuse a worktree only when its branch, changes, and ownership match this
   Work Item and no other worker is using it.
2. Resolve the base from the user's request or repository convention. Otherwise
   inspect the default branch and local branch state, asking only if the intended
   base remains ambiguous. Do not assume a local ref is current or silently branch
   from another Work Item's branch. Record the chosen base ref and commit.
3. Prefer an available native worktree tool that supports the required base and
   dedicated branch; otherwise use Git. For manual creation, choose the location
   by user preference, then repository instructions or an established worktree
   directory, then `.worktrees/` at the repository root. Check path and branch
   collisions without overwriting or repurposing another item's workspace.
4. Before project-local creation, verify the actual target path with
   `git check-ignore`. Resolve missing ignore configuration under repository change
   and approval rules before creation; do not automatically commit that change.
   External locations do not need this check.
5. Follow applicable approval rules, honoring existing authorization for this
   Work Item's worktree, then use the selected tool or
   `git worktree add -b <branch> <path> <base>`. Verify the resulting path and branch;
   a detached workspace needs a dedicated Work Item branch before implementation.
6. Read instructions in the selected worktree and use documented setup commands.
   Use `execution-context-first-repo-onboarding` when commands are unclear. Do not
   infer install commands solely from manifest filenames. Restore dependencies
   only as repository rules permit, without modifying manifests or lockfiles.
7. Run the smallest relevant documented baseline check before editing. Report
   existing failures or unavailable checks without claiming a clean baseline.
   Include the path, branch, base commit, and check result in each worker handoff.

If creation fails, diagnose and report it; do not silently implement in the
original checkout. Preserve unrelated changes in their original workspace and
obtain required approval before removing worktrees or branches during cleanup.

## Guardrails

- Do not assume cross-project Work Items.
- If no Work Item ID is provided, stop and ask for one.
- Do not commit or push without explicit approval.
- Dependency changes and manifest or lockfile edits require explicit approval;
  restoration from existing manifests and lockfiles follows repository rules.
- If setup, tests, or worktree creation fails, stop and report the failure.
- Do not close, update, assign, tag, transition, or comment on Work Items unless
  the user explicitly asks.
