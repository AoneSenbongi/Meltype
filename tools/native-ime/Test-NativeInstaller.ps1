$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeInstaller.ps1')
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture=Join-Path $root ('experimental-build/installer-test-'+[Guid]::NewGuid().ToString('N'))
$scripts=Join-Path $fixture 'tools/native-ime'
New-Item -ItemType Directory -Force $scripts|Out-Null
$global:installerTestEvents=[Collections.Generic.List[string]]::new()
$script:installed=$false
$script:failure=$false
function Get-NativeGuiContext($Root){@{Installed=$script:installed;Root=$Root;Scripts=$scripts}}
function Get-NativeGoogleTool{'fixture-google-tool'}
function Get-NativePanelShortcutRoot{'C:\fixture-old-panel'}
function Restart-NativeControlPanel($NewRoot,$PreviousRoot,$PreviousPanelRoot){if($PreviousPanelRoot -ne 'C:\fixture-old-panel'){throw 'Old shortcut root was lost'};$global:installerTestEvents.Add('RestartPanel')}
function Assert-NativeUpdatePackage($Root){$global:installerTestEvents.Add('Validate');@{}}
function Invoke-NativeInstallerElevation($Root,$Action){
    $global:installerTestEvents.Add($Action)
    if($script:failure){throw 'fixture cancellation'}
    $script:installed=$Action -eq 'Install'
}
Set-Content (Join-Path $scripts 'Update-NativeIme.ps1') '$global:installerTestEvents.Add("Update")'
Set-Content (Join-Path $scripts 'Start-NativeIme.ps1') '$global:installerTestEvents.Add("Start")'
Set-Content (Join-Path $scripts 'Set-NativeShortcuts.ps1') 'param($WorkspaceRoot,[switch]$Remove,[switch]$NoDesktop);$global:installerTestEvents.Add("Links:$Remove`:$NoDesktop")'
function Check-Events([string]$Expected){if(($global:installerTestEvents -join ',') -ne $Expected){throw ('Unexpected operations: '+($global:installerTestEvents -join ','))};$global:installerTestEvents.Clear()}
try {
    Invoke-NativeInstaller $fixture 'Install' $true
    Check-Events 'Validate,Install,Links:False:False,Start,RestartPanel'
    Invoke-NativeInstaller $fixture 'Install' $false
    Check-Events 'Validate,Update,Links:False:True,Start,RestartPanel'
    $script:failure=$true
    $rejected=$false
    try{Invoke-NativeInstaller $fixture 'Uninstall' $true}catch{$rejected=$true}
    if(-not $rejected){throw 'Failed unregister was accepted'}
    Check-Events 'Uninstall'
    $script:failure=$false
    Invoke-NativeInstaller $fixture 'Uninstall' $true
    Check-Events 'Uninstall,Links:True:False'
    $script:failure=$true
    $rejected=$false
    try{Invoke-NativeInstaller $fixture 'Install' $true}catch{$rejected=$true}
    if(-not $rejected){throw 'Cancelled installation was accepted'}
    Check-Events 'Validate,Install'
    $rejected=$false
    try{Assert-NativeInstallerUser 'S-1-5-21-999-999-999-999'}catch{$rejected=$true}
    if(-not $rejected){throw 'Another Windows account was accepted'}
    $iss=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MeltypeSetup.iss'))
    if($iss -match '\[Icons\]'){throw 'Setup must preserve old shortcut until successful IME update'}
    if($iss -notmatch 'PrivilegesRequired=lowest' -or $iss -notmatch 'ArchitecturesAllowed=x64os'){throw 'Installer privileges or architecture changed'}
    if($iss -notmatch 'function InitializeUninstall' -or $iss -notmatch 'Result := Result and \(Code = 0\)'){throw 'Uninstaller must stop on unregister failure'}
    Write-Output 'PASS: new install, existing ZIP update, desktop opt-out, cancellation, uninstall failure and account isolation. No installed IME changes.'
} finally {
    foreach($file in Get-ChildItem -LiteralPath $scripts -File){Remove-Item -LiteralPath $file.FullName}
    Remove-Item -LiteralPath $scripts
    Remove-Item -LiteralPath (Join-Path $fixture 'tools')
    Remove-Item -LiteralPath $fixture
}
