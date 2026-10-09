# dotfiles

これは, 私個人の開発環境向け dotfiles リポジトリです.

## Core Stack

- Shell : `zsh`
- Terminal multiplexer : `tmux`
- Editor : `neovim`, 補助用の `vim`
- Tool/package management : `mise`
- `zsh` plugin management : `sheldon`

このリポジトリの setup スクリプトは, この構成を前提にしています.

`mise` は `mise/config.toml` を共通設定として読み込み, 環境ごとに次の設定を自動で切り替えます.
- Linux: `mise/config.linux.toml`
- WSL: `mise/config.wsl.toml`
- macOS: `mise/config.macos.toml`

任意利用の mise env config は `mise/README.md` に記載しています.

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

## Editors

`vim/vimrc` と `vim/gvimrc` は, プラグインなしでも使える Vim の基本設定です.
リンク処理により, Linux/macOS では `~/.vimrc` と `~/.gvimrc`,
Windows ではホームディレクトリの `_vimrc` と `_gvimrc` に配置します.
既存のチェックアウトを更新した後は, `./setup.sh links`
(Windows: `.\setup.ps1 links`) でリンクを更新してください.

プラグインは `vim/plugins.vim` に定義し, vim-plug で管理します.
commentary (`gc`/`gcc`), surround (`ys`/`cs`/`ds`), repeat (`.`), auto-pairs,
sleuth (インデント検出), Kanagawa (wave), fzf/fzf.vim を使います.
Git, curl, Vim がある環境で, リポジトリのルートから次を実行してください.

```sh
vim -Nu vim/vimrc -n -i NONE -S vim/install.vim
```

PowerShell でも同じコマンドを使えます. vim-plug 0.14.0 と未導入のプラグインを
`~/.vim/dotfiles/` (Windows: `~/vimfiles/dotfiles/`) に導入します.
既存の Vim プラグイン用ディレクトリは保持します. 導入後は Vim を開き直してください.
更新は `:PlugUpdate`, 状態確認は `:PlugStatus` を使い, 通常の起動時にはダウンロードしません.

fzf 本体は外部コマンドを使い, 全文検索には `rg`, 色付きプレビューには任意で `bat` が必要です.
プレビューには Bash (Windows: Git Bash) も使います. Linux/WSL の mise 設定と
macOS の Brewfile はこれらのツールを管理し, Windows の mise 設定は fzf と rg を管理します.
必要なツールがない検索キーは登録せず, 未導入のテーマは標準の色で起動します.
Kanagawa にはトゥルーカラー対応の端末が必要です.

