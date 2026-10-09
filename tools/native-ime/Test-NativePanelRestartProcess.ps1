$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$fixture=Join-Path $env:TEMP ('Meltype-panel-process-'+[Guid]::NewGuid().ToString('N'))
$scripts=Join-Path $fixture 'tools/native-ime';New-Item -ItemType Directory $scripts -Force|Out-Null
$old=Join-Path $scripts 'Host-NativeControlPanel.ps1';$open=Join-Path $scripts 'Open-NativeControlPanel.ps1'
[IO.File]::WriteAllText($old,'Start-Sleep -Seconds 120')
$global:panelProcessOpened=$false
[IO.File]::WriteAllText($open,'$global:panelProcessOpened=$true')
$runtime=Join-Path $PSHOME 'pwsh.exe'
$process=Start-Process -FilePath $runtime -ArgumentList @('-NoProfile','-File',('"'+$old+'"')) -WindowStyle Hidden -PassThru
try{
    Start-Sleep -Milliseconds 500
    Restart-NativeControlPanel $fixture $fixture
    $process.Refresh()
    if(-not $process.HasExited -or -not $global:panelProcessOpened){throw 'Real old panel process was not replaced'}
    Write-Output 'PASS: real same-user panel fixture terminated before opening replacement; no installed IME or panel touched'
}finally{
    if(-not $process.HasExited){Stop-Process -Id $process.Id}
    $process.Dispose();Remove-Item -LiteralPath $old;Remove-Item -LiteralPath $open;Remove-Item -LiteralPath $scripts;Remove-Item -LiteralPath (Join-Path $fixture 'tools');Remove-Item -LiteralPath $fixture
}
