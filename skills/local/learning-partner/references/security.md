# Security learning guidance

Use the design, code, configuration, incident analysis, or security claim in the
current work. Focus on the property to protect and the conditions under which it
could fail. A tool name or checklist item is not itself a learning objective.

## Make the threat model explicit

Identify the relevant assets, actors, trust boundaries, and security property.
Clarify what an adversary can control or observe, the privileges they start with,
and which assumptions or threats are outside the current analysis.

Trace how input, authority, or sensitive data crosses a boundary. Connect each
control to the condition it is meant to prevent and the place that actually
enforces it. Distinguish intended policy from implemented enforcement, and
prevention from detection or recovery.

## Reason about failure paths

Invite the user to explain how the property could be violated under the stated
assumptions, why a control blocks that path, or what happens if a trusted component
fails. Examine the causal path rather than matching a vulnerability label.

A plausible attack path needs its preconditions and evidence stated. A successful
normal operation does not demonstrate resistance to adversarial behavior, while
one blocked attempt establishes only the tested case. A failed control does not
by itself establish the full impact; trace the authority and resources reachable.

## Check controls within scope

Use relevant code paths, configuration, specifications, and bounded observations.
If testing would clarify the model, use an isolated synthetic case or an explicitly
authorized test environment. A learning request does not authorize probing other
systems or using real credentials and sensitive data as teaching fixtures.

Inspect both the outcome and the boundary that produced it. Scanner results and
passing tests can contribute evidence, but do not establish that all relevant
paths are covered. Report the tested conditions, remaining assumptions, and
uncertainty without declaring the whole system secure.

## Transfer the reasoning

When useful, change an actor's capabilities, a trust assumption, the exposure of
a component, or the required security property. Ask how the failure path and
control requirements change. Include usability and operational constraints when
they affect whether a proposed control will work in practice.
