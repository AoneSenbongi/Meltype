$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$context = Get-NativeGuiContext $workspace
if (-not $context.Installed) { throw 'Native IME is not registered.' }
$public = Join-Path $context.Root 'tools/native-ime/Uninstall-NativeIme.ps1'
$script = if (Test-Path -LiteralPath $public) { $public } else { Join-Path $context.Scripts 'Uninstall-NativeIme.ps1' }
& $script
& (Join-Path $PSScriptRoot 'Set-NativeAutoStart.ps1') -Disable -WorkspaceRoot $context.Root
& (Join-Path $PSScriptRoot 'Set-NativeShortcuts.ps1') -Remove -WorkspaceRoot $context.Root
