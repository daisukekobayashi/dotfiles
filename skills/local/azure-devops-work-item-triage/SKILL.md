---
name: azure-devops-work-item-triage
description: Use only when the user explicitly invokes `$azure-devops-work-item-triage` or names `azure-devops-work-item-triage` to triage Azure DevOps Work Items in the current project.
---

# Azure DevOps Work Item Triage

## Scope

Use this skill to recommend which Azure DevOps Work Item to handle next, which
items are blocked, and which items can be worked on in parallel. This skill is
read-only and does not start implementation.

Read `../azure-devops-common/references/context.md` before querying Azure
DevOps.

Ranking follows a lens given as `lens=<name>`, `deliver` by default. Choose it
under [Triage Lenses](../triage-common/references/lenses.md#choose-the-lens)
before step 1.

## Workflow

1. Resolve the current Azure DevOps organization, project, repository, branch,
   and dirty state.
   - List other worktrees with `git worktree list --porcelain`, and map each to
     a Work Item ID when its branch or path names one; report the rest as
     unmapped.
2. Fetch candidate Work Items.
   - Prefer repository or project guidance when it defines the query.
   - Otherwise use `az boards query --wiql` for active, relevant Work Items in
     the current project, selecting `System.Tags`, `System.IterationPath`,
     `Microsoft.VSTS.Common.Severity`, and `Microsoft.VSTS.Common.Priority`
     with the other fields.
   - For plausible candidates, fetch details and relations with
     `az boards work-item show --id <id> --expand relations`.
   - Collect dependencies from `Predecessor` relations and from
     `Blocked by #<id>` lines in the description.
   - Collect each Work Item's `Touched Areas` section when present.
3. Fetch open PRs with `az repos pr list`.
   - For PRs that may overlap with candidates, compare changed files with
     `git diff --name-only <target>...<source>` when both branches are
     available as local or remote-tracking refs. Do not fetch or check out
     branches only for this.
4. Read local repository guidance such as `AGENTS.md`, `README.md`,
   `docs/*.md`, and roadmap docs when present.
5. Classify Work Items:
   - parent/tracking item
   - directly actionable implementation item
   - blocked by another Work Item or PR. Treat an item as blocked while any
     blocker is not in a completed state under the project's process. If the
     state meaning is unclear, say so instead of guessing.
   - If relations and `Blocked by` lines disagree, use their union and note
     the disagreement.
   - future-scope or out-of-scope work
   - duplicate or already represented by an open PR
   - already in progress in another local worktree
6. Rank actionable Work Items under the lens, following
   [Rank](../triage-common/references/lenses.md#rank).
   - Read tags, iteration paths, and parent Epics or Features as core feature
     sources, alongside the docs from step 4.
   - Read severity from `Microsoft.VSTS.Common.Severity`, then priority from
     `Microsoft.VSTS.Common.Priority`; read regressions and release blockers
     from tags, iteration paths, and the description.
7. Identify safe parallel candidates.
   - Build the current wave: actionable Work Items with no incomplete
     blockers.
   - Within the current wave, group items as parallel only when their touched
     areas do not overlap, including shared resources such as schemas, config,
     migrations, lockfiles, or public interfaces.
   - Flag overlaps between candidates and open PR changes as conflicts with
     in-flight work.
   - For other worktrees that may overlap candidates, list changed files with
     `git -C <path> diff --name-only <default-branch>...HEAD` and
     `git -C <path> status --short`, and flag overlaps the same way. Skip
     worktrees with no changes.
   - When a Work Item has no `Touched Areas` section, infer its likely areas
     from the description and repository, and label them as inferred.
   - Do not group items with an ordering dependency.

## Output Format

```markdown
**Current State**
- Lens: <lens>
- Basis: <the lens's report basis>
- Candidate Work Items: <count>
- Open PRs: <count>
- Active worktrees: <count, mapped Work Items>
- Local branch/state: <short note>

**Recommended Order**
| Rank | Work Item | Recommendation | Reason |
|---|---|---|---|
| 1 | #<id> <title> | Do next | <why> |

**Parallel Work**
- Current wave: #<a>, #<b> (<parallel groups, or why they must not run together>)
- Overlaps: <touched-area overlaps between items or with open PRs or worktrees, or "none">
- Next wave after #<n> completes: #<c>, #<d>
- Or: "No safe parallel split right now"

**Next Step**
- Start with `$azure-devops-work-item-start <id>` if the user wants to implement the top recommendation.
```

## Guardrails

- Do not create worktrees, branches, commits, pull requests, or Work Item comments.
- Do not edit files.
- Do not mutate Work Items.
- If Azure DevOps auth or network access blocks reads, report the blocker and stop.
- If product intent or the lens basis is unclear after reading local docs and
  Work Item descriptions, ask a focused question before ranking.
