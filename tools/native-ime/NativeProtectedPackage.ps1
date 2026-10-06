function Get-NativeProtectedBase {
    return Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'MeltypeNativeGoogle'
}
function Assert-NativeProtectedDestination([string]$Destination) {
    $base=[IO.Path]::GetFullPath((Get-NativeProtectedBase)).TrimEnd('\')
    $target=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if((Split-Path $target -Parent) -ne $base -or (Split-Path $target -Leaf) -notmatch '^package-[0-9a-f]{32}$'){throw 'Unexpected protected package destination.'}
    foreach($path in @($base,$target)) {
        if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Protected directory must not be a junction or symbolic link.'}
    }
    return $target
}
function New-NativeProtectedAcl([switch]$File) {
    $acl=if($File){[Security.AccessControl.FileSecurity]::new()}else{[Security.AccessControl.DirectorySecurity]::new()}
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    $inherit=if($File){[Security.AccessControl.InheritanceFlags]::None}else{[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}
    foreach($sid in @('S-1-5-18','S-1-5-32-544','S-1-5-32-545','S-1-15-2-1')) {
        $rights=if($sid -in @('S-1-5-18','S-1-5-32-544')){[Security.AccessControl.FileSystemRights]::FullControl}else{[Security.AccessControl.FileSystemRights]::ReadAndExecute}
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),$rights,$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    }
    return $acl
}
function Assert-NativeProtectedAcl([string]$Path) {
    $acl=Get-Acl -LiteralPath $Path
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Protected package has an untrusted owner.'}
    $write=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') -and ($rule.FileSystemRights -band $write)){throw 'Protected package is writable by a non-administrator.'}
    }
}
function Invoke-NativeProtectedDeploy([string]$Stage,[string]$Destination,[string]$Runtime,[string]$ResultFile,[string]$PreviousPackage,[string]$PreviousRegistration,[switch]$RestoreOnly) {
    $arguments=@('-NoProfile','-File',(ConvertTo-NativeGuiArgument (Join-Path $PSScriptRoot 'Install-ProtectedNativePackage.ps1')),'-Destination',(ConvertTo-NativeGuiArgument $Destination),'-UserSid',([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),'-ResultFile',(ConvertTo-NativeGuiArgument $ResultFile))
    if($RestoreOnly){$arguments+='-RestoreOnly'}else{$arguments+=@('-Stage',(ConvertTo-NativeGuiArgument $Stage),'-ManifestHash',(Get-NativeFileSha256 (Join-Path $Stage 'manifest.json')))}
    if($PreviousPackage){$arguments+=@('-PreviousPackage',(ConvertTo-NativeGuiArgument $PreviousPackage),'-PreviousRegistration',$(if($PreviousRegistration -eq 'Machine'){'Machine'}else{'User'}),'-PreviousDllHash',(Get-NativeFileSha256 (Join-Path $PreviousPackage 'MeltypeNative64.dll')),'-PreviousControlHash',(Get-NativeFileSha256 (Join-Path $PreviousPackage 'native-ime-control.exe')))}
    $process=Start-Process -FilePath $Runtime -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -Wait
    try {
        if(-not(Test-Path -LiteralPath $ResultFile)){throw 'Protected package operation did not return a result.'}
        $result=Get-Content -LiteralPath $ResultFile -Raw|ConvertFrom-Json
        if($null -eq $result.Success){throw 'Protected package operation returned an invalid result.'}
    } catch {
        $failure=[InvalidOperationException]::new($_.Exception.Message)
        $failure.Data['NativeRegistrationMayHaveChanged']=$true
        throw $failure
    }
    if($process.ExitCode -ne 0 -or -not $result.Success){
        $failure=[InvalidOperationException]::new('Protected package operation failed: '+$result.Error)
        $failure.Data['NativeRegistrationMayHaveChanged']=[bool]($result.RegistrationAttempted -and -not $result.Restored)
        throw $failure
    }
    return $result
}
