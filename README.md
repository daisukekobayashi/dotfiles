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
~/.dotfiles/setup.sh skills --scope project --profile base,beads
~/.dotfiles/setup.sh skills --scope project --profile base,azure-devops
~/.dotfiles/setup.sh skills --scope project --profile workbench
```

`base` is provider-neutral. Use `base,github` for the previous GitHub-enabled baseline, `base,beads` for Beads-backed issue workflows, or `base,azure-devops` for Azure DevOps repositories. `azure` and `azure-devops` are independent; combine them only when a repository needs both Azure cloud/resource work and Azure DevOps workflow skills. Domain profiles such as `office`, `docs`, and `browser` are standalone. Include `base` explicitly when a repository needs the common workflow skills, or use the aggregate `workbench` profile.

Project scope installs third-party skills with `npx skills add` from the repository root and lets the official CLI manage the repository `skills-lock.json`. Dotfiles local skills are symlinked from `skills/local/` and are not written to `skills-lock.json`.

When project scope refreshes agent skill directories, pre-existing skill entries that are not recreated by the selected profile are preserved. Entries with the same name as a profile-managed skill are replaced by the profile-managed version.

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

Neovim DAP full E2E checks are opt-in because they start real debug adapters and Docker services.

```bash
bats tests/dap/e2e.bats
DAP_E2E=1 bats tests/dap/e2e.bats
```

`DAP_E2E=1` verifies real breakpoint stops for Elixir, Python, Node, and Rust across local, direct Docker, and Docker Compose targets. The Docker checks require Docker Compose v2 and build pinned fixture images on first run. Node and Rust Docker checks use host networking for server-style debug adapters; Rust also grants `SYS_PTRACE` with `seccomp=unconfined`.

Local checks use host-installed adapters and skip with explicit reasons when a compatible toolchain is missing: Elixir needs `elixir-ls-debugger`, Python needs `debugpy`, Node needs `js-debug-adapter`, and Rust needs `cargo` plus `codelldb`. Docker and Compose checks install the language-specific adapter inside the fixture image. Set `DAP_E2E_KEEP=1` to keep per-test logs under the temporary run directory.

Static checks.

```bash
shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```
