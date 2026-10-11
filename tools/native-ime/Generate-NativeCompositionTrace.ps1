param([ValidateSet('Google','Microsoft')][string]$Engine='Google')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$core = Join-Path $build 'Meltype.Core.dll'
$app = Join-Path $build 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core) | Out-Null
[Reflection.Assembly]::LoadFrom($app) | Out-Null
$references = @($core, $app) + @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
Add-Type -Path (Join-Path $PSScriptRoot 'Generate-NativeCompositionTrace.cs') -ReferencedAssemblies $references
$traceName = if ($Engine -eq 'Microsoft') { 'native-microsoft-trace.bin' } else { 'native-composition-trace.bin' }
[NativeCompositionTrace]::Run((Join-Path $build $traceName),$Engine)
