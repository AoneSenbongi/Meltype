param([string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeContextModel.ps1')
$fixture = Join-Path $root 'experimental-build/roman-model'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'native/tsf/context-model.json') -Destination $fixture -Force
$model = $null
try {
    $model = Start-NativeContextModel $(if ($PackageRoot) { $PackageRoot } else { $fixture }) $fixture
    foreach ($name in @('Meltype.Core','Meltype.Mac.Native','Meltype.Core.Tests','Meltype','Meltype.Tests')) {
        $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $root ('experimental-build/' + $name + '.dll')))
    }
    $runner = $assembly.GetType('Meltype.Tests.TestRunner').GetMethod('Main')
    $arguments = [object[]]::new(1)
    $arguments[0] = [string[]]@('--roman-monitor-bench', $model.Endpoint, (Join-Path $fixture 'result.json'))
    if ($runner.Invoke($null, $arguments) -ne 0) { throw 'Real model replay failed' }
} finally { if ($model) { Stop-NativeContextModel $model } }
