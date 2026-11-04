---
name: issue-understanding-check
description: Use only when explicitly requested with `$issue-understanding-check`, or through the full `github-issue-delivery` or `azure-devops-work-item-delivery` workflow before design preflight, to check the user's own understanding of a GitHub issue or Azure DevOps Work Item with a concrete before/after example and one prediction.
---

# Issue Understanding Check

Confirm that the user understands what an issue or Work Item changes before
design starts. Issues are often drafted by AI and accepted without a close read;
this check is where the user actually confirms the spec. Knowledge flows from the
AI to the user: explain, then let the user predict. Eliciting the user's intent
is `find-unknowns`; deciding how to build is `design-preflight`.

Use read-only inspection. Propose issue edits; leave the issue itself unchanged.

## Workflow

### 1. Inspect

Read the issue body, comments, acceptance criteria, open questions, linked items,
and the code or docs that show the current behavior it describes.

### 2. Explain one typical case

- State in one sentence what changes and why.
- Show one typical case as **before / after**: a concrete situation (input,
  operation, or state, using real names and values from the repository) and the
  observable result before and after the change.
- Cite the source of each claim (an issue quote or `file:line`). Label anything
  the sources leave unstated as your interpretation.

### 3. Ask one prediction

Pick the situation where readings most plausibly diverge: a boundary, an
exclusion, an interaction, or a non-goal a reader might assume is in scope.
Prefer a situation the acceptance criteria decide; route a situation that only
an open question decides to preflight instead.

Show only the situation and ask what should happen. Ask one question (at most
two parts about the same situation) and wait for the answer. Keep the answer and
any hint toward it out of the question message.

### 4. Compare and discuss

Compare the answer with the issue and code, quoting the deciding lines.

- **Match:** the check is confirmed.
- **Mismatch:** discuss with the user. Establish whether the user's reading or
  the issue is off: the issue may be wrong, ambiguous, or in conflict with the
  code. Agree on the intended behavior, and ask a new prediction only to confirm
  a corrected understanding. Keep the discussion on what changes and why; record
  how-to-build questions for preflight.
- When the agreed behavior differs from the issue text, record it as an agreed
  issue change and propose updating the issue.
- When the discussion shows that the problem itself is unsettled, recommend
  `find-unknowns` and close as `unresolved`.

The user may skip at any point; close as `skipped`. When interaction is
unavailable, close as `not run`; the prediction belongs to the user alone.

## Result

The check is complete when its status is one of: `confirmed` (the prediction
matched), `corrected` (a mismatch ended in agreement), `skipped`, `unresolved`,
or `not run`. Return:

```markdown
# Understanding Check: <issue or Work Item reference>

Status: <status>

## Confirmed Examples
- <situation> -> <expected behavior> (<source>)

## Agreed Issue Changes
## Carry to Design Preflight
## Open Disagreements
```

Write `None` for empty sections. Confirmed examples serve as acceptance examples
for preflight, implementation, and tests.
