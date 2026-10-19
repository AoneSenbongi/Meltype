# このPCへの2.0.0適用

2026年10月15日、利用者から従来版と版番号を分けてこのPCへ適用する指示を受け、その後に版番号2.0.0を明示指定された。NativeVersion・管理画面・インストーラー設定を2.0.0へ揃える。本家由来のBaseVersionは1.2.1のまま区別する。公開・pushは対象外。

文節単位のローカルzenz評価を有効にするため、この候補パッケージにだけcontext-model.jsonを含める。モデルと必要なruntimeはE:/prog/Meltype/models/zenz-v3.2-smallへ配置し、configに記載したSHA256と照合して起動する。brokerがモデルサーバーを所有し、broker終了時に停止する。動的なloopbackポートだけを使い、再起動時も同じ管理スクリプトから起動する。モデルの標準出力・標準エラーは破棄し、普段の入力をファイルへ保存しない。

標準のUpdate-NativeIme.ps1によるデータバックアップ・保護パッケージ配置・通常のWindows管理者確認・登録・復旧手順を使用する。旧版のパッケージを削除しない。適用後は登録DLL、配置manifest、NativeVersion、brokerとモデルの実プロセス、endpoint、active profileを照合する。管理者確認が取り消された場合は適用済みと報告しない。

## 適用結果

追補: 適用後に利用者から英語しか入力できないと報告があった。旧broker59844とモデル66984の停止を実確認し、登録・状態JSONが残るだけでは稼働を保証しないことを確認した。Windows shellから再起動し、実導入brokerへの隔離入力試験と利用者本人の日本語入力成功で復旧を確認した。停止原因そのものは未確定だが、前回の出力取得ラッパー停止との関係が疑われる。詳細はCURRENT_STATE.mdの復旧記録。以下の適用直後のPID・稼働確認は履歴として扱う。

2026年10月15日、通常の保護パッケージ配置を行い、導入状態NativeVersion2.0.0・BaseVersion1.2.1、登録DLLと配置7/7ファイルのmanifest一致を確認した。配置先はC:/Program Files/MeltypeNativeGoogle/package-894db90c003f4502b230b8f6000b5fef。旧package-69e97bf1f2f540a5a662ac944ca585a1は保持している。broker59844が新しいパッケージを指定し、モデル66984が安定配置先から起動した。loopback endpoint http://127.0.0.1:53365/health はok、brokerも接続準備済み。PID・portはこの確認時の値であり再起動で変わる。

実登録DLLでモードアイコン・自動/英語状態・Windows既存モード保持の試験が通過した。GetActiveProfileでNative CLSIDと日本語profile（langid1041）を確認した。導入済みHost-NativeControlPanel.ps1の版表示は2.0.0。Windows作業場所から起動していた旧版管理画面のみを終了し、導入先の管理画面へ切替起動した。

データ退避はbackups/20261015-180025の11ファイルで、退避ファイルのSHA256は11/11一致。ユーザー辞書、Meltype設定、変換履歴設定ファイル、入力設定・キーボード設定は適用前と一致した。Google history.db・segment.db、Meltype phrases.txtは変更を観測したため同一とは報告しない。予測履歴の読みと表記のキーは1143件全て保持され、8件追加、既存1件の回数・時刻更新があった。Googleの変更DBについて内容の完全一致は未検証。

標準更新の子プロセス終了後も出力取得用のラッパーが残り、出力ファイルは0 bytesだった。更新子プロセスが残っていないことを確認してこの取得処理だけを停止した。成功判定は標準出力に依存せず、上記の実登録・配置ハッシュ・稼働プロセス・health・active profileを独立して照合した結果による。

証跡はexperimental-build/context-2.0.0-applied.json、context-2.0.0-data-check.json、context-2.0.0-phrase-check.json、context-2.0.0-active-profile.log、context-model-lifecycle.log、context-2.0.0-build-package.log。公開・push・インストーラーEXE配布はしていない。開いていた入力アプリは再起動し、新しいDLLを読み込ませる必要がある。
