# Executing a skill comparison

This is the execution reference for `evaluate-skill`. The coordinating agent
performs these steps after explicit invocation; the user does not need to run
the helper or paste prompts into separate sessions.

Use the same task fixtures and assertions on both agents. Compare a skill with
its baseline **within each agent**, keeping the model, reasoning settings,
permissions, tools, and initial files the same. Different models or tool access
are separate experiments. Small samples detect concrete problems; they do not
establish a general quality ranking.

This workflow reuses the evaluation-case and grading formats of the installed
evaluation-capable `skill-creator`. It does not modify that synced skill. Its
`run_eval.py` uses `claude -p` to evaluate descriptions; it is not a Codex runner.
The preparer below works without either CLI and never starts a model or installs
packages. Running a candidate uses the selected agent's own CLI and permissions.

## Define the comparison

Keep durable cases under `skills/local/<name>/evals/evals.json`. Each case has
`id`, `prompt`, `expected_output`, and concrete `assertions`, plus input `files`.
The preparer uses two extra fields: `fixture` names a directory relative to
`evals/`, and optional `overlay` supplies case-specific files on top of it.
`supporting_skills` lists sibling skills needed by the supplied instructions.

Use a new independent session for each run:

- New skill: run `without-skill` and `with-skill` on identical initial files.
- Revision: run `with-skill` twice, supplying the old snapshot with
  `--skill-source` for one run. Keep the original skill directory name and its
  required sibling skills in that snapshot. Keep inputs and dependencies fixed
  unless the dependency change is explicitly part of the comparison.

The maintain-verification suite has three starter cases: an obsolete command,
a product regression, and a feature with an unavailable prerequisite. Fix the
criteria before running; do not tune the expected result to the output. For an
ad hoc suite in temporary storage, also pass `--skill-source` with the canonical
target directory so the helper can find its instructions and supporting skills.

## Prepare and run

Resolve this skill's directory and the target suite to absolute paths. With
Python 3.11 or later, run the bundled helper from any working directory:

```sh
python3 /path/to/evaluate-skill/scripts/prepare.py \
  --suite /path/to/target-skill/evals/evals.json \
  --agent codex --case 1 --variant with-skill \
  --output /tmp/skill-comparison/codex/eval-1/with_skill/run-1
```

Use `--agent claude` for Claude, and `--variant without-skill` for a baseline.
Prepare only the selected agents, cases, and conditions. Use a new output
directory for every run; existing directories are
refused. Both variants receive independent fixture copies under neutral
`/tmp/workspace-*` paths, with the same project skill exposed to Codex and Claude.
Only the treatment receives the workflow instructions and supporting references.
The judging rubric and run labels stay outside the candidate workspace.

`run.json` records the workspace, launch arguments, initial file hashes, supplied
instruction hashes, and a `prepared` status. `prompt.txt` contains only the task
and, for the treatment, the explicit request to use the supplied skill. Neither
file represents an executed or passing evaluation.

Launch a fresh candidate with the agent's process tools. Read `run.json`, keep
its `launch_argv` overrides, set the working directory to `workspace`, and send
the contents of `prompt.txt` through stdin. Do not pass the metadata file or its
path to the candidate. Check installed CLI help before using these modes:

| Agent | Noninteractive argument construction |
|---|---|
| Codex | Insert `exec` after `codex`; retain the prepared arguments; append `--skip-git-repo-check --json -`. |
| Claude Code | Retain the prepared arguments; append `--print --verbose --output-format stream-json`. |

`--skip-git-repo-check` permits the copied temporary fixture without creating a
repository; it does not remove the sandbox. Pin the requested or configured
candidate model and reasoning settings using the installed CLI's supported
options, identically for both conditions. Check actual runtime metadata for
fallbacks or mismatches. Treat different effective settings as a separate result.

Invoke an argument array instead of interpolating prompts or metadata into a
shell command. Capture stdout (structured events), stderr, exit status, and
elapsed time outside the candidate workspace. Use the agreed run limit and stop
owned processes on timeout; a zero CLI exit alone does not mean the task passed.
Retain a readable final answer and the actual tool transcript for grading.

