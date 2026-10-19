$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('Meltype-input-settings-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
function Get-NativeInputPreferencesPath { return Join-Path $fixture 'input-preferences.json' }
try {
    $path=Get-NativeInputPreferencesPath
    [IO.File]::WriteAllText($path,'{"Comma":"、","Period":"。","LearningEnabled":false,"DirectModeAutoDetect":false,"FutureOption":"keep"}')
    $current=Get-NativeInputPreferences
    Save-NativeInputPreferences $current.Comma $current.Period $current.LearningEnabled -Options @{CalculatorCandidates=$false;EscStepsBack=$true;ControlKeyBindings='T=F6;Y=F7'}
    $saved=Get-NativeInputPreferences;$raw=[IO.File]::ReadAllText($path)|ConvertFrom-Json
    if($saved.CalculatorCandidates -or -not $saved.EscStepsBack -or $saved.LearningEnabled -or $saved.DirectModeAutoDetect -or $saved.ControlKeyBindings -ne 'T=F6;Y=F7' -or $raw.FutureOption -ne 'keep' -or $saved.Comma -ne '、'){throw 'New options or existing settings were lost'}
    $before=[IO.File]::ReadAllText($path);$rejected=$false
    try {Save-NativeInputPreferences $saved.Comma $saved.Period $saved.LearningEnabled -Options @{ControlKeyBindings='Q=Run'}} catch {$rejected=$true}
    if(-not $rejected -or [IO.File]::ReadAllText($path) -ne $before){throw 'Invalid key binding was accepted or changed the settings'}
    Write-Output 'PASS: new input options roundtrip, existing/unknown fields retained, invalid binding rejected without writing'
} finally {
    Remove-Item -LiteralPath (Join-Path $fixture 'input-preferences.json') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture
}
