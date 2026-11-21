---
status: accepted
---

# Codex レビューの実行が起動したプロセスツリーを所有関係で停止する

[English](0003-stop-process-trees-a-review-run-started.md)

## 背景

Codex ルートのローカルレビュー（`change-review`、`change-adversarial-review`、
`change-security-review`）は、対象 worktree に対して `codex-companion.mjs task`
を実行します。[#99](https://github.com/daisukekobayashi/dotfiles/pull/99) 以降、
レビューは実行の前後に取った 2 つの `list-processes.sh` の一覧を比べ、その実行が
起動した companion の `app-server-broker.mjs` のツリーを停止してきました。
選ぶのは、`app-server-broker.mjs` を実行していて cwd が対象のルートと一致する
プロセスと、2 回目の一覧でのその子孫でした。

#249 の delivery では、`codex-linux-sandbox -> node -> git hash-object --stdin`
のような sandbox 内のコマンドのツリーが実行後も入力待ちのまま残り、worktree の
cleanup manifest で初めて見つかりました
（[#262](https://github.com/daisukekobayashi/dotfiles/issues/262)）。2 回目の一覧を
取る時点で、こうしたツリーはもう broker の下にありません。共有 broker が使用中の
とき companion は直接の `codex app-server` 子プロセスに切り替え、終了時にはその
app-server だけに SIGTERM を送ります。また、シェルや app-server が先に終了した
コマンドは親が付け替わります。broker だけを見るルールではこれらのツリーが
見えませんでした。Codex のラッパー名もプラットフォームで異なり、macOS の
Seatbelt ラッパーは親プロセスとして残らないと考えられます。

このようなホストでは、他のエージェントのセッションが隣の worktree や同じ
worktree でコマンドを実行し、エージェントのツールのシェルには tty がありません。
レビューは確認なしでプロセスを停止するので、その実行が何を起動したかを決める
ルールが、他のセッションの作業を止めないための境界になります。

## 決定

レビューの実行が起動したすべてのプロセスツリーを 1 つのルールで扱い、broker は
その一例とします。ルールはスクリプト
`skills/local/worktree-runtime-cleanup/scripts/stop-run-processes.mjs` が実装し、
`worktree-runtime-cleanup` の「Process Trees Started by a Codex Review」節が
呼び出し、レビュー skill と `repro-runs.md` がその節にリンクします。

- **記録と停止。** 実行の前、または 1 つの worktree に対して同時に始める実行の
  組の前に、`record` が全プロセスの PID と開始時刻を対象の外の新しい mode 0600
  のファイルに書きます。実行の後、`stop` が `list-processes.sh` で対象を一覧し、
  新しいプロセス表を取ります。
- **所有関係。** あるプロセスをその実行が起動したとみなすのは、PID と開始時刻で
  記録になく、reason `cwd under target` かつバックスラッシュを含まない cwd で
  一覧され、対象の下に登録された worktree の外にあり、tty がなく、親が pid 1
  か 0、または実行が起動した別のプロセスであるときだけです。所有関係は時刻と
  場所で決め、プロセス名では決めません。
- **表全体での祖先。** 実行前から存在した親（cwd がどこであっても）の下の
  プロセスや、対象の外の新しい親の下のプロセスは `left` と報告し、シグナルを
  送りません。pid 1 と 0 だけは既存とみなさずに祖先の連鎖を終えます。実行の
  残りは親が付け替わってそこに来る孤児だからです。
- **シグナル。** 起動された各ツリーの最上位に、開始時刻を確かめ直してから
  SIGTERM を送り、約 10 秒後、開始時刻が同じまま動いている起動されたプロセスに、
  親が付け替わっていてももう一度だけ SIGTERM を送ります。SIGKILL は使わず、
  起動されたツリーの外にはシグナルを送りません。実行が起動したものは実行が所有
  するので、停止に確認は要りません。
- **失敗。** `list-processes.sh`、`ps`、git が実行できないとき、または記録が
  使えないとき、スクリプトは終了コード 1 で終わり、何にもシグナルを送りません。
  teardown は未検証と報告し、worktree の cleanup に任せます。残ったものは
  レビュー結果を変えません。

## 検討した選択肢

- **`codex-linux-sandbox` などの sandbox ラッパー名で照合する。** 変更は最小
  ですが、Codex の内部の名前を追いかけることになり、macOS や、ラッパーがすでに
  終了したツリーを見落とします。
- **一覧に載ったプロセスだけで祖先を判定する。** 記録は小さくなりますが、実行中
  に他のセッションが対象で実行したコマンドは、持ち主が一覧の外にあるため停止
  されてしまいます。
- **`systemd --user` などの既知の subreaper を pid 1 として扱う。** より多くの
  Linux ホストを扱えますが、所有関係をまたプロセス名で決めることになります。
- **レビューのエージェントがたどる文章のままにする。** 選択、確認し直し、
  エスケープのルールは機械的で、文章は何度も修正が必要でした。また、ツリーが
  停止されることは停止を実際に走らせないと示せません。
- **`list-processes.sh` の隣の Bash スクリプトにする。** skill のスクリプトの
  言語を 1 つに保てますが、祖先の走査と記録の扱いには Bash 3.2 にない連想配列が
  要ります。companion が node なので、Codex ルートが動く場所には必ず node が
  あります。

## 影響

- レビューは broker だけでなく、その実行が対象の下で起動したすべてのツリーを
  確認なしで停止します。
- 孤児の親が pid 1 ではなく既存の subreaper に付け替わるホストでは、実行の残りは
  `left` と報告され、これまでどおり worktree の cleanup に回ります。
- 実行中に他のセッションが対象で起動したプロセスが停止されるのは、親の連鎖全体も
  実行中に対象の下で起動されたとき、たとえばそのセッションがそこで起動した
  切り離されたデーモンのときだけです。
- worktree の cleanup（`github-worktree-cleanup`、`azure-devops-worktree-cleanup`）
  は確認付きの独自の停止を保ちます。後でこのスクリプトを採り入れることもできます。
