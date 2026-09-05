---
name: design-preflight
description: Use only when explicitly invoked with $design-preflight before design or implementation work to control grilling for hard-to-change decisions, durable architecture, compatibility assumptions, and one-way-door risks.
---

# Design Preflight

Run a controlled `grilling` pass before design or implementation. Keep the interface small and the default lightweight.

## Required Sub-Skill

**REQUIRED SUB-SKILL:** Use `grilling`.

This skill is a wrapper, not a replacement. Use `grilling` as the questioning engine and provide it with the brief below.

In `durable` and `quick`, inherit its fact-finding, recommended answers, and dependency-aware rounds. This wrapper overrides its exhaustive question scope, question budget, and completion rules with the rules below. In `open`, use `grilling` unchanged.

## Public Interface

| Invocation | Meaning |
|---|---|
| `$design-preflight` | Same as `durable`. |
| `$design-preflight durable` | Controlled grilling for high-impact, hard-to-change design decisions. |
| `$design-preflight quick` | Blocker-only preflight. Ask at most 3 questions. |
| `$design-preflight open` | Raw `grilling`; do not apply this skill's filtering. |

Treat unknown words as context hints, not CLI errors. Natural-language limits like "3 questions max" or "blockers only" are upper bounds.

## Presets

### durable

Default. Use when the user wants durable design instead of compatibility-preserving defaults.

Internal brief: `focus=one-way-door decisions`, `budget=5 by default, extend only for unresolved high-impact decisions`, `threshold=high`, `compatibility=not assumed`.

Do not assume backward compatibility is required. Treat compatibility as real only when the user, public contract, stored data, external integration, rollout plan, or operational reality makes it real.

Within real constraints, prefer long-term maintainability, clear responsibilities and boundaries, and a single coherent model. Accept justified short-term migration work when it reduces long-term architectural debt. Base the design on current requirements and evidenced future constraints; do not add abstractions or extension points for speculative needs. Choose the simplest design that meets those requirements.

Prefer questions that reveal whether to:

- make a breaking change now instead of adding a compatibility shim
- migrate or replace an old data model instead of supporting two models indefinitely
- create a cleaner boundary instead of matching the current structure
- remove or rename an awkward interface before it spreads
- accept short-term migration work to avoid long-term architectural debt

### quick

Use when the user wants only blockers.

Internal brief: `focus=blocker-level one-way-door decisions`, `budget=3`, `threshold=blocker-only`, `compatibility=not assumed`.

Ask only questions where a wrong default is likely to force rework, migration, or a visible contract change.

### open

Use raw `grilling`. Do not impose this skill's one-way-door filter, compatibility stance, or question budget.

## Brief To Give Grilling

For `durable` and `quick`, start the `grilling` session with this brief:

```text
This is a design preflight, not an open-ended interview.

Ask only questions whose answers affect hard-to-change design decisions.
Apply the selected mode's question budget across the whole session, not per round.
Do not ask filler questions.
Stop early if no question clears the bar.

Prioritize one-way-door risks: public contracts, data models, architecture boundaries, dependency direction, migration cost, rollout constraints, operational assumptions, security boundaries, and long-term maintenance cost.

For durable mode: challenge compatibility-preserving defaults. Ask whether compatibility is a real constraint or merely an assumed safe choice.
```

## Question Bar

Ask only when the answer would materially change:

- public interfaces, contracts, data formats, or persisted schemas
- migration path, compatibility policy, or rollout constraints
- module boundaries, ownership, extension points, or dependency direction
- security, privacy, deployment, or operational assumptions
- long-term maintainability versus compatibility tradeoffs

Do not ask about:

- internal names or small implementation tactics
- reversible UI copy or local layout details
- test organization unless it affects public behavior or architecture
- preferences already covered by project conventions

## Question Budget and Completion

For `durable` and `quick`:

- Carry forward the user's stated preferences and settled decisions. Reopen them only when new evidence or a contradiction materially affects the design.
- In `durable`, aim for at most 5 questions. If high-impact, hard-to-change decisions remain unresolved, briefly explain why further questions are needed and ask only those questions.
- In `quick`, ask at most 3 questions. Explicit user limits are hard caps in every mode. Count separately answerable decisions separately; do not bundle them to evade a cap.
- Stop when no unresolved decision meets the selected question bar. Do not exhaust branches outside that scope. For minor, reversible choices, use repo conventions and state material assumptions as needed.
- If a hard cap leaves a high-impact decision unresolved, summarize it and its implications. Continue only work that does not depend on it; do not silently choose an answer or treat the cap as approval.
- Replace `grilling`'s blanket final confirmation with a brief handoff, then proceed within the user's already authorized scope. Still obtain any independently required approval. A request for preflight alone does not authorize implementation.

## Output

For `durable` and `quick`, briefly summarize the chosen direction, compatibility constraints to preserve, agreed breaking changes or migration work, and remaining material assumptions or unresolved decisions. Omit empty categories. Keep this in the conversation unless a durable document is requested or required by repo conventions.

If no question clears the bar, say so briefly and give the applicable direction and assumptions without requiring an extra confirmation.
