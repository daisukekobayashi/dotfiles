# Phase Delegation

After implementation, the coordinator hands every component-skill call of the
calling workflow to an agent instead of reading that skill: publication, the
hosted review cycle and each later hosted round, the cleanup Caller preview,
and the cleanup. The agent reads and runs the component skill as a delegated
call under [Delegated Authorization](../SKILL.md#delegated-authorization), so
the skill behaves as it does on its own. The coordinator keeps every dialogue
with the user, the assessment of findings, the decision summary, the merge,
and the final task state checks. No agent asks the user a question.

## Choose the agent

- The hosted review cycle, on every call: the target's worker, continued
  through the host's mechanism for messaging an existing agent. When it cannot
  be continued, dispatch a fresh worker for the same worktree under
  [Worker Dialogue](worker-dialogue.md#assign-the-worker).
- Publication in a workflow without a hosted review cycle, the cleanup Caller
  preview, and the cleanup: a fresh subagent for each call. The preview agent
  ends once it returns the targets and the manifest path. After the merge, a
  fresh cleanup agent receives that manifest path and the user's combined
  confirmation quoted verbatim, and the cleanup skill's own comparison decides
  whether they still match.

Never dispatch an agent for a target while another delegated agent for it is
outstanding.

Delegation is required when the host can dispatch subagents. Without it,
report the limitation; the coordinator then runs the component skill itself,
reading it when its phase starts and, after context compaction, rereading only
the section of the current step.

## Brief the agent

The brief carries the user's actual request, the existing approvals, the exact
target (task, branch, worktree, and the PR and head when known), the component
skill and the call it makes, the records directory, the report path under
[Report path](#report-path), and earlier dispositions and other material as
paths to existing material. Include
[Foreground Checks](../SKILL.md#foreground-checks): a wait for a hosted review
polls in foreground commands with a time bound, and reaching the component
skill's waiting bound is a blocker.

The agent appends the intent and outcome entries of each external action it
takes to the task's `log.md` under Delivery Completion's
[Progress record](completion.md#progress-record), and never writes
`state.md`.

## Return to the coordinator

The agent ends each turn with a report under
[Report Handoff](report-handoff.md#report-file) and the
[Worker summary](report-handoff.md#worker-summary), and its full report holds
the component skill's unchanged final report or output. Its Completion is:

- `complete` when the call finished;
- `question` before any action that its forwarded approvals do not cover,
  with the prepared result under Questions, such as the cleanup targets and
  their manifest path or the push remote candidates;
- `blocked` with the blocker and the last state it checked.

In the hosted review cycle, when Prepare finds anything in the latest review,
the worker stops after Prepare, before any review-fix commit, push, reply, or
resolution, and returns `question` with the prepared dispositions. The
coordinator assesses them under Local Review's
[Assess findings](local-review.md#assess-findings), asks the user what needs a
user decision, and sends the settled dispositions; the worker then continues
the cycle from its review-fix publication through Writeback and the final
state check. A review without findings runs through.

For a `question`, the coordinator asks the user, then continues the same agent
with the user's reply quoted verbatim as the approval for that action alone.
The component skill's own checks, such as the cleanup comparison, still run
before the agent acts.

## Report path

Each return writes a new report on the head the phase started from, under
Delivery Completion's [Progress record](completion.md#progress-record) layout:
`<base12>-<start12>/rh<n>-hosted-a<attempt>.md` for hosted round `n`, and
`<base12>-<start12>/r<phase>-phase-a<attempt>.md` for `publish`, `preview`, or
`cleanup`. Take the next attempt for each return.

The summary's Head is the head the phase ended on. Before
[Check a handoff](report-handoff.md#check-a-handoff), the coordinator reads that
head itself and passes it as `--head`: the PR's current remote source head once
a PR exists, the worktree's `HEAD` before that, and the merged PR head for the
preview and the cleanup. Pass `h<n>` or the phase as `--round`. A Head that
differs from the head the coordinator read fails the check.

## Resume a delegated phase

While a phase is delegated, `state.md` names the phase, the agent, the report
path, and the attempt. On resume, act on the recorded report when it exists and
passes the check. Otherwise continue the recorded agent when the host can
address it. Only when it cannot, dispatch a fresh agent for the next attempt
with the records; that agent resumes through the component skill's own resume
and reconciles the logged external actions under Delivery Completion's
[Resume](completion.md#resume).
