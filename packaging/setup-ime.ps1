# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 MuNeNICK
#
# setup.exe から、元のユーザーの権限で実行する。
# IME の登録に失敗しても、本体はキーボード方式で使える。
# -Uninstall: アンインストーラーから、インストール先を消す前に実行する (IME の登録を外す)。

param([switch]$Ask, [switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP 'Meltype-setup-ime.log'

try {
    & {
        . (Join-Path $PSScriptRoot 'meltype-ime.ps1')
        if ($Uninstall) {
            if (-not (Uninstall-MeltypeIme)) { Write-Host 'Meltype IME の登録を外せませんでした。' }
        }
        # チェックが OFF でも、登録済みの DLL は本体と一緒に更新する。
        elseif ($Ask -or (Test-MeltypeImeRegistered)) {
            if (-not (Install-MeltypeIme -Source (Join-Path $PSScriptRoot 'tip') -Ask:$Ask)) {
                Write-Host 'Meltype IME を登録できませんでした。Meltype キーボード方式は引き続き使えます。'
            }
        }
        # チェックを外して、登録もしていない: 断ったことを覚えて、Meltype.exe が起動したときに聞かない
        else { Set-MeltypeImeDeclined }
    } *> $log
}
catch {
    Add-Content -LiteralPath $log -Value "Meltype IME の登録に失敗しました: $($_.Exception.Message)" -Encoding UTF8
    exit 1
}
