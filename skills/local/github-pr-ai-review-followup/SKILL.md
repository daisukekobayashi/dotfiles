---
name: github-pr-ai-review-followup
description: Use when the user wants to follow up on GitHub Copilot or Codex review feedback on a pull request, including AI review threads that may need code fixes, explanations, or resolution.
---

# GitHub PR AI Review Follow-Up

## Scope

This skill covers GitHub Copilot and Codex review feedback and the decision record for each AI review thread. It is not for human review sweeps, generic bot spam, unattended GitHub writeback, PR publishing, or merge handling.

## Workflow

1. Resolve the current-repo PR from a provided number/URL or the current branch; ask if ambiguous.
2. Fetch PR metadata and AI review comments with the GitHub plugin.
3. When inline context, resolution state, stale/outdated state, or GitHub writeback matters, follow `github:gh-address-comments`; flat comment reads are insufficient.
4. Identify the latest Copilot or Codex review feedback. If the source is ambiguous, say so instead of guessing.
5. Split feedback into actionable, explanation-only, stale/resolved/duplicate/non-actionable, and ambiguous/conflicting/risky items.
6. Apply only the worthwhile local fixes. Skip speculative churn, style-only noise, and anything likely to cause regression.
7. Assign a disposition to every latest AI feedback item, even when no code changed.
8. Draft a GitHub writeback preview: comments, resolve targets, open threads, and human-decision items.
9. Perform only writeback the user explicitly requested or approved. Otherwise, report the preview without writing to GitHub.
10. Summarize changes, skips, comments/resolutions, open items, and verification.

## Dispositions

- `applied`: Addressed by local code or tests. Draft a short response and mark as a resolve candidate.
- `explained`: Needs explanation, not code. Resolve only if the explanation fully closes the point.
- `skipped`: Intentionally not applied. Include the technical reason. Leave open if reasonable disagreement remains.
- `stale`: No longer applies to the current diff. Draft a stale note and mark as a resolve candidate.
- `duplicate`: Covered elsewhere. Reference the covering item and mark as a resolve candidate.
- `needs-human-decision`: Ambiguous, conflicting, policy-sensitive, or risky. Draft the question or tradeoff and leave open.

## GitHub Writeback

- Approval to inspect or fix AI review feedback is not approval to write to GitHub.
- Prefer the specific review thread or comment. Use a top-level PR comment only when no thread target exists.
- Keep comments short: outcome, reason, and verification.
- Resolve only unresolved, thread-aware review threads whose disposition clearly closes the feedback: usually `applied`, `stale`, or `duplicate`.
- Do not resolve `needs-human-decision`. Do not resolve `skipped` unless the skip reason fully answers the feedback and the user approved resolving it.
- After writeback, verify the resulting thread state when possible.

Comment shapes:
- `Addressed. Changed <file or behavior>. Verification: <command or not run reason>.`
- `Not changed. Reason: <technical reason>. Leaving open for maintainer decision.`
- `Stale after the latest changes. This no longer applies to the current diff.`

## Guardrails

- Do not reply on GitHub, resolve threads, or submit a review unless the user explicitly asks for that write action or approves the writeback preview.
- Do not treat flat PR comments as a full representation of thread state when thread context matters.
- Do not resolve a thread unless thread-aware data confirms the target and current resolution state.
- Do not assume every Copilot or Codex suggestion should be applied.
- Do not assume cross-repository PRs. This skill is current-repo only.
- If auth, rate limits, or missing PR context block review inspection, stop and report the blocker.
