param([Parameter(Mandatory)][string]$Runtime)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Wait-NativeBroker.ps1')
function Start-Fixture([string]$Code) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    return Start-Process $Runtime -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru
}
function Stop-Fixture([Diagnostics.Process]$Process) {
    if (-not $Process.HasExited) { $Process.Kill(); $Process.WaitForExit() }
    $Process.Dispose()
}
$pipeName = 'Meltype.Startup.Test.' + [Guid]::NewGuid().ToString('N')
$name = '\\.\pipe\' + $pipeName
$process = Start-Fixture "Start-Sleep -Seconds 8; `$pipe=[IO.Pipes.NamedPipeServerStream]::new('$pipeName'); try { `$pipe.WaitForConnection() } finally { `$pipe.Dispose() }"
try {
    Wait-NativeBrokerReady $name $process 15
    if (-not (Test-NativeBrokerReady $name)) { throw 'Ready broker was not reusable' }
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [IO.Pipes.PipeDirection]::Out)
    try { $client.Connect(1000) } finally { $client.Dispose() }
    Write-Output 'PASS: slow startup beyond original four-second timeout; existing ready broker detected'
} finally { Stop-Fixture $process }
$process = Start-Fixture 'exit 23'
try {
    $failure = $null
    try { Wait-NativeBrokerReady $name $process 10 } catch { $failure = $_.Exception.Message }
    if ($failure -notlike '*exited (code 23)*') { throw "Early exit not reported: $failure" }
    Write-Output 'PASS: early process failure reported with exit code'
} finally { Stop-Fixture $process }
$process = Start-Fixture 'Start-Sleep -Seconds 20'
try {
    $failure = $null
    try { Wait-NativeBrokerReady $name $process 1 } catch { $failure = $_.Exception.Message }
    if ($failure -notlike '*within 1 seconds*') { throw "Timeout not reported: $failure" }
    Write-Output 'PASS: finite startup timeout'
} finally { Stop-Fixture $process }
