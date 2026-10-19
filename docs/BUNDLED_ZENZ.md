# 2.0.0のSetupにローカルzenzを標準同梱する

2026年10月20日、利用者がSetup.exeでモデルも一緒にインストールするよう指定した。モデルの別途取得・手動設定を不要にする。文節編集とGoogle連携をREADMEの主要機能として説明し、計算は本家由来の対応機能に置く。

## 配置と起動

追加のリファクタリング指定により、設定読込・パス解決・資産検証をGet-NativeVerifiedContextModelへ分離する。Startは起動と所有プロセスの管理に専念し、配布時も同じ検証関数で完成したパッケージを確認する。

既存の保護パッケージのmanifestへモデル・CPU推論runtime・相対パスのcontext-model.json・ライセンスと出典通知を追加する。Setupの既存配置・ハッシュ照合・Program Filesへの保護配置・更新と削除を使う。新しい導入方式は設けない。

zenz-v3.2-small Q5_K_M（73,871,936バイト、SHA-256 29C223D4C23327B80FD13EBB5AB2555057A46317997D5DA391584FFBEF0DB673）とazooKey/llama.cpp b4846 Windows AVX2 CPU版を使う。配布用の相対ファイル名はパッケージ内だけで解決し、親ディレクトリへの参照やドライブ指定・区切り文字を拒否する。既存PCの検証済み絶対パス設定は引き続き扱う。

broker起動時に全資産をSHA-256検証し、動的loopbackポートでCPU4スレッド・context1024のモデルを起動する。モデル終了は既存の所有プロセスだけを対象にする。実入力のモデル出力ログは保存しない。AVX2非対応CPUではモデルを起動せず、状態ファイルへ理由を記録し、通常のGoogle／Microsoft変換を使う。

## ライセンス

モデル配布元のApache-2.0表記と、使用runtimeのMITを確認した。モデル出典revision、配布物の改名（内容未変更）、runtimeの配布元とハッシュを通知する。Apache-2.0とb4846のMIT全文を同梱する。

- https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/tree/c67e03e07d215c869f591b274c1631170d3e11fe
- https://github.com/azooKey/llama.cpp/releases/tag/b4846
- https://www.apache.org/licenses/LICENSE-2.0

## 検証

実装前に、任意の別フォルダーへモデルとruntimeを配置して、相対パス設定で起動・制約付き候補評価・所有プロセス終了を行う再現試験を書く。移動後の起動、改ざん・パス逸脱の拒否、旧絶対パス設定と設定なしの既存挙動、AVX2非対応時の通常変換維持を確認する。

Setupの同梱元manifestと全ファイル、ライセンス、個人データ非同梱、旧入力DLL一致、README図と対応ソース、Setupビルド・ハッシュを確認する。Computer Useと画面操作は行わない。実際の他PCへのSetupインストールは未検証として区別する。公開前に最終配布物と変更点を提示する。

## 実装・試験結果

相対設定の試験は修正前にInvalid context model asset pathで失敗し、修正とリファクタリング後に実推論・終了・移動後起動・パス逸脱と改ざん拒否が通過した。既存絶対設定と設定なしも通過。DOTNET_EnableAVX2=0の別プロセスで、モデルを起動せず理由を記録して返ることを確認した。

相対配置した実モデルからbrokerの非同期評価、TSF試験用文書への表示更新・表示どおりのEnter確定・取消が通過した。実アプリの画面操作は行っていない。既存のSetup契約試験（新規・既存ZIPから更新・デスクトップ不要・取消・削除失敗・利用者分離）も通過し、導入済みIMEは変更していない。

証跡はexperimental-build/bundled-model-{red,refactor,legacy,noavx,tsf}.log、bundled-installer-contract.log。Setup梱包結果はinstaller-build.jsonを参照する。Google Driveへの別PC試験用配置は、利用者の明示依頼によるもので、一般公開のReleaseとは区別する。
