param([string]$Compiler='E:/prog/w64devkit/bin/g++.exe')
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$probe=Join-Path $workspace 'experimental-build/search-peer-probe.exe'
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -static -static-libgcc -static-libstdc++ (Join-Path $workspace 'native/tsf/NativeSandboxProbe.cpp') -luserenv -ladvapi32 -o $probe
if($LASTEXITCODE -ne 0){throw 'Sandbox probe compilation failed'}
function Invoke-Probe([string]$Mode,[string]$Policy) {
    $output=& $probe $Mode $Policy
    if($LASTEXITCODE -ne 0){throw 'Isolated probe setup failed'}
    $output|ConvertFrom-Json
}
$baseline=Invoke-Probe '--server-check' '--baseline'
if($baseline.processQueryError -ne 5){throw 'Expected peer identity query denial was not reproduced'}
$granted=Invoke-Probe '--server-check' '--grant-query'
if($granted.processQueryError -ne 0 -or $granted.tokenQueryError -ne 0){throw 'Limited peer metadata permission did not work'}
$allowed=Invoke-Probe '--pipe-check' '--allowed'
if($allowed.pipeConnectError -ne 0 -or $allowed.processQueryError -ne 0 -or $allowed.tokenQueryError -ne 0){throw 'Allowed sandbox cannot connect and inspect its server'}
if($allowed.extraServerError -ne 5){throw 'Sandbox received permission to create an extra server'}
$unrelated=Invoke-Probe '--pipe-check' '--unrelated'
if($unrelated.pipeConnectError -ne 5){throw 'Unrelated sandbox SID was not rejected'}
[ordered]@{Baseline=$baseline;LimitedMetadata=$granted;AllowedPackage=$allowed;UnrelatedPackage=$unrelated}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $workspace 'experimental-build/search-peer-access-result.json') -Encoding utf8
Write-Output 'PASS: peer metadata query reproduced; exact package SID can connect/query; unrelated package and extra pipe server denied. Production IME unchanged.'
