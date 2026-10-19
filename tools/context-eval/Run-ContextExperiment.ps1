param([switch]$Download, [string]$Dotnet = "$env:LOCALAPPDATA/Microsoft/dotnet/dotnet.exe")
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$directory=Join-Path $root 'experimental-build/zenz'
$model=Join-Path $directory 'zenz-v3.2-small-Q5_K_M.gguf'
$zip=Join-Path $directory 'azookey-llama.zip'
$server=Join-Path $directory 'azookey-runtime/llama-server.exe'
function CheckHash([string]$Path,[string]$Expected) {
    if((Get-FileHash -LiteralPath $Path).Hash -ne $Expected){throw "Unexpected SHA256: $Path"}
}
if($Download){
    New-Item -ItemType Directory -Force -Path $directory|Out-Null
    if(-not(Test-Path -LiteralPath $model)){
        Invoke-WebRequest -UseBasicParsing 'https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf' -OutFile $model
    }
    if(-not(Test-Path -LiteralPath $zip)){
        Invoke-WebRequest -UseBasicParsing 'https://github.com/azooKey/llama.cpp/releases/download/b4846/llama-b4846-bin-win-avx2-x64.zip' -OutFile $zip
    }
    CheckHash $zip '52AD0D24305421BB011A1308FADAC37A28BC74F9767B0702B20311AE0539AA5B'
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $directory 'azookey-runtime') -Force
}
if(-not(Test-Path -LiteralPath $server)){throw 'Run with -Download to prepare the pinned azooKey CPU runtime and model.'}
CheckHash $model '29C223D4C23327B80FD13EBB5AB2555057A46317997D5DA391584FFBEF0DB673'
CheckHash $zip '52AD0D24305421BB011A1308FADAC37A28BC74F9767B0702B20311AE0539AA5B'
# Allocate an unused local port; never reuse an unrelated inference server.
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$endpoint="http://127.0.0.1:$port/"
$arguments=@('-m',('"'+$model+'"'),'--host','127.0.0.1','--port',[string]$port,'-ngl','0','-t','4','-c','1024','--no-webui')
$process=Start-Process -FilePath $server -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'server-out.log') -RedirectStandardError (Join-Path $directory 'server-error.log')
Push-Location $root
try {
    $ready=$false
    for($attempt=0;$attempt -lt 50;$attempt++){
        if($process.HasExited){throw 'Local model server exited; see experimental-build/zenz/server-error.log.'}
        try{$health=Invoke-RestMethod ($endpoint+'health') -TimeoutSec 1;$ready=$health.status -eq 'ok'}catch{}
        if($ready){break};Start-Sleep -Milliseconds 100
    }
    if(-not $ready){throw 'Model server did not become ready.'}
    & $Dotnet run --project src/Meltype.Core.Tests -- --context-bench tools/context-eval/cases.json $endpoint experimental-build/context-learning-results.json
    if($LASTEXITCODE -ne 0){throw 'Controlled candidate experiment failed.'}
    & $Dotnet run --project src/Meltype.Tests -- --context-native-bench $endpoint experimental-build/context-native-results.json
    if($LASTEXITCODE -ne 0){throw 'Google/controller replay failed.'}
    $process.Refresh()
    [ordered]@{DateJst=[DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(9)).ToString('o');Backend='CPU';Threads=4;ContextSize=1024;Runtime='azooKey/llama.cpp b4846';Model='zenz-v3.2-small Q5_K_M';ModelRevision='c67e03e07d215c869f591b274c1631170d3e11fe';WorkingSetBytes=$process.WorkingSet64;PrivateBytes=$process.PrivateMemorySize64} |
        ConvertTo-Json|Set-Content (Join-Path $directory 'environment.json') -Encoding utf8
} finally {
    Pop-Location
    if(-not $process.HasExited){Stop-Process -Id $process.Id}
}
