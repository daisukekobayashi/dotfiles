# Codex Review Request

Use the host, repository and PR resolved by the parent skill. Read the PR's
`issue_url` from `repos/<owner>/<repo>/pulls/<PR>` on that host.

1. Set `body` to `@codex review`, or `@codex review for <user-provided focus>`
   when the user supplied review criteria. For a GitHub delivery call, prepare
   a [delivery trigger intent](#delivery-trigger-intent) and append its suffix
   to `body`. A standalone request sends `body` as set above.
2. Post once, passing the body as a literal string:
   ```bash
   gh api --hostname "$host" --method POST \
     "repos/$owner/$repo/issues/$pr/comments" \
     -H 'Accept: application/vnd.github.raw+json' -f "body=$body"
   ```
   Require `id`, `html_url` and `created_at` in that successful response. Confirm
   its `issue_url` matches the resolved PR's `issue_url` and its raw `body`
   equals the requested body. In delivery, check the recorded author, time
   and prior IDs against the response and confirm the published head still
   matches the intent. Append the outcome with the returned ID before polling.
   On an error or unverifiable response, stop and report. Delivery recovers an
   unrecorded outcome under [Recover a delivery trigger](#recover-a-delivery-trigger).
3. [Acknowledge the trigger](#acknowledge-the-trigger) on that exact comment.
4. Report the PR URL, the trigger comment URL, and one of these outcomes:
   - `Codex acknowledged`: the posted comment has an `eyes` reaction.
   - `Codex request posted but not acknowledged`: the comment exists, but no `eyes`
     reaction appeared before the timeout.
5. If the user explicitly asks to retry an unacknowledged request, recheck the
   exact posted comment ID and its PR before deleting it. In delivery, also
   confirm the published head and the evidence tying that comment to its post.
   If ownership or the previous attempt is uncertain, stop and report. Otherwise
   delete only that comment and repeat steps 1–4 once with the same review
   command and focus. In delivery the replacement is a new post with its own
   intent and identifier. Preserve the prior attempt in the log.
   ```bash
   gh api --hostname "$host" --method DELETE "repos/$owner/$repo/issues/comments/$comment_id"
   ```

## Acknowledge the trigger

A verified comment ID establishes posting. Use that exact ID for
acknowledgement, including on resume. Reuse verified acknowledgement already
recorded for that ID. Preserve a recorded timeout. With acknowledgement
still unchecked, use a bounded read of all reaction pages on that comment:

```bash
gh api --hostname "$host" --method GET --paginate --slurp \
  "repos/$owner/$repo/issues/comments/$comment_id/reactions" \
  -H 'Accept: application/vnd.github+json' -f content=eyes
```

For standalone, poll for an `eyes` reaction at 5-10 second intervals for up
to 120 seconds. For delivery, use the comment's provider `created_at` to
start the 120-second bound, so a resume uses only the remaining time. Read
even if the deadline has passed, and count only reactions created within
the original window, including both endpoints. Run this query with `jq -e`
on a successful, complete read, passing the comment's `created_at` with
`--arg posted_at`:

```jq
if type != "array" or length == 0 or any(.[]; type != "array") then
  error("expected complete reaction pages")
else
  ($posted_at | fromdateiso8601) as $start
  | [.[][]
    | select(.content == "eyes")
    | (.created_at | fromdateiso8601) as $reaction
    | select($start <= $reaction and $reaction <= ($start + 120))
    | {user: .user.login, created_at}]
end
```

In delivery, keep the 5-10 second polling intervals within the original
deadline. At or after the deadline, take one bounded read and finish
without another wait. Record timeout only after a complete read at or after
the deadline with no eligible reaction. If the read or timestamp evidence
is unavailable, stop and report acknowledgement as unverified.
Append verified acknowledgement or timeout to the task log for that comment
ID. With a timeout, stop unless the user explicitly asks to continue
waiting for this review or approves the retry in step 5. Review output on
the same head does not establish acknowledgement of this comment.

## Delivery trigger intent

Use the ignored task log assigned by the checked GitHub delivery call under
[Phase Delegation](../../delivery-common/references/phase-delegation.md#brief-the-agent).
Before each post, verify the resolved PR is still on the assigned published
head. Read all current comment pages and collect the existing IDs of comments
starting with `@codex review` using the [raw comment read](#recover-a-delivery-trigger).
Immediately before the post, read the login and the `Date` response header
with `gh api --hostname <host> --include user` for the posting account and
ordering baseline. Stop if these reads are incomplete.

Generate a random UUIDv4 for this post. Add the exact suffix `\n\n<!-- codex-review-intent:v1 <uuid> -->`
to the raw trigger body, with two line feeds before the comment and no bytes
after it. Keep the public suffix free of task record data. Append the intent to
the assigned task log before posting, with the marker version and UUID, target,
hosted round, full published head, existing trigger IDs, login, and baseline.
For a replacement, also record the ID it replaces. Follow the delegated
assignment check before each write.
The suffix correlates a post with its intent. Approval and review completion
use their own evidence.

## Recover a delivery trigger

Start from the current hosted round's latest post intent, or its recorded trigger
when resuming an older delivery. Confirm the resolved PR and published head
match the record. With an existing outcome or previously verified trigger ID,
read that exact comment from `repos/<owner>/<repo>/issues/comments/<id>` on
the resolved host and verify the recorded evidence, including its PR and the
suffix when one was recorded. A verified old ID can still resume at
[acknowledgement](#acknowledge-the-trigger).

For an intent with no outcome or verified ID, require its recorded UUIDv4
and marker version `v1`. A missing marker in an older pending record
blocks recovery, even if author and time match. Read the PR's raw comment bodies
within the current phase bound:

```bash
gh api --hostname "$host" --paginate --slurp \
  "repos/$owner/$repo/issues/$pr/comments" -H 'Accept: application/vnd.github.raw+json'
```

Require a successful, complete read. Run this query with `jq -e`, pages on
stdin, `issue_url`, `login`, `baseline` (UTC ISO 8601) and `uuid` passed with
`--arg`, and the `prior_ids` array passed with `--argjson`.

```jq
if ($uuid | test("\\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\z") | not)
then error("missing or invalid Codex review intent UUID")
else "\n\n<!-- codex-review-intent:v1 \($uuid) -->" as $suffix
| [ .[][] as $comment
  | select($comment.issue_url == $issue_url and $comment.user.login == $login)
  | select(($comment.id | type) == "number" and ($prior_ids | index($comment.id)) == null)
  | select(($comment.body | type) == "string" and ($comment.body | endswith($suffix)))
  | ($comment.body | split("\n")[0]) as $command
  | select($command == "@codex review" or ($command | startswith("@codex review for ")))
  | select(($comment.created_at | fromdateiso8601) >= ($baseline | fromdateiso8601))
  | $comment ]
| if length == 1 then .[0] else error("expected one matching Codex review trigger") end
end
```

Recheck the published head before recording the recovered comment ID as the
outcome. Return the verified ID and `created_at` to the cycle for
[acknowledgement](#acknowledge-the-trigger). On missing, mismatched or
ambiguous evidence, stop and report without posting or deleting a comment.

## Guardrails

- Do not create a PR.
- Do not push, commit, merge, or edit repository files.
  A delivery call appends its records only to its assigned ignored task log.
- Do not request Copilot review from this provider procedure.
- Use only the PR comment path described above to request Codex review.
- Assume Codex review is already configured unless an API error proves
  otherwise; do not run setup troubleshooting by default.
- If Codex is unavailable, permission-blocked, or the repository does not support Codex review, report that explicitly.
