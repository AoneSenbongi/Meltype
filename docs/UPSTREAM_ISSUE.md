Meltypeを元に、Google日本語入力と連携する非公式のWindows TSF版を作成しました。独自の入力用ポップアップではなく、入力先のテキスト欄に未確定文字を表示したいという目的で開発しています。元のMeltypeの公開と開発に感謝します。

日英自動判別とライブ変換を共有コアで処理し、日本語の変換にはPCにインストール済みのGoogle日本語入力を利用します。既存のユーザー辞書・学習履歴を使い、学習が有効な場合には確定結果を一致確認してGoogleへ通知します。Google本体のプログラムやシステム辞書は変更・同梱していません。

管理画面から導入・起動・停止・自動起動設定・Googleの単語登録と辞書管理を操作できます。全角句読点「，」「．」、候補選択、日英モード切替も提供します。

ソース: https://github.com/AoneSenbongi/Meltype/tree/google-native-ime
配布: https://github.com/AoneSenbongi/Meltype/releases/tag/native-google-1.0.2
セキュリティ説明: https://github.com/AoneSenbongi/Meltype/blob/google-native-ime/SECURITY.md

lnkiai氏のIME化Forkで公開された入力スコープ保護と通信先確認も参考にし、該当コードに出典とGPLの表記を残しました。
https://github.com/lnkiai/Meltype/releases/tag/ime-1.0.1-2

現在の配布対象はWindows 10／11 x64のデスクトップアプリです。198件の既存テスト、Google接続とTSF文書でのライブ更新・確定・取消・モード切替、管理画面、起動・更新、秘密入力欄の保護とパイプ通信先の試験を実施しました。利用者による別PCでの入力確認もあります。

Windows検索欄で入力できない問題は残っています。ストアアプリ／AppContainer、32ビットアプリ、ARM64は対応範囲に含めていません。非公式IPCを使うため、Google側の更新によって接続できなくなる可能性もあります。コード署名や第三者によるセキュリティ監査は実施していません。

実装・テスト・文書の作成にはCodexを使用しています。元のMeltypeの著作権・ライセンスを保持し、配布ZIPには対応するソースとランタイムのライセンス通知を同梱しています。参考になる部分があれば、実装や検証結果を共有できればと思います。
