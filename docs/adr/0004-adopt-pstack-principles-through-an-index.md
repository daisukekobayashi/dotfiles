---
status: accepted
---

# Adopt pstack principles through an index

[日本語](0004-adopt-pstack-principles-through-an-index.ja.md)

## Context

Upstream pstack ([`cursor/plugins@0b46ec3`](https://github.com/cursor/plugins/tree/0b46ec399d55f2829e88822998f53b84944837d3/pstack))
ships 24 principles, each as its own `principle-<title>` skill with
`disable-model-invocation: true`. `poteto-mode` lists them in its Principles
section, reads the leaf of each principle it applies, and names the principle
and the decision it changed.

[ADR 0001](0001-pstack-principles-in-delivery.md) read pstack as two
principles, check the real thing and encode repeated mistakes in structure,
and wrote short rules into delivery phase text. Locally, `prove-it-works`,
`encode-lessons-in-structure`, and `explain-the-number` were separate `base`
skills with no index, and the restraining principles existed only as a partial
global rule from [#310](https://github.com/daisukekobayashi/dotfiles/issues/310).
In [#255](https://github.com/daisukekobayashi/dotfiles/issues/255)'s delivery
([PR #309](https://github.com/daisukekobayashi/dotfiles/pull/309)), local review
found new defects in one area for four rounds while each fix added steps under
one shared premise, and the recommended design was much heavier than the
upstream skill it adapted. While scoping
[#311](https://github.com/daisukekobayashi/dotfiles/issues/311), a one-sentence
delivery rule per principle was found to drop parts of each rule and to apply
only inside delivery.

## Decision

### Index and leaves

A `principles` skill is the index. It lists all 24 upstream principles, each
with when it applies and one disposition:

- **Leaf:** adopted on evidence; a `principle-<title>` skill holds the full
  rule.
- **Covered:** an existing skill or rule makes the same decision, such as
  `arena` for Exhaust the Design Space or the global approval tiers for Never
  Block on the Human.
- **Not adopted:** it conflicts with local rules or has nothing to apply to,
  with the reason.
- **Deferred:** no conflict, but no recorded evidence yet. A recorded
  recurrence or failure, cited in an issue, can promote it to a leaf.

The leaves are `principle-attack-the-premise`,
`principle-subtract-before-you-add`, `principle-laziness-protocol`,
`principle-fix-root-causes`, and `principle-redesign-from-first-principles`,
selected on #255's evidence, plus `principle-prove-it-works`,
`principle-encode-lessons-in-structure`, and `principle-explain-the-number`,
renamed from their earlier names to match upstream. No skill is kept under an
old name; a user reruns the skills setup, which drops links to skills that no
longer exist.

The index is the only principle skill an agent invokes by itself: its
description names the situations in which the leaves apply. The leaves are
explicit-only on both agents (`disable-model-invocation: true` and
`allow_implicit_invocation: false`), as upstream, and are read from the index
or from a workflow skill's link. To apply a principle, an agent reads its leaf
or target in full and names the principle and the decision it changed on the
line that reports that decision; no separate report field records it.

The new leaves keep the upstream text. Where a leaf conflicts with the
approval, safety, or scope rules that apply to a task, those rules win, and
the leaf's `Source` section lists the delta. Leaves and the index add no rule
that grants, limits, or gates agent authority.

### Dependency policy

The index links its eight leaves, so `skills export` carries them with it and
excluding a leaf the index needs fails. It names covered skills, global rules,
and external skills without linking them. Leaves do not link the index.
Workflow skills keep their links to the leaves they use.

Delivery does not depend on the index: `delivery-common` names it without a
link, and its phase rules hold when it is not installed, as ADR 0001's
dependency policy already requires for every pstack skill. An exported
`github` bundle therefore still adds only `delivery-common` and
`worktree-runtime-cleanup` as dependencies.

### Roles

- Global rules in `ai-rules/base/global.md` carry short always-on forms, such
  as the recurring-failure and completion-evidence rules. They stay within
  their word limit and do not point to the index.
- The index and its leaves carry the full rules and are read when a
  principle applies, inside or outside delivery.
- Delivery phase text names when a phase applies a principle, under ADR 0001.
  Wiring delivery phases to the restraining leaves is #311's work.

## Considered Options

- **One delivery rule per principle.** Rejected: it drops parts of each rule
  and applies only inside delivery.
- **Import all 24 principles as leaves.** Rejected: principles are selected on
  evidence for this environment.
- **Model-invocable leaves.** Rejected: one entry point keeps one description
  in every agent's skill list and matches upstream.
- **A global-rule pointer to the index.** Rejected for now: `global.md` is at
  its word limit, and a pointer would displace an agreed rule.
- **A start-of-task trigger, as `poteto-mode` uses.** Rejected: upstream reads
  the index only inside a mode the user enters; an always-on description with
  that trigger would load the index for nearly every task.
- **Stubs under the old names.** Rejected: no public contract or stored data
  depends on them, and setup drops the old links.

## Consequences

- An agent reaches a restraining principle outside delivery only when the
  index's description matches its situation. Delivery reaches it through
  #311's phase text.
- Users rerun the skills setup after the rename; until then, the installed
  links under the old names are broken.
- Promoting a deferred principle needs recorded evidence and a leaf, and the
  index row changes with it.
