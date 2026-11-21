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

Only files that grant, limit, or gate agent authority (approval for commit,
push, merge, cleanup, or remote writes; read-only limits; code execution;
permission, allowlist, or hook rules; the tier and security review selection)
and setup code that installs agent configuration or fetches or executes remote
content stay sensitive. A new authority rule in a file that an `exclude` entry
matches and no `add` entry matches is a `REVIEW.md` failure.

- exclude `skills/**/*.md` from agent instruction files
- exclude `skills/**/evals/**` from agent instruction files
- exclude `skills/**/LICENSE` from agent instruction files
- exclude `setup/test/**` from install, setup, and bootstrap scripts
- exclude `setup/skills-export.js` from install, setup, and bootstrap scripts
- exclude `setup/src/skills-export.ts` from install, setup, and bootstrap scripts
- exclude `setup/tsconfig.json` from install, setup, and bootstrap scripts
- add `skills/local/delivery-common/SKILL.md`
- add `skills/local/delivery-common/references/completion.md`
- add `skills/local/delivery-common/references/local-review.md`
- add `skills/local/delivery-common/references/phase-delegation.md`
- add `skills/local/delivery-common/references/report-handoff.md`
- add `skills/local/delivery-common/references/repro-runs.md`
- add `skills/local/delivery-common/references/risk-tier.md`
- add `skills/local/change-review/SKILL.md`
- add `skills/local/change-adversarial-review/SKILL.md`
- add `skills/local/change-security-review/SKILL.md`
- add `skills/local/*-delivery/SKILL.md`
- add `skills/local/azure-devops-work-item-delivery/references/merge-and-state.md`
- add `skills/local/*-worktree-cleanup/SKILL.md`
- add `skills/local/worktree-runtime-cleanup/SKILL.md`
- add `skills/local/beads-merge-cleanup/SKILL.md`
- add `skills/local/github-pr-*/SKILL.md`
- add `skills/local/github-pr-review-request/references/*.md`
- add `skills/local/azure-devops-pr-*/SKILL.md`
- add `skills/local/azure-devops-common/references/context.md`
- add `skills/local/github-issue-create/SKILL.md`
- add `skills/local/azure-devops-work-item-create/SKILL.md`
- add `skills/local/github-issue-start/SKILL.md`
- add `skills/local/azure-devops-work-item-start/SKILL.md`
