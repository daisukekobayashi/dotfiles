# Skills Profile 設計

このドキュメントは、この dotfiles リポジトリで予定している skill 管理モデルを記録するものです。

## 目的

- global に見える skill を小さく保つ。
- リポジトリ固有の作業には project scope の skill を使う。
- よく使う skill 群は dotfiles 内で curated profile として管理し、リポジトリごとに再調査しなくて済むようにする。
- 外部 skill はできるだけ公式の `skills` CLI の挙動に寄せる。
- 自作 local skill の正本は dotfiles に置く。

## Scope

### Project Scope

Project scope は、通常のリポジトリ作業で使う基本形です。

Git リポジトリ内のどこから実行しても、`git rev-parse --show-toplevel` でリポジトリ root を解決します。

想定コマンド:

```sh
~/.dotfiles/setup.sh skills --scope project --profile office
~/.dotfiles/setup.sh skills --scope project --profile base,github --agent codex
~/.dotfiles/setup.sh skills --scope project --profile base,beads
~/.dotfiles/setup.sh skills --scope project --profile base,azure-devops
~/.dotfiles/setup.sh skills --scope project --profile workbench
```

Project scope では `--profile` を必須にします。未指定の場合は、暗黙の default を入れずにエラーにします。

外部 skill はリポジトリ root で公式の `skills` CLI を使ってインストールします。生成される外部 skill 実体と root の `skills-lock.json` は CLI に管理させます。

自作 local skill は `skills-lock.json` には入れません。dotfiles から、選択した agent の project skill ディレクトリへ symlink します。

Project scope の出力:

```text
repo/
  skills-lock.json          # 外部 skill 用。skills CLI が生成
  .agents/
    skills/                 # Codex project skills
    skills-profile.json     # dotfiles 独自の profile metadata
  .claude/
    skills/                 # Claude Code project skills
```

`.gitignore` は自動更新しません。`.agents/skills/` と `.claude/skills/` は生成物または link 先なので、通常は ignore 候補であることだけをログで案内します。

### User Scope

User scope は通常のリポジトリ向けではなく、dotfiles の bootstrap 用の特殊な mode です。

`./setup.sh skills` は user scope のコマンドとして維持し、次と同等に扱います。

```sh
./setup.sh skills --scope user --profile base --agent codex --agent claude-code
```

User scope では dotfiles 管理の user skill view を 1 つ作り、ユーザーの agent config ディレクトリからそこへ link します。

```text
~/.dotfiles/.agents/user/skills/
~/.dotfiles/.agents/user/skills-profile.json
~/.agents/skills  -> ~/.dotfiles/.agents/user/skills/
~/.claude/skills  -> ~/.dotfiles/.agents/user/skills/
```

User profile を変更した場合は、profile の組み合わせごとに別 view を持つのではなく、この 1 つの user skill view を作り直します。選択した profile は `skills-profile.json` に記録します。

Codex の user skill は、OpenAI の Codex skills docs に合わせて `$HOME/.agents/skills` を使います。`skills` CLI 側の global Codex path が異なる場合でも、それには依存しません。

## Dotfiles Layout

目標の layout:

```text
skills/
  local/
    github-pr-create/
    github-issue-start/
    ...
  profiles/
    base.json
    github.json
    office.json
    azure.json
    azure-devops.json
    beads.json
    frontend.json
    browser.json
    data.json
    research.json
    docs.json
    workbench.json
```

自作 skill は `skills/local/<name>` に置きます。

### GitHub ワークフローの構成

Issue の仕事には、必要に応じて `github-issue-create`、
`github-issue-triage`、`github-issue-review`、`github-issue-start` を使います。
`start` は独立した worktree を準備し、実装まで進めます。
`github-worktree-cleanup` は安全確認と承認を経て、完了した仕事のローカル
worktree とブランチを削除します。

`github-pr-create` は公開済みブランチから PR を作成または再利用し、
`github-pr-publish` は検証・commit・push・PR 作成を担当します。
`github-pr-review` は読み取り専用のレビューです。AI レビュー依頼は
`$github-pr-review-request #123 codex`、`copilot`、`both` で対象を指定します。
対象ごとの手順は、このスキルの `references/` に置きます。