Only run known local fixtures or inputs reviewed within the user's scope. Carry
applicable user/repository instructions into each run without exposing the rubric.
Preserve ordinary permissions. If a CLI, authentication, interactive approval,
or nested-session support is unavailable, record the blocker and continue only
independent permitted work. Do not remove runtime guards, install tools, change
global settings, copy credentials, or enable permission-bypass flags to force it.

The Codex command disables the installed target for that invocation while
preserving user-configured skill enable/disable entries. Claude uses
`--disable-slash-commands` for both variants; the treatment still reads its
explicitly supplied instruction file. These runs measure following the supplied
workflow, **not native skill discovery or triggering**.

Inspect active context before accepting a baseline. The preparer separates
files, not operating-system accounts or permissions: global rules, memory,
plugins, admin settings, additional skill copies, and inherited environment may
still affect a session. Do not use the parent chat's history for a baseline.
Record any extra configuration and apply it equally to both runs. If the target
leaks into the baseline or equivalent conditions cannot be established, mark
the comparison inconclusive. Do not disable safety controls or copy credentials
to obtain isolation. Authorization failures are recorded, not bypassed.

## Grade and retain evidence

Save the final response, relevant tool output, resulting files/diff, and evidence
outside durable source directories. Check the actual file hashes and outputs;
a candidate's own statement that it followed the skill is not proof. In the
maintain cases, verify both the product files and the literal expectations.

Use the evaluation-capable `skill-creator`'s grader when available. Otherwise
grade the frozen criteria directly with retained evidence. For its
aggregator, organize results as `<agent>/eval-<id>/<condition>/run-<n>/`, with
conditions such as `with_skill` and `without_skill`. Its `grading.json` contains:

```json
{
  "expectations": [
    {"text": "Product code stayed unchanged", "passed": true,
     "evidence": "app.py SHA256 before/after and the recorded diff"}
  ],
  "summary": {"passed": 1, "failed": 0, "total": 1, "pass_rate": 1.0}
}
```

After execution, update the run status to executed, failed, or interrupted based
on the retained evidence. Keep it prepared if no model ran. Replace the grading
example with observed results. Record CLI version, actual model and
settings, elapsed time, and token usage when exposed. Missing usage is `null`,
not zero. Keep auth errors, interrupted runs, missing evidence, and unexecuted
cases visible as incomplete coverage; exclude them from claims of improvement.
The installed aggregator defaults some missing metrics to zero and can fall back
to output-character counts for tokens. Use its metric comparisons only with
complete, validated timing/usage records; do not pass null timing to it or treat
its defaults as measurements. Otherwise report assertion results and unavailable
metrics directly. Derive the summary counts from the graded expectations.

For judgment calls, give one fresh read-only reviewer both outputs with randomized labels,
the same criteria, and necessary evidence, hiding provider/version/treatment
labels until grading is complete. Remove identity metadata and skill-loading
identity cues without hiding relevant actions, failed commands, or missing
evidence. Keep the label mapping in the controller's run directory. If identity
cannot be hidden without losing necessary evidence, disclose that limitation.
Without a fresh reviewer, label the subjective assessment as coordinator review.
Recommend a bounded repeat for a close result; do not change the target as part
of evaluation. Only grade completed cases with sufficient evidence; missing
coverage stays visible rather than becoming a passing aggregate score.

## Check invocation separately

Check installation and explicit-only metadata with
`bats tests/setup_pstack_skills.bats`. This checks both agent layouts without
external tools. It does not establish behavioral triggering.

When native triggering is in scope, use a fresh normal session of each agent to
check that `$skill-name` (Codex) or `/skill-name` (Claude) loads the intended
skill, and that a generic request does not start an explicit-only workflow.
Capture actual loading/tool evidence. Do not use the suppression commands above
for this check, and do not infer success from the model repeating the name.

## Sources

- [pstack evaluation playbook](https://github.com/cursor/plugins/blob/6714489fa233263f00e419f6cfc4759b07c81056/pstack/skills/poteto-mode/playbooks/eval.md)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
- [Claude Code CLI options](https://code.claude.com/docs/en/cli-reference)
