param([Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$ModelAssets)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config=Get-Content (Join-Path $root 'native/tsf/context-model.json') -Raw|ConvertFrom-Json
$files=@()
foreach($asset in $config.Assets){
    $name=[IO.Path]::GetFileName($asset.Path)
    $source=Join-Path $ModelAssets $name
    if((Get-FileHash -LiteralPath $source).Hash -ne $asset.SHA256){throw ('Bundled model checksum mismatch: '+$name)}
    Copy-Item -LiteralPath $source -Destination (Join-Path $Stage $name)
    $asset.Path=$name
    $files+=$name
}
$config.ServerPath=[IO.Path]::GetFileName($config.ServerPath)
$config.ModelPath=[IO.Path]::GetFileName($config.ModelPath)
$config|Add-Member NoteProperty RequireAvx2 $true -Force
$config|ConvertTo-Json -Depth 5|Set-Content (Join-Path $Stage 'context-model.json') -Encoding utf8
$files+='context-model.json'
. (Join-Path $PSScriptRoot 'NativeContextModel.ps1')
Get-NativeVerifiedContextModel $Stage | Out-Null
foreach($name in @('ZENZ-APACHE-2.0.txt','LLAMA-MIT.txt','ZENZ-NOTICE.txt')){
    Copy-Item -LiteralPath (Join-Path $root ('licenses/'+$name)) -Destination (Join-Path $Stage $name)
    $files+=$name
}
foreach($name in $files){@{Name=$name;SHA256=(Get-FileHash -LiteralPath (Join-Path $Stage $name)).Hash}}
