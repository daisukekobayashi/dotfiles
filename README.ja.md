# dotfiles

これは, 私個人の開発環境向け dotfiles リポジトリです.

## Core Stack

- Shell : `zsh`
- Terminal multiplexer : `tmux`
- Editor : `neovim`
- Tool/package management : `mise`
- `zsh` plugin management : `sheldon`

このリポジトリの setup スクリプトは, この構成を前提にしています.

`mise` は `mise/config.toml` を共通設定として読み込み, 環境ごとに次の設定を自動で切り替えます.
- Linux: `mise/config.linux.toml`
- WSL: `mise/config.wsl.toml`
- macOS: `mise/config.macos.toml`

macOS のパッケージセットアップは Homebrew と `brew/Brewfile` で管理します.

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
- `./setup.sh all --reload-shell`

利用可能な環境変数.

- `SETUP_HOME`
- `SETUP_TMPDIR`
- `SETUP_DOTFILES_ROOT`
- `SETUP_DRY_RUN` (`0` or `1`)
- `SETUP_MISE_STRICT` (`0` or `1`, default: `0`)

例.

```bash
SETUP_HOME=/tmp/dotfiles-home SETUP_DRY_RUN=1 ./setup.sh all
./setup.sh all --reload-shell
```

## AI Agent Rules

`./setup.sh links` は, Codex, Gemini, Claude 向けの生成済み rule file も配置します.

外部 skill は `skills-lock.json` で管理します.

独自 skill は `skills/` に置きます.

`./setup.sh skills` はデフォルトで `skills-lock.json` から外部 skill を `.agents/skills` に restore し, `skills/` 配下の独自 skill を symlink します. `./setup.sh skills --source lock` は独自 skill を保持したまま外部 skill を更新し, `./setup.sh skills --source local` は restore 済みの外部 skill を消さずに独自 skill だけ更新します. そのうえで `~/.agents/skills` と `~/.claude/skills` を生成先へ向けます.

Windows ではデフォルトの restore+link は `.\setup.ps1 skills` で実行し, 外部 skill だけ更新したい場合は `.\setup.ps1 skills -Source lock`, 独自 skill だけ更新したい場合は `.\setup.ps1 skills -Source local` を使います. `.\setup.ps1 all` は引き続き `packages` と `links` だけを実行するため, skill の restore は明示的に実行します. `skills-lock.json` から外部 skill を restore する場合は `npx` が利用可能である必要があります.

`.agents/` は生成物なので git には含めません.

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
