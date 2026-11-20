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

- **場所。** 実行ごとに、レビュー対象の head で detached の `git worktree` を
  作ります。場所はタスクの ignore 済み・mode 700 の records ディレクトリ内の
  レビュー report の横、report がないときは `mktemp -d` のディレクトリです。
  実際の checkout でなければ、リポジトリの文書化されたチェックを実行できません。
- **役割。** launcher（reviewer を起動するセッション。delivery ではコーディネーター、
  直接呼び出しでは呼び出したセッション）が、両ルートとも使い捨て worktree の作成と
  削除をすべて受け持ちます。reviewer はその中で再現を実行し、parent（launcher と
  同じセッション）は finding に基づいて行動する前に、新しい使い捨て worktree で
  証明コマンドを再実行します。
- **削除の権限。** レビューを求めたユーザーの依頼は、launcher がその実行のために
  作った使い捨て worktree だけを、失敗や上限到達の後も含めて、確認なしで削除する
  ことを認めます。それ以外の削除は確認を保ちます。
- **出所。** 実行はレビュー対象のコード、テスト、依存関係をユーザーの権限で
  動かします。そのため、そのコードの作者は攻撃者の位置にあり、reviewer の再現を
  誘導するテキストの作者も同じです。実行が自動になるのは、delivery 自身の worker
  head か、呼び出したユーザー自身のローカルの変更だけです。外部の pull request や
  他者のブランチやコミットなど、それ以外の head では reviewer は何も実行せず、
  正確なコマンドを `unproven: needs approval` として報告し、parent はユーザー自身の
  メッセージで承認された後にだけそれを実行します。skill の description には、
  レビュー対象のコードを実行することを明記します。
- **境界。** 影響が使い捨て worktree の中にとどまるコマンドは自動で実行します。
  lifecycle script を無効にした（`--ignore-scripts`）lockfile に従う依存関係の
  復元も含み、`TMPDIR` とパッケージマネージャーのキャッシュは worktree の中に
  向けます。その script が必要なチェックは、script を実行する復元コマンドの承認を
  求めます。Docker、ホームやグローバル設定、特権、
  リモートへの書き込み、共有ポートやプロセス、opt-in の end-to-end スイートなど、
  外に影響するコマンドを reviewer は実行しません。finding は正確なコマンドとともに
  `unproven: needs approval` と報告し、parent はユーザーの承認後にだけ実行します。
- **強制の仕組み。** 境界は指示で守ります。Codex ルートは
  `--write --cwd <使い捨て worktree>` で実行します。Codex 0.171.0 の
  `workspace-write` sandbox は `.git` と linked worktree の gitdir を保護しますが、
  `/tmp`、`$TMPDIR`、ユーザーの Codex 設定が有効にするネットワークも許し、
  companion は実行ごとにそれを変えられません。subagent ルートと parent の再実行には
  ホストの permission mode しかなく、実行されたレビュー対象のコードの動作を縛る
  指示もありません。それは出所のゲートで扱います。各レビューはこの残る範囲を
  報告します。
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
  `command` ファイルは、worktree のルートからの相対ディレクトリと、POSIX `sh` の
  1 行を持ちます。
- **parent の再実行。** parent は sandbox の外で実行するため、再実行の前に
  コマンドとすべての再現ファイルを表示して読み、すべてのパスが相対で `..` を含まず
  シンボリックリンクでないことを確かめ、worktree の外に触れるものは
  `unproven: needs approval` として扱います。
- **パス。** git は worktree を実パスで一覧するため、使い捨て worktree のパスは
  親ディレクトリの実パスから組み立てます。macOS の `mktemp -d` は
  `/private/var/...` に対して `/var/...` を返します。review block には
  finding ごとの必須キー `proof` が加わり、`change-review` と
  `change-security-review` は `not requested` を書きます。block の区切りは
  `<!-- report-summary v3 -->` に変わり、チェックは切り替え前に記録された report の
  `--sha256` 再チェックでだけ v2 の block を受け付けます。
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
- **どの head も自動で実行する、または sandbox の中でだけ再実行する。** 外部の
  pull request のコードを承認なしで実行すると、ユーザーの資格情報とネットワークを
  その作者に晒します。companion は parent 自身の再実行のための sandbox を
  提供しません。
- **upstream のように実行のない finding を捨てる。** このリポジトリの delivery の
  大半を占める skill テキストの変更では、レビューが何も返さなくなります。
- **v2 の block のまま `proof` を破壊的に追加する。** 進行中の delivery が記録済み
  report の再チェックに失敗し、レビュー全体をやり直すことになります。

## 影響

- delivery の adversarial review は長くなります。上限の範囲で依存関係を復元して
  再現を実行し、コーディネーターは証明された finding をそれぞれ再実行します。
- adversarial reviewer の Run the Reviewer セクションは、読み取り専用のままの
  通常レビューとセキュリティレビューのものと一致しなくなります。
- High tier の delivery の `blast-radius`（#253）は同じ reference を参照します。
