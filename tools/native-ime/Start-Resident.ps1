param([switch]$Stop)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $Stop) {
    $pidFile = Join-Path $workspace 'experimental-build/resident.pid'
    if (Test-Path $pidFile) {
        $residentId = [int](Get-Content $pidFile -Raw)
        $running = Get-CimInstance Win32_Process -Filter "ProcessId=$residentId"
        if ($running -and $running.CommandLine -like '*Host-Resident.ps1*') { return }
    }
}
$runtime = Get-Content (Join-Path $workspace 'experimental-build/runtime-path.txt') -Raw
$runtime = $runtime.Trim()
if (-not (Test-Path -LiteralPath $runtime)) { throw 'Bundled PowerShell runtime missing' }
$script = Join-Path $PSScriptRoot 'Host-Resident.ps1'
$arguments = @('-NoProfile','-STA','-File', ('"' + $script + '"'))
if ($Stop) { $arguments += '-Stop' }
$prefix = if ($Stop) { 'stop' } else { 'resident' }
Start-Process -FilePath $runtime -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $workspace -RedirectStandardError (Join-Path $workspace "experimental-build/$prefix-errors.txt") -RedirectStandardOutput (Join-Path $workspace "experimental-build/$prefix-output.txt")
