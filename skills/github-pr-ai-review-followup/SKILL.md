---
name: github-pr-ai-review-followup
description: Use when the user wants to inspect the latest Copilot or Codex review feedback on a GitHub pull request, filter worthwhile comments, and apply useful follow-up fixes locally.
---

# GitHub PR AI Review Follow-Up

## Scope

This skill is for:
- GitHub Copilot review feedback
- Codex-generated review feedback

This skill is not for:
- all human review comments
- generic bot spam
- PR publishing or merge handling

## Workflow

1. Resolve the PR in the current repo and fetch its metadata and comments with the GitHub plugin.
2. When thread-aware review state matters, follow `gh-address-comments` instead of relying on flat comment reads alone.
3. Identify the latest Copilot or Codex review feedback. If the source is ambiguous, say so instead of guessing.
4. Split the feedback into:
   - actionable code changes
   - explanation-only comments
   - stale, resolved, duplicate, or non-actionable comments
5. Apply only the worthwhile local fixes. Skip speculative churn, style-only noise, and anything likely to cause regression.
6. If a suggestion is ambiguous, conflicting, or risky, stop and explain the tradeoff before editing.
7. Summarize what was changed, what was skipped, and what verification supports the result.

## Guardrails

- If the prompt does not include a PR number, stop and ask for one.
- Do not reply on GitHub, resolve threads, or submit a review unless the user explicitly asks for it.
- Do not treat flat PR comments as a full representation of thread state when thread context matters.
- Do not assume every Copilot or Codex suggestion should be applied.
- Do not assume cross-repository PRs. This skill is current-repo only.
- If auth, rate limits, or missing PR context block review inspection, stop and report the blocker.
