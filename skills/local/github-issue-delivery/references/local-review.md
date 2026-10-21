# Local Review

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

Record the issue URL/acceptance criteria, applicable standards, worktree, branch,
base SHA, merge-base, head SHA, and dirty/untracked state. Use the issue workspace's
recorded base; do not ask for a fixed point already established by issue start.
Review the entire issue diff, not only the last fix commit.

`code-review` reviews `git diff <fixed-point>...HEAD`. To include a new implementation
and new files, prepare a normal scoped checkpoint commit after verification and
before running these reviews. Obtain any required commit approval first, reuse
existing authorization when it covers the commit, and use `git-commit` for the
operation. Stage only the issue's intended files; leave unrelated changes and
temporary progress records untouched. Do not amend or create an empty commit.
If approval is pending, the checkpoint and reviews remain pending; an empty
`HEAD` diff cannot establish that uncommitted work passed `code-review`.

Use the same approach for the plugin branch reviews so both hosts review a fixed
snapshot. After every worthwhile fix, verify and make the next authorized scoped
commit before repeating the pair. A commit permits local review; publication
still belongs to the PR cycle and its approval rules.

If unrelated dirty files must remain, identify them explicitly and use branch
scope for both passes. If any intended issue changes remain outside the committed
snapshot, report incomplete coverage and do not advance. Keep the snapshot stable
until both results arrive; invalidate results if another writer changes it.

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

Use `code-review` with the pinned base as its fixed point and the issue plus
accepted design/docs as its spec source. Require its Standards and Spec outputs;
an available issue must not be reported as "no spec available". Pass the exact
worktree and branch to its reviewers and preserve its independent reviewer
requirements. Report unavailable delegation instead of claiming independence.

Use `adversarial-review` with the same target, `--base <base-sha> --scope branch`,
and issue context. Require its verdict, concrete findings, coverage, and residual
risk. Keep both skill executions read-only; only the parent implementation phase
applies accepted fixes. Do not run both the plugin and fallback routes merely
because both are installed.
