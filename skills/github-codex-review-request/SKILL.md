---
name: github-codex-review-request
description: Use only when the user explicitly invokes `$github-codex-review-request` or names `github-codex-review-request`. Do not use for generic PR creation, PR review, or AI review requests.
---

# GitHub Codex Review Request

## Scope

Use this skill to request Codex review on an existing pull request.

Codex availability varies by environment, so this skill treats reviewer request
success and mention-comment fallback as separate outcomes.

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
4. Try to resolve the Codex GitHub user:
   ```bash
   gh api users/codex --jq '{login: .login, id: .id, type: .type}'
   ```
5. Try a reviewer request with GraphQL:
   ```bash
   PR_NODE_ID=$(gh api repos/<owner>/<repo>/pulls/<PR> --jq .node_id)
   gh api graphql -F pullRequestId="$PR_NODE_ID" -f query='
     mutation($pullRequestId: ID!) {
       requestReviewsByLogin(input: {
         pullRequestId: $pullRequestId,
         userLogins: ["codex"],
         union: true
       }) {
         pullRequest {
           number
         }
       }
     }'
   ```
6. Verify whether `codex` appears as a requested reviewer:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<PR> --jq \
     '{url: .html_url, requested_reviewers: [.requested_reviewers[].login]}'
   ```
7. If `codex` is not a requested reviewer, post a mention comment. Use the
   shortest trigger by default:
   ```bash
   gh pr comment <PR> --body "@codex review"
   ```
   If the user provided review focus or criteria after invoking the skill, append
   it as a concise instruction:
   ```bash
   gh pr comment <PR> --body "@codex review: <user-provided focus>"
   ```
8. Verify the comment exists with:
   ```bash
   gh api repos/<owner>/<repo>/issues/<PR>/comments --jq \
     '[.[] | select(.body | startswith("@codex review")) | {user: .user.login, body: .body, url: .html_url}]'
   ```
9. Report whether Codex was requested as a reviewer, requested by mention comment, or blocked.

## Guardrails

- Do not create a PR.
- Do not push, commit, merge, or edit repository files.
- Do not request Copilot review from this skill.
- Do not claim Codex review was requested unless reviewer verification or comment verification supports it.
- If Codex is unavailable, permission-blocked, or the repository does not support Codex review, report that explicitly.
