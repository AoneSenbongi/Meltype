param([Parameter(Mandatory)][string]$WorkspaceRoot, [switch]$Remove)
$ErrorActionPreference = 'Stop'
$folder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Meltype Google日本語入力'
$linkPath = Join-Path $folder 'Meltypeの管理画面.lnk'
if ($Remove) { if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath }; return }
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath = Join-Path $WorkspaceRoot 'Meltype-Settings.exe'
$link.WorkingDirectory = $WorkspaceRoot
$link.Description = 'Meltypeの起動、停止、辞書登録と設定'
$link.Save()
[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
