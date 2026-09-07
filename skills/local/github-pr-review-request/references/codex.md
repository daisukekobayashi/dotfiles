# Codex Review Request

Use the repository and PR resolved by the parent skill.

1. Post a pull request comment with the shortest trigger by default:
   ```bash
   gh pr comment <PR> --body "@codex review"
   ```
   If the user provided review focus or criteria after invoking the skill, use
   the documented one-off focus form:
   ```bash
   gh pr comment <PR> --body "@codex review for <user-provided focus>"
   ```
2. Verify the `@codex review` comment exists, and capture its `id` and URL:
   ```bash
   gh api repos/<owner>/<repo>/issues/<PR>/comments --jq \
     '[.[] | select(.body | startswith("@codex review")) | {id, user: .user.login, body: .body, url: .html_url, created_at}] | sort_by(.created_at) | last'
   ```
3. Poll the posted comment for up to 120 seconds for an `eyes` reaction:
   ```bash
   gh api --method GET repos/<owner>/<repo>/issues/comments/<comment_id>/reactions \
     -H "Accept: application/vnd.github+json" \
     -f content=eyes \
     --jq '[.[] | select(.content == "eyes") | {user: .user.login, created_at}]'
   ```
   Repeat at 5-10 second intervals until the output is non-empty or the timeout expires.
4. Report the PR URL, the trigger comment URL, and one of these outcomes:
   - `Codex acknowledged`: the posted comment has an `eyes` reaction.
   - `Codex request posted but not acknowledged`: the comment exists, but no `eyes`
     reaction appeared before the timeout.
5. If the user explicitly asks to retry an unacknowledged request, delete only
   the exact trigger comment you posted, repost the same trigger once, and repeat
   the `eyes` reaction polling:
   ```bash
   gh api --method DELETE repos/<owner>/<repo>/issues/comments/<comment_id>
   ```
   If the posted trigger comment cannot be identified unambiguously, stop
   instead of deleting a matching older comment.

## Guardrails

- Do not create a PR.
- Do not push, commit, merge, or edit repository files.
- Do not request Copilot review from this provider procedure.
- Use only the PR comment path described above to request Codex review.
- Treat comment existence as proof that the request was posted, not as proof
  that Codex picked it up.
- Do not claim Codex acknowledged the request unless the posted comment has an
  `eyes` reaction.
- Assume Codex review is already configured unless an API error proves
  otherwise; do not run setup troubleshooting by default.
- Do not delete or repost the trigger comment unless the user explicitly asks
  for a retry after an acknowledgement timeout.
- Do not delete any comment unless it is the exact trigger comment posted by
  this workflow.
- Retry at most once.
- If Codex is unavailable, permission-blocked, or the repository does not support Codex review, report that explicitly.
