# Google変換を使うNative版

このForkはWindowsのTSF入力サービスと常駐Brokerを追加する。Meltypeの日英判定とライブ変換を使い、未確定文字は元の入力欄へ表示する。候補選択中だけ白い候補画面を出す。Google日本語入力本体は別途インストールする。

日本語の句読点は全角の「，」「．」。英語区間の記号と、未確定文字内の数値の小数点・桁区切りは半角を維持する。ローマ字入力の区切りで`zh → ←`、`zj → ↓`、`zk → ↑`、`zl → →`を使える。英単語の途中の`zl`などは置き換えない。英数へ手動切替した場合は直接入力する。

## ビルドと起動

別のPCへ移す場合は、`Build-TransferPackage.ps1`で作るWindows x64用ZIPを使う。ZIPには必要なPowerShellランタイム、試作IME、対応するソースを含める。個人の設定・学習履歴・インストール先のパス・Windowsアカウント情報は含めない。移行先のPCではGoogle日本語入力を別途インストールし、ZIPを固定した場所へ展開してから管理者権限で登録する。展開先は登録後に移動しない。

移行用ZIPの`Stop-NativeIme.cmd`は通常のGoogle日本語入力に戻す。元のMeltype常駐版は起動しない。Windowsへサインインした後は`Start-NativeIme.cmd`を通常権限で実行する。句読点設定と学習設定はGoogle側で別途設定する。

起動時はBrokerの準備を最大60秒待つ。起動済みなら再起動せず有効化する。起動失敗時は通常のGoogleへ戻し、この起動操作で開始したプロセスを終了する。画面には`native-broker-errors.txt`と`native-broker-output.txt`の末尾を表示する。従来の約4秒の待機では、初回のコンパイルに時間がかかるPCで正常な起動を拒否していた。

必要な環境はWindows 10/11の64ビット、インストール済みGoogle日本語入力、MinGW-w64のg++、Roslynと.NET参照アセンブリ、Windows Formsを含むPowerShellランタイム。この試作はCodexの同梱PowerShellランタイムとw64devkitで検証した。通常のPowerShell 5.1だけではビルドできない。Googleの変換サービスを一度起動しておく。

1. リポジトリのルートで次を実行する。パスは自分の環境に合わせる。

   ```powershell
   .\tools\native-ime\Build-Package.ps1 -Runtime 'C:\runtime\powershell\pwsh.exe' -Compiler 'C:\w64devkit\bin\g++.exe'
   ```

2. `Install-NativeIme.cmd`を管理者として実行する。設定と学習データを`backups`へ退避してから、この試作IMEを登録する。
3. 管理者画面を閉じ、`Start-NativeIme.cmd`を通常権限で実行する。従来のMeltype常駐を停止し、Native版を有効にする。
4. 通常のGoogleプロファイルと従来のMeltype常駐へ戻す場合は`Stop-NativeIme.cmd`を通常権限で実行する。
5. 登録を削除する場合は`Uninstall-NativeIme.cmd`を管理者として実行する。続けて通常権限で`Start-Meltype.cmd`を実行すると従来版を起動できる。

Google本体の句読点も合わせる場合は、Google日本語入力のプロパティで句読点を「，．」に設定する。Native版の起動スクリプトはGoogleの個人設定を自動変更しない。

## 検証範囲

全角句読点・矢印入力の回帰テスト、既存の入力テスト82件、実際のWindows TSF文書を使う未確定文字・確定・取消の試験が通った。Native DLLのキー処理、Broker、Google変換エンジン、TSF文書を接続した試験も通った。試験中はGoogleへの学習を無効にした。

管理者による登録と通常権限での有効化は実機で成功した。ブラウザー等のフォント・改行・候補配置は使用するアプリで確認する。32ビットアプリとストアアプリは未検証。Native版は前後の確定文字の取得とMeltype独自の永続学習をまだ接続していない。Googleの既存辞書・学習履歴と、通常起動時の確定学習はGoogleエンジンを使う。

入力文字はネットワークへ送らない。Googleへの接続は公開Mozcスキーマを参考にした非公開IPCであり、Googleの更新で接続できなくなる可能性がある。Googleの配布バイナリ・システム辞書・個人の学習履歴はこのForkに含めない。
