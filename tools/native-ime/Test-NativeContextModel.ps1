$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeContextModel.ps1')
$fixture=Join-Path $root ('experimental-build/context-model-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
if($null -ne (Start-NativeContextModel $fixture $fixture)){throw 'Legacy package unexpectedly enabled a model'}
Copy-Item (Join-Path $root 'native/tsf/context-model.json') (Join-Path $fixture 'context-model.json')
$model=$null
try{
    $model=Start-NativeContextModel $fixture $fixture
    $request=@{prompt="`u{EE02}川を渡る。`u{EE00}ハシ`u{EE01}";grammar='root ::= "橋" | "箸"';n_predict=16;temperature=0;seed=0}
    $response=Invoke-RestMethod ($model.Endpoint+'completion') -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json)))
    if($response.content -notin @('橋','箸')){throw 'Model response is outside candidates'}
    $processId=$model.Process.Id
    Stop-NativeContextModel $model;$model=$null
    if(Get-Process -Id $processId -ErrorAction SilentlyContinue){throw 'Owned model process did not stop'}
    $bad=Get-Content (Join-Path $fixture 'context-model.json') -Raw|ConvertFrom-Json
    $bad.Assets[0].SHA256='0'*64
    $bad|ConvertTo-Json -Depth 4|Set-Content (Join-Path $fixture 'context-model.json') -Encoding utf8
    $rejected=$false
    try{Start-NativeContextModel $fixture $fixture|Out-Null}catch{$rejected=$_.Exception.Message -like '*checksum*'}
    if(-not $rejected){throw 'Altered asset was not rejected'}
    Write-Output 'PASS: legacy disabled; checked model startup; loopback conversion; owned shutdown; tampered asset rejected'
}finally{if($model){Stop-NativeContextModel $model}}
