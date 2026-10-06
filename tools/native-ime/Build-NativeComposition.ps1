param([string]$Compiler = 'g++.exe', [switch]$GoogleTrace, [switch]$Broker)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source = Join-Path $workspace 'native/tsf'
$output = Join-Path $workspace 'experimental-build/native-composition-test.exe'
$Compiler = (Get-Command $Compiler -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath $Compiler)) { throw "C++ compiler not found: $Compiler" }
& $Compiler -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-misleading-indentation -static -static-libgcc -static-libstdc++ '-finput-charset=UTF-8' "${source}/NativeComposition.cpp" "${source}/NativeCompositionTest.cpp" -lole32 -loleaut32 -luuid -o $output
if ($LASTEXITCODE -ne 0) { throw 'Native composition compilation failed' }
$arguments = @()
if ($GoogleTrace -or $Broker) { $arguments = @((Join-Path $workspace 'experimental-build/native-composition-trace.bin')) }
if ($Broker) { $arguments += (Join-Path $workspace 'experimental-build/MeltypeNative64.dll') }
& $output @arguments
if ($LASTEXITCODE -ne 0) { throw 'Native composition verification failed' }
