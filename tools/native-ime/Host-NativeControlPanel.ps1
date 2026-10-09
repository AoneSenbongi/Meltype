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
$form.Text = 'Meltype 1.0.7-rc.1 · Google日本語入力'
$form.ClientSize = [Drawing.Size]::new(600, 646)
$form.MinimumSize = [Drawing.Size]::new(616, 685)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::White
$form.Font = [Drawing.Font]::new('Yu Gothic UI', 10)
$form.Icon = [Drawing.SystemIcons]::Application
$layout = [Windows.Forms.TableLayoutPanel]::new()
$layout.Dock = 'Fill'; $layout.Padding = [Windows.Forms.Padding]::new(24)
$layout.ColumnCount = 2; $layout.RowCount = 12
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
function Show-NativeGuiError([string]$Details) {
    $text = Get-NativeGuiErrorMessage $Details
    try {
        $folder = Join-Path $workspace 'experimental-build'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $path = Join-Path $folder ('gui-error-' + [Guid]::NewGuid().ToString('N') + '.txt')
        [IO.File]::WriteAllText($path, $Details, [Text.UTF8Encoding]::new($false))
        $text += "`n`nエラーの詳細を保存しました：`n" + $path
    } catch { $text += "`n`nエラーの詳細を保存できませんでした。" }
    [Windows.Forms.MessageBox]::Show($text, 'Meltype', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
function Start-Action([string]$Action) {
    if ($script:actionProcess) { return }
    if ($buttons.ContainsKey($Action) -and -not $buttons[$Action].Enabled) { return }
    if ($Action -eq 'Uninstall' -and [Windows.Forms.MessageBox]::Show('Meltype Native版の登録、自動起動、ショートカットを削除してGoogle日本語入力へ戻します。Google日本語入力と辞書・学習履歴は残ります。続けますか？','Meltype',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2) -ne [Windows.Forms.DialogResult]::Yes) { return }
    try {
        $route = Get-NativeGuiAction $workspace $Action
        $script:pendingAction = $Action
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
        $autoToggle.Enabled = $false
    } catch { Show-NativeGuiError ($_ | Out-String) }
}
function Add-Button([string]$Text, [int]$Column, [int]$Row, [string]$Action) {
    $button = [Windows.Forms.Button]::new(); $button.Text = $Text; $button.Dock = 'Fill'; $button.Height = 46
    $button.Margin = [Windows.Forms.Padding]::new(4); $button.FlatStyle = 'Flat'; $button.FlatAppearance.BorderColor = [Drawing.Color]::LightGray
    $button.Add_Click({ Start-Action $Action }.GetNewClosure())
    $layout.Controls.Add($button,$Column,$Row); $buttons[$Action] = $button
    return $button
}
foreach ($row in 3..7) { $layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,50)) | Out-Null }
Add-Button 'インストール' 0 3 'Install' | Out-Null
(Add-Button 'アンインストール' 1 3 'Uninstall').Enabled = $false
Add-Button 'この版に更新' 0 4 'Update' | Out-Null
Add-Button '最新版を確認' 1 4 'ReleaseCheck' | Out-Null
(Add-Button '起動' 0 5 'Start').Enabled = $false
(Add-Button '停止してGoogleに戻る' 1 5 'Stop').Enabled = $false
$script:refreshingAutoStart = $false
$autoToggle = [Windows.Forms.CheckBox]::new()
$autoToggle.Text = 'Windows起動時に自動で起動する'
$autoToggle.Dock = 'Fill'; $autoToggle.Margin = [Windows.Forms.Padding]::new(8)
$autoToggle.Enabled = $false
$autoToggle.Add_CheckedChanged({
    if (-not $script:refreshingAutoStart -and -not $script:actionProcess) {
        Start-Action $(if ($autoToggle.Checked) { 'Enable' } else { 'Disable' })
    }
})
$layout.Controls.Add($autoToggle, 0, 6); $layout.SetColumnSpan($autoToggle, 2)
function Open-NativeGoogleDialog([string]$Mode) {
    try { Start-Process -FilePath (Get-NativeGoogleTool) -ArgumentList ('--mode='+$Mode) }
    catch { Show-NativeGuiError ($_ | Out-String) }
}
foreach ($item in @(@('単語登録','word_register_dialog',0),@('辞書を管理','dictionary_tool',1))) {
    $button = [Windows.Forms.Button]::new(); $button.Text = $item[0]; $button.Dock = 'Fill'; $button.Margin = [Windows.Forms.Padding]::new(4)
    $button.FlatStyle = 'Flat'; $button.FlatAppearance.BorderColor = [Drawing.Color]::LightGray
    $mode = $item[1]
    $button.Add_Click({ Open-NativeGoogleDialog $mode }.GetNewClosure())
    $layout.Controls.Add($button,[int]$item[2],7)
}
$footer = [Windows.Forms.FlowLayoutPanel]::new(); $footer.Dock = 'Fill'
$layout.Controls.Add($footer,0,10); $layout.SetColumnSpan($footer,2)
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,42)) | Out-Null
foreach ($item in @(@('Googleの設定','Settings'),@('バックアップ','Backup'))) {
    $button = [Windows.Forms.Button]::new(); $button.Text = $item[0]; $button.AutoSize = $true; $operation = $item[1]
    $button.Add_Click({
        try {
            switch ($operation) {
                'Settings' { Start-Process (Get-NativeGoogleTool) -ArgumentList '--mode=config_dialog' }
                'Backup' { $root = (Get-NativeGuiContext $workspace).Root; $folder = Join-Path $root 'backups'; New-Item -ItemType Directory $folder -Force | Out-Null; Start-Process explorer.exe -ArgumentList (ConvertTo-NativeGuiArgument $folder) }
            }
        } catch { Show-NativeGuiError ($_ | Out-String) }
    }.GetNewClosure())
    $footer.Controls.Add($button)
}
$punctuationRow = [Windows.Forms.FlowLayoutPanel]::new(); $punctuationRow.Dock = 'Fill'
$layout.Controls.Add($punctuationRow,0,8); $layout.SetColumnSpan($punctuationRow,2)
$layout.RowStyles.Insert(8,[Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,54))
function Add-PunctuationChoice([string]$Title,[string[]]$Values) {
    $label = [Windows.Forms.Label]::new(); $label.Text=$Title; $label.AutoSize=$true; $label.Margin=[Windows.Forms.Padding]::new(4,10,4,4)
    $punctuationRow.Controls.Add($label)
    $choice=[Windows.Forms.ComboBox]::new(); $choice.DropDownStyle='DropDownList'; $choice.Width=128
    foreach($value in $Values){$choice.Items.Add($value) | Out-Null}
    $punctuationRow.Controls.Add($choice); return $choice
}
$commaValues=@('、','，',',');$periodValues=@('。','．','.')
$commaChoice=Add-PunctuationChoice '読点' @('、（読点）','，（全角カンマ）',',（半角カンマ）')
$periodChoice=Add-PunctuationChoice '句点' @('。（句点）','．（全角ピリオド）','.（半角ピリオド）')
$punctuationSave=[Windows.Forms.Button]::new();$punctuationSave.Text='句読点を保存';$punctuationSave.AutoSize=$true
$punctuationSave.Add_Click({
    try {
        $current=Get-NativeInputPreferences
        Save-NativeInputPreferences $commaValues[$commaChoice.SelectedIndex] $periodValues[$periodChoice.SelectedIndex] $current.LearningEnabled
        $message.Text='句読点を保存しました。次の入力から反映します。'
    } catch { Show-NativeGuiError ($_ | Out-String) }
});$punctuationRow.Controls.Add($punctuationSave)
$preferences=Get-NativeInputPreferences
$commaChoice.SelectedIndex=[Array]::IndexOf($commaValues,$preferences.Comma);$periodChoice.SelectedIndex=[Array]::IndexOf($periodValues,$preferences.Period)
$learningStatus=[Windows.Forms.Label]::new();$learningStatus.Dock='Fill';$learningStatus.TextAlign='MiddleLeft'
$layout.Controls.Add($learningStatus,0,9)
$learningButton=[Windows.Forms.Button]::new();$learningButton.Dock='Fill';$learningButton.Margin=[Windows.Forms.Padding]::new(4);$learningButton.FlatStyle='Flat'
$learningButton.Add_Click({
    try {
        $current=Get-NativeInputPreferences
        Save-NativeInputPreferences $current.Comma $current.Period (-not $current.LearningEnabled)
        Refresh-NativeLearningState
        $message.Text='学習設定を保存しました。既存の辞書・履歴は残ります。'
    } catch { Show-NativeGuiError ($_ | Out-String) }
});$layout.Controls.Add($learningButton,1,9)
$layout.RowStyles.Insert(9,[Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,54))
function Refresh-NativeLearningState {
    $current=Get-NativeInputPreferences
    $learningStatus.Text=if($current.LearningEnabled){'Meltype経由の学習：有効'}else{'Meltype経由の学習：停止中'}
    $learningButton.Text=if($current.LearningEnabled){'学習を停止'}else{'学習を再開'}
}
Refresh-NativeLearningState
$message = Add-Label '画面を閉じると、タスクトレイに格納します。' 11 52
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
    if($learningButton){Refresh-NativeLearningState}
    if ($showEvent.WaitOne(0)) { $form.Show(); $form.Activate() }
    if ($script:actionProcess -and $script:actionProcess.HasExited) {
        try {
            $result = Receive-NativeGuiActionCompletion ([ref]$script:actionProcess) ([ref]$script:resultFile)
            $message.Text = if ($result.Success) { '完了しました。' } else { '処理に失敗しました。' }
            if (-not $result.Success) { Show-NativeGuiError $result.Output }
            elseif($script:pendingAction -eq 'ReleaseCheck') {
                $release=$result.Output|ConvertFrom-Json
                if($release.Available) {
                    $message.Text='最新版 '+$release.Version+' を利用できます。'
                    if([Windows.Forms.MessageBox]::Show('Meltype '+$release.Version+'へ更新します。ダウンロード後、バックアップとセットアップを実行します。必要なWindowsの管理者確認を承認してください。','Meltypeの更新','YesNo','Question') -eq 'Yes'){Start-Action 'ReleaseInstall'}
                }else{$message.Text='新しい公開版はありません。'}
            }
        } catch { $message.Text = Get-NativeGuiErrorMessage ($_ | Out-String) }
    }
    if (-not $script:actionProcess) {
        try {
            foreach ($button in $buttons.Values) { $button.Enabled = $false }
            if ($autoToggle) { $autoToggle.Enabled = $false }
            $context = Get-NativeGuiContext $workspace
            $auto = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
            $autoEnabled = $auto -and $auto.PSObject.Properties['MeltypeNativeGoogle']
            $running = Test-NativeBrokerRunning $sid
            $status.Text = if ($context.Installed) { 'インストール済み  ·  入力サービス：' + $(if($running){'起動中'}else{'停止中'}) + '  ·  自動起動：' + $(if($autoEnabled){'有効'}else{'無効'}) } else { '未インストール' }
            foreach ($action in $buttons.Keys) { $buttons[$action].Enabled = if ($action -eq 'Install') { -not $context.Installed } else { $context.Installed } }
            if ($buttons.ContainsKey('Start')) { $buttons.Start.Enabled = $context.Installed -and -not $running }
            if ($buttons.ContainsKey('Stop')) { $buttons.Stop.Enabled = $context.Installed -and $running }
            if ($autoToggle) {
                $script:refreshingAutoStart = $true
                try {
                    $autoToggle.Checked = [bool]($context.Installed -and $autoEnabled)
                    $autoToggle.Enabled = [bool]$context.Installed
                } finally { $script:refreshingAutoStart = $false }
            }
            $buttons.Update.Enabled = $false
            $buttons.Update.Enabled = Test-NativeUpdateRequired $workspace $context
            $buttons.Update.Text = if ($context.Installed -and -not $buttons.Update.Enabled) { 'この版は適用済み' } else { 'この版に更新' }
        } catch { foreach ($button in $buttons.Values) { $button.Enabled = $false }; if ($autoToggle) { $autoToggle.Enabled = $false }; $status.Text = '状態を確認できません。少し待ってから画面を開き直してください。' }
    }
})
try {
    if ($RenderTo) {
        $status.Text = 'インストール済み  ·  入力サービス：起動中  ·  自動起動：有効'
        $buttons.Install.Enabled = $false; $buttons.Start.Enabled = $false; $buttons.Stop.Enabled = $true
        $buttons.Uninstall.Enabled = $true
        $script:refreshingAutoStart = $true
        try { $autoToggle.Checked = $true; $autoToggle.Enabled = $true } finally { $script:refreshingAutoStart = $false }
        $form.Show(); $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()
        $bitmap = [Drawing.Bitmap]::new($form.Width,$form.Height)
        try { $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save($RenderTo,[Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    } else {
        $timer.Start()
        if ($Tray) { $form.Add_Shown({ $form.Hide() }) }
        [Windows.Forms.Application]::Run($form)
    }
} finally { $timer.Dispose(); $icon.Dispose(); $menu.Dispose(); $showEvent.Dispose(); $mutex.Dispose(); $form.Dispose() }
