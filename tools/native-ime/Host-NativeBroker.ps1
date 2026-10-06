param([switch]$Learning, [string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$loadRoot = if ($PackageRoot) { $PackageRoot } else { $build }
$core = Join-Path $loadRoot 'Meltype.Core.dll'
$app = Join-Path $loadRoot 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core) | Out-Null
[Reflection.Assembly]::LoadFrom($app) | Out-Null
$references = @($core, $app) + @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
$brokerSource = if ($PackageRoot) { Join-Path $PackageRoot 'NativeBroker.cs' } else { Join-Path $workspace 'native/tsf/NativeBroker.cs' }
Add-Type -Path $brokerSource -ReferencedAssemblies $references
$created = $false
$mutex = [Threading.Mutex]::new($true, ('Local\' + [MeltypeNativeBroker]::PipeName + '.Mutex'), [ref]$created)
if (-not $created) { $mutex.Dispose(); return }
try {
    [IO.File]::WriteAllText((Join-Path $build 'native-broker.pid'), [string]$PID)
    Write-Output "Native broker ready; learning=$($Learning.IsPresent)"
    [MeltypeNativeBroker]::Run($Learning.IsPresent)
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
