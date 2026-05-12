# TypeScript Skills Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `setup.sh skills` and `setup.ps1 skills` to one TypeScript-authored Node runtime while preserving current skills behavior.

**Architecture:** `setup/src/skills.ts` owns argument parsing, profile resolution, external install orchestration, local skill linking, metadata writing, and rollback. `setup/skills.js` is the committed runtime output used by Bash and PowerShell wrappers. Tests exercise the Node runtime directly, while existing Bats tests keep Bash wrapper behavior covered.

**Tech Stack:** TypeScript, Node.js standard library, `node --test`, existing Bats setup tests, existing `npx skills add` CLI contract.

---

### Task 1: Lock Runtime Contract With Tests

**Files:**
- Create: `setup/test/skills.test.mjs`

- [ ] Add Node tests that call `node setup/skills.js` directly with temp dotfiles/home/tmp directories.
- [ ] Cover `profile validate`, user-scope install, project-scope install, project profile requirement, and rollback on project install failure.
- [ ] Run `node --test setup/test/skills.test.mjs`; expected RED failure: `setup/skills.js` does not exist or cannot be executed.

### Task 2: Add TypeScript Build Scaffold

**Files:**
- Create: `setup/package.json`
- Create: `setup/tsconfig.json`
- Create: `setup/src/skills.ts`
- Generate: `setup/package-lock.json`
- Generate: `setup/skills.js`

- [ ] Add a minimal `setup/package.json` with `typescript` as a dev dependency, `build` script, and `test` script.
- [ ] Add `setup/tsconfig.json` that compiles `setup/src/skills.ts` to `setup/skills.js` as CommonJS.
- [ ] Add a minimal `setup/src/skills.ts` CLI placeholder.
- [ ] Run `npm --prefix setup install` to create `setup/package-lock.json`.
- [ ] Run `npm --prefix setup run build`.
- [ ] Run `node --test setup/test/skills.test.mjs`; expected GREEN only for the placeholder tests that are already implemented, otherwise continue implementing behavior test by test.

### Task 3: Port Profile Planning and Metadata

**Files:**
- Modify: `setup/src/skills.ts`
- Generate: `setup/skills.js`

- [ ] Implement profile JSON loading, includes expansion, duplicate merging, local skill validation, metadata output, and profile validation output.
- [ ] Run `npm --prefix setup run build`.
- [ ] Run `node --test setup/test/skills.test.mjs`; validation tests should pass.

### Task 4: Port User-Scope Install

**Files:**
- Modify: `setup/src/skills.ts`
- Generate: `setup/skills.js`

- [ ] Implement user default `base` profile and default `codex,claude-code` agents.
- [ ] Install external skills into a temp directory with `npx skills add <source> --copy --yes --agent codex --skill <name>`.
- [ ] Copy generated external skills into the staging user view after each source install.
- [ ] Symlink dotfiles local skills into the staging user view.
- [ ] Write staging metadata and atomically swap it into `.agents/user`.
- [ ] Link `$SETUP_HOME/.agents/skills` and `$SETUP_HOME/.claude/skills` to the dotfiles-managed user view.
- [ ] Keep the previous user view if an external install fails.
- [ ] Run build, Node tests, and `bats tests/setup_skills.bats tests/setup_skills_profiles.bats`.

### Task 5: Port Project-Scope Install

**Files:**
- Modify: `setup/src/skills.ts`
- Generate: `setup/skills.js`

- [ ] Require explicit `--profile` for project scope.
- [ ] Resolve the project root with `git rev-parse --show-toplevel`.
- [ ] Back up `skills-lock.json`, `.agents/skills-profile.json`, and selected agent skill directories before install.
- [ ] Run external installs from the project root with all selected agents.
- [ ] Symlink local skills into selected agent project skill directories.
- [ ] Write `.agents/skills-profile.json`.
- [ ] Roll back backups and remove partial generated outputs if install fails.
- [ ] Run build, Node tests, and existing Bats skills tests.

### Task 6: Switch Wrappers and Documentation

**Files:**
- Modify: `setup/main.sh`
- Modify: `setup/skills.sh`
- Modify: `setup/skills.ps1`
- Modify: `setup.ps1`
- Modify: `README.md`
- Modify: `README.ja.md`
- Modify: `docs/skills-profiles.md`
- Modify: `docs/skills-profiles.ja.md`

- [ ] Route `setup.sh skills ...` to `node setup/skills.js ...`.
- [ ] Route `setup.ps1 skills ...` to `node setup/skills.js ...`.
- [ ] Update usage text to remove PowerShell unsupported wording.
- [ ] Update docs to describe TypeScript-authored Node core with Bash and PowerShell wrappers.
- [ ] Run build, Node tests, Bats skills tests, `bash -n`, and relevant static checks.

### Task 7: Final Verification

**Files:**
- Review all modified files.

- [ ] Run `npm --prefix setup run build`.
- [ ] Run `npm --prefix setup test`.
- [ ] Run `bats tests/setup_skills.bats tests/setup_skills_profiles.bats tests/setup.bats`.
- [ ] Run `bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash`.
- [ ] Run `shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats` if shellcheck is available.
- [ ] Run `git status --short` and report modified files, including any pre-existing dirty files that were left untouched.
