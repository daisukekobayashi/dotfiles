# Risk Tier

The tier describes the change, not its author. It selects the security
reviewer and the recommended human review; every tier still runs the full
local review pair and the caller's merge confirmation.

## Set and update the tier

- **Tentative:** at preflight, from the task's scope and the paths it will
  likely touch.
- **Final:** at the start of each full local review, from the committed diff
  against the recorded base. A focused follow-up re-evaluates the tier from the
  delta since the preceding reviewed head; the tier never drops below the one
  already recorded for this delivery unless the task scope itself narrowed.
- **Changed head:** re-evaluate whenever the head changes, including hosted
  follow-up fixes, before reusing review evidence.

Record the tier, the dimension ratings, the matched sensitive paths, and the
head they describe in the progress record. Diff size, test count, green CI, and
the author's confidence never establish a lower tier by themselves.

## Rate the dimensions

Rate each from the diff and its callers:

- **Impact if wrong:** `low` (local, no contract, state, privilege, or shared
  runtime effect), `moderate` (bounded component with clear containment),
  `high` (shared runtime, public contract, persistent state, privileged
  boundary, broad deployment), `critical` (major security, irreversible state,
  fleet-wide).
- **Regression likelihood:** `low`, `moderate`, `high`, or `critical`
  (a regression is already evidenced).
- **Regression protection:** `strong` (checks observe the changed behavior
  through affected callers and ran at this head), `partial`, `none`, or
  `unknown`.
- **Recoverability:** `easy` (isolated revert), `managed` (needs coordination
  or cleanup), or `hard` (irreversible, stateful, or uncertain).
- **Confidence:** `high`, `moderate`, or `low` in the ratings above.

Strong protection lowers likelihood and raises confidence; it never lowers impact.

## Assign the tier

- **Low:** impact and likelihood `low`, protection `strong`, recovery `easy`,
  confidence `high`, and no sensitive path touched.
- **High:** impact `high` or `critical`, likelihood `high` or `critical`,
  recovery `hard`, or confidence `low`.
- **Medium:** everything else, including any `unknown` rating.

## Sensitive paths

Read the reviewed repository's policy at the merge-base: paths that
`SECURITY.md` files name as sensitive, and `CODEOWNERS` entries other than a
catch-all owner. Without such policy, use these defaults:

- CI/CD workflow and pipeline definitions
- authentication, authorization, secret, and credential handling
- install, setup, and bootstrap scripts
- agent permission, tool allowlist, and hook configuration
- agent instruction files: skills, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`

A change that adds, edits, or deletes `SECURITY.md` or `CODEOWNERS` touches a
sensitive path; changed policy applies to later deliveries, never this one.

## Select the security review

Run `change-security-review` as a third local reviewer when the tier is High or
the diff touches a sensitive path. Once selected, keep it on every later full
pair in this delivery, and include it in a focused follow-up when the delta
touches a sensitive path or fixes an accepted security finding.

Assess its findings with Local Review's Assess findings; its `introduced` and
`worsened` findings are `material`. Advance and merge only with no open
material security finding. Present its deferred candidates on sensitive paths
to the user before publication; they need a user decision, not silence.

## Recommend human review

| Tier | Recommended review |
| --- | --- |
| Low | AI review only |
| Medium | One human reviewer |
| High | Multiple human reviewers |

Show the tier, its main reasons, and the recommendation before PR publication
and in the merge confirmation, and keep them in the progress record. Keep them
out of the PR body. The recommendation adds to repository-required approvals
and never replaces them. When the recommended reviewers are unavailable, say so
in the merge confirmation and let the user decide. For High, mention that
naming another review tool, such as Codex, gives a more independent review than
same-host subagents; switch routes only when the user names it.

## Source

Rating dimensions adapted from the `assess-patch-risk` risk rubric in OpenAI's
[codex-security](https://github.com/openai/codex-security/tree/cb92c4fb41510a1c5e51452897e5d94b2f9f083e/plugins/codex-security)
plugin (Apache-2.0), compared on 2026-11-04 with upstream commit `cb92c4f`.
Its strict auto-merge gate became the Low tier here; local delivery always
keeps the user's merge confirmation.
