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

setup はフェーズ単位で実行します. `all` は次の順に実行し, 後のフェーズは前のフェーズに依存します.

| フェーズ | ステップ |
| --- | --- |
| `links` | `links` (設定ファイルのリンクと生成) |
| `bootstrap` | `apt`, `homebrew`, `sheldon`, `mise` (OS パッケージとツールの管理ツール) |
| `tools` | `mise-tools`, `uv-tools`, `claude`, `codex`, `tmux`, `luarocks`, `quarto`, `nvtop` |
| `plugins` | `alacritty`, `tpm`, `themes` (ツールの上に乗るプラグインや付属ファイル) |

- `./setup.sh all`
- `./setup.sh links`, `./setup.sh bootstrap`, `./setup.sh tools`, `./setup.sh plugins`

その環境で対象外のステップは, メッセージを表示してスキップします. 例えば macOS では
`sheldon`, `tmux`, `luarocks`, `quarto`, `nvtop` を `homebrew` ステップで `brew/Brewfile` から入れます.
`packages` と `post` は非推奨の別名として残しています. `packages` は `bootstrap`, `tools`,
`plugins` を, `post` は `mise-tools`, `uv-tools`, `tpm`, `themes` を実行します.

Windows の `.\setup.ps1 links`, user scope の `skills`, 名前付き `claude` env は,
通常権限でリンクを作成し, symlink 権限が不足するとリンク作成だけを UAC で昇格して
一度再試行します. パッケージ導入・設定生成・認証情報入力は元のプロセスで実行し,
リンク先にも元のユーザーのパスを引き継ぎます. 昇格のキャンセル・利用不可, または
昇格後もリンク権限が不足する場合はコピーへ切り替えます. 最初からコピーする場合:

```powershell
.\setup.ps1 links -Copy
.\setup.ps1 skills -Copy
.\setup.ps1 claude --env personal -Copy
```

`-Copy` は `.\setup.ps1 all` の links 処理でも使えます. skills では user scope が対象です.
Codex env は独立ファイルを生成し, skills は共通の `~/.agents/skills` を参照するため,
env の生成には symlink や昇格が不要です.
コピーは元ファイルの変更に追従しないため, dotfiles や local skill を更新した後は
対応する setup を再実行してください. 一時パスへのコピーが完了してから配置先を置き換えます.
権限不足以外のエラーでは処理を中断します.
Vim の設定入口と `claude-pick.ps1` は, 関連ファイルを見つけられるように小さな loader を
配置し, リポジトリ内の元ファイルを引き続き読み込みます.
PowerShell 5.1+ と Node.js がある環境では, `.\tests\setup_link_copy.ps1` で
両 entry point と権限不足・コピー失敗の回帰テストをオフライン実行できます.

ステップの絞り込みは `all` とすべてのフェーズのサブコマンドで使えます.

- `./setup.sh all --only claude,codex`
- `./setup.sh tools --only tmux,luarocks`
- `./setup.sh all --skip quarto,tpm`
- `./setup.sh all --dry-run`
- `./setup.sh all --reload-shell`

利用可能な環境変数.

- `SETUP_HOME`
- `SETUP_TMPDIR`
- `SETUP_DOTFILES_ROOT`
- `SETUP_DRY_RUN` (`0` or `1`)
- `SETUP_STRICT` (`0` or `1`, default: `0`. 最初に失敗したステップで停止)
- `SETUP_MISE_STRICT` (`0` or `1`, default: `0`. mise ツールの失敗をステップの失敗として扱う)
- `SETUP_APT_INSTALL` (`0` or `1`, default: `0`)
- `MISE_JOBS` (mise の並列インストール数, default: mise の `jobs` 設定)

