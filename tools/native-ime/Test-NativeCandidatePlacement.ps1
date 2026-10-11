param([string]$Compiler='g++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$test=Join-Path $root 'experimental-build/native-candidate-placement-test.exe'
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -static (Join-Path $root 'native/tsf/NativeCandidatePlacementTest.cpp') -o $test
if($LASTEXITCODE -ne 0){throw 'Candidate placement test compilation failed'}
& $test (Join-Path $root 'experimental-build/MeltypeNative64.dll')
if($LASTEXITCODE -ne 0){throw 'Candidate placement verification failed'}
