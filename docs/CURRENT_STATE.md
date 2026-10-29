# 現在の状態

## 現在タスク: PC適用済み2.0.1-rc.9の公開準備

利用者が公開を依頼し、公開対象は現在の2.0.1-rc.9そのものと明示した。2.0.1正式版への変更や公開済み2.0.0からの入力機能統合は行わない。公開先はAoneSenbongi/Meltype、予定タグnative-google-2.0.1-rc.9、先行版。既存のgoogle-native-imeブランチを巻き戻さず、新しいタグのみ公開する。公開前にSetup・本文・検証結果を提示して具体的な確認を受ける。

配布するIMEの6ファイルは導入済みrc.9と一致させる。モデルは同じ既存資産を相対配置で同梱し、梱包用ツールとモデル読込ヘルパーには公開済み9af8545の処理を使用する。これは別PCでのSetup導入に必要な配置対応であり、IME本体は再ビルド・変更しない。公開本文docs/RELEASE_2_0_1_RC_9.md、案内README.txt。

2026年10月29日、利用者がWindows版で文章末尾の「」を確定したら内側へ移動し、内側の文字列を確定したら外側へ移動する動作を依頼。導入済みソースf9cdc5eを基点とする専用作業先で、既存の括弧内移動設定を拡張する。候補番号2.0.1-rc.9、本家基準1.3.0。仕様docs/BRACKET_COMMIT_NAVIGATION.md。2026年10月29日10:21JSTに通常更新でPC適用済み。外部公開は行っていない。

実装: 確定文字列末尾の空ペアを検出し、Nativeでは末尾2文字へ範囲を限定。閉じ括弧をTSF範囲として追跡し、同じ文書でその直前の文字列を確定した場合だけ外へ移動。明示移動・Esc・フォーカス変更で追跡解除。実アプリのComputer UseやCLIによる画面操作は行わない。

検証: 旧条件で追加Core試験が1/3失敗、修正後3/3通過。SDK apphost全体638/638通過。隔離broker＋実TSF文書で文章末尾のペア→内側入力→確定→外側の続き、既存括弧内編集の維持、連続入力、Esc解除、アプリ側選択リセット、自身の合成矢印を識別して追跡を維持することを確認。既存のプライバシー・数値・英語・再変換・Tab・保護欄の試験も通過。証跡experimental-build/bracket-navigation-{red,core,full,final-tsf,final-privacy,final-upstream}.log。

PC適用: NativeVersion2.0.1-rc.9、BaseVersion1.3.0、登録先C:/Program Files/MeltypeNativeGoogle/package-bee22138da3a43d29d717cd9a3541942。導入済み7ファイルのうちMeltypeNative64.dllとMeltype.Core.dllのみ変更し、変換エンジン・broker等5点を保持。配置7/7、管理スクリプト7/7、設定3/3不変、backups/20261029-102032の退避15/15ハッシュ一致。更新元終了後にbroker4024の本人SID・ジョブ外稼働、model19144のhealth okを確認した（PIDは検証時点）。証跡experimental-build/bracket-navigation-applied.jsonとapply.log、verification.log。入力アプリを開き直す必要がある。ユーザーが使用する実アプリでの手入力は未確認。

## 前回タスクと適用履歴

## 前回完了: 本家1.3.0対応・独自2.0.0公開準備（PC適用済み、未公開）

利用者がComputer Useの停止を明示したため、この作業では以後使用しない。画面操作・自動キー入力をCLIによる別手段へ置き換えない。ソース・ログ・画面を操作しないCLI試験・配布準備で進める。

専用作業先E:/prog/Meltype/Tools/release-2.0.0-1.3.0。本家v1.3.0（6310c44）と取り込み済みpre.2（21fb255）の差分から共通変換・判定・辞書と関連試験を統合した。元のcontext-evaluationの未コミット内容・インデックス・HEADを保持し、保全スナップショット4e9e3afから作業している。仕様はdocs/UPSTREAM_1_3_0.md、公開本文案はdocs/RELEASE_2_0_0.md。外部push・タグ・Release公開は未実施。公開前に具体的な内容の承認が必要。

括弧内移動は利用者の管理画面/Codexで不具合報告。試験用TSF文書だけを使った一次修正8b7cfa6と遅延修正0f4483eは実アプリで戻ってしまった。登録済みIMEと通常のWindows EDITで()→Enterを入力するNativeEditControlTest.cppを追加し、旧版の全角括弧確定後の選択2/2（外側）を自動再現した。TSFの直接選択だけでなく、確定通知後に入力欄自身の通常矢印キー処理で移動させる追加修正で選択1/1（内側）を確認した。自プロセスの前面UIスレッド・同じ文書・範囲内の空選択を確認し、修飾キー押下中は保留、他アプリへ送信しない。試験用文書は直接選択、実アプリは通常キーの経路であることを区別する。実EDITの試験はComputer Use停止指定より前に実施し、以後は画面操作を行っていない。

2026年10月19日23:05JSTに追加修正を標準更新でPC適用。NativeVersion2.0.0、BaseVersion1.3.0、package-12079ea97b524c3b9bdd67b745e87e12。23:10JSTに配置7/7・登録DLL・管理スクリプト7点、設定等3/3、backups/20261019-230513の11/11ハッシュを独立照合。broker91236は本人SID・ジョブ外・更新元終了後も稼働、model66348 health ok。導入サービスの荷台候補も通過。PIDは検証時点の値。証跡experimental-build/upstream130-applied.jsonとverificationログ。

共通・Windows回帰637/637、標準パッケージNative20/20・Google16/16・Microsoft2/2、設定保存・プライバシー・定型文が通過。今回の追加修正後も試験用TSF文書の通知・遅延・連続入力・明示移動、保護欄・学習抑止・再変換・Tab操作を確認した。実EDITの旧版失敗はexperimental-build/upstream-1.3.0/real-edit-red.log、新修正成功はreal-edit-arrow-green.log。追加回帰はbracket-arrow-contract.log、arrow-privacy.log、arrow-upstream.log。管理画面とCodexでの最新修正の最終確認は未完了。

新アイコンは本家タグの雪の結晶＋Mを変更せず使用。Native DLL・管理画面・トレイ、管理ランチャーとショートカット、Setupへ反映。自動／英語のモード文字は維持し、埋め込み32px画像と元ICOの全画素一致、管理画面描画を確認した。

独自Windows本体が必要とする旧APIは保持。子音略入力・文脈別日英学習など全ての本家機能をNativeへ接続したものではない。PC用ローカルzenzモデルは維持し、配布物にはモデル本体と絶対パスのcontext-model.jsonを含めない。公開版はGoogle/Microsoft変換で動作する。個人の辞書・設定・履歴は配布しない。

