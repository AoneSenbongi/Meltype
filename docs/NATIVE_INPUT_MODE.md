# タスクバーの入力モード

タスクバーには、日本語を含む自動入力が有効なときは「自動」、IMEを閉じて直接入力するときは「英語」と表示する。Windowsの入力モード表示はGetIconを使うため、GetTextの文字に合わせてモードアイコンにも文字を描く。本家ロゴはIMEの識別アイコンとして保持する。

クリック、半角／全角、IME ON／OFF、WindowsのKEYBOARD_OPENCLOSE変更で、文字・アイコン・ツールチップを同じ状態へ更新する。有効化時にWindowsが既に保持している開閉状態を上書きしない。未設定のときのみ自動を初期値にする。

パスワード、PIN、非公開欄、読み取り専用欄、IMEが無効な入力欄では変換しない。その入力欄での表示は「英語」とし、通常の入力欄へ戻ると元のモードを表示する。入力欄がない場合のWindowsによる無効表示は維持する。

検証はTest-NativeModeButton.ps1でアイコンの描画差とWindowsの開閉状態を確認し、NativeCompositionTest.cppで入力欄の保護と表示を確認する。

Windowsのモード表示仕様は[MicrosoftのIME要件](https://learn.microsoft.com/en-us/windows/apps/develop/input/input-method-editor-requirements)を参照する。
