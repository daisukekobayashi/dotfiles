# Local Review

Use the caller's GitHub issue or Azure DevOps Work Item as the task context.

Select reviewers from the actual host and available capabilities. Read the
installed command or skill instructions; do not infer the host from a directory
name or invoke a slash command as shell text.

| Host | First pass | Second pass |
|---|---|---|
| Claude Code with the Codex plugin | `/codex:review` | `/codex:adversarial-review` |
| Codex | `code-review` skill | `adversarial-review` skill |
| Claude Code without the plugin | `code-review` skill, when available | `adversarial-review` skill, when available |

Report the selected route. If either required reviewer is unavailable or cannot
be invoked under its policy, report the missing prerequisite; do not substitute
the implementation owner's informal inspection for a completed review.

## Pin the implementation

Record the task URL/acceptance criteria, applicable standards, worktree, branch,
base SHA, merge-base, head SHA, and dirty/untracked state. Use the task workspace's
recorded base; do not ask for a fixed point already established by workspace
preparation. For a full review, cover the entire task diff, not only the last fix
commit. Use a full pair unless the caller selects focused follow-up below.

`code-review` reviews `git diff <fixed-point>...HEAD`. To include a new implementation
and new files, prepare a normal scoped checkpoint commit after verification and
before running these reviews. Obtain any required commit approval first, reuse
existing authorization when it covers the commit, and use `git-commit` for the
operation. Stage only the task's intended files; leave unrelated changes and
temporary progress records untouched. Do not amend or create an empty commit.
If approval is pending, the checkpoint and reviews remain pending; an empty
`HEAD` diff cannot establish that uncommitted work passed `code-review`.

Use the same approach for the plugin branch reviews so both hosts review a fixed
snapshot. After every worthwhile fix, verify and make the next authorized scoped
commit before the next review or follow-up. A commit permits local review;
publication still belongs to the caller's publication phase and its approval rules.

If unrelated dirty files must remain, identify them explicitly and use branch
scope for both passes. If any intended task changes remain outside the committed
snapshot, report incomplete coverage and do not advance. Keep the snapshot stable
until the required results arrive; invalidate affected coverage if another writer
changes it.

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

Use the reviewer's supported follow-up interface. If it supports only a full
branch review, invoke that supported review and let the caller assess the results
under its completion criteria. Preserve the route's independence and read-only
requirements; use only supported arguments.

## Claude Code plugin

Resolve the currently installed `codex` plugin from host metadata and read its
`review` and `adversarial-review` command definitions. Use their supported
foreground execution so orchestration waits for actual output. Where supported:

```text
/codex:review --wait --base <base-sha> --scope branch
/codex:adversarial-review --wait --base <base-sha> --scope branch
```

When the host cannot delegate a slash command, use the foreground runtime
documented by that installed command, under the same user authorization and
review-only constraints. Resolve its plugin root dynamically; never assume a
cache version/path or replace the plugin with a newly downloaded package.
Preserve the command's output as required and return to the parent workflow for
assessment after the command finishes. Launching a background task is not a
completed review. A narrower native review contract is not permission to append
unsupported focus text to `/codex:review`.

## Codex or skill fallback

Use `code-review` with the pinned base as its fixed point and the task plus
accepted design/docs as its spec source. Require its Standards and Spec outputs;
an available task must not be reported as "no spec available". Pass the exact
worktree and branch to its reviewers and preserve its independent reviewer
requirements. Report unavailable delegation instead of claiming independence.

Use `adversarial-review` with the same target, `--base <base-sha> --scope branch`,
and task context. Require its verdict, concrete findings, coverage, and residual
risk. Keep both skill executions read-only; only the parent implementation phase
applies accepted fixes. Do not run both the plugin and fallback routes merely
because both are installed.
