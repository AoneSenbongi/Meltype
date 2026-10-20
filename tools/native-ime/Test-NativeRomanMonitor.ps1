param([string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $root 'experimental-build'
. (Join-Path $PSScriptRoot 'NativeContextModel.ps1')
$fixture = Join-Path $build ('roman-broker-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
'{"ConversionEngine":"Microsoft"}' | Set-Content -LiteralPath (Join-Path $fixture 'input-preferences.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $root 'native/tsf/context-model.json') -Destination $fixture
$source = [IO.File]::ReadAllText((Join-Path $root 'native/tsf/NativeBroker.cs'))
$original = 'private static readonly string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Meltype");'
if (-not $source.Contains($original)) { throw 'Fixture substitution no longer matches' }
$source = $source.Replace($original, ('private static readonly string DataDirectory = @"' + $fixture + '";'))
$source = $source.Replace('Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MeltypeNativeGoogle", "input-preferences.json"', ('@"' + $fixture + '", "input-preferences.json"'))
$broker = Join-Path $fixture 'NativeBroker.cs'; [IO.File]::WriteAllText($broker, $source)
foreach ($name in @('Meltype.Core', 'Meltype')) { [Reflection.Assembly]::LoadFrom((Join-Path $build ($name + '.dll'))) | Out-Null }
$refs = @((Join-Path $build 'Meltype.Core.dll'), (Join-Path $build 'Meltype.dll')) + @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
Add-Type -Path @($broker, (Join-Path $PSScriptRoot 'NativeRomanMonitorTransportTest.cs')) -ReferencedAssemblies $refs
$model = $null
$oldEndpoint = $env:MELTYPE_CONTEXT_ENDPOINT
try {
    $model = Start-NativeContextModel $(if ($PackageRoot) { $PackageRoot } else { $fixture }) $fixture
    $env:MELTYPE_CONTEXT_ENDPOINT = $model.Endpoint
    [NativeRomanMonitorTransportTest]::Run().GetAwaiter().GetResult()
} finally {
    $env:MELTYPE_CONTEXT_ENDPOINT = $oldEndpoint
    if ($model) { Stop-NativeContextModel $model }
}
