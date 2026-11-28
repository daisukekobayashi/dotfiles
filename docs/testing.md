# Testing

GitHub Actions (`.github/workflows/test.yml`) runs the routine checks on Ubuntu,
macOS, and Windows. The pre-commit hook in `.githooks/` checks that the
committed setup runtime matches its TypeScript sources and scans staged changes.

## Sensitive changes

The hook and the **Sensitive changes** workflow use Betterleaks 1.10.1 for
secret detection. CI runs the checksum-verified official binary. The local
hook uses Node.js 24 and the `dotfiles-betterleaks-staged` adapter on `PATH`.
The adapter receives the Git-relative path and raw blob through stdin and
passes both to the pinned detector. Its output contains only the rule and line.
The hook stops when the adapter is missing, reports an incompatible protocol or
engine version, fails, or finds a match.

### Build the local adapter

Set up Go 1.27.4 from the existing mise pin or the matching
[official Go distribution](https://go.dev/dl/). Build the adapter once and
rebuild it after updating its source or dependencies. Choose an owner-managed
directory already on your `PATH`. For example, if `~/.local/bin` is set up:

```sh
cd tools/betterleaks-staged
GOENV=off GOWORK=off GOTOOLCHAIN=local CGO_ENABLED=0 \
  GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org \
  go build -mod=readonly -trimpath -buildvcs=false -o "$HOME/.local/bin/dotfiles-betterleaks-staged" .
dotfiles-betterleaks-staged --version
```

On native Windows, set the same environment values in your build shell and give
`go build -o` an absolute path ending in `dotfiles-betterleaks-staged.exe` in
your chosen directory. The expected version output is
`dotfiles-betterleaks-staged protocol 1 engine v1.10.1`. Dependency resolution
happens during this explicit build. The hook does not build, download, or install
a scanner. To run the staged check alone, return to the checkout root and run
`node scripts/check-sensitive-changes.mjs staged`.

Git supplies new and changed file contents directly from its index or object
database. The checkout, unstaged changes and candidate scanner configuration
cannot change those inputs. CI scans branch pushes and pull requests. It checks
each selected commit, including intermediate commits and merge changes compared
with the first parent. It uses the push before/after or PR base/head SHA. A
first branch push has no before SHA, so CI scans the commits that the fetched
default branch does not contain, and treats commits reachable from that branch
as already scanned. It first checks that the remote's default branch is still
the one the event names. A first push of the default branch itself, a remote
default branch that differs or cannot be read, or a checkout without the
fetched default branch has no such base and is reported as incomplete.
If a required object or range cannot be verified, CI reports the scan as
incomplete. Commit messages, tags, old history sweeps and the contents of other
repositories linked as submodules are outside this check. Review changes to
the workflow or scanner itself under the repository review policy.

### Private denylist

Keep the real values outside Git. To enable the local check, set
`DOTFILES_SCAN_DENYLIST_FILE` to the absolute path of an owner-managed regular
file outside all repository worktrees and in a directory other users cannot
modify. Use a single-link file with mode `0600` on POSIX, or a Windows ACL
granting access only to your account, SYSTEM and Administrators. Use a nonempty JSON array of UTF-8 literal
`category` and `value` pairs. Categories are `identifier`, `organization`,
`hostname` and `path`. This example contains a synthetic value:

```json
[{"category":"hostname","value":"internal.example.test"}]
```

An unset denylist skips only the personal-information check. Invalid or
unreadable configured input makes the scan incomplete. The denylist is used
only by the local staged check. GitHub Actions scans for secrets on pushes and
pull requests with no private denylist input.

Both scanners use the pinned version's rules, per-match filters, and file-type
limits. They disable the default file-path prefilter. Findings report the commit
or staged change, rule, and line number. Filenames are masked because a value
detected in file contents may also appear in the path. Inspect the indicated
commit or staged changes locally to locate the finding.

For synthetic parity tests, put the local adapter and the checksum-verified
[official Betterleaks 1.10.1 binary](https://github.com/betterleaks/betterleaks/releases/tag/v1.10.1)
on the test process's `PATH` and run:

```sh
DOTFILES_TEST_REAL_BETTERLEAKS=1 DOTFILES_TEST_REAL_STAGED_SCANNER=1 \
  node --test setup/test/sensitive-changes.test.mjs
```

### Known false positives

To approve a known benign match, add an entry to
`scripts/sensitive-scan-allowlist.json` through normal review. Each entry
specifies the exact repository-relative `path`, `rule` (such as
`secret:github-pat`), `line` (0 for a filename match), `contentSha256` for the
selected file bytes, and a `reason`. Keep private values out of this file.
The existing reviewed default-branch copy controls the scan. For a push to
the default branch, the before commit supplies the policy. A first push of a
different branch uses its verified comparison base. For other branch pushes
and pull requests, CI reads the exact `refs/remotes/origin/<default>` ref and
returns incomplete (exit 2) when Git cannot verify it points to a commit.
A change to the allowlist cannot exempt the same candidate change by itself.

The staged check reads the exact `refs/remotes/origin/main` ref. If Git
confirms that ref is absent, the check runs with no allowlist exceptions.
If the ref cannot be read or does not point to a commit, the check returns
incomplete. A valid ref works on older Git. Git 2.43 or later can confirm
absence with `git show-ref --exists`; without that option, a failed exact
lookup returns incomplete.

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
