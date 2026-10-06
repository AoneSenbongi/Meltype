$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
. (Join-Path $PSScriptRoot 'NativeProtectedPackage.ps1')
$base=Get-NativeProtectedBase
$valid=Join-Path $base ('package-'+[Guid]::NewGuid().ToString('N'))
if((Assert-NativeProtectedDestination $valid) -ne $valid){throw 'Valid protected destination rejected'}
foreach($invalid in @('E:\Prog\package-'+[Guid]::NewGuid().ToString('N'),(Join-Path ($base+'-other') 'package-1234'),(Join-Path $base '..\outside'))) {
 $rejected=$false;try{Assert-NativeProtectedDestination $invalid|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'Escaped protected destination accepted'}
}
$acl=New-NativeProtectedAcl
if(-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-32-544'){throw 'Protected ACL inherits permissions or has wrong owner'}
foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
 if($rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') -and ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write)){throw 'Users or app packages can modify protected payload'}
}
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture=Join-Path $root ('experimental-build/protected-package-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$stage=Join-Path $fixture 'stage';$previous=Join-Path $fixture 'previous'
foreach($folder in @($stage,$previous)){New-Item -ItemType Directory -Path $folder|Out-Null}
Set-Content (Join-Path $stage 'manifest.json') '{}'
foreach($name in @('MeltypeNative64.dll','native-ime-control.exe')){Set-Content (Join-Path $previous $name) 'old fixture payload'}
$resultFile=Join-Path $fixture 'result.json'
@{Success=$true}|ConvertTo-Json|Set-Content $resultFile
function Start-Process {
 param($FilePath,$ArgumentList,$Verb,$WindowStyle,[switch]$PassThru,[switch]$Wait)
 $script:captured=@{FilePath=$FilePath;Arguments=$ArgumentList;Verb=$Verb;Window=$WindowStyle}
 return [pscustomobject]@{ExitCode=0}
}
Invoke-NativeProtectedDeploy -Stage $stage -Destination $valid -Runtime 'fixture-pwsh.exe' -ResultFile $resultFile -PreviousPackage $previous -PreviousRegistration User|Out-Null
if($script:captured.Verb -ne 'RunAs' -or $script:captured.Window -ne 'Hidden' -or $script:captured.Arguments -notcontains '-ManifestHash' -or $script:captured.Arguments -notcontains 'User'){throw 'Deployment arguments lost elevation, immutable manifest or old scope'}
Invoke-NativeProtectedDeploy -Destination $valid -Runtime 'fixture-pwsh.exe' -ResultFile $resultFile -PreviousPackage $previous -PreviousRegistration Machine -RestoreOnly|Out-Null
if($script:captured.Arguments -notcontains '-RestoreOnly' -or $script:captured.Arguments -notcontains 'Machine'){throw 'Restoration scope is wrong'}
$unknown=$false
try {Invoke-NativeProtectedDeploy -Stage $stage -Destination $valid -Runtime 'fixture-pwsh.exe' -ResultFile (Join-Path $fixture 'missing-result.json') -PreviousPackage $previous -PreviousRegistration User|Out-Null}
catch {$unknown=[bool]$_.Exception.Data['NativeRegistrationMayHaveChanged']}
if(-not $unknown){throw 'A launched helper without a result must require registration recovery'}
# A protected DLL's parent is not the user's management/script root. Exercise the
# real context resolver with a registry view fixture; no real registration changes.
$script:fakeRoot=Join-Path $fixture 'user-install';$script:fakePackage=Join-Path $fixture 'protected-version'
New-Item -ItemType Directory -Path (Join-Path $script:fakeRoot 'experimental-build') -Force|Out-Null
New-Item -ItemType Directory -Path (Join-Path $script:fakeRoot 'investigation') -Force|Out-Null
Set-Content (Join-Path $script:fakeRoot 'investigation/Start-NativeIme.ps1') 'legacy fixture'
$state=@{UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;PackageRoot=$script:fakePackage;Portable=$false;NativeRegistration='Machine'}
$state|ConvertTo-Json|Set-Content (Join-Path $script:fakeRoot 'experimental-build/native-ime-install.json')
function Test-Path {
 [CmdletBinding()]param([string]$Path,[string]$LiteralPath)
 $target=if($LiteralPath){$LiteralPath}else{$Path}
 if($target -like 'Registry::*CLSID*'){return $target -like '*HKEY_LOCAL_MACHINE*'}
 Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
function Get-ItemProperty {
 [CmdletBinding()]param([string]$LiteralPath,[string]$Name)
 if($LiteralPath -eq 'HKCU:\Software\MeltypeNativeGoogle'){return [pscustomobject]@{InstallRoot=$script:fakeRoot}}
 Microsoft.PowerShell.Management\Get-ItemProperty @PSBoundParameters
}
function Get-Item {
 [CmdletBinding()]param([string]$LiteralPath)
 if($LiteralPath -like 'Registry::*CLSID*') {
  $item=[pscustomobject]@{}
  $item|Add-Member ScriptMethod GetValue {param($name) return Join-Path $script:fakePackage 'MeltypeNative64.dll'}
  return $item
 }
 Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
}
$context=Get-NativeGuiContext $root
if(-not $context.Installed -or $context.Root -ne $script:fakeRoot -or $context.Scripts -ne (Join-Path $script:fakeRoot 'tools/native-ime')){throw 'Machine registration did not use its user-specific management root'}
$state.PackageRoot=Join-Path $fixture 'wrong-version'
$state|ConvertTo-Json|Set-Content (Join-Path $script:fakeRoot 'experimental-build/native-ime-install.json')
$rejected=$false;try{Get-NativeGuiContext $root|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Registry and installed state mismatch was accepted'}
Write-Output 'PASS: protected path boundaries, read-only non-admin ACL, elevated deploy/restore arguments, machine registration context and mismatched-state rejection. No installed IME changes.'
