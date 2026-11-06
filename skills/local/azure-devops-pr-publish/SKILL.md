---
name: azure-devops-pr-publish
description: Use only when the user explicitly requests azure-devops-pr-publish, or its publication phase through azure-devops-work-item-delivery, for specified local Azure DevOps branches or worktrees. Publish as a PR without requesting AI review.
---

# Azure DevOps PR Publish

## Scope

Use this orchestration skill to publish one or more local branches or worktrees
as Azure DevOps pull requests. It covers the normal path from local changes to a
remote PR: inspect state, verify, commit when needed, push, and create or reuse
the PR.

Read `../azure-devops-common/references/context.md` before resolving targets.

## Approval Model

An explicit publication request can arrive directly or through
`azure-devops-work-item-delivery`. A delegated caller must forward the actual
user request, exact target, and existing authorizations; a skill reference or
automatic selection is insufficient. Subject to governing approval instructions,
treat that request as approval for ordinary non-destructive commits and normal
pushes for the requested target branches. Prepare the verified publication target
before asking for any missing approval.

Still stop and ask before:

- force push, branch deletion, reset, rebase, amend, or merge
- staging secret-like files, credentials, private keys, or local-only config
- staging unrelated files
- staging or publishing dependency manifests or lockfiles without explicit
  approval
- publishing from the default branch
- completing PRs, enabling auto-complete, changing policies, voting, approving,
  or requesting reviewers

## Workflow

1. Resolve targets from the user request. If none is specified, use the current
   worktree and branch.
2. Resolve Azure DevOps organization, project, repository, default branch, and
   current branch for each target.
   - Stop and report the branch unless it is a **safe branch name** before
     running any command with it: run `node <script> -- '<branch>'`, where
     `<script>` is
     [`check-branch-name.mjs`](../delivery-common/scripts/check-branch-name.mjs)
     resolved from this skill's directory, and continue only on exit 0. Write a
     name into this or any command only when it uses solely ASCII letters,
     digits, `/`, `.`, `_`, and `-`; any other name is not safe, without running
     the check. The check also refuses a leading `+`, which would make the push
     refspec a force push.
   - Stop and report the default branch, and a target the user specifies,
     unless each is a **safe branch name** before running any command with
     it: run `node <script> -- '<default branch>'`, adding `'<target>'` when
     the user specifies one, with the script above, and continue only on
     exit 0. Write a name into this or any command only when it uses solely
     ASCII letters, digits, `/`, `.`, `_`, and `-`; any other name is not
     safe, without running the check.
   - Resolve the push remote. Use the remote the user names. Otherwise
     `<remote>` is the one remote whose fetch URL and every push URL
     (`git remote -v`) name the resolved organization, project, and repository
     in one of the accepted remote URL shapes from the common context, after
     decoding percent-encoding (`My%20Project` is `My Project`) and ignoring
     letter case, the `user@` part, and a trailing `.git` or `/`. Stop and
     report the candidates when more than one remote matches. When none
     matches, as with an SSH host alias, stop and ask the user to name the
     remote.
3. Inspect local state:
   - `git status --short --branch`
   - `git diff --stat`
   - `git diff --check`
   - `git log --oneline <default-branch>..HEAD` when available
4. Stop if there is no publishable work.
5. Confirm recent verification.
   - Use a successful verification log from the current conversation only if it
     happened after the latest changes.
   - Otherwise determine and run the repository's required verification command.
   - Stop if verification fails.
   - Before pushing, inspect any matching active PR for enabled auto-complete.
     If enabled, hold publication for an explicit decision: a push could merge
     the PR before separate merge approval. Do not silently disable it.
6. Commit when needed.
   - Use the `git-commit` skill.
   - Stage only files belonging to the requested work.
7. Push the branch.
   - `<remote>` is the push remote resolved in step 2. The PR base branch
     is the existing PR's target, otherwise the target
     `azure-devops-pr-create` uses: the default branch unless the user
     specifies another target.
   - Read the upstream with `git config --get-all branch.<branch>.remote` and
     `git config --get-all branch.<branch>.merge`; no output means no upstream,
     and more than one value for either key means stop and report.
   - Continue when there is no upstream, the same branch name on `<remote>`, or
     the PR base branch, either local (remote `.`) or remote-tracking. Stop and
     report any other upstream, such as a differently named branch or another
     remote; it may back an existing PR.
   - Push with `git push -u <remote> <branch>:refs/heads/<branch>`. The
     explicit refspec keeps a base upstream or `push.default=upstream` from
     sending the branch to the base. This sets the upstream for the same branch
     name; report it when it replaced the PR base branch.
   - Re-read the upstream; stop and report unless the remote is `<remote>`
     and the merge ref is `refs/heads/<branch>`.
8. Use `azure-devops-pr-create` to create or resolve the PR.
   - Pass along the actual publication request, exact target, existing approvals,
     known Work Item IDs, completion scope, and the user's state-transition intent.
9. Verify with `az repos pr show` and report branch, commit, push target, PR URL,
   and verification result.

## Guardrails

- Do not continue to later targets after a verification, commit, push, or PR
  creation failure.
- Do not create PRs from the default branch.
- Do not force push, rewrite history, merge, complete, or clean up worktrees.
- Do not hardcode or print secrets while summarizing diffs, commits, or templates.
