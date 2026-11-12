# Skill evaluation with Codex and Claude Code

Invoke `evaluate-skill` to compare a skill against a baseline or previous version.
The skill coordinates case selection, isolated candidate execution, grading, and
an evidence-based recommendation. It is included in the `pstack` profile and uses
one instruction body on both agents.

```text
Codex:       $evaluate-skill maintain-verification-skill
Claude Code: /evaluate-skill maintain-verification-skill
```

By default it evaluates on the current agent. Request both agents explicitly to
run the same cases on Codex and Claude, comparing conditions within each agent.
Keep model, settings, permissions, tools, and initial files fixed within a pair.
Small samples reveal concrete problems; they do not establish a general ranking.

The [skill entrypoint](../skills/local/evaluate-skill/SKILL.md) owns the procedure.
Its [execution reference](../skills/local/evaluate-skill/references/execution.md)
and bundled `scripts/prepare.py` contain the preparation and execution details.
Users do not need to run an external preparation command. The agent uses the
helper for repeatable file setup and runs candidates with available isolated
sessions or the selected CLI. Missing runtime capabilities are reported as
incomplete coverage, not as a completed evaluation.

The helper only prepares files; model execution and grading remain separate
steps controlled by the skill. Candidate outcomes are checked against actual
commands, file changes, and retained artifacts. Subjective comparisons use a
fresh judge with neutral labels when available; coordinator-only review is
identified as such. The workflow does not automatically edit the target skill.

Reusable cases remain in `skills/local/<target>/evals/evals.json`. The initial
`maintain-verification-skill` suite covers an obsolete command, a product
regression, and an unavailable prerequisite. Run-specific transcripts, scores,
and label mappings belong in `/tmp` or ignored storage.

The `change-adversarial-review` suite is built from defects that real delivery
review rounds found, plus sound controls. Its `execution` object in
`evals.json` records how to run it: Claude with `claude-opus-5-5` at effort
high, three runs per case and condition with a 30-minute limit each, and the
same command grant for both conditions. Before the runs, check that the
effective Claude settings set no sandbox proxy port and allow no network domain
or WebFetch, and record the result. Each run gets a new, empty
`CLAUDE_CODE_TMPDIR` whose `claude-<uid>` subpath stays within 44 bytes, since a
longer path falls back to the shared temp root; a run whose temp directory fell
back is excluded. The fresh directory keeps runs from sharing fixed-name
scratch directories, but it does not stop deliberate reads of another run's
files. Delete each run's workspace and temp directory when the run ends.
Candidates may run commands in the workspace under the OS sandbox in
`claude-settings.json`, which limits writes to the workspace and that temp
directory, blocks the network, and blocks reads of the real repository and
installed skills. macOS `ps` cannot run under that sandbox; the timing cases
still reproduce through pure Bash. A run whose transcript reaches outside the
workspace, including another run's workspace or temp directory, is excluded and
rerun once.

`bats tests/setup_pstack_skills.bats tests/skill_evals.bats` checks both agent
layouts and preparation behavior. Those checks do not establish real-model
effectiveness. Native skill discovery/triggering is a separate check from the
comparison of supplied instructions.
