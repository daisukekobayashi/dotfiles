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
    github-pr/
    github-issue-worktree/
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
- `using-superpowers`
- `brainstorming`
- `grill-me`
- 計画, debug, TDD, verification, code review 系の workflow skill
- repository onboarding と runtime isolation の local skill
- `git-commit`

以前の GitHub 対応込みの baseline が必要な場合は `base,github` を使います.

### `github`

GitHub workflow skill:

- `gh-cli`
- `skills/local/` 配下の自作 GitHub issue, pull request, AI review, merge cleanup skill

Azure DevOps provider profile では, GitHub の `issue` skill に相当するものを `work-item` skill として扱います.

### `beads`

Beads workflow skill:

- `beads-issue-create`
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
| `github-issue-worktree` | `azure-devops-work-item-worktree` |
| `github-pr` | `azure-devops-pr` |
| `github-pr-publish` | `azure-devops-pr-publish` |
| `github-pr-review` | `azure-devops-pr-review` |
| `github-merge-cleanup` | `azure-devops-merge-cleanup` |

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
