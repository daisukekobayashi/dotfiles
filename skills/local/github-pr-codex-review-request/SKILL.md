---
name: github-pr-codex-review-request
description: Use only when the user explicitly invokes `$github-pr-codex-review-request` or names `github-pr-codex-review-request` for requesting Codex review on an existing GitHub pull request.
---

# GitHub PR Codex Review Request

## Scope

Use this skill to request Codex review on an existing pull request.

Codex review is requested by adding a pull request comment that mentions
`@codex review`.

This skill is not for:
- creating pull requests
- requesting Copilot review
- reading or applying review feedback
- generic human reviewer requests

## Workflow

1. Resolve the current GitHub repository from local git context.
2. Resolve the pull request:
   - Use the PR number or URL in the prompt when provided.
   - Otherwise use `gh pr view --json number,url` on the current branch.
   - If no PR can be resolved, stop and ask for the PR number or URL.
3. Confirm the PR exists with `gh pr view <PR> --json number,url,state`.
4. Post a pull request comment with the shortest trigger by default:
   ```bash
   gh pr comment <PR> --body "@codex review"
   ```
   If the user provided review focus or criteria after invoking the skill, use
   the documented one-off focus form:
   ```bash
   gh pr comment <PR> --body "@codex review for <user-provided focus>"
   ```
5. Verify the `@codex review` comment exists with:
   ```bash
   gh api repos/<owner>/<repo>/issues/<PR>/comments --jq \
     '[.[] | select(.body | startswith("@codex review")) | {user: .user.login, body: .body, url: .html_url}]'
   ```
6. Report the PR URL and whether the comment verification proves Codex review was requested.

## Guardrails

- Do not create a PR.
- Do not push, commit, merge, or edit repository files.
- Do not request Copilot review from this skill.
- Use only the PR comment path described above to request Codex review.
- Do not claim Codex review was requested unless comment verification supports it.
- If Codex is unavailable, permission-blocked, or the repository does not support Codex review, report that explicitly.
