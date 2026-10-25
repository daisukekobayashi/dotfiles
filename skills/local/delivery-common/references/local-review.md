# Local Review

Use the caller's GitHub issue or Azure DevOps Work Item as the task context.

On every host, use the `change-review` skill for the first pass and the
`change-adversarial-review` skill for the second. Codex executes both; read the
installed skill instructions for how the actual host runs them, including their
Claude subagent fallback when Codex is not installed on Claude Code. Do not
infer the host from a directory name.

Report the selected route. If either required reviewer is unavailable or cannot
be invoked under its policy, report the missing prerequisite; do not substitute
the implementation owner's informal inspection for a completed review.

## Pin the implementation

Record the task URL/acceptance criteria, applicable standards, worktree, branch,
base SHA, merge-base, head SHA, and dirty/untracked state. Use the task workspace's
recorded base; do not ask for a fixed point already established by workspace
preparation. For a full review, cover the entire task diff, not only the last fix
commit. Use a full pair unless the caller selects focused follow-up below.

For delivery, use `--base <base-sha> --scope branch` with both local skills to
review the committed implementation. Include new code and files in a normal
scoped checkpoint commit after verification and before these reviews.
Obtain any required commit approval first, reuse
existing authorization when it covers the commit, and use `git-commit` for the
operation. Stage only the task's intended files; leave unrelated changes and
temporary progress records untouched. Do not amend or create an empty commit.
If approval is pending, the checkpoint and reviews remain pending; an empty
`HEAD` diff cannot establish that uncommitted work passed local review.

After every worthwhile fix, verify and make the next authorized scoped commit
before the next review or follow-up. A commit permits local review;
publication still belongs to the caller's publication phase and its approval rules.

If unrelated dirty files must remain, identify them explicitly and use branch
scope for both passes. If any intended task changes remain outside the committed
snapshot, report incomplete coverage and do not advance. Keep the snapshot stable
until the required results arrive; invalidate affected coverage if another writer
changes it.

## Assess findings

The caller applies these defaults when assessing local or hosted findings:

- **Triage:** Classify each finding as `material`, `minor`, or `pre-existing`.
  Reviewer labels (High/Medium/Low, P0-P3, critical-low, or none) are hints. A
  concrete failure affecting acceptance criteria, correctness, security, data
  integrity, regressions, a public contract, or mandatory repository rules is
  `material` whatever its label. Fix material findings or leave them open for
  the user.
- **Minor:** Record and defer by default. Every fix creates a new snapshot and
  another review round; fix a minor finding only when it is a trivial, local
  correction bundled with a material fix in the same round.
- **Pre-existing:** A finding is pre-existing only when the same failure, with
  the same impact, occurs at the merge-base. Verify by tracing the failure path
  at the merge-base, including callers and inputs this change adds; `git blame`
  on the reported line is only a hint. An older defect that this change makes
  newly reachable or more severe is `worsened` and material. Do not fix
  pre-existing findings in this delivery; record them as follow-up candidates
  and report them to the user rather than creating an issue or Work Item
  silently.
- **Follow-up candidates:** Record deferred minor findings, pre-existing
  findings, and out-of-scope problems found during the delivery in the progress
  record. Include the source target, phase, and review round or thread, the
  evidence, and a recommendation to create or drop it.
- **Bug class:** When fixing a finding, fix all instances of its class in the
  task diff in the same round, not only the reported location.
- **Repeats:** A finding already dispositioned in an earlier round is a
  `duplicate` unless new evidence changes the assessment. Pass the earlier local
  and hosted dispositions from the progress record to hosted follow-up so it
  applies the same rule.

At the round limit, classify the remaining findings before reporting: mostly
pre-existing (recommend proceeding with follow-up candidates), repeated in one
area or approach (recommend revisiting the design through design-preflight), or
genuinely new material defects (recommend extending the budget).

## Focused follow-up

When the caller selects focused follow-up after a completed full pair, retain the
full-review base/head and completed follow-up coverage. Pin the new committed
head, and give the relevant independent reviewers the accepted findings,
dispositions, and all changes since the preceding reviewed snapshot. Have them
verify the fixes and check regressions in affected paths, with enough surrounding
context to trace behavior. Use both reviewers when changes affect both areas of
coverage. Wait for the required results before the implementation owner edits.

Return the reviewed head, scope, confirmed fixes, remaining findings, and coverage
limits. Earlier review evidence remains valid for unaffected areas; the caller
decides whether broader changes require another full pair. Keep newly discovered
material risks visible for that assessment.

Run the relevant skills with `--base <preceding reviewed head> --scope branch`
and pass the accepted findings and dispositions as focus text. Preserve the
route's independence and read-only requirements.

## Run the pair

For a full pair, run `change-review` and `change-adversarial-review` as separate
reviewers independent of the implementation owner: separate subagents on Codex,
or a separate fresh Codex task for each on Claude Code. When Codex is not
installed on Claude Code, use a separate fresh Claude subagent for each as the
skills define, and report the reduced independence. Give both the same exact
worktree, branch, committed head, `--base <base-sha> --scope branch`, task
criteria, accepted design/docs, and the user's delivery request. Require the
normal review's findings, test gaps, verdict, and coverage, and the adversarial
review's verdict, concrete failure paths, coverage, and residual risk. Report
unavailable delegation instead of claiming independence.

Keep both skill executions read-only; only the parent implementation phase applies
accepted fixes. Wait for required results before editing. Do not substitute or
add the plugin's `/codex:review` or `/codex:adversarial-review` commands.