`github-pr-publish-and-ai-review-request` は公開と両方へのレビュー依頼を
組み合わせます。`github-pr-codex-review-cycle` は公開、Codex への依頼、
1回のレビュー待機、`github-pr-ai-review-followup` による修正準備、検証済み
修正の公開、Writeback フェーズによる返信・解決を順に行います。修正後の
再レビュー依頼は自動では行いません。複合スキルは順序と引き継ぎを担当し、
個別の処理手順は基本スキルに集約します。

外部 skill 用の pool/catalog ファイルは追加しません。Profile が curated external skill group の正本になります。

Root の `skills-lock.json` は、この移行後は global な全 skill catalog としては扱いません。dotfiles リポジトリ自身で project-scoped skill が必要な場合は、他の project と同じように root の `skills-lock.json` を生成します。

## Profile Format

Profile は JSON にします。Bash で無理に parse せず、Node で処理できるようにします。

例:

```json
{
  "description": "Office document skills",
  "external": [
    {
      "source": "anthropics/skills",
      "skills": ["docx", "pdf", "pptx", "xlsx"]
    }
  ],
  "local": []
}
```

ルール:

- `includes` は他の profile 名を持つ。
- `external[].source` は `npx skills add` に渡す `owner/repo`。
- `external[].skills` は、その source 内の skill 名。
- `local[]` は `skills/local/` 配下の名前。
- `includes` は union として展開する。
- 重複 skill は無視する。
- 循環 include はエラーにする。
- 存在しない profile、存在しない local skill、不正な external entry はエラーにする。
- domain profile は原則として独立させる。`base` が必要な場合は明示的に組み合わせるか、`workbench` のような集約 profile を使う。

## 初期 Profile

### `base`

多くのリポジトリで共通して使う provider-neutral な workflow skill.

含めるもの:

- `find-skills`
- 公開済みの Matt Pocock Engineering / Productivity skill 一式
- repository onboarding、`review-change`、`adversarial-review`、runtime isolation の local skill
- `git-commit`

Matt Pocock の `misc`、`personal`、`in-progress`、`deprecated` skill は含めません。
Superpowers は `base` に含めません。

以前の GitHub 対応込みの baseline が必要な場合は `base,github` を使います.

### `pstack`

Lauren Tan の pstack を、この環境の作業範囲と承認ルールに合わせた9つの local skill。
`base`・`github` から独立した profile で、外部パッケージ、プラグインの hook、
モデル設定、既定の自動ルーティングは追加しません。既存の `tdd`・`teach` は維持します。

| Skill | 責務 |
|---|---|
| `how` | 現在の実行経路・データフロー・責任の所在を読み取り専用で説明する。 |
| `why` | Git・PR・Issue・ADRから設計理由を調べ、記録と推測を区別する。読み取り専用。 |
| `architect` | 呼び出し側の使い方と契約を設計する。実装への移行は元の依頼範囲に従う。 |
| `arena` | 共通基準で独立した候補を比較する。書き込み先を分離し、統合結果を検証する。 |
| `interrogate` | 独立したレビューを読み取り専用で行い、根拠に基づいて統合する。 |
| `blast-radius` | 明示起動で、安全性を支える前提を隔離した実験で確かめる。実装修正は行わない。 |
| `create-verification-skill` | プロジェクト固有の検証手順と feature map を作り、その手順を実行確認する。 |
| `prove-it-works` | 完了の主張と観測した挙動を対応させる共通原則。 |
| `encode-lessons-in-structure` | 根拠のある再発パターンを、型・テスト・既存の検査などで防ぐ共通原則。 |

呼び出し例は `$how この処理の経路を説明して`、`$why この状態を永続化した理由は？`、
`$architect このインターフェースを設計して`、`$arena この案を比較して`、
`$interrogate この変更をレビューして`、`$blast-radius このスキーマ変更を検証して`、
`$create-verification-skill このCLIの検証手順を作って`。
Claude Code では、その環境の skill 呼び出し方法を使います。
共通原則2つは直接参照するほか、各 workflow skill から必要に応じて読みます。

