---
status: accepted
---

# pstack の原則を索引を通じて取り込む

[English](0004-adopt-pstack-principles-through-an-index.md)

## 背景

上流の pstack（[`cursor/plugins@0b46ec3`](https://github.com/cursor/plugins/tree/0b46ec399d55f2829e88822998f53b84944837d3/pstack)）
には24の原則があり、それぞれが `disable-model-invocation: true` を持つ
`principle-*` skill です。`poteto-mode` は Principles 節でそれらを一覧にし、
適用する原則の leaf を読み、原則名とそれが変えた判断を名指しします。

[ADR 0001](0001-pstack-principles-in-delivery.ja.md) は pstack を、実物を確かめることと
繰り返す誤りを構造で防ぐことの2原則と読み、delivery のフェーズの記述に短いルールを
書き込みました。ローカルでは `prove-it-works`・`encode-lessons-in-structure`・
`explain-the-number` が索引のない別々の `base` skill で、抑制側の原則は
[#310](https://github.com/daisukekobayashi/dotfiles/issues/310) によるグローバルルールの
一部としてしかありませんでした。
[#255](https://github.com/daisukekobayashi/dotfiles/issues/255) の delivery
（[PR #309](https://github.com/daisukekobayashi/dotfiles/pull/309)）では、local review が
4ラウンドにわたり同じ領域で新しい欠陥を見つけ、各修正は1つの共通の前提のもとで手順を
足し続けました。推奨された設計も、元にした上流 skill よりずっと重いものでした。
[#311](https://github.com/daisukekobayashi/dotfiles/issues/311) の範囲を決める中で、
原則ごとに1文の delivery ルールにすると各ルールの一部が落ち、delivery の中でしか
効かないことが分かりました。

## 決定

### 索引と leaf

`principles` skill を索引とします。上流の24原則すべてを、いつ適用するかと、次の
扱いのどれか1つとともに列挙します。

- **leaf:** 根拠に基づいて採用し、`principle-<title>` skill が全文を持つ。
- **既存:** 既存の skill やルールがその原則の中核の判断を担う。例: Exhaust the
  Design Space は `arena`、Never Block on the Human はグローバルの承認の段階。
  参照先が担わない部分は行に書く。
- **不採用:** ローカルの規則と衝突する、または当てはまる対象がない。理由を書く。
- **根拠待ち:** 衝突はないが、記録された根拠がまだない。issue に引用された再発や
  失敗の記録があれば leaf に昇格できる。

leaf は、#255 の根拠で選んだ `principle-attack-the-premise`・
`principle-subtract-before-you-add`・`principle-laziness-protocol`・
`principle-fix-root-causes`・`principle-redesign-from-first-principles` と、上流に
合わせて改名した `principle-prove-it-works`・`principle-encode-lessons-in-structure`・
`principle-explain-the-number` です。旧名の skill は残しません。ユーザーが skills の
setup を再実行すると、存在しなくなった skill へのリンクは外れます。

agent が自分で起動する原則の skill は索引だけで、その description が leaf の適用
場面を挙げ、pstack の原則が名前（title または上流の skill 名）で言及されたときにも
起動します。この名前の条件は言及があったときだけ当たるので、下で退けた作業開始時の
条件とは違います。leaf は上流と同じく両 agent で明示起動のみ
（`disable-model-invocation: true` と `allow_implicit_invocation: false`）で、
索引か workflow skill のリンクから読みます。原則を適用するときは、その leaf または
参照先を全文読み、原則名とそれが変えた判断を、その判断を報告する行に書きます。
報告に専用の欄は設けません。

新しい leaf は上流の本文を保ちます。leaf がタスクに適用される承認・安全・範囲の
規則と衝突するときはそれらの規則が優先し、leaf の `Source` 節にその差分を列挙します。
索引と leaf は、agent の権限を与える・制限する・条件づける規則を追加しません。

### 依存の方針

索引は8つの leaf にリンクします。そのため `skills export` は leaf を一緒に運び、
索引が必要とする leaf を除外すると失敗します。既存の skill、グローバルルール、
外部 skill はリンクせず名前で示します。leaf から索引へはリンクしません。
workflow skill は使う leaf へのリンクを保ちます。

delivery は索引に依存しません。`delivery-common` は索引をリンクせず名前で示し、
フェーズのルールは索引がなくても成り立ちます。これは ADR 0001 の依存の方針が
すべての pstack skill にすでに求めていることです。そのため export した `github`
bundle の依存は、引き続き `delivery-common` と `worktree-runtime-cleanup` だけです。

### 役割

- `ai-rules/base/global.md` のグローバルルールは、再発する失敗や完了の根拠のルール
  のような、常に効く短い形を持ちます。語数の上限内にとどまり、索引を指しません。
- 索引と leaf は全文を持ち、delivery の内外を問わず原則を適用するときに読みます。
- delivery のフェーズの記述は、ADR 0001 のもとで、どのフェーズが原則を適用するかを
  示します。抑制側の leaf を delivery のフェーズにつなぐのは #311 の作業です。

## 検討した選択肢

- **原則ごとに1つの delivery ルール。** 各ルールの一部が落ち、delivery の中でしか
  効かないため採用しませんでした。
- **24原則すべてを leaf として取り込む。** この環境では根拠に基づいて原則を選ぶため
  採用しませんでした。
- **leaf を model-invocable にする。** 入口を1つにすると各 agent の skill 一覧の
  description が1つで済み、上流とも一致するため採用しませんでした。
- **グローバルルールに索引への pointer を置く。** `global.md` は語数の上限にあり、
  pointer を置くと合意済みのルールを押し出すため、今は採用しませんでした。
- **`poteto-mode` と同じく作業の開始時に読む。** 上流が索引を読むのはユーザーが
  入るモードの中だけです。常に効く description にこの条件を置くと、ほぼすべての
  作業で索引が読まれるため採用しませんでした。
- **旧名の stub を残す。** 旧名に依存する公開の契約や保存データはなく、setup が
  旧リンクを外すため採用しませんでした。

## 影響

- delivery の外で agent が抑制側の原則に届くのは、索引の description が状況に
  合ったときだけです。delivery の中では #311 のフェーズの記述から届きます。
- 改名の後、ユーザーは skills の setup を再実行します。それまでは旧名のリンクが
  壊れたままです。
- 根拠待ちの原則を昇格させるには、記録された根拠と leaf が必要で、索引の行も一緒に
  変わります。
