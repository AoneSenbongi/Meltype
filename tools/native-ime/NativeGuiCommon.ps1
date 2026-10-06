function Get-NativeGuiContext([string]$SourceRoot) {
    $key = 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}\InprocServer32'
    $installed = Test-Path -LiteralPath $key
    $root = $SourceRoot
    $state = $null
    if ($installed) {
        $dll = (Get-Item -LiteralPath $key).GetValue('')
        if ([IO.Path]::GetFileName($dll) -ne 'MeltypeNative64.dll') { throw 'Unexpected registered IME.' }
        $root = Split-Path (Split-Path (Split-Path $dll -Parent) -Parent) -Parent
        $state = Get-Content (Join-Path $root 'experimental-build/native-ime-install.json') -Raw | ConvertFrom-Json
        if ($state.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or $state.PackageRoot -ne (Split-Path $dll -Parent)) { throw 'Installed IME does not match this Windows account.' }
    }
    $scripts = Join-Path $root 'tools/native-ime'
    if ($state -and -not $state.Portable -and (Test-Path (Join-Path $root 'investigation/Start-NativeIme.ps1'))) { $scripts = Join-Path $root 'investigation' }
    return @{ Installed = $installed; Root = $root; State = $state; Scripts = $scripts }
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
function Assert-NativeUpdatePackage([string]$Stage) {
    $manifest = Get-Content (Join-Path $Stage 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($name in @('Meltype.Core.dll','Meltype.dll','NativeBroker.cs')) {
        if ($name -notin $manifest.Files.Name) { throw ('Required update file is missing: '+$name) }
    }
    foreach ($file in $manifest.Files) {
        if ($file.Name -ne [IO.Path]::GetFileName($file.Name)) { throw 'Invalid package filename.' }
        if ((Get-NativeFileSha256 (Join-Path $Stage $file.Name)) -ne $file.SHA256) { throw ('Package checksum mismatch: '+$file.Name) }
    }
    return $manifest
}
