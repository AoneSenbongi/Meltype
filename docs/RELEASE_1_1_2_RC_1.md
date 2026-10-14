# Meltype Native Google 1.1.2-rc.1 レビュー資料

## 公開候補

公開予定先はAoneSenbongi/Meltype、ブランチgoogle-native-ime。現在の配布候補番号は1.1.2-rc.1。候補として公開する場合のタグはnative-google-1.1.2-rc.1、タイトルはMeltype Native 1.1.2-rc.1とする。正式版1.1.2として公開する場合は、正式番号に変更して再構築・検証する。外部公開は未実施で、今回の内容への利用者確認が必要。

## 本文案

本家v1.2.1以降のmain更新を9a25e7c27a842a51a7df7d485fb88aa07caca6bcまで取り込みました。英語辞書の補正、変換中のキー処理と文節境界の改善、設定画面のスイッチ、設定の同時変更保持、バックアップ復元の事前検証、Mozcの起動・終了とキャッシュの改善を含みます。本家コアの番号は1.2.1です。

Google／Microsoft切替、自動／英語表示、本家ロゴ、候補の画面端配置、Windows検索、辞書と学習履歴、句読点設定、学習停止、定型文を保持しています。青丸の入力モードアイコンは別作業の未コミット素材のため、この候補には含みません。

Windows 64ビット向けです。Google日本語入力が必要です。管理者確認を伴う保護領域への配置を行います。更新後は入力アプリを開き直してください。

## 検証

2026年10月14日、通常.NET apphostの共通・Windows489/489、品質1337/1337、Native18/18、Google13/13、Microsoft2/2が通過しました。Native DLL、入力モードと本家ロゴ、候補配置と再描画、実TSF文書の変換28更新・予測16更新・定型文11更新×2、定型文管理画面の初回表示を確認しました。

句読点と学習停止、Google／Microsoft設定保持、管理画面、更新候補、インストーラー、更新失敗時復旧、Windows10/11検索パッケージ選択、AppContainerから実DLLとGoogleまでの入力、通信32枠が通過しました。Googleの学習を停止した隔離試験を使用しています。

本家のMozc自己起動試験は、PowerShell反射ランナーではPowerShellをヘルパーとして起動して失敗します。通常.NET apphostで同試験を含む全件が通過しました。製品の動作不良として扱っていません。バンドルコンパイラにはToggleSwitchが使う既存同梱Microsoft.Win32.SystemEvents.dllの参照を追加しました。

証跡はexperimental-build/upstream-9a25e7c-apphost-all.log、quality.log、package.logと同接頭辞の各試験ログです。通常.NETビルドは成功しましたが、以前から存在する試験コードのnullable警告が3件あります。

## 制限と配布物

実アプリでの手入力、複数モニター、テーマ切替、32ビットアプリは未確認です。Microsoft辞書への学習書き込み、本家TIPの直接モード判定・選択範囲再変換・Tab文節変換の独自TSF移植は未対応です。本家native/tipは別実装として更新しましたが、配布EXEが使用するのは独自native/tsfです。Google版へMozcヘルパーを同梱していません。

配布EXEはdistributions/Meltype-Native-Google-1.1.2-rc.1-Setup.exeと同名.sha256を作成・検証済みです。対応ソースはd0803f552970855c023d7ec0f94102eea3fc0347、EXEのSHA256は185E8BF3A03337BAB98BA130CBA94D00377B4B03E4E33C808B2D0C826165746F。EXEの製品番号は1.1.2-rc.1、ファイル番号は1.1.2.0です。管理対象6ファイルと同梱主要ソースを照合しました。証跡はexperimental-build/installer-build.jsonとupstream-9a25e7c-verified.jsonです。

2026年10月14日のPC適用は管理者確認が取り消されたため未完了です。既存の復旧手順で旧1.1.1-rc.2へ戻し、旧packageの6/6ハッシュ、brokerの起動・接続準備、導入済みDLLの入力モード試験を確認しました。入力設定は不変、データ11ファイル中8ファイルは一致、使用中のGoogle DB3ファイルは照合不可です。バックアップ11/11ファイルのハッシュを確認しました。

この候補はローカルのビルド・配布物検証まで完了しています。PC適用成功条件を満たしていないため、公開候補の完了扱いにはしません。再適用は利用者の指示を待ちます。外部公開は未実施です。詳しい適用結果はdocs/CURRENT_STATE.mdに記録しています。
