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

For `verify-<app>` with no applicable project verification skill, use the exact
status `not run: no project verification skill`. A known applicable skill may
instead be unavailable on the host or lack an execution prerequisite. Use the
corresponding status and name the gap.

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
- It is invoked at most once per key under [Keys](#keys): once for each pair
  of its registry entry and key, so two entries on the same head or the same
  phase input never suppress each other. One invocation may cover several
  eval cases or several qualifying decisions within its time bound.
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
instead. Before recording the intent, run
[`write-phase-input-key.mjs`](../scripts/write-phase-input-key.mjs) with the
canonical target worktree, full expected HEAD, and a new output path in the
caller's private task records. Use `preflight` with the two exact input files
or `verification` with the worker's reported task paths as NUL-terminated
repository-relative bytes. Supply an empty file when there are no such paths.
Keep the input and output files in private task records outside the worktree.
The script prints only the key on success. If it fails, report
`not run: unavailable` with the reason and continue with the phase's ordinary
work. Use the same inputs and key spelling when resuming an existing pair.

The script writes the exact input the run is given as a sequence of parts in
a fixed order. Each
part is one header line of space-separated ASCII fields ending with byte
counts and a line feed, followed by exactly those bytes, so the file decodes back into its
parts and no two inputs share a file:

- for a preflight run, `decisions <byte count>` with the text of the
  qualifying decisions, then `shared-understanding <byte count>` with the
  shared understanding result they rest on;
- for verification of uncommitted work, `diff <byte count>` with the output
  of `git diff --binary --no-ext-diff --no-textconv --no-color HEAD`, then one
  part for each of the task's new files, the untracked files that the work's
  worker report lists as changed in the task, in byte order of its path:
  `file <git file mode> <path byte count> <content byte count>`, then the
  path's bytes, then the content's bytes. When the report lists no such
  path, add no file part and run no selector. Otherwise take each entry that
  `git --literal-pathspecs ls-files -z --others --exclude-standard -- <those paths>`
  lists and keep it only when its path equals a listed path byte for byte, so
  a listed directory adds none of its descendants. Any other untracked file
  in the worktree stays out of the input and never changes the key.

The git file mode is `100755` for an executable file, `100644` for any other
regular file, and `120000` for a symbolic link, whose content is its target,
so a mode change alone changes the key. The key is
`<phase>:<full HEAD SHA>:<git hash-object of that file>`. The workflow runs
again only when its key changes, such as when an answer changes a qualifying
decision.

The script hashes the recorded bytes without Git filters or writing an
object. Keep the evidence tied to its input when launching, completing, and
reusing a run. For worktree verification, use the helper with a fresh record
path to compare the current input before relying on earlier evidence.

## Accounting

A run on a reviewed head belongs to that head's local review round under
[Local Review](local-review.md#repeat-and-advance) and never adds a round. A
fix it prompts is verified, committed, and reviewed like any other fix, so the
next round counts as usual. A run keyed to a phase input belongs to no round
and counts only against its entry's once-per-key bound.

## Record and report

Record optional workflows in the task's `log.md` under Delivery Completion's
[Progress record](completion.md#progress-record), one `[optional O<n>]` id for
each pair of registry entry and key, with the target, workflow, phase, key,
status, time bound, and report path. Every later entry for the same pair
reuses its id, and the latest entry for an id is current; another entry or
key never reuses it.

When a workflow is skipped before it has a key, such as when no verification
skill applies or the key capture failed, record the status and reason in the
phase's progress entry and the worker's `Optional workflows:`. Include the
target, workflow and phase. The observation has no `[optional O<n>]` pair or
intent, consumes no allowance, and does not increment the run count. Report
it when it is the current phase result. Later evaluation can produce a real
key and use the usual once-per-key rule.

- Before invoking, append an intent entry with status `launching`, like the
  intent entry Progress record sets for an external action, then dispatch the
  run, then append its outcome: `ran`, `stopped: time bound`, or
  `failed: <reason>`.
- An intent entry consumes the pair's once-per-key allowance whatever entries
  follow it: a pair with an intent entry is never invoked again on that key,
  and no `not run` entry is recorded for it after its intent.
- A `not run` status recorded before any intent entry does not consume the
  pair, so it may still be invoked when the trigger, tier, or installation
  changes on the same key.
- On resume, before evaluating any trigger, installation, or tier, reconcile
  each pair whose intent entry has no outcome entry after it; never relaunch
  it. When its report path holds a completed result, record that result as
  its outcome; otherwise record `failed: interrupted` and report it.

`state.md` carries one line with the count of intent entries. A worker lists
each registry entry that applied to its work, with its status, under
`Optional workflows:` in its
[Worker summary](report-handoff.md#worker-summary). The final report under
Delivery Completion's [Report and complete](completion.md#report-and-complete)
lists, per target, the status of each entry's latest `log.md` entry.

## Registry

Each entry is one row. The issue that adds a workflow adds its row, with its
own trigger, tier gate, and time bound, and states its phase text by linking
this reference instead of restating the bounds.

Runs as: who invokes the workflow and in what form; Result: what the run produces, where it goes, and what it may be used as.

| Workflow | Phase | Trigger | Tier gate | Time bound | Key | Runs as | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `architect` | Design preflight draft, under [Worker Dialogue](worker-dialogue.md#draft-and-ask) | A draft question that clears the preflight question bar and whose one-way door is an interface, data shape, or module boundary | All tiers | 15 minutes per invocation | Phase input: `decisions` with the qualifying questions, then `shared-understanding` | The worker, in its own context, for design only, or without delegation the coordinator itself, for design only; a question it would ask the user becomes a draft question | The compared shapes under each qualifying question in `preflight-draft.md`, as input to its recommendation only |
| `arena` | Design preflight draft, after `architect`, under [Worker Dialogue](worker-dialogue.md#draft-and-ask) | After `architect` ran, a qualifying question still has two viable shapes | High | 30 minutes per invocation | Phase input: `decisions` with the still-open questions and `architect`'s compared shapes, then `shared-understanding` | The worker, invoking `arena` explicitly with the user's delivery request and exact target (an explicit `$arena` mention on Codex, the skill call on Claude Code), so this explicit-only skill counts as installed when the agent can invoke it by explicit mention; its isolated delegated candidates return design sketches only, with no file edits or worktrees; without delegation, `not run: unavailable` (no delegation) and no sequential comparison | The candidates, the judge's verdict, and the selected shape under each question in `preflight-draft.md`, as input to its recommendation only |
| `verify-<app>` | Implementation and fix verification under [Worker Dialogue](worker-dialogue.md#project-verification) | One project-owned verification skill can be selected for the changed feature | All tiers | 15 minutes per invocation including setup, execution, evidence, and owned cleanup | Phase input: `verification` with the worktree diff and exact reported untracked files | The worker invokes the selected existing skill on the exact target with the effective budget and existing approvals | Observed checks and coverage limits in the verification record, plus the latest optional status |
