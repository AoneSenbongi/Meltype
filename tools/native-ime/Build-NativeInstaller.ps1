param([Parameter(Mandatory)][string]$TransferZip,[Parameter(Mandatory)][string]$Compiler)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Test-NativeVersion.ps1')
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$TransferZip=(Resolve-Path -LiteralPath $TransferZip).Path
$Compiler=(Resolve-Path -LiteralPath $Compiler).Path
$stage=Join-Path $root ('experimental-build/installer-'+[Guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($TransferZip,$stage)
$package=Join-Path $stage 'Meltype-Native-Google-windows-x64'
$source=(Get-Content (Join-Path $package 'SOURCE_VERSION.txt') -Raw).Trim()
if($source -ne (& git -C $root rev-parse HEAD).Trim()){throw 'Rebuild transfer package from current committed sources'}
foreach($name in @('Invoke-NativeSetup.ps1','NativeInstaller.ps1')){
    if((Get-FileHash (Join-Path $package ('tools/native-ime/'+$name))).Hash -ne (Get-FileHash (Join-Path $PSScriptRoot $name)).Hash){throw "Installer script mismatch: $name"}
}
$output=Join-Path $root 'distributions'
& $Compiler ('/DPackageRoot='+$package) ('/DOutputRoot='+$output) (Join-Path $PSScriptRoot 'MeltypeSetup.iss')
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed'}
$exe=Join-Path $output 'Meltype-Native-Google-1.0.7-Setup.exe'
$hash=(Get-FileHash -LiteralPath $exe).Hash
Set-Content ($exe+'.sha256') ($hash+'  '+(Split-Path $exe -Leaf)) -Encoding ASCII
@{Version='1.0.7';SourceCommit=$source;Installer=$exe;SHA256=$hash;Stage=$package}|ConvertTo-Json|Set-Content (Join-Path $root 'experimental-build/installer-build.json') -Encoding UTF8
Write-Output $exe
Write-Output ('SHA256: '+$hash)
