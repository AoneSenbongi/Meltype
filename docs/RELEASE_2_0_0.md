# Meltype Native Google 2.0.0 公開準備

公開先はAoneSenbongi/Meltype、ブランチgoogle-native-ime、予定タグnative-google-2.0.0。タイトルは「Meltype Native Google 2.0.0（本家1.3.0対応）」。公開添付はSetup.exeとSHA-256ファイル。以下は最終配布物を提示して確認を受けるための本文案で、未公開。

利用者指定によりComputer Useは使わない。別PC用のSetup・ハッシュ・確認手順をGoogle Driveの専用非公開フォルダーへ配置する。フォルダーはhttps://drive.google.com/drive/folders/18O-ixJFYU9BgPnJBxp54_xMIIPwVYBW_ 。GitHub公開とDriveへの試験用配置を区別する。

## Release本文案

本家Meltype 1.3.0を基にした、Windows x64向けの非公式IMEです。Google日本語入力の辞書を使い、変換文節の区切りを手動で直して、その範囲の候補を選べます。

### このForkの主な追加・変更

- **Google変換でも文節の区切りを編集**：Shift＋左右で読みの範囲を変更し、その範囲全体のGoogle候補を取得します。「に｜だい」を「にだい」にまとめて「荷台」を選ぶ操作に対応します。
- **英語に誤判定された部分も修正**：日本語の読みを持つ英字表示の文節も、Shift＋左右で日本語として範囲変更・変換できます。全文が英字表示になった場合も操作を開始できます。URLや読めない英字は保持します。
- **ローカルzenzをSetupに標準同梱**：zenz-v3.2-small Q5_K_MとCPU推論runtime、ライセンスを一緒にインストールします。別途のモデル取得・手動設定は不要です。前後の文脈から、既存エンジンの候補の範囲で表記を選び直します。
- **Googleの既存辞書・履歴と連携**：管理画面でGoogle／Microsoftを切り替え、Googleの単語登録・辞書管理を利用できます。独自TSFと管理画面、更新前バックアップを使います。

文節編集という操作は本家にもあります。このForkでは、独自Google連携での区切り変更後の候補取得と、英語誤判定からの修正に対応しています。

### 本家由来の対応機能と修正

日英自動判別・共通辞書・予測・定型文・計算候補・EscやFキー操作などをNative入力へ接続しています。計算は本家由来の機能です。入力設定は主管理画面から保存できます。

括弧対だけを確定したときの内側への移動は、位置が外へ戻るNative側の不具合を修正しました。本家1.3.0の新しい「雪の結晶＋M」アイコンも反映しています。

READMEは、本家由来の対応機能・独自変更・未対応を分けて整理しました。文節編集を含む図解4点と実管理画面を掲載し、Setupにも案内を同梱します。

### 必要なものと制限

- Windows 10／11 x64と、別途インストールしたGoogle日本語入力。ランタイムとzenzモデルはSetupに同梱します。
- zenzにはAVX2対応CPUが必要です。非対応CPUではモデルを起動せず、通常のGoogle／Microsoft変換を使います。GPU・APIキーは不要です。
- 入力の判別・変換・モデル推論はPC内で処理します。zenzはCPU負荷・待機時間を伴い、すべての入力で精度が改善する保証はありません。候補にない表記の生成や、文節区切りの自動学習を提供するものではありません。
- 子音略入力・文脈別の日英学習・英字社名予測・GitHub／クリップボード候補・打鍵間隔記録はNativeへ未接続です。対応範囲はREADMEの表を参照してください。
- 更新後は入力アプリを再起動してください。32ビットアプリ・一般のストアアプリ・複数モニターは網羅試験していません。Google連携は非公式IPCで、Googleの更新の影響を受ける可能性があります。

### 検証

共通・Windows回帰637/637、Native20/20、Google16/16、Microsoft2/2が通過した入力処理を維持しています。括弧内移動は通常のWindows EDITで再現・修正確認し、PC適用後に利用者からも成功報告を受領しました。

今回の同梱対応では、任意の別フォルダーへの配置、実モデルの候補評価、所有プロセス終了、移動後の再起動、相対パス逸脱・改ざん拒否、既存の絶対パス設定、AVX2無効化時のモデル停止を検証しています。入力欄を操作する試験は行わず、TSF試験用文書によるモデル連携と区別します。実際の別PCへのSetup導入結果はまだ受領していません。

個人の設定・辞書・入力履歴は同梱しません。対応ソース、MeltypeのGPL、モデルのApache-2.0、推論runtimeのMITと出典通知を同梱します。

## 成果物と証跡

最新の対応ソース、SetupパスとSHA-256はexperimental-build/installer-build.jsonを参照する。README改訂・モデル標準同梱・起動検証の分離を含めて再構築し、古いモデル未同梱EXEを今回の配布物として使わない。

証跡：bundled-model-red.log、bundled-model-refactor.log、bundled-model-legacy.log、bundled-model-noavx.log、bundled-model-tsf.log、bundled-installer-contract.log。梱包とSetup作成後の結果もCURRENT_STATEへ反映する。
