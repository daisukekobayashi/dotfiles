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
~/.dotfiles/setup.sh skills --scope project --profile base --copy
```

```powershell
.\setup.ps1 skills --scope project --profile base
.\setup.ps1 skills --scope project --profile base -Copy
```

Project scope では `--profile` を必須にします。未指定の場合は、暗黙の default を入れずにエラーにします。

外部 skill は、project 外の private なステージングディレクトリで公式の `skills` CLI を実行してインストールし、生成された `skills-lock.json` と agent skill ディレクトリを project に移動します。

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

`synced/` 配下の外部同期スキルは user skill view の再生成時に引き継ぎます。プロファイル管理のスキルは選択した構成で再生成します。`synced` と `anthropic-skills` は大文字小文字を問わず予約名です。どちらかを local skill または external skill として宣言した profile は、どの scope でも `profile validate` とインストールが `Invalid or reserved skill name: <name>` で失敗します。インストールがどちらかの名前 (大文字小文字を問わない) のトップレベル entry を生成した場合、user scope では `skill entry collision in user staging: <entry> (<source>, reserved name)` で失敗して user view を入れ替えず、project scope では `skill entry collision in project install: <entry> (<source>, reserved name)` で失敗して project を復元します。

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
worktree とブランチを削除します。リモートブランチの先頭がマージ済み PR の
head と一致する場合は、その削除も提案します。

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

`github-issue-delivery` は、独立 worktree、各 issue の `shared-understanding`、
`design-preflight-with-docs`、実装、
2種類のローカルレビュー、PR の Codex レビュー対応、承認後のマージ、承認後の
ローカル cleanup までをまとめます。Claude Code では
`/github-issue-delivery 12 36`、Codex では `$github-issue-delivery 12 36` のように
呼び出します。前提スキルを揃えるには `base,github` を使います。
どちらのホストも `change-review` と `change-adversarial-review` スキルを使い、
それぞれ現在のホストの新しい subagent で実行して独立性の低下を報告します。
Claude Code での導入済み Codex plugin の読み取り専用 `task` ランタイムなど、
別のツールはユーザーが明示的に指定した場合だけ使います。
ユーザーが一括フローを明示依頼した場合は preflight、local review、
PR サイクルへの委譲も含みます。自動検出だけではこれらを実行しません。
各 issue の worker が issue とコードを読み、shared understanding と、推奨回答つきの
preflight の質問を草稿にします。コーディネーターは草稿を検証し、issue ごと、
論点ごとに1つずつユーザーに質問します。subagent がユーザーに直接質問することは
ありません。worker が既定値で決めるのは実装上の戦術だけで、契約、境界、互換性、
セキュリティの判断は質問として返し、選んだ既定値はすべて報告します。delegation
が使えない場合は、コーディネーター自身が草稿を作って質問します。
有用な指摘の修正後は上限内で再レビューし、再開用の進捗は追跡対象の文書に
混ぜません。マージと cleanup はそれぞれ対象を示して確認します。
ローカルのブランチレビュー前に行う checkpoint commit にも既存の承認条件を
適用します。単独の PR レビューサイクルは従来どおり1回のレビューを担当し、
繰り返しと最終的な完了確認は delivery スキルが担当します。

ローカルの `change-review` と `change-adversarial-review` は、OpenAI plugin の
レビューコマンドを移植したものが元になっており、現在は独自のレビュー規則を
含みます。各定義に出典と比較済みコミットを記録します。
明示起動限定の `change-security-review` は、両者と同じ対象選択と指摘タグを使い、
OpenAI の `codex-security` の diff レビュー手順を参考に、変更が持ち込む悪用可能な
脆弱性を確認します。レビュー対象の base に `SECURITY.md` があれば、脅威モデルの
ポリシーとして読みます。
3つのレビューはいずれも、base のルートに `REVIEW.md` があればレビュー方針として読みます。
通常レビューと adversarial レビューでは重点の絞り込みや対象外パスの指定に使えますが、
sensitive path を対象外にしたり、material やセキュリティの基準を下げたりはできません。
delivery フローでは、変更のリスク tier が High のとき、
または diff が sensitive path に触れるときに3番目のローカルレビューとして実行します。
リポジトリはルートの `AGENTS.md` の `## Delivery sensitive paths` セクションで、
既定の sensitive path を追加または除外できます。このリポジトリは `delivery-common`、`*-delivery`、`change-*review` と、ローカルやリモートのリソースを削除する skill や GitHub、Azure DevOps に書き込む skill（worktree、runtime、beads merge の cleanup skill、GitHub と Azure DevOps の PR skill、`azure-devops-common`、issue と Work Item の create skill と start skill）を除く `skills/` 配下の Markdown を除外します。
`delivery-common` のリスク tier（Low、Medium、High）は作者ではなく変更から決まり、
tier ごとの1つの表でレビューの量を決めます。preflight の深さ、ローカルレビューの reviewer と
ラウンド上限、hosted レビューのラウンド数、マージと cleanup の確認をまとめるかどうか、
PR 公開前とマージ確認時に提示する推奨の人間レビュー（AI のみ、1名、複数名）です。
Low の変更は短い preflight の読み上げ確認、`change-review` のみ、hosted レビュー1回、
PR のマージと事前に確認した cleanup 対象を1度にまとめた確認になり、Medium と High は
2つの reviewer によるローカルレビューを続けます。delivery の中で記録された最も重い tier が
適用され、手順が途中で軽くなることはありません。tier は PR 本文には書かず、push、マージ、
cleanup の明示的な承認はどの tier でも必要です。Matt Pocock 版の `code-review` は規約・仕様の2軸で
確認したい場面向けに残し、delivery の標準レビューには使いません。

外部 skill 用の pool/catalog ファイルは追加しません。Profile が curated external skill group の正本になります。

Root の `skills-lock.json` は、この移行後は global な全 skill catalog としては扱いません。dotfiles リポジトリ自身で project-scoped skill が必要な場合は、他の project と同じように root の `skills-lock.json` を生成します。

### Delivery ポリシーの階層

delivery スキルは、共通のポリシー層と薄いプロバイダー別アダプターに分けます。

- `delivery-common` は、両方のプロバイダーに共通する delivery のポリシー、つまり
  何を、いつ、どの深さで行うかの置き場所です。リスク tier、レビューの選択、
  完了とマージのゲート、人間レビューの推奨と承認が必要になる時点が含まれます。
- プロバイダー別の delivery スキル（`github-issue-delivery` と
  `azure-devops-work-item-delivery`）は、各フェーズをそのプロバイダーでどう実行するかを
  担当します。PR の作成と公開、API や CLI の呼び出し、ホスト側のレビューサイクル、
  Work Item のリンクや状態遷移などのプロバイダー固有の状態が含まれます。共通の
  ポリシーは書き直さずに `delivery-common` を参照し、承認は `github-pr-publish` など
  呼び出す各スキルに委ねます。承認ルールはそれぞれのスキルが持ちます。
  hosted レビューのラウンド上限を含む tier ごとのレビュー量は、リスク tier の表にある
  共通のポリシーです。Codex のトリガーや material な差分の判定のように、hosted
  レビューの実行方法と差分に次のラウンドが必要かの判断は、プロバイダーのスキルに残します。

