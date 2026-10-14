# 現在の状態

## 目的と作業場所

本家mainの53fafd036b4d06fab7dae9ca0b9ea4eeafbfe976から9a25e7c27a842a51a7df7d485fb88aa07caca6bcまでをWindows Native Google版へ統合し、候補1.1.2-rc.1の配布物とPC適用結果を準備する。本家ReleaseとBaseVersionは1.2.1。外部公開は今回の内容への確認待ち。

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

実アプリでの手入力、複数モニター、テーマ切替、32ビットアプリは未確認。Microsoft辞書への学習書き込み、本家TIPの直接モード判定・再変換・Tab文節変換の独自TSF移植は未対応。配布物にはMozcヘルパーを含めない。PC適用時は辞書・設定をバックアップし、登録、配置manifest、broker接続準備、辞書・設定の保持を確認する。管理者確認の取消・適用失敗・検証失敗を適用済みと扱わない。
