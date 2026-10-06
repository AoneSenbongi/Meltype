param([string]$Compiler='E:/prog/w64devkit/bin/g++.exe')
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $workspace 'experimental-build'
$fixture=Join-Path $build ('search-sandbox-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$probe=Join-Path $fixture 'sandbox-probe.exe'
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -static -static-libgcc -static-libstdc++ (Join-Path $workspace 'native/tsf/NativeSandboxProbe.cpp') -luserenv -ladvapi32 -o $probe
if($LASTEXITCODE -ne 0){throw 'Sandbox probe compilation failed'}
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.Core.dll'))|Out-Null
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.dll'))|Out-Null
$references=@((Join-Path $build 'Meltype.Core.dll'),(Join-Path $build 'Meltype.dll'))+@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
Add-Type -Path (Join-Path $workspace 'native/tsf/NativeBroker.cs') -ReferencedAssemblies $references
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$context=Get-NativeGuiContext $workspace
if(-not $context.Installed){throw 'This diagnostic requires an installed IME'}
$dll=Join-Path $context.State.PackageRoot 'MeltypeNative64.dll'
$name='Meltype.Search.Sandbox.'+[Guid]::NewGuid().ToString('N')
$listener=[MeltypeNativeBroker]::CreateListener($name,$true)
try {
    $output=& $probe $dll ('\\.\pipe\'+$name)
    if($LASTEXITCODE -ne 0){throw 'Isolated sandbox setup failed'}
    $result=$output|ConvertFrom-Json
    if(-not $result.appContainer){throw 'Probe did not run in an AppContainer'}
    $output|Set-Content (Join-Path $build 'search-sandbox-result.json')
    $output
    if($result.fileReadError -ne 5 -or $result.pipeConnectError -ne 5){throw 'Expected current DLL/pipe access denial was not reproduced'}
    Write-Output 'REPRODUCED: AppContainer cannot read the installed DLL or connect to the current broker pipe policy. No input was sent.'
} finally {
    $listener.Dispose()
    $resolved=(Resolve-Path -LiteralPath $fixture).Path
    $allowed=(Resolve-Path -LiteralPath $build).Path+'\search-sandbox-'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected sandbox cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
