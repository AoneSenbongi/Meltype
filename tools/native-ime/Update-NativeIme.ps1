$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$context = Get-NativeGuiContext $workspace
if (-not $context.Installed) { throw 'Install the native IME first.' }
$stage = Join-Path $workspace 'experimental-build/native-ime-package'
$manifest = Assert-NativeUpdatePackage $stage
$package = $context.State.PackageRoot
$launcher = Join-Path $workspace 'Meltype-Settings.exe'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Management launcher is missing from package.' }
$stateFile = Join-Path $context.Root 'experimental-build/native-ime-install.json'
$previousState = Get-Content -LiteralPath $stateFile -Raw
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
    foreach ($name in $updates) { Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $package $name) -Force }
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
    $context.State | Add-Member NoteProperty BaseVersion '1.0.1' -Force
    $context.State | ConvertTo-Json | Set-Content (Join-Path $context.Root 'experimental-build/native-ime-install.json') -Encoding UTF8
    if ($autoEnabled) { & (Join-Path $PSScriptRoot 'Set-InstalledNativeAutoStart.ps1') }
    & (Join-Path $PSScriptRoot 'Set-NativeShortcuts.ps1') -WorkspaceRoot $context.Root
    & (Join-Path $context.Scripts 'Start-NativeIme.ps1')
    Write-Output 'Updated to Meltype 1.0.1. Google dictionaries and learning data were preserved.'
} catch {
    $failure = $_
    foreach ($name in $updates) { Copy-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $package $name) -Force }
    Set-Content -LiteralPath $stateFile -Value $previousState -Encoding UTF8
    & (Join-Path $context.Scripts 'Start-NativeIme.ps1')
    throw $failure
}
