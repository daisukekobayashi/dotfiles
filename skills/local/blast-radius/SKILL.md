---
name: blast-radius
description: Use only when the user explicitly invokes `blast-radius` to test the assumptions a change's safety depends on, or as the High-tier Local Review step of an explicitly user-requested `github-issue-delivery` or `azure-devops-work-item-delivery` workflow for named issues or Work Items. May create isolated verification artifacts. Never repairs the implementation.
license: MIT
---

# Blast Radius

Run only when the user explicitly invokes `blast-radius`, such as `$blast-radius`
in Codex or `/blast-radius` in Claude Code, or through the user's explicit
request for the full `github-issue-delivery` or `azure-devops-work-item-delivery`
workflow for named issues or Work Items, as its High-tier Local Review step.
A caller must forward that request and exact target under
[Blast radius](../delivery-common/references/local-review.md#blast-radius).
A generic impact question or a reference from another skill does not activate
this workflow.

Identify the one or few facts a change's safety depends on, then test them.
A caller list is a starting point, not the result.

## Delivery invocation

Use the caller's base and pinned head for the committed diff and the trusted
disposable worktree the caller created for probes. Confirm they match the
assignment before running a probe. Use [Repro Runs](../delivery-common/references/repro-runs.md)
for collection, isolation, command limits, and retained evidence. It governs
where temporary files go and what commands can run for delivery. Stop proof
work at the caller's deadline. Keep the reviewed worktree read-only and
return any missing or failed prerequisite to the caller.

Report the coverage below, including premises that were cleared or could not
be tested. Supply concrete findings with their location, severity
(`High`, `Medium`, or `Low`), change tag, failure path, and proof status
under [Review block](../delivery-common/references/report-handoff.md#review-block).
Keep each `BR<n>` finding's repro files under [Evidence](../delivery-common/references/repro-runs.md#evidence).
Use `Findings to assess` when there are findings and `No findings` otherwise.
Return the assigned v3 report under Report Handoff. When the Codex companion
captures the report, return the report as final output under
[Codex route](../delivery-common/references/report-handoff.md#codex-route).

## Establish the claim

1. Resolve the target, baseline, intended behavior, and changes in scope.
   Include changed configuration, schemas, generated interfaces, and
   consumers outside the immediate language or repository when evidenced.
2. State the safety premise precisely: which inputs, versions, ordering, actors,
   and invariants make the change safe? Trace a concrete failure if it is false.
3. Follow what symbol search misses: serialization, persisted data, framework
   dispatch, lifecycle timing, feature flags, retries, and downstream consumers.
   Inspect pinned dependency source when it is material.

Use [how](../how/SKILL.md) and [why](../why/SKILL.md) when mechanism or intent
needs grounding. Do not manufacture distant callers or speculative risks.

## Test the premise

Choose the smallest check that could falsify the safety claim. Prefer an
existing documented check against the actual implementation. Follow repository
execution-context guidance; a script calling a reimplementation proves little.

For a standalone invocation, temporary probes and isolated test data are allowed.
Classify them and place them in an ignored task directory or /tmp. Preserve
production code, existing tests, user data, and unrelated changes. Do not repair
the target, add a permanent test, start a shared service, change dependencies,
or mutate remote state without authorization covering that action.

Inspect the side effects of a proposed command before running it. Prefer local
fixtures and owned runtime instances. A dry-run label is not evidence that
external state is untouched. Stop unsafe probes and report the missing proof.

Use a known counterexample or negative control when practical to establish that
the check can detect the failure. Run against the actual changed code and
capture the command, input identity, result, and relevant output. Do not replace
a failed check with one that merely passes.

Use [principle-prove-it-works](../principle-prove-it-works/SKILL.md) to assess the evidence. Stop
processes you started and retain useful evidence. In delivery the coordinator
owns cleanup of the isolated worktree and the handoff of repro files.

## Report the actual coverage

For each consequential premise, label the strongest evidence obtained:

- asserted only;
- traced to source;
- failure path ruled out under stated assumptions;
- exercised through real code;
- reproduced through the running application.

Return what changed, the safety premises and their scope, confirmed risks,
risks checked and cleared, and unproven assumptions with the cheapest next
check. Attach evidence pointers and runtime limitations. Do not turn a limited
successful probe into a blanket safety or merge verdict.

## Source

Adapted from Lauren Tan's [pstack blast-radius](https://github.com/cursor/plugins/blob/12d587dfb20741cafc376c42c696c5f6e2a64487/pstack/skills/blast-radius/SKILL.md).
Local changes: explicit invocation, isolated experiments, no automatic repairs
or permanent artifacts, and preserved mutation approvals. See [LICENSE](LICENSE).