Debian/Ubuntu (WSL を含む) では, `apt` ステップが `setup/apt-packages.txt` の
ビルド依存を確認し, 不足分を表示します. `sudo apt-get` でのインストールは
`SETUP_APT_INSTALL=1` のときだけ行います.
失敗したステップは表示して次のステップに進みます. `SETUP_STRICT=1` のときは停止します.
`claude` / `codex` ステップは, `PATH` 上に無い場合に
Claude Code と Codex CLI を公式の自動更新インストーラで `~/.local/bin` に入れます.
Homebrew や npm などで既に入っている場合は削除せずにそのまま残し, 削除コマンドを表示します.
削除後に setup を再実行すると公式インストールに切り替わります.
Windows の `.\setup.ps1` も同じフェーズで, `links`, `scoop` (bootstrap), `claude` と `codex` (tools),
`psmux` (plugins) のステップを持ち, `--only` / `--skip` を使えます. 管理者として実行した場合は
`links` 以外のステップをスキップします.
`claude` / `codex` ステップは公式の PowerShell インストーラで同様に処理します
(`~\.local\bin\claude.exe` と `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe`).
Scoop や npm で入っている場合は残したまま削除コマンドを表示します.
`mise-tools` ステップでは `mise install` を 1 回実行して並列にインストールします. 失敗したツールは
一覧表示され, `SETUP_MISE_STRICT=1` でなければ処理を継続します.

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

### Codex environments

**env (環境)** は, 保存先・認証・接続設定・履歴・メモリ・plugins をまとめた単位です.
**profile** は, その env で使うモデルと effort の設定セットです.
env 名は任意で, 同じ provider を使う env や同名の profile を複数持てます.

| env | 保存先 |
| --- | --- |
| `default` | 既存の `~/.codex`. 通常の ChatGPT サブスクリプション環境 |
| `azure` | 既存の `~/.codex-azure` |
| `openai` | 既存の `~/.codex-openai` |
| その他の名前 | `~/.codex-envs/<名前>` |

独立した env は共有 Node runtime で生成します. Windows は `.\setup.ps1 codex`
で同じ引数を使います. Node.js 18+ と setup のローカル依存が必要です.

```sh
npm --prefix setup ci
./setup.sh codex --env azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1' --dry-run
./setup.sh codex --env azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1'
./setup.sh codex --env openai
./setup.sh codex --env account-b --provider chatgpt
./setup.sh codex --env lab-a --provider azure --base-url 'https://RESOURCE.openai.azure.com/openai/v1' --api-key-env LAB_A_AZURE_KEY
```

新しい任意名の env には `--provider azure|openai|chatgpt` が必要です.
次回から `./setup.sh codex --env lab-a` のように実行すると, 保存済みの接続設定と
既定 profile を再利用します. 既存 env の provider は変更せず, 別 env を作ります.
`default` は従来の `setup links` で配置する設定を使います.
`setup links` / `setup all` は API 用 home の生成やログインを行いません.
名前は英小文字で始まる 1〜64 文字の英小文字・数字・`_`・`-` で,
Windows のデバイス名は予約名です.

Azure は初回に正確な base URL が必要です. `--api-key-env NAME` でキーを参照する
環境変数名 (既定 `AZURE_OPENAI_API_KEY`) を選べます.
`--api-version VERSION|none` で API version の設定・解除ができます.
次回以降に省略した接続項目は保存済みの値を維持します.
OpenAI の URL は既定で `https://api.openai.com/v1` で,
`--base-url` で Responses 互換 gateway も指定できます.
ChatGPT env はサブスクリプションでログインし, API 接続引数は受け付けません.
setup はキーの値を読み書きしません. dry-run は検証と変更予定の表示だけを行い,
接続設定や home を保存しないため, 実生成時にも接続引数を指定してください.