`arena`・`interrogate`・`blast-radius`・`create-verification-skill` は
ユーザーによる明示起動に限定します。description と本文に加え、Codex には
`policy.allow_implicit_invocation: false`、Claude Code には SKILL.md の
frontmatter に `disable-model-invocation: true` を設定します。
Codex では `$skill-name`、Claude Code では `/skill-name` で呼び出します。
他の skill からの参照だけでは起動しません。`architect` は、ユーザーが
`arena` を明示起動した場合を除き、自身で設計案を比較します。

`how`・`why`・`architect` はタスクの description に従って選択できます。
共通原則2つは、必要な場面や他の workflow から参照します。
登録されている全 skill を毎回実行する構成ではありません。
候補・レビューの並列実行は条件と上限を設け、利用できない場合は独立性の限界を明示します。

`architect` は利用可能な `codebase-design` の設計語彙を参照し、明示依頼された
事前確認は `design-preflight` に任せます。`interrogate` は利用可能な
`review-change`・`adversarial-review` の観点を参照しますが、明示起動限定の
workflow 自体は呼び出しません。`pstack` 単独でも使える最小限の代替基準を持ちます。
読み取り専用の調査・レビュー、実験による検証、修正の責務を分けます。
commit・push・依存関係・外部書き込み・破壊的操作の承認は、ユーザーの指示に従います。

live なリンクの正本にする checkout へソースを反映してから実行します。

```sh
./setup.sh skills profile validate --profile base,github,pstack
SETUP_DRY_RUN=1 ./setup.sh skills --scope user --profile base,github,pstack
./setup.sh skills --scope user --profile base,github,pstack
```

User scope は共通 view を作り直すため、維持したい profile をすべて指定します。
`pstack` 自体は local skill のみですが、組み合わせた `base` は外部の skills CLI を
実行する場合があります。実行計画と必要な承認を確認してください。
後で削除する一時 worktree から live な user link を作らないようにします。
Project scope では `--scope project --profile base,pstack` を使えます。

共通の生成手順は user scope に置き、生成した検証コマンド・feature map・再利用する
helper は対象プロジェクトの skill ディレクトリに置きます。生成した手順は実行確認まで
draft とし、検証済み範囲は実際に通した経路に限定します。実行ごとの証拠は ignore された
一時領域に保存し、プロセス終了後も残します。

