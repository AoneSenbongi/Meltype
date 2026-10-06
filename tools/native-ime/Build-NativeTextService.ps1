param([string]$Compiler = 'g++.exe')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source = Join-Path $workspace 'native/tsf'
$output = Join-Path $workspace 'experimental-build/MeltypeNative64.dll'
$Compiler = (Get-Command $Compiler -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath $Compiler)) { throw "C++ compiler not found: $Compiler" }
& $Compiler -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-misleading-indentation -shared -static -static-libgcc -static-libstdc++ '-finput-charset=UTF-8' "${source}/NativeComposition.cpp" "${source}/NativeTextService.cpp" -lole32 -loleaut32 -luuid -ladvapi32 -lgdi32 -luser32 -o $output
if ($LASTEXITCODE -ne 0) { throw 'Native text service compilation failed' }
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -static -static-libgcc -static-libstdc++ '-finput-charset=UTF-8' "${source}/NativeImeControl.cpp" -lole32 -luuid -o (Join-Path $workspace 'experimental-build/native-ime-control.exe')
if ($LASTEXITCODE -ne 0) { throw 'Native IME registration utility compilation failed' }
Write-Output "Native TSF module built: $output"
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -mwindows -static -static-libgcc -static-libstdc++ '-finput-charset=UTF-8' (Join-Path $workspace 'native/control-panel/Launcher.cpp') -luser32 -o (Join-Path $workspace 'Meltype-Settings.exe')
if ($LASTEXITCODE -ne 0) { throw 'Management launcher compilation failed' }
