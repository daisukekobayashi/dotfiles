# Merge and Work Item State

Read this reference when checking publication evidence, preparing a merge, or
verifying completion. Use the installed CLI's supported arguments and explicit
resolved organization/project/repository values where supported. Verify returned
identities; PR IDs alone are not sufficient target context.

## Check the current implementation and policies

Use `az repos pr show` to confirm repository, `sourceRefName`, `targetRefName`,
draft/completion state, and any existing auto-complete setting. Read the current
source ref with `az repos ref list`; its filter matches prefixes, so require the
exact ref name and compare `objectId` with the reviewed/published HEAD.
`lastMergeSourceCommit` describes a merge calculation and can lag the live ref.
Recheck after another push or before reusing prior evidence.

Use `az repos pr policy list --id <id>` for required policy evaluations, and
`az repos pr reviewer list --id <id>` for required human approvals. Honor the
repository's required CI/status checks and comment-resolution policy. Obtain
discussion threads through read-only REST when CLI cannot expose them. Report
inaccessible evidence and hold the merge when required evidence is missing.
An empty policy list does not excuse a failed inspection. Policy re-evaluation,
reviewer requests, votes, and thread resolution are mutations requiring their
own authorization; they are not part of an inspection.

Sources: [PR CLI](https://learn.microsoft.com/en-us/cli/azure/repos/pr?view=azure-cli-latest),
[Refs CLI](https://learn.microsoft.com/en-us/cli/azure/repos/ref?view=azure-cli-latest),
[Branch policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops).

## Complete only the approved PR

After target-specific approval, use `az repos pr update --id <id> --status completed`
with the supported approved merge method, `--delete-source-branch false`, and
the approved `--transition-work-items` value. Default that value to `false` when
no transitions were requested. Keep policy bypass and auto-complete out of the
ordinary completion path. If the repository's merge method is unsupported by
the available CLI, report the limitation and wait for supported/manual completion.

Re-read the source immediately before completion and reassess if it changed.
The CLI has no caller-supplied expected-source-SHA argument: this recheck detects
observed changes, not an atomic guarantee against concurrent pushes. When
another writer is active or strict SHA-conditional completion is required,
leave the merge pending for a supported method or user action. Do not claim
that a separate read and completion command guarantee the approved HEAD.

Verify `status=completed`, the actual merged source SHA, and the merge commit
afterwards. `mergeStatus=succeeded` alone can describe an active PR's test merge;
auto-complete and a queued completion request are not completed merges. A
different merged source invalidates the recorded review coverage and must be
reported before cleanup.

Sources: [Complete PRs](https://learn.microsoft.com/en-us/azure/devops/repos/git/complete-pull-requests?view=azure-devops),
[PR response and active-PR examples](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests?view=azure-devops-rest-7.1),
[CLI completion implementation](https://github.com/Azure/azure-devops-cli-extension/blob/master/azure-devops/azext_devops/dev/repos/pull_request.py).

## Verify the Work Item independently

Use structured PR links under the common context rules. Linking a Work Item is
separate from asking to change its state. A full delivery request alone does not
authorize changing Work Item fields or adding closing keywords.

`--transition-work-items true` applies to linked Work Items, not just the one
currently being delivered. Inspect the full linked set before proposing it;
do not include a parent tracker or unrelated item in a bulk transition. If only
some links should transition, leave the bulk option off and obtain approval for
the exact item-specific transitions instead.

Determine the intended completion state/category from the Work Item type and
project process. Do not hardcode `Closed` or assume `Resolved` is completed.
The CLI option attempts the next logical state, and workflow rules can prevent
the transition. Even the completion checkbox does not move an already Resolved
Agile Bug to Closed in the documented case.

After merge, read each requested Work Item with `az boards work-item show` and
report the actual state. If it remains unfinished, report
`Merged; Work Item completion pending`; propose the exact remaining transition
and required fields for approval rather than repeatedly attempting updates or
silently changing the process. Keep any intended uncompleted Work Item explicit
instead of declaring the full delivery complete.

Sources: [Automatic Work Item completion](https://learn.microsoft.com/en-us/azure/devops/boards/work-items/auto-complete-work-items-pull-requests?view=azure-devops),
[Workflow state categories](https://learn.microsoft.com/en-us/azure/devops/boards/work-items/workflow-and-state-categories?view=azure-devops).
