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
to set the tier at preflight and on each reviewed head, to select the security
reviewer, and to recommend human review. Local Review also sets local review
escalation, advancement, and round limits. Use
[Delivery Completion](references/completion.md) for the progress record, the
tier shown before publication, the merge confirmation, bounds, the final report
and `Complete` rule, and follow-up candidates.

The calling workflow owns implementation, assessment decisions, hosted review
policy, publication, and approvals. Where shared text names the calling
workflow's additions, the calling workflow lists its provider-specific items
next to its link. Return the completed results, review scope, reviewed
snapshot, and tier to that caller.