`delivery-common` は、Worker Dialogue（start スキルによる worker の割り当て、worker が
shared understanding と design preflight を草稿にし、コーディネーターがユーザーに
質問する流れ、preflight と実装への引き継ぎ）、ローカル
レビュー手順（snapshot の固定、follow-up 候補の記録を含む指摘の評価、focused
follow-up、reviewer の選択、ローカルレビューの full review への切り替え条件、完了
条件、ラウンドの数え方と上限、head と coverage の記録）、リスク tier、Delivery
Completion（進捗記録、再開、公開前とマージ確認時に示す decision summary、公開後の
公開 head の確認と次への進行、マージ確認で示す内容、delivery の上限と
停止条件、最終報告と `Complete` の条件、delivery 終了時の follow-up 候補の報告と
作成）を持ちます。その `SKILL.md` では、hosted レビューの実行方法と承認は呼び出し
元のワークフローが持つとしています。その Delegated Authorization の節は、呼び出し元が
ユーザーの依頼、正確な対象、既存の承認を呼び出すスキルに渡す方法を1か所で定めます。
両方のプロバイダーの PR スキル、レビュー依頼スキル、delivery スキルはこれにリンクし、
それぞれ自身の承認モデルを持ちます。その Missing Prerequisites の節は、必要な
スキル、reviewer、ツールが欠けているとき、それを必要とするフェーズを対象の task
について止めてブロッカーとして報告し、インストール、代替、省略はしないことを1か所で
定めます。両方のプロバイダー別 delivery スキルとローカルレビュー手順はこれにリンク
します。その Optional Workflows の reference は、その唯一の例外を1か所で定めます。
optional workflow はインストールされていてトリガーが成り立つときに実行し、それ以外は
理由を添えて `not run` と報告してフェーズを続けます。共通の上限（トリガーと tier
の条件、レビューした head またはフェーズの入力ごとに1回まで、時間の上限、ローカル
レビューのラウンド上限の内側で数える、ユーザーの上限や opt-out を優先する）に従い、
registry に各 workflow を載せ、各 worker summary は `Optional workflows:` に
その状態を書きます。その Phase Delegation の reference は、実装後のコンポーネントスキルの
呼び出し（公開、hosted レビューのサイクル、cleanup の事前確認、cleanup）を
コーディネーターがエージェントに渡し、ユーザーとの対話、指摘の評価、マージは自身で
持つことを1か所で定めます。両方のプロバイダー別 delivery スキルはこれにリンク
します。共通の記述はプロバイダーに依存せず、task と
task の完了（task closure）という言葉を使い、呼び出し元のワークフローが項目を追加
する箇所を示します。各プロバイダー別スキルは、GitHub の hosted レビューの結果や
Azure DevOps の Work Item 状態遷移の提案など、追加する項目だけをリンクの横に
書きます。

