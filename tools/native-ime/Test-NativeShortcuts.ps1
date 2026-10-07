$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'Set-NativeShortcuts.ps1'
$text=[IO.File]::ReadAllText($source)
if($text -notmatch "GetFolderPath\('DesktopDirectory'\)"){throw 'Desktop known folder is not used'}
if($text -notmatch 'NoDesktop'){throw 'Desktop opt-out is missing'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors){throw 'Shortcut script parse failed'}
$remove=$ast.Find({param($node)$node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq '$Remove'},$true)
if(-not $remove -or $remove.Extent.Text -notmatch 'desktopLink'){throw 'Uninstall does not remove the desktop shortcut'}
Write-Output 'PASS: desktop known folder, opt-out and uninstall cleanup'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture=Join-Path $root ('experimental-build/shortcut-test-'+[Guid]::NewGuid().ToString('N'))
$programs=Join-Path $fixture 'Programs'
$desktop=Join-Path $fixture 'Desktop'
New-Item -ItemType Directory -Force $programs,$desktop|Out-Null
$patched=$text.Replace("([Environment]::GetFolderPath('Programs'))",("'"+$programs.Replace("'","''")+"'"))
$patched=$patched.Replace("([Environment]::GetFolderPath('DesktopDirectory'))",("'"+$desktop.Replace("'","''")+"'"))
$run=[ScriptBlock]::Create($patched)
$menu=Join-Path $programs 'Meltype Google日本語入力/Meltypeの管理画面.lnk'
$linkPath=Join-Path $desktop 'Meltype Google日本語入力.lnk'
try {
    & $run -WorkspaceRoot $fixture
    if(-not(Test-Path $menu) -or -not(Test-Path $linkPath)){throw 'Install did not create both shortcuts'}
    $shell=New-Object -ComObject WScript.Shell
    try{
        $link=$shell.CreateShortcut($linkPath)
        if($link.TargetPath -ne (Join-Path $fixture 'Meltype-Settings.exe')){throw 'Wrong shortcut target'}
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)|Out-Null
    }finally{[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)|Out-Null}
    & $run -WorkspaceRoot $fixture -NoDesktop
    if(Test-Path $linkPath){throw 'Desktop opt-out was ignored'}
    & $run -WorkspaceRoot $fixture
    & $run -WorkspaceRoot $fixture -Remove
    if((Test-Path $menu) -or (Test-Path $linkPath)){throw 'Uninstall left shortcuts'}
    & $run -WorkspaceRoot (Join-Path $fixture 'Other')
    & $run -WorkspaceRoot $fixture -Remove
    if(-not(Test-Path $menu) -or -not(Test-Path $linkPath)){throw 'Another installation shortcut was removed'}
    & $run -WorkspaceRoot (Join-Path $fixture 'Other') -Remove
    Write-Output 'PASS: real COM shortcuts create/remove/opt-out and another installation is preserved. User desktop unchanged.'
}finally{
    foreach($file in Get-ChildItem -LiteralPath $fixture -Recurse -File){Remove-Item -LiteralPath $file.FullName}
    foreach($directory in Get-ChildItem -LiteralPath $fixture -Recurse -Directory|Sort-Object {$_.FullName.Length} -Descending){Remove-Item -LiteralPath $directory.FullName}
    Remove-Item -LiteralPath $fixture
}
