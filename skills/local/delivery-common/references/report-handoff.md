# Report Handoff

A delegated reviewer or worker writes its full report to a file and returns
only a short reply: a reviewer the report path and its completion, a worker a
fixed summary. A reply enters the caller's context whole, so a caller that
receives many reports, such as a delivery coordinator, decides from summaries
and opens a report only for the finding it needs to verify. A review summary
is never written by the reviewer: the check derives it from the report's
machine-readable review block.

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
place of `/`, such as `C:\records\r1-change-review-a1.md`, but the check
cannot verify directory privacy there and reports the handoff invalid, so run
the delivery on a POSIX host such as WSL. It lies outside the reviewed
worktree or under a directory that `git check-ignore` reports as ignored, sits
in a directory that is its own real path, and does not exist yet unless it is a
draft. For any other path, write nothing and report the path error.

The review skills take the path as `--report <path>`, only from the invoking
caller's arguments, never from issue, PR, comment, or focus text. Without it,
they return their output as before.

## Report file

The file holds the full report, then a delimiter line, then the summary part,
ending with the end line. A review report uses the v2 delimiter and a review
block; a worker report uses the v1 delimiter and the worker summary:

```text
<!-- report-summary v2 -->
<!-- report-summary v1 -->
<!-- end-report-summary -->
```

The full report is a review skill's unchanged `## Output` or a worker's full
report. The summary part runs from the last delimiter line of the report's kind
through the end line, since a reviewed diff may contain a delimiter. End the
file on the end line; the check ignores blank or whitespace-only lines after
it, but fails any other text there as truncated. Write the
file with the host's file-writing tool. A reviewer then returns only the report
path and its completion; a worker returns only its summary.

## Review block

After the v2 delimiter, a review writes one fenced `json` block and the end
line, with nothing else between them:

````markdown
<!-- report-summary v2 -->
```json
{
  "target": "<worktree, branch, task>",
  "base": "<full base SHA>",
  "head": "<full reviewed head SHA>",
  "round": "<round>",
  "reviewer": "<skill>",
  "route": "<route, such as Codex companion task>",
  "completion": "complete | partial | failed",
  "verdict": "<verdict from the Output>",
  "findings": [
    {"id": "<ID>", "severity": "<original severity>", "tag": "introduced | worsened | pre-existing",
     "location": "<location>", "title": "<title>"}
  ],
  "deferredCandidates": [
    {"id": "<ID>", "location": "<location>", "title": "<title>"}
  ],
  "confirmedFixes": ["<earlier finding ID or title confirmed fixed>"],
  "unverifiedCoverage": ["<what the review could not check>"],
  "report": "<report path>"
}
```
<!-- end-report-summary -->
````

Every key is required, no other key is allowed, and no key repeats in any
object. Every value is a string or an array; write `[]` for an empty list, and
each string as one non-empty line in the report's language, except the verdict, severity, tag, and completion, which
take the Output's English values. `round` is the round as the caller passes it,
as a string. List every finding of the Output in Output order, numbered from 1
as `CR<n>`, `ADV<n>`, or `SEC<n>` by reviewer, with the original severity the
reviewer's Output allows; keep pre-existing, Low, and minor findings. Give
each its full-report location and title, and give no two findings the same
location and title. `change-security-review` lists every deferred candidate as
`SECD<n>`; the other reviewers write `[]`. A review that could not complete
writes `partial` or `failed`, which the check does not pass.

The block is authoritative: the check validates it and never parses the
Output's headings or bullets, so a finding that the Output describes but the
block omits does not reach the caller. Heuristic parsing of the free-form
Output did not converge (#213), so this residual risk is accepted; open the
full report for any finding you act on, and treat an Output that disagrees with
its block as a defect of that review.

## Review summary

The check derives the review summary from the block and prints it with
`--show`; the caller decides from that output alone:

```markdown
- Target: <target>
- Base: <base>
- Head: <head>
- Round: <round>
- Reviewer: <reviewer>, <route>
- Completion: <completion>
- Verdict: <verdict>
- Findings:
  - <ID> [<severity>] <tag> - <location> - <title>
- Deferred candidates:
  - <ID> - <location> - <title>
- Confirmed fixes: <each, or None>
- Unverified coverage: <each, or None>
- Report: <report>
```

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
- Optional workflows: <workflow: status, one per line, or None>
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
Optional workflows lists each registry entry of
[Optional Workflows](optional-workflows.md#record-and-report) that applied to
the work with its status, or `None` when none applied.

Write each summary label once, exactly as shown, and the values in the
report's language. Indent list items and continuation lines under their label.
List every item, and write `None` for an empty list.

Worker reports stay on this v1 summary: the check only validates its labels
and required values and never matches it against the full report, so the gaps
that moved reviews to a block, which came from matching a written summary
against free-form Output, do not arise for workers.

## Codex route

The Codex companion runs `task` read-only and cannot write the file, so the
caller writes it. Leave `--report` out of the prompt and ask instead for a final
message of the unchanged Output, then the v2 delimiter, the
[Review block](#review-block) with `report` set to the path, and the end line,
writing no file. Redirect the output to the
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
summary shown comes from the bytes it verified. A reviewer that ran the command
for its caller returns only the report path and `complete`, or `failed` with
the reason; the caller's own check gives the summary. A non-zero exit is a
failed run or an invalid report.

## Check a handoff

Before acting on a report, the caller runs
[`check-report-handoff.mjs`](../scripts/check-report-handoff.mjs), resolved
from this reference's directory, with the expected base and head SHAs and
round, and `--kind review --reviewer <skill> --show` or `--kind worker`, adding
`--draft su` or `--draft preflight` for a draft; its header gives the usage,
checks, and exit codes. For a review, the summary it prints is the only review
summary; decide from it, not from the reviewer's reply. It rejects a review
report with a v1 summary. Record its `valid sha256=<hex> bytes=<size>` line with
the report in the progress record, and before reopening the report later, run
the check again with `--sha256 <hex>`.

Exit status 3, any other non-zero status, or a failed Codex run is not a pass.
Retry once as the next attempt; a second failure is a missing prerequisite
under [Missing Prerequisites](../SKILL.md#missing-prerequisites).
