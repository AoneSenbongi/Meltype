# 自分のPCへの導入

対象はWindows 10／11の64ビット版。ARM版と32ビット版にはこのZIPを使わない。Google日本語入力は別途インストールする。開発環境やCodexは不要。

1. Google日本語入力をインストールし、一度日本語を入力して動作を確認する。
2. ZIPを`C:\MeltypeNative`など、移動しない場所へすべて展開する。ZIP内から直接起動しない。ダウンロードしたZIPに「ブロックの解除」がある場合は、展開前にプロパティで解除する。
3. `Meltype-Settings.exe`を開き、「インストール」を押す。普段使うWindowsアカウントで管理者確認を承認する。Googleの設定と学習データをバックアップしてからIMEを登録する。
4. 「起動」を押す。スタートメニューにも「Meltypeの管理画面」を追加する。

本家Meltype 1.0.1を取り込んだ版。導入済みの場合は、新しいZIPを別の場所へ展開して`Meltype-Settings.exe`を開き、「この版に更新」を押す。Googleの設定・履歴と更新前のファイルをバックアップしてから更新する。再登録は不要。単語登録、辞書管理、Googleの設定、自動起動の切替も管理画面から操作できる。画面を閉じるとトレイに格納する。

日本語の句読点は全角の「，」「．」。ローマ字入力の区切りで`zh → ←`、`zj → ↓`、`zk → ↑`、`zl → →`を使える。Google本体でも同じ句読点を使う場合は、Google日本語入力のプロパティで句読点を「，．」に設定する。Googleへ新しい履歴を追加する場合は「学習する」を選ぶ。

インストール時にWindowsへのサインイン後の自動起動を設定する。起動時のコンソールは非表示。導入済みの場合は`Enable-NativeAutoStart.cmd`で設定し、解除は`Disable-NativeAutoStart.cmd`で行う。設定変更前の自動起動情報は`backups`に保存する。通常のGoogle日本語入力へ戻す場合は`Stop-NativeIme.cmd`を起動する。次回のサインインでもGoogleを使う場合は、自動起動も解除する。削除する場合は`Uninstall-NativeIme.cmd`を管理者として実行する。自動起動も解除し、バックアップは残る。登録後にフォルダーを移動する場合は、先に登録を削除する。

句読点・疑問符の入力でライブ変換がかなへ戻る問題への修正を公開している。修正適用後、デスクトップPCとノートPCの両方で症状の解消を確認した。導入済みの場合はReleaseの`Meltype-Native-PunctuationFix-20261006.zip`を展開し、`Update-Punctuation.cmd`を通常権限で実行する。既存の登録先を確認し、更新前のDLLをバックアップしてから変換部品だけを入れ替える。IMEの再登録と辞書の移行は不要。

個人の辞書・学習履歴・設定はこのZIPに入っていない。導入先のPCにあるGoogleの辞書と履歴を使う。実際のアプリでのフォント・改行・候補配置は導入後に確認する。32ビットアプリとストアアプリは未検証。

ソースは同梱の`corresponding-source.zip`と[GitHubのFork](https://github.com/AoneSenbongi/Meltype/tree/google-native-ime)で確認できる。対応するコミットは`SOURCE_VERSION.txt`に記載している。Meltypeのライセンスは`LICENSE`、同梱ランタイムのライセンスと第三者の通知は`runtime/LICENSE.txt`と`runtime/ThirdPartyNotices.txt`を参照。
