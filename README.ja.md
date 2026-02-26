# dotfiles

これは, 私個人の開発環境向け dotfiles リポジトリです.

## Core Stack

- Shell : `zsh`
- Terminal multiplexer : `tmux`
- Editor : `neovim`
- Tool/package management : `mise`
- `zsh` plugin management : `sheldon`

このリポジトリの setup スクリプトは, この構成を前提にしています.

## Setup

### 初回セットアップ

```bash
git clone https://github.com/daisukekobayashi/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh all
```

### リポジトリルートでの実行

```bash
./setup.sh help
```

主なサブコマンド.

- `./setup.sh all`
- `./setup.sh links`
- `./setup.sh packages`
- `./setup.sh post`

`packages` サブコマンドの追加オプション.

- `./setup.sh packages --only tmux,luarocks`
- `./setup.sh packages --skip quarto`
- `./setup.sh packages --dry-run`

利用可能な環境変数.

- `SETUP_HOME`
- `SETUP_TMPDIR`
- `SETUP_DOTFILES_ROOT`
- `SETUP_DRY_RUN` (`0` or `1`)

例.

```bash
SETUP_HOME=/tmp/dotfiles-home SETUP_DRY_RUN=1 ./setup.sh all
```

## Test

`setup` スクリプトのテストは `bats` を使います.

```bash
bats tests
```

静的チェック.

```bash
shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```
