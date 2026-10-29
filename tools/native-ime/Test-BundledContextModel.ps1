param([Parameter(Mandatory)][string]$ModelAssets)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeContextModel.ps1')
$fixture=Join-Path $root ('experimental-build/bundled model test '+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$config=Get-Content (Join-Path $root 'native/tsf/context-model.json') -Raw|ConvertFrom-Json
foreach($asset in $config.Assets){
    $name=[IO.Path]::GetFileName($asset.Path)
    Copy-Item -LiteralPath (Join-Path $ModelAssets $name) -Destination (Join-Path $fixture $name)
    $asset.Path=$name
}
$config.ServerPath=[IO.Path]::GetFileName($config.ServerPath)
$config.ModelPath=[IO.Path]::GetFileName($config.ModelPath)
$config|ConvertTo-Json -Depth 5|Set-Content (Join-Path $fixture 'context-model.json') -Encoding utf8
$model=$null
try {
    # Old implementation fails here: absolute paths were required even for bundled files.
    $model=Start-NativeContextModel $fixture $fixture
    $request=@{prompt="`u{EE02}川を渡る。`u{EE00}ハシ`u{EE01}";grammar='root ::= "橋" | "箸"';n_predict=16;temperature=0;seed=0}
    $response=Invoke-RestMethod ($model.Endpoint+'completion') -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json)))
    if($response.content -notin @('橋','箸')){throw 'Model response is outside candidates'}
    $ownedId=$model.Process.Id
    Stop-NativeContextModel $model;$model=$null
    if(Get-Process -Id $ownedId -ErrorAction SilentlyContinue){throw 'Bundled model process did not stop'}
    $relocated=$fixture+' relocated'
    # Both checked targets remain inside this worktree's experimental-build directory.
    if(-not [IO.Path]::GetFullPath($relocated).StartsWith([IO.Path]::GetFullPath((Join-Path $root 'experimental-build'))+[IO.Path]::DirectorySeparatorChar)){throw 'Invalid test destination'}
    Move-Item -LiteralPath $fixture -Destination $relocated
    $fixture=$relocated
    $model=Start-NativeContextModel $fixture $fixture
    Stop-NativeContextModel $model;$model=$null
    foreach($badPath in @('../llama-server.exe','..\llama-server.exe','C:llama-server.exe','sub/llama-server.exe')){
        $bad=$config|ConvertTo-Json -Depth 5|ConvertFrom-Json
        $bad.ServerPath=$badPath;$bad.Assets[0].Path=$badPath
        $bad|ConvertTo-Json -Depth 5|Set-Content (Join-Path $fixture 'context-model.json') -Encoding utf8
        $rejected=$false
        try{Start-NativeContextModel $fixture $fixture|Out-Null}catch{$rejected=$_.Exception.Message -like '*path*'}
        if(-not $rejected){throw ('Invalid bundled path accepted: '+$badPath)}
    }
    $config.Assets[0].SHA256='0'*64
    $config|ConvertTo-Json -Depth 5|Set-Content (Join-Path $fixture 'context-model.json') -Encoding utf8
    $rejected=$false
    try{Start-NativeContextModel $fixture $fixture|Out-Null}catch{$rejected=$_.Exception.Message -like '*checksum*'}
    if(-not $rejected){throw 'Tampered bundled model asset accepted'}
    'PASS: relative bundled assets; real inference; owned shutdown; relocated package; traversal rejected; tampering rejected'
}finally{if($model){Stop-NativeContextModel $model}}
