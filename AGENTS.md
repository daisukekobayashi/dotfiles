# Agent Instructions

## Verification

```bash
npm --prefix setup ci              # restore dependencies in a fresh worktree
npm --prefix setup test
scripts/check-skills-build.sh
bats tests
bats tests/compose_rules.bats      # one file
```

`bats` needs Bash 4.1 or later, and `tests/setup_suite.bash` stops the run on
older Bash. On macOS, put Homebrew bash ahead of `/bin/bash` 3.2 on `PATH`.

`scripts/check-skills-build.sh` checks the committed setup runtime against its
TypeScript sources: it rebuilds `setup/*.js` in place and fails on a difference
or an untracked runtime file.

`docs/testing.md` covers static, focused, Windows, and opt-in E2E checks.

## Delivery sensitive paths

- exclude `skills/**/*.md` from agent instruction files
- add `skills/local/delivery-common/**`
- add `skills/local/change-*review/**`
- add `skills/local/*-delivery/**`
- add `skills/local/*-worktree-cleanup/**`
- add `skills/local/worktree-runtime-cleanup/**`
- add `skills/local/beads-merge-cleanup/**`
- add `skills/local/github-pr-*/**`
- add `skills/local/azure-devops-pr-*/**`
- add `skills/local/azure-devops-common/**`
- add `skills/local/github-issue-create/**`
- add `skills/local/azure-devops-work-item-create/**`
- add `skills/local/github-issue-start/**`
- add `skills/local/azure-devops-work-item-start/**`
