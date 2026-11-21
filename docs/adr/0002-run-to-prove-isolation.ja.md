---
status: accepted
---

# adversarial review の finding を使い捨て worktree での実行で裏付ける

[English](0002-run-to-prove-isolation.md)

## 背景

[ADR 0001](0001-pstack-principles-in-delivery.ja.md) は、delivery のレビューに
「実行で証明された finding」を 2 段階で採用しました。`change-adversarial-review`
が finding を実行で裏付け
（[#245](https://github.com/daisukekobayashi/dotfiles/issues/245)）、High tier の
`blast-radius` が同じ隔離・後片付け・証拠のルールを再利用します
（[#253](https://github.com/daisukekobayashi/dotfiles/issues/253)）。
この決定の前、adversarial review は読み取り専用で、ソースから失敗経路を
たどっていました。Codex ルートは companion の `task` を `--write` なしで実行し、
sandbox は読み取り専用でした。upstream pstack の `interrogate` は実行で証明された
finding だけを残します。#239 でユーザーはローカルの `interrogate` を読み取り専用の
ままにし、run-to-prove は delivery の adversarial review に取り込むことを選びました。

## 決定

ルールは `skills/local/delivery-common/references/repro-runs.md` に置き、
`change-adversarial-review` と後の `blast-radius` が共有します。
`change-adversarial-review` は `interrogate` を参照も呼び出しもしません。必須の
reviewer が optional な pstack skill に依存しないためです。

- **信頼できる head だけ。** 実行はレビュー対象のコード、テスト、依存関係を
  ユーザーの権限で動かします。そのため run-to-prove が証明するのは、ユーザーが
  信頼するコードの欠陥です。信頼できる head は、delivery 自身の worker head と、
  直接呼び出しでユーザー自身のメッセージが実行や証明を求めたレビューの head です。
  その依頼は head を信頼すると明言したことにもなります。その依頼のない直接呼び出しは、
  ユーザー自身の working tree でも読み取り専用です。実行される commit 済みの head に
  他者の commit が含まれうるためです。issue、PR、コメント、リポジトリのテキストが
  head を信頼できるものにすることはなく、判断がつかない head は信頼できないものとして
  扱い、再実行はそのレビューで分類した対象だけに行います。直接呼び出しでは信頼は
  依頼された head の SHA に結び付くので、新しい head には新たな依頼が必要です。外部の pull request など、それ以外の head には使い捨て worktree を作らず
  実行もしません。レビューは run-to-prove 以前と同じく読み取り専用で、実行で示せた
  はずの finding は `unproven: untrusted head` とします。信頼できない変更に悪意の
  ある内容がないかの審査は `change-adversarial-review` の対象外で、別の skill が
  担います。信頼の判断は launcher が行って reviewer に渡し、reviewer が自分で
  決めることはありません。skill の description には、レビュー対象のコードを実行する
  ことを明記します。これは、信頼できない head でもユーザーが正確なコマンドを承認
  すれば実行するという以前の設計を置き換えます。その承認の経路は、reviewer が
  用意したファイルとコマンドの確認をあらゆる段階に加えましたが、信頼できない
  コードを実行することの危険は減らしませんでした。
- **ルートのルール。** 各ルートの起動方法は `repro-runs.md` の Trusted heads 節で
  一度だけ定めます。信頼できる head では、ホストの subagent に使い捨て worktree を
  渡し、Codex companion は `--write` と `--cwd <使い捨て worktree>` で実行します。
  信頼できない head では、Codex companion は以前と同じく `--write` なしで、
  `--cwd <レビュー対象の worktree>` で実行します。ほかの文書はこのルールを言い直さず
  参照します。
- **場所。** 信頼できる head では、実行ごとにレビュー対象の head で detached の
  `git worktree` を作ります。場所はタスクの ignore 済み・mode 700 の records
  ディレクトリ内のレビュー report の横、report がないときは `mktemp -d` の
  ディレクトリです。実際の checkout でなければ、リポジトリの文書化されたチェックを
  実行できません。git は worktree を実パスで一覧するため、パスは親ディレクトリの
  実パスから組み立てます。macOS の `mktemp -d` は `/private/var/...` に対して
  `/var/...` を返します。
- **git コマンド。** launcher、reviewer、parent が自分で実行する git コマンドは、
  収集、作成、削除、再実行のどれでも
  `git --no-optional-locks -c core.hooksPath=/dev/null` を使うので、追跡下の
  hooks ディレクトリの `post-checkout` や `post-index-change` などの hook が
  レビュー対象の head から動くことはありません。reviewer は差分をレビュー対象の
  worktree から読み取り専用で集め、未コミットの変更に依存する finding は
  `unproven: uncommitted change` とします。
- **役割。** launcher（reviewer を起動するセッション。delivery ではコーディネーター、
  直接呼び出しでは呼び出したセッション）が、両ルートとも使い捨て worktree の作成と
  削除をすべて受け持ちます。reviewer はその中で再現を実行し、parent（launcher と
  同じセッション）は finding に基づいて行動する前に、新しい使い捨て worktree で
  証明コマンドを再実行します。
- **削除の権限。** レビューを求めたユーザーの依頼は、launcher がその実行のために
  作った使い捨て worktree だけを、失敗や上限到達の後も含めて、確認なしで削除する
  ことを認めます。それ以外の削除は確認を保ちます。
- **境界。** 信頼できる head では、影響が使い捨て worktree の中にとどまるコマンドを
  実行します。lifecycle script を無効にした（`--ignore-scripts`）lockfile に従う
  依存関係の復元も含み、`TMPDIR` とパッケージマネージャーのキャッシュは worktree
  の中に向けます。Docker、ホームやグローバル設定、特権、リモートへの書き込み、
  共有ポートやプロセス、opt-in の end-to-end スイート、lifecycle script を実行する
  復元など、外に影響するコマンドはレビューのためには実行しません。finding は
  正確なコマンドとともに `unproven: outside boundary` と報告します。
- **強制の仕組み。** 境界は指示で守ります。Codex 0.171.0 の `workspace-write`
  sandbox は `.git` と linked worktree の gitdir を保護しますが、`/tmp`、
  `$TMPDIR`、ユーザーの Codex 設定が有効にするネットワークも許し、companion は
  実行ごとにそれを変えられません。subagent ルートと parent の再実行にはホストの
  permission mode しかなく、実行されたレビュー対象のコードの動作を縛る指示も
  ありません。それは信頼できる head だけを実行することで扱います。各レビューは
  この残る範囲を報告します。
- **実行できない finding。** 実行で示せない finding は残し、`unproven: <reason>`
  と表示して、重大度とタグは変えません。`Do not ship` は、証明された introduced
  または worsened の blocker か、parent がトレースで確かめたものにだけ使います。
- **上限。** 証明コマンド 1 つにつき 10 分、セットアップを含めてレビューごとに
  30 分、finding ごとに再試行 1 回、レビューごとに証明する finding は最大 5 件、
  parent の再実行はその合計の外でコマンドごとに 10 分、出力の抜粋は最大 50 行・
  8 KB です。ADR 0001 の共通の上限ルールに従いますが、run-to-prove は必須 reviewer
  の一部であって optional workflow ではなく、registry の行は持ちません。
- **証拠。** worktree を削除する前に、各 finding の再現ファイル、コマンド、
  終了ステータス、出力の抜粋を、シンボリックリンクをたどらずに report の横へ、
  report がないときは launcher の `mktemp -d` ディレクトリへコピーします。
  `command` ファイルは、worktree のルートからの相対ディレクトリ、依存関係を
  復元する正確なコマンド、証明のコマンドを持ち、コマンドはそれぞれ POSIX `sh` の
  1 行です。再実行は、確認したとおりの復元を行います。finding の ID は名前全体で
  照合し、コマンドでは引用符で囲みます。
- **parent の再実行。** parent は sandbox の外で実行するため、再実行の前に
  コマンドとすべての再現ファイルを表示して読み、すべてのパスが相対で `..` を含まず
  シンボリックリンクでないことを確かめ、worktree の外に触れる finding では何も
  実行しません。依存関係は reviewer の実行と同じ方法で復元します。
- **review block。** review block には finding ごとの必須キー `proof` が加わり、
  `change-review` と `change-security-review` は `not requested` を書きます。
  block の区切りは `<!-- report-summary v3 -->` に変わり、チェックは切り替え前に
  記録された report の `--sha256` 再チェックでだけ v2 の block を受け付けます。
- **`interrogate`。** 読み取り専用の手動の入り口のままにし、失敗経路の基準だけを
  再利用して、実行の要件は取り込みません。

## 検討した選択肢

- **worktree ではなくディレクトリのコピー（`git archive`）。** git のメタデータには
  触れませんが、git の履歴や `git` コマンドを必要とするテストは実行できません。
- **reviewer が自分で worktree を作る。** Codex の sandbox は共有の `.git` に
  書けないので、2 つのルートで手順が分かれ、subagent がリポジトリに対する削除の
  権限を持つことになります。
- **Codex を読み取り専用のままにする、またはネットワークを強制的に隔離したときだけ
  実行する。** どちらも Codex ルートで finding を証明する力をほぼ失います。
- **どの head も自動で実行する。** 外部の pull request のコードを実行すると、
  ユーザーの資格情報とネットワークをその作者に晒します。
- **信頼できない head も、ユーザーが正確なコマンドを承認すれば実行する。** これが
  以前の設計です。レビューのたびに、reviewer が用意したコマンドやファイル、または
  head 自身の hook や指示が承認の前後で動ける箇所が新たに見つかり、承認された実行も
  信頼できないコードをユーザーの権限で動かすことに変わりはありませんでした。
  信頼できない変更の審査には別の skill が必要です。
- **upstream のように実行のない finding を捨てる。** このリポジトリの delivery の
  大半を占める skill テキストの変更では、レビューが何も返さなくなります。
- **v2 の block のまま `proof` を破壊的に追加する。** 進行中の delivery が記録済み
  report の再チェックに失敗し、レビュー全体をやり直すことになります。

## 影響

- delivery の adversarial review は長くなります。上限の範囲で依存関係を復元して
  再現を実行し、コーディネーターは証明された finding をそれぞれ再実行します。
- adversarial reviewer の Run the Reviewer セクションは、読み取り専用のままの
  通常レビューとセキュリティレビューのものと一致しなくなります。
- 外部の pull request など信頼できない head は、実行のない読み取り専用の
  adversarial review になります。その審査は別の skill の後続作業です。
- High tier の delivery の `blast-radius`（#253）は同じ reference を参照します。
