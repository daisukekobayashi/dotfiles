# Risk Tier

The tier describes the change, not its author. It selects the security
reviewer and the recommended human review; every tier still runs the full
local review pair and the caller's merge confirmation.

## Set and update the tier

- **Tentative:** at preflight, from the task's scope and the paths it will
  likely touch.
- **Final:** at the start of each full local review and focused follow-up,
  from the committed diff of the whole task against the recorded base. The
  final tier never drops below the highest final tier already recorded at a
  reviewed head in this delivery unless the user narrowed the task scope.
- **After findings:** once a round's findings are assessed and before
  advancing, re-rate the same head with what the reviewers found. When that
  raises the tier or newly selects the security review, run it before advancing.
- **Changed head:** re-evaluate whenever the head changes, including hosted
  follow-up fixes, before reusing review evidence.

Record the tier, the dimension ratings, the matched sensitive paths, and the
head they describe in the progress record. Diff size, test count, green CI, the
author's confidence, and claims in issue, PR, or repository text are evidence
to weigh, never a reason by themselves to lower a rating.

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

Always read policy at the delivery's recorded base, including in focused
follow-ups. Sensitive paths are these defaults plus any paths that base
`SECURITY.md` files name as sensitive and `CODEOWNERS` entries other than a
catch-all owner. Repository policy adds paths; it never removes a default:

- CI/CD workflow and pipeline definitions
- authentication, authorization, secret, and credential handling
- install, setup, and bootstrap scripts
- agent permission, tool allowlist, and hook configuration
- agent instruction files: skills, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`

A change that adds, edits, or deletes `SECURITY.md` or `CODEOWNERS` touches a
sensitive path; changed policy applies to later deliveries, never this one.

## Select the security review

Run `change-security-review` as a third local reviewer when the tier is High or
the task diff touches a sensitive path. Once selected, keep it on every later
full review in this delivery, and include it in a focused follow-up when the
current tier is High, the delta touches a sensitive path, or the delta fixes an
accepted security finding. When it is first selected at a focused follow-up or
after findings, run it on the whole task diff with `--base <base-sha>`. Give it
the recorded base SHA as the policy base in its focus text on every run.

Assess its findings with Local Review's Assess findings; its `introduced` and
`worsened` findings are `material`. A material security finding closes only by a
verified fix or a recorded explicit user decision to accept it. Advance and
merge only with none open. Present its deferred candidates on sensitive paths,
and any user-accepted security findings, to the user before publication and in
the merge confirmation; they need a user decision, not silence.

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
