---
status: accepted
---

# Apply pstack principles across the delivery workflow

[日本語](0001-pstack-principles-in-delivery.ja.md)

[#245](https://github.com/daisukekobayashi/dotfiles/issues/245) implemented
the run-to-prove part of the Review row, recorded in
[ADR 0002](0002-run-to-prove-isolation.md). The rest of the implementation is
pending in the child issues of
[#246](https://github.com/daisukekobayashi/dotfiles/issues/246). Until they
land, this record describes the chosen design, not current delivery behavior;
[Skills Profile Design](../skills-profiles.md) describes current behavior.

## Context

The local pstack skills (`how`, `why`, `architect`, `arena`, `interrogate`,
`blast-radius`, `prove-it-works`, `encode-lessons-in-structure`,
`create-verification-skill`, `maintain-verification-skill`, `evaluate-skill`)
form the separate `pstack` profile. No delivery skill (`delivery-common`,
`github-issue-delivery`, `azure-devops-work-item-delivery`, `change-*review`)
names any of them, and delivery's prerequisites are `base,github` or
`base,azure-devops`. In #239's delivery, reviews of skill-text changes traced
the instructions without exercising them with an agent, although
`evaluate-skill` exists for that.

pstack reduces to two principles: check the real thing instead of a proxy, and
encode repeated mistakes in structure. Both already apply to every agent as
global rules in `ai-rules/base/global.md` ("Match completion claims to observed
evidence ..." and "When the same confirmed failure recurs, write down the
premise the failed fixes share and first consider removing the mechanism
behind it, then a small safeguard near its cause ..."). The rules below refine
that baseline for specific delivery phases; they do not replace it.

## Decision

### Dependency policy

Delivery applies the principles through short rules written into
`delivery-common` phase text, so they hold without any pstack skill installed.
In addition, the heavier pstack workflows are **optional workflows**: delivery
runs one automatically when it is installed and its trigger holds, and
otherwise reports `not run: not installed` or `not run: trigger not met` and
continues the phase. An installed optional workflow whose execution
prerequisites, such as a tool, runtime, or isolated location it needs, are
unavailable reports `not run: unavailable`, and the phase also continues. The
optional workflows are `architect`, `arena`, `blast-radius`, `evaluate-skill`,
a project's own `verify-<app>` skill, and the measurement workflows that #240
adapts.

This is the only exception to Missing Prerequisites: a missing required skill,
reviewer, check, or tool still stops the phase that needs it.

Delivery invokes `arena`, `blast-radius`, `evaluate-skill`, and
`benchmark-checklist` the way it already invokes `change-*review`: their
`SKILL.md` drops `disable-model-invocation`, their Codex metadata keeps
`allow_implicit_invocation: false`, and their description adds that the skill
also runs as its step of an explicitly user-requested `github-issue-delivery`
or `azure-devops-work-item-delivery` workflow. The "Run only ..." guard at the
start of each skill's body gains the same
scoped delivery exception, as the `change-*review` bodies state it, and the
implementing issues test both. Outside delivery they stay explicit-only.

### Phase mapping

| Phase | Principle | Verdict | Delivery behavior | Reason |
|---|---|---|---|---|
| Shared understanding and preflight | Ground claims in traced code and history | Adjusted | Drafts cite the traced path or recorded rationale, the `how` and `why` method. When a preflight draft has a one-way-door decision about an interface, data shape, or module boundary, the worker runs `architect` for it and shows the compared shapes. | Citation and option rules already exist; running `architect` only on one-way doors bounds its cost to the decisions preflight already isolates. |
| Preflight, High tier | Compare independent candidates | Adopted | When such a decision still has two viable shapes after `architect`, the worker runs `arena` for it. | `arena` runs isolated writers, so it is limited to an open one-way door at the tier that already escalates procedure. |
| Implementation verification | Check the real thing, not a proxy | Adopted | Each verification is labeled as the changed path run or a proxy only. When the target project has its own `verify-<app>` skill for the changed feature, the worker runs it. Delivery never runs `create-verification-skill` automatically. | Proxy-only checks went unlabeled; a project's `verify-<app>` skill is part of the target, while generating one would add files outside the task. |
| Skill and instruction changes | Exercise changed instructions with an agent | Adopted | At Medium and High tier, when a delivery changes skill or agent-instruction text, such as a skill or an instruction file like `AGENTS.md`, it invokes `evaluate-skill` once on the current agent under a time bound, in a delivery smoke mode: one existing eval case per changed skill, each run once with the changed instructions and no baseline session, so `evaluate-skill`'s usual baseline and treatment comparison does not run in delivery. Changed text with no applicable eval case, including an instruction-only change, is reported as not exercised; Low tier reports `not run: tier`. | Closes the gap #239 showed, at a cost a delivery can absorb; a full `evaluate-skill` comparison per delivery costs too much. |
| Review | Findings proven by a run | Adopted, in two parts | #245 makes `change-adversarial-review` back findings with runs; `change-review` and `change-security-review` are unchanged. At High tier, delivery also runs `blast-radius`, reusing #245's isolation, cleanup, and evidence rules. | One isolation design serves both; High tier already escalates review. |
| Performance claims | Explain the number before reporting it | Adopted, conditional | The inline rule applies to every claimed speedup or regression number in delivery output. When a worker's own implementation or fix report claims one, the worker runs `benchmark-checklist`, the measurement workflow #240 adapts, as an optional workflow in its verification, before reporting. | The trigger is narrow; a change with no claimed number never runs them. |
| Completion | Encode repeated mistakes in structure | Adjusted | Follow-up candidates gain a fourth creation criterion: the same finding class recurred at least twice across rounds or deliveries, with a proposed structural safeguard. `encode-lessons-in-structure` shapes the proposal when installed; otherwise the inline rule applies. Delivery never runs `correct` automatically. | The current criteria would recommend dropping such candidates; `correct` edits the repository beyond the task. |

### Cost bounds

Every optional workflow follows shared rules:

- it has a stated trigger and tier gate;
- it is invoked at most once per reviewed head; one invocation may cover
  several eval cases or several qualifying decisions within its time bound;
- a run before a checkpoint commit, such as for a preflight draft or the
  verification of uncommitted fixes, is keyed to the input of its delivery
  phase instead of a reviewed head;
- each run has a time bound;
- its runs count inside the existing local review round limits;
- a run that reaches its bound is reported and never counted as evidence;
- a limit or opt-out the user gives in the delivery request takes precedence.

The foundation issue below defines this shared accounting, including the
exact keying by phase input, within the local review budget. Each row's issue
sets the numbers, such as the time bound, for its own workflow.

### Provider parity

Everything above, including the detection of installed skills and the
`not run` reporting, lives in `delivery-common` and applies to GitHub and
Azure DevOps delivery alike. No part is provider-specific.

### Implementation order

A foundation issue adds the optional-workflow frame, the Missing Prerequisites
exception, and the cost bounds to `delivery-common`. Each row's issue builds
on it, and the `architect` and `arena` rows share one preflight issue. The
`blast-radius` step also waits for #245, and the performance step for #240.

## Considered Options

- **Principle rules only, with no optional workflows.** Delivery would behave
  the same with or without pstack installed, but the heavier checks would run
  only when the user named them.
- **Move `how`, `why`, and `prove-it-works` into `base`.** This would change
  every `base` install and split the `pstack` profile, while the principles
  those skills carry already reach every agent through the global rules.
- **Automatic `create-verification-skill`, `correct`, or full `evaluate-skill`
  comparisons.** These were rejected because they generate files outside the
  task, edit the repository beyond the task, or cost more than one delivery can
  absorb.

## Consequences

- With the optional workflows, delivery depth depends on what is installed. The
  `not run` lines in reports make that visible.
- The explicit-only rule for `arena`, `blast-radius`, `evaluate-skill`, and
  `benchmark-checklist` gains a delivery exception, and the tests that pin
  those skills' metadata and the Missing Prerequisites text change with the
  implementing issues.
