$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Host-NativeControlPanel.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw 'GUI parse failed'}
$tick=$ast.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_Tick'},$true)
function Get-NativeGuiContext {return @{Installed=$true}}
function Test-NativeUpdateRequired {return $false}
function Get-ItemProperty {return $null}
function Test-Path {param($LiteralPath) return $script:fixtureRunning}
$workspace='fixture'; $sid='fixture'; $script:actionProcess=$null
$showEvent=[pscustomobject]@{}; $showEvent|Add-Member ScriptMethod WaitOne {param($timeout) return $false}
$status=[pscustomobject]@{Text=''}
$buttons=@{}
foreach($key in @('Install','Update','Start','Stop','Enable','Disable')){$buttons[$key]=[pscustomobject]@{Enabled=$true;Text=''}}
foreach($running in @($true,$false)){
 $script:fixtureRunning=$running
 & $tick.Arguments[0].ScriptBlock.GetScriptBlock()
 if($buttons.Start.Enabled -eq $running -or $buttons.Stop.Enabled -ne $running){throw "Start/Stop buttons do not match running=$running"}
}
$errorText="Protected package operation did not return a result.`n発生場所 C:\fixture.ps1:44`n+ throw failure`nFullyQualifiedErrorId: failure"
$human=Get-NativeGuiErrorMessage $errorText
if($human -match 'Protected package|FullyQualified|発生場所|throw' -or $human -notmatch '管理者' -or $human -notmatch '確認'){throw 'Raw protected package failure remains in user message'}
$cancel=Get-NativeGuiErrorMessage 'The operation was canceled by the user. (1223)'
if($cancel -notmatch 'キャンセル'){throw 'Cancellation is not explained'}
$unknown=Get-NativeGuiErrorMessage 'unexpected technical failure'
if($unknown -match 'unexpected' -or $unknown -notmatch 'もう一度'){throw 'Unknown failure is not actionable'}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$layout=[Windows.Forms.TableLayoutPanel]::new()
try{
 $dictionary=$ast.Find({param($n) $n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text -like '*word_register_dialog*' -and $n.Extent.Text -like '*$layout.Controls.Add*'},$true)
 & ([scriptblock]::Create($dictionary.Extent.Text))
 foreach($button in $layout.Controls){
  if($button.FlatStyle -ne [Windows.Forms.FlatStyle]::Flat -or $button.FlatAppearance.BorderColor.ToArgb() -ne [Drawing.Color]::LightGray.ToArgb() -or -not $button.TabStop){throw 'Dictionary buttons still have default blue focus styling or lost keyboard access'}
 }
}finally{$layout.Dispose()}
Write-Output 'PASS: running/stopped buttons, Japanese error guidance and neutral dictionary styling'
