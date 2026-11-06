# Local Review

Use the caller's GitHub issue or Azure DevOps Work Item as the task context.

On every host, use the `change-review` skill for the first pass and the
`change-adversarial-review` skill for the second. When the [Risk Tier](risk-tier.md)
selects it, add the `change-security-review` skill as a third reviewer. Each runs
in a fresh subagent of the current host unless the user's delivery request
explicitly names another review tool, such as Codex; forward that instruction to
every selected skill and read their instructions for how each route runs. Do not
infer the host from a directory name. Run Codex-routed reviewers for one
worktree one at a time; each stops the broker it starts.

Report the selected route. If any required reviewer is unavailable or cannot
be invoked under its policy, report the missing prerequisite; do not substitute
the implementation owner's informal inspection for a completed review.

## Pin the implementation

Record the task URL/acceptance criteria, applicable standards, worktree, branch,
base SHA, merge-base, head SHA, and dirty/untracked state. Use the task workspace's
recorded base; do not ask for a fixed point already established by workspace
preparation. Run a full review unless Repeat and advance selects focused
follow-up.

Before running reviewers on a pinned head, set the tier for that head under
[Risk Tier](risk-tier.md) and record it with the selected reviewers.

For delivery, use `--base <base-sha> --scope branch` with every selected skill to
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
scope for every pass. If any intended task changes remain outside the committed
snapshot, report incomplete coverage and do not advance. Keep the snapshot stable
until the required results arrive; invalidate affected coverage if another writer
changes it.

## Assess findings

The caller assesses each local or hosted finding against the task, code, and
evidence, applying these defaults:

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
- **Self-closures:** Keep a self-closure list in the progress record so the user
  can check what the implementation owner closed alone. List each of these:
  - A `material` finding that ends without a verified fix and is not left open
    for the user, whatever its disposition: `explained`, `stale`, `skipped`, or
    `duplicate`. A `duplicate` stays listed even when the earlier finding is
    `applied`, unless a later reviewer round verified that fix against this
    report.
  - Marked `downgraded`, a finding triaged `minor` whose reviewer label is
    `unknown` or at the blocking level: High from `change-review` or
    `change-adversarial-review`, Critical or High from `change-security-review`,
    P0 or P1 from a hosted reviewer.
  - Marked `reclassified`, a finding triaged `pre-existing` that its reviewer
    tagged `introduced` or `worsened`.

  Give each entry the finding, its source reviewer and round or thread, the
  reviewer's label and tag, the disposition, and the reason. Add the source of a
  later `duplicate` to the existing entry for the same finding. Drop an entry
  once a later reviewer round verifies the fix or re-triage leaves the finding
  open for the user. A material `change-security-review` finding closes only
  under [Risk Tier](risk-tier.md), so it never enters this list. The list
  informs the user; publication and merge approval cover it, and a finding the
  user reopens is open again.

Apply worthwhile fixes and record a concise reason for each explained, duplicate,
stale, pre-existing, or skipped finding. Leave disputed material findings and
design decisions open for the user. Keep fixes within the task's scope and
backed by a finding.

At the round limit, classify the remaining findings before reporting: mostly
pre-existing (recommend proceeding with follow-up candidates), repeated in one
area or approach (recommend revisiting the design through design-preflight), or
genuinely new material defects (recommend extending the budget).

## Focused follow-up

When Repeat and advance selects focused follow-up after a completed full review, retain the
full-review base/head and completed follow-up coverage. Pin the new committed
head, and give the relevant independent reviewers the accepted findings,
dispositions, and all changes since the preceding reviewed snapshot. Have them
verify the fixes and check regressions in affected paths, with enough surrounding
context to trace behavior. Use both reviewers when changes affect both areas of
coverage, and the security reviewer when Risk Tier selects it, run as Risk
Tier directs. Wait for the required results before the implementation owner edits.

Return the reviewed head, scope, confirmed fixes, remaining findings, and coverage
limits. Earlier review evidence remains valid for unaffected areas; decide
whether broader changes require another full review under Repeat and advance. Keep
newly discovered material risks visible for that assessment.

Run `change-review` and `change-adversarial-review` with
`--base <preceding reviewed head> --scope branch`, and `change-security-review`
with the base Risk Tier sets; pass the accepted findings and dispositions as
focus text. Preserve the route's independence and read-only requirements.

## Run the full review

A full review is one pass of every selected reviewer over the entire task diff,
not only the last fix commit: `change-review` and `change-adversarial-review`,
plus `change-security-review` when selected. Run them as separate reviewers
independent of the implementation owner: a separate fresh subagent of the
current host for each, or a separate fresh run of the explicitly named tool for
each, as the skills define. Report the reduced independence of same-host
subagents. Give each the same exact
worktree, branch, committed head, `--base <base-sha> --scope branch`, task
criteria, accepted design/docs, and the user's delivery request. Require the
normal review's findings, test gaps, verdict, and coverage, and the adversarial
review's verdict, concrete failure paths, coverage, and residual risk, and the
security review's verdict, findings, deferred candidates, threat model, and
coverage. Report
unavailable delegation instead of claiming independence.

Keep every review skill execution read-only; only the parent implementation phase applies
accepted fixes. Wait for required results before editing. Do not substitute or
add the plugin's `/codex:review` or `/codex:adversarial-review` commands.

## Repeat and advance

Start with a full review on the task's first committed snapshot. After fixes, run
relevant checks and use focused follow-up to confirm accepted fixes and check
regressions in affected paths. Repeat the full review only when the design or
change scope shifts materially, or new evidence makes the earlier full-review
coverage insufficient.

Advance when acceptance criteria are met, verification is current, no required
new full review is still pending, the most recent full review and the
follow-ups completed since it cover the current head with the reviewers its
current tier selects, and no material actionable finding or human decision
remains open. A required new full review counts as the most recent one only
after it completes. Recorded deferrals of minor or pre-existing findings do not
require another round or a result with zero findings. Failed, unavailable,
empty, or partial review output is not a pass.

Allow at most three local review rounds per target across the delivery,
including resumes. Count the initial full review, each focused follow-up on a
fixed snapshot, and each required new full review as one round apiece, including
any reviewer Risk Tier adds on the same head. Lower user limits take precedence.
Advance as soon as the criteria above are met. At the limit with required work
remaining, preserve progress, report the remaining-findings classification from
Assess findings, and ask before extending the budget.

Keep a local review record in the caller's progress record: the full-review and
follow-up head SHAs, their coverage, and the local round count.