共通設定・MCP は `codex/config.toml`, モデル設定は
`codex/profiles/*.config.toml` を使います. モデル設定の内容は
`model` と `model_reasoning_effort` だけです.
`codex/env-profiles.json` が生成する env の初期候補と既定 profile を定義します.
provider・接続 URL・認証方式は各 env の `config.toml` に生成します.
既定モデルと effort もここに反映するため, Codex の直接起動でも使えます.
profile は公式の設定レイヤーで接続設定を継承するので,
名前に `azure_` / `openai_` を付ける必要はありません.
実際に使えるモデルは接続先とアカウントによります.
[公式の profile 仕様](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles)と
[認証手順](https://learn.chatgpt.com/docs/auth)も参照してください.

```sh
codex-pick                                         # env とモデル設定を同じ一覧から選ぶ
codex-pick -q azure                                # env 列も検索対象
codex-pick --env azure                             # この env 内の profile を選ぶ
codex-pick --env azure -p gpt-6_1-sol_max -- --resume
codex-pick --env openai -p gpt-6_1-sol_max
codex-pick --env account-b gpt-6-astra medium
CODEX_HOME="$HOME/.codex-azure" codex                # env の既定設定で直接起動
CODEX_HOME="$HOME/.codex-envs/account-b" codex login # 別サブスクリプションでログイン
```

`--env` は子プロセスに限って継承した `CODEX_HOME` より優先します.
`--env` が無い場合, 明示した `CODEX_HOME` は候補をその home に限定します.
モデル一覧の取得も選択した home で行います. ピッカーは env と profile の組を
識別し, 同名 profile を引数で指定する場合は `--env` / `CODEX_HOME` が必要です.
API profile の直接指定ではモデルカタログを読みません.
生成済み env の metadata 解析には `jq`, 対話選択には追加で `fzf` を使います.

OpenAI API 用 env の利用前には, 公式 CLI でその home に API キーを保存します.

```sh
printenv OPENAI_API_KEY | CODEX_HOME="$HOME/.codex-openai" codex login --with-api-key
```

PowerShell では対象 home を一時的に `$env:CODEX_HOME` に設定し,
`$env:OPENAI_API_KEY | codex login --with-api-key` を実行してから,
`CODEX_HOME` を元に戻します. 他 env の認証情報・セッション・plugin cache・
project や hook の信頼情報はコピーしません. User skills は既存の
`~/.agents/skills` を通して利用します.

共通設定・モデル設定・rules・hooks を変更したら, 利用する各 env を再生成します.
`--profile gpt-6-luna_max` で env の既定 profile を変更できます.
独立したローカル設定と実行時の状態は保持し, 同じ項目の競合は置換前に検出します.
置換前の管理ファイルはその home 内にバックアップします.
`.dotfiles-env.json` は env 名・provider・接続設定・既定 profile・前回の生成元を
記録するため, 生成ファイルと一緒に保持します. キーの値は保存しません.
管理外の既存ファイルや symlink は置換せず, 生成元の削除だけで生成済みファイルを
削除することもありません.

旧 Azure / OpenAI home は次の setup 実行で metadata を移行します.
保存先・認証・履歴を保持し, 旧 profile ファイルを残したまま新しい中立名の
profile を生成します. ローカル変更は引き継ぐか, 競合として報告します.
`codex-pick -p azure_gpt-6_1-sol_max` のような旧名も別名として使えます.
明示した env と旧名の provider が異なる場合はエラーになります.
従来の `--provider` だけの setup, `--azure-base-url`, `--azure-api-version` も使えます.
旧 `codex/azure_*.config.toml` は互換性のため保持し,
新しいモデル設定は `codex/profiles/` に追加します.

Codex と Claude の env は独立です.
[codex-plugin-cc v1.0.6](https://github.com/openai/codex-plugin-cc/blob/v1.0.6/plugins/codex/scripts/lib/app-server.mjs)
は継承した `CODEX_HOME` の既定設定で `codex app-server` を起動します.

```sh
CODEX_HOME="$HOME/.codex-azure" claude-pick --env account-b
```

同じリポジトリの既存 broker が以前の home を保持する場合があるため,
Codex home の切替前に plugin を利用中の Claude Code セッションを終了してください.

### Claude Code environments

macOS/Linux は `./setup.sh links`, Windows は `.\setup.ps1 links` で,
`~/.local/bin` に `claude-pick` / `claude-pick.ps1` を配置します.
起動処理は Bash / PowerShell 5.1+ です. 対話選択には `fzf` が必要ですが,
引数で指定すれば不要です. status line には Node.js を使います.
env 作成は両 OS とも共有 Node.js 18+ runtime を使い, Claude のインストールは不要です.
名前付き Claude env の作成 (`setup claude`) は symlink を優先します. Windows では
権限不足時にリンク作成を昇格して再試行し, 昇格できない場合や権限不足が続く場合は
コピーへ切り替えます. Developer Mode が有効なら通常権限でリンクを作成できます.
PowerShell の `-Copy`, または Node runtime の `--copy` で新しい共有項目をコピーにできます.
Windows での起動には native `claude.exe` が必要ですが, 権限の昇格は不要です.

Codex と同じく, env の作成・共通リンクの更新は setup, 選択・起動は picker が担います.
名前付き env は明示的に作成し, `setup links` / `setup all` では作成しません.

```sh
./setup.sh claude --env acme --dry-run        # ファイル変更なしで確認
./setup.sh claude --env acme                  # 初期化のみ. ログイン・起動はしない
claude-pick --env acme -- auth login --claudeai
claude-pick --env acme                        # 保存済み設定で起動
claude-pick --env acme opus high -- --resume
claude-pick --env default                     # 既存の ~/.claude を使う
claude-pick                                  # 既存 env を選び, 保存済み設定で起動
```

PowerShell では区切りを `'--'` と引用して
[パーサーに取り除かれないようにします](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing#the-end-of-parameters-token).

```powershell
.\setup.ps1 claude --env acme
claude-pick.ps1 --env acme '--' auth login --claudeai
claude-pick.ps1 --env acme opus high '--' --resume
```

ローカルモデルや gateway は, env の作成と同時に接続設定を指定できます.
接続先は実行時に入力し, setup スクリプトや共通設定には固定しません.
Linux/macOS の例:

```sh
printf 'Gateway URL: '
read -r gateway_url
printf 'Model ID: '
read -r gateway_model
./setup.sh claude --env local --base-url "$gateway_url" \
  --model "$gateway_model" --context-tokens 262144 --dry-run
```

Windows の例:

```powershell
$gatewayUrl = Read-Host 'Gateway URL'
$gatewayModel = Read-Host 'Model ID'
.\setup.ps1 claude --env local --base-url $gatewayUrl `
  --model $gatewayModel --context-tokens 262144 --dry-run
```

コンテキスト長はサーバーで実際に有効な値に合わせてください.
予定を確認してから `--dry-run` を外して再実行すると,
未設定の gateway 認証トークンを非表示で入力できます.
自動化では両 OS とも共有 runtime の
`node setup/claude.js --env local --auth-token-stdin` に直接トークンをパイプで渡します.
トークンそのものをコマンド引数には渡しません.
dry-run はトークンを読み取らず, 接続設定の値を表示せず, サーバーにも接続しません.

接続先には Anthropic Messages (`/v1/messages`) が必要です.
その形式を提供しない OpenAI 互換サーバーでは, 変換 gateway を使います.
Claude 以外のモデルでは, ツール呼び出し・ストリーミング・要約・
thinking/effort の対応を実際のサーバーで確認してください.

作成後は `claude-pick --env local` (Windows は `claude-pick.ps1 --env local`),
または `claude-pick` の一覧から `local` を選ぶだけで起動します.
接続設定は `~/.claude-envs/local` 内だけに保存し, 再設定で省略した項目は保持します.
1 モデルの gateway として, Fable/Opus/Sonnet/Haiku の別名も指定モデルに揃えます.
生成元の記録にはトークンを含めません. env 固有の `settings.json` と
そのローカルバックアップにはトークンを含むため, env は Git 管理外に置きます.
トークンの更新は, 同じ env に `--auth-token-stdin` を指定して再実行します.

旧 `-p` / `--profile` は `--env` の別名です.
旧 `--create-env` / `--create` は移行メッセージを出して setup に委譲し,
従来どおり既存 env の作成は拒否します.
名前付き env の保存先は `~/.claude-envs/<名前>` です.
名前は英小文字で始まる 1〜64 文字の英小文字・数字・`_`・`-` で,
`default` と Windows のデバイス名は予約名です.
picker には既存 env の選択だけを表示し, 名前付き env が無ければ `default` を表示します.
存在しない名前はエラーにし, 選択のキャンセルでは起動しません.
リンク配置前は `./tools/claude/claude-pick` /
`.\tools\claude\claude-pick.ps1` から実行できます.
従来の Zsh wrapper が追加していた共通 MCP 設定は `--env default` で使えます.
公式の `claude` は直接実行でき, `claude-raw` も利用できます.

共通設定を変更した場合は `./setup.sh claude --env acme` を再実行します.
設定を再生成し, 導入済みの全 dotfiles user skill へのリンクを配置します.
env ごとの skill 選択は不要です.
個別設定・履歴・MCP 設定・ローカル skill は保持します.
設定の競合や共通リンク先との競合では書き込み前に停止し,
未管理・作成途中のディレクトリは引き継ぎません.
`default` の配置には従来どおり `setup links` を使います.

env だけの選択では model/effort 選択を省略します. どちらかを指定すると
残りを選択し, `keep` なら保存済みの設定を使います.
`-m MODEL` / `-e EFFORT` も利用できます. effort は `low`, `medium`, `high`,
`xhigh`, `max` で, 対応範囲はモデル・バージョンによります.
選んだ effort は子プロセスの `CLAUDE_CODE_EFFORT_LEVEL` にも反映します.
`--` 以降は Claude に渡すため, Claude の `-p` / `--print` はここに書きます.
`auth` などの管理コマンドでは model/effort を選びません.
このランチャーに保存済みのモデル profile 機能はなく, model/effort を直接指定します.

| env 内の項目 | 扱い |
| --- | --- |
| `settings.json` | `claude/settings.json` から生成. 再実行で共通設定の更新と個別変更をマージ |
| `rules/00-global.md`, `rules/10-claude.md` | `ai-rules/` の共通ソースへのリンクまたは管理対象のコピー |
| `statusline.cjs` | 共通 renderer へのリンクまたは管理対象のコピー. 選択した env 名を表示 |
| `skills/` | env 固有の実ディレクトリ. 導入済みの全 `.agents/user/skills` 定義へのリンクまたは管理対象のコピー |
| `mcp.json` | 任意の env 固有 MCP 設定. 明示した `--mcp-config` が優先 |
| `claude-mem/` | 新規 env 専用の記憶保存先. worker の loopback ポートも個別に割り当て |
| ログイン・履歴・メモリ・plugins | 選択した保存先で Claude が個別管理 |

正本は dotfiles の `claude/settings.json` です. 共通の使い勝手の設定に加え,
hooks・plugin の有効化・marketplace 定義も生成内容に含みます.
各 env は通常ファイルを持ち, 個別に編集しても正本や別 env には影響しません.
`.dotfiles-env.json` に前回の共通設定を記録し, 別の JSON キーへの変更はマージします.
同じ値や配列を両方で変更すると競合として停止します.
置換前の設定と記録は `.dotfiles-claude-backups/` に保存します.
記録ファイルは env と一緒に保持してください. 更新中の別プロセスによる保存を確認し,
書き込みに失敗すると元のファイルを復元します. 復元中にも変更された場合は
その変更を保持して, 復旧用ファイルの場所を表示します.

記録のない旧 env は, 移行用に保持した旧 `claude/profile-settings.json` を基準に,
既存の個別変更を優先しながら共通設定を追加します.
既存 default の認証情報・履歴・メモリ・plugin cache はコピーしません.
新規 env では `CLAUDE_MEM_DATA_DIR` に env 内の `claude-mem/` を設定し,
`CLAUDE_MEM_WORKER_HOST` は `127.0.0.1`, `CLAUDE_MEM_WORKER_PORT` は
37800 以降から未使用のポートを自動割当します. 既存 env・記憶設定と使用中のポートを確認し,
作成完了まで選択したポートを確保するため, 同時作成でも重複しません.
同じ 3 項目を `claude-mem/settings.json` にも保存し, DB と検索インデックスは
plugin の初回利用時に新しく作成します. dry-run では保存先と予定ポートを表示します.
再実行では既存の記憶設定を保持し, 旧 env や default の保存先は自動移行しません.
他の独自保存先を持つ plugin は個別に設定が必要です. `CLAUDE_CONFIG_DIR` だけでは移動しません.

共通 skill 定義の編集は symlink を通じて反映されます. コピーの場合は隣接する
`.dotfiles-copy-*.json` に生成元のパスと内容のハッシュを記録するため, env と一緒に保持します.
`setup claude --env NAME` の再実行でコピーを更新できます. ローカルだけの編集は保持し,
生成元とコピーの両方が異なる内容へ変更された場合は書き込み前に競合として停止します.
管理情報のない既存ファイルは引き継ぎません.
user scope の `setup skills` は, `claude-code` を選択した場合 (既定値),
既存の管理対象 env すべてにも不足している skill リンクを追加します.
`SETUP_DRY_RUN=1` で予定を確認でき,
`SETUP_SKIP_USER_AGENT_SKILL_LINKS=1` でリンク追加を省略できます.
env の設定は変更せず, 同名のローカル項目があれば警告して保持します.
共有元が消えても既存リンクやローカル skill は自動削除しません.
`skills/synced/` などアカウントから同期されるデータは env 内に残します.
未導入の状態では共有 skill は空です. `setup skills` で復元すると env のリンクも追加されます.
旧 `--skill NAME` は導入済みかの確認として受け付け, 共有する skill の絞り込みは行いません.

名前付き env では `tools/claude/auth-env.txt` の認証・接続先の環境変数を検出すると
値を表示せずに停止します. 呼び出し元で対象変数を解除してください.
`default` は従来の環境変数を維持します.
`CLAUDE_CONFIG_DIR` と表示用の `CLAUDE_PICK_ENV` は子プロセスだけに設定し,
明示した `--env` を継承済みの config directory より優先します.
`CLAUDE_PICK_PROFILE` も互換用の表示ラベルとして設定します.
これはユーザー設定・状態の分離であり, OS のセキュリティ境界ではありません.
プロジェクト設定・管理ポリシー・外部 plugin の保存先は別途適用されます.
公式の[環境変数](https://code.claude.com/docs/en/env-vars)と
[認証の優先順位](https://code.claude.com/docs/en/authentication#authentication-precedence)も参照してください.

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

`pwsh` がある場合 (mise が Linux, WSL, macOS に `powershell` を入れます),
`tests/powershell.bats` が全ての `.ps1` の構文を確認し, `tests/setup_windows.ps1` を
Windows の API が必要なケースを除いて実行します.

Claude setup / picker の確認は一時 HOME と偽の Claude コマンドを使い,
ログイン・API 呼び出しは行いません.

```bash
node --test setup/test/claude.test.mjs
bats tests/claude_pick.bats tests/claude_wrapper.bats
shellcheck tools/claude/claude-pick tests/claude_pick.bats tests/claude_wrapper.bats
```

native Windows では PowerShell 5.1 以降で `.\tests\claude_pick.ps1` を実行します.
Node.js と Windows PowerShell 組み込みのコンパイラで確認用の実行環境を用意し,
setup・引数・プロセスの動作を確認します. symlink 権限が無い場合は管理対象のコピーで
作成します. UAC は模擬処理に置き換えているため, テスト中に昇格を要求しません.

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
