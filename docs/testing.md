# Testing

GitHub Actions (`.github/workflows/test.yml`) runs the routine checks on Ubuntu,
macOS, and Windows. The pre-commit hook in `.githooks/` checks that the
committed setup runtime matches its TypeScript sources.

## Routine checks

```bash
npm --prefix setup ci
scripts/check-skills-build.sh
npm --prefix setup test
bats tests
```

When `pwsh` is installed (mise installs `powershell` on Linux, WSL, and macOS),
`tests/powershell.bats` parses every tracked `.ps1` file and runs
`tests/setup_windows.ps1`, skipping the cases that need Windows APIs.

Static checks:

```bash
shellcheck -S warning setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```

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
| `tests\setup_link_copy.ps1` | Link/copy fallback for privilege and copy failures (not in CI yet; some cases fail) |

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
bats tests/bootstrap/bootstrap-e2e.bats
```
