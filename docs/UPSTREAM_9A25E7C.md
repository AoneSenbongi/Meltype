# 本家main 9a25e7cのWindows取り込み

## 対象と保持する機能

本家の53fafd036b4d06fab7dae9ca0b9ea4eeafbfe976から9a25e7c27a842a51a7df7d485fb88aa07caca6bcまでの116コミットを比較し、共通コア、辞書、Windows実装、関連試験と資料を三者比較で統合する。本家Releaseはv1.2.1のまま。Windows Native候補は1.1.2-rc.1とする。

作業場所はE:/prog/Meltype/Tools/1.1.1-source、開始ソースは正式1.1.1の86a8ff96b0ce5103f7be8b59fa866d66f488b958。E:/prog/Meltype/Windowsの未コミット変更を編集・取り込まない。Android、Mac、Linuxの製品実装は変更しない。

Google／Microsoft切替、正式ソースの自動／英語表示と本家ロゴ、画面端の候補配置、Google辞書・履歴、検索対応、句読点、学習停止を保持する。本家native/tipの変更は独自native/tsfとは別実装として統合する。青丸アイコン候補は別作業の未コミット素材であり、今回のソースには含めない。

## 手順と検証

本家の追加・更新試験を先に適用し、共通・Windows回帰試験、Google・Microsoft・Native試験、候補表示、入力モード、検索、設定、配布物、インストーラーの試験を行う。成功後に対応ソースをローカルコミットで固定し、候補EXEとSHA256を作成する。

PC適用は既存の明示承認範囲で通常のUpdate-NativeIme.ps1とバックアップを使う。管理者確認は回避しない。登録番号、配置manifest、broker接続準備、辞書・設定の保持を確認する。取消・失敗・検証失敗は適用済みと扱わない。外部へのpush、タグ、Release公開は実行しない。

## 現在の状態

2026年10月14日、実装統合と共通・Windows489/489、品質1337/1337、Native18/18、Google13/13、Microsoft2/2が通過した。候補配置、入力モード、検索AppContainer、設定、更新失敗時復旧も通過した。候補EXEを作成し、版番号・ハッシュ・同梱主要ソース・管理対象6ファイルを照合した。

PC適用は管理者確認の取消で未完了。旧1.1.1-rc.2の登録、配置6ファイル、brokerの起動・接続準備、入力モードへ復旧したことを確認した。入力設定は不変、データ8ファイルはハッシュ一致、使用中Google DB3ファイルは照合不可。バックアップ11ファイルのハッシュは一致。再適用は利用者の指示を待つ。外部公開は未実施で、公開候補の完了扱いにしない。

競合はREADME、本家USAGE、CompositionController.Resizeの3件。READMEの本家スポンサー追加はForkの対象外とし、USAGEは設定スイッチの説明へ更新した。ResizeはLegacyGoogleConversionの英語文節保護を残し、境界を動かせない場合に読み直しの副作用が出ない本家の条件を統合した。

ToggleSwitchのコンパイルに必要なMicrosoft.Win32.SystemEvents.dllは既存ランタイムに同梱済みで、バンドルコンパイラの参照へ追加した。Mozcの自己起動試験はPowerShell反射ランナーでは実行方式が適合しないため、通常.NET apphostで全件検証した。
