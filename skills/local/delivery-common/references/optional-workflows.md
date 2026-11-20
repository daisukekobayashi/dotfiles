# Optional Workflows

An optional workflow is a skill that a delivery phase runs when it is
installed and its trigger holds, and otherwise reports as not run while the
phase continues. Each one has an entry in the [Registry](#registry); a skill
without an entry is never run as an optional workflow. This frame is the only
exception to [Missing Prerequisites](../SKILL.md#missing-prerequisites): a
missing required skill, reviewer, check, or tool still stops the phase that
needs it. Everything here applies to GitHub and Azure DevOps delivery alike;
the delivery skills of both providers rely on this reference and add nothing
of their own.

## Run or report

When a phase reaches a registry entry for its target, give the entry exactly
one status and continue the phase whatever the status:

- `ran`: the run completed within its time bound;
- `not run: not installed`: the skill is not installed;
- `not run: trigger not met`: the entry's trigger does not hold;
- `not run: tier`: the entry's tier gate excludes the current tier;
- `not run: unavailable`, with the reason: the skill is installed but delivery
  cannot run it, because an execution prerequisite such as a tool, runtime, or
  isolated location it needs is missing, or because the skill's own invocation
  policy does not let delivery invoke it;
- `not run: opted out`: the user's delivery request opts out of it;
- `stopped: time bound`: the run reached its time bound;
- `failed: <reason>`: the run ended with an error.

Only a `ran` result counts as evidence. A run that reaches its bound or fails
is reported and never counted as evidence, and the phase never waits on it or
treats it as a failed required check.

## Installed

A skill is installed when it is listed in the current host's available
skills, the ones the agent can invoke. Do not look for skill directories on
disk, install a skill, or substitute another skill or an informal check for a
missing one. An installed skill whose invocation policy excludes delivery
reports `not run: unavailable` and names that policy.

## Shared bounds

Every registry entry follows these bounds:

- It states its trigger and its tier gate.
- It is invoked at most once per key under [Keys](#keys). One invocation may
  cover several eval cases or several qualifying decisions within its time
  bound.
- Each run has the time bound its entry sets and runs under
  [Foreground Checks](../SKILL.md#foreground-checks).
- Its runs count inside the existing local review round limits under
  [Accounting](#accounting).
- A limit or opt-out the user gives in the delivery request takes precedence
  over the entry: a shorter time bound applies as given, and an opted-out
  workflow reports `not run: opted out`.

## Keys

A run on a committed snapshot is keyed to the reviewed head: its full SHA.

A run before a checkpoint commit, such as for a preflight draft or the
verification of uncommitted fixes, is keyed to its delivery phase's input
instead. Before the run, write the exact input the run is given to a file in
the task's records directory: for a preflight run, the text of the qualifying
decisions and the shared understanding result they rest on; for verification
of uncommitted work, the output of `git diff --binary HEAD` followed by each
untracked task file's path and content. The key is
`<phase>:<full HEAD SHA>:<git hash-object of that file>`. The workflow runs
again only when its key changes, such as when an answer changes a qualifying
decision.

## Accounting

A run on a reviewed head belongs to that head's local review round under
[Local Review](local-review.md#repeat-and-advance) and never adds a round. A
fix it prompts is verified, committed, and reviewed like any other fix, so the
next round counts as usual. A run keyed to a phase input belongs to no round
and counts only against its key's once-per-key bound.

## Record and report

Record each invocation in the task's `log.md` under Delivery Completion's
[Progress record](completion.md#progress-record) as one entry,
`[optional O<n>]`, with the target, workflow, phase, key, status, time bound,
and report path. A later entry for the same key reuses its id, and the latest
entry for an id is current. Before invoking an entry, including on resume,
check the log for its key; a key with a recorded invocation is not invoked
again. `state.md` carries one line with the count of optional runs.

A worker lists each registry entry that applied to its work, with its status,
under `Optional workflows:` in its
[Worker summary](report-handoff.md#worker-summary). The final report under
Delivery Completion's [Report and complete](completion.md#report-and-complete)
lists each entry's latest status per target.

## Registry

Each entry is one row. The issue that adds a workflow adds its row, with its
own trigger, tier gate, and time bound, and states its phase text by linking
this reference instead of restating the bounds.

| Workflow | Phase | Trigger | Tier gate | Time bound | Key | Runs as | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |

No workflow has an entry yet.
