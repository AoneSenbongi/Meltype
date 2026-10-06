param([string]$Compiler='E:/prog/w64devkit/bin/g++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$test=Join-Path $root 'experimental-build/native-candidate-refresh-test.exe'
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -static (Join-Path $root 'native/tsf/NativeCandidateRefreshTest.cpp') -o $test
if($LASTEXITCODE -ne 0){throw 'Candidate repaint test compilation failed'}
& $test (Join-Path $root 'experimental-build/MeltypeNative64.dll')
if($LASTEXITCODE -ne 0){throw 'Candidate selection repaint regression failed'}
