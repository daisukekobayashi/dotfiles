---
name: beads-issue-triage
description: Use only when the user explicitly invokes `$beads-issue-triage` or names `beads-issue-triage` to triage Beads issues in the current repository before implementation.
---

# Beads Issue Triage

## Scope

Use this skill to recommend which Beads issue to handle next, which issues are blocked, and which issues can be worked on in parallel. This skill is read-only and does not start implementation.

Use `bd` as the source of truth. Do not create markdown TODO files for work tracking when Beads is available.

## Workflow

1. Resolve the current Beads workspace.
   - Run `bd prime`; if it prints nothing, run `bd where`.
   - Confirm local branch and dirty state with `git status --short --branch`.
2. Fetch candidate issues.
   - Start with `bd ready`.
   - Also run `bd list --status=open` to see blocked, parent, and in-progress work.
   - For plausible candidates, inspect details with `bd show <id>`.
3. Read local repository guidance before ranking.
   - Check project instructions such as `AGENTS.md`.
   - Check product, roadmap, or workflow docs if present, commonly `README.md`, `docs/*.md`, or `WORKFLOW.md`.
4. Classify candidate issues.
   - directly actionable implementation issue
   - blocked by another issue
   - parent, epic, or tracking issue
   - already in progress or claimed
   - future-scope, out-of-scope, duplicate, or ambiguous work
5. Rank actionable issues.
   - Prefer issues that unblock later work.
   - Prefer clear acceptance criteria, moderate blast radius, and alignment with repository guidance.
   - Defer broad, ambiguous, high-risk, or policy-setting issues unless explicitly prioritized.
6. Identify safe parallel candidates.
   - Recommend parallel work only when issues touch separate subsystems and have no dependency relationship.
   - Mention likely conflict areas such as shared config, schemas, migrations, test harnesses, or the same UI files.
7. Recommend the next step without starting work.
   - Give exactly one best next issue.
   - If useful, suggest `$beads-issue-worktree <id>`.

## Output Format

```markdown
**Current State**
- Ready issues: <count>
- Open issues: <count>
- Local branch/state: <short note>

**Recommended Order**
| Rank | Bead | Recommendation | Reason |
|---|---|---|---|
| 1 | <id> <title> | Do next | <why> |

**Parallel Work**
- <safe parallel grouping, or "No safe parallel split right now">

**Next Step**
- Start with `$beads-issue-worktree <id>` if the user wants to implement the top recommendation.
```

## Guardrails

- Do not create worktrees, branches, commits, pull requests, or notes.
- Do not edit files.
- Do not create, close, claim, assign, delete, or mutate Beads issues.
- Do not recommend blocked, closed, parent, or ambiguous issues as direct implementation work.
- If `bd` is unavailable or the repository is not a Beads workspace, report the blocker and stop.
- If product intent is unclear after reading local docs and issue bodies, ask one focused question before ranking.
