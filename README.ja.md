# dotfiles

これは, macOS, Linux, WSL, Windows 向けの, 私個人の開発環境の dotfiles です.
詳細なドキュメントは英語版を正本とし, `docs/` 以下は英語のみです. [English](README.md)

## Core Stack

- Shell : `zsh` (プラグイン管理は `sheldon`)
- Terminal multiplexer : `tmux`
- Editor : `neovim`, 補助用の `vim`
- Tool/package management : `mise`, macOS では Homebrew (`brew/Brewfile`), Windows では Scoop
- AI agent : Claude Code, Codex CLI, Gemini CLI

`mise` は `mise/config.toml` と OS ごとの設定
(`config.linux.toml`, `config.wsl.toml`, `config.macos.toml`, `config.windows.toml`)
を読み込みます. 任意利用の runtime は `mise/README.md` に記載しています.

## クイックスタート

```bash
git clone https://github.com/daisukekobayashi/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh all        # Windows: .\setup.ps1 all
```

`all` は次の 4 フェーズを順に実行します. 各フェーズは単独でも実行できます.

| フェーズ | 内容 |
| --- | --- |
| `links` | `~` 以下に設定ファイルをリンク・生成 |
| `bootstrap` | OS パッケージとツール管理ツール (apt, Homebrew, sheldon, mise) |
| `tools` | ツールの導入 (mise tools, uv tools, Claude Code, Codex CLI, tmux, luarocks) |
| `plugins` | ツールの上に乗るプラグイン (tpm) |

```bash
./setup.sh help                         # サブコマンドと引数の一覧
./setup.sh links                        # pull 後のリンク更新
./setup.sh all --only claude,codex      # 指定したステップだけ実行
./setup.sh all --skip luarocks,tpm      # ステップを除外
./setup.sh all --dry-run                # 副作用なしでコマンドを表示
```

`~/.codex/config.toml` と `~/.claude/settings.json` は, ツールが実行時の状態を書き込むため,
リンクではなくコピーとして配置します. ローカルでの変更は `./setup.sh diff` で確認できます.
環境変数, OS ごとの注意点, コピーのマージ方法は [Setup](docs/setup.md) を参照してください.

## ディレクトリ構成

| パス | 内容 |
| --- | --- |
| `setup.sh`, `setup.ps1`, `setup/` | setup の入口と実装 (TypeScript のソースは `setup/src/`) |
| `zsh/`, `.zshrc`, `.zshenv`, `sheldon/` | Zsh の設定とプラグイン |
| `tmux/`, `.tmux.conf`, `zellij/` | ターミナルマルチプレクサ |
| `nvim/`, `vim/` | Neovim と Vim |
| `mise/`, `brew/`, `nix/`, `flake.nix` | ツールとパッケージの定義 |
| `claude/`, `codex/`, `gemini/` | AI agent の設定 |
| `ai-rules/` | `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` に合成する共通ルール |
| `skills/` | skill profile とローカル skill |
| `tools/` | `~/.local/bin` に配置する補助コマンド |
| `powershell/` | PowerShell のプロファイル |
| `atuin/`, `lazygit/`, `gitui/`, `ipython/`, `process-compose/`, `mcphub/` | その他のツール設定 |
| `tests/` | Bats, Node, PowerShell のテスト |

## 補助コマンド

`setup links` で次のコマンドを `~/.local/bin` に配置します.

- `claude-pick` : Claude Code の環境, model, effort を選んで起動します.
  [Claude Code environments](docs/claude-environments.md) を参照してください.
- `codex-pick` : Codex の環境と model profile を選んで起動します.
  [Codex environments](docs/codex-environments.md) を参照してください.
- `share-dir` : 指定したディレクトリを Docker 上の FileBrowser Quantum で共有します.

## AI agent の skill

`./setup.sh skills` は user scope に `base` profile を導入し,
`~/.agents/skills` と `~/.claude/skills` をそこに向けます.
リポジトリ固有の skill は project scope で導入します.

```bash
~/.dotfiles/setup.sh skills --scope project --profile base,github
~/.dotfiles/setup.sh skills profile validate
```

profile の一覧は [Skills profiles](docs/skills-profiles.ja.md),
skill の評価方法は [Skill evaluation](docs/skill-evaluation.ja.md) を参照してください.

## ドキュメント

- [Setup](docs/setup.md)
- [Claude Code environments](docs/claude-environments.md)
- [Codex environments](docs/codex-environments.md)
- [Vim](docs/vim.md)
- [Skills profiles](docs/skills-profiles.ja.md)
- [Testing](docs/testing.md)
