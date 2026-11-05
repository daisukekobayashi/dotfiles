---
name: delivery-common
description: Shared local review procedure and risk tier for GitHub issue and Azure DevOps Work Item delivery. Read when a delivery workflow sets a change's risk tier, requires normal, adversarial, and security reviews, selects focused follow-up of a committed implementation, or decides whether local reviews repeat or advance.
---

# Delivery Common

Use [Local Review](references/local-review.md) when a delivery workflow reaches
its local reviews or selects focused follow-up, and apply its
Assess findings defaults to local and hosted findings. Use
[Risk Tier](references/risk-tier.md) to set the tier at preflight and on each
reviewed head, to select the security reviewer, and to recommend human review.
Local Review also sets local review escalation, advancement, and round limits.
The calling workflow owns implementation, assessment decisions, hosted review
policy, publication, and approvals. Return the completed results, review scope,
reviewed snapshot, and tier to that caller.
