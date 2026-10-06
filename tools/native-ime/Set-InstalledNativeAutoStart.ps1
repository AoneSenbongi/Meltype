param([switch]$Disable)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$context=Get-NativeGuiContext (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
if(-not $context.Installed){throw 'Install the native IME first.'}
$workspace=$context.Root
$start=Join-Path $context.Scripts 'Start-NativeIme.ps1'
& (Join-Path $PSScriptRoot 'Set-NativeAutoStart.ps1') -WorkspaceRoot $workspace -StartScript $start -Disable:$Disable
