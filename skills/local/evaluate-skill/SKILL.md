---
name: evaluate-skill
description: Use only when explicitly invoked to compare a skill against a baseline or previous version on Codex or Claude Code, or as the Local Review smoke step of an explicitly user-requested `github-issue-delivery` or `azure-devops-work-item-delivery` workflow for named issues or Work Items.
license: MIT
---

# Evaluate Skill

Run only when the user explicitly invokes `$evaluate-skill` in Codex or
`/evaluate-skill` in Claude Code, or as the Local Review smoke step of the user's
explicit request for `github-issue-delivery` or `azure-devops-work-item-delivery`.
A caller must forward that request and exact target. For the delivery step,
follow Delivery smoke below. Direct invocation uses the comparison
workflow below.

## Delivery smoke

1. Take the coordinator's pinned head, changed instruction paths, approved
   case inputs and launch settings, private evidence location, and effective
   deadline. Give preparation a fresh private scratch directory for this
   invocation as `TMPDIR`. Store evidence outside that directory. Follow
   Prepare and run in the [execution reference](references/execution.md)
   for fresh isolated sessions on the current agent. Prepare only `with-skill`
   using the changed instructions,
   run one selected existing case once for each applicable changed skill,
   and start zero baseline sessions. An empty selection starts no session.
   If a case cannot run within the approved settings, leave its paths
   uncovered. Use the remaining time for evidence and cleanup.
2. Return the head and, for each case, its skill, case ID, status, evidence
   location, and the changed paths it actually exercised. Check observed
   commands and artifacts against the case criteria. Record failures and
   incomplete runs with their reasons. A prepared candidate or a zero exit
   without evidence does not show that instructions ran. Return
   `changed instructions not exercised by an agent` for each uncovered path.
   Stop owned work on expiry. Retain private evidence and remove the owned
   scratch directory after success, failure, or timeout. Report any remaining
   scratch path in the private verification record. Return without entering
   the standalone comparison or comparative grading.

## Frame the comparison

Own the comparison from task selection through execution, grading, and synthesis.
Use the available agent tools; do not hand the user a preparation command and
call the evaluation complete. The bundled helper handles repeatable file setup,
while these instructions control the experiment and interpret its evidence.

Locate the target skill's canonical source and any existing `evals/evals.json`.
Compare supplied instructions with no supplied instructions, or a frozen old
version with the current version. Keep the target and its dependencies unchanged
while measuring. Evaluation does not authorize changing or promoting the skill.

Use the current agent unless the user selects another or requests both. Compare
conditions within each agent with the same model, reasoning settings, permissions,
tools, and initial files. Report Codex and Claude results separately; changing
models is a separate experiment. Pin the available candidate model/settings
before the first run and retain them for its counterpart.

Start with a small, bounded set of representative cases and one run per condition.
Reuse the target's existing cases where suitable; otherwise write a few realistic
tasks in temporary storage. Fix observable criteria before viewing candidates.
Include a meaningful failure or unavailable-prerequisite case when relevant.
State the cases, run count, and execution limits before starting. Keep expensive
extensions within the user's authorized budget; do not repeat runs indefinitely.

Read [the execution reference](references/execution.md) for case format, isolated
launches, and evidence formats. Reusable cases remain with the target skill;
session plans, label mappings, transcripts, and scores belong in `/tmp` or an
ignored work directory. Do not create durable cases without authorization.

## Prepare and run candidates

Use [scripts/prepare.py](scripts/prepare.py) for a supported fixture suite. Resolve
resources relative to this skill, so an installed link works from any project.
For other tasks, prepare equivalent independent inputs with the available tools.
Never rearrange the user's checkout to isolate candidates.

Keep the rubric, comparison labels, other candidates, and this coordinator's
conversation outside candidate context. Use neutral workspace names and an
ordinary user task. Supply only the task, applicable user/repository constraints,
and the selected skill version when applicable. Do not ask candidates which
principles or skills they used; inspect actual actions and artifacts afterward.

Execute each task in a fresh session with the prepared workspace and prompt.
Use independent native workers only when fresh context, target-skill visibility,
model/settings, tools, and permissions can be controlled equivalently. Otherwise
use the selected CLI's noninteractive mode from the execution reference. Do not
resume an earlier conversation. Two concurrent candidates are enough; sequential
fresh sessions are also valid. Do not permit unbounded nested delegation.

Inspect ambient rules, memory, plugins, extra skill copies, and inherited settings
before accepting a baseline. The helper isolates files and turns off the runner's
hooks, plugins, memories, and MCP servers on both agents; turning off these
runner extensions is isolation, not a removed safety control. Keep its prepared
arguments, and inspect what they leave on.
If the target leaks into the baseline or conditions differ materially, report the
comparison as inconclusive. Preserve safety controls and approval boundaries.
Unavailable authentication, permissions, tools, or isolation are missing coverage,
not a reason to bypass controls or substitute the coordinator's own answer.

Retain transcripts/tool output, final answers, initial and final files or hashes,
and relevant diffs. Record actual model/settings, CLI version, execution status,
elapsed time, and exposed usage. Missing measurements stay unknown. Stop owned
processes at the limit and retain evidence of failed or interrupted attempts.

## Grade and synthesize

Check objective criteria against commands, file contents, and artifacts, rather
than candidate self-report. For judgment calls, give one fresh read-only judge
both completed outputs under randomized neutral labels and the same criteria.
Keep provider, version, and treatment identities out of its context until grading
finishes. Use an independent model family when available and authorized; disclose
same-model judging. The judge receives evidence, not the coordinator's conclusions.

If independent judging is unavailable, still report observable checks and label
subjective assessments as coordinator review. Do not call them blinded or
independent. Read every candidate, reconcile the judge's claims with actual
evidence, and retain disagreements or incomplete checks.

Report the comparison, conditions, per-case outcomes, failures/missing coverage,
evidence locations, measured cost/time when available, and a recommendation.
Distinguish prepared, executed, and graded runs. A completed comparison may show
no benefit or a regression; a small sample is diagnostic, not a general ranking.
Recommend another bounded run for close results rather than claiming an advantage.
Installation checks and native skill triggering are separate from this supplied-
instruction comparison. Do not edit the target or install a winner implicitly.

## Source

Adapted from Lauren Tan's [pstack Eval playbook](https://github.com/cursor/plugins/blob/6714489fa233263f00e419f6cfc4759b07c81056/pstack/skills/poteto-mode/playbooks/eval.md).
This local standalone skill packages that playbook's experiment design, isolated
candidates, blinded judging, and artifact inspection. Local differences are
explicit invocation on both agents, delivery smoke, fixed-model skill comparisons,
bounded runs, a bundled preparation helper, and honest fallbacks when isolation
or independent judging is unavailable. See [LICENSE](LICENSE).
