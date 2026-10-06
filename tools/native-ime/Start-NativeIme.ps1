$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$state = Get-Content (Join-Path $build 'native-ime-install.json') -Raw | ConvertFrom-Json
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($state.UserSid -ne $identity.User.Value) { throw 'Start the native IME from the Windows account that installed it.' }
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Start-NativeIme.cmd normally, without administrator privileges.' }
if (-not $state.Portable) { & (Join-Path $PSScriptRoot 'Start-Resident.ps1') -Stop }
else {
    try { $original = [Threading.Mutex]::OpenExisting('Local\Meltype.SingleInstance'); $original.Dispose(); throw 'Stop the original Meltype resident before starting the native IME.' }
    catch [Threading.WaitHandleCannotBeOpenedException] { }
}
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
. (Join-Path $PSScriptRoot 'Wait-NativeBroker.ps1')
$name = '\\.\pipe\Meltype.NativeComposition.' + $identity.User.Value
if (Test-NativeBrokerReady $name) {
    & (Join-Path $state.PackageRoot 'native-ime-control.exe') --native
    if ($LASTEXITCODE -ne 0) { throw 'Windows did not activate the running native IME.' }
    Write-Output 'Native IME already running and active.'
    return
}
$arguments = @('-NoProfile','-File',('"' + (Join-Path $PSScriptRoot 'Host-NativeBroker.ps1') + '"'),'-PackageRoot',('"' + $state.PackageRoot + '"'),'-Learning')
$process = $null
try {
    $process = Start-Process -FilePath $runtime -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $workspace -PassThru -RedirectStandardOutput (Join-Path $build 'native-broker-output.txt') -RedirectStandardError (Join-Path $build 'native-broker-errors.txt')
    Write-Output 'Waiting for native broker startup (up to 60 seconds)...'
    Wait-NativeBrokerReady $name $process
    & (Join-Path $state.PackageRoot 'native-ime-control.exe') --native
    if ($LASTEXITCODE -ne 0) { throw 'Windows did not activate the native IME.' }
    Write-Output 'Native IME active. Use Stop-NativeIme.cmd to return to the original resident.'
} catch {
    $startupError = $_
    foreach ($log in @('native-broker-errors.txt','native-broker-output.txt')) {
        $path = Join-Path $build $log
        Write-Host "Log: $path"
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 0) {
            Get-Content -LiteralPath $path -Tail 15 | ForEach-Object { Write-Host $_ }
        } elseif (Test-Path -LiteralPath $path) { Write-Host '(empty)' }
        else { Write-Host '(not created)' }
    }
    if ($process) { $process.Refresh(); Write-Host "Broker process: $($process.Id); exited=$($process.HasExited)" }
    & (Join-Path $PSScriptRoot 'Stop-NativeIme.ps1')
    if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    throw $startupError
}
