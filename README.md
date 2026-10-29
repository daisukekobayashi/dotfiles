# dotfiles

Personal dotfiles for my own development environment on macOS, Linux, WSL, and
Windows. [日本語](README.ja.md)

## Core Stack

- Shell: `zsh`, with `sheldon` for plugins
- Terminal multiplexer: `tmux`
- Editor: `neovim`, with a `vim` fallback
- Tool/package management: `mise`; Homebrew (`brew/Brewfile`) on macOS, Scoop on Windows
- AI agents: Claude Code, Codex CLI, Gemini CLI

`mise` loads `mise/config.toml` and the platform config
(`config.linux.toml`, `config.wsl.toml`, `config.macos.toml`, or
`config.windows.toml`). Optional runtimes are described in `mise/README.md`.

## Quick start

```bash
git clone https://github.com/daisukekobayashi/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh all        # Windows: .\setup.ps1 all
```

`all` runs four phases in order. Each phase can also be run on its own.

| Phase | What it does |
| --- | --- |
| `links` | Link and generate config files under `~` |
| `bootstrap` | Install OS packages and tool managers (apt, Homebrew, sheldon, mise) |
| `tools` | Install tools (mise tools, uv tools, Claude Code, Codex CLI, tmux, luarocks) |
| `plugins` | Install plugins on top of the tools (tpm) |

```bash
./setup.sh help                         # All subcommands and arguments
./setup.sh links                        # Refresh links after pulling
./setup.sh all --only claude,codex      # Run selected steps
./setup.sh all --skip luarocks,tpm      # Skip steps
./setup.sh all --dry-run                # Print commands without side effects
```

`~/.codex/config.toml` and `~/.claude/settings.json` are installed as copies, not
links, because the tools write runtime state into them. Use `./setup.sh diff` to
review local edits. See [Setup](docs/setup.md) for environment variables,
platform notes, and how the copies are merged.

## Layout

| Path | Content |
| --- | --- |
| `setup.sh`, `setup.ps1`, `setup/` | Setup entry points and runtime (TypeScript sources in `setup/src/`) |
| `zsh/`, `.zshrc`, `.zshenv`, `sheldon/` | Zsh configuration and plugins |
| `tmux/`, `.tmux.conf`, `zellij/` | Terminal multiplexers |
| `nvim/`, `vim/` | Neovim and Vim |
| `mise/`, `brew/`, `nix/`, `flake.nix` | Tool and package definitions |
| `claude/`, `codex/`, `gemini/` | AI agent settings |
| `ai-rules/` | Shared agent rules composed into `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` |
| `skills/` | Skill profiles and local skills |
| `tools/` | Helper commands installed into `~/.local/bin` |
| `powershell/` | PowerShell profile |
| `atuin/`, `lazygit/`, `gitui/`, `ipython/`, `process-compose/`, `mcphub/` | Other tool configs |
| `tests/` | Bats, Node, and PowerShell tests |

## Helper commands

`setup links` installs these into `~/.local/bin`:

- `claude-pick`: choose a Claude Code environment, model, and effort.
  See [Claude Code environments](docs/claude-environments.md).
- `codex-pick`: choose a Codex environment and model profile.
  See [Codex environments](docs/codex-environments.md).
- `share-dir`: serve a chosen directory with a Dockerized FileBrowser Quantum.

## AI agent skills

`./setup.sh skills` installs the user-scope `base` profile and wires
`~/.agents/skills` and `~/.claude/skills` to it. Use project scope for
repository-specific skills:

```bash
~/.dotfiles/setup.sh skills --scope project --profile base,github
~/.dotfiles/setup.sh skills profile validate
```

See [Skills profiles](docs/skills-profiles.md) for the available profiles and
[Skill evaluation](docs/skill-evaluation.md) for evaluating skills.

## Documentation

- [Setup](docs/setup.md)
- [Claude Code environments](docs/claude-environments.md)
- [Codex environments](docs/codex-environments.md)
- [Vim](docs/vim.md)
- [Skills profiles](docs/skills-profiles.md)
- [Testing](docs/testing.md)
