$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$fixtureRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ('experimental-build/preferences-test-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$script:fixturePath = Join-Path $fixtureRoot 'input-preferences.json'
function Get-NativeInputPreferencesPath { return $script:fixturePath }
try {
    foreach ($comma in @('、','，',',')) {
        foreach ($period in @('。','．','.')) {
            foreach ($learning in @($false,$true)) {
                Save-NativeInputPreferences $comma $period $learning
                $actual = Get-NativeInputPreferences
                if ($actual.Comma -cne $comma -or $actual.Period -cne $period -or $actual.LearningEnabled -ne $learning) { throw 'Preferences did not round-trip.' }
            }
        }
    }
    [IO.File]::WriteAllText($script:fixturePath,'broken')
    if ((Get-NativeInputPreferences).LearningEnabled) { throw 'Invalid settings must stop learning.' }
    Write-Output 'PASS: punctuation combinations, learning stop/resume, invalid settings'
} finally {
    if ([IO.File]::Exists($script:fixturePath)) { [IO.File]::Delete($script:fixturePath) }
    [IO.Directory]::Delete($fixtureRoot)
}
