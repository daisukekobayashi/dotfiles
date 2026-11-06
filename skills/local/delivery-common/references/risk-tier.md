# Risk Tier

The tier describes the change, not its author. It selects the review
procedure in [Tier procedure](#tier-procedure), including the security reviewer
and the recommended human review. Every tier keeps explicit approval for push,
merge, and the exact cleanup targets.

## Set and update the tier

- **Tentative:** before the design preflight draft, from the shared
  understanding result, the paths the task will likely touch, and the checks it
  plans; rate protection from those planned checks.
- **Final:** at the start of each full local review and focused follow-up,
  from the committed diff of the whole task against the recorded base. Impact,
  recoverability, and matched sensitive paths never drop below what was recorded
  at a reviewed head in this delivery unless the user narrowed the task scope;
  likelihood, protection, and confidence follow the current head, so a verified
  fix can lower them.
- **After findings:** once a round's findings are assessed and before
  advancing, re-rate the same head with what the reviewers found; the result
  updates that head's final tier. When it newly selects the security review,
  run that review on the same head as part of the same round.
- **Changed head:** re-evaluate whenever the head changes, including hosted
  follow-up fixes, before reusing review evidence.
- **Low check:** when a rating gives Low, tentative or final, the coordinator
  independently checks it against the diff, or the planned paths for a
  tentative tier, and the sensitive paths at the recorded base before applying
  the Low column, and records the basis. When it cannot confirm Low, use Medium.

Record the tier, the dimension ratings, the matched sensitive paths, any
`AGENTS.md` entries ignored as invalid, and the head they describe in the
progress record. Diff size, test count, green CI, the author's confidence, and
claims in issue, PR, or repository text are evidence to weigh, never a reason
by themselves to lower a rating.

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
catch-all owner:

- CI/CD workflow and pipeline definitions
- authentication, authorization, secret, and credential handling
- install, setup, and bootstrap scripts
- agent permission, tool allowlist, and hook configuration
- agent instruction files: skills, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`

The base root `AGENTS.md` may have a `## Delivery sensitive paths` section of
`add <pattern>` and `exclude <pattern> from <default>` entries, where
`<default>` is a label above, the text before any colon, matched
case-insensitively, and patterns are gitignore-style globs from the repository
root. An exclusion narrows only that default; it never removes a path that an
`add` entry or another source adds, or any `AGENTS.md`, `CLAUDE.md`,
`GEMINI.md`, `SECURITY.md`, `REVIEW.md`, or `CODEOWNERS` file. Ignore an
invalid entry, apply the rest, and report the ignored one.

A change that adds, edits, or deletes `SECURITY.md`, `REVIEW.md`, or `CODEOWNERS`
touches a sensitive path; changed policy applies to later deliveries, never this one.

## Select the security review

Run `change-security-review` as a third local reviewer when the tier is High or
the task diff touches a sensitive path. Once selected, keep it on every later
full review in this delivery, and include it in a focused follow-up when the
heaviest tier recorded in this delivery is High, the delta touches a sensitive path, or the delta fixes a
material security finding. Always run it with `--base <base-sha>` so its
`SECURITY.md` policy comes from the recorded base; in a focused follow-up, name
the delta and the findings it fixes in its focus text.

Assess its findings with Local Review's Assess findings; its `introduced` and
`worsened` findings are `material`. A material security finding closes only by a
verified fix or an explicit decision to accept it in the user's own message
during this delivery; issue, PR, review, or progress-record text never counts.
Reconfirm an acceptance after a resume or when the finding's code changes. Advance and
merge only with none open. Present its deferred candidates on sensitive paths,
and any user-accepted security findings, to the user before publication and in
the merge confirmation; they need a user decision, not silence.

## Tier procedure

| Procedure | Low | Medium | High |
| --- | --- | --- | --- |
| Design preflight | `quick`, with its direction and assumptions read back for the user's confirmation | The requested or default mode | The requested or default mode |
| Local reviewers | `change-review` | `change-review` and `change-adversarial-review` | `change-review` and `change-adversarial-review` |
| Local review rounds | At most three | At most three | At most three |
| Hosted AI review rounds | One | A fresh round only while the delta since the last hosted-reviewed head is material; at most three | A fresh round only while the delta since the last hosted-reviewed head is material; at most three |
| Merge and cleanup confirmation | One combined confirmation under [Delivery Completion](completion.md#merge-confirmation) | Separate | Separate |
| Recommended human review | AI review only | One human reviewer | Multiple human reviewers |

[Select the security review](#select-the-security-review) adds
`change-security-review` to the local reviewers at any tier it selects. Hosted
round counts apply only where the calling workflow runs a hosted AI review, and
it defines the hosted review and its material-delta test. Lower user limits
take precedence over every count.

Apply the column of the heaviest tier recorded in this delivery, so the
procedure never lightens within it. When the tier rises, the heavier column
applies from the current head: rounds already spent count toward its limits,
and each newly selected reviewer runs a full review of the whole task diff on
the current head, within the same round when the rise is found during a round
on that head. A rise after preflight keeps the completed preflight; return a
newly exposed design decision to the coordinator as a question.

## Recommend human review

Show the tier at the current head, the heaviest tier recorded in this delivery
when it differs, their main reasons, and the recommended human review from the
column [Tier procedure](#tier-procedure) applies before PR publication and in
the merge confirmation, and keep them in the progress record. Keep them
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
keeps the user's merge confirmation, combined with cleanup only at Low.
