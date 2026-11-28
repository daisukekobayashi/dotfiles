# Skill evaluation with Codex and Claude Code

Invoke `evaluate-skill` to compare a skill against a baseline or previous version.
The skill coordinates case selection, isolated candidate execution, grading, and
an evidence-based recommendation. It is included in the `base` profile and uses
one instruction body on both agents.

```text
Codex:       $evaluate-skill maintain-verification-skill
Claude Code: /evaluate-skill maintain-verification-skill
```

By default it evaluates on the current agent. Request both agents explicitly to
run the same cases on Codex and Claude, comparing conditions within each agent.
Keep model, settings, permissions, tools, and initial files fixed within a pair.
Small samples reveal concrete problems; they do not establish a general ranking.

## Delivery smoke

In an explicitly requested GitHub or Azure DevOps issue delivery, Local Review
can use `evaluate-skill` at Medium and High tier when the pinned worker head
changes instructions. Within one 15-minute budget, the current agent runs one
applicable existing case per changed skill, once, using the changed instructions.
The smoke run starts zero baseline sessions.

The coordinator checks that the case inputs come from the trusted head and
that the launch stays within existing permissions. Verification evidence and
the decision summary show observed coverage and gaps, including missing cases
and removed or otherwise unexercised instructions. At Low tier an instruction
change reports `not run: tier`. See the shared
[Local Review step](../skills/local/delivery-common/references/local-review.md#skill-instruction-smoke).

## Comparison workflow

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

A suite's `supporting_skills` lists every sibling skill that the supplied
guidance refers to by relative path. Preparing `with-skill` scans every
Markdown file the helper copies (each supplied skill, without `evals/`) for
relative path references to sibling skills: any `./` or `../` path text, in a
link, code, an HTML attribute, or prose. It refuses the suite when such a path
resolves to an existing skill that is not supplied, to the skills root itself,
or into a path the copy skips, such as `evals/`, naming the file and the path.
A path into no existing skill, such as a code example, is ignored. The
prepared Codex launch turns off the runner's hooks, memories, plugins, and
apps, and disables each MCP server configured in `$CODEX_HOME/config.toml` by
name, since `-c mcp_servers={}` leaves configured servers running. Global
instructions such as `~/.codex/AGENTS.md` still load. The prepared Claude
launch adds `--safe-mode`, which turns off the runner's installed plugins,
settings and plugin hooks, MCP servers including claude.ai connectors, and
auto-memory, while `--settings`, the sandbox, and user permission rules still
apply. It leaves on Claude Code's built-in plugins and their hooks, and the
organization's managed settings and managed plugin hooks. Whether it skips
the user's `~/.claude/CLAUDE.md` is unverified, because a control run without
`--safe-mode` logged no line for that file either. These remaining items apply
to both conditions alike; record them with the run. Memories and MCP servers
are normally off, but these remaining layers on Claude, and Codex configuration
layers other than `$CODEX_HOME/config.toml`, can still add them.

Reusable cases remain in `skills/local/<target>/evals/evals.json`. The initial
`maintain-verification-skill` suite covers an obsolete command, a product
regression, and an unavailable prerequisite. Run-specific transcripts, scores,
and label mappings belong in `/tmp` or ignored storage.

The `change-adversarial-review` suite is built from defects that real delivery
review rounds found, plus sound controls. Its fixtures have no git history, so
the skill creates no disposable worktree there and reports its findings
`unproven: no checkout`; the cases check the findings, not repro runs. Its `execution` object in
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
installed skills, and Codex session transcripts. The prepared launch
arguments turn off hooks, memories, plugins, apps, and the configured MCP
servers, and the suite also turns off browser, computer use, and web search.
Before the runs, render the prompt with
`codex debug prompt-input` and probe the profile with `codex sandbox -P
skill_eval`, both with the same overrides, and record the results. A revision
runs only the new skill and compares it with the baseline with-skill runs of the
same agent; rerun the old snapshot when the model or CLI version changed. This
suite and `change-adversarial-review` supply `delivery-common` and
`worktree-runtime-cleanup` since #331, which their guidance refers to, so their
next comparison reruns the old snapshot under the new supplied set instead of
reusing earlier baseline runs.

The `github-issue-triage` suite checks that triage under the detail band, which
reads issue text only where the recommendation depends on it, keeps the
recommendation of a triage that reads every issue in full. Each of its four
scenarios is an offline snapshot of list data, native relationships, and issue
text: a dependent whose text changes its blocker's rank, a comment that alone
supersedes an item, a list-only item whose touched areas overlap the next item,
and a control in which no read changes a placement. Each scenario has a
`default` case and a `full-read` case with the same files and expected answer;
the full-read prompt names every open issue for a detail read. The fixture's
`bin/gh` answers only the `gh` command forms that the skill's `SKILL.md`
documents, from `.snapshot/issues.json`, with their exact `--json` field sets
and `--jq` expressions, which it evaluates itself; it refuses everything else
with exit 1, no stdout, and a fixed stderr line. Only the documented
`gh issue view` form returns an issue's body and comments, so the call log
records each call's arguments, stdout bytes, and that call's issue as its
detail read. Before launch, `evals/stage_gh.py stage` copies the stand-in into
a read-only directory outside every path the candidate can write and prints a
fixed launch `PATH`, never inherited: the staged copy, then `/usr/bin`, `/bin`,
`/usr/sbin`, and `/sbin`. Because the agent CLI is usually elsewhere, `stage`
first resolves it to an absolute executable from the coordinator's `PATH`,
along with the interpreter of a `#!/usr/bin/env <interpreter>` launcher,
rejects one it cannot resolve or the candidate could write, and prints the
launch arguments with those paths for both the pre-run checks and the launch. Inherited Claude hooks
run outside the sandbox with the fixed `PATH`, and a pre-run check records
that every hook executable resolves outside the writable roots or not at all. After the run and before cleanup,
`stage_gh.py collect`, within one deadline, opens the call log without
blocking or following links, accepts only a single-link regular file within a
byte limit, validates each record, and copies it to the run's evidence
directory. It derives each record's command form and issue from its arguments
and exit status with the stand-in's own rules and rejects a record whose
stored values disagree. A failed collection excludes the run, and each logged
call is reconciled one to one with the transcript by arguments and exit
status. The
`execution` object otherwise uses the `change-review` policy for both agents
and fixes the decision rule before any run: a run matches when its next issue,
current wave, and next wave equal the case's `expected` answer, and a default
run in the overlap scenario also must not pair the overlapping issue with the
next issue as parallel work. The read scope comes from the reconciled calls'
arguments, never from the report or output content: a default run that read
every issue does not count as detail-band evidence, a default overlap run that
read the overlapping issue does not count for the list-only guard, and a
full-read run counts only when it read every open issue. Per case and agent,
a counted default run that fails the rule is a detail-band regression only
when a majority of the valid full-read runs match the expected answer;
otherwise the case is inconclusive (suspected case defect). Each run records its next issue, both waves, its parallel groups,
its detail reads, and its `gh` bytes; bytes are measured, not gated.

The `delivery-common`, `shared-understanding`, and `design-preflight` suites
give delivery smoke one case each, and they have no `execution` object. Each
case reads its synthetic fixture and answers in the final message. The smoke
launch uses the prepared launch arguments, isolated as described above. The
`delivery-common` case is a single prompt over a synthetic progress record and
round 2 review summary, and needs no calling workflow; it checks Local Review's
Recurrence rule and the `[premise P<n>]` entry. The other two cases ask for a
coordinator draft, which never questions the user, and check the recommendation
rules, including the comparison with removal and a smaller option. Each suite
supplies the `principles` index and every leaf the index links, and
`tests/skill_evals_test.py` derives that list from the index; each also
supplies `benchmark-checklist`, and `delivery-common` supplies
`worktree-runtime-cleanup`, because the supplied guidance refers to them. Grading reads the
final answer and the transcript. A run is contaminated when it reads outside
the workspace, including an installed copy of the skill, or calls a memory or
other MCP tool, which the remaining configuration layers can still provide; a
contaminated run is excluded and its case reported as missing coverage. Not covered: the user
dialogue, the `grilling` sub-skill (not a sibling skill, so it cannot be
supplied), and the parts that only `design-preflight-with-docs` adds.

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

If the session also covers other work, run the script on a temporary local
JSONL copy from the delivery invocation through completion or the checkpoint
being compared. Keep tool calls with their results and record the bounds.
The peak can still include context carried into the delivery from earlier
work. Keep transcripts and temporary copies local.

The script prints one JSON object: `peak_tokens` (peak context tokens of the
coordinator), `compactions` (compaction count), and `tools` (calls and
characters by tool kind; writes cost their input, reads and fetches their
result). Compare `input_chars` for writes and `result_chars` for reads and
issue fetches. `tests/delivery_context_recipe.bats` covers the
classification with synthetic transcripts.

When a `Skill` call injects instructions as a separate user message, match
that message to the call and count the characters of the injected body,
excluding the wrapper and arguments. Report this count alongside the tool
counts. The script counts `Skill` tool results, and `peak_tokens` already
comes from recorded usage. If the injected body is unavailable, record the
reason and leave the count missing.

Also count missed reviews and decisions by hand: a review the tier selected
that did not run, or a user decision the coordinator acted on without asking.
Derive what should have happened from the workflow rules and the transcript,
not from the progress record, which can omit what it missed:

- Expected confirmations: each commit, push, PR creation, merge, cleanup, and
  issue or PR write the transcript shows, and each worker-listed default or
  question on a contract, boundary, compatibility, or security decision that
  the coordinator adopted. Implementation tactics need none, and neither does a
  commit that the global rules in force for the session let the agent make and
  report, such as one on a non-default task branch it created or was explicitly
  assigned.
- Expected reviews: every head that was published or merged needs a covering
  review by the reviewers its tier selects, whether or not the transcript
  shows a review phase for it. A head published without one, including after
  a resume that goes straight to publication, is a miss.
- Reconcile each expected item with the user's answers and own messages
  before it, and with the review reports for that head. An item with no match
  is a miss; the progress record only explains a match.

The `Bash` kinds are a heuristic for comparing like with like, not a shell
parser:

- A heredoc (`<<` or `<<-`; a `<<<` here-string is not one) on the first
  line is `Bash:write`, or `Bash:ambiguous` when that line also has a quote,
  `$(`, a backtick, `bash -c`, or `sh -c`. A delimiter word that is wholly
  single- or double-quoted and followed by whitespace or the line end, such as
  `<<'EOF'` or `<<-"END JSON"`, does not count as a quote.
- A `tee` or a redirect operator anywhere (`N>>`, `N>`, `&>>`, `&>`, `>>`,
  `>`, including `>&file`; not a descriptor duplication or close such as
  `>&2` or `2>&-`) is a write unless its destination word is exactly
  `/dev/null`. It is `Bash:write`, or `Bash:ambiguous` when the command has a
  quote, `$(`, a backtick, `bash -c`, or `sh -c` anywhere. A `>` inside a
  string, such as `->`, is counted too.
- Writes are checked before reads, so an uncertain case falls toward
  `Bash:write` or `Bash:ambiguous`. Classify `Bash:ambiguous` calls manually.

Before comparing two deliveries, check that they are comparable:

- At delivery start, record the revision or content digest of the installed
  skills the session loads, resolving links to the files actually used. Note
  any changes to those sources during the run. Report the revision as verified
  only where contemporaneous evidence establishes what was loaded. Otherwise
  report it as inferred and list the evidence used, such as the link target,
  the checkout's reflog, or the install time of a copy.
- Note reads of the skills under change in the task's own worktree, and the
  same file read twice through different paths, such as `.claude/skills` and
  `skills/local`.
- The review route matches, such as Codex for local reviews.

To check how the coordinator read references, match reads in the transcript
to the phase and the phase map in use at the time. Record heading or line
ranges and flag whole-file reads where the map calls for selected sections.
A phase entry of `all` allows a whole-file read.

A delivery-skill change can be checked before such a run with a static
**chars-read proxy**: for each phase in delivery-common's Phase sections, sum
the characters of `delivery-common/SKILL.md` and of the listed reference
sections, each from its `##` heading to the next, adding every section they
link to by heading anchor, and compare it with the whole files read at the
base. The proxy measures what the rules direct the coordinator to read, not
what an agent actually reads.