以前のEXE/ZIP（8b7cfa6・0f4483e）はexperimental-build/upstream-1.3.0/superseded-*へ退避し公開しない。最新の通常矢印キー修正からローカルソースを確定し配布物を再構築する。対応コミットとSHA-256はexperimental-build/installer-build.jsonに記録する。最新修正の管理画面/Codex確認と、公開内容の承認が残る。

## 直前完了: 管理画面内の設定統合・英語文節の境界変更（2.0.0、PC適用完了）

2026年10月19日、利用者が入力操作・計算を主画面に置き、英語誤判定の文節もShift+左右で変更できるよう依頼。未公開のため番号を2.0.0に保つとの明示指定を優先し、表示・登録・更新・インストーラーを統一。右側のスクロール領域へ設定と保存ボタンを直接配置し、独立フォームとリンクを廃止。既存の設定値は維持する。仕様docs/CONTROL_PANEL_AND_ENGLISH_BOUNDARY.md。既存の未コミット作業を保持し、外部公開なし。

LegacyGoogleConversionで英語文節の境界操作を拒否していた条件を修正。かなの読みを持つ英語文節を日本語として読み直して縮小・拡大でき、全体が自動で英語表示になった入力でもShift+左右で操作を始められる。通常フックの英語範囲選択・明示英語直接入力、移動不能時と読めない英字の保持は維持する。再現4/4、全体616/616、Native20/20、Google16/16、Microsoft2/2、実TSFと標準パッケージ、主画面の保存処理・描画が通過。

17:59JSTに標準更新でPCへ2.0.0を適用。登録先package-70995951ba9849da821c75da94f038d6の7/7ハッシュ・登録DLL、管理スクリプト7点、設定等3/3、backups/20261019-175844の退避11/11を照合。旧設定フォームはバックアップへ退避後に導入先から削除。broker72476は本人SID・ジョブ外で更新起動元71176終了後も稼働、model87380のhealth ok。導入サービスのprivate接続でcameraからの境界変更・かな表記選択・確定、荷台、計算、全角空白、英語直接入力、補助非表示を確認した。証跡experimental-build/panel-boundary-applied.json、panel-boundary-installed-english.log、control-panel-boundary/package-final.log。

追加の実モデル連携試験は初回に期待出力へ到達せず、同一条件の再試験は表示更新・確定・取消まで通過。初回原因と変更との因果は未確定で、モデル実装・時間制限は変更していない。証跡control-panel-boundary/real-model-first-details.logとreal-model-recheck-details.log。実アプリごとの手入力・複数モニターの使用感は未確認。入力アプリを開き直す必要がある。

## 直前完了: 本家pre.2の入力操作・計算候補（2.0.1-rc.8、PC適用完了）

2026年10月18日、利用者が検証後のPC導入と既存管理画面への設定項目追加を依頼。本家v1.2.2-pre.2の共通コア・辞書・関連試験を45e14f8から三者統合し、独自Google連携・文脈モデル・候補配置・rc.7の荷台候補修正を保持した。仕様と証跡はdocs/PRERELEASE_INPUT_2_0_1_RC_8.md。通常ブランチ・インデックスと他作業の変更を保持し、外部公開なし。

管理画面に「入力操作・計算の設定」を追加。計算候補は既定で有効。Esc段階取消、選択文節の取消、Enter確定、F9/F10、空白、括弧・記号、括弧内移動、Control割当、英字優先を切替可能。選択文節Fキー・Shift+Spaceの全角・英語直接入力維持・打鍵補助非表示を維持し、未指定の操作変更は既定で無効。子音略入力・文脈別の日英学習はNativeへ接続しない。設定は次の入力から反映する。

短い数値単位が変換されない本家変更の回帰を検出し、数字付き入力の長さ判定を維持して修正。括弧内移動の合成Leftが物理Enter再送になる経路は、専用アクションとTSF選択位置の移動で修正した。旧DLLを隔離した試験で失敗を確認。全体612/612、本家再現101/101、Native20/20、Microsoft2/2、Google16/16、実TSFの追加操作・26種の数値入力・既存機能・プライバシー・設定保存とGUI描画が通過。実ローカルzenzから隔離broker・実TSF文書への更新、表示どおりの確定、取消も通過。

23:40JSTに通常更新でPC適用。登録先package-b91e4d40d228486fbfc89d09fc8b4bd6の7/7ハッシュ、登録DLL、管理スクリプト8点、設定等3/3、backups/20261018-233934の退避11/11を照合。Googleユーザー辞書・Meltype設定・conversions・phrasesは不変、history.dbは稼働中に変化、Google DB3点は使用中で照合不可。broker95020は本人SID・ジョブ外で更新起動元73640終了後も稼働、model88340のhealth ok。導入brokerのprivate接続で荷台候補・計算確定・全角空白・英語直接入力・補助非表示を確認。証跡experimental-build/pre2-applied.json、pre2-installed-features.log、pre2-integration/real-model.log。入力アプリの開き直しと実アプリごとの手入力・複数モニターの使用感確認は残る。

## 直前完了: 手動でまとめた文節のGoogle候補取得（2.0.1-rc.7、PC適用完了）

2026年10月18日、「にだい」単独で「荷台」が候補に出ず、利用者が区切り変更後も選べないと報告した。実Googleで通常は「に｜だい」と分かれ、Candidates("にだい")が空になることを確認。通常分割を維持したまま、候補照会時だけ先頭文節を読み全体へ伸ばす修正を行った。辞書への固定語句追加はしていない。仕様docs/GOOGLE_SEGMENT_CANDIDATES.md。

再現試験は修正前に失敗し、修正後のGoogle関連16/16が通過。実Googleの「にだい」候補に「荷台」が含まれ、ローマ字打鍵からのShift+Right2回による区切り変更・候補選択・確定と、読みが既知の「二代に積む」の再変換からの区切り変更・後続文節保持を確認した。後続付きローマ字打鍵は既存の英語判定がinitを残すため、この検証では再変換を使って境界変更だけを確認した。標準パッケージのNative18/18、Microsoft2/2、Google16/16と変換・予測・定型文・入力機能・プライバシー試験が通過。

