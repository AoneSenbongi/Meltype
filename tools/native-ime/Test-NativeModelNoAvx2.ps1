param([Parameter(Mandatory)][string]$PackageRoot)
$ErrorActionPreference='Stop'
if([Runtime.Intrinsics.X86.Avx2]::IsSupported){throw 'Run this test with DOTNET_EnableAVX2=0'}
. (Join-Path $PSScriptRoot 'NativeContextModel.ps1')
if($null -ne (Start-NativeContextModel $PackageRoot $PackageRoot)){throw 'Model started without AVX2 support'}
$status=Get-Content (Join-Path $PackageRoot 'context-model-status.json') -Raw|ConvertFrom-Json
if($status.running -or $status.reason -ne 'AVX2 is not supported'){throw 'Missing unsupported CPU status'}
'PASS: AVX2-disabled process leaves model off and returns control for normal conversion'
