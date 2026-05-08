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

Skill profile は `skills/profiles/` に置きます.

独自 local skill は `skills/local/` に置きます.

`./setup.sh skills` はデフォルトで user scope の `base` profile をインストールし, `~/.agents/skills` と `~/.claude/skills` を dotfiles 管理の user skill view へ向けます. リポジトリ固有の skill は project scope でインストールします.

```bash
~/.dotfiles/setup.sh skills --scope project --profile office
~/.dotfiles/setup.sh skills --scope project --profile base,office --agent codex
~/.dotfiles/setup.sh skills --scope project --profile workbench
```

`office`, `docs`, `browser` のような domain profile は単体で使えるようにしています。共通 workflow skill が必要なリポジトリでは `base` を明示的に組み合わせるか、集約 profile の `workbench` を使います。

Project scope では, リポジトリ root から `npx skills add` で外部 skill をインストールし, 公式 CLI にリポジトリの `skills-lock.json` を管理させます. Dotfiles の local skill は `skills/local/` から symlink し, `skills-lock.json` には書き込みません.

Profile ベースの skills setup は Bash/Node で実装しています。PowerShell の `skills` subcommand は、旧 lock ベースの global restore を実行せず、意図的にエラーで止めます。

Profile は手で編集します. 検証は次のコマンドで行います.

```bash
./setup.sh skills profile validate
./setup.sh skills profile validate --profile base,office
```

詳細な設計は `docs/skills-profiles.ja.md` を参照してください.

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
