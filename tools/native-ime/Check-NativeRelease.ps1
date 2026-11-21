param([switch]$Install)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
. (Join-Path $PSScriptRoot 'NativeReleaseUpdater.ps1')
$candidate=Get-NativeLatestRelease '2.0.2'
if(-not $Install -or -not $candidate.Available){$candidate|ConvertTo-Json -Compress;return}
Invoke-NativeReleaseInstall $root $candidate
Write-Output 'Update completed.'
