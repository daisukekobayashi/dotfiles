---
name: issue-understanding-check
description: Use only when explicitly requested with `$issue-understanding-check`, or through the full `github-issue-delivery` or `azure-devops-work-item-delivery` workflow before design preflight, to check that a GitHub issue or Azure DevOps Work Item matches the user's intent with a concrete before/after example and one intent question.
---

# Issue Understanding Check

Confirm that an issue or Work Item says what the user intends before design
starts. Issues are often drafted by AI and accepted without a close read, and
the user usually works through agent CLIs without rereading them: the user knows
the goal, not the text. Give the user enough of the issue to judge, then ask a
judgment the user can make from the goal alone. Knowledge flows from the AI to
the user. Eliciting the user's intent from scratch is `find-unknowns`; deciding
how to build is `design-preflight`.

Use read-only inspection. Propose issue edits; leave the issue itself unchanged.

## Workflow

### 1. Inspect

Read the issue body, comments, acceptance criteria, open questions, linked items,
and the code or docs that show the current behavior it describes.

### 2. Present an overview

Write the overview for a user who has not reread the issue; it is everything the
user needs to answer step 3.

- State in one sentence what changes and why.
- Show one typical case as **before / after**: a concrete situation (input,
  operation, or state, using real names and values from the repository) and the
  observable result before and after the change.
- List the scope in 2-3 lines each: what is in scope and what is out of scope
  (non-goals).
- Cite the source of each claim (an issue quote or `file:line`). Label anything
  the sources leave unstated as your interpretation.

### 3. Ask one intent question

Pick a situation that the user can decide from the goal in the overview and
where a wrong reading would change the implementation: a boundary, an exclusion,
an interaction, or a non-goal a reader might assume is in scope. Choose one the
overview leaves the user to infer by applying the goal, rather than one a line of
the overview already answers. Prefer a situation the acceptance criteria decide;
route a situation that only an open question decides to preflight instead.

Show the situation and ask what should happen given the goal. Offer 2-3
concrete outcomes, one of which is the issue's reading, plus `can't decide`.
Ask one question (at most two parts about the same situation) and wait for the
answer. Write the options with equal detail, order them independently of the
issue's answer, and keep the issue's answer and any hint toward it out of the
question message.

### 4. Compare and discuss

Compare the answer with the issue and code, quoting the deciding lines.

- **Match:** the check is confirmed.
- **Mismatch:** treat it as possible drift between the issue and the user's
  intent, and discuss it with the user. Establish whether the user's reading or
  the issue is off: the issue may be wrong, ambiguous, or in conflict with the
  code. Agree on the intended behavior, and ask a new question only to confirm
  a corrected understanding. Keep the discussion on what changes and why; record
  how-to-build questions for preflight.
- **`can't decide`:** explain the issue's reading with its sources and what it
  leads to, then ask the user to accept or adjust it. Acceptance as written
  confirms the check; an adjustment is an agreed change and corrects it. Mark the
  resulting confirmed example `accepted after can't decide` in its source.
- When the agreed behavior differs from the issue text, record it as an agreed
  issue change and propose updating the issue.
- When the discussion shows that the problem itself is unsettled, recommend
  `find-unknowns` and close as `unresolved`.

The user may skip at any point; close as `skipped`. When interaction is
unavailable, close as `not run`; the judgment belongs to the user alone.

## Result

The check is complete when its status is one of: `confirmed` (the user's answer,
or acceptance after `can't decide`, matched the issue), `corrected` (a mismatch
or adjustment ended in agreement), `skipped`, `unresolved`, or `not run`. Return:

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
