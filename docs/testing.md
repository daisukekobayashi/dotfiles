# Testing

GitHub Actions (`.github/workflows/test.yml`) runs the routine checks on Ubuntu,
macOS, and Windows. The pre-commit hook in `.githooks/` checks that the
committed setup runtime matches its TypeScript sources and scans staged changes.

## Sensitive changes

The hook and the **Sensitive changes** workflow use Betterleaks 1.10.1 for
secret detection. Have Node.js 24 and that Betterleaks version on `PATH` before
committing. Linux and WSL select it in mise. For macOS and Windows, use the
matching [official release asset](https://github.com/betterleaks/betterleaks/releases/tag/v1.10.1)
and check its SHA-256 before installing. The hook stops if the scanner is
missing, reports a different version, fails, or finds a match. Run the staged
check alone with `node scripts/check-sensitive-changes.mjs staged` from the checkout.

Git supplies new and changed file contents directly from its index or object
database. The checkout, unstaged changes and candidate scanner configuration
cannot change those inputs. CI scans branch pushes and pull requests. It checks
each selected commit, including intermediate commits and merge changes compared
with the first parent. It uses the push before/after or PR base/head SHA, and
requires an exact comparison base from the event for a first branch push. When
GitHub does not supply one, open a PR to run the check with its base and head.
If a required object or range cannot be verified, CI reports the scan as
incomplete. Commit messages, tags, old history sweeps and the contents of other
repositories linked as submodules are outside this check. Review changes to
the workflow or scanner itself under the repository review policy.

### Private denylist

Keep the real values outside Git. To enable the local check, set
`DOTFILES_SCAN_DENYLIST_FILE` to the absolute path of an owner-managed regular
file outside all repository worktrees. Use a single-link file with mode
`0600` on POSIX, or a Windows ACL granting access only to your account,
SYSTEM and Administrators. Use a nonempty JSON array of UTF-8 literal
`category` and `value` pairs. Categories are `identifier`, `organization`,
`hostname` and `path`. This example contains a synthetic value:

```json
[{"category":"hostname","value":"internal.example.test"}]
```

An unset denylist skips only the personal-information check. Invalid or
unreadable configured input makes the scan incomplete. Findings identify the
rule and location. Paths that match a rule are redacted as well.

The private CI job is optional. Before supplying values, restrict the
`dotfiles-private-scan` GitHub Environment to the trusted default branch,
confirm only trusted changes can reach that branch and its workflow, and
store the JSON in the environment secret `DOTFILES_SCAN_PRIVATE_DENYLIST`.
Set the repository variable `DOTFILES_PRIVATE_SCAN_ENABLED` to `true` after
those controls are in place. The job uses the workflow's exact default-branch
push commit. Ordinary PRs and other branch pushes run the secret scan with
no private input. The private job reports the commit, rule and line with
every filename masked. Use the reported commit to correlate these results
with detailed diagnostics from the local check. The workflow keeps raw
findings out of logs and artifacts.

### Known false positives

To approve a known benign match, add an entry to
`scripts/sensitive-scan-allowlist.json` through normal review. Each entry
specifies the exact repository-relative `path`, `rule` (such as
`secret:github-pat`), `line` (0 for a filename match), `contentSha256` for the
selected file bytes, and a `reason`. Keep private values out of this file.
The existing reviewed default-branch copy controls the scan. For a push to
the default branch, the before commit supplies the policy. A change to the
allowlist cannot exempt the same candidate change by itself.

## Routine checks

```bash
npm --prefix setup ci
scripts/check-skills-build.sh
npm --prefix setup test
bats tests
```

`bats tests` runs the full suite on Linux and macOS, and CI runs it on both.
It needs Bash 4.1 or later: older Bash does not fail a test on a non-final
`[[ ]]` assertion, so `tests/setup_suite.bash` stops the run early instead. On
macOS, install Homebrew bash (`brew install bash`) and put it ahead of the
system `/bin/bash` 3.2 on `PATH`.

CI runs bats with `--timing` and a JUnit report, and the job summary of each
Linux and macOS job lists the 10 slowest tests. To time tests locally:

```bash
bats --timing tests/list_processes.bats
```

When `pwsh` is installed (mise installs `powershell` on Linux, WSL, and macOS),
`tests/powershell.bats` parses every tracked `.ps1` file and runs
`tests/setup_windows.ps1`, skipping the cases that need Windows APIs.

Static checks:

```bash
shellcheck -S warning setup.sh lib/common.sh setup/*.sh scripts/delivery-context.sh tests/setup_suite.bash tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/setup_suite.bash tests/helpers/*.bash
```

## Where to add setup tests

`npm --prefix setup test` runs `setup/test/*.test.mjs` without recursing, so
keep test files flat in `setup/test/`. Skills tests are split by concern; add a
new test to the file for its concern instead of a catch-all file:

| File | Concern |
| --- | --- |
| `skills-wiring-profiles.test.mjs` | Repository profile contents and references between skills copied from a profile |
| `skills-wiring-delivery.test.mjs` | Delivery workflow, design preflight, understanding check, change review, and risk tier skill content |
| `skills-wiring-issue-start.test.mjs` | Issue start, worktree branch, and first-push upstream skill content |
| `skills-wiring-pr.test.mjs` | PR review and Codex review cycle skill content |
| `skills-runtime.test.mjs` | `setup/skills.js` profile validation, user and project scope installs, dry run, and rollback |
| `skills-runtime-claude-env.test.mjs` | `setup/skills.js` refresh of skills in Claude environments |
| `skills-runtime-windows.test.mjs` | `setup/skills.js` Windows command resolution |

Shared fixtures and runners (`createFixture`, `runSkills*`, `readRepoProfile`)
live in `setup/test/skills-helpers.mjs`, which the test glob does not run.
When a new skill family outgrows these files, add a new
`skills-wiring-<family>.test.mjs` file.

## Focused checks

Claude setup and picker checks use temporary homes and fake Claude executables;
they do not log in or call the API:

```bash
node --test setup/test/claude.test.mjs
bats tests/claude_pick.bats tests/claude_wrapper.bats
```

Vim checks use temporary homes and do not download dependencies. The
installed-plugin checks skip when the managed plugins are absent; set
`VIM_PLUGIN_RUNTIME` to a separately installed `dotfiles/` runtime to test it.

```bash
bats tests/vim_config.bats tests/vim_plugins.bats
```

## Windows

Run these in PowerShell 5.1 or later with Node.js installed. UAC is mocked so
tests never prompt for elevation.

| Script | Checks |
| --- | --- |
| `tests\setup_windows.ps1` | Setup entry points |
| `tests\claude_pick.ps1` | Claude environment setup, argument forwarding, and process behavior (compiles a small native fixture) |
| `tests\setup_link_copy.ps1` | Link/copy fallback for privilege and copy failures |

## Opt-in E2E checks

### Neovim DAP

These start real debug adapters and Docker services, so they run only with
`DAP_E2E=1`:

```bash
DAP_E2E=1 bats tests/dap/e2e.bats tests/dap/e2e/*.bats
DAP_E2E=1 bats tests/dap/e2e/python.bats
DAP_E2E=1 bats --filter 'direct docker container' tests/dap/e2e/*.bats
```

They verify breakpoint stops for Elixir, Python, Node, and Rust across local,
direct Docker, and Docker Compose targets. Docker checks require Docker Compose
v2 and build pinned fixture images on first run; Node and Rust use host
networking, and Rust also grants `SYS_PTRACE` with `seccomp=unconfined`.

Local checks use host-installed adapters and skip with a reason when one is
missing: Elixir needs `elixir-ls-debugger`, Python needs `debugpy-adapter`
(Mason's `debugpy`), Node needs `js-debug-adapter`, and Rust needs `cargo` plus
`codelldb`. Set `DAP_E2E_KEEP=1` to keep per-test logs.

### Bootstrap

These start fresh Docker containers and may download packages. See
`tests/bootstrap/README.md` for suites and credential forwarding.

```bash
scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite dry-run
scripts/bootstrap-e2e.sh --suite all --strict --runs 2
bats tests/bootstrap/bootstrap-e2e.bats
```
