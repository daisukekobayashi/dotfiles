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
6. Claim each actionable bead before editing:
   - `bd update <id> --claim`
7. Prepare the isolated workspace using **Worktree Preparation** below.
8. In the worktree, verify baseline before implementation.
   - Use repo docs and `execution-context-first-repo-onboarding` to choose the smallest relevant documented test/build check.
   - If baseline fails, report the failure and ask before proceeding.
   - If checks are unavailable, report the limitation without claiming a clean baseline.
9. Report bead summary, branch, worktree path, base commit, baseline command/result, and next implementation step. Include these details in each worker handoff.

## Worktree Preparation

Use Beads or Git directly; no separate worktree skill is required.

1. Inspect `git status --short` and `git worktree list --porcelain` before changing workspace state. Reuse a worktree only when its branch, changes, and ownership match this bead and no other worker is using it.
2. Resolve the base from the user's request or repository convention. Otherwise inspect the default branch and local branch state, asking only if the intended base remains ambiguous. Do not assume a local ref is current or silently branch from another bead's branch. Record the chosen base ref and commit.
3. Choose the path by user preference, then repository instructions or an established worktree directory, then `.worktrees/<bead-id>-<slug>`. Check path and branch collisions without overwriting or repurposing another bead's workspace.
4. Before project-local creation, verify the actual target path with `git check-ignore`. Resolve missing ignore configuration under repository change and approval rules before creation; do not automatically commit that change. External locations do not need this check.
5. Follow applicable approval rules, honoring existing authorization for this bead's worktree. Prefer `bd worktree create` when it supports the required base, branch, and path; consult installed CLI help for supported options. Otherwise use `git worktree add -b <branch> <path> <base>`. Verify the resulting path and dedicated bead branch before implementation.
6. Read instructions in the selected worktree and run its documented setup. Use `execution-context-first-repo-onboarding` if commands are unclear; do not infer install commands solely from manifest filenames. Restore dependencies only as repository rules permit, without modifying manifests or lockfiles.

If creation fails, diagnose and report it; do not silently implement in the
original checkout. Obtain required approval before removing worktrees or branches
during cleanup.

## Multiple Beads

Create separate worktrees only when the beads touch mostly separate subsystems, have no dependency relationship, and do not share schema/config/workflow decisions. Otherwise recommend a sequential order.

For parallel work, each worker owns exactly one bead and one worktree. Do not let two workers edit the same worktree.

## Guardrails

- Do not commit, merge, push, close, or delete anything unless explicitly asked.
- Do not create a worktree for blocked or closed beads.
- Do not combine multiple beads into one branch unless the user explicitly approves.
- Preserve dirty worktree changes in the main checkout; do not revert user-owned changes.
- If worktree creation partially fails, inspect state before retrying.
