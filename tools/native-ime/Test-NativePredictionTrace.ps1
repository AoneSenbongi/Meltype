$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $root 'experimental-build'
$core = Join-Path $build 'Meltype.Core.dll'
$app = Join-Path $build 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core) | Out-Null
[Reflection.Assembly]::LoadFrom($app) | Out-Null
$references = @($core,$app) + @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
Add-Type -Path (Join-Path $PSScriptRoot 'Generate-NativeCompositionTrace.cs') -ReferencedAssemblies $references
$trace = Join-Path $build 'native-prediction-trace.bin'
[NativeCompositionTrace]::RunPrediction($trace)
& (Join-Path $build 'native-composition-test.exe') $trace
if ($LASTEXITCODE -ne 0) { throw 'Prediction -> TSF document verification failed' }
