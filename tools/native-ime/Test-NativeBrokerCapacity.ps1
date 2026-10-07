param([string]$PackageRoot,[string]$BrokerSource)
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $workspace 'experimental-build'
if($PackageRoot){$build=$PackageRoot}
$core=Join-Path $build 'Meltype.Core.dll'; $app=Join-Path $build 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core)|Out-Null
[Reflection.Assembly]::LoadFrom($app)|Out-Null
$references=@($core,$app)+@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll'|ForEach-Object FullName)
if(-not $BrokerSource){$BrokerSource=Join-Path $workspace 'native/tsf/NativeBroker.cs'}
Add-Type -Path $BrokerSource -ReferencedAssemblies $references
$name='Meltype.Capacity.Test.'+[Guid]::NewGuid().ToString('N')
$sid=[MeltypeNativeBroker]::SearchPackageSid
$pipes=[Collections.Generic.List[IDisposable]]::new()
$cancel=[Threading.CancellationTokenSource]::new()
try {
    for($index=0;$index -lt 32;$index++) {$pipes.Add([MeltypeNativeBroker]::CreateSearchListener($name,($index -eq 0),$sid))}
    $wait=[MeltypeNativeBroker]::WaitForSearchListener($name,$false,$sid,$cancel.Token)
    Start-Sleep -Milliseconds 200
    if($wait.IsCompleted){throw 'Full capacity did not wait'}
    $pipes[0].Dispose(); $pipes.RemoveAt(0)
    if(-not $wait.Wait(3000)){throw 'Available capacity was not reused'}
    $pipes.Add($wait.Result)
    $wait=[MeltypeNativeBroker]::WaitForSearchListener($name,$false,$sid,$cancel.Token)
    $cancel.Cancel()
    try {$wait.GetAwaiter().GetResult()|Out-Null; throw 'Cancellation was ignored'}
    catch {if($_.Exception.ToString() -notmatch 'OperationCanceled|TaskCanceled'){throw}}
    $pipes[0].Dispose(); $pipes.RemoveAt(0)
    $denied=$false
    try {$unexpected=[MeltypeNativeBroker]::WaitForSearchListener($name,$true,$sid,[Threading.CancellationToken]::None).GetAwaiter().GetResult();$unexpected.Dispose()}
    catch {$denied=$_.Exception.ToString() -match 'UnauthorizedAccessException'}
    if(-not $denied){throw 'First-instance conflict was not rejected'}
    Write-Output 'PASS: 32 instances, saturation waits, slot reused, cancellation, first-instance conflict rejected'
} finally {foreach($pipe in $pipes){$pipe.Dispose()};$cancel.Dispose()}
