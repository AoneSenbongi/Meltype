param([switch]$Disable, [string]$WorkspaceRoot, [string]$StartScript)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NativeAutoStart.ps1')
if (-not $WorkspaceRoot) { $WorkspaceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
if (-not $StartScript) { $StartScript = Join-Path $PSScriptRoot 'Start-NativeIme.ps1' }
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$name = 'MeltypeNativeGoogle'
$directory = Join-Path $env:LOCALAPPDATA $name
$backup = Join-Path $WorkspaceRoot ('backups/autostart-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$previous = $null
if (Test-Path -LiteralPath $runKey) {
    $properties = Get-ItemProperty -LiteralPath $runKey
    if ($properties.PSObject.Properties[$name]) { $previous = $properties.$name }
}
@{ Command = $previous } | ConvertTo-Json | Set-Content (Join-Path $backup 'previous-run.json') -Encoding UTF8
foreach ($file in @('Startup.ps1','settings.json')) {
    $path = Join-Path $directory $file
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $backup }
}
if ($Disable) {
    if ($null -ne $previous) { Remove-ItemProperty -LiteralPath $runKey -Name $name }
    Write-Output 'Native IME automatic startup disabled.'
    return
}
$build = Join-Path $WorkspaceRoot 'experimental-build'
$state = Get-Content (Join-Path $build 'native-ime-install.json') -Raw | ConvertFrom-Json
if ($state.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { throw 'Use the Windows account that installed this IME.' }
$runtime = (Get-Content (Join-Path $build 'runtime-path.txt') -Raw).Trim()
foreach ($path in @($runtime,$StartScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or $path -match '["\r\n]') { throw "Invalid startup component: $path" }
}
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$proxy = Join-Path $directory 'Startup.ps1'
$command = Get-NativeAutoStartCommand $proxy
@{ Runtime = $runtime; StartScript = $StartScript } | ConvertTo-Json | Set-Content (Join-Path $directory 'settings.json') -Encoding UTF8
@'
$ErrorActionPreference = 'Stop'
try {
    $settings = Get-Content (Join-Path $PSScriptRoot 'settings.json') -Raw | ConvertFrom-Json
    $arguments = '-NoProfile -File "' + $settings.StartScript + '"'
    Start-Process -FilePath $settings.Runtime -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput (Join-Path $PSScriptRoot 'startup-output.txt') -RedirectStandardError (Join-Path $PSScriptRoot 'startup-errors.txt')
} catch {
    $_ | Out-String | Set-Content (Join-Path $PSScriptRoot 'startup-errors.txt') -Encoding UTF8
}
'@ | Set-Content -LiteralPath $proxy -Encoding UTF8
New-Item -Path $runKey -Force | Out-Null
New-ItemProperty -LiteralPath $runKey -Name $name -Value $command -PropertyType String -Force | Out-Null
Write-Output 'Native IME will start hidden when you sign in to Windows.'
