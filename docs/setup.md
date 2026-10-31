# Setup

This document covers setup options, platform behavior, and the Codex and Claude
settings copies. See the [README](../README.md) for the quick start and
`./setup.sh help` for the full argument list.

## Phases and steps

`all` runs the phases in order; each later phase depends on the earlier ones.

| Phase | Steps |
| --- | --- |
| `links` | `links` (config links and generated files) |
| `bootstrap` | `apt`, `homebrew`, `sheldon`, `mise` (OS packages and tool managers) |
| `tools` | `mise-tools`, `uv-tools`, `claude`, `codex`, `tmux`, `luarocks` |
| `plugins` | `tpm` (plugins on top of the tools) |

Steps that do not apply to the platform are skipped with a message; for example,
macOS installs `sheldon`, `tmux`, and `luarocks` from `brew/Brewfile` in the
`homebrew` step.

A failed step is reported and setup continues with the next one, unless
`SETUP_STRICT=1`.

```bash
./setup.sh all --only claude,codex
./setup.sh tools --only tmux,luarocks
./setup.sh all --skip luarocks,tpm
./setup.sh all --dry-run
./setup.sh all --reload-shell
SETUP_HOME=/tmp/dotfiles-home SETUP_DRY_RUN=1 ./setup.sh all
```

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `SETUP_HOME` | `$HOME` | Home directory to install into |
| `SETUP_TMPDIR` | `$TMPDIR` or `/tmp` | Temporary directory for setup |
| `SETUP_DOTFILES_ROOT` | checkout root | Dotfiles source directory |
| `SETUP_DRY_RUN` | `0` | `1` prints commands without side effects |
| `SETUP_STRICT` | `0` | `1` stops at the first failed step |
| `SETUP_MISE_STRICT` | `0` | `1` treats failed mise tools as a failed step |
| `SETUP_APT_INSTALL` | `0` | `1` installs missing apt packages with `sudo apt-get` |
| `MISE_JOBS` | mise `jobs` | Parallel mise installs |
| `NO_COLOR` | unset | A non-empty value turns off the `[WARN]` / `[ERROR]` label colors |

## Platform notes

### Debian / Ubuntu / WSL

The `apt` step checks the build dependencies listed in `setup/apt-packages.txt`
and prints the missing ones. It installs them only when `SETUP_APT_INSTALL=1`.

### macOS

Packages are installed with Homebrew from `brew/Brewfile`.

### Windows

`.\setup.ps1` uses the same phases with the steps `links`, `scoop` and `mise`
(bootstrap), `claude` and `codex` (tools), and `psmux` (plugins), and accepts
`--only` and `--skip`. Steps other than `links` are skipped in an elevated
session unless `SETUP_ALLOW_ELEVATED=1` is set (CI uses this on always-elevated
runners).

Link creation in `.\setup.ps1 links`, user-scope `skills`, and named `claude`
environments first uses the current privileges. If symbolic link privileges are
missing, setup requests UAC elevation once for the link batch. Only link
installation is retried; package installation, configuration generation and
credential input stay in the original process with the original user's paths.
Cancelling or being unable to elevate, or missing link privileges after
elevation, falls back to copies. Other errors stop setup. Developer Mode allows
unelevated links. To copy from the start:

```powershell
.\setup.ps1 links -Copy
.\setup.ps1 skills -Copy
.\setup.ps1 claude --env personal -Copy
```

`-Copy` also applies to the links step of `.\setup.ps1 all`; skills supports it
for user scope. Codex environments generate independent files, so they need no
symbolic links or elevation.

Copies do not follow source edits: rerun the corresponding setup command after
updating dotfiles or local skills. A copy is completed in a temporary path
before it replaces the installed file. The Vim entry file and `claude-pick.ps1`
use small loader files that keep loading the source from the checkout.

## Claude Code and Codex CLI installation

The `claude` and `codex` steps install Claude Code and Codex CLI with their
official self-updating installers when neither is on `PATH`:

| Platform | Claude Code | Codex CLI |
| --- | --- | --- |
| Linux / macOS | `~/.local/bin/claude` | `~/.local/bin/codex` |
| Windows | `~\.local\bin\claude.exe` | `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe` |

If one is already installed by Homebrew, npm, Scoop, or another manager, setup
leaves it in place and prints the command to remove it; rerun setup afterwards
to switch to the official install.

The `mise-tools` step runs a single `mise install` so tools install in parallel.
Failed tools are reported and setup continues unless `SETUP_MISE_STRICT=1`.

## Codex and Claude settings copies

Codex and Claude Code write runtime state, such as trusted project paths and
hook approvals, into their settings files. `setup links` therefore installs
`~/.codex/config.toml` and `~/.claude/settings.json` as copies of
`codex/config.toml` and `claude/settings.json` instead of links; their other
files stay linked.

Each run merges dotfiles changes into the copies and keeps local edits. A local
value that conflicts with a dotfiles change is kept with a warning. The version
last applied is kept in `.dotfiles-managed/` next to each copy. Runtime state
keys (Codex `projects`, `hooks.state`, `tui.model_availability_nux`,
`tui.screen_reader_detection_done` and `notice.model_migrations`) are never
synced or compared. If Node.js is not installed yet, `links` only seeds missing
copies; rerun it after the `tools` phase.

To bring local edits back into dotfiles, review them and edit the tracked files:

```bash
./setup.sh diff           # + only in the local copy, - only in dotfiles, ~ changed locally
./setup.sh diff --check   # exit 1 when they differ
```

Values under `env` and keys that look like tokens, keys or secrets are masked.
Setup and the pre-commit hook print a one-line count when the copies differ;
neither fails because of it. On Windows, use `.\setup.ps1 diff`.
