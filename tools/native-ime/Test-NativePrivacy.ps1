param([ValidateSet('All','Private','Typed')][string]$Mode='All')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $root 'experimental-build'
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.Core.dll'))|Out-Null
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.dll'))|Out-Null
$fixture=Join-Path $build ('privacy-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
[IO.File]::WriteAllText((Join-Path $fixture 'config.json'),'{"showTypedKeys":true}')
[IO.File]::WriteAllText((Join-Path $fixture 'input-preferences.json'),'{"ConversionEngine":"Microsoft","LearningEnabled":true}')
$source=[IO.File]::ReadAllText((Join-Path $root 'native/tsf/NativeBroker.cs'))
$original='private static readonly string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Meltype");'
if(-not $source.Contains($original)){throw 'Broker fixture substitution no longer matches'}
$source=$source.Replace($original,('private static readonly string DataDirectory = @"'+$fixture+'";'))
$source=$source.Replace('Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MeltypeNativeGoogle", "input-preferences.json"',('@"'+$fixture+'", "input-preferences.json"'))
$broker=Join-Path $fixture 'NativeBroker.cs';[IO.File]::WriteAllText($broker,$source)
$refs=@((Join-Path $build 'Meltype.Core.dll'),(Join-Path $build 'Meltype.dll'))+@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll'|ForEach-Object FullName)
Add-Type -Path @($broker,(Join-Path $PSScriptRoot 'NativePrivacyTransportTest.cs')) -ReferencedAssemblies $refs
[NativePrivacyTransportTest]::Run($fixture,$Mode).GetAwaiter().GetResult()
Write-Output 'PASS: isolated Microsoft broker privacy/normal learning, typed keys and legacy response contract'
