param([Parameter(Mandatory)][string]$Runtime)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Runtime = (Resolve-Path -LiteralPath $Runtime).Path
$runtimeRoot = Split-Path $Runtime -Parent
$build = Join-Path $workspace 'experimental-build'
$package = Join-Path $build 'native-ime-package'
$manifest = Get-Content (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
foreach ($file in $manifest.Files) {
    if ((Get-FileHash (Join-Path $package $file.Name)).Hash -ne $file.SHA256) { throw "Build package checksum mismatch: $($file.Name)" }
}
$dirty = & git -C $workspace status --porcelain
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Commit all source changes before packaging corresponding sources.' }
$version = (& git -C $workspace rev-parse HEAD).Trim()
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root = Join-Path $build ('transfer-' + $stamp)
$name = 'Meltype-Native-Google-windows-x64'
$stage = Join-Path $root $name
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$stagePackage = Join-Path $stage 'experimental-build/native-ime-package'
New-Item -ItemType Directory -Path $stagePackage -Force | Out-Null
foreach ($file in $manifest.Files) { Copy-Item -LiteralPath (Join-Path $package $file.Name) -Destination (Join-Path $stagePackage $file.Name) }
@{ Architecture = 'x64'; Portable = $true; SourceCommit = $version; Files = $manifest.Files } |
    ConvertTo-Json -Depth 4 | Set-Content (Join-Path $stagePackage 'manifest.json') -Encoding UTF8
$scripts = Join-Path $stage 'tools/native-ime'
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
foreach ($script in @('Set-NativeShortcuts.ps1','Uninstall-InstalledNativeIme.ps1','NativeGuiCommon.ps1','Host-NativeControlPanel.ps1','Open-NativeControlPanel.ps1','Invoke-NativeGuiAction.ps1','Update-NativeIme.ps1','Set-InstalledNativeAutoStart.ps1','NativeAutoStart.ps1','Set-NativeAutoStart.ps1','Install-NativeIme.ps1','Start-NativeIme.ps1','Wait-NativeBroker.ps1','Stop-NativeIme.ps1','Uninstall-NativeIme.ps1','Host-NativeBroker.ps1','Backup-State.ps1','Start-Resident.ps1','Host-Resident.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $scripts $script)
}
foreach ($launcher in @('Enable-NativeAutoStart.cmd','Disable-NativeAutoStart.cmd','Install-NativeIme.cmd','Start-NativeIme.cmd','Stop-NativeIme.cmd','Uninstall-NativeIme.cmd')) {
    Copy-Item -LiteralPath (Join-Path $workspace $launcher) -Destination (Join-Path $stage $launcher)
}
Copy-Item -LiteralPath (Join-Path $workspace 'LICENSE') -Destination (Join-Path $stage 'LICENSE')
Copy-Item -LiteralPath (Join-Path $workspace 'SECURITY.md') -Destination (Join-Path $stage 'SECURITY.md')
Copy-Item -LiteralPath (Join-Path $workspace 'Meltype-Settings.exe') -Destination (Join-Path $stage 'Meltype-Settings.exe')
Copy-Item -LiteralPath (Join-Path $workspace 'docs/NATIVE_IME_TRANSFER.md') -Destination (Join-Path $stage 'README.md')
Set-Content (Join-Path $stage 'SOURCE_VERSION.txt') $version -Encoding ASCII
$sourceArchive = Join-Path $stage 'corresponding-source.zip'
& git -C $workspace archive --format=zip --output $sourceArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Corresponding source archive failed' }
$runtimeTarget = Join-Path $stage 'runtime'
New-Item -ItemType Directory -Path $runtimeTarget -Force | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $runtimeRoot -Force) {
    if ($item.Name -in @('preview','build.manifest','build.manifest.sig') -or $item.Name -like '*.profile.ps1') { continue }
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $runtimeTarget $item.Name) -Recurse
}
foreach ($required in @('pwsh.exe','LICENSE.txt','ThirdPartyNotices.txt','ref')) {
    if (-not (Test-Path -LiteralPath (Join-Path $runtimeTarget $required))) { throw "Runtime component missing: $required" }
}
$destination = Join-Path $workspace 'distributions'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$zip = Join-Path $destination ($name + '-' + $stamp + '.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($root, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash -LiteralPath $zip).Hash
Set-Content ($zip + '.sha256') ($hash + '  ' + (Split-Path $zip -Leaf)) -Encoding ASCII
Write-Output $zip
Write-Output ('SHA256: ' + $hash)
