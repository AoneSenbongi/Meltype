# 現在の状態

## 目的と作業場所

現在は本家mainの9a25e7cから45e14f8までの26コミットをWindows Native版へ取り込んでいる。候補は1.1.2-rc.3。本家ReleaseとBaseVersionは1.2.1。取り込み仕様と進行状況はdocs/UPSTREAM_45E14F8.md。外部公開は今回の内容への確認待ち。

直前の候補1.1.2-rc.2は、利用者が依頼した直接入力のローマ字判定・選択範囲再変換・Tab変換を実装し、2026年10月15日の利用者の指示によりPCへ適用済み。この3機能と辞書・設定を保持する。Androidは対象外。

2026年10月15日、45e14f8までの取り込みを実装し、共通・Windows494/494、品質1337/1337、Native18/18、Google13/13、Microsoft2/2が通過した。独自TSFのprivate欄の入力と学習抑止、通常欄の学習再開、password/PIN保護、打鍵ローマ字の候補上部表示を追加した。直接入力判定・再変換・Tab変換、候補配置、予測・定型文、検索AppContainer入力、通信32枠、設定、管理画面、更新失敗時の復旧とインストーラー試験も通過した。

対応ソースadf81c7ce23ca4bbb92042f2fa60d3967f0dfefeからセットアップEXEと.sha256を構築・照合した。EXEはdistributions/Meltype-Native-Google-1.1.2-rc.3-Setup.exe、SHA256は6F09BA2522C5C4B262C63C4254E0AC2E0B65CA7A277C05A051CED802BED5AFDC。製品・ファイル番号、配置対象6ファイルとmanifest、同梱主要ソース18点を確認した。ソースは改行コードを正規化して比較した。今回候補のPC適用は未完了。証跡はexperimental-build/upstream-45e14f8-*。

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
