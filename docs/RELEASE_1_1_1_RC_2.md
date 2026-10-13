# Meltype Native Google 1.1.1-rc.2 公開準備

公開先はAoneSenbongi/Meltype、ブランチgoogle-native-ime、予定タグnative-google-1.1.1-rc.2。タイトルは「Meltype Native Google 1.1.1-rc.2 — 本家main更新の取り込み」。公開は未承認。

本家Meltype v1.2.1の47ace142からmain 53fafd0までの共通コア、辞書、Windows実装を取り込みました。日英混在、つを含むローマ字、ユーザー辞書と文節境界、語句の後ろの変換、予測候補の扱いを更新しました。独自Google通常変換、Microsoft/Google切替、タスクバーの自動／英語表示、本家ロゴ、画面端での候補配置、検索、句読点、学習停止と定型文を保持しています。

共通・Windows456/456、Native18/18、Google13/13、Microsoft2/2が通過しました。候補配置、入力モードとアイコン、実TSF文書の変換・予測・定型文、検索AppContainerから本番brokerとGoogleへの変換、管理画面、更新候補、配布物検証、インストーラー、失敗時復旧を検証済みです。

PCへの適用は管理者確認が取り消されたため未完了です。旧1.1.1-rc.1の登録と6ファイルのmanifest一致、broker稼働と接続準備を確認しました。11ファイルのバックアップハッシュが一致し、設定・辞書・履歴の8ファイルも適用前と一致しました。Google稼働中のboundary.db、cform.db、segment.dbは開かれており、現在のハッシュ一致は未検証です。

実アプリの手入力、複数モニター、32ビットアプリは未検証です。本家TIPのAlt+バッククォート、直接モード判定、選択範囲再変換は独自TSFへ移植していません。Microsoft辞書の学習書き込みは未対応です。

配布EXEはdistributions/Meltype-Native-Google-1.1.1-rc.2-Setup.exe、ハッシュファイルは同名.sha256です。SHA256は3E298D602E78E5E82350DEC2FE094D05E4AEF0B2A10FC2E16F6FC7C0F3AD5DA6。対応ソースは候補スナップショット3f8f44d595cc34ec827d2fc6dc8e7504939f7feaを配布内のcorresponding-source.zipに同梱しています。このスナップショットは開始時点の未コミット入力モード修正も含みます。通常ブランチHEAD 2145bb2と通常インデックスは変更していません。