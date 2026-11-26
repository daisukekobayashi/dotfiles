# Local Review

Use the caller's GitHub issue or Azure DevOps Work Item as the task context.

On every host, the [Risk Tier](risk-tier.md)'s
[Tier procedure](risk-tier.md#tier-procedure) selects the reviewers: the
`change-review` skill for the first pass, the `change-adversarial-review` skill
for the second, and the `change-security-review` skill as a third. Each runs
in a fresh subagent of the current host unless the user's delivery request
explicitly names another review tool, such as Codex; forward that instruction to
every selected skill and read their instructions for how each route runs. Do not
infer the host from a directory name. Run the Codex-routed reviewers for one
pinned head in parallel as one set; only when the host cannot run them
concurrently, run them one at a time and report that.

`change-adversarial-review` backs its findings with runs against the real code
under [Repro Runs](repro-runs.md). The coordinator is its launcher and parent:
it creates and removes the reviewer's disposable worktree and reruns each
proving command before acting on the finding. The delivery's own worker head
is a trusted head under [Trusted heads](repro-runs.md#trusted-heads).

Include [Foreground Checks](../SKILL.md#foreground-checks) in every reviewer
brief, for full reviews and focused follow-ups, and handle each reviewer's
turn-end result under it.

Give every reviewer `--report <path>` under
[Report Handoff](report-handoff.md#report-path) for full reviews and focused
follow-ups. Pass the task, accepted design and docs, and earlier dispositions
as paths to existing material, such as the task URL, the docs, and the progress
record, instead of pasting them. Run
[Check a handoff](report-handoff.md#check-a-handoff) on each report with
`--kind review --show` and record its hash line, decide from the summaries it
prints, never from a reviewer's reply, and open a report only for the finding you need
to verify.

Report the selected route. A required reviewer that is unavailable or cannot be
invoked under its policy is a missing prerequisite under
[Missing Prerequisites](../SKILL.md#missing-prerequisites); the implementation
owner's informal inspection never substitutes for a completed review.

## Pin the implementation

Record the task URL/acceptance criteria, applicable standards, worktree, branch,
base SHA, merge-base, head SHA, and dirty/untracked state. Use the task workspace's
recorded base; do not ask for a fixed point already established by workspace
preparation. Run a full review unless Repeat and advance selects focused
follow-up.

Before running reviewers on a pinned head, set its final tier under
[Risk Tier](risk-tier.md#set-and-update-the-tier) and record it with the
selected reviewers.

For delivery, use `--base <base-sha> --scope branch` with every selected skill to
review the committed implementation. Include new code and files in a normal
scoped checkpoint commit after verification and before these reviews.
Obtain any required commit approval first, reuse
existing authorization when it covers the commit, and use `git-commit` for the
operation. Stage only the task's intended files; leave unrelated changes and
temporary progress records untouched. Do not amend or create an empty commit.
If approval is pending, the checkpoint and reviews remain pending; an empty
`HEAD` diff cannot establish that uncommitted work passed local review.
For each implementation or fix checkpoint, record in the progress record the
commit's full SHA with the path and checked SHA-256 of each accepted worker
report whose work it commits, so [Performance claims](#performance-claims) can
find them on a first run and on resume.

After every worthwhile fix, verify and make the next authorized scoped commit
before the next review or follow-up. A commit permits local review;
publication still belongs to the caller's publication phase and its approval rules.
Use [Project verification](worker-dialogue.md#project-verification) and
[Classified verification](report-handoff.md#classified-verification) before the
fix checkpoint, including the recorded report mode on resume.

If unrelated dirty files must remain, identify them explicitly and use branch
scope for every pass. If any intended task changes remain outside the committed
snapshot, report incomplete coverage and do not advance. Keep the snapshot stable
until the required results arrive; invalidate affected coverage if another writer
changes it.

For each pinned head, use [Skill instruction smoke](#skill-instruction-smoke)
before advancing from the full or focused review round. Apply
[Blast radius](#blast-radius) before assessing the round's findings.
Apply [Performance claims](#performance-claims) before advancing from the
round.

## Skill instruction smoke

The coordinator applies the `evaluate-skill` entry of the [Optional Workflows
registry](optional-workflows.md#registry) after setting the final tier.
[Reconcile existing intents](optional-workflows.md#record-and-report) before
evaluating eligibility. Reuse the result on an already attempted head and
record `not run: tier` for a Low-tier instruction change without an intent.

1. Account for every added, edited, or removed instruction file in the
   cumulative task diff from the recorded delivery base to the pinned head,
   even on a focused follow-up. Read exact paths with
   `git diff --name-status --no-renames -z <base> <head> --`, so a move has
   a removed path and an added path. Include skill entrypoints and their
   instruction references, and project agent instruction files such as
   `AGENTS.md`. Use the base tree to identify removed instructions. Consider
   changes to instruction text within the verified task scope. Group
   surviving paths by skill and keep deleted paths and standalone
   instruction files in the coverage list.
2. If the scope, tier and availability allow the run, confirm the exact
   [trusted worker head](repro-runs.md#trusted-heads). Select one applicable
   existing case per surviving changed skill from that head. Prefer a case
   that exercises the changed instructions, breaking ties by case ID.
   Verify that the target
   instructions, suite, fixtures, supporting skills, and the effective
   execution policy are in scope and safe to use. Resolve inputs from the
   pinned Git tree, rejecting symlinks or inputs outside the selected trees.
   Apply the host's existing approvals, isolation, and any tighter case
   requirements. A suite cannot authorize a command or relax permission or
   tool limits. Leave a case uncovered when those controls cannot be met.
   If the exact target's trust cannot be established, record
   `not run: unavailable` with that reason.
3. When eligible, record the launch intent and apply the effective deadline
   to the whole invocation. Stage the approved content in private storage
   outside the reviewed worktree. Forward the user's explicit delivery request, exact
   target and head, scoped paths, approved case inputs and launch settings,
   evidence location, and remaining budget to the registered smoke step.
   Recheck the current head before accepting a result.
4. For every outcome, account for each path in the verification record.
   Keep private run evidence there without rewriting earlier worker reports.
   Label any path without observed coverage
   `changed instructions not exercised by an agent`, including instruction-only
   changes and paths whose cases were skipped or could not exercise the changed
   text. Carry the status and coverage into the
   [decision summary](completion.md#decision-summary).

## Blast radius

The coordinator applies the `blast-radius` entry of the
[Optional Workflows registry](optional-workflows.md#registry) after pinning
the head and setting its final tier. The required reviewers are selected
independently under [Risk Tier](risk-tier.md#tier-procedure).

1. [Reconcile existing intents](optional-workflows.md#record-and-report) before
   evaluating eligibility. On an attempted key, reuse the recorded outcome under
   step 4. Otherwise apply the registry's tier, installation, and opt-out
   gates. Require the delivery's own [trusted worker head](repro-runs.md#trusted-heads)
   and the route, permission, and isolated location needed by
   [Disposable worktree](repro-runs.md#disposable-worktree). If the installed
   skill cannot be invoked or these prerequisites cannot be met, report
   `not run: unavailable` with the reason before launch.
2. Assign a [private report path](report-handoff.md#report-path). Record it in
   the launch intent with the reviewed worktree's absolute real path, recorded
   task base, full head SHA, original round, route, start time, and absolute
   deadline from the registry's bound or the user's shorter bound. Start that
   clock before creating the disposable worktree. Apply the command and
   finding limits in [Bounds](repro-runs.md#bounds) within the remaining time.
3. As launcher, create the disposable worktree at the pinned head and invoke
   the skill on the review route. Give the reviewer the user's explicit
   delivery request, task, exact assignment and deadline, trust decision,
   and disposable worktree path. Use a fresh subagent by default, or the
   user's explicitly selected route under
   [Trusted heads](repro-runs.md#trusted-heads) and
   [Report Handoff](report-handoff.md#codex-route) with
   [Foreground Checks](../SKILL.md#foreground-checks). Stop the run at the
   deadline. After it exits, copy the evidence and perform safe owned cleanup
   under [Remove](repro-runs.md#remove). If exit cannot be confirmed, leave
   the worktree in place and report it with any other leftovers.
4. Check the report with [Check a handoff](report-handoff.md#check-a-handoff),
   using `--kind review --reviewer blast-radius --target <reviewed-worktree>`.
   Recheck that the live head is still pinned. Record `ran` only with a valid
   completed report, evidence retention result, and safe worktree cleanup
   within the deadline. Record the completion time and report digest before
   acting on the result. An initial run that exceeded the deadline is
   `stopped: time bound`; setup, cleanup, or report errors fail the optional
   run. When resuming an intent without an outcome, require recorded evidence
   of timely completion and cleanup as well as a valid report to recover
   `ran`; otherwise record `failed: interrupted` and perform any remaining
   safe owned cleanup. Use the original assignment and recorded hash to recheck
   an accepted report before reopening it. Never invoke the skill again on
   that key, including after a malformed report, or use its result on another
   head.
5. Pass only findings from a checked `ran` result to [Assess findings](#assess-findings).
   Record each parent rerun outcome with its disposition. Reuse recorded
   confirmations on the same head. Apply [Remaining proof work](#remaining-proof-work)
   to unfinished confirmations, including on resume. Keep the checked primary
   report's `ran` status and the coverage limits in the
   [Decision summary](completion.md#decision-summary).

### Remaining proof work

Before creating a parent rerun's disposable worktree and immediately before
each pending restoration or proving command, check the user's current
authorization, opt-out, and time bound. This applies to every `blast-radius`
parent rerun, including a focused follow-up on a new head. Use the workflow
intent for that head. Use the earlier of its recorded deadline and its
recorded start time plus any current shorter bound. Keep that start time when
reusing a result or resuming. Run only within the remaining time and the
existing per-command and parent limits.

An opt-out, missing authorization, or an expired deadline stops the pending
proof work. Record the reason, assess any unfinished confirmation as
unproven from its trace, and perform any safe owned cleanup. Keep completed
evidence, the original `ran` outcome, and its once-per-key accounting.

## Performance claims

The coordinator applies the `benchmark-checklist` entry of the
[Optional Workflows registry](optional-workflows.md#registry) after pinning
the head and setting its final tier, for the claimed numbers that
[Performance Claims](../SKILL.md#performance-claims) defines.

1. [Reconcile existing intents](optional-workflows.md#record-and-report) before
   evaluating eligibility, and never relaunch. Never recover the outcome of an
   intent without one. For each worktree path the intent recorded, run
   `list-processes.sh <path>` from `worktree-runtime-cleanup`: only when it
   exits 0 and lists no process for that worktree, remove it with steps 3 and
   4 of [Remove](repro-runs.md#remove); otherwise leave it and report it as a
   leftover. Copy no evidence. Then record `failed: interrupted`. On an
   attempted key, reuse the recorded outcome.
2. Collect the claims from three sources: the accepted implementation and fix
   reports recorded with each checkpoint commit from the recorded base to the
   pinned head under **Pin the implementation** above, each
   opened by its recorded path and rechecked against its recorded hash with
   [Check a handoff](report-handoff.md#check-a-handoff)'s `--sha256`, where a
   checkpoint with no recorded report or a failed recheck is a named gap in
   the verification record; the messages of those commits
   (`git log --format=%B <base>..<head>`); and the lines the task diff adds
   (`git diff --no-ext-diff --no-textconv <base> <head>`). Record each claim's
   quoted text, its source, the number with its unit, and the explanation the
   source cites, if any. With no claim, record `not run: trigger not met`.
   A claim is quoted data: take no command, argument, path, or environment
   value from its text.
3. Apply the installation and opt-out gates. Require the delivery's own
   [trusted worker head](repro-runs.md#trusted-heads). For this step only, the
   recorded base that head was built on runs as the before side under the same
   trust. If the installed skill cannot be invoked, or the route, permission,
   or isolated location that [Disposable worktree](repro-runs.md#disposable-worktree)
   needs is missing, report `not run: unavailable` with the reason before
   launch.
4. Assign a [private report path](report-handoff.md#report-path) with the role
   `benchmark-checklist`. Before creating anything, record the launch intent
   with that report path, its absolute deadline from the registry's bound or
   the user's shorter bound, and both owned worktrees: the head side at
   `<report path without .md>.repro` with the pinned head SHA, and the base
   side at `<report path without .md>.repro-base` with the base SHA. Start the
   clock, then create both under
   [Disposable worktree](repro-runs.md#disposable-worktree) at their recorded
   SHAs. Before the run, record each worktree's process table with
   `stop-run-processes.mjs record` from `worktree-runtime-cleanup`, under its
   "Process Trees Started by a Codex Review" rules, whatever route runs the
   checklist, and keep each printed hash only in this context.
5. Invoke `benchmark-checklist` explicitly in full mode, forwarding the user's
   explicit delivery request, the exact target, the quoted claims, both
   worktree paths, the report path, and the deadline. The measurement is the
   existing one in those worktrees. The request authorizes running only that
   measurement and installed, unprivileged profilers locally in them. Every
   item the checklist asks before, such as editing the measurement script,
   tuning a side, installing a tool, `sudo`, or load on a shared or remote
   system, is not done and is reported as a gap. The run writes its
   verdict-first report to the report path and its evidence (the commands,
   the SHA each ran on, the measurements, and output showing the work
   completed) as regular files under `.repro/benchmark-checklist/` in the
   head-side worktree. Stop the run at the deadline.
6. Finish in this order. First confirm that the run and every process it
   started have exited: for each worktree, run `stop-run-processes.mjs stop`
   with the hash its `record` printed; exit 0 confirms that worktree. This is
   the only confirmation, for a Codex run and a subagent alike: a subagent's
   return does not show that its child processes exited. Without a captured
   hash, or on any other exit, exit is not confirmed: copy and remove nothing,
   leave both worktrees in place, record `failed: <reason>`, and report them.
   Then copy `.repro/benchmark-checklist/` from the head-side worktree to
   `<report path without .md>.evidence/benchmark-checklist/` with the copy
   rules of [Evidence](repro-runs.md#evidence): create the evidence directory
   with `mkdir -m 700`, copy nothing when anything below it is a symbolic link
   or not a regular file or directory, and copy with `cp -RP`. Then remove
   both worktrees with steps 3 and 4 of Remove. Last, record the outcome:
   `ran` only with a verdict for every claim, the evidence retained, and safe
   cleanup, all within the deadline; a run past it is `stopped: time bound`;
   a setup, run, retention, or cleanup error is `failed: <reason>`.
7. In the verification record, give each claim its source, the explanation
   its source cites, and the checklist's result: its verdict with run count,
   range, and limiter and the evidence path when it ran, or its status.
   A claim whose source explains it with cited evidence keeps that
   explanation when the checklist did not reach `ran` or its verdict agrees.
   When a `ran` verdict disagrees with the source's explanation, record both
   and label the claim `inconclusive`. Label an unexplained claim
   `inconclusive`, with the named gaps. Never remove or rewrite a claim.
   Never invoke the skill again on that key, or use its result on another
   head.

## Triage classes

Classify each finding as `material`, `minor`, or `pre-existing`. Reviewer
labels (High/Medium/Low, P0-P3, critical-low, or none) are hints.

- **Material:** a concrete failure affecting acceptance criteria, correctness,
  security, data integrity, regressions, a public contract, or mandatory
  repository rules, whatever its label.
- **Pre-existing:** the same failure, with the same impact, occurs at the
  merge-base. Verify by tracing the failure path at the merge-base, including
  callers and inputs this change adds; `git blame` on the reported line is only
  a hint. This class takes precedence.
- **Worsened:** an older defect that this change makes newly reachable or more
  severe. It is `material`, not pre-existing.
- **Minor:** any other finding.

## Assess findings

The caller assesses each local or hosted finding against the task, code, and
evidence, applying these defaults:

- **Triage:** Classify each finding under [Triage classes](#triage-classes).
  Fix material findings or leave them open for the user.
- **Run evidence:** Read each `change-adversarial-review` finding's proof from
  the summary. Rerun each `ran` finding under Repro Runs'
  [Parent rerun](repro-runs.md#parent-rerun) and record the result with its
  disposition. Assess a finding that is not reproduced, or whose proof is not
  `ran`, as unproven from its traced failure path; its severity and tag stay
  hints as for any finding. Treat a `Do not ship` verdict as a blocker only
  after the rerun reproduces its finding or your trace confirms it.
- **Blast radius:** Assess its findings individually under the same triage
  and evidence rules. Apply [Remaining proof work](#remaining-proof-work)
  before each parent rerun.
  The optional status and the report's verdict do not establish required
  coverage or close findings.
- **Minor:** Record and defer by default. Every fix creates a new snapshot and
  another review round; fix a minor finding only when it is a trivial, local
  correction bundled with a material fix in the same round.
- **Pre-existing:** Do not fix pre-existing findings in this delivery; record
  them as follow-up candidates and report them to the user rather than creating
  an issue or Work Item silently.
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
  can check what the implementation owner closed alone. List each finding that
  ends without a reviewer-verified fix and is not left open for the user when
  the owner triaged it `material`, its reviewer's label is `unknown` or at the
  blocking level (High from `change-review` or `change-adversarial-review`, P0
  or P1 from a hosted reviewer), or its reviewer tagged it `introduced` or
  `worsened`. A fix is reviewer-verified when a later reviewer round checks it
  against this finding and confirms it. Keep one entry per finding with its
  source reviewers and rounds or threads, the reviewer's label and tag, the
  disposition, and the reason. The list informs the user; publication and merge
  approval cover it, and a finding the user reopens is open again.
  `change-security-review` findings never enter this list; they close only
  under [Risk Tier](risk-tier.md).

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
context to trace behavior. Use each selected normal and adversarial reviewer
whose area of coverage the changes affect, and the security reviewer when Risk
Tier selects it, run as Risk Tier directs. Wait for the required results before
the implementation owner edits.

Return the reviewed head, scope, confirmed fixes, remaining findings, and coverage
limits. Earlier review evidence remains valid for unaffected areas; decide
whether broader changes require another full review under Repeat and advance. Keep
newly discovered material risks visible for that assessment.

For a fixed finding that a run proved, the follow-up reruns its retained
proving command on the new head under Repro Runs.
For a `blast-radius` finding, do that only inside the eligible
[Blast radius](#blast-radius) workflow for the new head, applying
[Remaining proof work](#remaining-proof-work). When that rerun cannot run or
finish, report that evidence gap and verify the fix with the required review
and verification paths.

Run the selected `change-review` and `change-adversarial-review` with
`--base <preceding reviewed head> --scope branch`, and `change-security-review`
with the base Risk Tier sets; pass the accepted findings and dispositions as
focus text. Preserve the route's independence and read-only requirements.

## Run the full review

A full review is one pass of every selected reviewer over the entire task diff,
not only the last fix commit. Run them as separate reviewers
independent of the implementation owner: a separate fresh subagent of the
current host for each, or a separate fresh run of the explicitly named tool for
each, as the skills define. Report the reduced independence of same-host
subagents. Give each the same exact
worktree, branch, committed head, `--base <base-sha> --scope branch`, paths to the task
criteria and accepted design/docs, and the user's delivery request. Require the
normal review's findings, test gaps, verdict, and coverage, and the adversarial
review's verdict, concrete failure paths, coverage, and residual risk, and the
security review's verdict, findings, deferred candidates, threat model, and
coverage. Report
unavailable delegation instead of claiming independence.

Keep every review skill execution read-only on the reviewed worktree;
`change-adversarial-review` runs its repros only in disposable worktrees under
[Repro Runs](repro-runs.md#boundary). Only the parent implementation phase
applies accepted fixes. Wait for required results before editing. Do not
substitute or add the plugin's `/codex:review` or `/codex:adversarial-review` commands.

## Repeat and advance

Start with a full review on the task's first committed snapshot. After fixes, run
relevant checks and use focused follow-up to confirm accepted fixes and check
regressions in affected paths. Repeat the full review only when the design or
change scope shifts materially, or new evidence makes the earlier full-review
coverage insufficient.

Advance when acceptance criteria are met, verification is current, no required
new full review is still pending, the most recent full review and the
follow-ups completed since it cover the current head with the reviewers the
Tier procedure selects, and no material actionable finding or human decision
remains open. A required new full review counts as the most recent one only
after it completes. Recorded deferrals of minor or pre-existing findings do not
require another round or a result with zero findings. Failed, unavailable,
empty, or partial review output, or a report that fails
[Check a handoff](report-handoff.md#check-a-handoff), is not a pass.

Allow at most the local review rounds the Tier procedure sets per target
across the delivery, including resumes. Count the initial full review, each
focused follow-up on a fixed snapshot, and each required new full review as
one round apiece. Lower user limits take precedence.
Advance as soon as the criteria above are met. At the limit with required work
remaining, preserve progress, report the remaining-findings classification from
Assess findings, and ask before extending the budget.

Keep a local review record in the caller's progress record: the full-review and
follow-up head SHAs, their coverage, and the local round count.
