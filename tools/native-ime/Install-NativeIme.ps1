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
if ($manifest.UserSid -ne $identity.User.Value) { throw 'Install from the same Windows account that prepared this package.' }
foreach ($file in $manifest.Files) {
    $path = Join-Path $stage $file.Name
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw "Package checksum mismatch: $($file.Name)" }
}
if (Test-Path -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}') {
    throw 'Native IME is already registered. Stop and uninstall the previous native trial before installing again.'
}
$runtime = (Get-Content (Join-Path $build 'runtime-path.txt') -Raw).Trim()
& $runtime -NoProfile -File (Join-Path $PSScriptRoot 'Backup-State.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Backup failed; installation stopped.' }
$package = Join-Path $build ('native-ime-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $package | Out-Null
foreach ($file in $manifest.Files) { Copy-Item -LiteralPath (Join-Path $stage $file.Name) -Destination (Join-Path $package $file.Name) }
$dll = Join-Path $package 'MeltypeNative64.dll'
& (Join-Path $package 'native-ime-control.exe') --register $dll
if ($LASTEXITCODE -ne 0) { throw 'Windows rejected IME registration. Original Google IME remains selected.' }
@{ PackageRoot = $package; Installed = (Get-Date).ToString('o'); UserSid = $identity.User.Value } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $build 'native-ime-install.json') -Encoding UTF8
Write-Output 'Registered native IME. Close this administrator window, then run Start-NativeIme.cmd normally.'
