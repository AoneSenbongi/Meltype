param([switch]$Clauses, [switch]$Native)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$prefix=if($Native){'context-clause-native-'}elseif($Clauses){'context-clauses-'}else{'context-length-'}
$output=Join-Path $root ('experimental-build/'+$prefix+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $output|Out-Null
$model=Join-Path $root 'experimental-build/zenz/zenz-v3.2-small-Q5_K_M.gguf'
if((Get-FileHash $model).Hash -ne '29C223D4C23327B80FD13EBB5AB2555057A46317997D5DA391584FFBEF0DB673'){throw 'Model hash mismatch'}
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$server=Join-Path $root 'experimental-build/zenz/azookey-runtime/llama-server.exe'
$process=Start-Process -FilePath $server -ArgumentList @('-m',('"'+$model+'"'),'--host','127.0.0.1','--port',"$port",'-ngl','0','-t','4','-c','1024','--no-webui') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'server-out.log') -RedirectStandardError (Join-Path $output 'server-error.log')
try{
    $ready=$false
    for($attempt=0;$attempt -lt 100;$attempt++){
        if($process.HasExited){throw 'Server exited during startup'}
        try{$ready=(Invoke-RestMethod "http://127.0.0.1:$port/health" -TimeoutSec 1).status -eq 'ok'}catch{}
        if($ready){break};Start-Sleep -Milliseconds 100
    }
    if(-not $ready){throw 'Server startup timed out'}
    if($Native){
        Copy-Item (Join-Path $root 'src/Meltype.Core/bin/Debug/net10.0/Meltype.Core.dll') (Join-Path $root 'experimental-build/Meltype.Core.dll')
        Copy-Item (Join-Path $root 'src/Meltype/bin/Debug/net10.0-windows/Meltype.dll') (Join-Path $root 'experimental-build/Meltype.dll')
        & (Join-Path $root 'src/Meltype.Tests/bin/Debug/net10.0-windows/Meltype.Tests.exe') --context-native-bench "http://127.0.0.1:$port/" (Join-Path $output 'google-replay.json') *> (Join-Path $output 'google-replay.log')
        if($LASTEXITCODE -ne 0){throw 'Google controller replay failed'}
        & (Join-Path $root 'src/Meltype.Tests/bin/Debug/net10.0-windows/Meltype.Tests.exe') --context-native-long-bench "http://127.0.0.1:$port/" (Join-Path $output 'google-long-replay.json') *> (Join-Path $output 'google-long-replay.log')
        if($LASTEXITCODE -ne 0){throw 'Long Google controller replay failed'}
        $previousLog=Join-Path $root 'experimental-build/native-context-evaluation.log'
        if(Test-Path $previousLog){Copy-Item $previousLog (Join-Path $output 'previous-native-context-evaluation.log')}
        & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $root 'tools/native-ime/Test-NativeUpstreamFeatures.ps1') -ContextEndpoint "http://127.0.0.1:$port/" *> (Join-Path $output 'native-tsf.log')
    }else{
        $mode=if($Clauses){'--context-clause-run'}else{'--context-length-run'}
        & (Join-Path $root 'src/Meltype.Core.Tests/bin/Debug/net10.0/Meltype.Core.Tests.exe') $mode "http://127.0.0.1:$port/" $output *> (Join-Path $output 'runner.log')
    }
    $runnerCode=$LASTEXITCODE
    if($runnerCode -ne 0){throw "Length experiment failed: $runnerCode; see $output"}
    $output
}finally{
    $process.Refresh()
    @{backend='CPU';threads=4;contextSize=1024;model='zenz-v3.2-small Q5_K_M';runtime='azooKey/llama.cpp b4846';serverExitedBeforeCleanup=$process.HasExited;peakWorkingSetBytes=$process.PeakWorkingSet64}|ConvertTo-Json|Set-Content (Join-Path $output 'environment.json') -Encoding utf8
    if(-not $process.HasExited){Stop-Process -Id $process.Id}
}
