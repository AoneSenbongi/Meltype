param([switch]$Tray)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$context = Get-NativeGuiContext $workspace
$runtime = Join-Path $workspace 'runtime/pwsh.exe'
if (-not (Test-Path -LiteralPath $runtime)) {
    $runtimeFile = Join-Path $workspace 'experimental-build/runtime-path.txt'
    if (-not (Test-Path -LiteralPath $runtimeFile)) { $runtimeFile = Join-Path $context.Root 'experimental-build/runtime-path.txt' }
    $runtime = (Get-Content -LiteralPath $runtimeFile -Raw).Trim()
}
$arguments = '-NoProfile -STA -File ' + (ConvertTo-NativeGuiArgument (Join-Path $PSScriptRoot 'Host-NativeControlPanel.ps1'))
if ($Tray) { $arguments += ' -Tray' }
Start-Process -FilePath $runtime -ArgumentList $arguments -WindowStyle Hidden
