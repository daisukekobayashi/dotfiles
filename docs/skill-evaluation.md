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

The `github-issue-triage` suite checks that triage under the detail band, which
reads issue text only where the recommendation depends on it, keeps the
recommendation of a triage that reads every issue in full. Each of its four
scenarios is an offline snapshot of list data, native relationships, and issue
text: a dependent whose text changes its blocker's rank, a comment that alone
supersedes an item, a list-only item whose touched areas overlap the next item,
and a control in which no read changes a placement. Each scenario has a
`default` case and a `full-read` case with the same files and expected answer;
the full-read prompt names every open issue for a detail read. The fixture's
`bin/gh` answers the `gh` commands the skill documents from
`.snapshot/issues.json`, applies the filters it accepts, prints compact JSON as
`gh` does off a terminal, applies `--jq` through the system `jq`, refuses every
other command, flag, and write, and logs each call's stdout bytes and the
issues whose text the call returned. Before launch, `evals/stage_gh.py stage`
copies that stand-in into a read-only directory outside every path the
candidate can write and prints the launch `PATH`: the staged copy first, then
the caller's `PATH` without empty, relative, workspace, or temp-directory
entries. Inherited Claude hooks run outside the sandbox with that `PATH`, so a
candidate cannot plant an executable for them. After the run, `stage_gh.py
collect` copies the call log, read only as a regular file inside the
workspace, to the run's evidence directory before cleanup, and the run is
reconciled with its transcript. The `execution` object otherwise uses the
`change-review` policy for both agents and fixes the decision rule before any
run: a run matches when its next issue, current wave, and next wave equal the
case's `expected` answer, and a default run in the overlap scenario also must
not pair the overlapping issue with the next issue as parallel work. The read
scope comes from the call log, not the report: a full-read run that did not
receive every issue's text and comments is rerun, a default run that received
every issue's text does not count as detail-band evidence, and a default
overlap run that read the overlapping issue does not count for the list-only
guard. A counted default run that fails where the full-read runs of the same
agent pass marks a detail-band regression. Each run records its next issue,
both waves, its parallel groups, its detail reads, and its `gh` bytes; bytes
are measured, not gated.

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
f="$HOME/.claude/projects/PROJECT/SESSION.jsonl"  # replace PROJECT and SESSION
# Peak context tokens of the coordinator.
jq -s '[.[] | select(.type=="assistant" and (.isSidechain|not) and .message.usage)
  | .message.usage | .input_tokens + (.cache_creation_input_tokens//0)
  + (.cache_read_input_tokens//0)] | max' "$f"
# Compaction count.
jq -s '[.[] | select(.type=="system" and .subtype=="compact_boundary")] | length' "$f"
# Characters by tool: writes cost their input, reads and fetches their result.
jq -s '[.[] | select(.isSidechain|not)] as $e
  | ([$e[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
      | {key: .id, value: {
          kind: (if .name=="Bash" then (.input.command
              | (split("\n")[0]) as $line
              | "\\btee\\b|(^|[^0-9&>])>>?[ ]*(?!/dev/null|&)[^ ]" as $redirect
              | if ($line | test("<<[^<]") and (test("\\$\\(|`|\\b(ba)?sh -c") | not)) then "Bash:write"
                elif test("[\u0027\"`]|\\$\\(|\\b(ba)?sh -c") and test($redirect) then "Bash:ambiguous"
                elif test($redirect) then "Bash:write"
                elif test("(^|[;&| ])(cat|sed -n|head|tail) [^|]*\\.md") then "Bash:read-md"
                elif test("gh issue (view|list)|az boards work-item show") then "Bash:issue-fetch"
                else "Bash:other" end)
            else .name end),
          input: ((.input.command // .input.content // .input.new_string // (.input | tostring)) | length)}}]
      | from_entries) as $use
  | [$e[] | select(.type=="user") | .message.content[]? | select(.type=="tool_result")
      | ($use[.tool_use_id] // {kind: "?", input: 0})
        + {result: (.content | if type=="string" then length
            else ([.[]? | .text? // ""] | add // "" | length) end)}]
  | group_by(.kind) | map({kind: .[0].kind, calls: length,
      input_chars: (map(.input) | add), result_chars: (map(.result) | add)})
  | sort_by(-(.input_chars + .result_chars))' "$f"
```

Also count missed reviews and decisions: a review the tier selected that did
not run, or a user decision the coordinator acted on without asking. The last
query is a heuristic for comparing like with like, not a shell parser. It
counts a heredoc or an unquoted `tee` or redirect as a write before any read.
A command with a quote, `$(`, a backtick, or `bash -c` or `sh -c` that also has
a `>` or `tee` anywhere is `Bash:ambiguous`; classify those calls manually.
Compare `input_chars` for writes and `result_chars` for reads and issue
fetches.

A delivery-skill change can be checked before such a run with a static
**chars-read proxy**: for each phase in delivery-common's Phase sections, sum
the characters of `delivery-common/SKILL.md` and of the listed reference
sections, each from its `##` heading to the next, adding every section they
link to by heading anchor, and compare it with the whole files read at the
base. The proxy measures what the rules direct the coordinator to read, not
what an agent actually reads.
