param([switch]$Baseline)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $root 'experimental-build'
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.Core.dll'))|Out-Null
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.dll'))|Out-Null
$fixture=Join-Path $build ('feature-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
# Settings/histories are isolated. Learning stays off until the Microsoft-only privacy test.
[IO.File]::WriteAllText((Join-Path $fixture 'config.json'),'{"directModeAutoDetect":true,"tabConversion":true}')
$source=[IO.File]::ReadAllText((Join-Path $root 'native/tsf/NativeBroker.cs'))
$original='private static readonly string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Meltype");'
if(-not $source.Contains($original)){throw 'Broker fixture substitution no longer matches'}
$source=$source.Replace($original,('private static readonly string DataDirectory = @"'+$fixture.Replace('"','""')+'";'))
$source=$source.Replace('Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MeltypeNativeGoogle", "input-preferences.json"',('@"'+$fixture.Replace('"','""')+'", "input-preferences.json"'))
$broker=Join-Path $fixture 'NativeBroker.cs';[IO.File]::WriteAllText($broker,$source)
$refs=@((Join-Path $build 'Meltype.Core.dll'),(Join-Path $build 'Meltype.dll'))+@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll'|ForEach-Object FullName)
Add-Type -Path @($broker,(Join-Path $PSScriptRoot 'NativeFeatureTransportTest.cs')) -ReferencedAssemblies $refs
if($Baseline){[NativeFeatureTransportTest]::Baseline().GetAwaiter().GetResult();return}
[NativeFeatureTransportTest]::Run((Join-Path $build 'native-composition-test.exe'),(Join-Path $build 'native-composition-trace.bin'),(Join-Path $build 'MeltypeNative64.dll'),(Join-Path $build 'native-upstream-features.log'),$fixture).GetAwaiter().GetResult()|Out-Null
Get-Content (Join-Path $build 'native-upstream-features.log')
