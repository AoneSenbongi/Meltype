$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NativeAutoStart.ps1')
$command = Get-NativeAutoStartCommand 'C:\Users\Test User\AppData\Local\MeltypeNativeGoogle\Startup.ps1'
if ($command -notlike '*-WindowStyle Hidden*' -or $command -notlike '*-File "C:\Users\Test User\*Startup.ps1"') { throw 'Hidden startup or path quoting failed.' }
foreach ($path in @('C:\bad"path.ps1', ('C:\' + ('a' * 260) + '.ps1'))) {
    $rejected = $false
    try { Get-NativeAutoStartCommand $path | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid startup command was accepted.' }
}
Write-Output 'PASS: hidden startup, quoted paths, invalid paths and command length.'
