# feat(skills): run Codex-routed local reviewers for one worktree in parallel

## Summary
Let the local reviewers selected for one worktree (`change-review`, `change-adversarial-review`, `change-security-review`) run their Codex runs in parallel instead of one at a time, without one run stopping a broker another run is still using.

## Background
4265c5c added broker cleanup around each Codex companion run and, with it, the rule "Run one Codex run at a time per target worktree". The cleanup in `worktree-runtime-cleanup` "Brokers Started by a Codex Review" treats an `app-server-broker.mjs` as owned by the run when it is absent from the pre-run process list and its cwd equals the target worktree root.

With parallel runs on the same worktree this ownership test breaks: when runs A and B both snapshot before the shared broker starts, both see it as their own after the run. The first to finish sends SIGTERM to a broker the other may still be using, and that review fails; the review skills stop on a failed Codex run with no fallback. Two runs starting together can also each spawn a broker (`ensureBrokerSession` race in the codex plugin).

Parallelism itself is otherwise supported or harmless:
- The codex plugin (1.0.6) answers a busy shared broker with `Shared Codex broker is busy.` and the client retries over a direct app-server (`scripts/lib/codex.mjs:621-633`).
- The runs are read-only (no `--write`).
- The reviewers run independent full reviews of the same pinned head (`risk-tier.md` Tier procedure); none consumes another's output.

## Acceptance Criteria
- When the caller runs several Codex-routed reviewers on one pinned head of one worktree, it runs them in parallel as one set by default; only when the host cannot run them concurrently does it run them one at a time with per-run cleanup, and it reports that.
- Broker cleanup for parallel runs happens once around the whole set: the caller records the process list before starting any reviewer, waits for all to finish (including failed runs), then stops only brokers absent from that list whose cwd exactly equals the worktree root, under the existing ownership rules.
- A reviewer that runs in a parallel set does not stop brokers itself; a reviewer run alone keeps its current per-run cleanup and still waits for any other Codex run in progress on that worktree.
- Runs for different worktrees stay unaffected.
- **Unchanged:** the read-only sandbox, the no-fallback-on-failure rule, the broker ownership test, and SIGTERM-only stops.
- **Tests:** the wiring tests are updated, and `npm --prefix setup test` and `scripts/check-skills-build.sh` pass.

## Implementation Notes
- No signal from caller to reviewer: on the Codex route the session that invokes the review skills launches the companion runs itself, so the launching session owns the set and its cleanup. The set rule lives in each reviewer's Run the Reviewer section; keep the added wording minimal.
- The reviewer's result report should still include the cleanup result; in a parallel set the caller reports it once.

## Touched Areas (estimate)
- `skills/local/change-review/SKILL.md`, `skills/local/change-adversarial-review/SKILL.md`, `skills/local/change-security-review/SKILL.md`
- `skills/local/delivery-common/references/local-review.md`
- `skills/local/worktree-runtime-cleanup/SKILL.md` ("Brokers Started by a Codex Review")
- `setup/test/skills-wiring-delivery.test.mjs`

## Dependencies
None.

## Parallelization
Overlaps `delivery-common` with #142 and #143, and `worktree-runtime-cleanup` with #120; do not implement in the same wave as those.