2026年10月18日16:39JST、標準更新で2.0.1-rc.7をPCへ適用。登録先package-d032af9241924a909cfd52428778ec2bの7/7ハッシュ、管理スクリプト6点、設定等3/3、backups/20261018-163836の退避11/11を照合した。配布対象の変更はMeltype.dllだけで残り6点は導入済みバイナリーを保持。導入brokerへの学習無効のprivate接続でnidai→Space→Shift押下→Right2回→Shift解放→荷台選択→Enter確定が通過した。broker74088は更新元68772終了後も本人SID・ジョブ外で稼働し、model75120のhealth okを確認。Googleユーザー辞書は不変、phrases.txtは1670件から1687件へ増加し既存の読みと語句の欠落0。history.dbは稼働中に変化し、Google DB3点は使用中で照合不可。証跡experimental-build/nidai-{direct,segment,red,green,google-live,package,stage,installed-after,verification}.log、nidai-applied.json。入力アプリの開き直しと実キーボードでの使用感確認は残る。外部公開なし。

## 候補欄のサイズ更新漏れ（2.0.1-rc.6、PC適用完了）

2026年10月17日、候補一覧の下側が見切れる報告を調査した。発生アプリと再現操作は不明。候補データ更新後に入力位置取得が失敗すると旧サイズが残る経路を隔離試験で確認し、利用者が修正とこのPCへの適用を依頼した。取得不能時は同じ変換中の最後の有効位置で候補欄を再計算し、候補を隠す際に位置を破棄する。有効位置がない場合は非表示。表示件数の変更は行わない。仕様docs/CANDIDATE_LAYOUT_2_0_1_RC_6.md。

再現試験は修正前にclient=30/required=220で失敗し、修正後はclient=222で通過。候補増減、打鍵表示、上下配置、取得回復、空座標、非表示後の座標破棄とフォーカス維持を確認した。標準パッケージのNative18/18、Microsoft2/2、Google15/15、実TSFの変換・予測・定型文、入力機能とプライバシー試験が通過。最終配布対象は候補表示DLLだけを変更し、変換エンジン等の残り6ファイルは導入済みバイナリーを保持した。

2026年10月17日02:54JST、標準更新と通常の管理者確認後に2.0.1-rc.6をPCへ適用した。登録先package-976491e7baed40d8958f4de27ef6d2caの7/7ハッシュ、登録DLL、主要管理スクリプト6点の一致、導入済みDLLの候補再描画・サイズ回復・配置・入力モード試験を確認。設定等3/3は不変、backups/20261017-025408の退避11/11が一致。Googleユーザー辞書は不変、phrases.txtは1409件から1412件へ増え、既存の読みと語句の欠落0。history.dbは稼働中に変化、使用中Google DB3点は照合不可。broker66204は更新元26912の終了後もジョブ外・本人SID・session1で稼働し、接続準備とmodel21452のhealth okを確認した。証跡experimental-build/candidate-layout-red.log、green.log、package.log、installed-tests.log、applied.json。入力アプリは旧DLLを保持するため開き直す必要がある。元の実アプリでの再発有無は未確認。外部公開なし。

2026年10月15日、利用者の画像で候補上部の打鍵ローマ字が不要と指定されたため、このPCのMeltype/config.jsonのShowTypedKeysをfalseに変更した。変更前はbackups/hide-typed-*へ退避。実導入brokerのprivate接続で、日本語入力を維持し、typed headerを要求しても空であることを確認した。証跡experimental-build/hide-typed-installed.log。製品バイナリーや版番号は変更していない。既存接続へ反映するには入力アプリを開き直す。

## Shift+Spaceの全角スペース（完了）

2026年10月16日、利用者の指示により未確定入力なしの日本語モードのShift+Spaceを全角スペースにした。共通コアには処理があり、NativeのIdleキー受付が除外していた。Native再現試験で修正前の失敗を確認し、Shiftが押されているSpaceのみを受付対象へ追加。通常Space、明示英語、Ctrl/Alt/Win・保護欄の既存除外、入力中の明示変換、候補選択中の前候補を保持する。関連5/5と標準パッケージ試験が通過。仕様docs/SHIFT_SPACE_2_0_1_RC_5.md。

00:39JSTに標準更新で2.0.1-rc.5をこのPCへ適用した。package-9f5c9be205f24d29976dd589d7c62596の7/7ハッシュとソースstage、登録DLLの一致、導入DLLのモード試験を確認。独立起動元62592の終了後もbroker62688（IsProcessInJob=false、session1）とmodel45300が稼働、health ok。導入brokerのprivate接続でShift+SpaceがU+3000を1文字確定し、keyupで重複しないことと英語直接入力を検証した。backups/20261016-003909の11/11退避ハッシュ、設定・入力設定・conversions.jsonの3/3ハッシュが一致。証跡experimental-build/shift-space-*。実アプリの旧DLLを置き換えるため入力アプリの開き直しが必要。実キーボードによる手入力の使用感は未確認。外部公開なし。

## 継続課題: 文脈に応じた区切り学習の方式比較

利用者は手動修正した変換区切りを文脈に応じて学習することと、多様な大量試験を明示要求した。2026年10月15日、実ローカルzenz-v3.2-smallで通常1,200件と否定・引用・話題転換など720件、候補順反転を含む3,840要求を完了した。12読み・学習48文・評価120意味文から派生した条件付き試験であり、1,920独立意味例ではない。候補表記は教師作成の2択で、Google候補生成や日常入力の正解率を測っていない。

通常の正解は履歴732/1200、zenz839/1200、併用902/1200。追加条件は360/720、409/720、405/720。追加条件では履歴適用28件中14件が誤り、併用はzenzから9改善・13悪化した。文字類似度による履歴自動適用案は見送る。製品への接続とPC適用は未実施、現在の導入版2.0.1-rc.4を維持する。

未接続のContextBoundaryMemory試作と11試験を追加。2,000回の文脈別照会、10,000回の交互修正、3,000回の並行修正・照会、最大件数、保存・再読込、破損・不正内容、保存不能、配列の防御、同一表記の別区切り、競合時の判断保留が通過。通常apphostの共通・Windows全体538/538通過、ビルドエラー0・既存nullable警告3。private欄・学習停止・取消しの既存回帰は通過したが、新しい区切り履歴との接続は未検証。次は実Googleの区切り候補生成と採用条件を決め、手動変更・確定だけの学習と保護条件を接続試験する。仕様docs/BOUNDARY_LEARNING_EXPERIMENT.md、結果docs/BOUNDARY_LEARNING_RESULTS.md、証跡experimental-build/boundary-*。

比較完了後もbroker5488/model68236の稼働を確認。実導入brokerのprivate接続で英語維持、打鍵ローマ字補助非表示、1.5倍速の即時・モデル待機後の一致が通過。証跡experimental-build/boundary-after-{direct,header,numeric}.log。稼働版・個人履歴を変更していない。

## 直前の入力サービス停止の復旧（2.0.1-rc.4維持）

