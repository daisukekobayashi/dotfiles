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
2. Fetch the overview data.
   - Prefer repository or project guidance when it defines the query.
   - Otherwise use `az boards query --wiql` for active, relevant Work Items in
     the current project, selecting `System.State`, `System.WorkItemType`,
     `System.Tags`, `System.IterationPath`,
     `Microsoft.VSTS.Common.Severity`, and `Microsoft.VSTS.Common.Priority`
     with the other fields.
   - Read each candidate's relations with
     `az boards work-item show --id <id> --expand relations --query "relations[?rel=='System.LinkTypes.Dependency-Reverse' || rel=='System.LinkTypes.Hierarchy-Forward' || rel=='System.LinkTypes.Hierarchy-Reverse' || rel=='ArtifactLink'].{rel: rel, url: url, name: attributes.name}"`,
     which keeps its `Predecessor`, child, and parent links and its artifact
     links, such as linked pull requests. Take each linked Work Item's state
     from the query results, or else from
     `az boards work-item show --id <linked-id> --expand none --fields System.State --query 'fields."System.State"'`.
3. Fetch open PRs with `az repos pr list`.
4. Read local repository guidance such as `AGENTS.md`, `README.md`,
   `docs/*.md`, and roadmap docs when present.
5. Read details under [Detail Reads](../triage-common/references/detail-reads.md).
   - Read a band item with
     `az boards work-item show --id <id> --expand none --fields System.State,System.Description,Microsoft.VSTS.TCM.ReproSteps,Microsoft.VSTS.Common.AcceptanceCriteria,System.CommentCount`,
     which also returns the type-specific text fields a Work Item type may use
     instead of the description.
   - When `System.CommentCount` is above zero, read its comments with
     `az devops invoke --area wit --resource comments --route-parameters project=<project> workItemId=<id> --api-version 7.1-preview --query "{comments: comments[].{author: createdBy.displayName, createdDate: createdDate, text: text}, next: continuationToken || continuation_token}"`.
     The token comes from the response body or, through `invoke`, from its
     header. While `next` is set, repeat with
     `--query-parameters continuationToken=<token>`. `invoke` accepts only
     `<major>.<minor>` with an optional `-preview`, never a resource version
     such as `-preview.4`. If the comments request fails, report that item's
     comments as unread and keep it in the band.
   - Collect dependencies from `Predecessor` relations and from
     `Blocked by #<id>` lines in the description.
   - Collect each band item's `Touched Areas` section when present.
   - Once the band is complete, for PRs that may overlap with band items,
     compare changed files with `git diff --name-only <target>...<source>`
     when both branches are available as local or remote-tracking refs. Do not
     fetch or check out branches only for this.
6. Classify Work Items:
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
7. Rank actionable Work Items under the lens, following
   [Rank](../triage-common/references/lenses.md#rank).
   - Read tags, iteration paths, and parent Epics or Features as core feature
     sources, alongside the docs from step 4.
   - Read severity from `Microsoft.VSTS.Common.Severity`, then priority from
     `Microsoft.VSTS.Common.Priority`; read regressions and release blockers
     from tags, iteration paths, and the description.
8. Identify safe parallel candidates.
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
- Detail reads: <Work Items read in full>; list only: <Work Items placed from list data, or "none">

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
