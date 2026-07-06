# Bootstrap E2E

Bootstrap E2E checks are manual, opt-in checks for the clean-container
bootstrap path. They are intentionally separate from routine `bats tests`,
pre-commit, and CI because `--suite all` performs real network downloads and
long-running build steps.

The formal entrypoint is:

```bash
scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite dry-run
```

The script streams tracked repository files into a disposable container. It does
not bind-mount the host checkout and should not edit host files.

## Suites

`dry-run` is the default and runs `./setup.sh all` with `SETUP_DRY_RUN=1`.
Use it for a quick harness smoke check.

```bash
scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite dry-run
scripts/bootstrap-e2e.sh --image ubuntu:24.04 --suite dry-run
```

`all` runs the real bootstrap path. Use it only when intentionally validating a
fresh setup.

```bash
scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite all
scripts/bootstrap-e2e.sh --image ubuntu:24.04 --suite all
```

`--suite all` mirrors normal non-strict bootstrap behavior. A setup step can
warn or fail internally while the process still exits 0. Read the final
warning/error summary.

## GitHub Auth

The default `--github-auth auto` forwards a host `GITHUB_TOKEN` if set. If no
environment token is set, it tries `gh auth token`. GitHub CLI config is not
mounted into the container.

```bash
scripts/bootstrap-e2e.sh --github-auth auto --suite all
scripts/bootstrap-e2e.sh --github-auth gh --suite all
scripts/bootstrap-e2e.sh --github-auth none --suite all
```

Use `--github-auth gh` when a valid host GitHub CLI login is required for
GitHub/aqua-backed mise tools. Use `--github-auth none` to reproduce
unauthenticated GitHub API behavior.

The harness passes the token as container environment, preserves it through
`sudo`, disables interactive Git prompting with `GIT_TERMINAL_PROMPT=0`, and
sets `GIT_ASKPASS=/bin/false`.

## Bats Wrapper

`tests/bootstrap/bootstrap-e2e.bats` exists for discoverability and skips unless
explicitly enabled.

```bash
bats tests/bootstrap/bootstrap-e2e.bats
BOOTSTRAP_E2E=1 BOOTSTRAP_E2E_IMAGE=debian:bookworm-slim BOOTSTRAP_E2E_SUITE=dry-run bats tests/bootstrap/bootstrap-e2e.bats
BOOTSTRAP_E2E=1 BOOTSTRAP_E2E_IMAGE=ubuntu:24.04 BOOTSTRAP_E2E_SUITE=all bats tests/bootstrap/bootstrap-e2e.bats
```

Set `BOOTSTRAP_E2E_GITHUB_AUTH=gh` or `none` to override the default `auto`
credential mode.

## Container Prerequisites

Before running `./setup.sh all`, the harness installs a focused prerequisite
set:

- compiler and build tools
- `libevent` for building `tmux`
- Lua and Lua headers for `luarocks`
- zlib, OpenSSL, curses, readline, sqlite, bz2, lzma, ffi, YAML, XML, XMLSec,
  and Tk headers for mise-built runtimes
- `libclang-dev` for Rust tools that use bindgen
- Java, ODBC, wxWidgets, WebKitGTK, OpenGL, and GLU dependencies for Erlang
  optional apps
- `vim-nox` for `PlugInstall`
- `pipx` for pipx-backed mise tools

The harness sets `LANG=C.UTF-8` and `LC_ALL=C.UTF-8`.

This prerequisite set is intentionally narrower than a full workstation setup.
It does not run `apt upgrade`, and it does not preinstall broad interactive
tools such as Docker, Neovim, jq, rsync, or ctags unless they are needed before
the bootstrap under test starts.

## Known Diagnostics

The script prints a warning/error summary after streaming the full setup output.
The summary includes `[WARN]`, `[ERROR]`, Vim-style `E123:` diagnostics,
`warning:`, `error:`, `failed`, and `failure`.

Known non-fatal diagnostics include:

- Debian or Ubuntu `update-alternatives` warnings for missing manpage files.
- Erlang `wxWebView` optional app warning in minimal containers.
- Cargo-installed mise tools warning that their install bin directory should be
  added to `PATH`.
- Upstream Cargo lock warnings, such as `tokei` depending on a yanked crate.
- `PlugInstall failed. Continuing setup.` when Vim plugin installation reports
  an error after the rest of bootstrap can continue.

GitHub/aqua-backed mise tools may fail under unauthenticated GitHub API rate
limits. Prefer `--github-auth auto` or `--github-auth gh` when the host has a
valid GitHub CLI login.
