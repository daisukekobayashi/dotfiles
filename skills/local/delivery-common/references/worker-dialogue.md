# Worker Dialogue

Each delivery target's shared understanding and design preflight split the work:
the target's worker reads the task and code and drafts, and the coordinator holds
every dialogue with the user. No subagent asks the user a question. This keeps
code reading out of the coordinator's context and lets several targets be
researched in parallel while questions to the user stay sequential.

## Assign the worker

With delegation, the start skill prepares the target's worktree and baseline,
then dispatches one worker for it, including when the delivery has a single
target. The same worker drafts the shared understanding, drafts the preflight,
and implements, keeping its context. Continue it through the host's mechanism
for messaging an existing agent. When it cannot be continued, such as after a
resume, dispatch a fresh worker for the same worktree with the recorded drafts
and results.

Without delegation, report the limitation and process targets one at a time.
The coordinator runs `shared-understanding` and `design-preflight-with-docs`
itself and asks the user directly, under the same rule for which decisions may
take a default.

## Draft and ask

For each target, in this order:

1. The worker runs `shared-understanding` in draft mode and returns its draft.
2. The coordinator verifies the draft: check the cited sources behind the
   decisions and undecided points it will present, and return gaps such as an
   uncited claim or a one-sided option list to the worker for a revised draft.
   Then run `shared-understanding` steps 2-5 with the user from the draft:
   present the overview, read back the decisions, and settle the undecided
   points one at a time. Relay a follow-up that needs code reading to the same
   worker. Forward a user's skip. Send the result to the worker.
3. Continue only with a status of `confirmed`, `corrected`, or `skipped`; report
   other targets as waiting for the user with their open points.
4. The worker sets the tentative tier under [Risk Tier](risk-tier.md), runs
   `design-preflight-with-docs` in draft mode with the shared understanding
   result in the mode the tier's [Tier procedure](risk-tier.md#tier-procedure)
   selects, and returns its draft with the tier and its ratings.
5. The coordinator verifies the preflight draft the same way. For a Low
   tentative tier, apply Risk Tier's
   [Low check](risk-tier.md#set-and-update-the-tier) before asking, and the
   [Tier procedure](risk-tier.md#tier-procedure)'s Design preflight row when
   Low is confirmed. Then ask the draft's questions under the preflight's
   question budget. When an answer changes a dependent question, have the
   worker revise that question before asking it. Send the settled decisions to
   the worker.
6. The worker writes the preflight's durable documentation and implements on the
   settled decisions.

With several targets, workers draft in parallel. The coordinator holds one
target's dialogue at a time, finishing its open questions before starting the
next target's. A drafted recommendation is not a decision; only the user's
answers settle the points. A worker returns a material question that arises
later, during implementation or review fixes, to the coordinator in the same
way.

## Worker defaults

Workers follow the start skill's worker rules: they choose defaults only for
implementation tactics, return contract, boundary, compatibility, and security
decisions as questions, and list every default they chose. The coordinator asks
those questions like preflight questions and checks the listed defaults for a
decision that should have been a question.
