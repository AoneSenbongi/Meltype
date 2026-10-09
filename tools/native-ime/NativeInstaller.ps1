function Assert-NativeInstallerUser([string]$ExpectedSid) {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -ne $ExpectedSid) { throw '管理者確認には、セットアップを開始したWindowsアカウントを使用してください。' }
}

function Invoke-NativeInstallerElevation([string]$Root,[string]$Action) {
    $result=Join-Path $Root ('experimental-build/setup-result-'+[Guid]::NewGuid().ToString('N')+'.json')
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $hostExe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $arguments='-NoProfile -ExecutionPolicy Bypass -File '+(ConvertTo-NativeGuiArgument (Join-Path $Root 'tools/native-ime/Invoke-NativeSetup.ps1'))+
        ' -ElevatedAction '+$Action+' -ExpectedSid '+$sid+' -ResultFile '+(ConvertTo-NativeGuiArgument $result)
    $process=Start-Process $hostExe -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    try {
        if (-not (Test-Path -LiteralPath $result)) { throw ('Protected package operation did not return a result. Exit code: '+$process.ExitCode) }
        $completed=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json
        if (-not $completed.Success -or $process.ExitCode -ne 0) { throw $completed.Output }
    } finally {
        $process.Dispose()
        if(Test-Path -LiteralPath $result){Remove-Item -LiteralPath $result}
    }
}

function Invoke-NativeInstaller([string]$Root,[string]$Mode,[bool]$Desktop) {
    $context=Get-NativeGuiContext $Root
    if($Mode -eq 'Uninstall') {
        if($context.Installed){Invoke-NativeInstallerElevation $Root 'Uninstall'}
        & (Join-Path $Root 'tools/native-ime/Set-NativeShortcuts.ps1') -WorkspaceRoot $Root -Remove
        return
    }
    Get-NativeGoogleTool|Out-Null
    $previousPanelRoot=Get-NativePanelShortcutRoot
    Assert-NativeUpdatePackage (Join-Path $Root 'experimental-build/native-ime-package')|Out-Null
    if($context.Installed) {
        & (Join-Path $Root 'tools/native-ime/Update-NativeIme.ps1') -NoRestartPanel
    } else {
        Invoke-NativeInstallerElevation $Root 'Install'
    }
    $context=Get-NativeGuiContext $Root
    if(-not $context.Installed){throw 'IMEの登録を確認できませんでした。管理画面からインストールをやり直してください。'}
    & (Join-Path $Root 'tools/native-ime/Set-NativeShortcuts.ps1') -WorkspaceRoot $Root -NoDesktop:(-not $Desktop)
    & (Join-Path $context.Scripts 'Start-NativeIme.ps1')
    Restart-NativeControlPanel $Root $context.Root $previousPanelRoot
}
