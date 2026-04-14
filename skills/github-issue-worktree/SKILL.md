---
name: github-issue-worktree
description: Use when the user wants to start work from one or more GitHub issue numbers in the current repository, review the issue context, decide whether they belong together, and continue in a new isolated worktree.
---

# GitHub Issue Worktree

## Workflow

1. Resolve the current repo from local git context and parse every `#<issue>` in the prompt.
2. Fetch the issue metadata with the GitHub plugin.
3. Summarize each issue in 1-2 lines and decide whether the issues belong in one branch.
4. If they are clearly unrelated, stop and recommend splitting the work instead of creating one shared worktree.
5. If they belong together, choose a branch name:
   - single issue: `type/<id>-<slug>`
   - multiple issues: `type/<id1>-<id2>-<slug>`
   - use a conventional-commit-style branch prefix such as `fix`, `feat`, or `chore`
   - use `fix` for bug fixes, `feat` for new user-facing behavior, and `chore` for maintenance or internal cleanup
6. Invoke `using-git-worktrees` to create the isolated workspace.
7. Continue work in that worktree. If repo-specific commands are unclear, use `execution-context-first-repo-onboarding` before picking test, build, or dev commands.
8. Report the issue grouping decision, the chosen name, the worktree path, and the next implementation step.

## Guardrails

- Do not assume cross-repository work. This skill is current-repo only.
- If the prompt does not include at least one issue number, stop and ask for one.
- Do not commit or push without explicit approval.
- Do not install dependencies or edit dependency manifests or lockfiles without explicit approval.
- If setup, tests, or worktree creation fails, stop and report the failure before proceeding.
- Do not force unrelated issues into one branch just because the user listed them together.
