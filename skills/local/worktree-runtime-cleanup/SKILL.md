---
name: worktree-runtime-cleanup
description: Stop Docker Compose stacks left running by a worktree, or by worktrees that no longer exist.
disable-model-invocation: true
---

# Worktree Runtime Cleanup

A Compose stack outlives the worktree that started it: `docker compose run --rm`
removes only the run container and leaves `depends_on` services up, and a
wrapper killed by a tool timeout never reaches its `down` trap. This skill ties
the stack's lifetime back to the worktree.

Worktree cleanup skills (`github-worktree-cleanup`,
`azure-devops-worktree-cleanup`, `beads-merge-cleanup`) read this file and run
it for the worktree they are about to remove.

## Workflow

1. Resolve the target and list its stacks with `scripts/list-stacks.sh` in this
   skill's directory. The script only reads Docker state.
   - A worktree path given: `list-stacks.sh <path>`.
   - No argument: `list-stacks.sh` targets the current worktree root.
   - `--stale` given: `list-stacks.sh --stale` lists stacks whose `working_dir`
     is missing or is not a registered worktree, across every repository.
2. If nothing is listed, report that and stop.
3. Show the listed stacks (project, running/total, `working_dir`, reason) and
   get explicit confirmation for each project to stop.
   - When the target is a primary checkout (the one that owns `.git`) or the
     list came from `--stale`, the stacks may belong to other sessions: list
     them and let the user choose, with no pre-selected default.
4. Run `docker compose -p <project> down --remove-orphans` for each confirmed
   project. Volumes stay; add `--volumes` only when the user asks to delete
   data.
5. Re-run the same `list-stacks.sh` command and report what stopped and what
   remains.

Run this before `git worktree remove`: the `working_dir` label still points to
a live worktree then, so the stacks are matched by path rather than by the
weaker `--stale` reasons.
