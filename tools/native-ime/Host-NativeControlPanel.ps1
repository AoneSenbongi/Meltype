param([switch]$Tray, [string]$RenderTo)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2) | Out-Null
[Windows.Forms.Application]::EnableVisualStyles()
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$created = $false
$mutex = [Threading.Mutex]::new($false, ('Local\Meltype.NativePanel.' + $sid), [ref]$created)
$showEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, ('Local\Meltype.NativePanel.Show.' + $sid))
if (-not $created -and -not $RenderTo) { $showEvent.Set() | Out-Null; $mutex.Dispose(); $showEvent.Dispose(); return }
$form = [Windows.Forms.Form]::new()
$form.Text = 'Meltype 1.0.3 · Google日本語入力'
$form.ClientSize = [Drawing.Size]::new(600, 480)
$form.MinimumSize = [Drawing.Size]::new(616, 519)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::White
$form.Font = [Drawing.Font]::new('Yu Gothic UI', 10)
$form.Icon = [Drawing.SystemIcons]::Application
$layout = [Windows.Forms.TableLayoutPanel]::new()
$layout.Dock = 'Fill'; $layout.Padding = [Windows.Forms.Padding]::new(24)
$layout.ColumnCount = 2; $layout.RowCount = 9
foreach ($n in 0..1) { $layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,50)) | Out-Null }
$form.Controls.Add($layout)
function Add-Label([string]$Text, [int]$Row, [int]$Height = 34) {
    $label = [Windows.Forms.Label]::new(); $label.Text = $Text; $label.Dock = 'Fill'; $label.TextAlign = 'MiddleLeft'
    $layout.Controls.Add($label,0,$Row); $layout.SetColumnSpan($label,2)
    $layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,$Height)) | Out-Null
    return $label
}
$title = Add-Label 'Meltype · Google日本語入力' 0 42
$title.Font = [Drawing.Font]::new('Yu Gothic UI',18,[Drawing.FontStyle]::Bold)
$status = Add-Label '状態を確認しています…' 1 40
$hint = Add-Label '辞書・学習履歴は、このPCのGoogle日本語入力を使います。' 2 40
$hint.ForeColor = [Drawing.Color]::DimGray
$buttons = @{}
$script:actionProcess = $null; $script:resultFile = $null; $script:quitting = $false
function Start-Action([string]$Action) {
    if ($script:actionProcess) { return }
    try {
        $route = Get-NativeGuiAction $workspace $Action
        $script:resultFile = Join-Path $workspace ('experimental-build/gui-' + [Guid]::NewGuid().ToString('N') + '.json')
        New-Item -ItemType Directory (Split-Path $script:resultFile -Parent) -Force | Out-Null
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeGuiArgument (Join-Path $PSScriptRoot 'Invoke-NativeGuiAction.ps1')) + ' -Script ' + (ConvertTo-NativeGuiArgument $route.Script) + ' -ResultFile ' + (ConvertTo-NativeGuiArgument $script:resultFile)
        foreach ($argument in $route.Arguments) { $arguments += ' ' + $argument }
        $hostPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $parameters = @{ FilePath = $hostPath; ArgumentList = $arguments; WindowStyle = 'Hidden'; PassThru = $true }
        if ($route.Elevated) { $parameters.Verb = 'RunAs' }
        $script:actionProcess = Start-Process @parameters
        $message.Text = '処理中です。完了するまでお待ちください。'
        foreach ($button in $buttons.Values) { $button.Enabled = $false }
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Meltype',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null }
}
function Add-Button([string]$Text, [int]$Column, [int]$Row, [string]$Action) {
    $button = [Windows.Forms.Button]::new(); $button.Text = $Text; $button.Dock = 'Fill'; $button.Height = 46
    $button.Margin = [Windows.Forms.Padding]::new(4); $button.FlatStyle = 'System'
    $button.Add_Click({ Start-Action $Action }.GetNewClosure())
    $layout.Controls.Add($button,$Column,$Row); $buttons[$Action] = $button
    return $button
}
foreach ($row in 3..6) { $layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,50)) | Out-Null }
Add-Button 'インストール' 0 3 'Install' | Out-Null
Add-Button 'この版に更新' 1 3 'Update' | Out-Null
Add-Button '起動' 0 4 'Start' | Out-Null
Add-Button '停止してGoogleに戻る' 1 4 'Stop' | Out-Null
Add-Button '自動起動を有効にする' 0 5 'Enable' | Out-Null
Add-Button '自動起動を無効にする' 1 5 'Disable' | Out-Null
function Open-NativeGoogleDialog([string]$Mode) {
    try { Start-Process -FilePath (Get-NativeGoogleTool) -ArgumentList ('--mode='+$Mode) }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Meltype') | Out-Null }
}
foreach ($item in @(@('単語登録','word_register_dialog',0),@('辞書を管理','dictionary_tool',1))) {
    $button = [Windows.Forms.Button]::new(); $button.Text = $item[0]; $button.Dock = 'Fill'; $button.Margin = [Windows.Forms.Padding]::new(4)
    $mode = $item[1]
    $button.Add_Click({ Open-NativeGoogleDialog $mode }.GetNewClosure())
    $layout.Controls.Add($button,[int]$item[2],6)
}
$footer = [Windows.Forms.FlowLayoutPanel]::new(); $footer.Dock = 'Fill'
$layout.Controls.Add($footer,0,7); $layout.SetColumnSpan($footer,2)
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,42)) | Out-Null
foreach ($item in @(@('Googleの設定','Settings'),@('バックアップ','Backup'),@('削除','Uninstall'))) {
    $button = [Windows.Forms.Button]::new(); $button.Text = $item[0]; $button.AutoSize = $true; $operation = $item[1]
    $button.Add_Click({
        try {
            switch ($operation) {
                'Settings' { Start-Process (Get-NativeGoogleTool) -ArgumentList '--mode=config_dialog' }
                'Backup' { $root = (Get-NativeGuiContext $workspace).Root; $folder = Join-Path $root 'backups'; New-Item -ItemType Directory $folder -Force | Out-Null; Start-Process explorer.exe -ArgumentList (ConvertTo-NativeGuiArgument $folder) }
                'Uninstall' { if ([Windows.Forms.MessageBox]::Show('Native版の登録を削除し、Google日本語入力へ戻します。辞書と履歴は残ります。','Meltype','YesNo','Question') -eq 'Yes') { Start-Action 'Uninstall' } }
            }
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Meltype') | Out-Null }
    }.GetNewClosure())
    $footer.Controls.Add($button)
}
$message = Add-Label '画面を閉じると、タスクトレイに格納します。' 8 52
$message.ForeColor = [Drawing.Color]::DimGray
$icon = [Windows.Forms.NotifyIcon]::new(); $icon.Icon = $form.Icon; $icon.Text = 'Meltype · Google日本語入力'; $icon.Visible = -not [bool]$RenderTo
$menu = [Windows.Forms.ContextMenuStrip]::new()
$open = $menu.Items.Add('管理画面を開く'); $open.Add_Click({ $form.Show(); $form.Activate() })
function Add-NativeTrayActions([Windows.Forms.ContextMenuStrip]$Menu) {
    $stop = $Menu.Items.Add('停止してGoogleに戻る'); $stop.Add_Click({ Start-Action 'Stop' })
    foreach ($entry in @(@('単語登録','word_register_dialog'),@('辞書管理','dictionary_tool'))) {
        $item = $Menu.Items.Add($entry[0]); $mode = $entry[1]
        $item.Add_Click({ Open-NativeGoogleDialog $mode }.GetNewClosure())
    }
}
Add-NativeTrayActions $menu
$exit = $menu.Items.Add('管理画面を終了'); $exit.Add_Click({ $script:quitting = $true; $form.Close() })
$icon.ContextMenuStrip = $menu; $icon.Add_DoubleClick({ $form.Show(); $form.Activate() })
$form.Add_FormClosing({ if (-not $script:quitting -and -not $RenderTo -and $_.CloseReason -eq 'UserClosing') { $_.Cancel = $true; $form.Hide() } })
$timer = [Windows.Forms.Timer]::new(); $timer.Interval = 1000
$timer.Add_Tick({
    if ($showEvent.WaitOne(0)) { $form.Show(); $form.Activate() }
    if ($script:actionProcess -and $script:actionProcess.HasExited) {
        try {
            $result = Receive-NativeGuiActionCompletion ([ref]$script:actionProcess) ([ref]$script:resultFile)
            $message.Text = if ($result.Success) { '完了しました。' } else { '処理に失敗しました。' }
            if (-not $result.Success) { [Windows.Forms.MessageBox]::Show($result.Output,'Meltype') | Out-Null }
        } catch { $message.Text = '結果を確認できません：' + $_.Exception.Message }
    }
    if (-not $script:actionProcess) {
        try {
            $context = Get-NativeGuiContext $workspace
            $auto = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
            $autoEnabled = $auto -and $auto.PSObject.Properties['MeltypeNativeGoogle']
            $running = Test-Path -LiteralPath ('\\.\pipe\Meltype.NativeComposition.' + $sid)
            $status.Text = if ($context.Installed) { 'インストール済み  ·  入力サービス：' + $(if($running){'起動中'}else{'停止中'}) + '  ·  自動起動：' + $(if($autoEnabled){'有効'}else{'無効'}) } else { '未インストール' }
            foreach ($action in $buttons.Keys) { $buttons[$action].Enabled = if ($action -eq 'Install') { -not $context.Installed } else { $context.Installed } }
            $buttons.Update.Enabled = $false
            $buttons.Update.Enabled = Test-NativeUpdateRequired $workspace $context
            $buttons.Update.Text = if ($context.Installed -and -not $buttons.Update.Enabled) { 'この版は適用済み' } else { 'この版に更新' }
        } catch { $status.Text = '状態を確認できません：' + $_.Exception.Message }
    }
})
try {
    if ($RenderTo) {
        $status.Text = 'インストール済み  ·  入力サービス：起動中  ·  自動起動：有効'
        $form.Show(); $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()
        $bitmap = [Drawing.Bitmap]::new($form.Width,$form.Height)
        try { $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save($RenderTo,[Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    } else {
        $timer.Start()
        if ($Tray) { $form.Add_Shown({ $form.Hide() }) }
        [Windows.Forms.Application]::Run($form)
    }
} finally { $timer.Dispose(); $icon.Dispose(); $menu.Dispose(); $showEvent.Dispose(); $mutex.Dispose(); $form.Dispose() }
