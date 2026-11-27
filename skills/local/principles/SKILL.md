---
name: principles
description: Index of the working principles adopted from pstack. Consult when two or more fixes that share one premise have failed; when refactoring, sizing a diff, or sequencing an addition, refactor, or rewrite; when tempted to add an abstraction, layer, or signal threading; when integrating a new requirement into an existing design; when debugging; when planning verification, interpreting whether a check's evidence proves the requested behavior, or before declaring work done; before measuring, and before trusting, reporting, or acting on a measured number such as a speedup, regression, throughput, latency, or eval result; or when the same correction or instruction comes up a second time; or when a pstack principle is named, by its title or as `principle-<title>`.
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
- **Covered:** an existing skill or rule makes the principle's core decision;
  read it. A `Delta:` names what it leaves out.
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
  structures, and what concurrent actors share. Covered: `architect`, whose
  Shape the contract step writes the caller's usage and derives state and
  data shapes before code. Upstream: "Get the data shape right before writing
  logic." Delta: concurrent sharing is Separate Before Serializing Shared
  State below; "Scaffold first" is not covered.
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
  Deferred: `codebase-design`'s deletion test removes pass-through modules,
  one of the two axes, but nothing local shrinks the scope of mutable state,
  and no recorded failure asks for it. Upstream: "layers to trace between the
  question and the answer, and hidden or mutable state to hold in their head.
  Guard both."
- **Outcome-Oriented Execution.** Planned rewrites and migrations with phase
  boundaries. Covered: the `durable` stance of `design-preflight`, which does
  not assume compatibility and accepts justified migration work. Upstream:
  "Prioritize end-state integrity over transitional stability." Delta: full
  verification at completion is `principle-prove-it-works`.
- **Experience First.** Product, UX, or feature-scope tradeoffs. Not adopted:
  those tradeoffs are the user's intent, which `shared-understanding` asks
  for, not an agent default. Upstream: "When implementation convenience
  conflicts with user delight, choose delight."
- **Exhaust the Design Space.** A novel decision with no precedent. Covered:
  `arena` for independent candidates, `prototype` for a throwaway answer.
  Upstream: "Build 2-3 competing prototypes and compare side by side before
  committing." Delta: `arena` runs only when explicitly invoked.
- **Build the Lever.** Any non-trivial work: build the tool that does or
  proves it. Not adopted: it conflicts with the global rules' Scope and
  Conduct, which keep changes small and focused on the request. Upstream:
  "No script, codemod, generator, or delegate skill in the diff means you
  didn't apply it."

## Architecture

- **Model the Domain.** Stateful or heavily branching code. Deferred:
  `domain-modeling` keeps the glossary and ADRs, not data structures, and
  `architect` derives domain state only for a change it designs; no recorded
  failure asks for more. Upstream: "Encode the domain in a data structure
  instead of scattering it across conditionals."
- **Boundary Discipline.** Wiring validation, error handling, or adapters.
  Deferred: no local skill or rule places validation at system boundaries,
  and no recorded failure asks for it. Upstream: "Inside, trust the types: no
  re-validation and no redundant nil checks."
- **Type System Discipline.** Designing types or signatures. Deferred: no
  local skill or rule covers it, and no recorded failure asks for it.
  Upstream: "Make the compiler reject impossible states, mismatched
  primitives, and unhandled variants."
- **Make Operations Idempotent.** Steps that run amid crashes and retries.
  Deferred: delivery's resume rules cover delivery only, and no recorded
  failure asks for more. Upstream: "converge to the correct state however
  many times it runs and wherever the previous run stopped."
- **Migrate Callers Then Delete Legacy APIs.** A new internal API while old
  callers exist. Covered: the `durable` stance of `design-preflight`, which
  makes a breaking change instead of adding a compatibility shim and removes
  or renames an awkward interface before it spreads. Upstream: "Migrate
  callers and delete the old API in the same wave instead of preserving
  compatibility layers."
- **Separate Before Serializing Shared State.** Concurrent actors might write
  the same file, branch, key, or object. Covered: one target, one branch, and
  one worktree per worker in the start skills, and
  `local-runtime-port-isolation` for host ports. Upstream: "Default to giving
  each actor its own file, key, branch, or state directory." Delta: shared
  state outside those cases is not covered.

## Verification

- **Prove It Works.** Before declaring done. Leaf:
  [principle-prove-it-works](../principle-prove-it-works/SKILL.md).
- **Fix Root Causes.** Debugging. Leaf:
  [principle-fix-root-causes](../principle-fix-root-causes/SKILL.md).
- **Sequence Work into Verifiable Units.** Multi-step work and how commits
  and PRs stack. Covered: `karpathy-guidelines`' Goal-Driven Execution, which
  plans each step with its check, and `tdd`'s vertical slices. Upstream:
  "Order work as small units that each end in a state you can check, and do
  not advance until the current one is green." Delta: ordering commits so
  the sequence proves itself is not covered.
- **Test Behavior, Not Implementation.** Writing, changing, or keeping a
  test. Covered: `tdd`, whose tests verify behavior through public
  interfaces and name implementation-coupled tests an anti-pattern.
  Upstream: "Assert what the code's users can observe."
- **Explain the Number.** Before measuring, and before trusting, reporting,
  or acting on a measured number. Leaf:
  [principle-explain-the-number](../principle-explain-the-number/SKILL.md).

## Delegation

- **Guard the Context Window.** Large outputs, long files, or fan-out.
  Covered: delivery's report handoff, which keeps full reports in files and
  returns summaries. Upstream: "Route bulk to subagents; keep summaries in
  the main thread, not raw payloads." Delta: outside delivery, not covered.
- **Never Block on the Human.** Tempted to ask about reversible work.
  Covered: the global rules' Approval tiers, which proceed and report on local
  reversible work and ask before outward or irreversible actions. Upstream:
  "Reversible actions (write code, edit notes, split tasks) should proceed
  without blocking." Delta: outward actions such as a push or a PR need one
  approval, and delivery returns contract and boundary decisions to the user.

## Meta

- **Encode Lessons in Structure.** The same instruction or correction comes
  up a second time. Leaf:
  [principle-encode-lessons-in-structure](../principle-encode-lessons-in-structure/SKILL.md).

## Source

Adapted from the Principles section of Lauren Tan's
[pstack poteto-mode](https://github.com/cursor/plugins/blob/0b46ec399d55f2829e88822998f53b84944837d3/pstack/skills/poteto-mode/SKILL.md).
Each `Upstream:` quote is from that commit's
`pstack/skills/principle-<title>/SKILL.md`, the leaf for that principle.
Local changes: the index is its own skill, consulted by its description
instead of a mode the user enters; each principle has a disposition, and only
leaves link here. Principles are named on the line that reports the decision,
not in a separate list. See [LICENSE](LICENSE).
