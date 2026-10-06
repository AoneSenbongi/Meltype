$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Update-Punctuation.cmd normally, without administrator privileges.' }
$source = Join-Path $PSScriptRoot 'Meltype.dll'
$hashFile = Join-Path $PSScriptRoot 'Meltype.dll.sha256'
if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-Content -LiteralPath $hashFile -Raw).Trim()) { throw 'Update DLL checksum mismatch' }
$regPath = 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}\InprocServer32'
$native = (Get-Item -LiteralPath $regPath).GetValue('')
if ([IO.Path]::GetFileName($native) -ne 'MeltypeNative64.dll') { throw 'Unexpected registered native IME' }
$package = Split-Path $native -Parent
$build = Split-Path $package -Parent
$workspace = Split-Path $build -Parent
$state = Get-Content (Join-Path $build 'native-ime-install.json') -Raw | ConvertFrom-Json
if ($state.UserSid -ne $identity.User.Value -or $state.PackageRoot -ne $package -or -not $state.Portable) { throw 'The registered IME does not match a portable installation for this Windows account.' }
$scripts = Join-Path $workspace 'tools/native-ime'
$target = Join-Path $package 'Meltype.dll'
if (-not (Test-Path -LiteralPath (Join-Path $scripts 'Start-NativeIme.ps1'))) { throw 'Installed startup script missing' }
& (Join-Path $scripts 'Stop-NativeIme.ps1') -NoStartOriginal
$pidFile = Join-Path $build 'native-broker.pid'
if (Test-Path -LiteralPath $pidFile) {
    $brokerId = [int](Get-Content -LiteralPath $pidFile -Raw)
    $broker = Get-CimInstance Win32_Process -Filter "ProcessId=$brokerId"
    if ($broker -and $broker.CommandLine -like '*Host-NativeBroker.ps1*') {
        Wait-Process -Id $brokerId -Timeout 30 -ErrorAction SilentlyContinue
        $remaining = Get-CimInstance Win32_Process -Filter "ProcessId=$brokerId"
        if ($remaining -and $remaining.CommandLine -like '*Host-NativeBroker.ps1*') { throw 'Native broker has not stopped. Update was not applied.' }
    }
}
$backup = Join-Path $workspace ('backups/punctuation-update-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'Meltype.dll')
Copy-Item -LiteralPath $source -Destination $target -Force
if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $source).Hash) { throw 'Installed update checksum mismatch' }
Write-Output "Punctuation update installed. Previous DLL saved in $backup"
& (Join-Path $scripts 'Start-NativeIme.ps1')
