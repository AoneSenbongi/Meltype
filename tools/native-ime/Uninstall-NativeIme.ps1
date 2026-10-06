$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Uninstall-NativeIme.cmd as administrator.' }
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state = Get-Content (Join-Path $workspace 'experimental-build/native-ime-install.json') -Raw | ConvertFrom-Json
if ($state.UserSid -ne $identity.User.Value) { throw 'Uninstall using the Windows account that installed this IME.' }
& (Join-Path $PSScriptRoot 'Stop-NativeIme.ps1') -NoStartOriginal
& (Join-Path $state.PackageRoot 'native-ime-control.exe') --unregister (Join-Path $state.PackageRoot 'MeltypeNative64.dll')
if ($LASTEXITCODE -ne 0) { throw 'IME unregistration failed. Existing files were preserved.' }
Remove-Item -LiteralPath (Join-Path $workspace 'experimental-build/native-ime-install.json')
Write-Output 'Native IME unregistered. Build and backup files were preserved.'
