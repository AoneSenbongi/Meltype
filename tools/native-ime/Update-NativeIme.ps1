param([switch]$NoRestartPanel)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
. (Join-Path $PSScriptRoot 'NativeProtectedPackage.ps1')
$context = Get-NativeGuiContext $workspace
$previousPanelRoot = Get-NativePanelShortcutRoot
$previousVersion = $context.State.NativeVersion
if (-not $context.Installed) { throw 'Install the native IME first.' }
if (-not (Test-NativeUpdateRequired $workspace $context)) {
    Write-Output 'This release is already installed. No changes were made.'
    return
}
$stage = Join-Path $workspace 'experimental-build/native-ime-package'
$manifest = Assert-NativeUpdatePackage $stage
$package = $context.State.PackageRoot
$packageChanged = $context.State.NativeRegistration -ne 'Machine'
foreach($file in $manifest.Files) {
    $installed=Join-Path $package $file.Name
    if(-not(Test-Path -LiteralPath $installed) -or (Get-NativeFileSha256 $installed) -ne $file.SHA256){$packageChanged=$true}
}
$updatedPackage = $package
$registrationChanged = $false
$launcher = Join-Path $workspace 'Meltype-Settings.exe'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Management launcher is missing from package.' }
$stateFile = Join-Path $context.Root 'experimental-build/native-ime-install.json'
$previousState = Get-Content -LiteralPath $stateFile -Raw
$locationKey='HKCU:\Software\MeltypeNativeGoogle'
$previousLocation=Get-ItemProperty -LiteralPath $locationKey -Name InstallRoot -ErrorAction SilentlyContinue
$runProperties = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$autoEnabled = $runProperties -and $runProperties.PSObject.Properties['MeltypeNativeGoogle']
if ($package -eq $stage) { throw 'Cannot update directly from installed files.' }
$runtimeFile = Join-Path $context.Root 'experimental-build/runtime-path.txt'
$runtime = (Get-Content -LiteralPath $runtimeFile -Raw).Trim()
& $runtime -NoProfile -File (Join-Path $PSScriptRoot 'Backup-State.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Backup failed. Update stopped.' }
$backup = Join-Path $context.Root ('backups/version-update-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$updates = @('Meltype.Core.dll','Meltype.dll','NativeBroker.cs')
foreach ($name in $updates) { Copy-Item -LiteralPath (Join-Path $package $name) -Destination (Join-Path $backup $name) }
& (Join-Path $context.Scripts 'Stop-NativeIme.ps1') -NoStartOriginal
$pidFile = Join-Path $context.Root 'experimental-build/native-broker.pid'
if (Test-Path -LiteralPath $pidFile) {
    $brokerId = [int](Get-Content -LiteralPath $pidFile -Raw)
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$brokerId"
    if ($process -and $process.CommandLine -like '*Host-NativeBroker.ps1*') {
        Wait-Process -Id $brokerId -Timeout 30 -ErrorAction SilentlyContinue
        $remaining = Get-CimInstance Win32_Process -Filter "ProcessId=$brokerId"
        if ($remaining -and $remaining.CommandLine -like '*Host-NativeBroker.ps1*') { throw 'Native broker did not stop. Installed files were kept.' }
    }
}
try {
    if ($packageChanged) {
        $updatedPackage = Join-Path (Get-NativeProtectedBase) ('package-' + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $locationKey -Force|Out-Null
        New-ItemProperty -LiteralPath $locationKey -Name InstallRoot -Value $context.Root -PropertyType String -Force|Out-Null
        $deployResult=Join-Path $backup 'protected-deploy-result.json'
        Invoke-NativeProtectedDeploy -Stage $stage -Destination $updatedPackage -Runtime $runtime -ResultFile $deployResult -PreviousPackage $package -PreviousRegistration $context.State.NativeRegistration|Out-Null
        $registrationChanged = $true
        $context.State.PackageRoot = $updatedPackage
        $context.State|Add-Member NoteProperty NativeRegistration 'Machine' -Force
    }
    $scripts = Join-Path $context.Root 'tools/native-ime'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
        $target = Join-Path $scripts $file.Name
        if ($file.FullName -ne $target) {
            if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $backup $file.Name) }
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
    }
    $targetLauncher = Join-Path $context.Root 'Meltype-Settings.exe'
    if ($launcher -ne $targetLauncher) {
        if (Test-Path -LiteralPath $targetLauncher) { Copy-Item -LiteralPath $targetLauncher -Destination $backup }
        Copy-Item -LiteralPath $launcher -Destination $targetLauncher -Force
    }
    $context.State | Add-Member NoteProperty BaseVersion '1.1.0' -Force
    $context.State | Add-Member NoteProperty SearchPackage (Get-NativeSearchPackageName) -Force
    $context.State | Add-Member NoteProperty NativeVersion '1.0.7' -Force
    $context.State | ConvertTo-Json | Set-Content (Join-Path $context.Root 'experimental-build/native-ime-install.json') -Encoding UTF8
    if ($autoEnabled) { & (Join-Path $PSScriptRoot 'Set-InstalledNativeAutoStart.ps1') }
    & (Join-Path $PSScriptRoot 'Set-NativeShortcuts.ps1') -WorkspaceRoot $context.Root
    & (Join-Path $scripts 'Start-NativeIme.ps1')
    # Shortcuts reopen the installed root. Its update source must now be this release,
    # rather than the old extracted payload that would offer a downgrade.
    Sync-NativeInstalledUpdateSource $workspace $context.Root
    Write-Output 'Updated to Meltype Native Google 1.0.7. Google dictionaries and learning data were preserved. Reopen input applications to load the new native DLL.'
} catch {
    $failure = $_
    if($failure.Exception.Data['NativeRegistrationMayHaveChanged']){$registrationChanged=$true}
    if ($registrationChanged) {
        $oldState=$previousState|ConvertFrom-Json
        Invoke-NativeProtectedDeploy -Destination $updatedPackage -Runtime $runtime -ResultFile (Join-Path $backup 'protected-restore-result.json') -PreviousPackage $package -PreviousRegistration $oldState.NativeRegistration -RestoreOnly|Out-Null
    }
    if($previousLocation -and $previousLocation.InstallRoot){New-ItemProperty -LiteralPath $locationKey -Name InstallRoot -Value $previousLocation.InstallRoot -PropertyType String -Force|Out-Null}
    elseif(Test-Path -LiteralPath $locationKey){Remove-ItemProperty -LiteralPath $locationKey -Name InstallRoot -ErrorAction SilentlyContinue}
    foreach($file in Get-ChildItem -LiteralPath $backup -Filter '*.ps1'){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $context.Root ('tools/native-ime/'+$file.Name)) -Force}
    if(Test-Path -LiteralPath (Join-Path $backup 'Meltype-Settings.exe')){Copy-Item -LiteralPath (Join-Path $backup 'Meltype-Settings.exe') -Destination (Join-Path $context.Root 'Meltype-Settings.exe') -Force}
    Set-Content -LiteralPath $stateFile -Value $previousState -Encoding UTF8
    if($autoEnabled){& (Join-Path $PSScriptRoot 'Set-InstalledNativeAutoStart.ps1')}
    & (Join-Path $context.Scripts 'Start-NativeIme.ps1')
    throw $failure
}
if(-not $NoRestartPanel){Restart-NativeControlPanel $workspace $context.Root $previousPanelRoot $previousVersion}
