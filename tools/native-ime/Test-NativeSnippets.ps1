$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $root 'experimental-build'
[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.Core.dll'))|Out-Null
$app=[Reflection.Assembly]::LoadFrom((Join-Path $build 'Meltype.dll'))
Add-Type -AssemblyName System.Windows.Forms
$fixture=Join-Path $build ('snippet-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
$path=Join-Path $fixture 'snippets.json'
$store=[Meltype.Composition.SnippetStore]::new($path)
$flags=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$type=$app.GetType('Meltype.UI.SnippetsForm',$true)
$form=[Activator]::CreateInstance($type,$flags,$null,[object[]]@($store,[Func[string]]{';'}),$null)
try {
    $name=$type.GetField('_name',$flags).GetValue($form)
    $text=$type.GetField('_text',$flags).GetValue($form)
    $grid=$type.GetField('_grid',$flags).GetValue($form)
    $name.Text=';sig';$text.Text="署名`r`n担当者"
    $type.GetMethod('Register',$flags).Invoke($form,@())|Out-Null
    if([Meltype.Composition.SnippetStore]::new($path).Get('sig') -ne "署名`n担当者"){throw 'Official form registration/persistence failed'}
    $grid.Rows[0].Selected=$true
    $name.Text='sig';$text.Text="更新した署名`r`n担当者"
    $type.GetMethod('Register',$flags).Invoke($form,@())|Out-Null
    if($store.Get('sig') -ne "更新した署名`n担当者" -or $store.Count -ne 1){throw 'Official form edit failed'}
    $form.Show();[Windows.Forms.Application]::DoEvents()
    $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
    try{$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$bitmap.Save((Join-Path $build 'native-snippets-form.png'))}finally{$bitmap.Dispose()}
    $grid.Rows[0].Selected=$true
    $type.GetMethod('RemoveSelected',$flags).Invoke($form,@())|Out-Null
    if([Meltype.Composition.SnippetStore]::new($path).Count -ne 0){throw 'Official form removal failed'}
    $references=@((Join-Path $build 'Meltype.Core.dll'),(Join-Path $build 'Meltype.dll'))+@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll'|ForEach-Object FullName)
    Add-Type -Path (Join-Path $PSScriptRoot 'Generate-NativeCompositionTrace.cs') -ReferencedAssemblies $references
    $trace=Join-Path $build 'native-snippet-trace.bin'
    [NativeCompositionTrace]::RunSnippets($trace)
    & (Join-Path $build 'native-composition-test.exe') $trace
    if($LASTEXITCODE -ne 0){throw 'Snippets -> real TSF document verification failed'}
    # Compile the real broker against an isolated data directory for the transport test.
    $store.Set('sig',"googleで検索`n署名")|Out-Null
    $source=[IO.File]::ReadAllText((Join-Path $root 'native/tsf/NativeBroker.cs'))
    $original='private static readonly string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Meltype");'
    if(-not $source.Contains($original)){throw 'Broker fixture data-directory substitution no longer matches source'}
    $source=$source.Replace($original,('private static readonly string DataDirectory = @"'+$fixture.Replace('"','""')+'";'))
    $broker=Join-Path $fixture 'NativeBroker.cs';[IO.File]::WriteAllText($broker,$source)
    Add-Type -Path @($broker,(Join-Path $PSScriptRoot 'NativeSnippetTransportTest.cs')) -ReferencedAssemblies $references
    $trace=Join-Path $build 'native-snippet-broker-trace.bin'
    [NativeSnippetTransportTest]::Run($trace).GetAwaiter().GetResult()|Out-Null
    & (Join-Path $build 'native-composition-test.exe') $trace
    if($LASTEXITCODE -ne 0){throw 'Snippet broker transport -> real TSF document verification failed'}
    Write-Output 'PASS: official snippet form registration, edit, deletion, persistence; multiline expansion, Escape restore, Tab expansion, TSF commit/cancel; isolated profile.'
    Add-Type -Path (Join-Path $PSScriptRoot 'NativeSnippetWindowTest.cs')
    $launcher=Join-Path $PSScriptRoot 'Open-NativeSnippets.ps1'
    $process=Start-Process (Join-Path $PSHOME 'pwsh.exe') -ArgumentList ('-NoProfile -STA -File "'+$launcher+'"') -WindowStyle Hidden -PassThru
    try {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        do {Start-Sleep -Milliseconds 100;$visible=[NativeSnippetWindowTest]::Visible($process.Id)}while(-not $visible -and -not $process.HasExited -and $watch.Elapsed.TotalSeconds -lt 5)
        if(-not $visible){throw 'Snippet form remains hidden when launched by the management panel'}
        Write-Output 'PASS: snippet form is visible while its PowerShell console is hidden.'
    }finally{if(-not $process.HasExited){Stop-Process -Id $process.Id};$process.Dispose()}
}finally{$form.Dispose()}
