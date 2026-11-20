Meltype Native Google 2.0.2

Windows 10／11 x64向けの非公式IMEです。Google日本語入力が別途必要です。

今回の変更
1. VRChatterのようにかなに読み直せない英語も、Shift+矢印で文節の区切りを動かせるようになりました。
2. Android版と同じく、打った元ローマ字の1音ずつで区切りが移動し、変更後も元ローマ字を保持します。

かなに読み直せる英語は従来どおり日本語の文節として扱います。最後の文節や、選んだ英語の次にかなに読めない英語が続く場合は変更しません。

この配布物のIME本体は、PC適用済み2.0.2-rc.1と同じファイルです。
2.0.2正式版として公開します。

導入
Meltype-Native-Google-2.0.2-Setup.exeを実行してください。
更新後は入力先のアプリを開き直してください。

文脈に応じた候補選択で使用するzenzモデルとCPUランタイムを同梱しています。
モデルの利用にはAVX2対応CPUが必要です。非対応CPUでは通常変換を使用します。
Google／Microsoft変換と、Google変換での文節編集に対応しています。

検証と制限
Shift+矢印の回帰5件、Meltype.Core.Tests 598/598が通過しました。
Meltype.Testsは638/639で、失敗1件はこの実行環境でクリップボード操作が使えない既存試験によるものです。
このSetupの別PC導入、32ビットアプリ、すべての入力アプリでの動作は未確認です。

変更点：docs/RELEASE_2_0_2.md
ライセンス：LICENSEと同梱モデルのライセンスを参照してください。

https://github.com/AoneSenbongi/Meltype/releases/tag/native-google-2.0.2
