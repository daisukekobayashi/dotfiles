---
name: beads-issue-worktree
description: Start implementation work from one or more Beads issue IDs in the current repository using isolated git worktrees and branches. Use when the user asks to work on a bead, start a bd issue, create a branch/worktree for a bead, or run multiple independent Beads workstreams.
---

# Beads Issue Worktree

## Overview

Start Beads issue work safely from the current repository. A single actionable bead gets one branch/worktree. Multiple beads get separate worktrees only when they are independent enough to work in parallel.

## Workflow

1. Run `bd prime`; if needed, run `bd where`.
2. Resolve bead IDs from the user prompt. If no ID is provided, run `bd ready` and ask which ready bead to start.
3. Inspect every target:
   - `bd show <id>`
   - classify as actionable, parent/tracker, blocked, already in progress, or ambiguous.
4. Stop before creating worktrees if a bead is blocked, closed, a parent tracker, ambiguous, or likely to conflict with another requested bead.
5. Choose branch/worktree names for actionable beads.
   - Branch format: `<type>/<bead-id>-<slug>`.
   - Use `fix` for bugs, `feat` for features, `chore` for maintenance/internal workflow.
   - Worktree path should live under `.worktrees/<bead-id>-<slug>` when project-local worktrees are used.
6. Claim each actionable bead before editing:
   - `bd update <id> --claim`
7. Create an isolated workspace.
   - Invoke `using-git-worktrees` if available.
   - Prefer `bd worktree create` when it supports the needed branch shape.
   - Fall back to `git worktree add -b <branch> <path> <base>` when needed.
   - Before project-local worktrees, verify `.worktrees/` or `worktrees/` is ignored.
8. In the worktree, verify baseline before implementation.
   - Use repo docs and `execution-context-first-repo-onboarding` to choose the test/build command.
   - If baseline fails, report the failure and ask before proceeding.
9. Report bead summary, branch, worktree path, baseline command/result, and next implementation step.

## Multiple Beads

Create separate worktrees only when the beads touch mostly separate subsystems, have no dependency relationship, and do not share schema/config/workflow decisions. Otherwise recommend a sequential order.

For parallel work, each worker owns exactly one bead and one worktree. Do not let two workers edit the same worktree.

## Guardrails

- Do not commit, merge, push, close, or delete anything unless explicitly asked.
- Do not create a worktree for blocked or closed beads.
- Do not combine multiple beads into one branch unless the user explicitly approves.
- Preserve dirty worktree changes in the main checkout; do not revert user-owned changes.
- If worktree creation partially fails, inspect state before retrying.
