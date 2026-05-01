---
name: github-pr-ai-review-request
description: Use only when the user explicitly invokes `$github-pr-ai-review-request` or names `github-pr-ai-review-request` for requesting both Copilot and Codex review on an existing GitHub pull request.
---

# GitHub PR AI Review Request

## Scope

Use this wrapper skill to request both Copilot and Codex review on an existing
pull request.

This skill is not for:
- creating pull requests
- Copilot-only requests
- Codex-only requests
- reading or applying review feedback

## Workflow

1. Resolve the current GitHub repository and target PR once.
   - Use the PR number or URL in the prompt when provided.
   - Otherwise use `gh pr view --json number,url` on the current branch.
   - If no PR can be resolved, stop and ask for the PR number or URL.
2. Invoke `github-pr-copilot-review-request` for the same PR.
3. Invoke `github-pr-codex-review-request` for the same PR.
4. If one request fails, continue to the other unless auth or repository access is completely blocked.
5. Verify final state:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<PR> --jq \
     '{url: .html_url, requested_reviewers: [.requested_reviewers[].login]}'
   gh api repos/<owner>/<repo>/issues/<PR>/comments --jq \
     '[.[] | select(.body | startswith("@codex review")) | {user: .user.login, body: .body, url: .html_url}]'
   ```
6. Report separate outcomes: Copilot is verified from requested reviewers, and
   Codex is verified from a PR comment containing `@codex review`.

## Guardrails

- Do not create a PR.
- Do not push, commit, merge, or edit repository files.
- Keep Copilot and Codex results separate in the final report.
- Do not hide partial failure: if only one AI review request succeeds, say exactly which one.