再び英語しか入力できないとの報告があり、broker64812とmodel24244の両プロセス停止・health不可を確認した。通常のShell.Application起動で29116へ復旧し、利用者本人の日本語入力成功を得た。しかし復旧brokerもWindows Jobへ所属していたため、ジョブ影響を避ける独立起動へ切り替えた。標準Stop-NativeImeで旧brokerを終了後、Win32_Process.CreateにWin32_ProcessStartup（ShowWindow=0、CreateFlags=0x09000000: CREATE_BREAKAWAY_FROM_JOB|CREATE_NO_WINDOW）を渡し、導入先Start-NativeIme.ps1を同じ通常ユーザーで起動した。新broker5488はIsProcessInJob=false、利用者SID一致、対話セッション1、起動launcher69292終了後も稼働。model68236とhealth ok、実導入brokerで1.5baisoku→1.5倍速を即時・モデル待機後に確認した。証跡experimental-build/detached-recovery-*.json。バイナリー・版番号は変更していない。停止原因そのものは未確定で、ジョブ所属と因果を断定しない。今後このツール環境から常駐・更新を起動するときはShell.Applicationだけで独立性を仮定せず、このWindows側のジョブ離脱起動を使い、IsProcessInJob=falseと起動元終了後の稼働を検証する。

### 数字入力修正の適用記録

利用者は1.5baisokuが英字のままになり、先頭の1に未確定の下線が付かないと報告した。実TSFのキー受付で数字から開始できず、先頭の1はアプリへ直接入力、.以降だけが未確定になることを再現した。内部brokerへ全文を渡す試験では再現しないため、実キーの受付とアプリ側直接入力を模擬する試験を追加した。自動モードの数字キーを未確定入力の開始対象へ追加。実TSFの数字関連26例、テンキー4例、明示英語26例、日英文脈2例、数字のみのSpace候補と先頭数字の未確定状態が通過した。標準パッケージとNative18/18も通過。2026年10月15日23:03JSTに標準更新で2.0.1-rc.4を適用済み。登録先package-58472452d09347b28b4e7589bfb3f941のmanifest7/7・登録DLL・モード試験、broker64812/model24244とhealth okを確認。導入brokerでも1.5baisoku→1.5倍速、0.75bai→0.75倍、100enn→100円が打鍵直後とモデル待機後に一致し、英語直接入力とローマ字補助非表示も通過。100enは末尾nの確定を含む実TSF試験で100円へ変換し、打鍵直後表示は100ennで確認している。標準バックアップbackups/20261015-230336の11/11を照合済み。証跡experimental-build/decimal-*.log/json。実アプリは旧DLLを保持するため開き直しが必要で、人間による使用感は未確認。仕様docs/NUMERIC_START_2_0_1_RC_4.md。上下候補・Shift+左右境界・ライブ表示保持・英語直接入力・ローマ字補助非表示は維持する。

### rc.3の適用記録

利用者の明示指示により、左右は対象文節、上下は候補、Shift+左右は境界に変更する。ライブ表示保持と英語直接入力維持は継続。仕様docs/ARROW_CANDIDATES_2_0_1_RC_3.md。旧上下境界オプションを削除し、単体再現試験を変更して修正前の失敗を確認した。再現試験3/3、関連Composition213/213、Native18/18、標準パッケージと実TSFの上下候補切替・Tab・確定に通過した。2026年10月15日22:42JST、標準更新で2.0.1-rc.3をこのPCへ適用済み。登録先package-bc1eee373e9e4903aa2fcca7c422f5ffのmanifest7/7・登録DLL・モード試験、broker69592/model59864とhealth okを確認。導入brokerのprivate接続で左右移動による表示保持、Shift+左で「せんか」を「せん｜か」へ縮小、Shift+右で復元、上下で候補切替、最後に「昼マックにせんか？」へ修正する操作が全て通過。英語直接入力維持も再通過。標準バックアップbackups/20261015-224224の11/11ハッシュ一致。証跡experimental-build/arrow-candidates-*.log/json。人間による実アプリでの使用感確認は残る。

### rc.2適用の記録

利用者は「昼マックに専科？」の「専科」だけを修正したいが、選択開始で「昼マック」が再分割されることを指摘し、左右を対象移動、上下を区切り変更へ指定した。上は1文字縮小、下は1文字拡大、Space/Tabは候補切替とする。実導入brokerでモデル補正後の表示が左キーで巻き戻る現象を確認した。仕様docs/LIVE_NAVIGATION_2_0_1_RC_2.mdに従い、実際のライブ表示と境界・モデル採用表記を選択状態へ引き継ぐよう修正した。3件の失敗する再現試験を先に追加し、修正後は全体527/527、標準パッケージの実TSF上下境界・Tab候補・表示確定試験に通過。版番号2.0.1-rc.2。実モデルのTSF表示から左キーで選択へ移っても「革で靴を作る」を保持する試験に通過。標準更新により2026年10月15日22:34JSTにPCへ適用済み。登録先package-342a228c497f4c44abe607fb8db84734とmanifest7/7、導入DLLのモード試験、broker10432/model69348とhealth okを確認。実導入brokerのprivate接続でhirumakkunisennka?をモデル待機後に左で移動し、表示を維持してTabで「昼マックにせんか？」へ変更できた。Fキーは不使用。英語直接入力の隔離試験も再通過。標準バックアップbackups/20261015-223357の11/11ハッシュを照合済み。証跡experimental-build/live-navigation-*.log/json。実アプリでの人間による操作感は未確認。英語直接入力維持は継続する。

### 直前の2.0.1-rc.1適用

利用者はUSキーボードのAlt+`で英語へ切り替え、メールアドレスや打鍵文字列をそのまま入力したいと指定した。このPCのDirectModeAutoDetectをfalseへ変更し、実導入brokerの隔離private接続でローマ字・空白・メールアドレスが直接通過し、日本語変換を開始しないことを確認した。自動モードの日英判定は維持する。文節選択中のF6/F10が全体へ作用する不具合を再現試験で確認後、F6〜F10を選択文節だけへ適用するよう修正した。仕様docs/INPUT_CORRECTION_2_0_1.md。版番号を2.0.1-rc.1へ更新し、標準パッケージ試験、全体回帰524/524、実TSFの選択文節F6/F10・確定試験が通過した。標準更新により2.0.1-rc.1をPCへ適用済み。登録先package-24a0388834324a59850cd6ee2411e132のmanifest7/7、登録DLLとモード試験、導入brokerへのprivate接続で英語直接入力と文節F6/F10、broker64152/model18748の稼働とhealth okを確認した。バックアップbackups/20261015-221935の11/11ハッシュ一致。ユーザー辞書・config.json・conversions.json等6点は不変、history.db・phrases.txtは変更あり、Google DB3点は使用中で照合不可。証跡experimental-build/input-correction-*.log/json。USキーボードの物理Alt+`操作そのものの手入力は未確認。外部公開はしない。

