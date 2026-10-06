param([switch]$Stop)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
[Reflection.Assembly]::LoadFrom((Join-Path $workspace 'experimental-build/Meltype.Core.dll')) | Out-Null
$app = [Reflection.Assembly]::LoadFrom((Join-Path $workspace 'experimental-build/Meltype.dll'))
if ($Stop) {
    $exit = $app.GetType('Meltype.ExitSignal').GetMethod('Send').Invoke($null, @())
    Write-Output "終了要求: $exit"
    return
}
$created = $false
$mutex = [Threading.Mutex]::new($true, 'Local\Meltype.SingleInstance', [ref]$created)
if (-not $created) { $mutex.Dispose(); return }
$engine = $null; $context = $null; $signal = $null
try {
    $app.GetType('Meltype.ApplicationConfiguration').GetMethod('Initialize', [Reflection.BindingFlags]'Static,NonPublic').Invoke($null, @()) | Out-Null
    $data = Join-Path $env:LOCALAPPDATA 'Meltype'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    $config = Join-Path $data 'config.json'
    $settings = [Meltype.Config.Settings]::Load($config)
    if (-not (Test-Path $config)) {
        $settings.ConversionEngine = [Meltype.Config.ConversionEngine]::Google
        $settings.AutoUpdate = $false
        $settings.WelcomeShown = $true
        $settings.FileLog = $true
        $settings.LogTypedText = $false
        $settings.Save($config)
    }
    $engine = $app.GetType('Meltype.MeltypeEngine').GetConstructors()[0].Invoke([object[]]@($settings,[string]$config,[string](Join-Path $data 'model.json'),[string](Join-Path $data 'dictionaries')))
    $engine.Start()
    $signal = [Activator]::CreateInstance($app.GetType('Meltype.ExitSignal'))
    $context = $app.GetType('Meltype.UI.TrayApplicationContext').GetConstructors()[0].Invoke([object[]]@($engine))
    $tray = $context.GetType().GetField('_tray', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($context)
    foreach ($item in @($tray.ContextMenuStrip.Items)) {
        if ($item.Text -in @('Windows の起動時に起動','更新','アンインストール...')) { $item.Visible = $false }
        if ($item.Text -eq 'バックアップ') {
            foreach ($child in @($item.DropDownItems)) { if ($child.Text -eq 'バックアップから戻す...') { $child.Visible = $false } }
        }
    }
    [IO.File]::WriteAllText((Join-Path $workspace 'experimental-build/resident.pid'), [string]$PID)
    [Windows.Forms.Application]::Run($context)
} finally {
    if ($context) { $context.Dispose() }
    if ($signal) { $signal.Dispose() }
    if ($engine) { $engine.Dispose() }
    if ($created) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
