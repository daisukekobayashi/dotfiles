---
name: delivery-common
description: Shared worker dialogue, local review procedure, risk tier, and completion policy for GitHub issue and Azure DevOps Work Item delivery. Read when a delivery workflow has workers draft the shared understanding and design preflight for the coordinator to ask, sets a change's risk tier, requires normal, adversarial, and security reviews, selects focused follow-up of a committed implementation, decides whether local reviews repeat or advance, keeps a progress record, prepares a merge confirmation, stops at a bound, or reports completion and follow-up candidates.
---

# Delivery Common

Use [Worker Dialogue](references/worker-dialogue.md) for each target's shared
understanding and design preflight: workers draft, and the coordinator asks the
user. Use [Local Review](references/local-review.md) when a delivery workflow
reaches its local reviews or selects focused follow-up, and apply its Assess
findings to local and hosted findings. Use [Risk Tier](references/risk-tier.md)
to set the tier before preflight and on each reviewed head, and to select the
tier's review procedure, including the security reviewer and the recommended
human review. Local Review also sets local review
escalation, advancement, and round limits. Use
[Delivery Completion](references/completion.md) for the progress record, the
decision summary shown before publication and at merge, the merge
confirmation, bounds, the final report and `Complete` rule, and follow-up
candidates.

The calling workflow owns implementation, assessment decisions, how its hosted
review runs, publication, and approvals. Where shared text names the calling
workflow's additions, the calling workflow lists its provider-specific items
next to its link. Return the completed results, review scope, reviewed
snapshot, and tier to that caller.

[`scripts/check-branch-name.mjs`](scripts/check-branch-name.mjs) is the shared
**safe branch name** check. The start, delivery, PR, and cleanup skills of every
provider, including Beads, run it from their own step; its header gives the
usage and exit codes.

[`scripts/check-push-target.mjs`](scripts/check-push-target.mjs) is the shared
**push target rule** check. The PR publish skills of both providers, and
`github-pr-create` and `github-pr-codex-review-cycle`, run it to resolve the push
remote and to check the upstream before and after the push; its header gives the
usage and exit codes.

[`scripts/check-cleanup-targets.mjs`](scripts/check-cleanup-targets.mjs) is the
shared **remote branch deletion check** and **cleanup target manifest**. The
worktree cleanup skills of both providers run it to decide whether to delete the
remote branch, to build the targets the user confirms or a Caller preview, and
to compare them right before any removal; its header gives the usage and exit
codes.
