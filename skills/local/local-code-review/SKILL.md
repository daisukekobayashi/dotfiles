---
name: local-code-review
description: Use only when the user explicitly invokes `$local-code-review` or names `local-code-review` to request a local code review with installed Codex or Claude CLI tools.
---

# Local Code Review

## Scope

Run a read-only local code review with installed CLI tools such as `codex` and `claude`. Review local changes before a PR or merge; do not request cloud PR review, post comments, mutate remote systems, or apply fixes.

## Required Choices

Before running any provider command, resolve both choices:

1. Provider: `codex`, `claude`, or `both`
2. Target: `working-tree`, `staged`, `branch`, or `commit`

If either provider or review target is omitted, ask the user. Do not default to `both`.

## Workflow

1. Confirm local state with `git status --short --branch`; identify the target without changing branches.
2. Verify provider availability: `command -v codex`, `command -v claude`; check `codex review --help` or `claude --help` when command shape is uncertain.
3. Build a findings-first prompt with the rubric below and an explicit "read-only, no edits or remote comments" instruction.
4. Run provider commands read-only:
   - Codex working tree: `codex review --uncommitted "<review prompt>"`
   - Codex branch: `codex review --base <base-branch> "<review prompt>"`
   - Codex commit: `codex review --commit <sha> "<review prompt>"`
   - Claude: use `claude -p --permission-mode plan "<review prompt>"` and include explicit target instructions.
   - For staged-only review, feed `git diff --staged --patch` as context to the selected provider rather than reviewing unstaged changes.
5. Synthesize results. Keep provider findings separate, deduplicate only clear duplicates, and report provider disagreement as residual risk.

## Review Rubric

Ask providers to check: correctness, regression risk, security/privacy, data safety, error handling, concurrency/idempotency, tests, maintainability, performance, operations/config, and docs/user impact.

## Output Format

```markdown
**Findings**
- [High|Medium|Low] <title> - <file:line or diff context>
  <impact, evidence, and suggested fix>
- If no issues are found: No blocking findings found.

**Provider Notes**
- codex: <summary or "not run">
- claude: <summary or "not run">

**Test Gaps**
- <missing verification or "None found">

**Residual Risk**
- <uncertainty, provider disagreement, unreviewed areas>

**Verdict**
- Approve equivalent | Comment equivalent | Request changes equivalent
```

## Guardrails

- Do not run unless the user explicitly invokes `$local-code-review` or names `local-code-review`.
- Do not run provider commands until provider and target are resolved.
- Do not edit files, stage, commit, push, branch, create PRs, post comments, or resolve threads.
- Do not invoke cloud PR review request skills.
- Do not pass secrets, `.env` contents, private keys, or broad environment dumps to providers.
- If the diff contains sensitive data, stop and ask before sending it to any provider.
- If a provider command fails, report the exact blocker and do not invent that provider's findings.
