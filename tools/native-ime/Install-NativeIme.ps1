$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'IME registration needs administrator privileges. Run Install-NativeIme.cmd as administrator.'
}
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$stage = Join-Path $build 'native-ime-package'
$manifest = Get-Content (Join-Path $stage 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.Architecture -ne 'x64' -or [IntPtr]::Size -ne 8) { throw 'This package requires 64-bit Windows and PowerShell.' }
if (-not $manifest.Portable -and $manifest.UserSid -ne $identity.User.Value) { throw 'Install from the same Windows account that prepared this package.' }
foreach ($file in $manifest.Files) {
    $path = Join-Path $stage $file.Name
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw "Package checksum mismatch: $($file.Name)" }
}
if (Test-Path -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}') {
    throw 'Native IME is already registered. Stop and uninstall the previous native trial before installing again.'
}
$portableRuntime = Join-Path $workspace 'runtime/pwsh.exe'
$runtime = if ($manifest.Portable -and (Test-Path -LiteralPath $portableRuntime)) { $portableRuntime } else { (Get-Content (Join-Path $build 'runtime-path.txt') -Raw).Trim() }
if (-not (Test-Path -LiteralPath $runtime)) { throw 'PowerShell runtime missing. Extract the entire ZIP before installing.' }
if ($manifest.Portable) { Set-Content (Join-Path $build 'runtime-path.txt') $runtime -Encoding UTF8 }
& $runtime -NoProfile -File (Join-Path $PSScriptRoot 'Backup-State.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Backup failed; installation stopped.' }
$package = Join-Path $build ('native-ime-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $package | Out-Null
foreach ($file in $manifest.Files) { Copy-Item -LiteralPath (Join-Path $stage $file.Name) -Destination (Join-Path $package $file.Name) }
$dll = Join-Path $package 'MeltypeNative64.dll'
& (Join-Path $package 'native-ime-control.exe') --register $dll
if ($LASTEXITCODE -ne 0) { throw 'Windows rejected IME registration. Original Google IME remains selected.' }
@{ PackageRoot = $package; Installed = (Get-Date).ToString('o'); UserSid = $identity.User.Value; Portable = [bool]$manifest.Portable } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $build 'native-ime-install.json') -Encoding UTF8
& (Join-Path $PSScriptRoot 'Set-NativeAutoStart.ps1')
Write-Output 'Registered native IME. Close this administrator window, then run Start-NativeIme.cmd normally.'
