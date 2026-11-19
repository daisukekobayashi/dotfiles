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
`evals.json` records how to run it on both agents, Claude and Codex: three runs
per case and condition with a 30-minute limit each, and the same command grant
for both conditions. The Claude arm uses `claude-opus-5-5` at effort high, and
the Codex arm uses the policy of the `change-review` suite's Codex arm,
described below. For the Claude arm, before the runs, check that no Claude
settings source other than `claude-settings.json` sets any `sandbox` key or
permission allow rule, and record the result. Inherited hooks run outside the
sandbox, so also check that no hook command runs or sources a file in the
workspace or the run's temp directory, and record the hook commands. Each run gets a new, empty
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

The `change-review` suite keeps its four synthetic criteria and rule cases and
adds defects from real review rounds with their fixed states as controls. Its
`execution` object runs both agents, Claude and Codex, three runs per case and
condition with a 30-minute limit each. The Claude arm uses the same policy as
the `change-adversarial-review` suite. The Codex arm pins the model and effort,
sets the approval policy to `never`, and runs commands under a `skill_eval`
permission profile. That profile limits writes to the workspace and the run's
fresh `TMPDIR`, blocks the network, and blocks reads of the real repository,
installed skills, and Codex session transcripts. Hooks, memories, plugins,
apps, browser, computer use, and web search are off, and the pre-run check
disables every configured MCP server. Before the runs, render the prompt with
`codex debug prompt-input` and probe the profile with `codex sandbox -P
skill_eval`, both with the same overrides, and record the results. A revision
runs only the new skill and compares it with the baseline with-skill runs of the
same agent; rerun the old snapshot when the model or CLI version changed.

`bats tests/setup_pstack_skills.bats tests/skill_evals.bats` checks both agent
layouts and preparation behavior. Those checks do not establish real-model
effectiveness. Native skill discovery/triggering is a separate check from the
comparison of supplied instructions.

## Delivery coordinator context

To compare how much context a delivery coordinator uses before and after a
change to the delivery skills, measure two comparable deliveries (a similar
number of issues, rounds, and phases) from their Claude Code transcripts,
`~/.claude*/projects/<project>/<session>.jsonl`. Subagent transcripts are
separate files, so these numbers cover the coordinator alone.

```bash
scripts/delivery-context.sh ~/.claude/projects/PROJECT/SESSION.jsonl
```

It prints one JSON object: `peak_tokens` (peak context tokens of the
coordinator), `compactions` (compaction count), and `tools` (calls and
characters by tool kind; writes cost their input, reads and fetches their
result). Compare `input_chars` for writes and `result_chars` for reads and
issue fetches. `tests/delivery_context_recipe.bats` covers the
classification with synthetic transcripts.

Also count missed reviews and decisions by hand: a review the tier selected
that did not run, or a user decision the coordinator acted on without asking.
Check the reviewers each round's tier selected in the progress record against
the review reports and log entries, and the decisions it records against the
transcript's questions to the user.

The `Bash` kinds are a heuristic for comparing like with like, not a shell
parser:

- A heredoc on the first line is `Bash:write`, or `Bash:ambiguous` when that
  line also has a quote, `$(`, a backtick, `bash -c`, or `sh -c`. A quoted
  delimiter such as `<<'EOF'` does not count as a quote.
- A `tee` or a redirect (`>`, `>>`, `N>`, `N>>`, `&>`, `&>>`; not to
  `/dev/null` or `>&N`) is `Bash:write`, or `Bash:ambiguous` when the command
  has a quote, `$(`, a backtick, `bash -c`, or `sh -c` anywhere.
- Writes are checked before reads. Classify `Bash:ambiguous` calls manually.

Before comparing two deliveries, check that they are comparable:

- The installed skills match the base being measured: compare the session
  start with the reflog of the branch the skills are installed from.
- Note reads of the skills under change in the task's own worktree, and the
  same file read twice through different paths, such as `.claude/skills` and
  `skills/local`.
- The review route matches, such as Codex for local reviews.

A delivery-skill change can be checked before such a run with a static
**chars-read proxy**: for each phase in delivery-common's Phase sections, sum
the characters of `delivery-common/SKILL.md` and of the listed reference
sections, each from its `##` heading to the next, adding every section they
link to by heading anchor, and compare it with the whole files read at the
base. The proxy measures what the rules direct the coordinator to read, not
what an agent actually reads.
