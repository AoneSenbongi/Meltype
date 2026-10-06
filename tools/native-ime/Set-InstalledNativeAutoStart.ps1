param([switch]$Disable)
$ErrorActionPreference = 'Stop'
$key = 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}\InprocServer32'
$dll = (Get-Item -LiteralPath $key).GetValue('')
$workspace = Split-Path (Split-Path (Split-Path $dll -Parent) -Parent) -Parent
$start = Join-Path $workspace 'tools/native-ime/Start-NativeIme.ps1'
if (-not (Test-Path -LiteralPath $start)) { $start = Join-Path $workspace 'investigation/Start-NativeIme.ps1' }
& (Join-Path $PSScriptRoot 'Set-NativeAutoStart.ps1') -WorkspaceRoot $workspace -StartScript $start -Disable:$Disable
