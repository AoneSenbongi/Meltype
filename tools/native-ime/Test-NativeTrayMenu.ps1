$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Host-NativeControlPanel.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Management script has syntax errors.' }
$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Add-NativeTrayActions' }, $true)
if (-not $definition) { throw 'Tray action menu is missing.' }
. ([scriptblock]::Create($definition.Extent.Text))
$script:calls = [Collections.Generic.List[string]]::new()
function Start-Action([string]$Action) { $script:calls.Add($Action) }
function Open-NativeGoogleDialog([string]$Mode) { $script:calls.Add($Mode) }
$menu = [Windows.Forms.ContextMenuStrip]::new()
try {
    Add-NativeTrayActions $menu
    if (($menu.Items | ForEach-Object Text) -join ',' -ne '停止してGoogleに戻る,単語登録,辞書管理') { throw 'Unexpected tray menu entries.' }
    foreach ($item in $menu.Items) { $item.PerformClick() }
    if ($script:calls -join ',' -ne 'Stop,word_register_dialog,dictionary_tool') { throw ('Wrong tray action: '+($script:calls -join ',')) }
    Write-Output 'PASS: tray menu clicks route to Stop and the two Google dictionary dialogs.'
} finally { $menu.Dispose() }
$dialog = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Open-NativeGoogleDialog' }, $true)
if (-not $dialog) { throw 'Google dialog launcher is missing.' }
. ([scriptblock]::Create($dialog.Extent.Text))
function Get-NativeGoogleTool { 'C:\Google\GoogleIMEJaTool.exe' }
function Start-Process([string]$FilePath, [string]$ArgumentList) { $script:calls.Add($FilePath+'|'+$ArgumentList) }
$script:calls.Clear()
Open-NativeGoogleDialog 'word_register_dialog'
Open-NativeGoogleDialog 'dictionary_tool'
if ($script:calls -join ',' -ne 'C:\Google\GoogleIMEJaTool.exe|--mode=word_register_dialog,C:\Google\GoogleIMEJaTool.exe|--mode=dictionary_tool') { throw 'Google dictionary launch arguments are incorrect.' }
Write-Output 'PASS: word registration and dictionary management launch the Google tool with the correct modes.'
