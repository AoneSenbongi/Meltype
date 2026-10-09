param([switch]$Install)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
. (Join-Path $PSScriptRoot 'NativeReleaseUpdater.ps1')
$candidate=Get-NativeLatestRelease '1.0.7'
if(-not $Install -or -not $candidate.Available){$candidate|ConvertTo-Json -Compress;return}
Invoke-NativeReleaseInstall $root $candidate
Write-Output 'Update completed.'
