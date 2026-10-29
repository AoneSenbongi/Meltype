function Resolve-NativeModelAssetPath([string]$PackageRoot,[string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -match '["\r\n]'){throw 'Invalid context model asset path'}
    if([IO.Path]::IsPathFullyQualified($Path)){return [IO.Path]::GetFullPath($Path)}
    # Bundled assets are flat manifest files, not arbitrary paths relative to the process.
    if($Path -in @('.','..') -or $Path -match '[/\\:]'){throw 'Invalid bundled context model asset path'}
    return [IO.Path]::GetFullPath((Join-Path $PackageRoot $Path))
}
function Get-NativeVerifiedContextModel([string]$PackageRoot) {
    $configPath=Join-Path $PackageRoot 'context-model.json'
    if(-not(Test-Path -LiteralPath $configPath)){return $null}
    $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
    foreach($asset in $config.Assets){
        $asset.Path=Resolve-NativeModelAssetPath $PackageRoot $asset.Path
        if((Get-FileHash -LiteralPath $asset.Path).Hash -ne $asset.SHA256){throw 'Context model asset checksum mismatch'}
    }
    $config.ModelPath=Resolve-NativeModelAssetPath $PackageRoot $config.ModelPath
    $config.ServerPath=Resolve-NativeModelAssetPath $PackageRoot $config.ServerPath
    foreach($path in @($config.ModelPath,$config.ServerPath)){
        if($path -notin $config.Assets.Path){throw 'Context model asset is not verified'}
    }
    return $config
}
function Start-NativeContextModel([string]$PackageRoot,[string]$BuildRoot) {
    $config=Get-NativeVerifiedContextModel $PackageRoot
    if($null -eq $config){return $null}
    if($config.RequireAvx2 -and -not [Runtime.Intrinsics.X86.Avx2]::IsSupported){
        @{running=$false;reason='AVX2 is not supported';brokerPid=$PID}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $BuildRoot 'context-model-status.json') -Encoding utf8
        return $null
    }
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
    $endpoint="http://127.0.0.1:$port/"
    $info=[Diagnostics.ProcessStartInfo]::new($config.ServerPath)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($argument in @('-m',$config.ModelPath,'--host','127.0.0.1','--port',"$port",'-ngl','0','-t','4','-c','1024','--no-webui')){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try{
        if(-not $process.Start()){throw 'Context model could not start'}
        # Drain and discard output. Never persist prompts or runtime diagnostics from real typing.
        $process.BeginOutputReadLine();$process.BeginErrorReadLine()
        $ready=$false
        for($attempt=0;$attempt -lt 100;$attempt++){
            if($process.HasExited){throw "Context model exited: $($process.ExitCode)"}
            try{$ready=(Invoke-RestMethod ($endpoint+'health') -TimeoutSec 1).status -eq 'ok'}catch{}
            if($ready){break};Start-Sleep -Milliseconds 100
        }
        if(-not $ready){throw 'Context model startup timed out'}
        $status=Join-Path $BuildRoot 'context-model-status.json'
        @{running=$true;pid=$process.Id;endpoint=$endpoint;modelSHA256=($config.Assets|Where-Object Path -EQ $config.ModelPath).SHA256;brokerPid=$PID}|ConvertTo-Json|Set-Content -LiteralPath $status -Encoding utf8
        return [pscustomobject]@{Process=$process;Endpoint=$endpoint;StatusPath=$status}
    }catch{
        if($process.Id -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
        $process.Dispose();throw
    }
}
function Stop-NativeContextModel($Model) {
    if(-not $Model){return}
    try{
        if(-not $Model.Process.HasExited){$Model.Process.Kill();$Model.Process.WaitForExit()}
        @{running=$false;pid=$Model.Process.Id;endpoint=$Model.Endpoint;brokerPid=$PID}|ConvertTo-Json|Set-Content -LiteralPath $Model.StatusPath -Encoding utf8
    }finally{$Model.Process.Dispose()}
}
