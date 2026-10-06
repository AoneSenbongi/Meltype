$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$runtime=(Get-Content (Join-Path $workspace 'experimental-build/runtime-path.txt') -Raw).Trim()
$fixture=Join-Path $workspace ('experimental-build/protected-update-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$actualCommon=(Join-Path $PSScriptRoot 'NativeGuiCommon.ps1').Replace("'","''")
$actualProtected=(Join-Path $PSScriptRoot 'NativeProtectedPackage.ps1').Replace("'","''")
$commonStub=@'
. '__COMMON__'
function Get-FixtureCaseRoot {Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent}
function Write-FixtureEvent([string]$Event){Add-Content -LiteralPath (Join-Path (Get-FixtureCaseRoot) 'events.log') -Value $Event}
function Get-NativeGuiContext([string]$SourceRoot){Get-Content (Join-Path $SourceRoot 'context.json') -Raw|ConvertFrom-Json}
function Get-ItemProperty {
 [CmdletBinding()]param([string]$Path,[string]$LiteralPath,[string]$Name)
 $target=if($LiteralPath){$LiteralPath}else{$Path}
 if($target -eq 'HKCU:\Software\MeltypeNativeGoogle') {
  $value=(Get-Content (Join-Path (Get-FixtureCaseRoot) 'tag.txt') -Raw).Trim()
  if($value){return [pscustomobject]@{InstallRoot=$value}};return $null
 }
 if($target -like '*\CurrentVersion\Run'){return [pscustomobject]@{MeltypeNativeGoogle='fixture-autostart'}}
 throw 'Fixture encountered an unexpected registry read.'
}
function New-Item {
 [CmdletBinding()]param([string]$Path,[string]$ItemType,[switch]$Force)
 if($Path -eq 'HKCU:\Software\MeltypeNativeGoogle'){return [pscustomobject]@{}}
 Microsoft.PowerShell.Management\New-Item @PSBoundParameters
}
function New-ItemProperty {
 [CmdletBinding()]param([string]$LiteralPath,[string]$Name,[string]$Value,[string]$PropertyType,[switch]$Force)
 if($LiteralPath -ne 'HKCU:\Software\MeltypeNativeGoogle' -or $Name -ne 'InstallRoot'){throw 'Unexpected fixture registry write.'}
 Set-Content -LiteralPath (Join-Path (Get-FixtureCaseRoot) 'tag.txt') -Value $Value
 Write-FixtureEvent 'tag-set'
}
function Remove-ItemProperty {
 [CmdletBinding()]param([string]$LiteralPath,[string]$Name)
 if($LiteralPath -ne 'HKCU:\Software\MeltypeNativeGoogle' -or $Name -ne 'InstallRoot'){throw 'Unexpected fixture registry removal.'}
 Set-Content -LiteralPath (Join-Path (Get-FixtureCaseRoot) 'tag.txt') -Value ''
 Write-FixtureEvent 'tag-removed'
}
function Test-Path {
 [CmdletBinding()]param([string]$LiteralPath,[string]$Path)
 $target=if($LiteralPath){$LiteralPath}else{$Path}
 if($target -eq 'HKCU:\Software\MeltypeNativeGoogle'){return $true}
 Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
'@.Replace('__COMMON__',$actualCommon)
$protectedStub=@'
. '__PROTECTED__'
function Invoke-NativeProtectedDeploy {
 param([string]$Stage,[string]$Destination,[string]$Runtime,[string]$ResultFile,[string]$PreviousPackage,[string]$PreviousRegistration,[switch]$RestoreOnly)
 $caseRoot=Get-FixtureCaseRoot
 if($RestoreOnly){Write-FixtureEvent ('restore-'+$PreviousRegistration);return [pscustomobject]@{Success=$true}}
 Write-FixtureEvent 'deploy'
 $mode=(Get-Content (Join-Path $caseRoot 'mode.txt') -Raw).Trim()
 if($mode -eq 'Cancel'){throw 'fixture cancellation before registration'}
 if($mode -eq 'RecoveryNeeded') {
  $failure=[InvalidOperationException]::new('fixture registration failure requiring restoration')
  $failure.Data['NativeRegistrationMayHaveChanged']=$true
  throw $failure
 }
 return [pscustomobject]@{Success=$true;PackageRoot=$Destination}
}
'@.Replace('__PROTECTED__',$actualProtected)
$eventScript=@'
param([switch]$NoStartOriginal)
$caseRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Add-Content (Join-Path $caseRoot 'events.log') '__EVENT__'
'@
foreach($mode in @('Cancel','StartupFailure','RecoveryNeeded')) {
 $caseRoot=Join-Path $fixture $mode
 $source=Join-Path $caseRoot 'source';$installed=Join-Path $caseRoot 'installed'
 $sourceScripts=Join-Path $source 'tools/native-ime';$installedScripts=Join-Path $installed 'tools/native-ime'
 $stage=Join-Path $source 'experimental-build/native-ime-package';$package=Join-Path $installed 'experimental-build/old'
 foreach($path in @($sourceScripts,$installedScripts,$stage,$package)){New-Item -ItemType Directory -Path $path -Force|Out-Null}
 Set-Content (Join-Path $caseRoot 'mode.txt') $mode
 Set-Content (Join-Path $caseRoot 'tag.txt') ''
 $state=@{PackageRoot=$package;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;NativeRegistration='User';Portable=$true}
 $stateFile=Join-Path $installed 'experimental-build/native-ime-install.json'
 $state|ConvertTo-Json|Set-Content $stateFile
 $context=@{Installed=$true;Root=$installed;Scripts=$installedScripts;State=$state}
 $context|ConvertTo-Json -Depth 4|Set-Content (Join-Path $source 'context.json')
 Set-Content (Join-Path $installed 'experimental-build/runtime-path.txt') $runtime
 $files=foreach($name in @('Meltype.Core.dll','Meltype.dll','NativeBroker.cs','MeltypeNative64.dll','native-ime-control.exe')) {
  Set-Content (Join-Path $stage $name) ('new '+$name)
  Set-Content (Join-Path $package $name) ('old '+$name)
  @{Name=$name;SHA256=(Get-FileHash (Join-Path $stage $name)).Hash}
 }
 @{Files=@($files);NativeRegistration='Machine'}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $stage 'manifest.json')
 Set-Content (Join-Path $source 'Meltype-Settings.exe') 'new launcher'
 Set-Content (Join-Path $installed 'Meltype-Settings.exe') 'old launcher'
 Copy-Item (Join-Path $PSScriptRoot 'Update-NativeIme.ps1') (Join-Path $sourceScripts 'Update-NativeIme.ps1')
 Set-Content (Join-Path $sourceScripts 'NativeGuiCommon.ps1') $commonStub
 Set-Content (Join-Path $sourceScripts 'NativeProtectedPackage.ps1') $protectedStub
 Set-Content (Join-Path $sourceScripts 'Backup-State.ps1') 'Write-Output "fixture backup"'
 Set-Content (Join-Path $sourceScripts 'Set-InstalledNativeAutoStart.ps1') ($eventScript.Replace('__EVENT__','auto-restored'))
 Set-Content (Join-Path $sourceScripts 'Set-NativeShortcuts.ps1') 'param([string]$WorkspaceRoot)'
 Set-Content (Join-Path $sourceScripts 'Start-NativeIme.ps1') ($eventScript.Replace('__EVENT__','new-start')+"`nthrow 'fixture startup failure'")
 Set-Content (Join-Path $installedScripts 'Start-NativeIme.ps1') ($eventScript.Replace('__EVENT__','old-start'))
 Set-Content (Join-Path $installedScripts 'Stop-NativeIme.ps1') ($eventScript.Replace('__EVENT__','old-stop'))
 Set-Content (Join-Path $installedScripts 'NativeGuiCommon.ps1') '# old management fixture'
 $oldHash=(Get-FileHash (Join-Path $package 'MeltypeNative64.dll')).Hash
 $failed=$false
 try{& (Join-Path $sourceScripts 'Update-NativeIme.ps1')}catch{$failed=$true;Write-Output ('Injected failure: '+$_.Exception.Message)}
 if(-not $failed){throw 'Injected update failure was ignored'}
 $restored=Get-Content $stateFile -Raw|ConvertFrom-Json
 if($restored.PackageRoot -ne $package -or $restored.NativeRegistration -ne 'User'){throw 'Old installation state was not restored'}
 if((Get-FileHash (Join-Path $package 'MeltypeNative64.dll')).Hash -ne $oldHash){throw 'Running old DLL was overwritten'}
 if((Get-Content (Join-Path $caseRoot 'tag.txt') -Raw).Trim()){throw 'Failed migration left a new install-root pointer'}
 $events=Get-Content (Join-Path $caseRoot 'events.log')
 if($events -notcontains 'old-start' -or $events -notcontains 'auto-restored'){throw 'Old service/startup was not restored'}
 if($mode -eq 'Cancel' -and @($events|Where-Object {$_ -like 'restore-*'}).Count){throw 'Cancelled operation unnecessarily changes registration'}
 if($mode -ne 'Cancel' -and $events -notcontains 'restore-User'){throw 'Changed or uncertain registration was not restored with the old scope'}
 if($mode -eq 'StartupFailure' -and (Get-Content (Join-Path $installed 'Meltype-Settings.exe') -Raw).Trim() -ne 'old launcher'){throw 'Old launcher was not restored'}
 Write-Output ('PASS: real update orchestration rollback: '+$mode+'. Fixture dependencies only; no registry, IME, or administrator changes.')
}
