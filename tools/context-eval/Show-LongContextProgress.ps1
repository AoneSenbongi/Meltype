param([Parameter(Mandatory)][string]$RunDirectory,[switch]$SelfTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2)|Out-Null
[Windows.Forms.Application]::EnableVisualStyles()
$form=[Windows.Forms.Form]::new()
$form.Text='Meltype 文脈評価テスト — 1000件'
$form.Size=[Drawing.Size]::new(940,720)
$form.MinimumSize=[Drawing.Size]::new(780,600)
$form.StartPosition='CenterScreen'
$form.Font=[Drawing.Font]::new('Yu Gothic UI',10)
$layout=[Windows.Forms.TableLayoutPanel]::new()
$layout.Dock='Fill';$layout.Padding=[Windows.Forms.Padding]::new(16);$layout.ColumnCount=1;$layout.RowCount=9
foreach($height in @(36,30,32,52,44,0,60,42,28)){
    if($height -eq 0){$style=[Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100)}else{$style=[Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,$height)}
    $layout.RowStyles.Add($style)|Out-Null
}
$form.Controls.Add($layout)
function AddLabel([string]$Text,[int]$Row){
    $label=[Windows.Forms.Label]::new();$label.Text=$Text;$label.Dock='Fill';$label.TextAlign='MiddleLeft';$layout.Controls.Add($label,0,$Row);return $label
}
$heading=AddLabel 'モデルを準備しています' 0
$heading.Font=[Drawing.Font]::new('Yu Gothic UI',15,[Drawing.FontStyle]::Bold)
$counts=AddLabel '本試験 0 / 1000件　評価用の別文脈 0 / 40件' 1
$progress=[Windows.Forms.ProgressBar]::new();$progress.Dock='Fill';$progress.Maximum=1040;$layout.Controls.Add($progress,0,2)
$timing=AddLabel '経過時間・残り時間を計測しています。' 3
$note=AddLabel '200の意味例 × 5変種を比較します。人工例での評価で、日常入力の正解率ではありません。' 4
$note.ForeColor=[Drawing.Color]::DimGray
$grid=[Windows.Forms.DataGridView]::new()
$grid.Dock='Fill';$grid.ReadOnly=$true;$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false
$grid.RowHeadersVisible=$false;$grid.AutoSizeColumnsMode='Fill';$grid.SelectionMode='FullRowSelect';$grid.BackgroundColor=[Drawing.SystemColors]::Window
foreach($pair in @(@('point','処理件数'),@('policy','履歴方式'),@('correct','別文脈40例の一致'),@('regressions','履歴による悪化'),@('memory','履歴の再利用'))){$grid.Columns.Add($pair[0],$pair[1])|Out-Null}
$grid.Columns['policy'].FillWeight=180
$layout.Controls.Add($grid,0,5)
$last=AddLabel '評価用40例を準備した後、100件・300件・1000件の経過を表示します。' 6
$buttons=[Windows.Forms.FlowLayoutPanel]::new();$buttons.Dock='Fill'
$folder=[Windows.Forms.Button]::new();$folder.Text='結果フォルダーを開く';$folder.AutoSize=$true
$folder.Add_Click({Start-Process explorer.exe -ArgumentList ('"'+$RunDirectory+'"')})
$stop=[Windows.Forms.Button]::new();$stop.Text='テストを停止';$stop.AutoSize=$true
$stop.Add_Click({[IO.File]::WriteAllText((Join-Path $RunDirectory 'cancel.request'),'user requested stop');$stop.Enabled=$false;$heading.Text='停止を要求しました。途中結果を保存しています。'})
$buttons.Controls.Add($folder);$buttons.Controls.Add($stop);$layout.Controls.Add($buttons,0,7)
$footer=AddLabel 'この画面を閉じてもテストは続きます。完了後にチャットへ「終わった」と伝えてください。' 8
$footer.Font=[Drawing.Font]::new('Yu Gothic UI',9)
$names=@{'none'='追加履歴なし';'all-commits'='全確定を記録';'explicit-only'='明示修正のみ';'contextual-explicit'='文脈一致の明示修正'}
function Duration($seconds){if($null -eq $seconds){return '計算中'};return [TimeSpan]::FromSeconds([Math]::Max(0,[double]$seconds)).ToString('hh\:mm\:ss')}
function ReadState{
    $path=Join-Path $RunDirectory 'status.json'
    foreach($name in @('terminal.json','results.json')){
        $candidate=Join-Path $RunDirectory $name
        if(Test-Path -LiteralPath $candidate){$path=$candidate;break}
    }
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader=[IO.StreamReader]::new($stream)
    try{return $reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
}
$script:lastUpdated=''
function RefreshProgress{
    try{
        $state=ReadState
        $heading.Text=$state.stage
        $counts.Text="本試験 $($state.processed) / 1000件　評価用の別文脈 $($state.probesProcessed) / 40件　要求失敗 $($state.failures)件"
        $progress.Value=[Math]::Min(1040,[Math]::Max(0,[int]$state.processed+[int]$state.probesProcessed))
        $remaining=if($state.status -in @('completed','completed_with_errors')){'00:00:00'}else{Duration $state.remainingSeconds}
        $timing.Text="経過 $(Duration $state.elapsedSeconds)　残り目安 $remaining`nモデル要求 $($state.modelRequests)件　応答中央値 $([Math]::Round([double]$state.medianMs))ms　p95 $([Math]::Round([double]$state.p95Ms))ms"
        $grid.Rows.Clear()
        foreach($row in $state.checkpoints){$grid.Rows.Add([string]$row.checkpoint,$names[$row.policy],"$($row.correct) / $($row.total)",[string]$row.regressions,[string]$row.memoryUses)|Out-Null}
        if($grid.Rows.Count -gt 4){$grid.FirstDisplayedScrollingRowIndex=$grid.Rows.Count-4}
        $last.Text="直近の読み　$($state.lastReading)`nモデル出力　$($state.lastChosen)　／　作成した正解　$($state.lastExpected)"
        $heading.ForeColor=[Drawing.SystemColors]::ControlText
        if($state.status -in @('completed','completed_with_errors','failed','cancelled')){
            $stop.Enabled=$false;$last.Text=$state.message
            $form.Text='Meltype 文脈評価テスト — '+$state.stage
            $heading.ForeColor=if($state.status -eq 'completed'){[Drawing.Color]::DarkGreen}else{[Drawing.Color]::DarkRed}
        }elseif($state.runnerPid -and -not(Get-Process -Id $state.runnerPid -ErrorAction SilentlyContinue)){
            $heading.Text='実行プロセスが見つかりません。途中結果を確認してください。';$heading.ForeColor=[Drawing.Color]::DarkRed
        }
        $script:lastUpdated=[DateTime]::Now.ToString('HH:mm:ss')
        $footer.Text="最終読込 $script:lastUpdated　画面を閉じても実行は続きます。終了後にチャットへ「終わった」と伝えてください。"
    }catch{
        $footer.Text="進捗ファイルの更新を待っています。最終読込 $script:lastUpdated"
    }
}
$timer=[Windows.Forms.Timer]::new();$timer.Interval=1000;$timer.Add_Tick({RefreshProgress})
$form.Add_Shown({
    RefreshProgress
    @{pid=$PID;visible=$form.Visible;title=$form.Text;handle=$form.Handle.ToInt64()}|ConvertTo-Json|Set-Content (Join-Path $RunDirectory 'gui-ready.json') -Encoding utf8
    $timer.Start()
    if($SelfTest){
        $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height);$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$bitmap.Save((Join-Path $RunDirectory 'gui-preview.png'));$bitmap.Dispose()
        $form.Close()
    }
})
$form.Add_FormClosed({$timer.Stop();$timer.Dispose()})
[void]$form.ShowDialog()
$form.Dispose()
