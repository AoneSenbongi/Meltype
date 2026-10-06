$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$state = Get-Content (Join-Path $build 'native-ime-install.json') -Raw | ConvertFrom-Json
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($state.UserSid -ne $identity.User.Value) { throw 'Start the native IME from the Windows account that installed it.' }
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Start-NativeIme.cmd normally, without administrator privileges.' }
& (Join-Path $PSScriptRoot 'Start-Resident.ps1') -Stop
$pidFile = Join-Path $build 'resident.pid'
if (Test-Path -LiteralPath $pidFile) {
    $residentId = [int](Get-Content $pidFile -Raw)
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $resident = Get-CimInstance Win32_Process -Filter "ProcessId=$residentId"
        if (-not $resident -or $resident.CommandLine -notlike '*Host-Resident.ps1*') { break }
        Start-Sleep -Milliseconds 250
    }
    if ($resident -and $resident.CommandLine -like '*Host-Resident.ps1*') { throw 'Original resident did not stop; native IME was not activated.' }
}
$runtime = (Get-Content (Join-Path $build 'runtime-path.txt') -Raw).Trim()
$arguments = @('-NoProfile','-File',('"' + (Join-Path $PSScriptRoot 'Host-NativeBroker.ps1') + '"'),'-PackageRoot',('"' + $state.PackageRoot + '"'),'-Learning')
try {
    $process = Start-Process -FilePath $runtime -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $workspace -PassThru -RedirectStandardOutput (Join-Path $build 'native-broker-output.txt') -RedirectStandardError (Join-Path $build 'native-broker-errors.txt')
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class NativeBrokerReady { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool WaitNamedPipe(string name, uint timeout); }'
    $name = '\\.\pipe\Meltype.NativeComposition.' + $identity.User.Value
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ([NativeBrokerReady]::WaitNamedPipe($name, 50)) { $ready = $true; break }
        if ($process.HasExited) { throw 'Native broker exited; inspect experimental-build/native-broker-errors.txt.' }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw 'Native broker did not become ready.' }
    & (Join-Path $state.PackageRoot 'native-ime-control.exe') --native
    if ($LASTEXITCODE -ne 0) { throw 'Windows did not activate the native IME.' }
    Write-Output 'Native IME active. Use Stop-NativeIme.cmd to return to the original resident.'
} catch {
    & (Join-Path $PSScriptRoot 'Stop-NativeIme.ps1')
    throw
}
