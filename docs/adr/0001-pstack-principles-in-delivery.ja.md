---
status: accepted
---

# pstack の原則を delivery ワークフロー全体に適用する

[English](0001-pstack-principles-in-delivery.md)

Review 行の run-to-prove の部分は [#245](https://github.com/daisukekobayashi/dotfiles/issues/245)
で実装し、[ADR 0002](0002-run-to-prove-isolation.ja.md) に記録しました。残りの実装は
[#246](https://github.com/daisukekobayashi/dotfiles/issues/246) の子 issue で行います。
それらが実装されるまで、この記録は採用した設計を表し、現在の delivery の動作は
表しません。現在の動作は [Skills Profile 設計](../skills-profiles.ja.md) に記載しています。

## 背景

ローカルの pstack skill（`how`、`why`、`architect`、`arena`、`interrogate`、
`blast-radius`、`prove-it-works`、`encode-lessons-in-structure`、
`create-verification-skill`、`maintain-verification-skill`、`evaluate-skill`）は
独立した `pstack` profile にあります。delivery の skill（`delivery-common`、
`github-issue-delivery`、`azure-devops-work-item-delivery`、`change-*review`）は
どれもこれらに触れておらず、delivery の前提 profile は `base,github` または
`base,azure-devops` です。#239 の delivery では、skill の文面を変えた変更のレビューが
指示を読んで追跡しただけで、agent による実行はしませんでした。そのための
`evaluate-skill` は存在していました。

pstack の考え方は2つの原則にまとめられます。代理の指標ではなく実物を確かめること、
繰り返す誤りを構造で防ぐことです。どちらもすでに `ai-rules/base/global.md` の
グローバルルール（「Match completion claims to observed evidence ...」と「When the
same confirmed failure recurs, prefer a small safeguard near its cause ...」）として
すべての agent に適用されています。以下のルールはこの基準を delivery の各フェーズ向けに
具体化するもので、置き換えるものではありません。

## 決定

### 依存の方針

delivery は原則を `delivery-common` のフェーズの記述に短いルールとして書き込み、
pstack skill がなくても成り立つようにします。加えて、重い pstack workflow を
**任意 workflow** とします。delivery はインストールされていてトリガー条件を満たすときに
自動で実行し、そうでなければ `not run: not installed` または `not run: trigger not met`
と報告してフェーズを続けます。インストールされていても、必要なツール、実行環境、
隔離した場所など実行の前提が使えない任意 workflow は `not run: unavailable` と報告し、
この場合もフェーズを続けます。任意 workflow は `architect`、`arena`、`blast-radius`、
`evaluate-skill`、対象プロジェクト自身の `verify-<app>` skill、#240 で取り込む計測の
workflow です。

これは Missing Prerequisites の唯一の例外です。必須の skill、レビュアー、チェック、
ツールがない場合は、引き続きそれを必要とするフェーズを止めます。

delivery は `arena`、`blast-radius`、`evaluate-skill` を、すでに `change-*review` を
呼んでいるのと同じ方法で呼び出します。`SKILL.md` から `disable-model-invocation` を
外し、Codex のメタデータは `allow_implicit_invocation: false` のまま残し、description
に、ユーザーが明示的に依頼した `github-issue-delivery` または
`azure-devops-work-item-delivery` の該当ステップとしても実行すると書き加えます。
各 skill の本文冒頭の「Run only ...」の制限にも、
`change-*review` の本文と同じく、delivery に限った例外を加えます。実装する issue で
両方をテストします。delivery の外では明示呼び出し専用のままです。

### フェーズの対応

| フェーズ | 原則 | 判定 | delivery での動作 | 理由 |
|---|---|---|---|---|
| Shared understanding と preflight | 主張を追跡したコードと経緯に基づかせる | 調整して採用 | 草案は追跡した経路または記録された理由を引用します（`how` と `why` の方法）。preflight の草案にインターフェース、データの形、モジュール境界に関する後戻りしにくい決定があるとき、worker はその決定について `architect` を実行し、比較した形を示します。 | 引用と選択肢のルールはすでにあります。`architect` を後戻りしにくい決定に限ると、preflight がすでに絞り込んだ決定だけにコストが収まります。 |
| Preflight（High tier） | 独立した候補を比較する | 採用 | その決定が `architect` の後も2つの有力な形を残しているとき、worker はその決定について `arena` を実行します。 | `arena` は隔離した複数の作成者を動かすため、手順がすでに重くなる tier で、後戻りしにくい未決の決定に限ります。 |
| 実装の検証 | 代理ではなく実物を確かめる | 採用 | 各検証に、変更した経路を実行したのか代理の確認だけなのかを明記します。対象プロジェクトに変更した機能を扱う自身の `verify-<app>` skill があれば、worker はそれを実行します。`create-verification-skill` は自動では実行しません。 | 代理だけの確認が区別されずに報告されていました。プロジェクトの `verify-<app>` skill は対象の一部ですが、新たに生成するとタスク外のファイルが増えます。 |
| skill と指示の変更 | 変更した指示を agent で実行する | 採用 | Medium と High tier で skill や `AGENTS.md` などの指示ファイルの文面を変えた delivery は、現在の agent で `evaluate-skill` を時間の上限つきで1回呼び出し、delivery 用のスモークモードで実行します。変更した skill ごとに既存の eval ケースを1つ選び、変更後の指示でそれぞれ1回だけ実行し、ベースラインのセッションは作りません。`evaluate-skill` の通常のベースラインとの比較は delivery では行いません。指示ファイルだけの変更を含め、該当する eval ケースのない変更は未実行と報告し、Low tier は `not run: tier` と報告します。 | #239 で見えた穴を、1回の delivery が負担できるコストで埋めます。delivery ごとの `evaluate-skill` の完全な比較は高すぎます。 |
| レビュー | 実行で裏付けた指摘 | 2つに分けて採用 | #245 で `change-adversarial-review` の指摘を実行で裏付けます。`change-review` と `change-security-review` は変えません。High tier では delivery が `blast-radius` も実行し、#245 の隔離、後片付け、証拠のルールを再利用します。 | 1つの隔離の設計を両方で使えます。High tier はすでにレビューを重くしています。 |
| 性能の主張 | 数値を報告する前に説明する | 条件つきで採用 | 変更が高速化や性能低下の数値を主張するとき、本文のルールを適用し、#240 で取り込む計測の workflow を任意 workflow として実行します。 | トリガーが狭く、数値を主張しない変更では実行しません。 |
| 完了 | 繰り返す誤りを構造で防ぐ | 調整して採用 | follow-up 候補の作成条件に4つ目を加えます。同じ種類の指摘がラウンドや delivery をまたいで2回以上起き、構造による防止策を提案しているものです。提案は、`encode-lessons-in-structure` がインストールされていればそれに沿って作り、なければ本文のルールに従います。`correct` は自動では実行しません。 | 現在の条件ではこうした候補は見送りが推奨されます。`correct` はタスクを超えてリポジトリを編集します。 |

### コストの上限

任意 workflow はすべて共通のルールに従います。

- トリガー条件と tier の条件を明記する。
- レビュー対象の head ごとに最大1回呼び出す。1回の呼び出しで、時間の上限内に
  複数の eval ケースや条件を満たす複数の決定を扱える。
- preflight の草案や未コミットの修正の検証など、チェックポイントのコミット前の
  実行は、レビュー対象の head ではなく、その delivery フェーズの入力を単位とする。
- 1回の実行ごとに時間の上限を設ける。
- 実行は既存のローカルレビューのラウンド上限の内側で数える。
- 上限に達した実行は報告し、証拠としては数えない。
- ユーザーが delivery の依頼で示した上限や無効化の指定を優先する。

この共通の数え方は、フェーズの入力を単位とする具体的な決め方を含め、ローカル
レビューの予算の範囲内で下記の基盤の issue が定めます。時間の上限などの数値は、
各行の issue がそれぞれの workflow について決めます。

### プロバイダー間の同等性

インストール済み skill の判定と `not run` の報告を含め、上記はすべて
`delivery-common` に置き、GitHub と Azure DevOps の delivery に同じように適用します。
プロバイダー固有の部分はありません。

### 実装の順序

まず基盤の issue で、任意 workflow の枠組み、Missing Prerequisites の例外、
コストの上限を `delivery-common` に加えます。各行の issue はその上に作り、`architect`
と `arena` の行は1つの preflight の issue にまとめます。`blast-radius` のステップは
#245 も、性能のステップは #240 も待ちます。

## 検討した選択肢

- **原則のルールだけで任意 workflow を設けない。** pstack の有無で delivery の動作は
  変わりませんが、重い確認はユーザーが名指ししたときにしか実行されません。
- **`how`、`why`、`prove-it-works` を `base` に移す。** すべての `base` のインストールが
  変わり、`pstack` profile が分かれます。一方で、これらの skill が担う原則はすでに
  グローバルルールですべての agent に届いています。
- **`create-verification-skill`、`correct`、`evaluate-skill` の完全な比較を自動で実行する。**
  タスク外のファイルを生成する、タスクを超えてリポジトリを編集する、または1回の
  delivery が負担できる以上のコストがかかるため、採用しませんでした。

## 影響

- 任意 workflow により、delivery の確認の深さはインストール状況で変わります。
  報告の `not run` の行でそれが見えるようにします。
- `arena`、`blast-radius`、`evaluate-skill` の明示呼び出し専用のルールに delivery の
  例外が加わり、それらのメタデータと Missing Prerequisites の文面を固定しているテストは、
  実装する issue で一緒に変わります。
