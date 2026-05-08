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
~/.dotfiles/setup.sh skills --scope project --profile base,office --agent codex
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
    office.json
    azure.json
    frontend.json
    browser.json
    data.json
    research.json
    docs.json
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
  "includes": ["base"],
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

## 初期 Profile

### `base`

多くのリポジトリで共通して使う workflow skill。

含めるもの:

- `find-skills`
- `using-superpowers`
- `brainstorming`
- `grill-me`
- 計画、debug、TDD、verification、code review 系の workflow skill
- `skills/local/` 配下の自作 GitHub workflow skill
- repository onboarding と runtime isolation の local skill

### `office`

Office/document 系:

- `docx`
- `pdf`
- `pptx`
- `xlsx`

### `azure`

現在の curated set から選ぶ Azure 関連:

- `azure-*`
- `appinsights-instrumentation`
- `azure-devops-cli`

利用価値がある Azure skill だけを明示的に入れ、利用可能な Azure skill を機械的に全部入れないようにします。

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

Bash は公開 entry point として維持し、profile 解決と metadata 生成は小さな Node helper に寄せます。

想定 helper:

```text
setup/skills-profile.js
```

Bash の責務:

- setup flag の parse
- setup path の解決
- 外部 skill 用の `npx skills add` 実行
- user scope の最終 link 作成

Node helper の責務:

- profile JSON の読み込みと validation
- `includes` の展開
- source ごとの external skill merge
- local skill 名の validation
- `.agents/skills-profile.json` の出力
- Bash が実行しやすい安定した install plan の生成

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

既存の `skills-lock.json` を置き換える場合は、事前に backup を作ります。Git の dirty state は warning に留め、実行自体は止めません。

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
