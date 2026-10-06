$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $workspace "backups/$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$profileRoots = @(
    @{ Name = 'Google'; Path = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData/LocalLow/Google/Google Japanese Input' },
    @{ Name = 'Meltype'; Path = Join-Path $env:LOCALAPPDATA 'Meltype' }
)
$manifest = [System.Collections.Generic.List[object]]::new()
function Read-SharedBytes([string]$path) {
    $stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    $memory = [IO.MemoryStream]::new()
    try { $stream.CopyTo($memory); return ,$memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
}
foreach ($profile in $profileRoots) {
    $targetDir = Join-Path $backupDir $profile.Name
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $profile.Path)) {
        $manifest.Add(@{ Profile = $profile.Name; Source = $profile.Path; Existed = $false })
        continue
    }
    $files = Get-ChildItem -LiteralPath $profile.Path -File -Recurse -Force | Where-Object {
        if ($profile.Name -eq 'Google') { $_.DirectoryName -eq $profile.Path -and $_.Extension -eq '.db' }
        else { $_.Extension -notin @('.lock','.ipc','.log') }
    }
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($profile.Path, $file.FullName)
        $target = Join-Path $targetDir $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        $verified = $false
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            $bytes = Read-SharedBytes $file.FullName
            $before = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
            [IO.File]::WriteAllBytes($target, $bytes)
            $copyHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            $after = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData((Read-SharedBytes $file.FullName)))
            if ($before -eq $copyHash -and $copyHash -eq $after) { $verified = $true; break }
        }
        if (-not $verified) { throw "Could not obtain stable backup: $relative" }
        $manifest.Add(@{ Profile = $profile.Name; Source = $file.FullName; Backup = $target; SHA256 = $copyHash; Existed = $true })
    }
}
foreach ($registryPath in @('HKCU\Software\Google\Google Japanese Input','HKCU\Keyboard Layout')) {
    $label = if ($registryPath -like '*Google*') { 'google-registry' } else { 'keyboard-layout' }
    & reg.exe export $registryPath (Join-Path $backupDir "$label.reg") /y 2>$null | Out-Null
    if ($LASTEXITCODE -notin @(0,1)) { throw "Registry backup failed: $label" }
}
$snapshotDir = Join-Path $backupDir 'source'
New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
$sourceRoot = $workspace
$sourceCommit = $null
$changed = @()
if ((Test-Path (Join-Path $sourceRoot '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $sourceCommit = (& git -C $sourceRoot rev-parse HEAD)
    $changed = @(& git -C $sourceRoot diff --name-only) + @(& git -C $sourceRoot ls-files --others --exclude-standard)
} elseif (Test-Path (Join-Path $sourceRoot 'SOURCE_VERSION.txt')) { $sourceCommit = (Get-Content (Join-Path $sourceRoot 'SOURCE_VERSION.txt') -Raw).Trim() }
foreach ($relative in $changed | Select-Object -Unique) {
    $source = Join-Path $sourceRoot $relative
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $target = Join-Path $snapshotDir $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
}
@{ Created = (Get-Date).ToString('o'); SourceCommit = $sourceCommit; Files = $manifest } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupDir 'manifest.json') -Encoding utf8
$backupDir
