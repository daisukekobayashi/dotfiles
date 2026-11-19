---
name: beads-issue-triage
description: Use only when the user explicitly invokes `$beads-issue-triage` or names `beads-issue-triage` to triage Beads issues in the current repository before implementation.
---

# Beads Issue Triage

## Scope

Use this skill to recommend which Beads issue to handle next, which issues are blocked, and which issues can be worked on in parallel. This skill is read-only and does not start implementation.

Use `bd` as the source of truth. Do not create markdown TODO files for work tracking when Beads is available.

Ranking follows a lens given as `lens=<name>`, `deliver` by default. Choose it under [Triage Lenses](../triage-common/references/lenses.md#choose-the-lens) before step 1.

## Workflow

1. Resolve the current Beads workspace.
   - Run `bd prime`; if it prints nothing, run `bd where`.
   - Confirm local branch and dirty state with `git status --short --branch`.
   - List other worktrees with `git worktree list --porcelain`, and map each to a bead ID when its branch or path names one; report the rest as unmapped.
2. Fetch the overview data.
   - Start with `bd ready --brief --json`.
   - List every unfinished bead without its free-form text with `bd list --status=open,in_progress,blocked,hooked --brief --json --limit 0`, which keeps status, priority, type, and labels.
   - Read blocked beads and their blockers with `bd blocked --json=false`, whose plain output leaves out descriptions even when the workspace sets `json: true`.
3. Read local repository guidance before ranking.
   - Check project instructions such as `AGENTS.md`.
   - Check product, roadmap, or workflow docs if present, commonly `README.md`, `docs/*.md`, or `WORKFLOW.md`.
4. Read details under [Detail Reads](../triage-common/references/detail-reads.md).
   - Read a band bead with `bd show <id> --json --include-comments --brief-deps`, which returns its text and comments and reduces each dependency to its identity, and collect its `Touched areas` section when present.
   - Also read in-progress or claimed beads, so their touched areas can be checked for conflicts.
5. Classify candidate issues.
   - directly actionable implementation issue
   - blocked by another issue, using `bd` dependencies as the source of truth
   - parent, epic, or tracking issue
   - If a `Blocked by` section names a blocker that `bd` does not record, treat the bead as blocked and note the disagreement.
   - already in progress or claimed, or in progress in another local worktree
   - future-scope, out-of-scope, duplicate, or ambiguous work
6. Rank actionable issues under the lens, following [Rank](../triage-common/references/lenses.md#rank).
   - Read labels and parent epics as core feature sources, alongside the docs from step 3.
   - Read severity from severity-like labels, then priority from the bead's `priority`; read regressions and release blockers from labels, the issue type, and the description.
7. Identify safe parallel candidates.
   - Build the current wave: actionable ready issues with no open blockers.
   - Within the current wave, group issues as parallel only when their touched areas do not overlap, including shared resources such as schemas, config, migrations, lockfiles, or public interfaces.
   - Also check each candidate's touched areas against in-progress or claimed beads, and flag overlaps as conflicts with in-flight work.
   - For other worktrees that may overlap candidates, list changed files with `git -C <path> diff --name-only <default-branch>...HEAD` and `git -C <path> status --short`, and flag overlaps the same way. Skip worktrees with no changes.
   - When a bead has no `Touched areas` section, infer its likely areas from the description and repository, and label them as inferred.
   - Recommend parallel work only when issues have no dependency relationship.
   - Mention likely conflict areas such as shared config, schemas, migrations, test harnesses, or the same UI files.
8. Recommend the next step without starting work.
   - Give exactly one best next issue.
   - If useful, suggest `$beads-issue-worktree <id>`.

## Output Format

```markdown
**Current State**
- Lens: <lens>
- Basis: <the lens's report basis>
- Ready issues: <count>
- Open issues: <count>
- Active worktrees: <count, mapped beads>
- Local branch/state: <short note>
- Detail reads: <beads read in full>; list only: <beads placed from list data, or "none">

**Recommended Order**
| Rank | Bead | Recommendation | Reason |
|---|---|---|---|
| 1 | <id> <title> | Do next | <why> |

**Parallel Work**
- Current wave: <id>, <id> (<parallel groups, or why they must not run together>)
- Overlaps: <touched-area overlaps between beads or with in-progress beads or worktrees, or "none">
- Next wave after <id> closes: <id>, <id>
- Or: "No safe parallel split right now"

**Next Step**
- Start with `$beads-issue-worktree <id>` if the user wants to implement the top recommendation.
```

## Guardrails

- Do not create worktrees, branches, commits, pull requests, or notes.
- Do not edit files.
- Do not create, close, claim, assign, delete, or mutate Beads issues.
- Do not recommend blocked, closed, parent, or ambiguous issues as direct implementation work.
- If `bd` is unavailable or the repository is not a Beads workspace, report the blocker and stop.
- If product intent or the lens basis is unclear after reading local docs and issue bodies, ask one focused question before ranking.