共通の delivery ポリシーは `delivery-common` に置き、プロバイダー別 delivery
スキルで書き直すことはずれとして扱います。両方のプロバイダーに当てはまるポリシー
変更は `delivery-common` を1回だけ編集し、`delivery-common/SKILL.md` の担当範囲の
記述と frontmatter の `description` もそれに合わせて更新します。片方のプロバイダー
にしかないポリシーはプロバイダー別スキルに残します。両方のプロバイダー別スキルは、
テストが固定している短い記述を1つだけ、ローカルの安全確認として意図的に残します。
再開時の段落で、記録されたブランチをコマンドで使う前に、共有の安全なブランチ名
チェック（[共有スクリプト](#共有スクリプト)）を1行で実行する確認です。再開のそれ以外の
手順は Delivery Completion に置き、shared understanding の状態の確認は Worker
Dialogue だけに置きます。

Azure DevOps 版との同等性を標準とします。`delivery-common` のポリシーは両方の
プロバイダーに自動的に適用されます。一方のプロバイダーでの変更が、もう一方の
スキルにもプロバイダー固有の変更を必要とする場合は、同じ issue と PR で行います。
Azure DevOps 側を後回しにできるのは、Azure DevOps の API やポリシーなど Azure 固有の
調査が必要な場合だけで、その場合も追跡用の follow-up issue を作成します。
意図的なプロバイダー差分は、ずれとして扱いません。意図的な差分は次のとおりです。

- Azure DevOps 版はホスト側 AI レビューサイクルを省いています。そのため、hosted
  レビューのラウンド上限、hosted 再レビューの条件、hosted 側の修正からローカル
  レビューへ戻る手順はありません。

両方のプロバイダー別 delivery スキルは同じ `delivery-common` のファイルにリンク
します。片方だけがリンクを追加または削除すると
`setup/test/skills-wiring-delivery.test.mjs` が失敗します。

pstack の原則と任意の pstack workflow を共有 delivery ポリシーにどう組み込むかは
[ADR 0001](adr/0001-pstack-principles-in-delivery.ja.md) に記録しています。
上記の記述は現在の動作です。

### 共有スクリプト

複数のワークフロースキルで繰り返す確認は、`skills/local/delivery-common/scripts/`
にスクリプトとして1つだけ置き、呼び出す各手順はそのスクリプトを実行する1行で
ルールを示します。この場所は `base` に含まれ、PR、クリーンアップ、Beads など
delivery 以外のスキルも使うため、スクリプトを呼ぶスキルを含む profile には
`base` が必要です。`base,github`、`base,azure-devops`、`base,beads` を使います。

- スクリプトは Node の `.mjs` にします。setup がすでに `node` を必須としている
  macOS、Linux、Windows で動きます。
- 呼び出すスキルは自分のディレクトリからの相対パス
  （`../delivery-common/scripts/<name>.mjs`）でリンクします。スキルは並べて
  インストールされるため、リンクでもコピーでも解決できます。
- スクリプトや `node` がない場合や想定外の終了コードの場合は、呼び出し側の
  手順を止めます。確認なしの経路には戻りません。

`check-branch-name.mjs` は**安全なブランチ名**を定義します。空でなく、
`[A-Za-z0-9/._-]` だけを使い、`-` で始まらない名前です。呼び出し側は各名前を
シングルクォートで囲んで `node <script> -- '<name>' ...` を実行し、ASCII の英字、
数字、`/`、`.`、`_`、`-` だけからなる名前だけをこのコマンドや他のコマンドに
書きます。それ以外の名前は何も実行せずに安全でないと扱います。PowerShell が
U+2018-U+201B もクォートとして扱うように、`'` 以外もクォートとして扱うシェルが
あるためです。先頭の `-` や今後のルールはスクリプトが判定します。終了コード 0
はすべての名前が安全、2 は使い方の誤り、3 は安全でない名前があること（それぞれ
stderr に出力）です。それ以外の終了コードは、`node` がスクリプトがないときに
返す 1 も含めて、確認を実行できなかったことを意味します。ホストのシェルが 3 以外
の非 0 を報告することがあるため（PowerShell は 1 を報告します）、安全でない場合
に処理を分ける呼び出し側は、stderr が1行以上の `unsafe branch name:` の行だけ
からなる非 0 の終了も安全でないと扱います。両プロバイダーの start、delivery、PR、Codex
レビューサイクル、クリーンアップの各スキルと、Beads の worktree とマージクリーンアップ
のスキルはブランチを確認し、PR の作成と公開のスキルはベースまたはターゲットの
ブランチも確認します。`azure-devops-work-item-start` は、名前がその ASCII の
範囲外のとき、終了コード 3 のとき、stderr が1行以上の `unsafe branch name:` の
行だけからなる非 0 の終了のときだけ open PR の比較を飛ばし、それ以外の失敗では
止まります。worktree のパス、bead ID、head owner（`github-pr-create` が独自のルールで確認）、PR の作成と公開以外
のスキルのベースブランチは、このスクリプトの対象外です。
`tests/check_branch_name.bats` がスクリプトをテストします。

`check-push-target.mjs` は**push 先のルール**を確認します。push するのは、
ユーザーが指定した remote か、リポジトリを指す唯一の remote だけで、
`<branch>:refs/heads/<branch>` の refspec を明示します。remote が複数あり指定が
ないときは、そのうち1つだけがリポジトリを指していても確認します。fork 構成では
`gh repo view` が親リポジトリを解決することがあり、一致する1つの remote が親で
ある可能性があるためです。確認すれば remote ごとの API 照会なしにすべての fork
構成を扱え、作成した PR の head リポジトリは引き続き `github-pr-create` が
検証します。呼び出し側は解決したリポジトリ（`--github <host> <owner>/<repo>` または
`--azure <org> <project> <repo>`）を渡し、スクリプトはローカルの git 設定と
remote の URL だけを読みます。`gh`、`az`、ネットワークは使いません。`resolve`
は1行目に remote を、GitHub では2行目に head の `<owner>/<repo>` を出力します。
Azure DevOps の URL は `azure-devops-common/references/context.md` の受け付ける
remote URL の形のいずれかである必要があります。指定された GitHub の remote は
ホスト上のどの `<owner>/<repo>` を指してもよく、それが head リポジトリになります。
指定された Azure DevOps の remote は、fetch とすべての push の URL が渡された
リポジトリを指す必要があります。`pre` と `post` は push の前後で
ブランチの upstream を確認します。push 自体はスキルの中で
`git push -u <remote> <branch>:refs/heads/<branch>` として見えるコマンドのまま
残し、承認や権限のルールが引き続き確認できるようにします。終了コード 0 は確認が
通ったこと、2 は使い方の誤り、3 は確認が失敗したことを意味します。`resolve` の後
では呼び出し側がユーザーに remote の指定を求め、`pre` と `post` の後では止めて
報告します。それ以外の終了コードは確認を実行できなかったことを意味し、push を
止めます。GitHub と Azure DevOps の公開スキル、直接呼ばれた `github-pr-create`、
記録した remote がない状態で再開した `github-pr-codex-review-cycle` がこの
スクリプトを実行します。`tests/check_push_target.bats` がスクリプトをテストします。

`check-cleanup-targets.mjs` は `github-worktree-cleanup` と
`azure-devops-worktree-cleanup` の**リモートブランチ削除の確認**と
**クリーンアップ対象マニフェスト**を扱います。`remote` は、PR の head リポジトリが
fork でなく、push 先のルールで remote が解決でき、その remote が PR の head リポジトリを指し、
PR がマージ済み（Azure DevOps
では completed）で、ブランチが既定ブランチでも保護やポリシーの対象でもなく、
ほかの open な PR が使っておらず、`git ls-remote` が PR の head とちょうど一致する
ときだけリモートブランチの削除を提案し、lease に使う SHA を出力します。それ以外は
リモートブランチを残します。クリーンアップ対象マニフェストは、worktree、ローカル
ブランチ、そのリモートブランチの判定結果、`worktree-runtime-cleanup` の読み取り
専用の一覧が報告するプロセスと Compose プロジェクト（ボリュームを含む）、呼び出し
側が渡す実行時の一時ファイルのパスと、PR の head リポジトリを記録します。
`manifest` はこれを worktree の外の新しいファイルにモード 0600 の JSON で書き出し、確認のために対象を出力します。`--preview` を付けると、
マージとクリーンアップをまとめて確認するための、マージ前の Caller preview に
なります。`compare` はどの削除よりも直前にマニフェストを作り直し、確認済みの
マニフェストとの差分があれば失敗します。許容する差分は、ホストがマージ時に
削除したものなど、確認したリモートブランチがもう存在しない場合だけです。一覧を
実行できないときや stderr にエラーを出したときは、Caller preview とその compare では失敗し、それ以外では
未検証として報告し、確認時にも未検証だった場合だけ通ります。プロバイダーの情報は
呼び出し側が `gh` または `az` で調べて渡し、照会が失敗したらクリーンアップを
止めます。スクリプトは git、プロセス、Docker の状態だけを読み、`git ls-remote`
は自分で実行し、何も削除、停止、シグナル送信しません。終了コード 0 は確認が
通ったこと、2 は使い方の誤り、3 は確認が失敗したことを意味します。`remote` では
リモートブランチを残してクリーンアップを続け、`manifest --preview` と `compare`
ではクリーンアップを止めます。それ以外の終了コードは確認を実行できなかったことを
意味し、クリーンアップを止めます。`tests/check_cleanup_targets.bats` がスクリプトを
テストします。

### Triage レンズ

`github-issue-triage`、`azure-devops-work-item-triage`、`beads-issue-triage`
は、呼び出し時に `lens=<name>` で渡すレンズで着手可能な項目を順位付けします。
`deliver`(既定)は長期的な基盤を損なわずにコア機能を優先し、`stabilize` は
重大度、ユーザー影響、リグレッション、リリースブロッカーを優先します。記録した
フェーズは更新されずに古くなるため、レンズをリポジトリのドキュメントから読むことは
しません。それ以外の `lens=` の値では順位付けせずに止まります。

レンズが変えるのは順位付けの手順だけです。分類、並列 wave と重なりの確認、
ガードレールはどのレンズでも同じです。レポートの `Current State` にはレンズと
その根拠を書きます。`deliver` ではコア機能とその出典、Deferred foundation の一覧、
`stabilize` では重大度の出典と推定した重大度です。

共有ローカルスキル `triage-common` が `references/lenses.md` でレンズの定義を
持ちます。レンズの選び方、順位付けの順序、すべてのレンズに共通の tie-breaker
(リポジトリのガイダンスとの整合、明確な受け入れ条件、適度な影響範囲、広い・
曖昧・高リスク・将来スコープの作業の後回し、トラッカーを調整項目として扱うこと)、
各レンズのルール、レポートの行です。基盤、契約、ポリシーを決める項目の順位は
レンズが決めます。各プロバイダーの triage スキルは、プロバイダー上でシグナルを
どこから読むか(GitHub ではラベルとマイルストーン、Azure DevOps では Severity と
Priority フィールド、Beads では bead の `priority`)だけを持ち、ルールを書き直さず
`triage-common` にリンクします。重大度のシグナルがないときは優先度のシグナルを
重大度として扱い、どちらもないときは本文から推定して推定と明記します。

`triage-common` は `base` ではなく `github`、`azure-devops`、`beads` の各 profile
に入れます。これでプロバイダー profile 単体でも triage スキルが動き
([単体で動く読み取り系スキル](#単体で動く読み取り系スキル)を参照)、profile を
組み合わせたときは重複が除かれます。`base` が `mattpocock/skills` から `triage`
を入れるため、名前は `triage` にしません。レンズを追加するときは、既存のレンズと
同じ項目を持つ節を `lenses.md` に足し、そこにある有効なレンズの一覧に名前を
加えます。`setup/test/skills-wiring-profiles.test.mjs` は、どの triage スキルも
共有の順位付けルールを書き直していないことを確認します。

### Triage の詳細読み

triage スキルは、まず一覧のデータですべての open な項目を位置づけます。使うのは
一覧のフィールド、ID と状態だけに絞ったネイティブのブロック関係と親子関係、
リポジトリのガイダンスです。説明とコメントを全文読むのは detail band に入る項目
だけで、次に勧める項目、それと並行して進める項目、次の wave、band の項目に
ネイティブにブロックされている open な項目、本文次第で位置が変わる項目がそれに
当たります。詳細読みで項目の分類、重大度、コアパス上かどうかが変わったら、その項目をブロックしている項目も
位置づけ直し、概観の順に band を広げます。並行作業のグループは band の項目の
中だけで組み、それ以外の現在の wave の項目は並行作業について未確認と書きます。
レポートの `Current State` には全文を読んだ項目と一覧のデータだけで位置づけた
項目を書くので、利用者は追加の詳細読みを頼めます。

選び方は説明のテンプレートに依存しないため、項目の書き方が違うプロジェクトでも
使えます。band の外にある項目の本文にだけ書かれた依存関係や重大度は読まれず、
その項目を通じてだけ順位を変えることがあります。どこがそうかはレポートの一覧だけの
項目でわかります。このルールは `triage-common` の `references/detail-reads.md`
が持ち、各プロバイダーの triage スキルは取得コマンドだけを持ちます。

### 単体で動く読み取り系スキル

各プロバイダー profile の読み取り系スキルは、`base` なしでその profile だけを
入れても動きます。`github` の `github-issue-triage`、`github-issue-create`、
`github-issue-review`、`azure-devops` の `azure-devops-work-item-triage`、
`azure-devops-work-item-create`、`azure-devops-work-item-review`、`beads` の
`beads-issue-triage`、`beads-issue-create` です。これらは issue や Work Item を
作ることはあっても push や PR の作成はしないため、[共有スクリプト](#共有スクリプト)
も `base` の他のスキルも必要としません。

Azure DevOps のスキルは `azure-devops-common/references/context.md` を読みます。
その target 解決は、受け付ける remote URL の形に合う remote と `az devops` の
既定値だけを使います。push remote は選びません。push remote を選ぶのは push する
スキルだけで、`azure-devops-pr-publish` の step 2 にある push target rule に
従います。

`setup/test/skills-wiring-profiles.test.mjs` は各プロバイダー profile を単体で
コピーし、これらの各スキルから、すべての Markdown リンクとバッククォートで書いた
`../<skill>/...` 参照を確認します。参照先はアンカーも含めて存在しなければなりません。
スキル自身のファイルと他スキルの references はたどります。他のワークフロースキルの
`SKILL.md` は存在だけを確認し、たどりません。そのリンクはルールの置き場所を示すもので、
読み取り系スキルが読むものではないためです。

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

- UI 作成・テスト用の `frontend-design`、`webapp-testing`
- ブラウザ自動操作用の `playwright-cli` と、ライブラリドキュメント参照用の `context7-cli`
- 公開済みの Matt Pocock Engineering / Productivity skill から選択したもの
- `repo-execution-context`、`change-review`、`change-adversarial-review`、`change-security-review`、runtime isolation の local skill
- worker の草稿とコーディネーターの質問の流れ、commit 済み snapshot のローカルレビュー手順、リスク tier、delivery の完了ポリシーを共有する `delivery-common`
- design preflight の前に、before/after の具体例を含む概要で issue や Work Item の内容を読み上げ、決めていることと決めていない点をユーザーと合意する `shared-understanding`
- `git-commit`

Matt Pocock の `misc`、`personal`、`in-progress`、`deprecated` skill は含めません。
Superpowers は `base` に含めません。`writing-great-skills` は上流で改名されたため、後継の `writing-for-agents` を使います。

以前の GitHub 対応込みの baseline が必要な場合は `base,github` を使います.

### `pstack`

Lauren Tan の pstack を、この環境の作業範囲と承認ルールに合わせた13個の local skill。
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
| `maintain-verification-skill` | 既存の検証手順をソースと実動作に照合して保守し、製品の契約を保つ。 |
| `evaluate-skill` | 両エージェントで、スキルの候補実行・条件名を伏せた採点・結果の整理を進める。 |
| `benchmark-checklist` | 明示起動で、性能測定値の律速要因・チューニング・限界・エラー・再現性・影響度・処理の実行有無を確かめる。 |
| `prove-it-works` | 完了の主張と観測した挙動を対応させる共通原則。 |
| `encode-lessons-in-structure` | 根拠のある再発パターンを、型・テスト・既存の検査などで防ぐ共通原則。 |
| `explain-the-number` | 測定値を信頼する前に、律速要因と他に測っている可能性のあるものを確かめる共通原則。 |

呼び出し例は `$how この処理の経路を説明して`、`$why この状態を永続化した理由は？`、
`$architect このインターフェースを設計して`、`$arena この案を比較して`、
`$interrogate この変更をレビューして`、`$blast-radius このスキーマ変更を検証して`、
`$create-verification-skill このCLIの検証手順を作って`、
`$maintain-verification-skill このアプリの検証手順を更新して`、
`$evaluate-skill maintain-verification-skill`、
`$benchmark-checklist この高速化を検証して`。
Claude Code では、その環境の skill 呼び出し方法を使います。
共通原則3つは直接参照するほか、各 workflow skill から必要に応じて読みます。

delivery でのこれらの skill の使い方は
[ADR 0001](adr/0001-pstack-principles-in-delivery.ja.md) で決めています。
子 issue が実装されるまで、delivery skill は pstack の workflow を実行せず、
下記の明示呼び出しの規則もそのまま適用されます。

`arena`・`interrogate`・`blast-radius`・`create-verification-skill`・
`maintain-verification-skill`・`evaluate-skill`・`benchmark-checklist` は
ユーザーによる明示起動に限定します。description と本文に加え、Codex には
`policy.allow_implicit_invocation: false`、Claude Code には SKILL.md の
frontmatter に `disable-model-invocation: true` を設定します。
Codex では `$skill-name`、Claude Code では `/skill-name` で呼び出します。
他の skill からの参照だけでは起動しません。`architect` は、ユーザーが
`arena` を明示起動した場合を除き、自身で設計案を比較します。

`how`・`why`・`architect` はタスクの description に従って選択できます。
共通原則3つは、必要な場面や他の workflow から参照します。
登録されている全 skill を毎回実行する構成ではありません。
候補・レビューの並列実行は条件と上限を設け、利用できない場合は独立性の限界を明示します。

`architect` は利用可能な `codebase-design` の設計語彙を参照し、明示依頼された
事前確認は `design-preflight` に任せます。`interrogate` は利用可能な
`change-review`・`change-adversarial-review` の観点を参照しますが、明示起動限定の
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

`maintain-verification-skill` はCodexとClaude Codeで同じ本文を使います。
未検証の機能が残る場合は blocked とし、製品本体の修正は範囲に含めません。
明示起動する [evaluate-skill](skill-evaluation.ja.md) が候補の実行・採点・結果の整理を進め、
準備用の補助スクリプトもスキル内に同梱します。両エージェントで共通の課題と
判定基準を使い、環境の準備や設定検証だけで実モデルでの成功とはしません。

`arena`・`interrogate`・`create-verification-skill`・`benchmark-checklist`・
`explain-the-number` は上流リビジョン
[`0b46ec399d55f2829e88822998f53b84944837d3`](https://github.com/cursor/plugins/tree/0b46ec399d55f2829e88822998f53b84944837d3/pstack) に追従しています。
最初の9スキルのうち残り6つは
[`12d587dfb20741cafc376c42c696c5f6e2a64487`](https://github.com/cursor/plugins/tree/12d587dfb20741cafc376c42c696c5f6e2a64487/pstack) を参照し、
`0b46ec3` までの上流の変更は照合したうえで取り込んでいません。
各 skill に出典リンク・ローカルでの調整理由・Lauren Tan の MIT license を含めます。
保守・評価スキルは自身の本文に参照した上流リビジョンを記載します。
`evaluate-skill` は上流の Eval playbook を独立したローカルスキルにしたもので、
上流に同名の独立スキルがあるという意味ではありません。
上流の `principle-prove-it-works`・`principle-encode-lessons-in-structure`・
`principle-explain-the-number` は、ローカルでは接頭辞を省略しています。
`explain-the-number` は `benchmark-checklist` をユーザーが起動する workflow として
示すだけで、自身では実行しません。自動同期するプラグイン fork ではなく、
上流の変更とローカルの契約を照合して更新する構成です。

### `github`

GitHub workflow skill:

- `gh-cli`
- `skills/local/` 配下の自作 GitHub issue, pull request, AI review, merge cleanup skill
- [Triage レンズ](#triage-レンズ) 用の `triage-common`

Azure DevOps provider profile では, GitHub の `issue` skill に相当するものを `work-item` skill として扱います.

### `beads`

Beads workflow skill:

- `beads-issue-create`
- `beads-issue-triage`
- `triage-common`
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

`azure-rbac` は配布元のスキル実体を確認できないため含めません。

### `azure-devops`

Azure DevOps workflow skill:

- `azure-devops-cli`
- `azure-devops-common`
- `azure-devops-work-item-create`
- `azure-devops-work-item-review`
- `azure-devops-work-item-triage`
- `triage-common`
- `azure-devops-work-item-start`
- `azure-devops-work-item-delivery`
- `azure-devops-pr-create`
- `azure-devops-pr-publish`
- `azure-devops-pr-review`
- `azure-devops-worktree-cleanup`

`azure-devops-work-item-start` は独立した worktree を準備し、実装まで進めます。
`azure-devops-pr-create` は PR の作成・再利用を担当し、
`azure-devops-pr-publish` は検証・commit・push の後に PR 作成を委譲します。
`azure-devops-worktree-cleanup` は完了した作業のローカル branch と worktree を削除します。
リモートの source branch の先頭が完了済み PR のマージ元と一致する場合は、その削除も提案します。

`azure-devops-work-item-delivery` は Azure DevOps Services の Azure Boards と
Azure Repos Git を対象に、独立 worktree、`shared-understanding`、
`design-preflight-with-docs`、実装、
2種類のローカルレビュー、PR 公開、承認後のマージ、承認後のローカル cleanup
までをまとめます。Claude Code では `/azure-devops-work-item-delivery 123 456`、
Codex では `$azure-devops-work-item-delivery 123 456` のように Work Item ID を
指定します。前提スキルは `base,azure-devops` で揃えます。
GitHub 版と Azure 版は、worker が草稿を作りコーディネーターがユーザーに質問する
`delivery-common` の流れ、ローカルレビュー手順、完了ポリシー、ホスト別の reviewer を共有します。一括フローの明示依頼は preflight、adversarial review、
PR 公開への委譲を含み、既存の承認条件に従います。マージと cleanup はそれぞれ
対象を示して確認します。Work Item の状態遷移には明示的な意図が必要で、
マージ後の実状態も確認します。再開記録は一時的な agent-work 領域に残します。
公開には `azure-devops-pr-publish` を使い、公開後の AI レビュー依頼・対応
サイクルは実行しません。必須 policy、CI、人間の承認はマージ前に確認します。

Work Item のリンクと状態遷移のルールは
[共通文書](../skills/local/azure-devops-common/references/context.md#work-item-links-and-state-transitions)
に集約します。PR 作成スキルがルールを適用し、公開スキルは Work Item の文脈を渡します。

`azure-devops` は `azure` から独立しています. Azure DevOps リポジトリでは `base,azure-devops` を使います. 同じリポジトリで Azure cloud/resource 作業も必要な場合だけ `base,azure,azure-devops` を使います.

Azure DevOps の AI review request/follow-up skill は, 初期対応では意図的に含めません.

GitHub と Azure DevOps の workflow 対応:

| GitHub skill | Azure DevOps skill |
|---|---|
| `github-issue-create` | `azure-devops-work-item-create` |
| `github-issue-review` | `azure-devops-work-item-review` |
| `github-issue-triage` | `azure-devops-work-item-triage` |
| `github-issue-start` | `azure-devops-work-item-start` |
| `github-issue-delivery` | `azure-devops-work-item-delivery` |
| `github-pr-create` | `azure-devops-pr-create` |
| `github-pr-publish` | `azure-devops-pr-publish` |
| `github-pr-review` | `azure-devops-pr-review` |
| `github-worktree-cleanup` | `azure-devops-worktree-cleanup` |

### `frontend`

Frontend、UI、React、Tailwind、SEO、Remotion、web design 系。

`frontend-design`、`webapp-testing` は `base` にも含めます。`frontend` 単独でも使えるようにここにも残し、`base,frontend` を組み合わせた場合は重複を除きます。

Browser automation は frontend 開発以外でも使うため、ここにはデフォルトでは含めません。

### `browser`

Browser automation/debugging 系:

- `agent-browser`
- `browser-use`
- `chrome-devtools`

`playwright-cli` は `base` に含めます。これらのツールと併用する場合は `base,browser` を指定します。

### `data`

Data/database 系:

- `redis-core`
- `supabase-postgres-best-practices`

### `research`

Research 固有の skill:

- `read-arxiv-paper`

### `docs`

執筆とドキュメント作成を支援する skill:

- `writing-partner`

ライブラリドキュメント参照用の `context7-cli` は `base` に含めます。

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
- local と external、または external source 同士の skill 名衝突の拒否
- 外部 skill 用の `npx skills add` 実行
- local skill の link 作成
- project output の backup と rollback
- `.agents/skills-profile.json` の出力
- user scope の最終 link 作成

Profile add/remove の補助コマンドは初期実装の対象外にします。Profile JSON は手で編集し, `./setup.sh skills profile validate` で検証します。

## Export

`skills export` は、選択した skill と agent ルールを自己完結したバンドルとしてディレクトリに書き出します。dotfiles リポジトリ全体や個人設定を渡さずに skill 環境を共有するためのコマンドです。

脅威モデル: export を実行する人と dotfiles のチェックアウトは信頼します。Export が防ぐのは、操作ミス (誤った `--out`、`--force` の誤用、リンクが壊れたバンドル) と、個人情報がバンドルに入って外に出ることです。Export の実行中に他のローカルユーザーがファイルを変更する場合は対象外です。

```sh
./setup.sh skills export --profile base,github --out ~/share/ai-skills
./setup.sh skills export --profile base --agent codex --exclude ask-matt --out ~/share/ai-skills --force
```

```powershell
.\setup.ps1 skills export --profile 'base,github' --out $HOME\share\ai-skills
```

- `--profile <csv>` と `--out <dir>` は必須です。Profile はインストールと同じく、`setup/src/skill-profiles.ts` の共通 resolver で解決します。同じ profile を 2 回指定しても 1 回として扱います。
- `--agent` はインストールと同じ `codex` と `claude-code` を受け付けます。繰り返し指定とカンマ区切りが使え、省略時は両方です。
- `--exclude <csv>` は local skill と外部 skill のどちらも除外できます。含まれる skill が依存する skill を除外すると `<dependency> is required by <skill>` で失敗します。Profile が含まない skill を指定しても失敗します。
- `--force` は以前のバンドルだけを置き換えます (後述)。
- 値を取るオプション (`--profile`、`--agent`、`--exclude`、`--out`) の直後に別の `--` オプションが来た場合は、値がないものとして失敗します。`--` で始まるパスは `./--name` のように書きます。
- `--scope` と `--copy` (PowerShell では `-Copy`) は export では使えません。
- `SETUP_DRY_RUN=1` では選択結果を表示するだけで、何も書き出しません。
- 出力ディレクトリは dotfiles リポジトリの外にある必要があります。Export は `--out` をファイルシステムと同じ方法で解決します。存在する最も長い先頭部分を書かれたとおりに OS に解決させ (`..` より先にリンクをたどります)、パスの構文はプラットフォームのものに従うので、Linux と macOS ではバックスラッシュは名前の一部です。ディレクトリはファイルシステム上の同一性で比較します。そのため、大文字小文字を区別しないボリューム上で大文字小文字だけが異なる表記など、チェックアウトの別の書き方も拒否します。まだ存在しないディレクトリの後の `..`、ファイルの下に続くパス、Windows での `C:bundle` のようなドライブ相対パスは失敗します。
- PowerShell ではカンマ区切りの値を `'base,github'` のように引用符で囲みます。囲まないと PowerShell が配列として渡すためです。`setup.ps1` は export の引数をそのまま Node に渡すので、`--out` が PowerShell の共通パラメーターと解釈されることはありません。

### バンドルの構成

```text
<out>/
  skills/<name>/       # local skill の実ファイルコピー
  AGENTS.md            # Codex 用ルール (codex 選択時)
  CLAUDE.md            # Claude Code 用ルール (claude-code 選択時)
  README.md            # 各部分の配置先と外部 skill のインストールコマンド
  skills-bundle.json   # マニフェスト
```

バンドルは `skills/local/<name>/`、`skills/profiles/`、`ai-rules/` だけから作ります。`claude/settings.json`、`codex/config.toml`、`codex/profiles/`、MCP 設定、その他のファイルは含めません。

選択した skill も依存として追加した skill も、ルートに名前がちょうど `SKILL.md` の通常のファイルを持つ必要があります。skill 内のファイル名はすべて正しい UTF-8 でなければなりません。選択した local skill は `scripts/` や `references/` を含むディレクトリ全体を、実行ビットを保ったままコピーします。最上位の `evals/` はこのリポジトリ用の開発フィクスチャなのでコピーしません。選択した skill の中にシンボリックリンクがある場合や、選択した skill のディレクトリ自体がシンボリックリンクの場合、export は失敗します。

読み取りはすべて dotfiles のチェックアウト内に限ります。Export は中身を読む前に、`ai-rules/`、`skills/local/`、`skills/profiles/`、選択した各 skill ディレクトリ、各 profile ファイル (`includes` で読むものを含む)、各ルールファイルが、シンボリックリンクではない実際のディレクトリまたはファイルで、チェックアウト内に解決されることを確認します。パースに失敗した profile は名前と位置だけを報告し、内容は表示しません。Profile 名、`includes` の各要素、local skill 名はそれぞれ 1 つのパス要素 (`[A-Za-z0-9][A-Za-z0-9._-]*`) でなければなりません。この制約はインストールと検証でも同じです。

ルールファイルは Node で組み立て、`ai-rules/scripts/compose-rules.sh <agent>` を `--with-metadata` なしで実行した結果と同じ内容 (UTF-8 のバイトオーダーマークも含む。スクリプトの `grep` と同じく、バイトオーダーマークだけの上書きファイルも内容ありとして扱う) にします。これにより `setup.ps1` からも Bash なしで export できます。`ai-rules/base/global.md` はそのまま共有します。

外部 skill はコピーしません。マニフェストに `{source, skills}` として記録し、README に source ごとの `npx skills add <source> --skill <name> ... --agent <agent>` コマンドを、各引数をシェル用に引用し、setup 自身と同じくコピーでインストールする `--copy` を付けて載せます。Export が受け付けるのは `owner/repo` 形式の source と単純な skill 名だけなので、profile からこれらのコマンドにシェル構文を入れることはできません。README では、これらのコマンドをどのプロジェクトにも属さない新しい空のディレクトリで実行するよう案内します。`npx` はカレントディレクトリからコマンドと npm の設定を解決するためで、setup 自身のインストールも同じように分離しています。`skills-lock.json` は `skills` CLI の管理物のままにし、export ではコピーも生成もしません。

### 依存 skill の追加

ある local skill のファイル内の参照を、そのファイルのディレクトリから解決して別の local skill の中を指すとき、その skill に依存しているとみなします。例: `SKILL.md` 内の `../delivery-common/scripts/check-branch-name.mjs` ([共有スクリプト](#共有スクリプト) を参照)。Export はこうした skill を推移的に追加し、`Added as a dependency: <skill> (required by <skills>)` と表示して、`origin: "dependency"` として記録します。

参照は、空白、引用符、バッククォート、括弧のあとに続く 1 つ以上の `../` で始まり、次の区切り文字までを指します。最初の名前の要素は英字、数字、`_`、`%` のいずれかで始まる必要があるので、スクリプト内の `../../.agents/skills` のような隠しパスは参照とみなしません。文末の句読点と `#anchor` は除き、末尾の `..` は残します。Export は参照元ファイルのディレクトリから要素を 1 つずつ解決するので、`missing/..` は失敗します。後ろにパスが続く要素 (末尾の `/` や `..` を含む) はディレクトリでなければならないので、`SKILL.md/` や `SKILL.md/../x` も失敗します。%-エンコードされた参照はデコードした形でも解決を試みます。依存の抽出とバンドルの検査は同じパーサーを使います。

コピー後、バンドル内 skill の参照はすべて、バンドルの `skills/` 内に存在するパスを指す必要があります。存在しないファイル、選択されていない skill、`evals/` 内のファイルへの参照があると export は失敗します。依存として追加した skill の名前が、選択した外部 skill の名前と同じ場合も名前の衝突として失敗します。

本文で skill 名に触れているだけ (たとえば `change-review` を実行する workflow skill) では依存とみなしません。名前の言及は provider の境界をまたぎます。`delivery-common` は GitHub と Azure DevOps の両方の skill 名に触れているので、名前をたどるとほぼすべての workflow skill がどのバンドルにも入ってしまいます。こうした skill はインストールと同じく profile で選びます。たとえば `github` 単体ではなく `base,github` を指定します。

### マニフェスト

`skills-bundle.json`:

```json
{
  "schemaVersion": 1,
  "generatedBy": "dotfiles setup skills export",
  "requestedProfiles": ["github"],
  "expandedProfiles": ["github"],
  "agents": ["codex", "claude-code"],
  "local": [
    { "name": "delivery-common", "origin": "dependency", "requiredBy": ["github-issue-delivery"] },
    { "name": "github-issue-delivery", "origin": "profile" }
  ],
  "excluded": [],
  "external": [{ "source": "owner/repo", "skills": ["name"] }],
  "rules": ["AGENTS.md", "CLAUDE.md"],
  "files": ["AGENTS.md", "CLAUDE.md", "README.md", "skills-bundle.json", "skills/delivery-common/SKILL.md"]
}
```

`files` には export が書いたすべてのファイルを、`/` 区切りでソートして記録します。出力は決定的で、タイムスタンプや絶対パスを含みません。有効なマニフェストの定義は 1 つだけです。Export は書き出す前に自分のマニフェストをこの定義で確認し、`--force` もマニフェストがこの定義を満たす場合だけ以前のバンドルとして受け入れます。そのため、export が書いたバンドルは後の export でいつでも置き換えられます。

### 出力ディレクトリ

Export はバンドルのすべてのファイルをメモリに読み込み、何かを書き込む前にそこで個人情報チェックを行います。その後、読み込んだ内容から `<out>` の隣にステージングディレクトリを書き出し、ステージングした内容がマニフェストと一致することとリンクが解決できることを確認してから、所定の場所に移動します。大文字小文字だけが異なるバンドル内のパス (たとえば `Gamma` と `gamma` の 2 つの skill) は、何かを書き込む前に失敗します。ステージングと退避用のディレクトリは `<out>` の隣の短い名前 (`.skx-s…`、`.skx-b…`) を使うので、有効な `--out` の名前ならどれでも `--force` で置き換えられます。どこかで失敗した場合はステージングディレクトリを削除し、`<out>` は元のまま残します。

Linux と macOS では、`<out>` の直接の親ディレクトリが、sticky ビットなしで他のユーザーから書き込み可能な場合や、自分と root 以外のユーザーが所有し書き込み可能な場合、export は書き込みを拒否します。そのような親はほぼ確実にパスの指定ミスだからです。`/tmp` のような sticky ビット付きの共有ディレクトリは使えます。Windows ではこの確認を行いません。

- `<out>` が存在しないか空なら、そこに書き出します。
- `<out>` が空でなければ、`--force` がない限り失敗します。
- `--force` で置き換えるのは、`<out>` が以前のバンドルの場合だけです。つまり `skills-bundle.json` が通常のファイルで、有効なマニフェスト (文書どおりのフィールドだけを持つスキーマバージョン 1。要求した各 profile が `expandedProfiles` に含まれ、依存 skill には必要とする列挙済みの skill が記録され、`excluded` と `local` が重ならず、`rules` が `agents` と一致し、`files` が `README.md`、マニフェスト、ルールファイル、列挙された各 skill の最上位 `evals/` 以外のファイルだけからなる) を持ち、ディレクトリ内のすべてのファイルを列挙している必要があります。手で追加したメモや `.git/` などそれ以外のエントリがあると `--force` でも失敗し、エラーでそのエントリを示します。Export が書いていないファイルを消すことはありません。
- 既存のディレクトリ (空のディレクトリまたは以前のバンドル) を置き換えるときは、まずそれを退避し、退避したディレクトリをもう一度検査してから新しいバンドルを配置します。それまでに失敗した場合は、退避したディレクトリを元に戻します。配置後は、その検査で見たファイルだけを削除し、空になったディレクトリを削除します。それ以外のものが残った場合も export は成功として終了し、新しいバンドルを配置したことと古いディレクトリの残っている場所を警告で示します。

### 個人情報チェック

バンドルを所定の場所へ移動する前に、すべてのファイルのパスと内容を大文字小文字を区別せずに検査し、次のものを探します。

- setup が使い得るホームディレクトリ (`SETUP_HOME`、`HOME`、`USERPROFILE`、`setup.ps1` の `CUSTOM_HOME`、OS のホーム、アカウントのホームディレクトリ)。それぞれ与えられたとおりの形、末尾の区切り文字を除いた形、実パスを対象にします。どちらのパス区切り文字の形も、JSON や JavaScript でエスケープした形 (二重のバックスラッシュ、`\/`) も対象にします。`setup.ps1` は明示的に設定された `SETUP_HOME` を維持します。
- dotfiles リポジトリで読んだ `git config user.name` と `user.email`。未設定のキーは対象外ですが、`git` がない場合やその他の読み取りエラーでは export は失敗します。この読み取りでは、git に別のリポジトリを指させたり設定を注入したりする変数 (Windows では名前の大文字小文字を区別しません。`GIT_DIR`、`GIT_WORK_TREE`、`GIT_CONFIG`、`GIT_CONFIG_PARAMETERS`、`GIT_CONFIG_COUNT` とそのキーと値など) を除くので、dotfiles リポジトリの設定とグローバル・システムの設定を読みます。Windows では `git` を `PATH` から探し、カレントディレクトリからは実行しません。
- 個人マーカーファイルの各マーカー

個人マーカーファイルは、どの OS でも `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/export-personal-markers` です。`XDG_CONFIG_HOME` がない場合、上記の各ホームディレクトリの下から読みます。1 行に 1 つのマーカーを文字どおり書きます。空行と `#` で始まる行は無視します。マーカー自体が個人情報なので、このファイルはリポジトリの外に置きます。既定のファイルがなくても構いません。`SETUP_EXPORT_PERSONAL_MARKERS_FILE` でパスを上書きでき、値が空の場合や指定したファイルが存在しない場合、export は失敗します。

バンドルのすべてのファイル、マーカーファイル、ルールファイルは、NUL 文字を含まない厳密な UTF-8 である必要があります。UTF-16 やバイナリデータなどそれ以外のものは、検査しないまま通すのではなく export を失敗させます。既定のマーカーファイルを読み飛ばすのは、そのパスに何も存在しない場合だけです。壊れたリンク、その他の読み取りエラー、マーカーのパスが通常のファイルでない場合は export を失敗させます。マーカーファイルのエラーは、ファイルの役割 (既定または上書き) とエラーコードだけを示し、パスは表示しません。

一致があると export は失敗し、`skills/x/SKILL.md: git user.email` のようにファイルと一致の種類を示します。マーカーごとに 1 つの大文字小文字を区別しない照合を、検査と伏字の両方に使うので、検査で見つかったものは必ず伏字になり、一致した値そのものは表示しません。マーカーは引数の解析より前に、読み込んだ順にすぐ登録し、引数エラーや選択結果の表示を含むすべてのメッセージで、ホームパスは `<home>`、その他のマーカーは `<redacted>` に置き換えます。

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

setup はこれを project 外の private なステージングディレクトリで実行し、生成された `skills-lock.json` と agent skill ディレクトリを project に移動します。

既存の `skills-lock.json` や agent skill directory を置き換える場合は、事前に backup を作り、install に失敗したら復元します。Install が成功した場合は、選択した profile で再作成されなかった既存の agent skill entry を戻します。Profile 管理の skill と同じ名前の entry は、ローカルで編集したコピーであっても profile 管理版に置き換えます。以前の entry は backup にだけ残り、それが編集済みのコピーだった場合は `Replaced locally edited skill copy` の warning で backup 内の entry を示します。ただし、選択されなくなった、または存在しなくなった skill を指す `skills/local` へのリンクと、その未編集の管理コピーは戻さず、backup にだけ残します。それらの skill の編集済みのコピーは warning を出して残します。予約名の既存 entry も他の entry と同様に戻します。予約名で失敗するのは install が生成した entry だけです。Git の dirty state は warning に留め、実行自体は止めません。

どちらの scope でも、`npx skills add` は project や `/tmp` のような共有 temp directory ではなく、実行ごとに作る private directory で実行します。npm cache と project の backup も同じユーザー専用の場所に置きます。Linux では `$XDG_CACHE_HOME` または `~/.cache`、macOS では `$TMPDIR`、Windows では `%TEMP%` です。Cache は `dotfiles-skills-npm-cache/` で、実行をまたいで再利用します。Backup は `dotfiles-skills-backup/<project directory 名>/` に置き、install が成功しても残します。`$TMPDIR` と `%TEMP%` は絶対 path でなければならず、`%TEMP%` は network share (`\\server\share`、またはそれを割り当てた drive letter)、device path、drive のない path (`\Temp`) ではなく local drive 上 (`C:\...` または `\\?\C:\...`) でなければなりません。これらの directory は作成する前にすべて確認するため、止まった場合に新しい directory は残りません。これらの値が条件を満たさない場合、その場所が project 内にある場合 (Windows と、大文字小文字を区別しない macOS の volume では、大文字小文字の違いを無視します)、その場所か上位の directory が他のユーザーの所有か他のユーザーから書き込み可能な場合、その directory が group から書き込み可能で、自分が所有し自分の user-private group (自分の名前を持つ primary group で、`/etc/passwd` と `/etc/group` に他の member がいないもの) に属する directory ではない場合 (macOS では group から書き込み可能な directory はすべて対象)、または project 内の `.agents`、`.claude`、agent skill directory、`skills-lock.json`、`.agents/skills-profile.json` が symbolic link の場合は、リンク先が project の内外どちらでも、リンク切れでも、何も変更せずに止まります。

外部インストール後は、指定した各スキルの `SKILL.md` が存在することを確認します。欠落時は user view を入れ替えず、project scope では既存のバックアップを復元します。`profile validate` は設定の構造を確認するもので、配布元の存在確認や実行評価は行いません。

user scope では、各インストールが生成したエントリを、指定していないものも含めてすべて1つのステージング view にコピーします。2つのインストールが同じ名前のエントリを生成した場合は `skill entry collision in user staging: <entry> (<earlier source>, <later source>)` で失敗し、user view を入れ替えません。インストールがそのステージングディレクトリの `.agents/skills` または `.agents` をシンボリックリンク、またはディレクトリ以外のものにした場合は、`skill entry collision in user staging: <path> (<source>, symbolic link)` または `skill entry collision in user staging: <path> (<source>, not a directory)` で失敗し、そこから何もコピーせず、user view を入れ替えません。

project scope では、各インストールを1つのプライベートディレクトリで順に実行します。先のインストールが生成したエントリを後のインストールが削除、置き換え、またはその中身を変更した場合 (ファイルのその場での書き換え、ファイルの追加、権限の変更など) は、内容が同じでも `skill entry collision in project install: <entry> (<earlier source>, <later source>)` で失敗し、backup から project を復元します。インストールがそのディレクトリの `.agents/skills`、`.claude/skills`、`.agents`、`.claude` をシンボリックリンク、またはディレクトリ以外のものにした場合は、`skill entry collision in project install: <path> (<source>, symbolic link)` または `skill entry collision in project install: <path> (<source>, not a directory)` で失敗し、backup から project を復元します。

## Local Skills

Local skill は `skills/local/<name>` に置き、dotfiles が正本です。

Project scope では、選択した agent の project skill ディレクトリに local skill を symlink します。

```text
repo/.agents/skills/<name> -> ~/.dotfiles/skills/local/<name>
repo/.claude/skills/<name> -> ~/.dotfiles/skills/local/<name>
```

User scope でも、生成した user profile view 内に local skill を symlink します。

Windows で symbolic link の権限がなく Node が project のリンクを作れない場合、setup はリンク全体について UAC 昇格を1回だけ要求します。昇格をキャンセルした場合や昇格できない場合 (Win32 code 5、740、1223、1314)、または昇格後もリンク権限がない場合はコピーに切り替えます。それ以外の昇格の失敗では setup を止め、backup から project を復元します。

`--copy` (`.\setup.ps1` では `-Copy`) を付けると、どの platform でも、リンクや昇格を試さずに最初から project の local skill をコピーとしてインストールします。`--scope project` でのみ使え、user scope では `--copy is supported only for project scope` で失敗します。`.\setup.ps1 skills -Copy` の user scope では、PowerShell 側で user scope のリンクをコピーにします。各実行はその実行のフラグに従います。`--copy` 付きで実行すると既存の project のリンクをコピーに置き換え、その後 `--copy` なしで実行すると再びリンクを作ります。

各コピーは通常のディレクトリで、隣にソースと内容を記録した `.dotfiles-copy-<name>.json` marker を置きます。コピーはソースの編集に追従しないため、更新するには setup を再実行します。選択した他の entry と同様に、コピーも実行ごとに置き換わり、ローカルの編集は backup にだけ残ります。

Target path がすでに存在し、それが dotfiles 管理の symlink ではない場合は、上書きせずエラーにします。local skill は external のインストールより優先しません。インストールが local skill と同じ名前のエントリを生成した場合は `skill entry collision in user staging: <entry> (<source>, local)` または `skill entry collision in project install: <entry> (<source>, local)` で失敗し、user view を入れ替えず、project を復元します。

Skill 名は選択した profile 全体で一意にします。local skill は external skill と同じ名前にできず、2つの external source が同じ名前を提供することもできません。`profile validate` とインストールは、external のインストールを始める前に衝突を検出して失敗します。`review` や `code-review` のように、ホストや広く使われている skill 集がすでに使っている汎用名は避けます。

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
