$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($name in @('Meltype.Core','Meltype.Mac.Native','Meltype.Core.Tests','Meltype','Meltype.Tests')) {
    $assembly=[Reflection.Assembly]::LoadFrom((Join-Path $root ('experimental-build/'+$name+'.dll')))
}
$runner=$assembly.GetType('Meltype.Tests.TestRunner').GetMethod('Main')
foreach($filter in @('NativeEngine','Google')) {
    $arguments=[object[]]::new(1); $arguments[0]=[string[]]@($filter)
    if($runner.Invoke($null,$arguments) -ne 0){throw "Conversion tests failed: $filter"}
}
& (Join-Path $PSScriptRoot 'Generate-NativeCompositionTrace.ps1') -Engine Microsoft
& (Join-Path $root 'experimental-build/native-composition-test.exe') (Join-Path $root 'experimental-build/native-microsoft-trace.bin')
if($LASTEXITCODE -ne 0){throw 'Microsoft conversion trace -> TSF verification failed'}