### 適用後の入力不能と復旧

利用者から英語しか入力できないと報告があり、実確認では旧broker59844とモデル66984が共に停止、pipe未準備、health接続不可だった。登録と状態JSONは残っていたため、前回の起動直後の稼働確認だけでは常駐継続の確認として不十分だった。作業用出力取得プロセスを停止したこととの関係が疑われるが、終了原因そのものは未確定。

Windows shellのShellExecuteから導入先Start-NativeIme.ps1を通常ユーザーで起動し直した。新broker55292・モデル54336、endpoint http://127.0.0.1:58667/health のokとpipe準備を複数の独立した呼出しで確認した。brokerが現在のツールjobのメンバーでないことをQueryInformationJobObjectで確認した。現在のPID・portは再起動で変わる。Test-InstalledNativeInput.ps1は実導入brokerへのprivateな独立接続でnihongoを日本語へ変換し、Esc取消まで通過。辞書学習や他アプリへの文字挿入は行わない。証跡はexperimental-build/context-2.0.0-recovery-input.log。

復旧後、利用者本人から「日本語を入力できる」と確認を得た。製品バイナリーの変更や再登録・再インストールは行っていない。今後は常駐プロセスを起動したツールのラッパーを安易に停止せず、起動元の終了後にも稼働と実入力を確認する。

2026年10月15日、通常の更新手順によりNativeVersion2.0.0・BaseVersion1.2.1を適用した。登録先はC:/Program Files/MeltypeNativeGoogle/package-894db90c003f4502b230b8f6000b5fef。登録DLL、manifestと7/7ファイル、同パッケージ指定のbroker59844、安定配置モデルのserver66984、loopback health ok、broker接続準備、Native日本語active profileを独立して確認した。実登録DLLの入力モードとアイコン試験も通過。導入済み管理画面ソースの版は2.0.0で、旧Windows作業場所の管理画面を閉じて導入先へ切替起動した。入力アプリの再起動後の人間による使用感は未検証。

backups/20261015-180025の11ファイルが退避SHA256と11/11一致。ユーザー辞書・Meltype設定・変換履歴ファイル・入力設定・キーボード設定の一致を確認。Google history.dbとsegment.db、phrases.txtは変更あり。予測履歴は既存1143キーの欠落0、新規8、既存1のメタデータ更新を確認し、Google変更DBの内容一致は未検証。旧パッケージを保持している。詳細と証跡はdocs/DEPLOY_2_0_0.md、experimental-build/context-2.0.0-*.json。

2026年10月15日、利用者が従来版と区別してこのPCへ適用するよう依頼し、版番号2.0.0を明示指定した。導入中の1.1.2-rc.2を実登録とstateで確認済み。NativeVersion・GUI・インストーラー設定を2.0.0へ統一し、BaseVersion1.2.1を維持した。モデル資産はE:/prog/Meltype/models/zenz-v3.2-small、保護パッケージのcontext-model.jsonにハッシュを記載。brokerが必要時にloopbackサーバーを起動し、終了時に停止する。実入力のモデルログは保存しない。lifecycle試験が通過した。

Build-Package.ps1が全工程を通過し、payload7ファイルとmanifestを照合した。辞書・入力設定の追加退避先はbackups/context-2.0.0-preferences-20261015-180002。適用準備情報はexperimental-build/context-2.0.0-prepared.json。標準Update-NativeIme.ps1を1回実行した。更新子プロセス終了後に出力取得ラッパーだけが残ったため、子プロセスがいないことを確認して取得処理のみ停止した。標準出力は0 bytesで、成功は上記の実状態照合で確認した。公開は行っていない。

## 文節単位の長文対応（実装・検証済み）

利用者の「実装してみよう」により、controllerをClauseContextEvaluationへ切替えた。全文生成と100文字制限をcontroller経路から除き、短い対象文節（読み・候補64文字以内、候補5個）だけを出力する。左256・右128文字、180ms待機、世代全体1500ms。完了済みの複数箇所の補正を一括反映し、期限切れなら未処理分は保持する。入力・文脈変更・手動選択・確定・取消で古い結果を破棄する。英語・保護区間は固定。旧ContextEvaluationは先行実験用APIとして残した。

experimental-build/context-clauses-20261015-172939で101段階・106実モデル要求を確認し、例外0、80/100/101/200/400文字は各6/8正解。100文字の待機込み中央値311ms（変更前774ms）、400文字232ms。2箇所補正は200/400文字で成功したが50/80/100文字では失敗。analyze_clause_results.pyで全ログ・ID・候補からの合成・短い要求・文脈幅を照合した。共通Windows518/518、文節状態機械6/6、長文controller含む5/5が通過。実Google7入力と実TSF文書の待機中更新・Enter・Escはcontext-clause-native-20261015-173240で通過した。短文でも橋をわたる→はしをわたるの表記悪化が観測され、候補選択の品質は未解決。

実Google147/377文字の試験では、GoogleImeConverter自体の100文字上限で全体がひらがなへ戻る問題を発見した。全体512文字までを100文字以内の窓で処理し、中間窓の最後の文節を次へ残す変更を行った。全窓で2秒期限を共有、1MB応答上限、読み一致、セッション破棄を維持し、Google学習要求は従来どおり100文字上限。再現テストは先に失敗を確認しており、共通Windows最終521/521、期限共有変更後のGoogle15/15が通過した。既存nullable警告3件。最終直接変換でも147/377文字が33/84文節へ分かれ、読みの欠落なし、約162/282msを確認した（context-clause-google-long-final.json）。

実Googleとcontrollerの長文打鍵はexperimental-build/context-clause-native-20261015-174404で両方とも川で靴を作る→革で靴を作るへ補正し、表示どおり確定した。入力終了後待機は約1730/1764ms。多文節では1500msの予算に収まった先頭側だけが評価される。打鍵再生全体の入力処理は約10.9/66.7秒で、Google候補の同期取得等による長文応答性は未解決。実TSF文書の待機中更新・Enter・Escも同実行で再通過した。詳細と制限はdocs/CONTEXT_CLAUSE_RESULTS.md。PC適用・公開は行っていない。

## 変更前の長文測定（完了）

