---
name: github-issue-triage
description: Use only when the user explicitly invokes $github-issue-triage or names github-issue-triage. Triage open GitHub issues in the current repository, recommend the next issue to handle, and identify safe parallel work candidates without starting implementation.
---

# GitHub Issue Triage

## Scope

Use this skill to answer questions like:

- Which open GitHub issue should we handle next?
- Which issues can be worked on in parallel?
- Which issues are blocked, parent trackers, or future-scope work?

This skill is for current-repository triage only. It recommends work; it does
not start implementation.

Ranking follows a lens given as `lens=<name>`, `deliver` by default. Choose it
under [Triage Lenses](../triage-common/references/lenses.md#choose-the-lens)
before step 1.

## Workflow

1. Resolve the current repository from local git context.
   - Confirm the branch and dirty state with `git status --short --branch`.
   - List other worktrees with `git worktree list --porcelain`, and map each to an issue number when its branch or path names one; report the rest as unmapped.
   - Resolve the GitHub repository with `gh repo view --json nameWithOwner,url,defaultBranchRef`, and pass `--repo <host>/<owner>/<repo>` to every later `gh issue` and `gh pr` call.
2. Fetch the overview data.
   - List open issues with `gh issue list --state open --limit 100 --json number,title,labels,milestone,assignees,updatedAt,createdAt,url`.
   - List open pull requests with `gh pr list --state open --limit 50 --json number,title,headRefName,baseRefName,labels,updatedAt,url`.
   - Read each open issue's native blockers with `gh api --hostname <host> --paginate repos/<owner>/<repo>/issues/<number>/dependencies/blocked_by --jq '.[] | {repository: (.repository_url | sub("^.*/repos/"; "")), number, state}'` and its children with `gh api --hostname <host> --paginate repos/<owner>/<repo>/issues/<number>/sub_issues --jq '.[] | {repository: (.repository_url | sub("^.*/repos/"; "")), number, state}'`.
   - Treat a related issue whose `repository` differs from `<owner>/<repo>` as external: it blocks by its own state, and never joins a local issue with the same number.
   - If a relationship API is unavailable or fails, rely on `Blocked by #<n>` lines from detail reads and mention that native relationships could not be read.
3. Read local repository guidance before ranking.
   - Check project instructions such as `AGENTS.md`.
   - Check product or roadmap docs if present, commonly `README.md`, `docs/*.md`, `WORKFLOW.md`, or milestone docs.
   - Use this context to filter out work that violates product scope or repository rules.
4. Read details under [Detail Reads](../triage-common/references/detail-reads.md).
   - Read a band issue with `gh issue view <number> --json number,state,body,comments --jq '{number, state, body, comments: [.comments[] | {author: .author.login, createdAt, body}]}'`.
   - Collect each band issue's dependencies from `Blocked by #<n>` lines in its body, alongside its native blockers.
   - Collect each band issue's `Touched Areas` section when present.
   - For open PRs that may overlap with band issues, list changed files with `gh pr view <number> --json files --jq '.files[].path'`.
5. Classify each open issue.
   - Parent tracker or milestone issue.
   - Directly actionable implementation issue.
   - Blocked by another issue or PR. Treat an issue as blocked while any of its blocking issues is still open, whether the dependency came from a `Blocked by #<n>` line or a native relationship.
   - If body lines and native relationships disagree, use their union and note the disagreement.
   - Future-scope or out-of-scope work.
   - Duplicate or already represented by an open PR.
   - Already in progress in another local worktree.
6. Rank actionable issues under the lens, following [Rank](../triage-common/references/lenses.md#rank).
   - Read milestones and labels as core feature sources, alongside the docs from step 3.
   - Read severity from severity-like labels (for example `severity:high`, `critical`) and priority from priority-like labels (for example `P1`, `priority:high`); read regressions and release blockers from labels, milestones, and the body.
7. Identify parallel work candidates.
   - Build the current wave from every actionable issue with no open blockers, including issues provisionally placed as actionable from list data only.
   - Report the complete wave even when no safe parallel group can be named. Mark current-wave issues whose touched areas were not checked as unverified for parallel work.
   - Within the current wave, group issues as parallel only when their touched areas do not overlap, including shared resources such as schemas, config, migrations, lockfiles, or public interfaces.
   - Also check each candidate's touched areas against the changed files of open PRs, and flag overlaps as conflicts with in-flight work.
   - For other worktrees that may overlap candidates, list changed files with `git -C <path> diff --name-only <default-branch>...HEAD` and `git -C <path> status --short`, and flag overlaps the same way. Skip worktrees with no changes.
   - When an issue has no `Touched Areas` section, infer its likely areas from the body and repository, and label them as inferred.
   - Do not recommend parallel work when one issue defines policy, schema, or workflow behavior that another issue depends on.
   - Mention likely conflict areas such as shared config modules, schemas, migrations, job orchestration, or the same UI files.
8. Recommend the next step without starting work.
   - Give exactly one best next issue.
   - If useful, suggest the follow-up command, for example `$github-issue-start #23`.

## Output Format

Use this structure:

```markdown
**Current State**
- Lens: <lens>
- Basis: <the lens's report basis>
- Open issues: <count>
- Open PRs: <count>
- Active worktrees: <count, mapped issues>
- Local branch/state: <short note>
- Detail reads: <issues read in full>; list only: <issues placed from list data, or "none">

**Recommended Order**
| Rank | Issue | Recommendation | Reason |
|---|---|---|---|
| 1 | #<n> <title> | Do next | <why> |

**Parallel Work**
- Current wave: <all current-wave issue numbers, or "none">
- Parallel groups: <verified groups, or "No safe parallel split right now">
- Unverified for parallel work: <current-wave issue numbers with unchecked touched areas, or "none">
- Overlaps: <touched-area overlaps between issues or with open PRs or worktrees, or "none">
- Next wave after #<n> closes: #<c>, #<d>

**Next Step**
- Start with `$github-issue-start #<n>` if the user wants to implement the top recommendation.
```

Keep the report concise, but include enough reasoning that the recommendation
is auditable.

## Guardrails

- Do not create worktrees, branches, commits, pull requests, or issue comments.
- Do not edit repository files.
- Do not close, label, assign, or otherwise mutate GitHub issues.
- Do not assume cross-repository work.
- Do not force unrelated issues into a parallel plan just because multiple issues are open.
- If GitHub authentication or network access blocks issue reads, report the blocker and stop.
- If product intent or the lens basis is unclear after reading local docs and issue bodies, ask a focused question before ranking.
