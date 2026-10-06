# Meltype Native Google

[雪代／Yukishiro氏のMeltype](https://github.com/yksr-melt/Meltype)を基に、Windowsの入力欄へ未確定文字を表示するIMEと、インストール済みGoogle日本語入力との連携を追加した非公式Forkです。改良は`google-native-ime`ブランチで管理しています。Googleや元作者の公式配布版ではありません。

本家Meltype 1.0.1の判定・辞書・ログ修正を取り込んでいます。PC版は`Meltype-Settings.exe`の管理画面からインストール、起動、停止、単語登録、辞書管理を操作できます。

## できること

Meltypeの日英判別を使い、`kyouhagoogledekensaku`を「今日はgoogleで検索」のように入力できます。日本語の読みが4文字以上になると、Spaceを押す前からGoogleの変換結果で表示を更新します。途中では確定しません。

未確定文字は元の入力欄へ表示し、フォントや色を独自に指定しません。候補選択中だけ白い候補画面を出します。日本語の句読点は全角の「，」「．」。ローマ字入力の区切りで`zh → ←`、`zj → ↓`、`zk → ↑`、`zl → →`を使えます。

Googleの既存辞書・学習履歴を使います。学習が有効なら、確定した日本語を一致確認のうえGoogleにも学習させます。

## インストール

必要なものはWindows 10／11のx64版と、インストール済みのGoogle日本語入力です。ARM版と32ビット版にはこのパッケージを使わないでください。ランタイムはZIPに同梱しているので、Codex・開発環境・別途の.NETインストールは不要です。

1. Google日本語入力をインストールし、一度日本語を入力して動作を確認します。
2. [このForkの1.0.1 Release](https://github.com/AoneSenbongi/Meltype/releases/tag/native-google-1.0.1)のAssetsから、`Meltype-Native-Google-windows-x64-<日時>.zip`をダウンロードして全部展開します。`C:\MeltypeNative`など、移動しない場所へ置いてください。ZIPのプロパティに「ブロックの解除」がある場合は、展開前に解除します。
3. `Meltype-Settings.exe`を開き、「インストール」を押します。普段使うWindowsアカウントで管理者確認を承認してください。Googleの設定と学習データをバックアップしてからIMEを登録します。
4. 「起動」を押します。初回は最大60秒待ちます。スタートメニューにも「Meltypeの管理画面」を追加します。

インストール時に、Windowsへのサインイン後の自動起動を設定します。起動時のコンソールは非表示です。導入済みの場合は`Enable-NativeAutoStart.cmd`で設定できます。解除は`Disable-NativeAutoStart.cmd`です。自動更新はありません。従来のMeltype常駐版が動いている場合は、先に終了します。

ZIPのSHA-256はReleaseの`.sha256`ファイルと比較できます。

```powershell
Get-FileHash .\Meltype-Native-Google-windows-x64-<日時>.zip -Algorithm SHA256
```

詳しくは[自分のPCへの導入](docs/NATIVE_IME_TRANSFER.md)を参照してください。Mac版・Linux版のNative Google連携パッケージは配布していません。

## 使い方

入力欄へローマ字で入力します。日本語はライブ変換し、英語と判別した部分は英字で残します。Spaceで変換候補を選び、Enterで確定します。半角／全角キーで日本語入力と英数の直接入力を切り替えます。

Google本体でも全角の「，」「．」を使う場合は、Google日本語入力のプロパティで句読点を「，．」に設定します。新しい履歴をGoogleへ追加する場合は、Google側で「学習する」を選んでください。

## 停止・更新・削除

管理画面の「停止してGoogleに戻る」で通常のGoogle日本語入力へ戻します。登録の削除は「削除」です。バックアップとGoogleの辞書・学習履歴は残ります。導入済みの場合は、新しいZIPを別の場所へ展開して管理画面を開き、「この版に更新」を押します。再登録は不要です。詳しくは[管理画面の説明](docs/NATIVE_GUI.md)を参照してください。

句読点・疑問符の入力でライブ変換がかなへ戻る問題への修正を公開しています。導入済みの場合はReleaseの`Meltype-Native-PunctuationFix-20261006.zip`を全部展開し、`Update-Punctuation.cmd`を通常起動してください。更新前のDLLをバックアップしてから変換部品を更新します。再登録は不要です。現在の通常ZIPにも修正を含めています。修正適用後、デスクトップPCとノートPCの両方で症状が解消したことを確認しました。

古いパッケージで起動待ちが約4秒で失敗する場合は、Releaseの`Meltype-Native-StartupFix-20261006.zip`を展開し、`tools`フォルダーを導入先へコピーして上書きしてください。

## 検証範囲と制約

WindowsのTSF文書を使った未確定文字・確定・取消の試験、Googleとの接続試験、日英混在と起動待ちの試験を実施しています。登録・有効化と、別のPCでの起動も確認しました。フォント・改行・候補配置は使用するアプリで確認してください。32ビットアプリとストアアプリは未検証です。

Native版では、前後の確定文字の取得やMeltype独自の永続学習をまだ接続していません。元のMeltypeにあるトレイ設定・コードエディター用の判別・ユーザー辞書画面など、一部の機能はNative版で提供していません。

Googleへの接続は非公式IPCを使っています。Googleの更新によって接続できなくなる可能性があります。Google本体のプログラムやシステム辞書は改造・同梱していません。

不具合を報告する際は、アプリ名、入力した操作、期待した動作、実際の動作を記載してください。起動失敗時は画面のメッセージと、`experimental-build`内の`native-broker-errors.txt`・`native-broker-output.txt`も確認できます。

## プライバシー

入力の判別とGoogleへの変換要求はPC内で処理します。入力文字をネットワークへ送信する処理は追加していません。ZIPには個人の設定・辞書・学習履歴を含めず、導入先のGoogleのデータを使います。登録時のバックアップは展開先の`backups`へ保存します。

## 元のMeltypeとライセンス

日英判別と入力処理は、元のMeltypeの成果を基にしています。元作者と協力者への謝意を含む[元のREADME](README.UPSTREAM.md)を保存しています。この文書は元の常駐版の説明であり、上記のNative版の導入手順とは異なります。

MeltypeとこのForkの改良は[GNU GPL](LICENSE)に従って公開しています。配布ZIPには対応するソースを同梱しています。同梱ランタイムのライセンスと第三者の通知は、ZIP内の`runtime/LICENSE.txt`と`runtime/ThirdPartyNotices.txt`を参照してください。

```text
Meltype
Copyright (C) 2026 雪代 / Yukishiro (@yksr_melt / @yksr-melt)

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.
```

ソースからのビルドは[Native版の構成と手順](docs/NATIVE_IME_SETUP.md)、Googleとの接続方式は[Google連携の説明](docs/GOOGLE_IME_EXPERIMENT.md)を参照してください。
