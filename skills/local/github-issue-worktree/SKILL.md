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
   - Invoke `using-git-worktrees` once to create the isolated workspace.
   - Continue work in that worktree. If repo-specific commands are unclear, use `execution-context-first-repo-onboarding` before picking test, build, or dev commands.
   - Report the issue summary, branch name, worktree path, and next implementation step.
6. If multiple issues were provided:
   - Decide whether the issues are safe to run in parallel before creating worktrees.
   - Treat issues as safe to parallelize only when they appear to touch separate subsystems, have no ordering dependency, and do not require the same schema/config/workflow decisions.
   - If any issue is blocked, ambiguous, a parent tracker, or likely to conflict with another requested issue, stop before creating worktrees. Report the unsafe grouping and recommend a sequential order or a smaller safe parallel subset.
   - For every safe issue, invoke `using-git-worktrees` separately and create one branch/worktree per issue.
   - Dispatch one worker per issue/worktree. Each worker owns only its assigned worktree and issue scope.
   - Continue coordinating the workers in parallel, then review and integrate their results when they finish.
   - Report the parallelization decision, each issue summary, branch name, worktree path, worker assignment, and expected next checkpoint.

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
- Do not install dependencies or edit dependency manifests or lockfiles without explicit approval.
- If setup, tests, or worktree creation fails, stop and report the failure before proceeding with additional worktrees or workers.
- Do not combine multiple requested issues into one branch just because the user listed them together.
- Do not dispatch parallel workers for issues with known ordering dependencies, shared migrations, shared schema decisions, or likely edits to the same files.
- Do not close, label, assign, or comment on issues unless the user explicitly asks.
