Meltype Native Google 2.0.1

Windows 10／11 x64向けの非公式IMEです。Google日本語入力が別途必要です。

今回の変更
1. 文章末尾の空の括弧を確定すると、括弧の内側へ移動します。
2. 内側の文章を確定すると、閉じ括弧の外へ移動します。

管理画面の「カッコを打ったら中にカーソルを移動」を有効にしてください。
以前からある括弧の内側を手動で編集する場合は、自動で外へ移動しません。

この配布物のIME本体は、PC適用済み2.0.1-rc.9と同じファイルです。
2.0.1正式版として公開します。

導入
Meltype-Native-Google-2.0.1-Setup.exeを実行してください。
更新後は入力先のアプリを開き直してください。

文脈に応じた候補選択で使用するzenzモデルとCPUランタイムを同梱しています。
モデルの利用にはAVX2対応CPUが必要です。非対応CPUでは通常変換を使用します。
Google／Microsoft変換と、Google変換での文節編集に対応しています。

検証と制限
共通・Windowsの自動試験638件と、実TSF文書での括弧操作を検証しました。
このSetupの別PC導入、32ビットアプリ、すべての入力アプリでの動作は未確認です。

変更点：docs/RELEASE_2_0_1.md
括弧操作の仕様：docs/BRACKET_COMMIT_NAVIGATION.md
ライセンス：LICENSEと同梱モデルのライセンスを参照してください。

https://github.com/AoneSenbongi/Meltype/releases/tag/native-google-2.0.1
