param([Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$directory=Join-Path $root 'experimental-build/zenz'
$model=Join-Path $directory 'zenz-v3.2-small-Q5_K_M.gguf'
$server=Join-Path $directory 'azookey-runtime/llama-server.exe'
$runner=Join-Path $root 'src/Meltype.Core.Tests/bin/Debug/net10.0/Meltype.Core.Tests.exe'
$process=$null
function WriteFailure([string]$Message){
    $state=[ordered]@{status='failed';stage='異常終了';message=$Message;processed=0;total=1000;runnerPid=$PID;checkpoints=@()}
    $existing=Join-Path $RunDirectory 'status.json'
    try{
        foreach($name in @('terminal.json','results.json')){
            $finished=Join-Path $RunDirectory $name
            if(Test-Path -LiteralPath $finished){
                $saved=Get-Content -LiteralPath $finished -Raw|ConvertFrom-Json
                if($saved.status -in @('completed','completed_with_errors','cancelled','failed')){
                    if($name -ne 'terminal.json'){$saved|ConvertTo-Json -Depth 12|Set-Content (Join-Path $RunDirectory 'terminal.json') -Encoding utf8}
                    return
                }
            }
        }
        if(Test-Path -LiteralPath $existing){
            $prior=Get-Content -LiteralPath $existing -Raw|ConvertFrom-Json
            if($prior.status -in @('completed','completed_with_errors','cancelled','failed')){return}
            if($null -ne $prior.processed){$state=$prior;$state.status='failed';$state.stage='異常終了';$state.message=$Message}
        }
    }catch{}
    $existing=Join-Path $RunDirectory 'terminal.json'
    $temp=$existing+'.tmp'
    $state|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $temp -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $existing -Force
}
try{
    [IO.File]::WriteAllText((Join-Path $RunDirectory 'worker.pid'),[string]$PID)
    if((Get-FileHash -LiteralPath $model).Hash -ne '29C223D4C23327B80FD13EBB5AB2555057A46317997D5DA391584FFBEF0DB673'){throw 'モデルのSHA256が準備済みの値と一致しません。'}
    if(-not(Test-Path -LiteralPath $runner)){throw '実験ランナーが未ビルドです。'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'long-cases.json') -Destination (Join-Path $RunDirectory 'cases.json')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'long-cases-manifest.json') -Destination (Join-Path $RunDirectory 'corpus-manifest.json')
    $manifest=Get-Content (Join-Path $RunDirectory 'corpus-manifest.json') -Raw|ConvertFrom-Json
    if((Get-FileHash (Join-Path $RunDirectory 'cases.json')).Hash.ToLowerInvariant() -ne $manifest.sha256){throw '実験コーパスのSHA256が一致しません。'}
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
    $endpoint="http://127.0.0.1:$port/"
    $arguments=@('-m',('"'+$model+'"'),'--host','127.0.0.1','--port',[string]$port,'-ngl','0','-t','4','-c','1024','--no-webui')
    $process=Start-Process -FilePath $server -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $RunDirectory 'model-out.log') -RedirectStandardError (Join-Path $RunDirectory 'model-error.log')
    [IO.File]::WriteAllText((Join-Path $RunDirectory 'server.pid'),[string]$process.Id)
    $ready=$false
    for($attempt=0;$attempt -lt 50;$attempt++){
        if(Test-Path (Join-Path $RunDirectory 'cancel.request')){
            @{status='cancelled';stage='停止';message='起動中に停止しました。';processed=0;total=1000;runnerPid=$PID}|ConvertTo-Json|Set-Content (Join-Path $RunDirectory 'status.json') -Encoding utf8
            return
        }
        if($process.HasExited){throw 'モデルサーバーが起動中に終了しました。model-error.logを確認してください。'}
        try{$health=Invoke-RestMethod ($endpoint+'health') -TimeoutSec 1;$ready=$health.status -eq 'ok'}catch{}
        if($ready){break};Start-Sleep -Milliseconds 100
    }
    if(-not $ready){throw 'モデルサーバーの起動確認が時間切れになりました。'}
    & $runner --context-long-run (Join-Path $RunDirectory 'cases.json') $endpoint $RunDirectory
    $code=$LASTEXITCODE
    if($code -notin @(0,2)){throw "実験ランナーが終了コード${code}で停止しました。"}
}catch{
    $_|Out-String|Set-Content (Join-Path $RunDirectory 'worker-error.log') -Encoding utf8
    WriteFailure $_.Exception.Message
}finally{
    if($process){
        try{
            $process.Refresh()
            $exited=$process.HasExited
            $exitCode=if($exited){$process.ExitCode}else{$null}
            @{backend='CPU';threads=4;contextSize=1024;model='zenz-v3.2-small Q5_K_M';runtime='azooKey/llama.cpp b4846';peakWorkingSetBytes=$process.PeakWorkingSet64;privateBytes=$process.PrivateMemorySize64;serverPid=$process.Id;serverExitedBeforeCleanup=$exited;serverExitCode=$exitCode}|
                ConvertTo-Json|Set-Content (Join-Path $RunDirectory 'environment.json') -Encoding utf8
            if(-not $process.HasExited){Stop-Process -Id $process.Id}
        }catch{}
    }
}
