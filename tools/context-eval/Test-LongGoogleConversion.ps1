param()
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $root 'src/Meltype/bin/Debug/net10.0-windows'
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.Core.dll'))|Out-Null
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.dll'))|Out-Null
$rows=@()
foreach($repeat in @(6,16)){
    $reading='かわでくつをつくる'+('そしてそのときのようすをくわしくきろくしておく'*$repeat)
    $converter=[Meltype.Composition.GoogleImeConverter]::new($false)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $clauses=$converter.ConvertClauses($reading)
    $clock.Stop()
    if(-not $clauses -or [string]::Concat([string[]]@($clauses|ForEach-Object Reading)) -ne $reading){throw "Long Google conversion failed at $($reading.Length) characters"}
    $text=[string]::Concat([string[]]@($clauses|ForEach-Object Text))
    if($text -eq $reading){throw 'Long input has no converted candidates'}
    $rows+=@{readingLength=$reading.Length;clauses=$clauses.Count;textPrefix=$text.Substring(0,[Math]::Min(18,$text.Length));elapsedMs=$clock.Elapsed.TotalMilliseconds;readingPreserved=$true;learning=$false}
}
$rows|ConvertTo-Json|Set-Content (Join-Path $root 'experimental-build/context-clause-google-long-final.json') -Encoding utf8
$rows|ConvertTo-Json
