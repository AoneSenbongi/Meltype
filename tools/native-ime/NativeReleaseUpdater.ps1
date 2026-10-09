function Get-NativeReleaseCandidate($Release,[string]$CurrentVersion) {
    if($Release.draft -or $Release.prerelease -or $Release.tag_name -notmatch '^native-google-(\d+\.\d+\.\d+)$'){throw 'NativeReleaseInvalid: not a stable Windows release'}
    $version=$Matches[1]
    if($CurrentVersion -notmatch '^\d+\.\d+\.\d+(?:-rc\.\d+)?$'){throw 'NativeReleaseInvalid: invalid current version'}
    if($Release.html_url -cne ('https://github.com/AoneSenbongi/Meltype/releases/tag/'+$Release.tag_name)){throw 'NativeReleaseInvalid: unexpected repository'}
    $available=[version]$version -gt [version]($CurrentVersion.Split('-')[0]) -or
        ([version]$version -eq [version]($CurrentVersion.Split('-')[0]) -and $CurrentVersion.Contains('-rc.'))
    if(-not $available){return [pscustomobject]@{Available=$false;Version=$version}}
    $name='Meltype-Native-Google-'+$version+'-Setup.exe'
    $assets=@($Release.assets|Where-Object name -CEQ $name)
    if($assets.Count -ne 1){throw 'NativeReleaseInvalid: installer is missing or ambiguous'}
    $asset=$assets[0]
    $url='https://github.com/AoneSenbongi/Meltype/releases/download/'+$Release.tag_name+'/'+$name
    if($asset.browser_download_url -cne $url -or $asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$'){throw 'NativeReleaseInvalid: download URL or SHA-256 is invalid'}
    $hash=$Matches[1]
    if($asset.size -le 0 -or $asset.size -gt 512MB){throw 'NativeReleaseInvalid: invalid installer size'}
    return [pscustomobject]@{Available=$true;Version=$version;Name=$name;URL=$url;SHA256=$hash;Size=[long]$asset.size}
}
function Assert-NativeReleaseDownload([string]$File,$Candidate) {
    if((Get-Item -LiteralPath $File).Length -ne $Candidate.Size -or
        (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ine $Candidate.SHA256){throw 'NativeReleaseInvalid: downloaded installer checksum differs'}
}
function Get-NativeLatestRelease([string]$CurrentVersion) {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    try{
        $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/AoneSenbongi/Meltype/releases/latest' -Headers @{'User-Agent'='Meltype-Native-Updater';Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'} -TimeoutSec 30
    }catch{throw 'NativeReleaseNetwork: latest release could not be retrieved'}
    Get-NativeReleaseCandidate $release $CurrentVersion
}
function Invoke-NativeReleaseInstall([string]$Root,$Candidate) {
    $folder=Join-Path $Root ('updates/'+$Candidate.Version)
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    $file=Join-Path $folder $Candidate.Name
    try{Invoke-WebRequest -UseBasicParsing -Uri $Candidate.URL -OutFile $file -TimeoutSec 300|Out-Null}catch{throw 'NativeReleaseNetwork: installer could not be downloaded'}
    Assert-NativeReleaseDownload $file $Candidate
    $destination=Join-Path (Split-Path $Root -Parent) $Candidate.Version
    $arguments=@('/SILENT','/NORESTART',('/DIR='+ (ConvertTo-NativeGuiArgument $destination)))
    $process=Start-Process -FilePath $file -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    try{
        if($process.ExitCode -ne 0){throw 'NativeReleaseInstall: setup did not complete'}
        $context=Get-NativeGuiContext $Root
        if($context.State.NativeVersion -ne $Candidate.Version){throw 'NativeReleaseInstall: IME update was cancelled or failed'}
    }finally{$process.Dispose()}
}
