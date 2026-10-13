# 現在の状態

## 目的と現在の適用版

Windows Native版を本家Meltypeに近づけ、Microsoft／Googleの変換先選択、自動／英語の切り替え、本家ロゴ、画面下端の候補配置、本家1.2.0の定型文登録・展開を提供する。現在の依頼は、英語しか入力できないときは「英語」、日本語を含む自動入力が可能なときは「自動」をタスクバーへ表示すること。現在の依頼は正式版1.1.1の公開準備。PC適用版は1.1.1-rc.2。本家の検証済み取り込み基準はv1.2.1、53fafd036b4d06fab7dae9ca0b9ea4eeafbfe976。Androidはこの作業で変更しない。

2026年10月13日、初回の管理者確認は取り消されたが、利用者の再実行指示後に通常更新手順で1.1.1-rc.2をPCへ適用した。現在のPC適用版は1.1.1-rc.2。BaseVersionは1.2.1。登録先はC:/Program Files/MeltypeNativeGoogle/package-358a25b2469c409ea1f7c124667b3274。稼働管理先はC:/Users/AoneSenbongi/Documents/Codex/2026-10-06/https-x-com-yksr-melt-statusを保持する。管理スクリプト・状態・インストーラー定義・Windowsのアプリ一覧は1.1.1-rc.2。1.1.1-rc.2候補の配布EXEは作成済み。入力アプリは新しいDLLを読み込むため開き直す必要がある。

## 実装と検証

変換先はinput-preferences.jsonのConversionEngineで選択し、新しい接続で反映する。初期値はGoogle。Microsoftは本家の変換・候補取得・日英判別を専用STAスレッドで使う。Googleは従来の通常変換と学習を維持し、予測は本家コアを使う。Microsoftの辞書への学習書き込みは未対応。

利用者の「押しても自動のまま」を受け、WindowsのKEYBOARD_OPENCLOSE区画との同期とINPUTMODECOMPARTMENTカテゴリを追加した。閉じた英語モードから半角／全角で戻るためVK_KANJIを保持キーとして登録する。旧DLLで区画の有効化がない状態を再現し、修正後はクリック・キー・Windowsからの状態変更と通知が通過した。入力欄がないときの無効表示はWindowsの通常挙動として残す。パスワード欄・読み取り専用欄の保護を維持する。

1.1.1-rc.1では、GetTextだけを切り替えてGetIconは同じロゴを返す不具合をテストで再現し、モードアイコンに「自動／英語」を描くよう修正した。本家ロゴは識別アイコンとして保持する。有効化時はWindowsが保持する開閉状態を読み、未設定時のみ自動を初期値にする。入力欄へのフォーカス変更、無効区画、入力範囲の変更を監視する。IMEが使えない入力欄では「英語」を表示し、通常の入力欄では元の選択モードへ戻る。保護された入力欄でのクリックはモードを変更しない。表示とキー処理は同じ入力欄の保護判定を使う。仕様はdocs/NATIVE_INPUT_MODE.md。

2026年10月12日、Native17/17、Google13/13、Microsoft2/2、変換・予測・定型文・候補配置、管理画面・更新候補・版番号の試験が通過した。導入済みDLLでも、アイコンの描画差、既存の英語モード保持、Windowsの開閉同期、読み取り専用・IME無効の表示と入力、無効区画変更時の通知、通常欄への復帰を確認した。モードアイコンの描画を拡大して確認した。実アプリのタスクバー表示、複数モニター、テーマの切り替えは未確認。証跡はexperimental-build/input-mode-rc1-build.log、input-mode-rc1-apply.log、input-mode-rc1-applied.json、input-mode-rc1-installed-context-test.log、native-mode-preview.png。導入済み6ファイルはmanifestと一致し、brokerの接続準備も確認した。バックアップはbackups/20261012-211949の11ファイルと、稼働管理先のbackups/version-update-20261012-211950。旧登録パッケージは保持した。

アイコンは本家docs/images/logo.pngを使う。利用者の追加指示により、中央の水色・ピンクの文字を大きく切り抜き、16～256pxのICOとしてDLLへ組み込む。旧rc.2の小さいロゴが視認性の試験に失敗し、拡大版と導入済みDLLが通過した。候補は下に収まらなければ上へ置き、モニターの作業領域内へ収める。

