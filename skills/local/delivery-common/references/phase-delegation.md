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
  fresh cleanup agent receives that manifest path, its hash, and the user's
  combined confirmation quoted verbatim. It checks that the file still has that
  hash, runs the cleanup skill with that file as the confirmed manifest, and
  the skill's comparison decides whether the targets still match.

One agent acts on a target at a time. Never dispatch an agent for a target
while another delegated agent for it is outstanding. Before each external
action and each removal, the agent checks that `state.md` still names its
agent and attempt, and stops without acting when it does not.

Delegation is required when the host can dispatch subagents. Without it,
report the limitation; the coordinator then runs the component skill itself,
reading it when its phase starts and, after context compaction, rereading only
the section of the current step.

## Brief the agent

The brief carries the user's actual request, the existing approvals, the exact
target (task, branch, worktree, and the PR and head when known), the component
skill and the call it makes, the agent's name and attempt as `state.md` records
them, the records directory, the report path under
[Report path](#report-path), and earlier dispositions and other material as
paths to existing material. For the hosted cycle's fixes, forward the
[classified verification format](report-handoff.md#classified-verification)
and the task records used by [Project verification](worker-dialogue.md#project-verification).
For the preview and the cleanup, it also assigns
the manifest path: the report path with `.manifest.json` in place of `.md`,
which the cleanup skill creates as a new file. Include
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
- `question` before any action that its forwarded approvals do not cover, and
  for a preview that returns targets, which asks for the combined
  confirmation;
- `blocked` with the blocker and the last state it checked.

The summary's labels carry what the next step needs:

- Target: the worktree, branch, and task, and the PR's URL and ID once a PR
  exists.
- Head: the head the phase ended on, under [Report path](#report-path).
- Verification: one line each for the component skill's status, such as the
  cycle's status or the publish result, and for a hosted round the published
  head and the head the hosted review covered. Include the classified rows
  from the check of the settled hosted fixes when there are such checks. Phase
  status rows stay on the ordinary worker format. Check the hosted fix rows
  against the classified syntax in their Prepare or recheck record. Use the
  ordinary v1 check for the outer phase report, which also carries status.
- Questions: the prepared result to decide on: the prepared dispositions, the
  push remote candidates, or the cleanup targets as the manifest command
  printed them with the manifest path.
- Blockers: the blockers and the component's open items.

When the Caller preview returns no preview, such as on a non-zero status of
its manifest command, the preview agent returns `complete` with a Verification
line saying no preview and why. The coordinator then presents the merge alone,
and the cleanup keeps its own confirmation after the merge.

The coordinator opens the full report only for a named field: the hosted
cycle's Final Report `Not applied` items, which it records as the provider
delivery skill says. For the preview and the cleanup, it presents the targets
from the manifest file at the assigned path, not from the summary, and records
the file's SHA-256 with the report.

In the hosted review cycle, when Prepare finds anything in the latest review,
the worker stops after Prepare, before any review-fix commit, push, reply, or
resolution, and returns `question` with the prepared dispositions. The
coordinator assesses them under Local Review's
[Assess findings](local-review.md#assess-findings) and sends the settled
dispositions. Before the cycle's review-fix publication, the worker makes the
worktree match them: it removes the edits of every fix not settled as
`applied`, makes any change they add, and reruns the smallest relevant
verification when a file changed after Prepare's verification. It then
commits, pushes, replies, and resolves only as the settled dispositions say,
through Writeback and the final state check, and returns `blocked` when the
worktree cannot be matched without touching other changes. A review without
findings runs through.

For a `question`, the coordinator asks the user only what needs the user's
decision or an approval not already forwarded; it answers the rest from its own
assessment. It continues the same agent with the answer, quoting the user's
reply verbatim as the approval for that action alone. The preview's answer
goes to the cleanup agent after the merge instead. The component skill's own
checks, such as the cleanup comparison, still run before the agent acts.

## Report path

Each return writes a new report on the head the phase started from, under
Delivery Completion's [Progress record](completion.md#progress-record) layout:
`<base12>-<start12>/rh<n>-hosted-a<attempt>.md` for hosted round `n`, and
`<base12>-<start12>/r<phase>-phase-a<attempt>.md` for `publish`, `preview`, or
`cleanup`. Take the next attempt for each return.

The summary's Head is the head the phase ended on. Before
[Check a handoff](report-handoff.md#check-a-handoff), the coordinator reads that
head itself and passes it as `--head`: the worktree's `HEAD` before a PR
exists; the PR's current remote source head after that, which for the preview
is the head to be merged that the Caller preview checks; and for the cleanup
the source head of the merged PR. Pass `h<n>` or the phase as `--round`. A
Head that differs from the head the coordinator read fails the check.

## Resume a delegated phase

While a phase is delegated, `state.md` names the phase, the agent, the report
path, and the attempt. On resume of any delegated phase other than cleanup:

1. Read the latest report that passes the check, if any. A `complete` report
   gives the result; a `question` report gives the prepared result to decide
   on. Recorded assessments carry forward; ask the user again for an approval
   that the records show but this context did not receive, since a progress
   record is not authorization.
2. Continue the recorded agent when the host can address it, with the answer
   when there is one.
3. Otherwise, dispatch a fresh agent only when the host shows the recorded
   agent has ended; when it cannot show that, report the target `Blocked`.
   Before dispatching, write the new agent and attempt to `state.md`, so the
   old agent's check before acting stops it. Give the fresh agent the records,
   the latest report path, and the answer. It resumes through the component
   skill's own resume and reconciles the logged external actions under
   Delivery Completion's [Resume](completion.md#resume) before acting.

A delegated cleanup, including its Caller preview, is never resumed. On a
resume, before or after the first confirmation, the coordinator first records
the resume in `state.md` with a new attempt, so the cleanup agent's check
before each removal stops it, and only then tells the cleanup agent, continued
or fresh, that it is a resume. The agent removes nothing and returns `blocked`,
listing which previewed or confirmed targets are gone and which remain, or
stating that it could not observe them. The coordinator reports this to the
user, and the cleanup is redone by the provider's cleanup skill run on its own,
with its own target listing, confirmation, and checks. An interrupted Caller
preview counts as no preview: the coordinator presents the merge alone.