leader は Space です. `Space ff` (ファイル), `Space /` / `Space sg` (全文検索),
`Space ,` / `Space fb` (バッファ), `Space sw` (単語・選択範囲) などを
Neovim の Snacks Picker と同じキーにしています.
`Space Space` は通常のファイル選択で, Smart Find Files の代わりに使います.
[検索キーの一覧](README.md#editors)も参照してください.

Zsh は `nvim`, `vim`, `vi` の順に `EDITOR` と `VISUAL` を選び,
mise が runtime の PATH を反映した後にも選び直します.

Vim のクリップボードは, 組み込み機能, または既存の macOS, Wayland,
X11, Windows/WSL, tmux のコマンドを使います. tmux popup では Neovim と
同じヘルパーを使います. 通常の `y`, `p`/`P`, 挿入モードの `Ctrl-R "`
がクリップボードに連携し, 名前付きレジスタは通常の動作を保ちます.
`:echo g:dotfiles_clipboard_provider` で現在の方式を確認できます.

クリップボード用コマンドがない SSH 接続では, OSC 52 対応端末にコピーできます.
この場合の貼り付けは端末のショートカットを使います. OSC 52 のコピーは
デフォルトで 32 KiB までで, tmux ではそれを超える内容も tmux のバッファに保存します.
tmux の貼り付け時は, 対応端末にクリップボードの再取得を要求します.
組み込みの `"+`/`"*` レジスタには `+clipboard` の Vim が必要です.
外部コマンドによる補助設定は通常のコピー・貼り付け操作を連携します.

## Tools

### Claude Code profiles

macOS/Linux は `./setup.sh links`, Windows は `.\setup.ps1 links` で,
`~/.local/bin` に `claude-pick` / `claude-pick.ps1` を配置します.
起動処理は Bash / PowerShell 5.1+ です. 対話選択には `fzf` が必要ですが,
引数で指定すれば不要です. Windows は native `claude.exe` と symlink 作成権限が
必要です. profile 作成時は PowerShell 7+ と Developer Mode, または適切な権限の
端末を使います. Windows PowerShell 5.1 は Developer Mode があっても後者が
必要です ([PowerShell の報告](https://github.com/PowerShell/PowerShell/issues/5000)).
通常の起動に権限の昇格は不要です.
既存の status line には引き続き Node.js を使います.

```sh
claude-pick                                 # profile, model, effort を選択
claude-pick --create acme                    # 初期化のみ. ログイン・起動はしない
claude-pick -p acme -- auth login            # profile ごとにログイン
claude-pick -p acme                          # 保存済み設定で起動
claude-pick -p acme opus high -- --resume
claude-pick -p default                       # 既存の ~/.claude を使う
```

PowerShell では `claude-pick.ps1` を使い, 区切りは `'--'` と引用して
[PowerShell に取り除かれないようにします](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing#the-end-of-parameters-token).

```powershell
claude-pick.ps1 --create acme
claude-pick.ps1 -p acme '--' auth login
claude-pick.ps1 -p acme opus high '--' --resume
```

リンク配置前は `./tools/claude/claude-pick` / `.\tools\claude\claude-pick.ps1` から実行できます.
更新後はシェルを開き直してください. `claude` は本来のコマンドになり,
従来の Zsh wrapper が追加していた共通 MCP 設定は `claude-pick -p default`
で使えます. 互換性のため `claude-raw` は残しています.

保存先は `~/.claude-profiles/<名前>` です. 名前は英小文字で始まる 1〜64 文字の
英小文字・数字・`_`・`-` で, `default` と Windows のデバイス名は予約名です.
profile が無い場合は `default` と新規作成を選べます. 存在しない名前を引数で
指定した場合はエラーになります. 選択中のキャンセルでは作成・起動せず,
既存 profile の上書きもしません.

profile だけの指定では model/effort 選択を省略します. どちらかを指定すると
残りを選択し, `keep` なら Claude の設定を維持します. 位置引数の代わりに
`-m MODEL` / `-e EFFORT` も使えます. effort の候補は `low`, `medium`, `high`,
`xhigh`, `max` で, 対応範囲は Claude のモデル・バージョンによります.
選んだ effort は子プロセスの `CLAUDE_CODE_EFFORT_LEVEL` にも反映します.
`--` 以降は Claude にそのまま渡すため, Claude の `-p` / `--print` もここに書きます.
`auth` などの管理コマンドでは model/effort を選択しません.

| profile 内の項目 | 扱い |
| --- | --- |
| `settings.json` | `claude/profile-settings.json` の初期コピー. 作成後は個別に編集 |
| `rules/00-global.md`, `rules/10-claude.md` | `ai-rules/` の共通ソースへ symlink |
| `statusline.cjs` | 共通 renderer へ symlink. 選択した profile 名を表示 |
| `skills/` | 初期状態は空. `--create acme --skill NAME` で導入済み skill を個別にリンク |
| `mcp.json` | 任意の profile 固有 MCP 設定. 明示した `--mcp-config` が優先 |
| ログイン・履歴・メモリ・plugins | 選択した設定ディレクトリで Claude が個別管理 |

既存 `~/.claude/settings.json`・認証情報・hooks・plugins はコピーしません.
特に, 別のデータ保存先を持つ `claude-mem` は新規 profile では有効にしません.
使う場合はその保存先も個別に設定してください. rules と status line は dotfiles
の変更に追従し, 設定テンプレートの変更は次に作る profile にだけ反映します.
設定の自動同期やアカウントの自動移行は行いません.

名前付き profile では `tools/claude/auth-env.txt` にある認証・接続先の環境変数が
残っていると起動を止め, 値を表示せず変数名を案内します. 呼び出し元のシェルで
対象変数を解除してください. `default` は従来の環境変数を維持します.
`CLAUDE_CONFIG_DIR` の変更は子プロセスにだけ適用します. これは Claude の
ユーザー設定・状態の分離であり, OS のセキュリティ境界ではありません.
プロジェクト設定・管理ポリシー・外部 plugin の保存先は別途適用されます.
公式の[環境変数](https://code.claude.com/docs/en/env-vars),
[認証の優先順位](https://code.claude.com/docs/en/authentication#authentication-precedence),
[ユーザールール](https://code.claude.com/docs/en/memory#user-level-rules)も参照してください.

## AI Agent Rules

`./setup.sh links` は, Codex, Gemini, Claude 向けの生成済み rule file も配置します.

Skill profile は `skills/profiles/` に置きます.

独自 local skill は `skills/local/` に置きます.

`./setup.sh skills` はデフォルトで user scope の `base` profile をインストールし, `~/.agents/skills` と `~/.claude/skills` を dotfiles 管理の user skill view へ向けます. PowerShell entry point の `.\setup.ps1 skills` も同じ Node runtime を使います. リポジトリ固有の skill は project scope でインストールします.

```bash
~/.dotfiles/setup.sh skills --scope project --profile office
~/.dotfiles/setup.sh skills --scope project --profile base,github --agent codex
~/.dotfiles/setup.sh skills --scope project --profile base,azure-devops
~/.dotfiles/setup.sh skills --scope project --profile workbench
```

`base` は provider-neutral です. 以前の GitHub 対応込みの baseline が必要な場合は `base,github`, Azure DevOps リポジトリでは `base,azure-devops` を使います. `azure` と `azure-devops` は独立しているため, Azure cloud/resource 作業と Azure DevOps workflow skill の両方が必要な場合だけ組み合わせます. `office`, `docs`, `browser` のような domain profile は単体で使えるようにしています. 共通 workflow skill が必要なリポジトリでは `base` を明示的に組み合わせるか, 集約 profile の `workbench` を使います.

Project scope では, リポジトリ root から `npx skills add` で外部 skill をインストールし, 公式 CLI にリポジトリの `skills-lock.json` を管理させます. Dotfiles の local skill は `skills/local/` から symlink し, `skills-lock.json` には書き込みません.

Profile ベースの skills setup は TypeScript で実装し, commit 済み Node runtime の `setup/skills.js` で実行します. Bash と PowerShell はこの runtime への薄い wrapper です.

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
npm --prefix setup install
npm --prefix setup run build
npm --prefix setup test
bats tests
```

Claude picker の確認は一時 HOME と偽の Claude コマンドを使い,
ログイン・API 呼び出しは行いません.

```bash
bats tests/claude_pick.bats tests/claude_wrapper.bats
shellcheck tools/claude/claude-pick tests/claude_pick.bats tests/claude_wrapper.bats
```

native Windows では PowerShell 5.1 以降で `.\tests\claude_pick.ps1` を実行します.
Windows PowerShell 組み込みのコンパイラで確認用の小さな実行ファイルを作り,
引数やプロセスの動作を確認します. symlink 権限が無い場合, 作成成功の確認は
skip し, 作成失敗時に途中のファイルが残らないことを確認します.

Manual bootstrap E2E は opt-in です. 新しい Docker container で実行し,
package download や build を伴うため, 通常の `bats tests` には含めません.
手動入口は `scripts/bootstrap-e2e.sh` です. suite, GitHub credential 転送,
Bats wrapper, known diagnostics は `tests/bootstrap/README.md` を参照してください.

```bash
scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite dry-run
bats tests/bootstrap/bootstrap-e2e.bats
```

静的チェック.

```bash
shellcheck setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash tests/*.bats
bash -n setup.sh lib/common.sh setup/*.sh tests/helpers/*.bash
```
