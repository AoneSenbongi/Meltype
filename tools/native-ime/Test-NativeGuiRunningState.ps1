$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Host-NativeControlPanel.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw 'GUI parse failed'}
$tick=$ast.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_Tick'},$true)
$workspace='fixture';$sid='Test.'+[Guid]::NewGuid().ToString('N')
$script:actionProcess=$null;$script:contextFailure=$false
function Get-NativeGuiContext {if($script:contextFailure){throw 'fixture state failure'};return @{Installed=$true}}
function Test-NativeUpdateRequired {if($script:updateFailure){throw 'fixture update failure'};return $false}
function Get-ItemProperty {return $null}
# Reproduce pipe-based status failing even though the service owns its start mutex.
function Test-Path {param($LiteralPath) return $false}
$showEvent=[pscustomobject]@{};$showEvent|Add-Member ScriptMethod WaitOne {param($timeout) return $false}
$status=[pscustomobject]@{Text=''};$autoToggle=[pscustomobject]@{Enabled=$true;Checked=$false}
$buttons=@{}
foreach($key in @('Install','Uninstall','Update','Start','Stop')){$buttons[$key]=[pscustomobject]@{Enabled=$true;Text=''}}
$mutex=[Threading.Mutex]::new($true,('Local\Meltype.NativeComposition.'+$sid+'.Mutex'))
try {
 & $tick.Arguments[0].ScriptBlock.GetScriptBlock()
 if($buttons.Start.Enabled -or -not $buttons.Stop.Enabled){throw 'Running broker with unavailable pipe leaves Start enabled'}
} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
& $tick.Arguments[0].ScriptBlock.GetScriptBlock()
if(-not $buttons.Start.Enabled -or $buttons.Stop.Enabled){throw 'Stopped broker button states are wrong'}
$script:contextFailure=$true
& $tick.Arguments[0].ScriptBlock.GetScriptBlock()
if(@($buttons.Values|Where-Object Enabled).Count -or $autoToggle.Enabled){throw 'Failed status refresh leaves stale actions enabled'}
$script:contextFailure=$false;$script:updateFailure=$true
& $tick.Arguments[0].ScriptBlock.GetScriptBlock()
if(@($buttons.Values|Where-Object Enabled).Count -or $autoToggle.Enabled){throw 'Failed update check re-enables actions'}
Write-Output 'PASS: running mutex without available pipe, stopped state and failed refresh; isolated service name only'
