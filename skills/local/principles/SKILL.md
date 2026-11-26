---
name: principles
description: Index of the working principles adopted from pstack. Consult when two or more fixes that share one premise have failed, when sizing or sequencing an addition, refactor, or rewrite, when tempted to add an abstraction or layer, when integrating a new requirement into an existing design, when debugging, before declaring work done, before measuring or reporting a measured number, or when the same correction repeats.
license: MIT
---

# Principles

This index lists each of pstack's 24 principles with when it applies and how
it is adopted here. Principles are selected for this environment on evidence,
not imported wholesale.

## Apply a principle

Read the leaf or target in full for any principle you apply; the one-line
summary below is not the rule. When a principle shapes a decision, name the
principle and the decision it changed on the line that reports that decision,
such as a recommendation's reason, a chosen default, or a follow-up. Name only
principles whose leaf or target you read for this task.

## Dispositions

- **Leaf:** adopted on evidence; the leaf holds the full rule.
- **Covered:** an existing skill or rule makes the same decision; read it.
- **Not adopted:** it conflicts with local rules or has nothing to apply to
  here; the reason is given.
- **Deferred:** no conflict, but no recorded evidence yet. A recorded
  recurrence or failure, cited in an issue, can promote it to a leaf.

Each leaf is the `principle-<title>` skill, with the title in kebab case.
Leaves are not invoked implicitly; reach them through this index or by
explicit invocation.

## Core

- **Laziness Protocol.** Refactoring, sizing a diff, or tempted to add
  abstractions or layers. Leaf:
  [principle-laziness-protocol](../principle-laziness-protocol/SKILL.md).
- **Foundational Thinking.** Before writing logic: core types, data
  structures, and what concurrent actors share. Covered: `architect`, which
  writes the caller's usage and data shapes first.
- **Redesign from First Principles.** Integrating a new requirement into an
  existing design. Leaf:
  [principle-redesign-from-first-principles](../principle-redesign-from-first-principles/SKILL.md).
- **Attack the Premise.** Two or more fixes that share one premise have
  failed the same gate. Leaf:
  [principle-attack-the-premise](../principle-attack-the-premise/SKILL.md).
  The global rule on recurring failures gives its short form.
- **Subtract Before You Add.** Sequencing an addition, refactor, or rewrite.
  Leaf: [principle-subtract-before-you-add](../principle-subtract-before-you-add/SKILL.md).
- **Minimize Reader Load.** Reviewing or shaping code that is hard to trace.
  Deferred.
- **Outcome-Oriented Execution.** Planned rewrites and migrations with phase
  boundaries. Covered: the `durable` stance of `design-preflight`, which does
  not assume compatibility and accepts justified migration work.
- **Experience First.** Product, UX, or feature-scope tradeoffs. Not adopted:
  those tradeoffs are the user's intent, which `shared-understanding` asks
  for, not an agent default.
- **Exhaust the Design Space.** A novel decision with no precedent. Covered:
  `arena` for independent candidates, `prototype` for a throwaway answer.
- **Build the Lever.** Any non-trivial work: build the tool that does or
  proves it. Deferred: it can widen a change beyond the request, so adopting
  it needs evidence and a scope.

## Architecture

- **Model the Domain.** Stateful or heavily branching code. Deferred.
- **Boundary Discipline.** Wiring validation, error handling, or adapters.
  Deferred.
- **Type System Discipline.** Designing types or signatures. Deferred.
- **Make Operations Idempotent.** Steps that run amid crashes and retries.
  Deferred; delivery's resume rules cover delivery only.
- **Migrate Callers Then Delete Legacy APIs.** A new internal API while old
  callers exist. Covered: the `durable` stance of `design-preflight`, which
  removes or renames an awkward interface before it spreads.
- **Separate Before Serializing Shared State.** Concurrent actors might write
  the same file, branch, key, or object. Covered: one target, one branch, and
  one worktree per worker in the start skills, and
  `local-runtime-port-isolation` for host ports.

## Verification

- **Prove It Works.** Before declaring done. Leaf:
  [principle-prove-it-works](../principle-prove-it-works/SKILL.md).
- **Fix Root Causes.** Debugging. Leaf:
  [principle-fix-root-causes](../principle-fix-root-causes/SKILL.md).
- **Sequence Work into Verifiable Units.** Multi-step work and how commits
  and PRs stack. Deferred.
- **Test Behavior, Not Implementation.** Writing, changing, or keeping a
  test. Covered: `tdd`.
- **Explain the Number.** Before measuring, and before trusting, reporting,
  or acting on a measured number. Leaf:
  [principle-explain-the-number](../principle-explain-the-number/SKILL.md).

## Delegation

- **Guard the Context Window.** Large outputs, long files, or fan-out.
  Covered: delivery's report handoff, which keeps full reports in files and
  returns summaries.
- **Never Block on the Human.** Tempted to ask about reversible work.
  Covered, adjusted: the approval tiers in the global rules. Upstream's
  external actions without asking are not adopted.

## Meta

- **Encode Lessons in Structure.** The same instruction or correction comes
  up a second time. Leaf:
  [principle-encode-lessons-in-structure](../principle-encode-lessons-in-structure/SKILL.md).

## Source

Adapted from the Principles section of Lauren Tan's
[pstack poteto-mode](https://github.com/cursor/plugins/blob/0b46ec399d55f2829e88822998f53b84944837d3/pstack/skills/poteto-mode/SKILL.md).
Local changes: the index is its own skill, consulted by its description
instead of a mode the user enters; each principle has a disposition, and only
leaves link here. Principles are named on the line that reports the decision,
not in a separate list. See [LICENSE](LICENSE).
