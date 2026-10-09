$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeReleaseUpdater.ps1')
$hash='a'*64
$release=[pscustomobject]@{tag_name='native-google-1.0.7';draft=$false;prerelease=$false;html_url='https://github.com/AoneSenbongi/Meltype/releases/tag/native-google-1.0.7';assets=@([pscustomobject]@{name='Meltype-Native-Google-1.0.7-Setup.exe';size=123;digest=('sha256:'+$hash);browser_download_url='https://github.com/AoneSenbongi/Meltype/releases/download/native-google-1.0.7/Meltype-Native-Google-1.0.7-Setup.exe'})}
if(-not (Get-NativeReleaseCandidate $release '1.0.6').Available){throw 'New release not offered'}
if((Get-NativeReleaseCandidate $release '1.0.6').SHA256 -ne $hash){throw 'Release digest capture failed'}
if((Get-NativeReleaseCandidate $release '1.0.7').Available){throw 'Same version offered'}
if((Get-NativeReleaseCandidate $release '1.0.8-rc.1').Available){throw 'Downgrade offered'}
if(-not (Get-NativeReleaseCandidate $release '1.0.7-rc.1').Available){throw 'Stable release must replace its RC'}
foreach($field in @('prerelease','digest','url','name','tag','size')){
    $copy=$release|ConvertTo-Json -Depth 5|ConvertFrom-Json
    switch($field){
        'prerelease'{$copy.prerelease=$true}
        'digest'{$copy.assets[0].digest=''}
        'url'{$copy.assets[0].browser_download_url='https://example.com/setup.exe'}
        'name'{$copy.assets[0].name='Other.exe'}
        'tag'{$copy.tag_name='android-prototype-1.0.7'}
        'size'{$copy.assets[0].size=0}
    }
    $rejected=$false;try{Get-NativeReleaseCandidate $copy '1.0.6'|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw "Invalid release accepted: $field"}
}
$fixture=Join-Path $env:TEMP ('Meltype-update-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
try{
    $file=Join-Path $fixture 'fixture.exe';[IO.File]::WriteAllText($file,'synthetic fixture, never execute')
    $candidate=Get-NativeReleaseCandidate $release '1.0.6'
    $candidate.Size=(Get-Item $file).Length;$candidate.SHA256=(Get-FileHash $file).Hash
    Assert-NativeReleaseDownload $file $candidate
    [IO.File]::AppendAllText($file,' changed')
    $rejected=$false;try{Assert-NativeReleaseDownload $file $candidate}catch{$rejected=$true}
    if(-not $rejected){throw 'Changed download accepted'}
    . (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
    $script:downloadBytes=[Text.Encoding]::UTF8.GetBytes('synthetic downloaded installer')
    $script:downloadChanged=$false;$script:networkFails=$false;$script:launches=0;$script:installerCode=0;$script:installedVersion='1.0.7'
    function Invoke-WebRequest($Uri,$OutFile,$TimeoutSec,[switch]$UseBasicParsing){
        if($script:networkFails){throw 'synthetic offline'}
        [IO.File]::WriteAllBytes($OutFile,$script:downloadBytes)
        if($script:downloadChanged){[IO.File]::AppendAllText($OutFile,' changed')}
    }
    function Start-Process($FilePath,$ArgumentList,$WindowStyle,[switch]$Wait,[switch]$PassThru){
        $script:launches++;$script:installerArgs=$ArgumentList
        $process=[pscustomobject]@{ExitCode=$script:installerCode};$process|Add-Member ScriptMethod Dispose {};return $process
    }
    function Get-NativeGuiContext($Root){return @{State=@{NativeVersion=$script:installedVersion}}}
    [IO.File]::WriteAllBytes($file,$script:downloadBytes)
    $candidate.Size=(Get-Item $file).Length;$candidate.SHA256=(Get-FileHash $file).Hash
    Invoke-NativeReleaseInstall $fixture $candidate
    if($script:launches -ne 1 -or $script:installerArgs -notcontains '/NORESTART'){throw 'Verified installer not launched correctly'}
    $script:downloadChanged=$true
    $rejected=$false;try{Invoke-NativeReleaseInstall $fixture $candidate}catch{$rejected=$true}
    if(-not $rejected -or $script:launches -ne 1){throw 'Changed download was executed'}
    $script:downloadChanged=$false;$script:networkFails=$true
    $rejected=$false;try{Invoke-NativeReleaseInstall $fixture $candidate}catch{$rejected=$true}
    if(-not $rejected -or $script:launches -ne 1){throw 'Offline update executed installer'}
    $script:networkFails=$false;$script:installedVersion='1.0.6'
    $rejected=$false;try{Invoke-NativeReleaseInstall $fixture $candidate}catch{$rejected=$true}
    if(-not $rejected){throw 'File placement without an IME version update was accepted'}
    Write-Output 'PASS: download verification before launch, offline/tampered installer rejection and partial setup detection; fixture only'
}finally{
    $download=Join-Path $fixture ('updates/'+$candidate.Version+'/'+$candidate.Name)
    if(Test-Path -LiteralPath $download){Remove-Item -LiteralPath $download;Remove-Item -LiteralPath (Split-Path $download -Parent);Remove-Item -LiteralPath (Join-Path $fixture 'updates')}
    Remove-Item -LiteralPath $file;Remove-Item -LiteralPath $fixture
}
Write-Output 'PASS: stable versions, no downgrade, RC transition, release/URL/asset/digest checks and changed download rejection'
