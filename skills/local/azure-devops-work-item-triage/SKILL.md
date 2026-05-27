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

## Workflow

1. Resolve the current Azure DevOps organization, project, repository, branch,
   and dirty state.
2. Fetch candidate Work Items.
   - Prefer repository or project guidance when it defines the query.
   - Otherwise use `az boards query --wiql` for active, relevant Work Items in
     the current project.
3. Fetch open PRs with `az repos pr list`.
4. Read local repository guidance such as `AGENTS.md`, `README.md`,
   `docs/*.md`, and roadmap docs when present.
5. Classify Work Items:
   - parent/tracking item
   - directly actionable implementation item
   - blocked by another Work Item or PR
   - future-scope or out-of-scope work
   - duplicate or already represented by an open PR
6. Rank actionable Work Items.
   - Prefer unblocking work, clear acceptance criteria, moderate blast radius,
     and alignment with repository guidance.
   - Defer ambiguous, broad, high-risk, or policy-setting items unless they are
     explicitly the priority.
7. Identify safe parallel candidates only when they touch separate subsystems
   and have no ordering dependency.

## Output Format

```markdown
**Current State**
- Candidate Work Items: <count>
- Open PRs: <count>
- Local branch/state: <short note>

**Recommended Order**
| Rank | Work Item | Recommendation | Reason |
|---|---|---|---|
| 1 | #<id> <title> | Do next | <why> |

**Parallel Work**
- <safe parallel grouping, or "No safe parallel split right now">

**Next Step**
- Start with `$azure-devops-work-item-worktree <id>` if the user wants to implement the top recommendation.
```

## Guardrails

- Do not create worktrees, branches, commits, pull requests, or Work Item comments.
- Do not edit files.
- Do not mutate Work Items.
- If Azure DevOps auth or network access blocks reads, report the blocker and stop.
