# dotfiles

Personal dotfiles for my own development environment.

## Core Stack

- Shell: `zsh`
- Terminal multiplexer: `tmux`
- Editor: `neovim`
- Tool/package management: `mise`
- `zsh` plugin management: `sheldon`

The setup scripts are designed around this stack.

`mise` loads `mise/config.toml` as the base config and switches environment-specific config automatically:
- Linux: `mise/config.linux.toml`
- WSL: `mise/config.wsl.toml`
- macOS: `mise/config.macos.toml`

On macOS, package bootstrap is handled with Homebrew and `brew/Brewfile`.

## Setup

### First-time setup

```bash
git clone https://github.com/daisukekobayashi/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh all
```

### Run setup from repository root

```bash
./setup.sh help
```

Main subcommands.

- `./setup.sh all`
- `./setup.sh links`
- `./setup.sh packages`
- `./setup.sh post`

Package step filters.

- `./setup.sh packages --only tmux,luarocks`
- `./setup.sh packages --skip quarto`
- `./setup.sh packages --dry-run`
- `./setup.sh all --reload-shell`

Optional environment variables.

- `SETUP_HOME`
- `SETUP_TMPDIR`
- `SETUP_DOTFILES_ROOT`
- `SETUP_DRY_RUN` (`0` or `1`)
- `SETUP_MISE_STRICT` (`0` or `1`, default: `0`)

Example.

```bash
SETUP_HOME=/tmp/dotfiles-home SETUP_DRY_RUN=1 ./setup.sh all
./setup.sh all --reload-shell
```

## AI Agent Rules

`./setup.sh links` also installs generated rule files for Codex, Gemini, and Claude.

Third-party skills are tracked in `skills-lock.json`.

Custom skills live in `skills/`.

`./setup.sh skills` restores third-party skills from `skills-lock.json` and symlinks custom skills from `skills/` into `.agents/skills` by default. Use `./setup.sh skills --source lock` to refresh third-party skills while preserving installed custom skills, or `./setup.sh skills --source local` to refresh only custom skills without clearing restored third-party ones. The command wires `~/.agents/skills` and `~/.claude/skills` to that generated directory.

On Windows, use `.\setup.ps1 skills` for the default restore+link flow, `.\setup.ps1 skills -Source lock` to refresh only third-party skills, or `.\setup.ps1 skills -Source local` to refresh only custom skills. `.\setup.ps1 all` still runs only `packages` and `links`, so skills restore remains an explicit step. The PowerShell workflow expects `npx` to be available when restoring third-party skills from `skills-lock.json`.

`.agents/` is a generated restore target and is intentionally ignored by git.

## Test

Run setup tests with `bats`.

```bash
bats tests
```

Static checks.

```bash
shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```
