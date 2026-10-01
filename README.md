# dotfiles

Personal dotfiles for my own development environment.

## Core Stack

- Shell: `zsh`
- Terminal multiplexer: `tmux`
- Editor: `neovim`, with a `vim` fallback
- Tool/package management: `mise`
- `zsh` plugin management: `sheldon`

The setup scripts are designed around this stack.

`mise` loads `mise/config.toml` as the base config and switches environment-specific config automatically:
- Linux: `mise/config.linux.toml`
- WSL: `mise/config.wsl.toml`
- macOS: `mise/config.macos.toml`

Optional mise env configs are documented in `mise/README.md`.

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

## Editors

`vim/vimrc` and `vim/gvimrc` provide basic Vim settings that also work without plugins.
The link step installs them as `~/.vimrc` and `~/.gvimrc` on Linux/macOS,
or `_vimrc` and `_gvimrc` in the home directory on Windows.
After updating an existing checkout, run `./setup.sh links`
(Windows: `.\setup.ps1 links`) to refresh the links.

Vim plugins are defined in `vim/plugins.vim` and managed by vim-plug:
commentary (`gc`/`gcc`), surround (`ys`/`cs`/`ds`), repeat (`.`), auto-pairs,
sleuth (indent detection), Kanagawa (wave), and fzf/fzf.vim.
Install them explicitly from the repository root with Git, curl, and Vim available:

```sh
vim -Nu vim/vimrc -n -i NONE -S vim/install.vim
```

The same command works in PowerShell. The installer bootstraps vim-plug 0.14.0
and installs missing plugins. Runtime files live in `~/.vim/dotfiles/`
(`~/vimfiles/dotfiles/` on Windows), preserving any older Vim plugin installation.
Restart Vim after installation. Use `:PlugUpdate` to update plugins explicitly
and `:PlugStatus` to inspect their state. Normal startup never downloads plugins.

fzf uses the existing external binary (0.54.0 or later); install `rg` for text
search and optionally `bat` for syntax-highlighted previews. Preview also needs
Bash (Git Bash on Windows). Linux/WSL mise configs and the macOS Brewfile already
manage these tools; the Windows mise config manages fzf and rg. Mappings for
missing tools are omitted, and Kanagawa falls back to the standard colors when
it is not installed. Kanagawa needs a true-color terminal.

The leader is Space. Search keys follow the Neovim Snacks Picker configuration:

| Keys | Vim action |
| --- | --- |
| `<leader>ff`, `<leader><Space>` | Files (`<leader><Space>` uses a regular file picker instead of Smart Find Files) |
| `<leader>fc` | Files in the dotfiles `vim/` directory |
| `<leader>fg` | Git files |
| `<leader>fr` | Recent files |
| `<leader>,`, `<leader>fb` | Buffers |
| `<leader>/`, `<leader>sg` | Live grep |
| `<leader>sw` (normal/visual) | Literal search for the word or selection |
| `<leader>:`, `<leader>sc` | Command history |
| `<leader>s/` | Search history |
| `<leader>sb`, `<leader>sB` | Lines in the current/all open buffers |
| `<leader>sC` | Commands |
| `<leader>sh` | Help tags (requires Perl) |
| `<leader>sj`, `<leader>sk`, `<leader>sm` | Jumps, keymaps, marks |
| `<leader>uC` | Color schemes |

Pickers use a centered popup with a preview. `Ctrl-U`/`Ctrl-D` scroll the preview,
`Ctrl-/` toggles it, and `Ctrl-T`/`Ctrl-X`/`Ctrl-V` open selections in a tab or split.

Zsh selects `nvim`, then `vim`, then `vi` for both `EDITOR` and `VISUAL`,
and refreshes the selection after mise activates its runtime PATH.

Vim clipboard integration uses native support when available, or existing
macOS, Wayland, X11, Windows/WSL, and tmux clipboard commands. The tmux popup
backend uses the same helpers as Neovim. Normal `y`, `p`/`P`, and insert-mode
`Ctrl-R "` use the selected clipboard; named registers keep their usual meaning.
Run `:echo g:dotfiles_clipboard_provider` to see the active backend.

Without a clipboard command, SSH sessions can copy to a compatible terminal
using OSC 52. Paste in that case uses the terminal's paste shortcut.
OSC 52 copies are limited to 32 KiB by default;
tmux keeps larger copies in its own buffer. tmux paste requests a clipboard
refresh from the terminal when supported. Native `"+`/`"*` registers require a
Vim build with `+clipboard`; the external fallback bridges ordinary operations.

## Tools

`./setup.sh links` installs dotfiles-managed helper commands into `~/.local/bin`.

- `share-dir`: start a Dockerized FileBrowser Quantum instance for a chosen directory.

## AI Agent Rules

`./setup.sh links` also installs generated rule files for Codex, Gemini, and Claude.

Skill profiles live in `skills/profiles/`.

Custom local skills live in `skills/local/`.

The optional `pstack` profile adds eleven workflow and principle skills adapted
from Lauren Tan's pstack. Use `base,github,pstack` to combine them with the
existing baseline and GitHub workflows. See the [pstack profile](docs/skills-profiles.md#pstack)
for responsibilities, invocation boundaries, and installation.

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
bats tests/dap/e2e.bats tests/dap/e2e/*.bats
DAP_E2E=1 bats tests/dap/e2e.bats tests/dap/e2e/*.bats
```

`DAP_E2E=1` verifies real breakpoint stops for Elixir, Python, Node, and Rust across local, direct Docker, and Docker Compose targets. The Docker checks require Docker Compose v2 and build pinned fixture images on first run. Node and Rust Docker checks use host networking for server-style debug adapters; Rust also grants `SYS_PTRACE` with `seccomp=unconfined`.

Local checks use host-installed adapters and skip with explicit reasons when a compatible toolchain is missing: Elixir needs `elixir-ls-debugger`, Python needs `debugpy-adapter` (provided by Mason's `debugpy` package), Node needs `js-debug-adapter`, and Rust needs `cargo` plus `codelldb`. Docker and Compose checks install the language-specific adapter inside the fixture image. Run one language with `DAP_E2E=1 bats tests/dap/e2e/python.bats`, or filter targets with Bats, for example `DAP_E2E=1 bats --filter 'direct docker container' tests/dap/e2e/*.bats`. Set `DAP_E2E_KEEP=1` to keep per-test logs under the temporary run directory.

Manual bootstrap E2E checks are opt-in because they start fresh Docker
containers and may download packages or build tools. The manual entrypoint is
`scripts/bootstrap-e2e.sh`; see `tests/bootstrap/README.md` for suites,
GitHub credential forwarding, Bats wrapper usage, and known diagnostics.

```bash
scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite dry-run
bats tests/bootstrap/bootstrap-e2e.bats
```

Static checks.

```bash
shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```

Vim checks use temporary homes and do not download dependencies:

```bash
bats tests/vim_config.bats tests/vim_plugins.bats
```

The installed-plugin checks skip when the managed plugins are absent. Set
`VIM_PLUGIN_RUNTIME` to a separately installed `dotfiles/` runtime to test it.
