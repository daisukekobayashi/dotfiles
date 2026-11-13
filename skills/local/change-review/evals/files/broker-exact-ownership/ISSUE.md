# fix(skills): stop the Codex review broker before delivery cleanup

## Summary
Stop the Codex companion broker that a Codex-routed local review starts in an issue worktree, so delivery cleanup is not blocked by leftover processes.

## Background
Found during the delivery of #73, #77, and #70 (PRs #88-#90), where the user asked for local reviews through Codex.
- The `change-review`, `change-adversarial-review`, and `change-security-review` Codex route runs `codex-companion.mjs task --fresh --cwd <target worktree>`. Each run starts or reuses an `app-server-broker.mjs` for that cwd, with `codex app-server`, Serena MCP servers, and language servers as children.
- The broker session is keyed by cwd and is torn down only by the companion's session-end hook (`session-lifecycle-hook.mjs` `teardownBrokerSession`), so it outlives the review and keeps the worktree as its cwd until the Claude Code session ends.
- At cleanup, `lsof` showed these processes in each issue worktree. The coordinator had to stop three broker trees by hand (one tree needed SIGTERM twice), and one worktree was removed while its broker was still running.

## Acceptance Criteria
- After a Codex-routed review completes, the broker it started for that worktree is shut down (or delivery cleanup shuts it down) before the worktree is removed, without killing brokers that serve other worktrees.
- Cleanup still reports and stops on unrelated processes that use the worktree.
- The Claude-subagent route is unaffected.
- Wiring tests assert the new step.

## Open Questions
- Where the shutdown belongs: in each review skill's Codex route after the run, or in `github-worktree-cleanup` / `azure-devops-worktree-cleanup` as a known runtime to stop.
- Whether the companion exposes a supported per-cwd shutdown, or only the session-end hook does.

## Touched Areas (estimate)
- `skills/local/change-review/SKILL.md`, `skills/local/change-adversarial-review/SKILL.md`, `skills/local/change-security-review/SKILL.md` (Codex route), or
- `skills/local/github-worktree-cleanup/SKILL.md`, `skills/local/azure-devops-worktree-cleanup/SKILL.md` (runtime inspection)
- the matching `setup/test/skills-wiring-*.test.mjs`

## Dependencies
None.

## Parallelization
Independent of the other follow-ups from #73 / #77 / #70.

