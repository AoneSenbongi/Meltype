$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$fixture=Join-Path $env:TEMP ('Meltype-panel-test-'+[Guid]::NewGuid().ToString('N'))
$scripts=Join-Path $fixture 'tools/native-ime'
New-Item -ItemType Directory -Path $scripts -Force|Out-Null
$global:panelTestEvents=[Collections.Generic.List[string]]::new()
[IO.File]::WriteAllText((Join-Path $scripts 'Open-NativeControlPanel.ps1'),'$global:panelTestEvents.Add("OpenNew")')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$session=(Get-Process -Id $PID).SessionId
$panel=Join-Path $scripts 'Host-NativeControlPanel.ps1'
$global:panelFixture=@(
    @{ProcessId=101;Name='pwsh.exe';SessionId=$session;CommandLine=('-File "'+$panel+'"');Owner=$sid},
    @{ProcessId=102;Name='pwsh.exe';SessionId=$session;CommandLine=('-File "'+$panel+'"');Owner='other'},
    @{ProcessId=103;Name='pwsh.exe';SessionId=($session+1);CommandLine=('-File "'+$panel+'"');Owner=$sid},
    @{ProcessId=104;Name='pwsh.exe';SessionId=$session;CommandLine='-File C:\other\tools\native-ime\Host-NativeControlPanel.ps1';Owner=$sid},
    @{ProcessId=105;Name='pwsh.exe';SessionId=$session;CommandLine='-File C:\other\Host-NativeBroker.ps1';Owner=$sid},
    @{ProcessId=106;Name='pwsh.exe';SessionId=$session;CommandLine=$null;Owner=$sid})
function Get-CimInstance {return $global:panelFixture}
function Invoke-CimMethod($InputObject,$MethodName){return @{ReturnValue=0;Sid=$InputObject.Owner}}
function Stop-Process($Id){$global:panelTestEvents.Add('Stop:'+$Id)}
function Wait-Process($Id,$Timeout){}
try{
    Restart-NativeControlPanel $fixture $fixture
    if(($global:panelTestEvents -join ',') -ne 'Stop:101,OpenNew'){throw 'Restart touched other user/session/root or broker'}
    Write-Output 'PASS: old panel stops before new one opens; other user/session/root and broker are untouched'
    $global:panelTestEvents.Clear()
    Restart-NativeControlPanel $fixture $fixture 'C:\other'
    if(($global:panelTestEvents -join ',') -ne 'Stop:101,Stop:104,OpenNew'){throw 'Previous shortcut panel was not replaced when registration root differs'}
}finally{Remove-Item -LiteralPath (Join-Path $scripts 'Open-NativeControlPanel.ps1');Remove-Item -LiteralPath $scripts;Remove-Item -LiteralPath (Join-Path $fixture 'tools');Remove-Item -LiteralPath $fixture}