2026年10月15日、利用者の「長い文章になったとき」「やってみよう」を受け、製品上限を変えず長文テストを追加した。実行先experimental-build/context-length-20261015-163834、詳細docs/CONTEXT_LENGTH_RESULTS.md。8意味例の入力20/50/80/100/101/200/400文字、左文脈距離、正解の組合せが候補にない条件、上限を通さない診断の計123段階を実zenz/CPUで実行した。通常経路75評価は例外0・候補内応答75、80/100文字は各6/8正解（基準4/8、改善3・悪化1）、100文字応答中央値580ms・待機込み774ms。101文字から要求0。100文字上限を通さない200/250文字は各8/8が1500msで期限切れ、400文字は候補256文字上限で送信前棄却。serverは異常終了していない。左文脈の手掛かりは後ろに128文字を挟むと送信範囲外になり、正解4/8。モデル判断だけでなく入力・候補・出力範囲の設計が制限になっている。

ContextLengthTestsの4試験が通過し、実controller代役試験では100文字で採用した接頭部は101文字でも保持され、新規評価だけが止まり、表示どおり確定された。長文実験は手作業候補・共通ひらがな埋め草を使い、段階ごとに新しい評価状態機械を作るため、実アプリの表示の揺れは未測定。analyze_length_results.pyでケースログとresults全行、123件、ID・文字数・候補内採用・境界を照合しsummary.jsonへ保存した。次の設計候補は前後文脈を参照して対象文節だけを出力する方式で未実装。製品実装・PC適用・公開は今回変更していない。

## 1000件の継続評価（完了）

2026年10月15日、利用者の完了報告を受けてlong-context-20261015-162621のterminal.json・samples.jsonl・environment.jsonを確認した。1000件+評価専用40件=1040要求、112.1秒、要求失敗0件、保存省略0件でcompleted。ケースログから方式別正解・悪化数を再計算し、集計と一致した。追加履歴なし812/1000、全確定496/1000、明示修正769/1000、文脈完全一致812/1000（履歴使用0）。評価専用40例は明示修正方式が37→35→34→30、全確定は37→20→20→20、他2方式は37のまま。重み固定の外部履歴比較であり、LLMの追加訓練による過学習や日常精度を測った結果ではない。HTTP中央値101.5ms、p95 154.7ms。約2分のバッチで、長時間実アプリ利用の検証は未実施。詳細と限界はdocs/CONTEXT_EVALUATION_RESULTS.mdの冒頭に保存した。次の設計候補は手動修正を文脈付き参考情報としてLLMへ渡す方式で、未実装。追加実験・PC適用・公開はしていない。

2026年10月15日16:26JST、利用者の異常終了報告を受けて修正し、1000件を最初から起動し直した。利用者の運用指定は「GUIに表示、完了は利用者がチャットへ知らせる」。完了を待つポーリングや通知用automationは作成せず、利用者から連絡が来たら結果を読む。

完了した実行先はE:/prog/Meltype/Tools/context-evaluation/experimental-build/long-context-20261015-162621。最新実行先の参照はexperimental-build/long-context-latest.json。GUI2656、worker16536、実験runner1776は起動時のPIDで、今後操作する場合は同一実行か確認する。GUIの可視状態とウィンドウ名、評価用モデル要求30件、要求失敗0件を起動時に確認し、その後は利用者の報告まで待機した。

long-context-20261015-124211は805件で停止した。801件目のGitHub接頭部からHttpRequestExceptionが5回連続し、前回修正した進捗保存の失敗は0件だった。同じ入力1件だけでもserverが終了コード3221226505で異常終了することを再現した。候補共通の固定ASCII接頭部をpromptの出力開始位置へ事前入力し、残りだけをgrammarで生成、応答へ接頭部を復元する修正を行った。runtime内部の終了原因は未特定。801〜1000件目の実モデル200要求は修正後に失敗0件、候補内出力200件、接頭部保持200件だった。証跡はexperimental-build/mixed-prefix-reproのoriginal-repro.jsonとfixed-results.json。先に追加した再現試験の失敗を確認後に修正し、関連29試験が通過した。workerはserver終了状態と終了コードをenvironment.jsonへ記録し、要求失敗の例外詳細をsamplesへ残す。途中・末尾を含むすべての英字混在ケースを保証したものではない。旧実行の結果は保持している。

前回long-context-20261015-122059は193件目で進捗JSONのFile.MoveがUnauthorizedAccessExceptionとなり停止した。モデル要求233件は失敗0件。元のsamples.jsonlとresults.jsonを保持している。削除共有なしでstatus.jsonを開くreaderとの競合をテストで再現し、進捗保存の短い再試行・更新省略、最終結果用terminal.json、GUIの最終結果優先読込を追加した。エラー表示のPowerShell変数展開も修正し、workerが保存済みの診断情報を消さないようにした。

コーパスは20組の同音異義語×2語義×5文脈×5変種=1000件。別に40例を評価専用として保持する。意味例は200件で、1000独立語義ではない。4方式が同じ生モデル出力を共有し、処理0/100/300/1000件時点で評価用40例を比較する。模擬修正25%、取消27イベント。重みは固定で、変化するのは方式別のメモリ上の履歴だけ。実IME・Google辞書・既存履歴は今回使わず、従来の26例の結果も上書きしない。

新規ファイルはtools/context-eval/generate_long_cases.py、long-cases.json、long-cases-manifest.json、Start-LongContextExperiment.ps1、Invoke-LongContextWorker.ps1、Show-LongContextProgress.ps1、src/Meltype.Core.Tests/ContextLongRun.csとTests。コーパスSHA256は600221373f4c06ac179e1c4b65178806b4457b9846c643b508827504706ea8b5。修正後の継続評価4試験が通過し、進捗ファイルのロック中の完走・別readerが繰り返し開く条件でテスト用1000件の完走・最終結果保存を確認した。GUIは古いfailed状態よりterminal.jsonのcompletedを優先する実画面試験が通過した。証跡はexperimental-build/long-run-lock-regression.logとlong-gui-terminal-test。初回作成時の関連26試験も通過済み。

再開時は実行先のterminal.json、results.json、status.jsonの順で状態を読み、samples.jsonl、environment.jsonも確認する。statusがcompleted/completed_with_errors/cancelled/failedかを区別し、件数と要求失敗を確認してから報告する。まだrunningの場合はプロセスと更新時刻を確認する。進捗JSONの保存省略数はprogressWriteSkipsに記録する。GUIは結果フォルダーを開くボタンと停止要求ボタンを持ち、閉じても実行は続く。GUIを再表示する場合はbundled PowerShellの-STAでShow-LongContextProgress.ps1へ同じRunDirectoryを渡す。モデルサーバーはworkerが終了時に自分のプロセスだけ停止する。

## 文脈評価の試作と初回比較

2026年10月15日、利用者の「実装してみよう」「学習パターンを作って比較したい」に対応し、E:/prog/Meltype/Tools/context-evaluationで実装した。分岐元はTools/1.1.1-sourceの5438d7a。Git worktreeで分離し、分岐元のファイル・インデックス、PC適用版、公開物は変更していない。この作業場所は実験用で、分岐元の更新候補を再適用する場所ではない。

