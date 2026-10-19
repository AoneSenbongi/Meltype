$ErrorActionPreference='Stop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('Meltype-inline-ui-'+[Guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
New-Item -ItemType Directory (Join-Path $fixture 'MeltypeNativeGoogle') -Force|Out-Null
$path=Join-Path $fixture 'MeltypeNativeGoogle/input-preferences.json'
[IO.File]::WriteAllText($path,'{"LearningEnabled":false,"DirectModeAutoDetect":false,"FutureOption":"keep"}')
$scriptPath=Join-Path $PSScriptRoot 'Host-NativeControlPanel.ps1'
$source=[IO.File]::ReadAllText($scriptPath)
$needle='$form.Show(); $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()'
if(-not $source.Contains($needle) -or $source.Contains('Windows.Forms.LinkLabel')){throw 'Inline panel or render hook does not match'}
$source=$source.Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))
$source=$source.Replace($needle,($needle+"`n"+@'
        $inputChecks.CalculatorCandidates.Checked=$false
        $inputChecks.EscStepsBack.Checked=$true
        $inputChecks.CursorIntoBrackets.Checked=$true
        $bindingText.Text='T=F6;Y=F7'
        $inputSave.PerformClick()
'@))
try {
    $env:LOCALAPPDATA=$fixture
    & ([scriptblock]::Create($source)) -RenderTo (Join-Path $fixture 'panel.png') -RenderInputBottom
    $saved=Get-Content $path -Raw|ConvertFrom-Json
    if($saved.CalculatorCandidates -or -not $saved.EscStepsBack -or -not $saved.CursorIntoBrackets -or $saved.ControlKeyBindings -ne 'T=F6;Y=F7'){throw 'Inline Save button did not save the selected values'}
    if($saved.LearningEnabled -or $saved.DirectModeAutoDetect -or $saved.FutureOption -ne 'keep'){throw 'Inline Save lost existing settings'}
    Write-Output 'PASS: main-window inline checkboxes and Control field saved by actual Save handler; existing fields retained; no separate settings link'
} finally {
    $env:LOCALAPPDATA=$oldLocal
    # Keep the small fixture for diagnostic review; it contains synthetic settings only.
}
