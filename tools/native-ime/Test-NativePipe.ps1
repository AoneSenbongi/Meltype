$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $workspace 'experimental-build'
$core = Join-Path $build 'Meltype.Core.dll'
$app = Join-Path $build 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core) | Out-Null
[Reflection.Assembly]::LoadFrom($app) | Out-Null
$references = @($core,$app) + @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
Add-Type -Path (Join-Path $workspace 'native/tsf/NativeBroker.cs') -ReferencedAssemblies $references
$name = 'Meltype.NativePipe.Test.' + [Guid]::NewGuid().ToString('N')
$occupied = [IO.Pipes.NamedPipeServerStream]::new($name, [IO.Pipes.PipeDirection]::InOut, 16,
    [IO.Pipes.PipeTransmissionMode]::Byte, ([IO.Pipes.PipeOptions]::Asynchronous -bor [IO.Pipes.PipeOptions]::CurrentUserOnly))
try {
    $rejected = $false
    try { $unexpected = [MeltypeNativeBroker]::CreateListener($name,$true); $unexpected.Dispose() }
    catch [UnauthorizedAccessException] { $rejected = $true }
    if (-not $rejected) { throw 'Broker accepted a pipe name already owned by another server.' }
} finally { $occupied.Dispose() }
$listener = [MeltypeNativeBroker]::CreateListener($name,$true)
$second = $null
try {
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $name, [IO.Pipes.PipeDirection]::InOut)
    try {
        $wait = $listener.WaitForConnectionAsync()
        $client.Connect(2000)
        if (-not $wait.Wait(2000)) { throw 'Local connection did not reach the listener.' }
        $second = [MeltypeNativeBroker]::CreateListener($name,$false)
        $buffer = [byte[]]::new(1)
        $read = $listener.ReadAsync($buffer,0,1)
        $client.WriteByte(42)
        $client.Flush()
        if (-not $read.Wait(2000) -or $read.Result -ne 1 -or $buffer[0] -ne 42) { throw 'Authorized local client cannot send data.' }
    } finally { $client.Dispose() }
} finally { if ($second) { $second.Dispose() }; $listener.Dispose() }
Write-Output 'PASS: occupied pipe name rejected; additional listener and authorized local client accepted.'