未確定の読み全体と前後文脈をローカルzenzへ渡し、既存候補の中から文章全体として選ぶ。英語・数字・記号は保持する。180msの待機後に非同期評価し、期限は1500ms。新しい入力・取消・確定・手動候補選択後の古い結果は破棄する。表示中の補正は、対応する読みと基準文字列の前方一致が保たれる範囲で入力中の子音にも維持する。自動補正結果を新しい予測履歴へ保存しない。既存の手動変換の学習方法は変更していない。

Native brokerは`MELTYPE_CONTEXT_ENDPOINT`を明示した場合だけ有効。LLM要求は別タスクで処理し、Native DLLは待機中だけ40ms間隔で結果を回収する。現在のTSFフォーカスと入力欄保護を確認し、同じ未確定範囲へ更新する。通常は無効。PCへの適用・インストーラー作成・外部公開は未実施。

学習実験はモデル重みの追加訓練ではなく、隔離したメモリ上の4種類の履歴適用方式を比較する。学習用10イベントと別文脈の評価26例、20周を使用。合成候補による対照実験と、実Google候補での7入力の再生を分けている。仕様・再実行手順はdocs/CONTEXT_EVALUATION.md。個人の実入力や普段の辞書・履歴を実験へ使っていない。

検証済み: 共通・Windows503/503、既存品質1337/1337。新規9試験には古い結果・期限切れ・候補外出力・記号保護・手動選択・入力中子音の表示保持・確定値・余分な同期エンジン呼出し防止・文脈をまたぐ履歴の影響を含む。Native DLLのC++ビルド、実TSF文書の待機中補正・Enter確定・Esc取消・COM解放が通過。既存の入力モード、直接入力判定、再変換、Tab、private欄の学習抑止と通常欄への復帰も通過。証跡はexperimental-build/context-*、native-context-evaluation.log、native-upstream-features.log。

残作業・制限: 実アプリの使用感、長時間入力、複数アプリ同時入力、GPUは未検証。既存候補に無い表記、新しい文節区切り、複数文節を同時変更する候補は生成しない。Nativeの入力欄の外側の右文脈は未取得。C++の記号全角化など、既存の日英区間判定由来の表記は今回直さず、モデルがそれ以上変えないようにした。文脈別学習は完全一致のみで、今回の別文脈評価では再利用0件のため学習効果は未検証。次は実験例を増やし、改善・悪化の内訳から候補生成範囲と採用条件を調整する。

## 分岐元の更新候補と適用状態

本家mainの9a25e7cから45e14f8までの26コミットをWindows Native版へ取り込み、候補1.1.2-rc.3の検証と配布物構築を完了した。PC適用はWindowsの管理者確認が取り消されたため未完了。旧1.1.2-rc.2へ復旧済み。本家ReleaseとBaseVersionは1.2.1。取り込み仕様と進行状況はdocs/UPSTREAM_45E14F8.md。外部公開は今回の内容への確認待ち。

直前の候補1.1.2-rc.2は、利用者が依頼した直接入力のローマ字判定・選択範囲再変換・Tab変換を実装し、2026年10月15日の利用者の指示によりPCへ適用済み。この3機能と辞書・設定を保持する。Androidは対象外。

2026年10月15日、45e14f8までの取り込みを実装し、共通・Windows494/494、品質1337/1337、Native18/18、Google13/13、Microsoft2/2が通過した。独自TSFのprivate欄の入力と学習抑止、通常欄の学習再開、password/PIN保護、打鍵ローマ字の候補上部表示を追加した。直接入力判定・再変換・Tab変換、候補配置、予測・定型文、検索AppContainer入力、通信32枠、設定、管理画面、更新失敗時の復旧とインストーラー試験も通過した。

対応ソースadf81c7ce23ca4bbb92042f2fa60d3967f0dfefeからセットアップEXEと.sha256を構築・照合した。EXEはdistributions/Meltype-Native-Google-1.1.2-rc.3-Setup.exe、SHA256は6F09BA2522C5C4B262C63C4254E0AC2E0B65CA7A277C05A051CED802BED5AFDC。製品・ファイル番号、配置対象6ファイルとmanifest、同梱主要ソース18点を確認した。ソースは改行コードを正規化して比較した。証跡はexperimental-build/upstream-45e14f8-*。

2026年10月15日09:18JST、標準Update-NativeIme.ps1を1回実行した。辞書・設定11ファイルをbackups/20261015-091837へ退避し、退避ハッシュ11/11一致を確認した。入力設定はbackups/upstream-45e14f8-preferences-20261015-091835に追加退避し、退避・現在値のハッシュ一致を確認した。09:19JSTにconsent.exeのPID70440が通常の管理者確認待ちだったが、その後Windowsが「この操作はユーザーによって取り消されました」と返した。実行セッションは66649。エージェントによる確認回避・プロセス強制停止・取消・再実行は行っていない。

標準アップデータは旧1.1.2-rc.2へ復旧した。旧package-69e97bf1f2f540a5a662ac944ca585a1の6/6ファイルとmanifest、登録DLLの一致、旧パッケージを指定したbrokerの稼働と接続準備、導入済みDLLの入力モードと本家ロゴ、Native日本語プロファイル有効を確認した。入力設定と辞書・設定8ファイルはハッシュ一致、変化は0ファイル。使用中Google DB3ファイルは照合不可。バックアップ11/11は一致した。今回候補のPC適用と適用後検証は未完了。証跡はexperimental-build/upstream-45e14f8-apply.log、apply-status.json、recovered-active-profile.log。再適用は利用者の指示後に行う。

専用ソース作業場所はE:/prog/Meltype/Tools/1.1.1-source、開始コミットは正式1.1.1の86a8ff96b0ce5103f7be8b59fa866d66f488b958。E:/prog/Meltype/Windowsの未コミット作業を編集・取り込んでいない。Android、Mac、Linuxの製品実装は変更していない。別作業の青丸入力モード素材は未取り込み。

## 実装と決定

共通コア・辞書・Windows・本家TIP・関連試験と資料を三者統合した。Google／Microsoft切替、自動／英語表示、本家ロゴ、候補配置、Google辞書・履歴、Windows検索、句読点、学習停止、定型文を正式版ソースから保持した。独自TSFと本家TIPは別実装として扱う。Google従来変換の英語文節保護を維持して本家の境界変更条件を統合した。詳細はdocs/UPSTREAM_9A25E7C.mdとdocs/RELEASE_1_1_2_RC_1.md。

## 2026年10月14日の検証

