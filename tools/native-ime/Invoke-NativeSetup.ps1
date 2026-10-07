param([ValidateSet('Install','Uninstall')][string]$Mode='Install',
    [ValidateSet('Install','Uninstall')][string]$ElevatedAction,
    [string]$ExpectedSid,[string]$ResultFile,[switch]$NoDesktop,[switch]$NoDialog)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
. (Join-Path $PSScriptRoot 'NativeInstaller.ps1')
if($ElevatedAction) {
    try {
        Assert-NativeInstallerUser $ExpectedSid
        $script=if($ElevatedAction -eq 'Install'){'Install-NativeIme.ps1'}else{'Uninstall-InstalledNativeIme.ps1'}
        $output=& (Join-Path $PSScriptRoot $script)|Out-String
        @{Success=$true;Output=$output}|ConvertTo-Json|Set-Content -LiteralPath $ResultFile -Encoding UTF8
        exit 0
    } catch {
        @{Success=$false;Output=($_|Out-String)}|ConvertTo-Json|Set-Content -LiteralPath $ResultFile -Encoding UTF8
        exit 1
    }
}
try {
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'セットアップは「管理者として実行」を使わず、通常のダブルクリックで開いてください。'}
    Invoke-NativeInstaller $root $Mode (-not $NoDesktop)
    exit 0
} catch {
    $log=Join-Path $root ('experimental-build/setup-error-'+[Guid]::NewGuid().ToString('N')+'.txt')
    $details=$_|Out-String
    $message=Get-NativeGuiErrorMessage $details
    if($details -match 'セットアップは|管理者確認には|IMEの登録'){ $message=$_.Exception.Message }
    try {Set-Content -LiteralPath $log $details -Encoding UTF8;$message+="`n`n詳しい情報: $log"}catch{}
    if(-not $NoDialog){Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show($message,'Meltypeのセットアップ','OK','Error')|Out-Null}
    exit 1
}
