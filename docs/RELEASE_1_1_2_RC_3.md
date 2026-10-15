# Meltype Native Google 1.1.2-rc.3

本家mainの45e14f8までを取り込んだWindows Native版のローカル候補。本家の通常ReleaseとBaseVersionは1.2.1。Windows x64向け。Android、macOS、Linuxの製品実装は変更していない。

ブラウザーがIS_PRIVATEを指定する入力欄で、学習を止めて入力・変換できるようにした。Googleへの学習、Meltypeの変換履歴とフレーズ履歴を抑止する。通常の入力欄に戻ると、既存の設定に従って学習する。パスワードとPIN、読み取り専用欄、IME無効欄の保護は保持する。

本家のShowTypedKeys設定に従い、候補の上部に打鍵ローマ字を表示する。入力中の英字と表示文字が同じ場合は省略する。複数キーボード時にShiftの解放がアプリへ届かない不具合の修正、「いめ」のIME候補、感嘆符の‼️候補、破損設定の退避失敗ログも取り込んだ。

Microsoft／Google切替、本家アイコン、自動／英語表示、画面端の候補配置、直接入力のローマ字判定、選択範囲再変換、Tab変換、辞書・学習履歴、検索、句読点と学習停止を保持する。

共通・Windows494/494、品質1337/1337、Native18/18、Google13/13、Microsoft2/2が通過。旧実装でShift解放、感嘆符候補、private入力の学習発生と打鍵応答の欠落を再現し、変更後の試験が通過した。実TSFのprivate変換・学習抑止・通常欄の学習再開、既存の直接入力判定・再変換・Tab変換、予測16更新、定型文各11更新、入力モード、候補配置と再描画、設定、検索のAppContainer入力、通信32枠、更新・復旧、管理画面、インストーラーの隔離試験も通過した。証跡はexperimental-build/upstream-45e14f8-*.log。

通常.NETビルドの既存nullable警告は3件。実アプリの手入力、複数モニター、テーマ切替、32ビットアプリは未確認。Microsoft辞書への学習書き込みは未対応。配布物にはMozcヘルパーを含めない。PC適用時には通常の管理者確認とバックアップを使う。今回候補のPC適用と配布物の構築は進行中。

公開予定先はAoneSenbongi/Meltypeのgoogle-native-ime、候補タグはnative-google-1.1.2-rc.3。タイトルは「Meltype Native 1.1.2-rc.3 本家main更新とプライベート入力対応」。公開本文は本書を基本とし、今回の検証結果と制限を確定して提示する。添付予定はdistributions/Meltype-Native-Google-1.1.2-rc.3-Setup.exeと同名.sha256。今回内容への個別承認がないため、push、タグ作成、Release公開は行わない。
