# fix(skills): resolve the publish remote and upstream unambiguously

## Summary
Make the publish skills resolve the push remote and read the upstream unambiguously, and close the remaining edge cases left by #43.

## Background
Deferred findings from the local reviews of #43 (PR #54, rounds 2-3); the user chose to publish #43 and track them here.
- `<remote>` in `github-pr-publish` / `azure-devops-pr-publish` step 7 is "the repository remote resolved in step 2", but step 2 resolves the repository, not a git remote name. In a fork layout an agent could pick the parent's remote; the pre- and post-push upstream checks keep this from pushing to the base.
- A branch name starting with `+` makes the explicit refspec `<branch>:refs/heads/<branch>` a force push. Start-skill branch formats cannot start with `+`.
- `git config --get branch.<branch>.merge` returns the last value when the key has several values, while git uses the first; a manually added second value can be misread as the same-named upstream (the later push then fails safely).
- The publish skills say "the PR base branch, local or remote-tracking" without stating that a local base shows remote `.`, as the start skills do.
- With `branch.<branch>.pushRemote` set, the later plain push in `github-pr-codex-review-cycle` goes to that remote instead of the PR head (pre-existing).

## Acceptance Criteria
- Step 2 or step 7 names the git remote whose URL matches the resolved repository, and the push and recheck use that remote.
- A branch name starting with `+` is refused before the push.
- The upstream read uses `--get-all` (or equivalent) and continues only on exactly one value.
- The publish skills spell out the local-base `remote .` case.
- The review-cycle follow-up push targets the same remote as publication, or the cycle checks `pushRemote`.
- `setup/test/skills-wiring-issue-start.test.mjs` (and `skills-wiring-pr.test.mjs` if the cycle changes) assert the wiring.

## Open Questions
- Whether the review cycle should push with the same explicit refspec as publication.

## Touched Areas (estimate)
- `skills/local/github-pr-publish/SKILL.md`, `skills/local/azure-devops-pr-publish/SKILL.md`
- `skills/local/github-pr-codex-review-cycle/SKILL.md`
- `skills/local/github-issue-start/SKILL.md`, `skills/local/azure-devops-work-item-start/SKILL.md`, `skills/local/beads-issue-worktree/SKILL.md` (multi-value read)
- `setup/test/skills-wiring-issue-start.test.mjs`, `setup/test/skills-wiring-pr.test.mjs`

## Dependencies
None.

## Parallelization
Shares the start skills and `setup/test/skills-wiring-issue-start.test.mjs` with the slug follow-up; implement sequentially.

