function Test-NativeBrokerRunning([string]$UserSid) {
    $mutex = $null
    try {
        $mutex = [Threading.Mutex]::OpenExisting(('Local\Meltype.NativeComposition.' + $UserSid + '.Mutex'))
        return $true
    } catch [Threading.WaitHandleCannotBeOpenedException] {
        return $false
    } finally { if ($mutex) { $mutex.Dispose() } }
}
function Get-NativeGuiContext([string]$SourceRoot) {
    $key = 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}\InprocServer32'
    $installed = Test-Path -LiteralPath $key
    $machine=$false
    $root = $SourceRoot
    $state = $null
    if(-not $installed) {
        $key='Registry::HKEY_LOCAL_MACHINE\Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}\InprocServer32'
        $location=Get-ItemProperty -LiteralPath 'HKCU:\Software\MeltypeNativeGoogle' -Name InstallRoot -ErrorAction SilentlyContinue
        if((Test-Path -LiteralPath $key) -and $location -and $location.InstallRoot){$installed=$true;$machine=$true;$root=$location.InstallRoot}
    }
    if ($installed) {
        $dll = (Get-Item -LiteralPath $key).GetValue('')
        if ([IO.Path]::GetFileName($dll) -ne 'MeltypeNative64.dll') { throw 'Unexpected registered IME.' }
        if(-not $machine){$root = Split-Path (Split-Path (Split-Path $dll -Parent) -Parent) -Parent}
        $state = Get-Content (Join-Path $root 'experimental-build/native-ime-install.json') -Raw | ConvertFrom-Json
        if ($state.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or $state.PackageRoot -ne (Split-Path $dll -Parent)) { throw 'Installed IME does not match this Windows account.' }
    }
    $scripts = Join-Path $root 'tools/native-ime'
    if ($state -and $state.NativeRegistration -ne 'Machine' -and -not $state.Portable -and (Test-Path (Join-Path $root 'investigation/Start-NativeIme.ps1'))) { $scripts = Join-Path $root 'investigation' }
    return @{ Installed = $installed; Root = $root; State = $state; Scripts = $scripts }
}
function Get-NativeInputPreferencesPath {
    return Join-Path $env:LOCALAPPDATA 'MeltypeNativeGoogle/input-preferences.json'
}
function Get-NativeInputPreferences {
    $path = Get-NativeInputPreferencesPath
    $result = [pscustomobject]@{ Comma='，'; Period='．'; LearningEnabled=$true }
    if (-not [IO.File]::Exists($path)) { return $result }
    try {
        $value = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        if ($value.Comma -in @('、','，',',')) { $result.Comma = $value.Comma }
        if ($value.Period -in @('。','．','.')) { $result.Period = $value.Period }
        $result.LearningEnabled = $value.LearningEnabled -is [bool] -and $value.LearningEnabled
    } catch { $result.LearningEnabled = $false }
    return $result
}
function Save-NativeInputPreferences([ValidateSet('、','，',',')][string]$Comma, [ValidateSet('。','．','.')][string]$Period, [bool]$LearningEnabled) {
    $path = Get-NativeInputPreferencesPath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
    $temp = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, (@{Comma=$Comma;Period=$Period;LearningEnabled=$LearningEnabled} | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp,$path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function Get-NativeGuiAction([string]$SourceRoot, [string]$Action) {
    $context = Get-NativeGuiContext $SourceRoot
    $sourceScripts = Join-Path $SourceRoot 'tools/native-ime'
    $scripts = $context.Scripts
    $arguments = @()
    $elevated = $false
    switch ($Action) {
        'Install' { $script = Join-Path $sourceScripts 'Install-NativeIme.ps1'; $elevated = $true }
        'Uninstall' { $script = Join-Path $sourceScripts 'Uninstall-InstalledNativeIme.ps1'; $elevated = $true }
        'Start' { $script = Join-Path $scripts 'Start-NativeIme.ps1' }
        'Stop' { $script = Join-Path $scripts 'Stop-NativeIme.ps1'; $arguments = @('-NoStartOriginal') }
        'ReleaseCheck' { $script = Join-Path $sourceScripts 'Check-NativeRelease.ps1' }
        'ReleaseInstall' { $script = Join-Path $sourceScripts 'Check-NativeRelease.ps1'; $arguments = @('-Install') }
        'Update' { $script = Join-Path $sourceScripts 'Update-NativeIme.ps1' }
        'Enable' { $script = Join-Path $sourceScripts 'Set-InstalledNativeAutoStart.ps1' }
        'Disable' { $script = Join-Path $sourceScripts 'Set-InstalledNativeAutoStart.ps1'; $arguments = @('-Disable') }
        default { throw 'Unknown management action.' }
    }
    if (-not $context.Installed -and $Action -ne 'Install') { throw 'Install the native IME first.' }
    return @{ Script = $script; Arguments = $arguments; Elevated = $elevated }
}
function ConvertTo-NativeGuiArgument([string]$Value) {
    if ($Value -match '["\r\n]') { throw 'Invalid process argument.' }
    return '"' + $Value + '"'
}
function Get-NativeGoogleTool {
    $active = Get-Process -Name GoogleIMEJaConverter -ErrorAction SilentlyContinue | Where-Object SessionId -EQ (Get-Process -Id $PID).SessionId | Select-Object -First 1
    $roots = @()
    if ($active -and $active.Path) { $roots += Split-Path $active.Path -Parent }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) { if ($base) { $roots += Join-Path $base 'Google/Google Japanese Input' } }
    foreach ($root in $roots) { $tool = Join-Path $root 'GoogleIMEJaTool.exe'; if (Test-Path -LiteralPath $tool) { return $tool } }
    throw 'Google日本語入力を先にインストールしてください。'
}
function Get-NativeFileSha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-', '') }
    finally { $hash.Dispose(); $stream.Dispose() }
}
function Test-NativeDllUpdateRequired([string]$Stage, [string]$InstalledPackage) {
    return (Get-NativeFileSha256 (Join-Path $Stage 'MeltypeNative64.dll')) -ne
        (Get-NativeFileSha256 (Join-Path $InstalledPackage 'MeltypeNative64.dll'))
}
function Test-NativeUpdateRequired([string]$SourceRoot, $Context) {
    if (-not $Context.Installed) { return $false }
    $stage = Join-Path $SourceRoot 'experimental-build/native-ime-package'
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'manifest.json'))) { return $false }
    $manifest = Assert-NativeUpdatePackage $stage
    if($manifest.NativeRegistration -eq 'Machine' -and $Context.State.NativeRegistration -ne 'Machine'){return $true}
    foreach ($file in $manifest.Files) {
        $installed = Join-Path $Context.State.PackageRoot $file.Name
        if (-not (Test-Path -LiteralPath $installed) -or (Get-NativeFileSha256 $installed) -ne $file.SHA256) { return $true }
    }
    # Compare only shipped management scripts; build and diagnostic tools are not updates.
    foreach($name in @('NativeReleaseUpdater.ps1','Check-NativeRelease.ps1')) {
        $source=Join-Path $SourceRoot ('tools/native-ime/'+$name)
        $installed=Join-Path $Context.Root ('tools/native-ime/'+$name)
        if((Test-Path -LiteralPath $source) -and (-not(Test-Path -LiteralPath $installed) -or (Get-NativeFileSha256 $source) -ne (Get-NativeFileSha256 $installed))){return $true}
    }
    foreach($name in @('NativeProtectedPackage.ps1','Install-ProtectedNativePackage.ps1')) {
        $source=Join-Path $SourceRoot ('tools/native-ime/'+$name)
        $installed=Join-Path $Context.Root ('tools/native-ime/'+$name)
        if((Test-Path -LiteralPath $source) -and (-not(Test-Path -LiteralPath $installed) -or (Get-NativeFileSha256 $source) -ne (Get-NativeFileSha256 $installed))){return $true}
    }
    foreach ($name in @('Set-NativeShortcuts.ps1','Uninstall-InstalledNativeIme.ps1','NativeGuiCommon.ps1','Host-NativeControlPanel.ps1','Open-NativeControlPanel.ps1','Invoke-NativeGuiAction.ps1','Update-NativeIme.ps1','Set-InstalledNativeAutoStart.ps1','NativeAutoStart.ps1','Set-NativeAutoStart.ps1','Install-NativeIme.ps1','Start-NativeIme.ps1','Wait-NativeBroker.ps1','Stop-NativeIme.ps1','Uninstall-NativeIme.ps1','Host-NativeBroker.ps1','Backup-State.ps1','Start-Resident.ps1','Host-Resident.ps1')) {
        $source = Join-Path $SourceRoot ('tools/native-ime/'+$name)
        if (-not (Test-Path -LiteralPath $source)) { continue }
        $installed = Join-Path $Context.Root ('tools/native-ime/'+$name)
        if (-not (Test-Path -LiteralPath $installed) -or (Get-NativeFileSha256 $source) -ne (Get-NativeFileSha256 $installed)) { return $true }
    }
    $source = Join-Path $SourceRoot 'Meltype-Settings.exe'
    $installed = Join-Path $Context.Root 'Meltype-Settings.exe'
    return (Test-Path -LiteralPath $source) -and
        (-not (Test-Path -LiteralPath $installed) -or (Get-NativeFileSha256 $source) -ne (Get-NativeFileSha256 $installed))
}
function Sync-NativeInstalledUpdateSource([string]$SourceRoot, [string]$InstalledRoot) {
    if ([IO.Path]::GetFullPath($SourceRoot).TrimEnd('\') -eq [IO.Path]::GetFullPath($InstalledRoot).TrimEnd('\')) { return }
    $stage = Join-Path $SourceRoot 'experimental-build/native-ime-package'
    $manifest = Assert-NativeUpdatePackage $stage
    $target = Join-Path $InstalledRoot 'experimental-build/native-ime-package'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($file in $manifest.Files) { Copy-Item -LiteralPath (Join-Path $stage $file.Name) -Destination (Join-Path $target $file.Name) -Force }
    Copy-Item -LiteralPath (Join-Path $stage 'manifest.json') -Destination (Join-Path $target 'manifest.json') -Force
}
function Receive-NativeGuiActionCompletion([ref]$Process, [ref]$ResultFile) {
    if (-not $Process.Value -or -not $Process.Value.HasExited) { return $null }
    # A modal dialog pumps timer events. Consume the action before returning its result.
    $completed = $Process.Value; $path = $ResultFile.Value
    $Process.Value = $null; $ResultFile.Value = $null
    $completed.Dispose()
    if (-not (Test-Path -LiteralPath $path)) {
        return @{ Success = $false; Output = '処理を完了できませんでした。管理者確認をキャンセルした場合は、再度操作してください。' }
    }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    finally { Remove-Item -LiteralPath $path }
}
function Assert-NativeUpdatePackage([string]$Stage,[string]$ManifestJson) {
    $manifest = $(if($ManifestJson){$ManifestJson}else{Get-Content (Join-Path $Stage 'manifest.json') -Raw}) | ConvertFrom-Json
    foreach ($name in @('Meltype.Core.dll','Meltype.dll','NativeBroker.cs')) {
        if ($name -notin $manifest.Files.Name) { throw ('Required update file is missing: '+$name) }
    }
    foreach ($file in $manifest.Files) {
        if ($file.Name -ne [IO.Path]::GetFileName($file.Name)) { throw 'Invalid package filename.' }
        if ((Get-NativeFileSha256 (Join-Path $Stage $file.Name)) -ne $file.SHA256) { throw ('Package checksum mismatch: '+$file.Name) }
    }
    return $manifest
}

function Get-NativeGuiErrorMessage([string]$Details) {
    if($Details -match 'NativeReleaseNetwork'){return '最新版を取得できませんでした。ネットワーク接続を確認して、もう一度「最新版を確認」を押してください。'}
    if($Details -match 'NativeReleaseInvalid'){return '更新ファイルの情報またはSHA-256を確認できないため、更新を中止しました。現在の版はそのまま使えます。'}
    if($Details -match 'NativeReleaseInstall'){return '更新が完了していません。管理画面の状態とWindowsの管理者確認を確認してください。'}
    if ($Details -match '1223|cancell?ed|キャンセル|取り消されました|取り消し|取消') {
        return '管理者確認がキャンセルされたため、処理を中止しました。変更する場合は、もう一度操作して管理者確認を許可してください。'
    }
    if ($Details -match 'Protected package operation did not return a result|Protected package operation returned an invalid result') {
        return '管理者権限で行う処理の結果を確認できませんでした。管理者確認のキャンセルや、処理の起動失敗が考えられます。画面のインストール状態を確認してから、もう一度操作してください。'
    }
    if ($Details -match 'Native broker did not become ready|broker.*ready|入力サービス.*起動') {
        return '入力サービスの起動を確認できませんでした。少し待ってから状態を確認し、停止中の場合はもう一度「起動」を押してください。'
    }
    if ($Details -match 'hash mismatch|Missing.*file|Required update file|Invalid.*package|package.*missing') {
        return '更新用のファイルが不足しているか、内容が一致しません。ReleaseのZIPを新しいフォルダーへ展開し直してから、もう一度操作してください。'
    }
    if ($Details -match 'access.*denied|UnauthorizedAccess|アクセス.*拒否') {
        return '必要なファイルへのアクセスが拒否されました。管理者確認を許可したか確認し、もう一度操作してください。'
    }
    if ($Details -match 'Google.*tool.*missing|Google.*not found') {
        return 'Google日本語入力の設定ツールが見つかりません。Google日本語入力のインストール状態を確認してください。'
    }
    return '処理を完了できませんでした。画面の状態を確認してから、もう一度操作してください。繰り返す場合は、保存したエラーの詳細を確認してください。'
}

function Get-NativePanelShortcutRoot {
    $linkPath=Join-Path ([Environment]::GetFolderPath('Programs')) 'Meltype Google日本語入力/Meltypeの管理画面.lnk'
    if(-not(Test-Path -LiteralPath $linkPath)){return $null}
    $shell=New-Object -ComObject WScript.Shell
    $link=$null
    try {
        $link=$shell.CreateShortcut($linkPath)
        if((Split-Path $link.TargetPath -Leaf) -eq 'Meltype-Settings.exe') {
            $root=Split-Path $link.TargetPath -Parent
            if(Test-Path -LiteralPath (Join-Path $root 'tools/native-ime/Host-NativeControlPanel.ps1')){return $root}
        }
    }finally{
        if($link){[Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)|Out-Null}
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)|Out-Null
    }
}
function Restart-NativeControlPanel([string]$NewRoot, [string]$PreviousRoot, [string]$PreviousPanelRoot, [string]$PreviousVersion) {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session=(Get-Process -Id $PID).SessionId
    $previousVersionRoot=if($PreviousVersion -match '^\d+\.\d+\.\d+(?:-rc\.\d+)?$'){Join-Path (Split-Path $NewRoot -Parent) $PreviousVersion}
    $paths=@($NewRoot,$PreviousRoot,$PreviousPanelRoot,$previousVersionRoot) | Where-Object { $_ } | ForEach-Object {
        [IO.Path]::GetFullPath((Join-Path $_ 'tools/native-ime/Host-NativeControlPanel.ps1'))
    }
    foreach($process in Get-CimInstance Win32_Process) {
        if($process.Name -notin @('pwsh.exe','powershell.exe') -or $process.SessionId -ne $session -or -not $process.CommandLine){continue}
        $match=[regex]::Match($process.CommandLine,'(?i)-File\s+(?:"([^"]+[/\\]Host-NativeControlPanel\.ps1)"|(\S+[/\\]Host-NativeControlPanel\.ps1))')
        if(-not $match.Success){continue}
        $path=if($match.Groups[1].Success){$match.Groups[1].Value}else{$match.Groups[2].Value}
        if([IO.Path]::GetFullPath($path) -notin $paths){continue}
        $owner=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
        if($owner.ReturnValue -ne 0 -or $owner.Sid -ne $sid){continue}
        Stop-Process -Id $process.ProcessId -ErrorAction Stop
        Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
    }
    & (Join-Path $NewRoot 'tools/native-ime/Open-NativeControlPanel.ps1')
}
