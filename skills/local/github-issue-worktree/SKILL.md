---
name: github-issue-worktree
description: Use when the user wants to start implementation from one or more GitHub issue numbers in the current repository, especially requests involving multiple issue IDs, separate workstreams, parallel issue work, or isolated issue worktrees.
---

# GitHub Issue Worktree

## Overview

Start GitHub issue work from the current repository by creating isolated
worktrees. A single issue gets one branch/worktree. Multiple issues are treated
as separate work items: create one branch/worktree per issue and run them in
parallel only after confirming the issues are independent enough to work safely.

## Workflow

1. Resolve the current repo from local git context and parse every `#<issue>` in the prompt.
2. Fetch the issue metadata with the GitHub plugin.
3. Summarize each issue in 1-2 lines and classify it:
   - directly actionable implementation work
   - parent/tracking issue
   - blocked or dependent on another issue/PR
   - ambiguous and needing user clarification
4. For each directly actionable issue, choose a branch name:
   - format: `type/<id>-<slug>`
   - use a conventional-commit-style branch prefix such as `fix`, `feat`, or `chore`
   - use `fix` for bug fixes, `feat` for new user-facing behavior, and `chore` for maintenance or internal cleanup
5. If exactly one issue was provided:
   - Prepare the issue workspace using **Worktree Preparation** below.
   - Continue implementation in that worktree.
   - Report the issue summary, branch name, worktree path, baseline check result, and next implementation step.
6. If multiple issues were provided:
   - Decide whether the issues are safe to run in parallel before creating worktrees.
   - Treat issues as safe to parallelize only when they appear to touch separate subsystems, have no ordering dependency, and do not require the same schema/config/workflow decisions.
   - If any issue is blocked, ambiguous, a parent tracker, or likely to conflict with another requested issue, stop before creating worktrees. Report the unsafe grouping and recommend a sequential order or a smaller safe parallel subset.
   - For every safe issue, follow **Worktree Preparation** separately, keeping one branch/worktree per issue.
   - Dispatch one worker per issue/worktree. Each worker owns only its assigned worktree and issue scope.
   - Continue coordinating the workers in parallel, then review and integrate their results when they finish.
   - Report the parallelization decision, each issue summary, branch name, worktree path, baseline check result, worker assignment, and expected next checkpoint.

## Worktree Preparation

Use the available worktree tools or ordinary Git commands directly; no separate
worktree skill is required.

1. Inspect `git status --short` and `git worktree list --porcelain` before changing state. Reuse an existing worktree only when its branch, changes, and ownership match this issue and no other worker is using it. Being in a linked worktree alone does not establish that it belongs to this issue.
2. For a new workspace, resolve the starting commit from the user's requested base or the repository's documented convention. If neither identifies a base, inspect the default branch and local branch state; ask only if the intended base remains ambiguous. Do not silently branch from another issue's branch or assume a local ref is current. Record the chosen base ref and commit.
3. Prefer an available native worktree tool when it supports the required base and dedicated issue branch; otherwise plan to use Git directly. For manual creation, choose the location by explicit user preference, then repository instructions or an established worktree directory, then `.worktrees/` at the repository root. Check for path and branch collisions; do not overwrite, force checkout, or repurpose another issue's workspace.
4. Before creating a project-local worktree, verify the actual target path is ignored with `git check-ignore`. If it is not, resolve the ignore configuration under the repository's change and approval rules before creation. Do not automatically commit an ignore change. External worktree locations do not need this check.
5. Follow applicable approval rules, honoring authorization already given for this issue's worktree, then create it with the selected tool or `git worktree add -b <branch> <path> <base>`. Verify the resulting path and branch; a detached workspace still needs an issue branch before implementation.
6. Read the instructions in the selected worktree and run its documented setup. If commands are unclear, use `execution-context-first-repo-onboarding`. Do not infer an install command solely from a manifest filename. Restore dependencies only as permitted by repository rules, using existing manifests and lockfiles without modifying them.
7. Run the smallest relevant documented baseline check before editing. Report the command and result, including existing failures or unavailable checks; do not claim a clean baseline when verification was blocked. Include the worktree path, branch, and base commit in the handoff.

If workspace creation fails, diagnose and report it; do not silently switch to
implementation in the original checkout. Keep unrelated changes in their
original workspace, and obtain required approval before removing worktrees or
branches during cleanup.

## Parallel Worker Rules

Give each worker a focused prompt with:

- the GitHub issue number, title, URL, and concise summary
- the assigned branch name and worktree path
- the repository guardrails from this skill and local project instructions
- clear ownership: work only inside the assigned worktree and only on the assigned issue
- a reminder that other workers may be active in sibling worktrees, so do not revert or edit outside the assigned scope
- the expected return format: status, files changed, tests run, blockers, and any follow-up needed

Do not use one worker for all requested issues. Do not let multiple workers edit
the same worktree. If a worker reports that its issue depends on another active
issue, pause that worker and report the dependency instead of forcing progress.

## Guardrails

- Do not assume cross-repository work. This skill is current-repo only.
- If the prompt does not include at least one issue number, stop and ask for one.
- Do not commit or push without explicit approval.
- Dependency changes and manifest or lockfile edits require explicit approval; restoration from existing manifests and lockfiles follows repository rules.
- If setup, tests, or worktree creation fails, stop and report the failure before proceeding with additional worktrees or workers.
- Do not combine multiple requested issues into one branch just because the user listed them together.
- Do not dispatch parallel workers for issues with known ordering dependencies, shared migrations, shared schema decisions, or likely edits to the same files.
- Do not close, label, assign, or comment on issues unless the user explicitly asks.
