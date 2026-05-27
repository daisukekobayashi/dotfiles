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

Skill profiles live in `skills/profiles/`.

Custom local skills live in `skills/local/`.

`./setup.sh skills` installs the user-scope `base` profile by default and wires `~/.agents/skills` and `~/.claude/skills` to a dotfiles-managed user skill view. The PowerShell entry point `.\setup.ps1 skills` uses the same Node runtime. Use project scope to install repository-specific skills:

```bash
~/.dotfiles/setup.sh skills --scope project --profile office
~/.dotfiles/setup.sh skills --scope project --profile base,github --agent codex
~/.dotfiles/setup.sh skills --scope project --profile base,azure-devops
~/.dotfiles/setup.sh skills --scope project --profile workbench
```

`base` is provider-neutral. Use `base,github` for the previous GitHub-enabled baseline, or `base,azure-devops` for Azure DevOps repositories. `azure` and `azure-devops` are independent; combine them only when a repository needs both Azure cloud/resource work and Azure DevOps workflow skills. Domain profiles such as `office`, `docs`, and `browser` are standalone. Include `base` explicitly when a repository needs the common workflow skills, or use the aggregate `workbench` profile.

Project scope installs third-party skills with `npx skills add` from the repository root and lets the official CLI manage the repository `skills-lock.json`. Dotfiles local skills are symlinked from `skills/local/` and are not written to `skills-lock.json`.

Profile-based skills setup is authored in TypeScript and runs through the committed Node runtime at `setup/skills.js`; Bash and PowerShell are thin wrappers around that runtime.

Profiles are edited by hand. Validate them with:

```bash
./setup.sh skills profile validate
./setup.sh skills profile validate --profile base,office
```

See `docs/skills-profiles.md` for the full design.

`.agents/` is a generated restore target and is intentionally ignored by git.

## Test

Run setup tests with `bats`.

```bash
npm --prefix setup install
npm --prefix setup run build
npm --prefix setup test
bats tests
```

Static checks.

```bash
shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```
