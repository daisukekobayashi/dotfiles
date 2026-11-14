# Triage Lenses

A lens sets the ranking basis for one triage run. It changes only the calling
skill's rank step. Classification, the parallel waves and overlap checks, the
single next-item recommendation, and the guardrails stay as the calling skill
defines them, identical under every lens.

The calling skill owns where each signal is read on its provider, such as
labels, fields, or milestones. This file owns how a lens uses the signals.

## Choose the lens

Before anything else in the run, take the lens from a `lens=<name>` argument
in the invocation. Valid lenses: `deliver`, `stabilize`, matched exactly in
lowercase.

- No `lens=` argument: use `deliver`. Other words in the request are context,
  never a lens.
- Any other `lens=` value: stop, report
  `Unknown lens: <value>. Valid lenses: deliver, stabilize.`, and rank
  nothing.

The lens comes only from the invocation; repository documents never set it.

## Rank

1. Determine the lens's basis under its **Basis** rule. When the rule says to
   ask, ask one focused question and rank only after the answer.
2. Order actionable items by the lens's **Prefers** rules, in their order.
   **Prefers wins:** an item a Prefers rule places keeps that place even when
   it also matches the lens's Defers, such as a foundation item that is a
   refactor, a bug that blocks the core path, or a feature that is a release
   blocker.
3. Among items the lens leaves equal or close, apply the
   [shared tie-breakers](#shared-tie-breakers).
4. Place last the Defers items that no Prefers rule places.

Each row's `Reason` names the lens rule that placed it.

## Shared tie-breakers

These apply under every lens, after the lens's own ordering:

- Prefer alignment with repository guidance and current product direction.
- Prefer clear acceptance criteria and moderate blast radius.
- Defer broad, ambiguous, high-risk, or future-scope work unless it is
  explicitly the priority.
- Treat parent and tracking items as coordination items, not the next coding
  task, unless all their children are complete.

How foundation, contract, or policy-setting items rank is lens-owned.

## Lens: deliver

Core features first, without undermining long-term foundations.

**Terms**

- **Core features:** the features the product exists to deliver now.
  **Upcoming core features:** those named as next in the sources below and not
  yet delivered by a closed item.
- **Core path item:** an item that makes a core feature usable or
  demonstrable end to end.
- **Foundation item:** an item that settles a contract, schema, shared
  configuration, public interface, or workflow policy that other items build
  on.
- **Shares the contract:** the core item's touched areas, declared or
  inferred, include something the foundation item's acceptance criteria
  define or change. Label an overlap found only from inferred areas as
  inferred.

**Basis.** Read core and upcoming core features from `README.md`, roadmap or
milestone docs, milestones, and labels. When either cannot be determined from
them, ask the user before ranking.

**Prefers**

1. Foundation items before a core path item that is blocked by them, or whose
   touched areas overlap theirs and share the contract.
2. A foundation item instead of a feature item that would pre-empt a decision
   the open foundation item is meant to settle.
3. Core path items, thin vertical slices before single-layer work. Count
   unblocking work as core only when the work it unblocks is on the core path.
   Bugs that block the core path or a demo rank here.
4. **Deferred foundation:** foundation items that upcoming core features need,
   above polish and peripheral work.

**Defers:** minor bugs, polish, edge cases, refactors, and peripheral
features.

**Rework risk.** When a feature item ranks before a related foundation item,
its `Reason` names that foundation item and the rework it risks.

**Report basis:**
`- Basis: core features <list> (from <README | roadmap | milestones | labels | user answer>); Deferred foundation: <items, or "none">`

## Lens: stabilize

Severity and regressions first.

**Terms**

- **Severity:** read in this order: a severity signal, else a priority signal
  as recorded severity, else inferred from the item body. Mark an inferred
  severity `inferred` wherever it appears.
- **Release blocker:** an item marked as blocking a release, by label,
  milestone, field, or body.

**Basis.** The calling skill's severity and priority signals; then the item
body.

**Prefers**

1. Higher severity and wider user impact.
2. Regressions and release blockers.
3. Unblocking work, only when the work it unblocks is severe or release
   blocking.

**Defers:** new features.

**Report basis:**
`- Basis: severity from <labels | fields>; inferred for <items, or "none">`

## Report lines

Add under `Current State`:

```markdown
- Lens: <deliver | stabilize>
- Basis: <the lens's report basis>
```
