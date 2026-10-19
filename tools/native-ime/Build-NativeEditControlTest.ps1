param([string]$Compiler='g++.exe')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$output=Join-Path $root 'experimental-build/native-edit-control-test.exe'
New-Item -ItemType Directory (Split-Path $output -Parent) -Force|Out-Null
& $Compiler -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -municode -static '-finput-charset=UTF-8' (Join-Path $root 'native/tsf/NativeEditControlTest.cpp') -lole32 -loleaut32 -luuid -luser32 -o $output
if($LASTEXITCODE -ne 0){throw 'Real EDIT test compilation failed'}
# Build only: this test requires a foreground desktop and is run explicitly.
Write-Output $output