参照した上流リビジョンは
[`12d587dfb20741cafc376c42c696c5f6e2a64487`](https://github.com/cursor/plugins/tree/12d587dfb20741cafc376c42c696c5f6e2a64487/pstack)。
各 skill に出典リンク・ローカルでの調整理由・Lauren Tan の MIT license を含めます。
上流の `principle-prove-it-works` と `principle-encode-lessons-in-structure` は、
ローカルでは接頭辞を省略しています。自動同期するプラグイン fork ではなく、
上流の変更とローカルの契約を照合して更新する構成です。

### `github`

GitHub workflow skill:

- `gh-cli`
- `skills/local/` 配下の自作 GitHub issue, pull request, AI review, merge cleanup skill

Azure DevOps provider profile では, GitHub の `issue` skill に相当するものを `work-item` skill として扱います.

### `beads`

Beads workflow skill:

- `beads-issue-create`
- `beads-issue-triage`
- `beads-issue-worktree`
- `beads-merge-cleanup`

`bd`/Beads で作業を追跡するリポジトリでは `base,beads` を使います.

### `workbench`

広めのリポジトリ作業向けの標準 workbench profile。

含めるもの:

- `base`
- `docs`
- `browser`
- `research`

### `office`

Office/document 系:

- `docx`
- `pdf`
- `pptx`
- `xlsx`

### `azure`

現在の curated set から選ぶ Azure cloud/resource management 関連:

- `azure-*`
- `appinsights-instrumentation`

利用価値がある Azure skill だけを明示的に入れ, 利用可能な Azure skill を機械的に全部入れないようにします.

### `azure-devops`

Azure DevOps workflow skill:

- `azure-devops-cli`
- `azure-devops-common`
- `azure-devops-work-item-create`
- `azure-devops-work-item-review`
- `azure-devops-work-item-triage`
- `azure-devops-work-item-worktree`
- `azure-devops-pr`
- `azure-devops-pr-publish`
- `azure-devops-pr-review`
- `azure-devops-merge-cleanup`

`azure-devops` は `azure` から独立しています. Azure DevOps リポジトリでは `base,azure-devops` を使います. 同じリポジトリで Azure cloud/resource 作業も必要な場合だけ `base,azure,azure-devops` を使います.

Azure DevOps の AI review request/follow-up skill は, 初期対応では意図的に含めません.

GitHub と Azure DevOps の workflow 対応:

| GitHub skill | Azure DevOps skill |
|---|---|
| `github-issue-create` | `azure-devops-work-item-create` |
| `github-issue-review` | `azure-devops-work-item-review` |
| `github-issue-triage` | `azure-devops-work-item-triage` |
| `github-issue-start` | `azure-devops-work-item-worktree` |
| `github-pr-create` | `azure-devops-pr` |
| `github-pr-publish` | `azure-devops-pr-publish` |
| `github-pr-review` | `azure-devops-pr-review` |
| `github-worktree-cleanup` | `azure-devops-merge-cleanup` |

### `frontend`

Frontend、UI、React、Tailwind、SEO、Remotion、web design 系。

Browser automation は frontend 開発以外でも使うため、ここにはデフォルトでは含めません。

### `browser`

Browser automation/debugging 系:

- `agent-browser`
- `browser-use`
- `chrome-devtools`
- `playwright-cli`

### `data`

Data/database 系:

- `redis-development`
- `supabase-postgres-best-practices`

### `research`

Research 固有の skill:

- `read-arxiv-paper`

### `docs`

Documentation lookup や library docs 参照系:

- `context7-cli`

## CLI Behavior

Profile ベースの skills setup は TypeScript を正本にします。bootstrap 時に TypeScript runtime を要求しないよう、生成済みの Node runtime を commit します。

Runtime entry point:

```text
setup/skills.js
```

TypeScript source:

```text
setup/src/skills.ts
```

Bash と PowerShell の責務:

- setup path と環境変数の解決
- `node setup/skills.js` の起動

Node runtime の責務:

- skills flag の parse
- profile JSON の読み込みと validation
- `includes` の展開
- source ごとの external skill merge
- local skill 名の validation
- 外部 skill 用の `npx skills add` 実行
- local skill の link 作成
- project output の backup と rollback
- `.agents/skills-profile.json` の出力
- user scope の最終 link 作成

Profile add/remove の補助コマンドは初期実装の対象外にします。Profile JSON は手で編集し, `./setup.sh skills profile validate` で検証します。

## External Skills

Project scope では公式 CLI を使います。

```sh
npx skills add <owner/repo> \
  --skill <name> \
  --agent codex \
  --agent claude-code \
  --copy \
  --yes
```

これはリポジトリ root で実行し、`skills-lock.json` と agent ごとの project output path は CLI に管理させます。

既存の `skills-lock.json` や agent skill directory を置き換える場合は、事前に backup を作り、install に失敗したら復元します。Install が成功した場合は、選択した profile で再作成されなかった既存の agent skill entry を戻します。Profile 管理の skill と同じ名前の entry は、profile 管理版に置き換えます。Git の dirty state は warning に留め、実行自体は止めません。

## Local Skills

Local skill は `skills/local/<name>` に置き、dotfiles が正本です。

Project scope では、選択した agent の project skill ディレクトリに local skill を symlink します。

```text
repo/.agents/skills/<name> -> ~/.dotfiles/skills/local/<name>
repo/.claude/skills/<name> -> ~/.dotfiles/skills/local/<name>
```

User scope でも、生成した user profile view 内に local skill を symlink します。

Target path がすでに存在し、それが dotfiles 管理の symlink ではない場合は、上書きせずエラーにします。

## Agents

Profile selection と agent selection は分離します。

Default agents:

```text
codex
claude-code
```

例:

```sh
~/.dotfiles/setup.sh skills --scope project --profile office
~/.dotfiles/setup.sh skills --scope project --profile office --agent codex
```

## Metadata

Dotfiles 独自の project metadata は次に書きます。

```text
repo/.agents/skills-profile.json
```

Metadata に記録するもの:

- requested profiles
- expanded profiles
- selected agents
- external install plan
- local skill links
- 必要なら generator name/version

Dotfiles 独自 metadata は `skills-lock.json` には入れません。
