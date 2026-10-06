param([Parameter(Mandatory)][string]$Runtime, [string]$Compiler = 'g++.exe')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$Runtime = (Resolve-Path -LiteralPath $Runtime).Path
New-Item -ItemType Directory -Path $build -Force | Out-Null
Set-Content (Join-Path $build 'runtime-path.txt') $Runtime -Encoding UTF8
& $Runtime -NoProfile -File (Join-Path $PSScriptRoot 'Build-WithBundledCompiler.ps1') -TestFilter NativeInput
if ($LASTEXITCODE -ne 0) { throw 'Managed build or input tests failed' }
& (Join-Path $PSScriptRoot 'Build-NativeTextService.ps1') -Compiler $Compiler
& $Runtime -NoProfile -File (Join-Path $PSScriptRoot 'Generate-NativeCompositionTrace.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Google conversion trace failed' }
& (Join-Path $PSScriptRoot 'Build-NativeComposition.ps1') -Compiler $Compiler -GoogleTrace
$stage = Join-Path $build 'native-ime-package'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$files = @('MeltypeNative64.dll', 'native-ime-control.exe', 'Meltype.Core.dll', 'Meltype.dll')
foreach ($name in $files) { Copy-Item -LiteralPath (Join-Path $build $name) -Destination (Join-Path $stage $name) -Force }
Copy-Item -LiteralPath (Join-Path $workspace 'native/tsf/NativeBroker.cs') -Destination (Join-Path $stage 'NativeBroker.cs') -Force
Copy-Item -LiteralPath (Join-Path $workspace 'LICENSE') -Destination (Join-Path $stage 'LICENSE') -Force
$files += @('NativeBroker.cs', 'LICENSE')
$hashes = foreach ($name in $files) { @{ Name = $name; SHA256 = (Get-FileHash (Join-Path $stage $name)).Hash } }
@{ Created = (Get-Date).ToString('o'); Architecture = 'x64'; UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value; Files = @($hashes) } |
    ConvertTo-Json -Depth 4 | Set-Content (Join-Path $stage 'manifest.json') -Encoding UTF8
Write-Output 'Package prepared. Run Install-NativeIme.cmd as administrator, then Start-NativeIme.cmd normally.'
