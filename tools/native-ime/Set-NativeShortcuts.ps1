param([Parameter(Mandatory)][string]$WorkspaceRoot, [switch]$Remove, [switch]$NoDesktop)
$ErrorActionPreference = 'Stop'
$folder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Meltype Google日本語入力'
$linkPath = Join-Path $folder 'Meltypeの管理画面.lnk'
$desktopLink = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Meltype Google日本語入力.lnk'
$target = Join-Path $WorkspaceRoot 'Meltype-Settings.exe'
$shell = New-Object -ComObject WScript.Shell
try {
    if ($Remove) {
        foreach ($path in @($linkPath,$desktopLink)) {
            if (Test-Path -LiteralPath $path) {
                $link=$shell.CreateShortcut($path)
                if ($link.TargetPath -eq $target) { Remove-Item -LiteralPath $path }
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)|Out-Null
            }
        }
        return
    }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $paths=@($linkPath)
    if (-not $NoDesktop) { $paths += $desktopLink }
    elseif (Test-Path -LiteralPath $desktopLink) {
        $link=$shell.CreateShortcut($desktopLink)
        if ($link.TargetPath -eq $target) { Remove-Item -LiteralPath $desktopLink }
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)|Out-Null
    }
    foreach ($path in $paths) {
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $target
        $link.WorkingDirectory = $WorkspaceRoot
        $link.Description = 'Meltypeの起動、停止、辞書登録と設定'
        $link.IconLocation = $target + ',0'
        $link.Save()
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)|Out-Null
    }
} finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)|Out-Null }
