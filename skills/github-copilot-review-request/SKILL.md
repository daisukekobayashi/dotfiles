---
name: github-copilot-review-request
description: Use only when the user explicitly invokes `$github-copilot-review-request` or names `github-copilot-review-request`. Do not use for generic PR creation, PR review, or AI review requests.
---

# GitHub Copilot Review Request

## Scope

Use this skill to request a GitHub Copilot review on an existing pull request.

This skill is not for:
- creating pull requests
- requesting Codex review
- reading or applying review feedback
- generic human reviewer requests

## Workflow

1. Resolve the current GitHub repository from local git context.
2. Resolve the pull request:
   - Use the PR number or URL in the prompt when provided.
   - Otherwise use `gh pr view --json number,url` on the current branch.
   - If no PR can be resolved, stop and ask for the PR number or URL.
3. Confirm the PR exists with `gh pr view <PR> --json number,url,state`.
4. Request Copilot review using the official GitHub CLI path:
   ```bash
   gh pr edit <PR> --add-reviewer @copilot
   ```
5. If `gh pr edit` fails because the GitHub CLI hits an unrelated GraphQL field error, use the GraphQL fallback:
   ```bash
   PR_NODE_ID=$(gh api repos/<owner>/<repo>/pulls/<PR> --jq .node_id)
   gh api graphql -F pullRequestId="$PR_NODE_ID" -f query='
     mutation($pullRequestId: ID!) {
       requestReviewsByLogin(input: {
         pullRequestId: $pullRequestId,
         botLogins: ["copilot-pull-request-reviewer[bot]"],
         union: true
       }) {
         pullRequest {
           number
         }
       }
     }'
   ```
6. Verify the request with:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<PR> --jq \
     '{url: .html_url, requested_reviewers: [.requested_reviewers[].login]}'
   ```
7. Report the PR URL and whether `Copilot` appears in requested reviewers.

## Guardrails

- Do not create a PR.
- Do not push, commit, merge, or edit repository files.
- Do not request Codex review from this skill.
- If Copilot review is unavailable due to plan, policy, permission, or API limits, report the blocker and stop.
- If verification cannot prove Copilot was requested, say so instead of assuming success.
