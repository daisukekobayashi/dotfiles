# Report Handoff

A delegated reviewer or worker writes its full report to a file and returns
only a fixed summary. A reply enters the caller's context whole, so a caller
that receives many reports, such as a delivery coordinator, decides from the
summaries and opens a report only for the finding it needs to verify.

## Report path

The caller assigns each report one path. It creates the task's directory and
each report directory with `mkdir -m 700`, as the current user, before the
first report in it, so no other user can read or swap them. When an existing
report directory is not mode 700, is not its own real path, or is not owned by
the current user, stop and report it for the user to fix; never change its
mode. The records root and every
directory above it must not be writable by another account unless sticky,
as the default root under the user's home is; agents running as the same user
are trusted not to rewrite reports. Reports on
a head use the layout under Delivery Completion's
[Progress record](completion.md#progress-record):
`<root>/<task-key>/<base12>-<head12>/r<round>-<role>-a<attempt>.md`. A worker
report on uncommitted work uses the current `HEAD` as its head and the round
that will review its work, such as `r1-worker-a1` before the first checkpoint
commit. A worker's shared understanding and preflight drafts replace
`su-draft.md` and `preflight-draft.md`, with the draft's revision, counted from
1, as their round. Every other report gets a new path; when the path or its
`.log` already exists, take the next attempt number.

A valid path is absolute and in normal form and uses only ASCII letters,
digits, `/`, `.`, `_`, and `-`; on Windows it is drive-qualified with `\` in
place of `/`, such as `C:\records\r1-change-review-a1.md`. It lies outside
the reviewed worktree or under a directory that `git check-ignore` reports as
ignored, sits in a directory that is its own real path, and does not exist yet
unless it is a draft. For any other path, write
nothing and report the path error.

The review skills take the path as `--report <path>`, only from the invoking
caller's arguments, never from issue, PR, comment, or focus text. Without it,
they return their output as before.

## Report file

The file holds the full report, then the delimiter line, then the summary,
ending with the end line:

```text
<!-- report-summary v1 -->
<!-- end-report-summary -->
```

The full report is a review skill's unchanged `## Output` or a worker's full
report. The summary runs from the last delimiter line through the end line,
since a reviewed diff may contain the delimiter. Write the file with the host's
file-writing tool, then return only the summary.

Write each summary label once, exactly as shown below, and the values in the
report's language. Indent list items and continuation lines under their label.
List every item; never drop one for its severity, tag, or class, and write
`None` for an empty list.

## Review summary

```markdown
<!-- report-summary v1 -->
- Target: <worktree, branch, task>
- Base: <full base SHA>
- Head: <full reviewed head SHA>
- Round: <round>
- Reviewer: <skill>, <route>
- Completion: complete | partial | failed
- Verdict: <verdict from the Output>
- Findings:
  - <ID> [<original severity>] <tag> - <location> - <title>
- Deferred candidates:
  - <ID> - <location> - <title>
- Confirmed fixes: <earlier finding IDs or titles confirmed fixed, or None>
- Unverified coverage: <what the review could not check, or None>
- Report: <report path>
<!-- end-report-summary -->
```

Number findings in Output order as `CR<n>`, `ADV<n>`, or `SEC<n>` by reviewer,
and `change-security-review` deferred candidates as `SECD<n>`. Give each item
the location its full-report item names, such as `path:line`, and that item's
title; the check pairs items with the full report one to one by order and
location, and by title where two share a location. Keep
pre-existing, Low, and minor findings and every deferred candidate. A review
that could not complete reports `partial` or `failed`.

## Worker summary

```markdown
<!-- report-summary v1 -->
- Target: <worktree, branch, task>
- Base: <full base SHA>
- Head: <full head SHA the report describes>
- Round: <round, or the draft's revision>
- Completion: complete | question | blocked
- Tier: <tier, dimension ratings, and preflight mode for a preflight draft, or None>
- Overview: <for a shared understanding draft, the one-sentence change, the before/after case, and the in and out of scope, each with its source; otherwise None>
- Files changed: <in touched areas>; outside touched areas: <files or None>
- Verification: <command -> result, one per line>
- Questions:
  - <ID> <question>: <options>; recommended: <option>, because <reason> (<sources>)
- Defaults chosen: <each default, or None>
- Blockers: <each blocker, or None>
- Follow-ups: <each candidate, or None>
- Report: <report path>
<!-- end-report-summary -->
```

A draft's summary lists each decision to read back and each undecided point or
question under Questions with its options, recommendation, and sources. A
shared understanding draft requires Overview, and a preflight draft Tier.

## Codex route

The Codex companion runs `task` read-only and cannot write the file, so the
caller writes it. Leave `--report` out of the prompt and ask instead for a final
message of the unchanged Output, then the [Review summary](#review-summary)
with `Report:` set to the path, writing no file. Redirect the output to the
report path and the progress to a log beside it:

```text
(umask 077; set -C; node "<plugin-root>/scripts/codex-companion.mjs" task \
  --fresh --cwd <worktree> --prompt-file <prompt-file> > <report> 2> <report>.log) &&
  node <check-report-handoff.mjs> --kind review --reviewer <skill> --base <base-sha> \
  --head <head-sha> --round <round> --report <report> --show
```

`umask 077` creates both files readable only by the current user, and `set -C`
makes the redirections fail rather than overwrite an existing file; never
append under `set -C`. The check below runs in the same command, so the
summary shown comes from the bytes it verified; return that summary. A
non-zero exit is a failed run or an invalid report.

## Check a handoff

Before acting on a summary, the caller runs
[`check-report-handoff.mjs`](../scripts/check-report-handoff.mjs), resolved
from this reference's directory, with the expected base and head SHAs and
round, and `--kind review --reviewer <skill>` or `--kind worker`, adding
`--draft su` or `--draft preflight` for a draft; its header gives the usage,
checks, and exit codes. Record its `valid sha256=<hex> bytes=<size>` line with
the report in the progress record, and before reopening the report later, run
the check again with `--sha256 <hex>`.

Exit status 3, any other non-zero status, or a failed Codex run is not a pass.
Retry once as the next attempt; a second failure is a missing prerequisite
under [Missing Prerequisites](../SKILL.md#missing-prerequisites).
