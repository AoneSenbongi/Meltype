param([string]$ExpectedVersion)
$ErrorActionPreference='Stop'
$iss=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MeltypeSetup.iss'))
$match=[regex]::Match($iss,'#define AppVersion "([^"]+)"')
if(-not $match.Success){throw 'Installer version is missing'}
$version=$match.Groups[1].Value
if($iss -match 'VersionInfoVersion=([^\r\n]+)' -and $Matches[1] -ne ($version.Split('-')[0]+'.0')){throw 'Installer binary version differs'}
if($ExpectedVersion -and $version -ne $ExpectedVersion){throw "Expected version $ExpectedVersion, got $version"}
$checks=@{
    'Host-NativeControlPanel.ps1'="Meltype $version · Google日本語入力"
    'Install-NativeIme.ps1'="NativeVersion = '$version'"
    'Update-NativeIme.ps1'="NoteProperty NativeVersion '$version'"
    'Build-NativeInstaller.ps1'="Meltype-Native-Google-$version-Setup.exe"
}
foreach($name in $checks.Keys){
    if(-not [IO.File]::ReadAllText((Join-Path $PSScriptRoot $name)).Contains($checks[$name])){throw "Version mismatch: $name"}
}
$builder=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Build-NativeInstaller.ps1'))
if(-not $builder.Contains("Version='$version'")){throw 'Installer result version differs'}
$update=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Update-NativeIme.ps1'))
if(-not $update.Contains("Updated to Meltype Native Google $version.")){throw 'Update completion message version differs'}
$online=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Check-NativeRelease.ps1'))
if(-not $online.Contains("Get-NativeLatestRelease '$version'")){throw 'Online update current version differs'}
Write-Output "PASS: Native version $version matches GUI, registration, installer and update message"