定型文は本家SnippetsFormとSnippetStoreを使い、管理画面の「定型文を登録・管理」とトレイの「定型文...」から開く。登録・編集・削除・JSONの取り込みと書き出しを提供する。自動モードで行の先頭か空白の直後に「;名前」を入力し、Space／Tabで複数行を展開、直後のEscで元に戻す。Native TSFでは名前と展開結果を未確定範囲へ表示し、Enterまたは次の入力で確定する。保存先はLOCALAPPDATA/Meltype/snippets.json。コード内のセミコロンと未登録名は展開しない。登録変更を次の定型文入力から読み直す。英語モードは直接入力。仕様はdocs/NATIVE_SNIPPETS.md。

Native関連17/17、Google13/13、Microsoft2/2、両エンジンからTSF文書への変換・確定・取消、予測、候補配置、モードとロゴの試験が通過した。定型文の本家画面の登録・編集・削除・保存と描画、複数行・Esc復元・Tab展開・確定・取消、製品brokerの通信からTSF文書への反映を隔離したファイルで検証した。管理画面、更新候補判定、版番号一致も通過。実アプリごとの新機能の実操作、複数モニター、32ビットアプリは未確認。

導入済み6ファイルのmanifestとの一致、登録番号、サービス接続準備、定型文を開くスクリプトの一致、導入済みDLLのモード・拡大アイコンを確認した。バックアップはE:/prog/Meltype/Windows/backups/20261011-235841で、11ファイルの退避ハッシュが一致した。稼働中の履歴は変化するため適用前後の全ファイル一致は主張しない。rc.2時点ではGoogle辞書・設定は一致し、phrases.txtは既存行の削除なしで2行追加、history.dbは変化を確認した。

定型文画面の初回起動がコンソールと一緒に隠れる不具合を再現し、初回表示後に画面を表示し直すよう修正した。1.1.0-rc.4の導入済みスクリプトの一致、実際の登録画面が表示されること、サービスの接続準備を確認した。証跡はexperimental-build/native-snippet-rc4-apply.logとapplied.json。

証跡はexperimental-build/native-snippet-rc3-build.log、同接頭辞のapply.logとapplied.json、native-snippets-form.png、native-snippet-panel.png。定型文の通信試験はtools/native-ime/Test-NativeSnippets.ps1。Build-Packageから同試験を実行するよう追加済み。2026年10月12日、正式番号1.1.0でBuild-Packageを実行した。定型文画面の表示と通信試験を含めて通過し、管理画面・導入処理・更新候補判定の試験も通過した。証跡はexperimental-build/release-1.1.0-final-build.log。正式EXEの作成・適用も完了し、6ファイルと管理スクリプトの一致、サービス接続準備、導入済みDLLのモードとロゴの試験が通過した。バックアップはLOCALAPPDATA/Programs/MeltypeNativeGoogle/1.1.0/backups/20261012-001522で、11ファイルのハッシュが一致した。証跡はexperimental-build/release-1.1.0-final-verified.json、final-applied.json、final-apply.log。

## 2026年10月13日の本家main取り込み

本家47ace142から53fafd036b4d06fab7dae9ca0b9ea4eeafbfe976までをWindowsの共通コア・辞書・Windows実装・試験へ統合した。本家Releaseの番号は1.2.1のまま。独自候補番号は1.1.1-rc.2。開始時点の1.1.1-rc.1入力モード修正と未コミット作業を保持した。通常インデックスとブランチを変更せず、配布物の対応ソースは別の候補スナップショットで固定する。

三者比較の競合はCompositionTextのt/s結合と英語末尾判定、CompositionServiceのCreateSession。Google従来判定・学習停止・Microsoft/Google切替を保持して本家条件を統合した。独自native/tsfは既存入力モード修正を保持し、本家native/tipを別実装として更新した。仕様と範囲はdocs/UPSTREAM_53FAFD0.md。

