# 本家main 45e14f8のWindows取り込み

2026年10月15日の朝監視で、9a25e7c27a842a51a7df7d485fb88aa07caca6bcから45e14f86558aa6ea34f2c2ecd038ba95ca8c3c46までの26コミットを検出した。本家の通常ReleaseとBaseVersionは1.2.1。Windows Native候補は既存1.1.2-rc.2の次の1.1.2-rc.3とする。

作業場所はE:/prog/Meltype/Tools/1.1.1-source、開始コミットは7f942db0b322a98481802123935bdc15be124773。Windowsの利用者の未コミット作業とAndroidは編集しない。macOS、fcitx5、botの製品変更は対象外。共通コア、辞書、Windows、本家TIPと関連試験・資料を三者比較で取り込む。

独自TSFにもプライベート入力欄への対応を接続する。IS_PRIVATEでは入力・変換を許可し、Googleへの学習、変換履歴、フレーズ履歴を抑止する。パスワード、PIN、読み取り専用、IME無効欄の保護は保持する。既存バイナリ通信の要求フラグにprivateを追加し、入力欄の種類をキーごとに確認する。通常欄に戻れば設定に従って学習する。

独自TSFの候補上部にも打鍵ローマ字を表示する。本家のShowTypedKeys設定に従い、表示文字と同じ英字は省略する。候補のページ送り、画面端配置、再描画を保持する。要求フラグで対応を通知した接続だけに、候補応答の末尾へ打鍵文字列を追加する。従来の接続の応答形式は保持する。

Microsoft／Google切替、本家アイコン、自動／英語表示、直接入力判定、選択範囲再変換、Tab変換、辞書・学習履歴、Windows検索、句読点と学習停止を保持する。追加試験で旧実装の不具合を確認してから実装し、共通・Windows、品質、Native、Google、Microsoft、実TSF、設定、検索、配布物とインストーラーを検証する。

PC適用は標準アップデータとバックアップを使い、通常の管理者確認を受ける。登録番号、配置manifest、broker起動、辞書・設定を確認する。確認待ちや取消を適用済みと扱わない。外部公開は今回内容への個別承認がないため行わない。

2026年10月15日、共通・Windows494/494、品質1337/1337、Native18/18、Google13/13、Microsoft2/2が通過した。旧実装でShift解放、感嘆符候補、IS_PRIVATE保護、private要求での学習発生、打鍵応答欠落を再現した。実TSFでは直接入力判定、かな・漢字・ローマ字の再変換、Tab変換、private変換と学習抑止、通常欄への復帰後の学習、password/PIN保護が通過した。プライベート学習の試験はMicrosoft変換と隔離データを使い、製品の辞書・履歴を使っていない。

候補上部の打鍵、同一英字の非表示、打鍵だけの表示、従来応答の互換性、画面端配置と再描画を検証した。検索のWin10/11パッケージSID、AppContainerからGoogleまでの入力、通信32枠、句読点・学習停止と既存入力設定、更新候補、管理画面、インストーラーと更新失敗時の復旧も通過した。管理画面の画像はexperimental-build/upstream-45e14f8-panel.png。証跡は同ディレクトリのupstream-45e14f8-*.logとnative-upstream-features.log。

試験の三者統合時にCompositionTestsの同位置への追加が1件競合した。既存の学習停止・並行フレーズ更新の試験を保持し、本家の感嘆符試験を追加して解消した。製品実装の競合はない。通常.NETビルドの既存nullable警告は3件。SDKは既存のAndroid/dotnetを読み取り利用し、Androidソースを編集していない。

対応ソースをadf81c7ce23ca4bbb92042f2fa60d3967f0dfefeに固定し、distributions/Meltype-Native-Google-1.1.2-rc.3-Setup.exeと.sha256を構築した。EXEのSHA256は6F09BA2522C5C4B262C63C4254E0AC2E0B65CA7A277C05A051CED802BED5AFDC。製品番号1.1.2-rc.3、ファイル番号1.1.2.0、配置対象6ファイルとmanifest、同梱主要ソース18点、対応ソース番号、SHA256を照合した。同梱ソースはGitの改行変換があるため、UTF-8テキストとしてCRLF/LFを正規化して比較した。バイナリとEXEは生のSHA256で比較した。証跡はexperimental-build/upstream-45e14f8-verified.json。

PC適用は未完了。外部公開は未実施。実アプリの手入力、複数モニター、テーマ切替、32ビットアプリは未確認。Microsoft辞書への学習書き込みは未対応。
