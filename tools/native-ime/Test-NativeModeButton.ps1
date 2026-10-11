param([string]$Compiler='g++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$test=Join-Path $root 'experimental-build/native-mode-button-test.exe'
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -static (Join-Path $root 'native/tsf/NativeModeButtonTest.cpp') -lole32 -loleaut32 -luuid -lgdi32 -luser32 -o $test
if($LASTEXITCODE -ne 0){throw 'Mode button test compilation failed'}
& $test (Join-Path $root 'experimental-build/MeltypeNative64.dll')
if($LASTEXITCODE -ne 0){throw 'Mode button verification failed'}