管理ビルド、共通・Windows456/456、Native18/18、Google13/13、Microsoft2/2が通過。Native DLL、候補配置、描画更新、入力モード・アイコン、実TSF文書の変換28更新・予測16更新、定型文各11更新、登録画面の初回表示を検証した。既存のGoogle通常変換と予測の分離、句読点・学習停止の試験も通過。証跡はexperimental-build/upstream-53fafd0-managed.logとupstream-53fafd0-package.log。実アプリでの手入力、複数モニター、32ビットアプリ、本家TIPの新しいAlt+バッククォートと直接モード判定の独自TSF移植は未検証・未対応。

初回のPC適用は管理者確認が取り消された。利用者の再実行指示後、1.1.1-rc.2をPC適用済み。登録、配置6ファイルのmanifest一致、broker稼働と接続準備を確認した。再実行時バックアップはbackups/20261013-101831の11ファイル。配布EXEはdistributions/Meltype-Native-Google-1.1.1-rc.2-Setup.exe、SHA256は3E298D602E78E5E82350DEC2FE094D05E4AEF0B2A10FC2E16F6FC7C0F3AD5DA6。対応ソースは候補スナップショット3f8f44d595cc34ec827d2fc6dc8e7504939f7fea。独立ソース作業場所はE:/prog/Meltype/Tools/rc2-source。公開予定内容はdocs/RELEASE_1_1_1_RC_2.md。外部公開は今回の具体的内容への確認待ち。Android・Mac・Linuxを変更していない。
## 本家の朝監視

独立したローカル定期タスクmeltype-luna-6-1-solはACTIVE、毎朝9時、日本時間、gpt-6-luna、medium。更新時のみgpt-6.1-solへ委任する。利用者は独立タスクとこの委任を明示的に承認済み。変更なしの通知はしない。PCとCodexの起動が必要。

手順はdocs/UPSTREAM_MONITOR.md、状態はLOCALAPPDATA/MeltypeUpstreamMonitor/state.json。2026年10月13日に通常Release v1.2.1とmain 53fafd036b4d06fab7dae9ca0b9ea4eeafbfe976を検出。47ace142からの120コミットをWindows向けに統合し、docs/UPSTREAM_53FAFD0.mdで記録。未コミットの入力モード修正を保持した。

このPCへの自動適用は既存の承認範囲で、検証・バックアップ・適用確認後に行う。最新の利用者指定AGENTS.mdでは、外部公開の前に今回の内容への確認が必要。過去の包括的な公開許可を今回の確認として扱わない。定期タスクのプロンプトと手順をこの規則へ合わせた。

## 残作業と公開状態

1. 1.1.1-rc.2は共通・Windows456/456、Native18/18、Google13/13、Microsoft2/2を通過し、配布EXEを作成済み。利用者の再実行指示後、通常手順でPC適用済み。登録版・配置6ファイルとmanifestの一致・broker起動とNative IME有効を確認。適用前バックアップはbackups/20261013-101831。ユーザー設定・辞書・履歴11ファイルのうち8ファイルはハッシュ一致。boundary.db、cform.db、segment.dbは使用中でハッシュを照合できず。
2. 公開先AoneSenbongi/Meltype、ブランチgoogle-native-ime、予定タグnative-google-1.1.1。正式版1.1.1を再構築して公開準備中。タイトル・本文・変更点・検証・制限・EXEとSHA256はdocs/RELEASE_1_1_1.mdに確定する。具体的な内容の公開承認待ち。
3. 実アプリの手入力、複数モニター、32ビットアプリは未確認。本家TIPのAlt+バッククォート、直接モード判定、選択範囲再変換は独自TSFへ未移植。Microsoft辞書の学習書き込みは未対応。

既存のWindows検索、句読点と学習停止、通信枠32、管理者確認付きの保護配置・復旧、管理画面・オンライン更新を維持する。Win10/11の検索パッケージはOSビルド22000を境に切り替える。ThinkPad側のWin11検索修正は統合済み。このPCの検索入力は過去に利用者確認済みだが、今回の追加機能の実検索欄操作は未確認。本家の選択範囲再変換とTab文節変換は独自TSFでは未対応。突然の停止報告と接続枠不足との因果は未確定。


