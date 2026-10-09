param()
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $workspace 'experimental-build'
$core=Join-Path $build 'Meltype.Core.dll';$app=Join-Path $build 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core)|Out-Null
[Reflection.Assembly]::LoadFrom($app)|Out-Null
$references=@($core,$app)+@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll'|ForEach-Object FullName)
Add-Type -Path (Join-Path $workspace 'native/tsf/NativeBroker.cs') -ReferencedAssemblies $references
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
if([Environment]::OSVersion.Version.Build -ge 22000) {
 $observed=@(Get-AppxPackage | Where-Object Name -eq 'MicrosoftWindows.Client.CBS')
 if($observed.Count -ne 1){throw 'Windows 11 search package identity is not available'}
 if([MeltypeNativeBroker]::SearchPackageSid -ne [MeltypeNativeBroker]::PackageSid($observed[0].PackageFamilyName)){throw 'REPRODUCED: broker denies the observed Windows 11 search package SID'}
}
foreach($buildNumber in @(19045,21999,22000,26200)) {
 $expected=if($buildNumber -ge 22000){'MicrosoftWindows.Client.CBS_cw5n1h2txyewy'}else{'Microsoft.Windows.Search_cw5n1h2txyewy'}
 if([MeltypeNativeBroker]::SearchPackageForBuild($buildNumber) -ne $expected){throw "Broker package selection differs at build $buildNumber"}
 if((Get-NativeSearchPackageName $buildNumber) -ne $expected){throw "Registration package selection differs at build $buildNumber"}
}
if([MeltypeNativeBroker]::PackageSid('Microsoft.Windows.Search_cw5n1h2txyewy') -ne 'S-1-15-2-536077884-713174666-1066051701-3219990555-339840825-1966734348-1611281757'){throw 'Windows 10 SID changed'}
if([MeltypeNativeBroker]::PackageSid('MicrosoftWindows.Client.CBS_cw5n1h2txyewy') -ne 'S-1-15-2-283421221-3183566570-1718213290-751554359-3541592344-2312209569-3374928651'){throw 'Windows 11 SID differs from observed token'}
Write-Output ('PASS: Windows 10/11 package boundary, registration agreement, both observed SIDs; current OS build '+[Environment]::OSVersion.Version.Build)
