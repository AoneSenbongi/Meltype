$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
if ((ConvertTo-NativeGuiArgument 'C:\日本語 folder\test.ps1') -ne '"C:\日本語 folder\test.ps1"') { throw 'Path quoting failed.' }
foreach ($argument in @('a"b', "a`nb")) {
    $rejected = $false
    try { ConvertTo-NativeGuiArgument $argument | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsafe process argument accepted.' }
}
$context = Get-NativeGuiContext (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
if ($context.Installed) {
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    foreach ($action in @('Start','Stop','Update','Enable','Disable')) {
        if ((Get-NativeGuiAction $root $action).Elevated) { throw 'Normal operation requires administrator rights.' }
    }
    if (-not (Get-NativeGuiAction $root 'Uninstall').Elevated) { throw 'Unregistration must use elevation.' }
    if ((Get-NativeGuiAction $root 'Stop').Arguments -notcontains '-NoStartOriginal') { throw 'Stop would restart the old resident.' }
}
if (-not (Test-Path -LiteralPath (Get-NativeGoogleTool))) { throw 'Google dictionary tool is missing.' }
$fixture = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ('experimental-build/gui-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$files = foreach ($name in @('Meltype.Core.dll','Meltype.dll','NativeBroker.cs')) {
    $path = Join-Path $fixture $name
    Set-Content -LiteralPath $path -Value 'fixture' -Encoding ASCII
    @{ Name = $name; SHA256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($path))) }
}
@{ Files = @($files) } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $fixture 'manifest.json') -Encoding UTF8
function Get-FileHash { throw 'Get-FileHash is unavailable in this runtime.' }
Assert-NativeUpdatePackage $fixture | Out-Null
Set-Content (Join-Path $fixture 'Meltype.dll') 'changed' -Encoding ASCII
$rejected = $false
try { Assert-NativeUpdatePackage $fixture | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Modified update payload was accepted.' }
$resultFile = Join-Path $fixture 'result.json'
@{ Success = $false; Output = 'fixture failure' } | ConvertTo-Json | Set-Content -LiteralPath $resultFile
$completed = [pscustomobject]@{ HasExited = $true; Disposed = $false }
$completed | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
$process = $completed
$completion = Receive-NativeGuiActionCompletion ([ref]$process) ([ref]$resultFile)
if ($completion.Success -or $completion.Output -ne 'fixture failure' -or $process -or $resultFile -or -not $completed.Disposed) { throw 'Failed action was not consumed before display.' }
if ($null -ne (Receive-NativeGuiActionCompletion ([ref]$process) ([ref]$resultFile))) { throw 'Completed action was returned again during dialog reentry.' }
foreach ($file in Get-ChildItem -LiteralPath $fixture -File) { Remove-Item -LiteralPath $file.FullName }
Remove-Item -LiteralPath $fixture
Write-Output 'PASS: quoted paths, action permissions, stop behavior and Google dictionary tool.'
Write-Output 'PASS: verified update payload and rejection before changing installed files.'
Write-Output 'PASS: missing hash command and one-time consumption of failed action results.'
