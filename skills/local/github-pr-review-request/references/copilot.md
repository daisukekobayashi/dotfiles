# Copilot Review Request

Use the repository and PR resolved by the parent skill.

1. Request Copilot review using the official GitHub CLI path:
   ```bash
   gh pr edit <PR> --add-reviewer @copilot
   ```
2. If `gh pr edit` fails because the GitHub CLI hits an unrelated GraphQL field error, use the GraphQL fallback:
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
3. Verify the request with:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<PR> --jq \
     '{url: .html_url, requested_reviewers: [.requested_reviewers[].login]}'
   ```
4. Report the PR URL and whether `Copilot` appears in requested reviewers.

## Guardrails

- Do not create a PR.
- Do not push, commit, merge, or edit repository files.
- Do not request Codex review from this provider procedure.
- If Copilot review is unavailable due to plan, policy, permission, or API limits, report the blocker and stop.
- If verification cannot prove Copilot was requested, say so instead of assuming success.
