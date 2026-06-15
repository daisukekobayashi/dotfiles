---
name: beads-issue-create
description: Create one or more Beads issues from a discussion, investigation, rough idea, plan, bug report, or feature request. Use when the user wants work captured in bd/Beads, asks to create beads issues, or wants a plan/spec split into Beads epic and child tasks with dependencies.
---

# Beads Issue Create

## Scope

Turn user intent into durable Beads issues in the current repository. The result may be one bead, several dependent beads, or an epic with child beads.

Use `bd` as the source of truth. Do not create markdown TODO files for work tracking when Beads is available.

## Workflow

1. Run `bd prime`; if it prints nothing, run `bd where`.
2. Resolve the current repository and read enough context from the conversation, docs, or local files to draft issue-ready work.
3. Search for existing work before creating duplicates:
   - `bd list --status=open`
   - `bd search <keyword>` when useful
4. Decide the bead breakdown.
   - Prefer one bead when there is one clear outcome.
   - Split when deliverables, sequencing, risk, owners, or subsystems differ.
   - Create an epic when there are 3 or more child beads, or when dependencies make coordination useful.
5. Classify each child bead as `AFK` or `HITL` in labels or notes.
   - `AFK`: implementable without more human decisions.
   - `HITL`: requires a design decision, review, or external input.
6. Draft a preview before creating anything. Include title, type, priority, labels, parent, dependencies, and acceptance criteria for every bead.
7. Wait for explicit user confirmation before running `bd create`.
8. Create approved beads in dependency order.
   - Create epic first when used.
   - Create blockers before blocked beads.
   - Use `--parent` for epic children.
   - Use `--deps` or `bd dep add` for dependencies.
9. Return created bead IDs, dependency order, safe parallel groups, and the recommended next command such as `$beads-issue-worktree <id>`.

## Issue Body Shape

Use this structure in `--description` unless the repo has a stronger local convention:

```markdown
## What to build
<Concise behavior or outcome, end-to-end.>

## Acceptance criteria
- [ ] <Verifiable criterion>
- [ ] <Verifiable criterion>

## Blocked by
<None - can start immediately, or bead IDs once known.>
```

Use `--acceptance` for duplicated machine-readable acceptance criteria when helpful.

## Guardrails

- Do not create any bead before preview and explicit approval.
- Do not assume the result is exactly one bead.
- Do not close, claim, assign, delete, or mutate existing beads unless explicitly asked.
- Do not invent facts or acceptance criteria that are not supported by the source material.
- Keep issue text implementation-oriented but avoid brittle file paths unless necessary.
- Prefer dependencies over prose-only ordering when one bead truly blocks another.
