# feat(skills): route a delivery back to discovery when an issue's goal is unsettled

## Summary
When a delivery target's goal is still unsettled, stop that target and point the user to discovery before resuming.

## Background
`shared-understanding` says framing an unsettled problem belongs to `find-unknowns`, but `github-issue-delivery` and the `delivery-common` references do not mention it. `worker-dialogue.md` reports a target as waiting for the user without naming a next step. Related: #51, #56.

## Acceptance Criteria
- [ ] `shared-understanding` defines when the goal counts as unsettled, such as when the one-sentence overview cannot be confirmed after correction, and ends with `unresolved`.
- [ ] The report recommends `find-unknowns` or `grilling`, updating the issue, and then resuming the delivery.
- [ ] A target with a settled goal gets no extra question or step.
- [ ] GitHub and Azure DevOps deliveries share the behavior.
- [ ] Wiring tests cover the route.

## Implementation Notes
Do not add a brainstorming phase to delivery. Discovery stays outside the workflow; this adds only the way back.

## Touched Areas
- `skills/local/shared-understanding/SKILL.md` (estimate)
- `skills/local/delivery-common/references/worker-dialogue.md` (estimate)
- `setup/test/skills-wiring-delivery.test.mjs` (estimate)

## Dependencies
None.

## Parallelization
Shares the wiring test with the change-review issue, so run it after that issue.

