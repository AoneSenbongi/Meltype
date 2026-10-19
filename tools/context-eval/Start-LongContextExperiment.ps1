param([string]$Runtime='C:/Users/AoneSenbongi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe')
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$directory=Join-Path $root ('experimental-build/long-context-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
if(Test-Path -LiteralPath $directory){throw '同じ実行先が存在します。1秒後に起動してください。'}
New-Item -ItemType Directory -Path $directory|Out-Null
$state=@{status='starting';stage='モデルを起動しています';message='';processed=0;total=1000;probesProcessed=0;probesTotal=40;modelRequests=0;failures=0;elapsedSeconds=0;remainingSeconds=$null;medianMs=0;p95Ms=0;checkpoints=@()}
$state|ConvertTo-Json|Set-Content (Join-Path $directory 'status.json') -Encoding utf8
$worker=Start-Process -FilePath $Runtime -ArgumentList @('-NoProfile','-File',('"'+(Join-Path $PSScriptRoot 'Invoke-LongContextWorker.ps1')+'"'),'-RunDirectory',('"'+$directory+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'worker-out.log') -RedirectStandardError (Join-Path $directory 'worker-stderr.log')
# The user explicitly requested a visible progress window.
$gui=Start-Process -FilePath $Runtime -ArgumentList @('-NoProfile','-STA','-File',('"'+(Join-Path $PSScriptRoot 'Show-LongContextProgress.ps1')+'"'),'-RunDirectory',('"'+$directory+'"')) -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $directory 'gui-out.log') -RedirectStandardError (Join-Path $directory 'gui-error.log')
$info=@{directory=$directory;workerPid=$worker.Id;guiPid=$gui.Id;startedJst=[DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(9)).ToString('o')}
$info|ConvertTo-Json|Set-Content (Join-Path $root 'experimental-build/long-context-latest.json') -Encoding utf8
$info|ConvertTo-Json
