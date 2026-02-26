# dotfiles

Personal dotfiles for my own development environment.

## Core Stack

- Shell: `zsh`
- Terminal multiplexer: `tmux`
- Editor: `neovim`
- Tool/package management: `mise`
- `zsh` plugin management: `sheldon`

The setup scripts are designed around this stack.

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

Optional environment variables.

- `SETUP_HOME`
- `SETUP_TMPDIR`
- `SETUP_DOTFILES_ROOT`
- `SETUP_DRY_RUN` (`0` or `1`)

Example.

```bash
SETUP_HOME=/tmp/dotfiles-home SETUP_DRY_RUN=1 ./setup.sh all
```

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
