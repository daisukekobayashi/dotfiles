# Vim

Neovim is the main editor (`nvim/`). This document covers the Vim fallback in
`vim/`, which also works without plugins.

## Install

`setup links` installs `vim/vimrc` and `vim/gvimrc` as `~/.vimrc` and
`~/.gvimrc` on Linux/macOS, or `_vimrc` and `_gvimrc` in the home directory on
Windows.

Plugins are defined in `vim/plugins.vim` and managed by vim-plug: commentary
(`gc`/`gcc`), surround (`ys`/`cs`/`ds`), repeat (`.`), auto-pairs, sleuth
(indent detection), Kanagawa (wave), and fzf/fzf.vim. Install them explicitly
from the repository root with Git, curl, and Vim available (also in PowerShell):

```sh
vim -Nu vim/vimrc -n -i NONE -S vim/install.vim
```

The installer bootstraps vim-plug 0.14.0 into `~/.vim/dotfiles/`
(`~/vimfiles/dotfiles/` on Windows). Restart Vim afterwards. Use `:PlugUpdate`
and `:PlugStatus` to update and inspect plugins; normal startup never downloads
them.

fzf uses the external binary (0.54.0 or later); install `rg` for text search and
optionally `bat` for previews. Preview needs Bash (Git Bash on Windows). The
Linux/WSL mise configs and the macOS Brewfile manage these tools; the Windows
mise config manages fzf and rg. Mappings for missing tools are omitted, and
Kanagawa falls back to the standard colors when it is not installed. Kanagawa
needs a true-color terminal.

## Search keys

The leader is Space. Search keys follow the Neovim Snacks Picker configuration:

| Keys | Action |
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

Pickers use a centered popup with a preview. `Ctrl-U`/`Ctrl-D` scroll the
preview, `Ctrl-/` toggles it, and `Ctrl-T`/`Ctrl-X`/`Ctrl-V` open selections in
a tab or split.

## Clipboard

Vim uses native clipboard support when available, or existing macOS, Wayland,
X11, Windows/WSL, and tmux clipboard commands; the tmux popup backend uses the
same helpers as Neovim. Normal `y`, `p`/`P`, and insert-mode `Ctrl-R "` use the
selected clipboard; named registers keep their usual meaning. Run
`:echo g:dotfiles_clipboard_provider` to see the active backend.

Without a clipboard command, SSH sessions copy to a compatible terminal with
OSC 52 (32 KiB by default) and paste with the terminal's shortcut. tmux keeps
larger copies in its own buffer and requests a clipboard refresh on paste when
supported. Native `"+`/`"*` registers require a Vim build with `+clipboard`.

## Editor selection

Zsh selects `nvim`, then `vim`, then `vi` for both `EDITOR` and `VISUAL`, and
refreshes the selection after mise activates its runtime PATH.
