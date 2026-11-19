# Report Handoff

A delegated reviewer or worker writes its full report to a file and returns
only a fixed summary. A reply enters the caller's context whole, so a caller
that receives many reports, such as a delivery coordinator, decides from the
summaries and opens a report only for the finding it needs to verify.

## Report path

The caller assigns each report one path and creates its directory. Reports on
a head use the layout under Delivery Completion's
[Progress record](completion.md#progress-record):
`<root>/<task-key>/<base12>-<head12>/r<round>-<role>-a<attempt>.md`. A worker
report on uncommitted work uses the current `HEAD` as its head and the round
that will review its work, such as `r1-worker-a1` before the first checkpoint
commit. A worker's shared understanding and preflight drafts replace
`su-draft.md` and `preflight-draft.md`, with the draft's revision, counted from
1, as their round. Every other report gets a new path; when the path or its
`.log` already exists, take the next attempt number.

A valid path is absolute, uses only ASCII letters, digits, `/`, `.`, `_`, and
`-`, lies outside the reviewed worktree or under a directory that
`git check-ignore` reports as ignored, and does not exist yet unless it is a
draft. For any other path, write nothing and report the path error.

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

Write the summary labels as shown below and the values in the report's
language. List every item; never drop one for its severity, tag, or class, and
write `None` for an empty list.

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
and `change-security-review` deferred candidates as `SECD<n>`. Keep
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
question under Questions with its options, recommendation, and sources.

## Codex route

The Codex companion runs `task` read-only and cannot write the file, so the
caller writes it. Leave `--report` out of the prompt and ask instead for a final
message of the unchanged Output, then the [Review summary](#review-summary)
with `Report:` set to the path, writing no file. Redirect the output to the
report path and the progress to a log beside it:

```text
(set -C; node "<plugin-root>/scripts/codex-companion.mjs" task --fresh \
  --cwd <worktree> --prompt-file <prompt-file> > <report> 2> <report>.log)
```

`set -C` makes the redirections fail rather than overwrite an existing file.

Record the exit status, run the check below with `show=1` so only the summary
is shown, and return that summary. A non-zero exit is a failed run.

## Check a handoff

Before acting on a summary, the caller runs this check on the report path with
the expected base and head SHAs, the round, and `kind=review` or `kind=worker`.
It prints `valid`, or the summary with `show=1`, or `invalid: <reason>` with
exit status 1; a missing file exits non-zero:

```sh
awk -v base=<base-sha> -v head=<head-sha> -v round=<round> -v path=<report> \
  -v kind=<review|worker> -v show=0 '
  { sub(/\r$/, ""); line[NR] = $0 }
  $0 == "<!-- report-summary v1 -->" { n = NR }
  END {
    if (!NR) { print "invalid: missing or empty file"; exit 1 }
    if (!n) { print "invalid: no summary"; exit 1 }
    if (line[NR] != "<!-- end-report-summary -->") { print "invalid: truncated"; exit 1 }
    for (i = 1; i < n; i++) if (line[i] ~ /[^ \t]/) body = 1
    if (!body) { print "invalid: no full report"; exit 1 }
    for (i = n; i <= NR; i++) s = s line[i] "\n"
    if (!index(s, "\n- Base: " base "\n") || !index(s, "\n- Head: " head "\n")) { print "invalid: base or head mismatch"; exit 1 }
    if (!index(s, "\n- Round: " round "\n")) { print "invalid: round mismatch"; exit 1 }
    if (!index(s, "\n- Report: " path "\n")) { print "invalid: report path mismatch"; exit 1 }
    if (kind == "review") req = "Completion: complete|Verdict:|Findings:|Deferred candidates:|Confirmed fixes:|Unverified coverage:"
    else if (kind == "worker") req = "Completion:|Files changed:|Verification:|Questions:|Defaults chosen:|Blockers:|Tier:"
    else { print "invalid: unknown kind"; exit 1 }
    k = split(req, field, "|")
    for (i = 1; i <= k; i++) if (!index(s, "\n- " field[i])) { print "invalid: missing " field[i]; exit 1 }
    if (show) printf "%s", s; else print "valid"
  }' <report>
```

A missing file, an invalid result, or a failed Codex run is not a pass; for a
review, the check also rejects a Completion other than `complete`. Retry once
as the next attempt; a second failure is a missing prerequisite under
[Missing Prerequisites](../SKILL.md#missing-prerequisites).
