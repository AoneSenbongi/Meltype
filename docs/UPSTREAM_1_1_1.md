# 本家1.1.1の取り込み

## 対象と維持する機能

Windows Native Google版へ本家v1.1.1の更新を取り込む。Androidは変更しない。既存のGoogle日本語入力との接続、独自TSF、検索向け通信制限、通信枠32、管理画面、句読点設定と学習停止を維持する。Googleの辞書・学習履歴・暗号鍵は初期化・復元しない。

Native版の通常変換は従来の判定・分節・候補順を維持し、予測のみ新しい本家コアを利用する既存方針を守る。本家の判定変更を無条件にNative通常変換へ適用しない。共通コアの新しい保護処理との競合は個別に検証する。

## 検証と配布

共通・Windows回帰試験、GoogleとTSF、予測の選択・取消、学習停止、検索通信、管理画面と番号一致を確認する。ローカルの構築・検証後に適用結果を別に記録する。独自配布版番号と本家1.1.1は区別し、公開版と同じ番号で内容を差し替えない。GitHubへのpush・Releaseは内容提示後の個別承認が必要。

## 現在の状態

2026年10月11日、本家v1.1.1タグを取得。Windows Gitの作業ツリーは取り込み前にクリーン。事前merge-treeでREADME、SECURITY、CompositionTests、CompositionController、CompositionDetector、CompositionTextに競合を検出。競合解消とNativeパッケージ構築は完了。共通338件・Windowsを含む353件、Google/TSF・予測・管理機能試験が通過。独自候補番号は1.0.8-rc.1、本家BaseVersionは1.1.1。導入・公開は未実施。
