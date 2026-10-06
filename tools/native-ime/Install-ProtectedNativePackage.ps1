param([string]$Stage,[Parameter(Mandatory)][string]$Destination,[Parameter(Mandatory)][string]$UserSid,[Parameter(Mandatory)][string]$ResultFile,[string]$ManifestHash,[string]$PreviousPackage,[ValidateSet('User','Machine')][string]$PreviousRegistration='User',[string]$PreviousDllHash,[string]$PreviousControlHash,[switch]$RestoreOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
. (Join-Path $PSScriptRoot 'NativeProtectedPackage.ps1')
$attempted=$false;$restored=$false
function Restore-Registration {
    $removeFailed=$false
    if(Test-Path -LiteralPath (Join-Path $Destination 'native-ime-control.exe')) {
        & (Join-Path $Destination 'native-ime-control.exe') --unregister-machine (Join-Path $Destination 'MeltypeNative64.dll')
        $removeFailed=$LASTEXITCODE -ne 0
    }
    if($PreviousPackage) {
        if((Get-NativeFileSha256 (Join-Path $PreviousPackage 'MeltypeNative64.dll')) -ne $PreviousDllHash -or (Get-NativeFileSha256 (Join-Path $PreviousPackage 'native-ime-control.exe')) -ne $PreviousControlHash){throw 'Previous registration payload changed.'}
        $mode=if($PreviousRegistration -eq 'Machine'){'--register-machine'}else{'--register'}
        & (Join-Path $PreviousPackage 'native-ime-control.exe') $mode (Join-Path $PreviousPackage 'MeltypeNative64.dll')
        if($LASTEXITCODE -ne 0){throw 'Previous IME registration could not be restored.'}
    }
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}\InprocServer32')
    try {$current=if($key){$key.GetValue('')}else{$null}}finally{if($key){$key.Dispose()}}
    $expected=if($PreviousPackage -and $PreviousRegistration -eq 'Machine'){Join-Path $PreviousPackage 'MeltypeNative64.dll'}else{$null}
    if($current -ne $expected){throw 'Previous machine COM registration was not restored.'}
    if($removeFailed -and -not $PreviousPackage){throw 'Protected profile could not be removed completely.'}
}
try {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($identity.User.Value -ne $UserSid -or -not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use the installing account with administrator privileges.'}
    $Destination=Assert-NativeProtectedDestination $Destination
    if($RestoreOnly) {
        if(Test-Path -LiteralPath $Destination){Assert-NativeProtectedAcl $Destination}
        $attempted=$true;Restore-Registration;$restored=$true
    }else {
        $manifestBytes=[IO.File]::ReadAllBytes((Join-Path $Stage 'manifest.json'))
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$capturedHash=[BitConverter]::ToString($sha.ComputeHash($manifestBytes)).Replace('-','')}finally{$sha.Dispose()}
        if($capturedHash -ne $ManifestHash){throw 'Manifest changed before elevation.'}
        $manifest=Assert-NativeUpdatePackage $Stage ([Text.Encoding]::UTF8.GetString($manifestBytes).TrimStart([char]0xfeff))
        foreach($name in @('MeltypeNative64.dll','native-ime-control.exe')){if($name -notin $manifest.Files.Name){throw 'Native registration payload is missing.'}}
        if(Test-Path -LiteralPath $Destination){throw 'Protected destination already exists.'}
        $base=Get-NativeProtectedBase
        if(Test-Path -LiteralPath $base){Assert-NativeProtectedAcl $base}
        else{New-Item -ItemType Directory -Path $base|Out-Null;Set-Acl -LiteralPath $base -AclObject (New-NativeProtectedAcl)}
        New-Item -ItemType Directory -Path $Destination|Out-Null
        Set-Acl -LiteralPath $Destination -AclObject (New-NativeProtectedAcl)
        foreach($file in $manifest.Files) {
            $target=Join-Path $Destination $file.Name
            Copy-Item -LiteralPath (Join-Path $Stage $file.Name) -Destination $target
            Set-Acl -LiteralPath $target -AclObject (New-NativeProtectedAcl -File)
            if((Get-NativeFileSha256 $target) -ne $file.SHA256){throw 'Protected copy checksum mismatch.'}
            Assert-NativeProtectedAcl $target
        }
        [IO.File]::WriteAllBytes((Join-Path $Destination 'manifest.json'),$manifestBytes)
        Set-Acl -LiteralPath (Join-Path $Destination 'manifest.json') -AclObject (New-NativeProtectedAcl -File)
        $attempted=$true
        & (Join-Path $Destination 'native-ime-control.exe') --register-machine (Join-Path $Destination 'MeltypeNative64.dll')
        if($LASTEXITCODE -ne 0){throw 'Windows rejected protected IME registration.'}
    }
    @{Success=$true;PackageRoot=$Destination;Restored=$restored}|ConvertTo-Json|Set-Content -LiteralPath $ResultFile -Encoding utf8
}catch {
    $failure=$_.Exception.Message
    if($attempted -and -not $RestoreOnly){try{Restore-Registration;$restored=$true}catch{$failure+=' Rollback failed: '+$_.Exception.Message}}
    @{Success=$false;Error=$failure;Restored=$restored;RegistrationAttempted=$attempted}|ConvertTo-Json|Set-Content -LiteralPath $ResultFile -Encoding utf8
    throw $failure
}