通常.NET apphostの共通・Windows489/489、品質1337/1337、Native18/18、Google13/13、Microsoft2/2通過。Native DLL、入力モードと本家ロゴ、候補配置・再描画、実TSF文書の変換28更新・予測16更新・定型文11更新×2、管理画面、句読点・学習停止、更新候補・インストーラー・更新失敗時復旧、Windows10/11検索SID、AppContainerからGoogleまでの入力、通信32枠を検証した。証跡はexperimental-build/upstream-9a25e7c-*。

初回のPowerShell反射ランナーではMozc自己起動試験だけ実行方式の相違で失敗した。通常.NET apphostでは全件通過。通常.NETビルドに試験コードの既存nullable警告が3件ある。

## PC適用と配布物

2026年10月14日に稼働登録を確認した。利用者の再適用指示と通常の管理者確認後、NativeVersionは1.1.2-rc.1、BaseVersionは1.2.1、登録パッケージはC:/Program Files/MeltypeNativeGoogle/package-226335951b214906becfbfa57598476a。稼働管理先はC:/Users/AoneSenbongi/Documents/Codex/2026-10-06/https-x-com-yksr-melt-status。

候補1.1.2-rc.1の配布EXEを作成・検証した。対応ソースはd0803f552970855c023d7ec0f94102eea3fc0347。EXEはdistributions/Meltype-Native-Google-1.1.2-rc.1-Setup.exe、SHA256は185E8BF3A03337BAB98BA130CBA94D00377B4B03E4E33C808B2D0C826165746F。EXEの製品/ファイル番号、管理対象6ファイル、同梱主要ソース、ハッシュを照合した。証跡はexperimental-build/upstream-9a25e7c-verified.json。公開済み1.1.1の配布物・タグ・Releaseは変更していない。

2026年10月14日の初回適用は管理者確認の取消で旧版へ復旧した。利用者の明示的な再適用指示を受け、15:36JSTにUpdate-NativeIme.ps1を一度再実行し、通常の管理者確認後に適用が完了した。管理者確認の回避は行っていない。

再適用前バックアップはbackups/20261014-153655、入力設定の追加退避はbackups/upstream-9a25e7c-retry-input-preferences。登録版1.1.2-rc.1、配置6/6ファイルとmanifest、管理スクリプト5/5の一致を確認した。新packageを指定したbrokerプロセスと接続準備、導入済みDLLの入力モード試験を確認し、TSFのGetActiveProfileでNativeの日本語プロファイルが有効なことも確認した。

入力設定は不変。データ11ファイル中7ファイルのハッシュは一致し、phrases.txtは976行から977行へ1行追加、既存行の削除は0。boundary.db・cform.db・segment.dbは使用中で照合不可。バックアップ11/11ファイルのハッシュは一致した。証跡はexperimental-build/upstream-9a25e7c-retry-apply.log、retry-applied.json、retry-check.log、retry-active-profile.log、retry-phrases.json。

候補はローカルのビルド、配布物検証、PC適用と適用後確認まで完了した。外部公開は今回の具体的な内容への確認待ち。入力アプリは新しいDLLを読むため開き直す必要がある。

## 既知の制限と残作業

2026年10月14日、3機能の独自TSF移植と管理画面の2設定を実装した。仕様はdocs/NATIVE_UPSTREAM_FEATURES.md。旧brokerの直接入力打鍵の不具合を隔離試験で再現し、実装後は直接入力の即時表示・キャレット移動・アプリの変換拒否時の文字保持・日本語復帰・英語維持・タスクバー同期、かな／漢字／ローマ字の再変換・Enter確定・Esc復元、Tab変換開始・候補切替・無効設定・空入力での通過・保護欄を実TSF文書で検証した。

通常apphostの共通・Windows489/489、品質1337/1337、Native18/18、Google13/13、Microsoft2/2が通過した。Google/Microsoftの変換、予測16更新、定型文各11更新、入力モード、候補配置、設定保持、管理画面描画とインストーラー隔離試験も通過。dotnetからDLLを直接実行する形式ではMozc自己起動試験1件が失敗し、通常apphostで全件を再検証した。試験がEnvironment.ProcessPathをヘルパーとして起動するためで、製品変更は不要。通常ビルドの既存nullable警告は3件。証跡はexperimental-build/native-upstream-package.log、native-upstream-apphost-tests.log、native-upstream-quality.log、native-upstream-features.log、native-upstream-panel.png。

セットアップEXEを作成済み。distributions/Meltype-Native-Google-1.1.2-rc.2-Setup.exe、SHA256は447EF10B129E1CB2DFCE1C7693C9A9675C36A787D634F7F734C0917B21ECD089。対応ソースは019f81f7ec1cdf02b92447ce55444a5b0c5b2262。製品番号1.1.2-rc.2・ファイル番号1.1.2.0、同梱主要ソース12ファイル、管理対象6ファイル、manifestとSHA256を照合した。証跡はexperimental-build/native-upstream-verified.json。外部公開は未実施。

2026年10月15日、利用者の適用指示と通常の管理者確認後、Update-NativeIme.ps1で1.1.2-rc.2を適用した。登録先はC:/Program Files/MeltypeNativeGoogle/package-69e97bf1f2f540a5a662ac944ca585a1。管理対象6/6ファイル、主要管理スクリプト6/6、入力設定のハッシュ一致、新パッケージを指定したbrokerの接続準備とプロセス、導入済みDLLの入力モード、Native日本語プロファイル有効状態を確認した。証跡はexperimental-build/native-upstream-apply.log、native-upstream-applied.json、native-upstream-active-profile.log。

バックアップはbackups/20261015-073913の11ファイルで、退避ハッシュ11/11が一致した。適用前後で7ファイルは一致し、Googleのhistory.dbは変化した。使用中のboundary.db・cform.db・segment.dbは照合不可。ユーザー辞書、Meltypeのconfig.json・conversions.json・phrases.txtは一致した。入力設定の追加退避はbackups/native-features-preferences-20261015-073910。実アプリの新機能の手入力確認は残る。入力アプリを開き直して新しいDLLを読み込む必要がある。

実アプリでの手入力、複数モニター、テーマ切替、32ビットアプリは未確認。Microsoft辞書への学習書き込みは未対応。直接入力の自動復帰にはTSFから文字位置を取得できる入力欄が必要で、取得できない場合は直接入力を維持する。漢字再変換にはMicrosoft IMEの逆変換を使い、読みを取得できない場合は文字を変更しない。配布物にはMozcヘルパーを含めない。PC適用時は辞書・設定をバックアップし、登録、配置manifest、broker接続準備、辞書・設定の保持を確認する。管理者確認の取消・適用失敗・検証失敗を適用済みと扱わない。
