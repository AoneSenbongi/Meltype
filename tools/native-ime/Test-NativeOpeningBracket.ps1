$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $root 'experimental-build'
& (Join-Path $build 'native-composition-test.exe') (Join-Path $build 'native-composition-trace.bin') (Join-Path $build 'MeltypeNative64.dll') --eligibility-only
if($LASTEXITCODE -ne 0){throw 'Opening bracket key capture verification failed'}
