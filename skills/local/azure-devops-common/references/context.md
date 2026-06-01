# Azure DevOps Context

Use this reference before any Azure DevOps workflow action.

## CLI Baseline

- Use Azure CLI with the `azure-devops` extension.
- Check authentication and extension availability before Azure DevOps commands:
  - `az account show`
  - `az extension show --name azure-devops`
  - `az devops configure --list`
- If the Azure DevOps extension, authentication, organization, or project is
  unavailable, stop and report the blocker.
- Do not install extensions, sign in, or change defaults unless the user
  explicitly approves.

## Repository Resolution

Resolve the Azure DevOps target from local git context before mutating anything.

Accepted remote URL shapes:

- `https://dev.azure.com/{org}/{project}/_git/{repo}`
- `https://{org}@dev.azure.com/{org}/{project}/_git/{repo}`
- `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`
- `ssh.dev.azure.com:v3/{org}/{project}/{repo}`

Resolution rules:

- Prefer the current branch upstream remote when multiple remotes exist.
- Compare git remote context with `az devops configure --list` defaults.
- Stop if organization, project, or repository cannot be resolved to one target.
- Stop if git remote context conflicts with `az devops` defaults.
- Do not run `az devops configure --defaults ...` without explicit approval.
- Before mutating actions, show organization, project, repository, branch, and
  target Work Item or pull request.

## Mutating Actions

- Preview Work Item or pull request content before creating it.
- Require explicit confirmation before creating or updating Work Items.
- Require explicit confirmation before destructive local cleanup.
- Never delete remote branches unless the user explicitly asks.
- Never force push, reset, rebase, amend, merge, complete a PR, set auto-complete,
  vote, approve, or resolve threads unless a workflow skill explicitly allows it
  and the user explicitly asks.
- Do not stage secrets, credentials, private keys, `.env` files, or local-only
  config.
- Do not stage dependency manifests or lockfiles without explicit approval.

## Work Items

- Use Azure DevOps terminology: Work Item, not issue.
- Work Item type is project/process-specific. Do not hardcode `Issue`.
- Use repository docs or project data to choose a type. If unclear, ask before
  creating.
- Required creation fields are title, type, and description.
- Optional fields include area, iteration, assigned-to, tags, and `--fields`.
- Do not infer custom fields. Use them only when repository docs or the user
  specify exact field names and values.
- Prefer body text for dependency notes. Add Work Item relations only when
  existing Work Item IDs and relation intent are unambiguous.

## Work Item Links And State Transitions

- For Azure Repos PRs, prefer Azure DevOps Work Item links over GitHub-style
  prose. Use `az repos pr create --work-items` when creating a PR if the Work
  Item ID is known and the CLI supports it; otherwise add the link after PR
  creation with `az repos pr work-item add`.
- Use state-transition keywords in the PR description, such as `Fixes #123`,
  `Closes #123`, or `Resolves #123`, only when the user explicitly wants the
  Work Item to transition on PR completion or merge and the PR fully completes
  that Work Item.
- For parent Work Items, epics, features, trackers, partial work, follow-ups, or
  context-only references, do not use transition keywords. Use a neutral note
  such as `Refs #123`, or link the Work Item without a transition keyword.
- Do not transition parent tracker Work Items unless this PR completes the whole
  tracker.
- When multiple Work Items should transition, repeat the transition keyword for
  each Work Item. Do not write one keyword followed by several IDs if all should
  transition.
- For GitHub repositories connected to Azure Boards, use `AB#123` references.
  Use `Fixes AB#123` or a similar transition keyword only when the Work Item
  should transition; use plain `AB#123` or `Refs AB#123` for non-closing links.

## Pull Requests

- Use `az repos pr` where possible.
- Use read-only REST API fallback only when Azure CLI cannot expose required PR,
  thread, policy, reviewer, or build information.
- Do not checkout PR branches for review.
- If thread state, policy state, reviewer state, build validation, or linked
  Work Items cannot be verified, say so explicitly.

## Useful Command Families

- `az devops`
- `az boards work-item`
- `az boards query`
- `az repos pr`
- `az repos pr policy`
- `az repos pr reviewer`
- `az repos pr work-item`
