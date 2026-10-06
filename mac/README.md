# Meltype for Mac (試作)

Mac の正式な IME の仕組み (Input Method Kit) で動く Meltype です。Windows 版と同じく、日本語を打っている途中の英単語は英字のまま、
英語とも日本語とも読める語は前後の文脈で判定します。Mac では OS が IME としてキーを渡してくれるので、
メニューバーの入力メニューにもふつうの IME として表示されます。

> **試作です。** 作者の開発環境 (Windows) ではビルドできていません。ビルドエラーや動かないところがあれば、エラーの全文とあわせて教えてください。

## しくみ

| 部分 | 中身 |
| --- | --- |
| IME 本体 (`Sources/MeltypeIME`, Swift) | Input Method Kit でキーを受け取り、変換中の文字 (下線付き)・候補の一覧・確定を入力欄に反映する |
| 判定の本体 (`src/Meltype.Mac.Native` → `libMeltypeNative.dylib`) | Windows 版と共通の C# の部分 (`src/Meltype.Core`: 英語 / 日本語の判定・ローマ字・変換の流れ・学習・辞書) を NativeAOT で Mac 用のライブラリにしたもの |
| 漢字変換 | [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) の変換エンジン (MIT License、辞書付き) |
| 英単語の判定 | macOS のスペルチェッカー (英語) |

## 必要なもの

- macOS 13 以降 (Apple シリコン / Intel)
- Xcode、またはコマンドライン ツール (`xcode-select --install`)
- .NET 10 SDK (<https://dotnet.microsoft.com/download>。または `curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0`)

## ビルドとインストール

```bash
cd mac
./build.sh
```

1. 本体 (C#) を NativeAOT でビルドし、IME (Swift) をビルドして、`build/Meltype.app` を作ります (初回は azooKey の変換エンジンと辞書のダウンロードで時間がかかります)
2. `~/Library/Input Methods/Meltype.app` にインストールします
3. 初めてのときは、いったんログアウトしてログインし直してから、**システム設定 → キーボード → 入力ソース →「編集…」→「+」→ 日本語 → Meltype** を追加します
4. メニューバーの入力メニューで Meltype を選ぶと使えます

作り直したときは `./build.sh` をもう一度実行すれば入れ替わります (動いている Meltype は自動で止めます)。
`mac/.build` (Swift のビルド結果) は azooKey の辞書の置き場所として使われることがあるので、消さないでください。

## 使い方

- ふつうにローマ字で打つと、下線付きの変換中の文字になります。英単語 (google, github …) は英字のまま
- Space で変換 (候補の一覧が出ます)、Enter で確定、← → で文節の選択、Esc で取り消し
- F6 ひらがな / F7 カタカナ / F9 全角英数 / F10 半角英数
- JIS キーボードの「英数」キーで英数 (直接入力)、「かな」キーで日本語に戻ります
- 設定・学習データ・ユーザー辞書は `~/Library/Application Support/Meltype` (入力メニューの「Meltype のデータフォルダを開く」)。
  設定は Windows 版と同じ `config.json` です (自動判定の強さ `DetectionLevel` など)

## 困ったとき

- 入力ソースに出てこない: ログアウトしてログインし直す。`~/Library/Input Methods/Meltype.app` があるか確かめる。「+」の一覧に出ないときは、ターミナルで次を実行してから入力メニューを見る (`install.sh` も同じことをします、#21)
  ```bash
  defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add \
    '<dict><key>Bundle ID</key><string>io.github.yksr-melt.inputmethod.Meltype</string><key>InputSourceKind</key><string>Keyboard Input Method</string></dict>' \
    '<dict><key>Bundle ID</key><string>io.github.yksr-melt.inputmethod.Meltype</string><key>Input Mode</key><string>io.github.yksr-melt.inputmethod.Meltype.Japanese</string><key>InputSourceKind</key><string>Input Mode</string></dict>'
  killall TextInputMenuAgent
  ```
- 動きがおかしい: ログを見る

  ```bash
  log stream --predicate 'process == "Meltype"' --level debug
  ```

- 止まってしまった: `pkill -x Meltype` (次にキーを打つと macOS が起動し直します)

## Windows 版との違い (今のところ)

- 設定画面・トレイ・ユーザー辞書の画面はありません (`config.json` を直接編集)
- VS Code などのアプリの種類 (コード / 一般) の判定は、まだ Mac では使っていません
- 英数状態でローマ字を検知して日本語に戻す機能は、まだありません
