# 現在の状態

## 目的と現在の適用版

Windows Native版を本家Meltypeに近づけ、Microsoft／Googleの変換先選択、自動／英語の切り替え、本家ロゴ、画面下端の候補配置、本家1.2.0の定型文登録・展開を提供する。正式公開の予定番号は1.1.0。本家の取り込み済み基準はv1.2.1、47ace1428e5d4c9213f64dbbaf00d73a01386c69。Androidはこの作業で変更しない。

2026年10月11日、このPCへ1.1.0-rc.4を適用した。BaseVersionは1.2.1。登録先はC:/Program Files/MeltypeNativeGoogle/package-167eace784f144a380ebb6dee210b1d2。稼働管理先はC:/Users/AoneSenbongi/Documents/Codex/2026-10-06/https-x-com-yksr-melt-statusを保持する。管理スクリプト・状態はrc.4へ更新済み。直接更新のためWindowsのアプリ一覧は先に適用した1.1.0表記のまま。入力アプリは新しいDLLを読み込むため開き直す必要がある。

## 実装と検証

変換先はinput-preferences.jsonのConversionEngineで選択し、新しい接続で反映する。初期値はGoogle。Microsoftは本家の変換・候補取得・日英判別を専用STAスレッドで使う。Googleは従来の通常変換と学習を維持し、予測は本家コアを使う。Microsoftの辞書への学習書き込みは未対応。

利用者の「押しても自動のまま」を受け、WindowsのKEYBOARD_OPENCLOSE区画との同期とINPUTMODECOMPARTMENTカテゴリを追加した。閉じた英語モードから半角／全角で戻るためVK_KANJIを保持キーとして登録する。旧DLLで区画の有効化がない状態を再現し、修正後はクリック・キー・Windowsからの状態変更と通知が通過した。入力欄がないときの無効表示はWindowsの通常挙動として残す。パスワード欄・読み取り専用欄の保護を維持する。

アイコンは本家docs/images/logo.pngを使う。利用者の追加指示により、中央の水色・ピンクの文字を大きく切り抜き、16～256pxのICOとしてDLLへ組み込む。旧rc.2の小さいロゴが視認性の試験に失敗し、拡大版と導入済みDLLが通過した。候補は下に収まらなければ上へ置き、モニターの作業領域内へ収める。

定型文は本家SnippetsFormとSnippetStoreを使い、管理画面の「定型文を登録・管理」とトレイの「定型文...」から開く。登録・編集・削除・JSONの取り込みと書き出しを提供する。自動モードで行の先頭か空白の直後に「;名前」を入力し、Space／Tabで複数行を展開、直後のEscで元に戻す。Native TSFでは名前と展開結果を未確定範囲へ表示し、Enterまたは次の入力で確定する。保存先はLOCALAPPDATA/Meltype/snippets.json。コード内のセミコロンと未登録名は展開しない。登録変更を次の定型文入力から読み直す。英語モードは直接入力。仕様はdocs/NATIVE_SNIPPETS.md。

Native関連17/17、Google13/13、Microsoft2/2、両エンジンからTSF文書への変換・確定・取消、予測、候補配置、モードとロゴの試験が通過した。定型文の本家画面の登録・編集・削除・保存と描画、複数行・Esc復元・Tab展開・確定・取消、製品brokerの通信からTSF文書への反映を隔離したファイルで検証した。管理画面、更新候補判定、版番号一致も通過。実アプリごとの新機能の実操作、複数モニター、32ビットアプリは未確認。

導入済み6ファイルのmanifestとの一致、登録番号、サービス接続準備、定型文を開くスクリプトの一致、導入済みDLLのモード・拡大アイコンを確認した。バックアップはE:/prog/Meltype/Windows/backups/20261011-235841で、11ファイルの退避ハッシュが一致した。稼働中の履歴は変化するため適用前後の全ファイル一致は主張しない。rc.2時点ではGoogle辞書・設定は一致し、phrases.txtは既存行の削除なしで2行追加、history.dbは変化を確認した。

定型文画面の初回起動がコンソールと一緒に隠れる不具合を再現し、初回表示後に画面を表示し直すよう修正した。1.1.0-rc.4の導入済みスクリプトの一致、実際の登録画面が表示されること、サービスの接続準備を確認した。証跡はexperimental-build/native-snippet-rc4-apply.logとapplied.json。

証跡はexperimental-build/native-snippet-rc3-build.log、同接頭辞のapply.logとapplied.json、native-snippets-form.png、native-snippet-panel.png。定型文の通信試験はtools/native-ime/Test-NativeSnippets.ps1。Build-Packageから同試験を実行するよう追加済み。製品コードは適用済みだが、その後に追加した試験・資料の更新は配布物を再構築していない。

## 本家の朝監視

独立したローカル定期タスクmeltype-luna-6-1-solはACTIVE、毎朝9時、日本時間、gpt-6-luna、medium。更新時のみgpt-6.1-solへ委任する。利用者は独立タスクとこの委任を明示的に承認済み。変更なしの通知はしない。PCとCodexの起動が必要。

手順はdocs/UPSTREAM_MONITOR.md、状態はLOCALAPPDATA/MeltypeUpstreamMonitor/state.json。初回のGitHub API確認では本家Release v1.2.1とmain 47ace14が取り込み済み基準と一致した。予定実行と更新検出から委任までの実行は未確認。競合する進行中の作業や未コミット変更は上書きしない。

このPCへの自動適用は既存の承認範囲で、検証・バックアップ・適用確認後に行う。最新の利用者指定AGENTS.mdでは、外部公開の前に今回の内容への確認が必要。過去の包括的な公開許可を今回の確認として扱わない。定期タスクのプロンプトと手順をこの規則へ合わせた。

## 残作業と公開状態

1. 入力アプリを開き直し、利用者の環境で自動／英語、拡大アイコン、登録した定型文を確認する。
2. 修正後の正式番号1.1.0で配布物を再構築する。現在の旧1.1.0 EXEはb589694に対応し、モード修正・拡大アイコン・定型文対応を含まないため公開しない。
3. 公開先AoneSenbongi/Meltype、ブランチgoogle-native-ime、タグnative-google-1.1.0、本文docs/RELEASE_1_1_0.md、EXEと.sha256の具体的な内容を準備して提示する。承認後にpush・タグ・Release公開を行う。修正版のGitHub公開は未実施。公開済みの最新基準はnative-google-1.0.7、be41abe。

既存のWindows検索、句読点と学習停止、通信枠32、管理者確認付きの保護配置・復旧、管理画面・オンライン更新を維持する。Win10/11の検索パッケージはOSビルド22000を境に切り替える。ThinkPad側のWin11検索修正は統合済み。このPCの検索入力は過去に利用者確認済みだが、今回の追加機能の実検索欄操作は未確認。本家の選択範囲再変換とTab文節変換は独自TSFでは未対応。突然の停止報告と接続枠不足との因果は未確定。