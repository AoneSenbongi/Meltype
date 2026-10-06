$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture=Join-Path $root ('experimental-build/update-availability-'+[Guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'source'
$installed=Join-Path $fixture 'installed'
$stage=Join-Path $source 'experimental-build/native-ime-package'
$package=Join-Path $installed 'experimental-build/installed'
foreach($dir in @($stage,$package,(Join-Path $source 'tools/native-ime'),(Join-Path $installed 'tools/native-ime'))){New-Item -ItemType Directory -Force $dir|Out-Null}
$context=@{Installed=$true;Root=$installed;State=@{PackageRoot=$package}}
try {
    $files=foreach($name in @('Meltype.Core.dll','Meltype.dll','NativeBroker.cs','MeltypeNative64.dll')){
        [IO.File]::WriteAllText((Join-Path $stage $name),'same payload')
        Copy-Item (Join-Path $stage $name) (Join-Path $package $name)
        @{Name=$name;SHA256=Get-NativeFileSha256 (Join-Path $stage $name)}
    }
    @{Files=@($files)}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $stage 'manifest.json')
    foreach($name in @('Host-NativeControlPanel.ps1','Update-NativeIme.ps1')){
        [IO.File]::WriteAllText((Join-Path $source ('tools/native-ime/'+$name)),'same script')
        Copy-Item (Join-Path $source ('tools/native-ime/'+$name)) (Join-Path $installed ('tools/native-ime/'+$name))
    }
    foreach($dir in @($source,$installed)){[IO.File]::WriteAllText((Join-Path $dir 'Meltype-Settings.exe'),'same launcher')}
    if(Test-NativeUpdateRequired $source $context){throw 'Identical installed release still offers Update'}
    # Run the real GUI timer callback against an identical installed package.
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Host-NativeControlPanel.ps1'),[ref]$tokens,[ref]$errors)
    if($errors){throw 'GUI parse failed'}
    $tick=$ast.Find({param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Member.Value -eq 'Add_Tick'},$true)
    if(-not $tick){throw 'GUI refresh callback missing'}
    $script:fixtureContext=$context
    function Get-NativeGuiContext { return $script:fixtureContext }
    $workspace=$source; $sid='fixture'; $script:actionProcess=$null
    $showEvent=[pscustomobject]@{}
    $showEvent|Add-Member ScriptMethod WaitOne {param($timeout) return $false}
    $buttons=@{Install=[pscustomobject]@{Enabled=$true};Update=[pscustomobject]@{Enabled=$true;Text='この版に更新'}}
    $status=[pscustomobject]@{Text=''}
    & $tick.Arguments[0].ScriptBlock.GetScriptBlock()
    if($buttons.Update.Enabled -or $buttons.Update.Text -ne 'この版は適用済み'){throw 'GUI timer re-enabled an identical installed update'}
    [IO.File]::WriteAllText((Join-Path $package 'Meltype.dll'),'older payload')
    if(-not (Test-NativeUpdateRequired $source $context)){throw 'Changed payload is not offered'}
    & $tick.Arguments[0].ScriptBlock.GetScriptBlock()
    if(-not $buttons.Update.Enabled -or $buttons.Update.Text -ne 'この版に更新'){throw 'GUI timer did not offer changed payload'}
    Copy-Item (Join-Path $stage 'Meltype.dll') (Join-Path $package 'Meltype.dll') -Force
    [IO.File]::WriteAllText((Join-Path $installed 'tools/native-ime/Host-NativeControlPanel.ps1'),'older GUI')
    if(-not (Test-NativeUpdateRequired $source $context)){throw 'GUI-only fix is not offered'}
    Copy-Item (Join-Path $source 'tools/native-ime/Host-NativeControlPanel.ps1') (Join-Path $installed 'tools/native-ime/Host-NativeControlPanel.ps1') -Force
    if(Test-NativeUpdateRequired $source $context){throw 'Successful update did not clear availability'}
    $registeredManifest=Get-Content (Join-Path $stage 'manifest.json') -Raw|ConvertFrom-Json
    $registeredManifest|Add-Member NoteProperty NativeRegistration 'Machine'
    $registeredManifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $stage 'manifest.json')
    if(-not(Test-NativeUpdateRequired $source $context)){throw 'Registration migration is not offered when payload bytes match'}
    $context.State.NativeRegistration='Machine'
    if(Test-NativeUpdateRequired $source $context){throw 'Completed registration migration still offers Update'}
    Sync-NativeInstalledUpdateSource $source $installed
    if(Test-NativeUpdateRequired $installed $context){throw 'Installed shortcut still offers an older update source'}
    $copied=Assert-NativeUpdatePackage (Join-Path $installed 'experimental-build/native-ime-package')
    if($copied.Files.Count -ne $files.Count){throw 'Installed update source is incomplete'}
    if(Test-NativeUpdateRequired $source @{Installed=$false}){throw 'Uninstalled machine offers Update'}
    Remove-Item (Join-Path $package 'MeltypeNative64.dll')
    if(-not (Test-NativeUpdateRequired $source $context)){throw 'Missing installed file is not repairable'}
    [IO.File]::WriteAllText((Join-Path $stage 'Meltype.dll'),'tampered payload')
    $rejected=$false
    try {Test-NativeUpdateRequired $source $context|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Tampered source is offered as an update'}
    Write-Output 'PASS: identical release disabled; binary/GUI/missing-file updates offered; completion disables again; tampered package rejected.'
}finally{
    $resolved=(Resolve-Path -LiteralPath $fixture).Path
    $allowed=(Resolve-Path -LiteralPath (Join-Path $root 'experimental-build')).Path+'\update-availability-'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
