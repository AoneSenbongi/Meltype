#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Yukishiro
#
# テスト版の Meltype.app を ~/Library/Input Methods に入れる。zip を展開したフォルダーで実行する:
#   bash install.sh
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -d Meltype.app ]]; then
    echo "Meltype.app が見つかりません。zip を展開したフォルダーで実行してください。" >&2
    exit 1
fi

# 入力ソースの「+」の一覧に Meltype が出ない Mac がある (macOS 26、#21)。
# ことえりと同じ形で、有効な入力ソースの一覧 (AppleEnabledInputSources) に入れておく。もう入っていれば何もしない。
enable_input_source() {
    local id=io.github.yksr-melt.inputmethod.Meltype
    defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "$id" && return 0
    defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add \
        "<dict><key>Bundle ID</key><string>$id</string><key>InputSourceKind</key><string>Keyboard Input Method</string></dict>" \
        "<dict><key>Bundle ID</key><string>$id</string><key>Input Mode</key><string>$id.Japanese</string><key>InputSourceKind</key><string>Input Mode</string></dict>"
    killall TextInputMenuAgent 2>/dev/null || true
    echo "入力ソースに Meltype を追加しました"
}

# 入力ソースの登録をやり直す (#134)。Meltype.app を入れ替えるとき、バンドルが無い一瞬に入力ソースの
# 走査が走ると、macOS は登録を消す。消えたあとは、バンドルを戻して走査し直しても戻らないことがあり、
# これまではログアウトするしかなかった。TISRegisterInputSource なら実行中でも戻せる。
register_input_source() {
    local tool="$TARGET/Meltype.app/Contents/MacOS/MeltypeRegisterInputSource"
    # この道具が入っていない Meltype.app (これまでの版) のときは何もしない。
    [[ -x "$tool" ]] || return 0
    "$tool" "$TARGET/Meltype.app" ||
        echo "入力ソースに登録できませんでした。ログアウトしてログインし直すと直ります。" >&2
}

TARGET="$HOME/Library/Input Methods"
mkdir -p "$TARGET"
pkill -x Meltype 2>/dev/null || true
rm -rf "$TARGET/Meltype.app"
cp -R Meltype.app "$TARGET/"
# インターネットから取ってきた印 (隔離属性) を外す。署名が自分用なので、外さないと macOS が起動させない。
xattr -dr com.apple.quarantine "$TARGET/Meltype.app" 2>/dev/null || true

echo "インストールしました: $TARGET/Meltype.app"
enable_input_source
register_input_source
echo
echo "使うときは:"
echo "  1. メニューバーの入力メニューで Meltype を選ぶ"
echo "     (出ていなければ、システム設定 → キーボード → 入力ソース →「編集…」→「+」→ 日本語 → Meltype を追加)"
echo "  2. それでも出てこなければ、いったんログアウトしてログインし直す"
