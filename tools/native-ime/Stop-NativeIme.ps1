param([switch]$NoStartOriginal)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$state = Get-Content (Join-Path $build 'native-ime-install.json') -Raw | ConvertFrom-Json
& (Join-Path $state.PackageRoot 'native-ime-control.exe') --google
if ($LASTEXITCODE -ne 0) { throw 'Windows did not restore the Google profile. Broker was kept running to preserve native input.' }
$taskSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
try {
    $stop = [Threading.EventWaitHandle]::OpenExisting(('Local\Meltype.NativeComposition.' + $taskSid + '.Stop'))
    $stop.Set() | Out-Null
    $stop.Dispose()
} catch [Threading.WaitHandleCannotBeOpenedException] { }
if (-not $NoStartOriginal -and -not $state.Portable) { & (Join-Path $PSScriptRoot 'Start-Resident.ps1') }
Write-Output 'Restored Google profile. Original resident starts only in normal mode.'
