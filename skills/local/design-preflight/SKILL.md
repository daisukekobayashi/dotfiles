---
name: design-preflight
description: Use only when explicitly invoked with $design-preflight before design or implementation work to control grill-me for hard-to-change decisions, durable architecture, compatibility assumptions, and one-way-door risks.
---

# Design Preflight

Run a controlled `grill-me` pass before design or implementation. Keep the interface small and the default lightweight.

## Required Sub-Skill

**REQUIRED SUB-SKILL:** Use `grill-me`.

This skill is a wrapper, not a replacement. Use `grill-me` as the questioning engine and provide it with the brief below.

## Public Interface

| Invocation | Meaning |
|---|---|
| `$design-preflight` | Same as `durable`. |
| `$design-preflight durable` | Controlled grilling for high-impact, hard-to-change design decisions. |
| `$design-preflight quick` | Blocker-only preflight. Ask at most 3 questions. |
| `$design-preflight open` | Raw `grill-me`; do not apply this skill's filtering. |

Treat unknown words as context hints, not CLI errors. Natural-language limits like "3 questions max" or "blockers only" are upper bounds.

## Presets

### durable

Default. Use when the user wants durable design instead of compatibility-preserving defaults.

Internal brief: `focus=one-way-door decisions`, `budget=5`, `threshold=high`, `compatibility=not assumed`.

Do not assume backward compatibility is required. Treat compatibility as real only when the user, public contract, stored data, external integration, rollout plan, or operational reality makes it real.

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

Use raw `grill-me`. Do not impose this skill's one-way-door filter, compatibility stance, or question budget.

## Brief To Give Grill-Me

For `durable` and `quick`, start the `grill-me` session with this brief:

```text
This is a design preflight, not an open-ended interview.

Ask only questions whose answers affect hard-to-change design decisions.
Treat the question count as a maximum, not a target.
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

## Output

Let `grill-me` conduct the session. If no question clears the bar, say so briefly and proceed with the user's stated preference and the repo conventions.
