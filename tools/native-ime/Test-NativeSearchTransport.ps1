param([string]$Compiler='E:/prog/w64devkit/bin/g++.exe')
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $workspace 'experimental-build'
$fixture=Join-Path $build ('search-transport-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
$probe=Join-Path $fixture 'sandbox-probe.exe'
& $Compiler -std=c++17 -Wall -Wextra -Werror -municode -static -static-libgcc -static-libstdc++ (Join-Path $workspace 'native/tsf/NativeSandboxProbe.cpp') -luserenv -ladvapi32 -o $probe
if($LASTEXITCODE -ne 0){throw 'Sandbox probe compilation failed'}
$dll=Join-Path $fixture 'sandbox-test.dll'
Copy-Item -LiteralPath (Join-Path $build 'MeltypeNative64.dll') -Destination $dll
$core=Join-Path $build 'Meltype.Core.dll';$app=Join-Path $build 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core)|Out-Null
[Reflection.Assembly]::LoadFrom($app)|Out-Null
$references=@($core,$app)+@(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll'|ForEach-Object FullName)
$harness=@'
public static class SearchTransportHarness {
 public static async System.Threading.Tasks.Task Convert(System.IO.Pipes.NamedPipeServerStream pipe,string sid) {
  using var cancel=new System.Threading.CancellationTokenSource(12000);
  await pipe.WaitForConnectionAsync(cancel.Token);
  await MeltypeNativeBroker.Serve(pipe,false,cancel.Token,sid);
 }
 public static async System.Threading.Tasks.Task<bool> Accept(System.IO.Pipes.NamedPipeServerStream pipe,string sid) {
  using var cancel=new System.Threading.CancellationTokenSource(5000);
  try {
   await pipe.WaitForConnectionAsync(cancel.Token);
   if(!MeltypeNativeBroker.IsTrustedClient(pipe,sid)) {pipe.Dispose();return false;}
   var bytes=new byte[1];
   await pipe.ReadExactlyAsync(bytes,cancel.Token);
   if(bytes[0]!=42) return false;
   bytes[0]=43;await pipe.WriteAsync(bytes,cancel.Token);await pipe.FlushAsync(cancel.Token);
   return true;
  }catch(System.OperationCanceledException){return false;}
 }
}
'@
Add-Type -TypeDefinition ((Get-Content (Join-Path $workspace 'native/tsf/NativeBroker.cs') -Raw)+$harness) -ReferencedAssemblies $references
$family=[MeltypeNativeBroker]::SearchPackageForBuild([Environment]::OSVersion.Version.Build)
$expectedSid=if([Environment]::OSVersion.Version.Build -ge 22000){'S-1-15-2-283421221-3183566570-1718213290-751554359-3541592344-2312209569-3374928651'}else{'S-1-15-2-536077884-713174666-1066051701-3219990555-339840825-1966734348-1611281757'}
if([MeltypeNativeBroker]::SearchPackageSid -ne $expectedSid){throw 'Derived SID does not match the observed Windows Search identity'}
$results=@()
foreach($case in @('Allowed','AclDenied','IdentityDenied')) {
 $profile='Meltype.Search.Test.'+[Guid]::NewGuid().ToString('N')
 $sid=[MeltypeNativeBroker]::PackageSid($profile)
 $other=[MeltypeNativeBroker]::PackageSid($profile+'.Other')
 [MeltypeNativeBroker]::AllowSearchPeerQuery($sid)
 $name='Meltype.Search.Test.'+[Guid]::NewGuid().ToString('N')
 $allowedSid=if($case -eq 'AclDenied'){$other}else{$sid}
 $expectedSid=if($case -eq 'IdentityDenied'){$other}else{$sid}
 $listener=[MeltypeNativeBroker]::CreateSearchListener($name,$true,$allowedSid)
 try {
  $accept=[SearchTransportHarness]::Accept($listener,$expectedSid)
  $output=& $probe --external-pipe $name $profile $dll
  if($LASTEXITCODE -ne 0){throw 'Sandbox setup failed'}
  $result=$output|ConvertFrom-Json
  if(-not $accept.Wait(6500)){throw 'Server did not finish its bounded test'}
  if($case -eq 'Allowed') {
   if($result.pipeConnectError -ne 0 -or -not $result.serverAuthorized -or -not $result.dllTrustedServer -or -not $accept.Result){throw 'Allowed sandbox did not pass both identity checks and byte exchange'}
   if($result.extraServerError -ne 5){throw 'Sandbox can create an extra pipe server'}
  }elseif($case -eq 'AclDenied') {
   if($result.pipeConnectError -ne 5 -or $accept.Result){throw 'Unrelated sandbox was not denied at the ACL'}
  }else {
   if($result.pipeConnectError -ne 0 -or $result.serverAuthorized -or $accept.Result){throw 'Transport permission bypassed client identity validation'}
  }
  $results += [pscustomobject]@{Case=$case;Result=$result;ClientAuthorized=$accept.Result}
 }finally{$listener.Dispose()}
}
# The production listener must reject an already occupied pipe name too.
$name='Meltype.Search.Test.'+[Guid]::NewGuid().ToString('N')
$occupied=[MeltypeNativeBroker]::CreateListener($name,$true)
try {
 $rejected=$false
 try{$unexpected=[MeltypeNativeBroker]::CreateSearchListener($name,$true,[MeltypeNativeBroker]::SearchPackageSid);$unexpected.Dispose()}
 catch [UnauthorizedAccessException]{$rejected=$true}
 if(-not $rejected){throw 'Search listener accepted an occupied pipe name'}
}finally{$occupied.Dispose()}
$results|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $build 'search-transport-result.json') -Encoding utf8
$profile='Meltype.Search.Test.'+[Guid]::NewGuid().ToString('N')
$sid=[MeltypeNativeBroker]::PackageSid($profile)
[MeltypeNativeBroker]::AllowSearchPeerQuery($sid)
$name='Meltype.Search.Test.'+[Guid]::NewGuid().ToString('N')
$listener=[MeltypeNativeBroker]::CreateSearchListener($name,$true,$sid)
try {
 $convert=[SearchTransportHarness]::Convert($listener,$sid)
 $output=& $probe --external-conversion $name $profile $dll
 if($LASTEXITCODE -ne 0){throw 'Conversion sandbox setup failed'}
 $conversion=$output|ConvertFrom-Json
 if(-not $convert.Wait(15000)){throw 'Conversion service did not finish'}
 if(-not $conversion.appContainer -or -not $conversion.conversionSucceeded){throw 'AppContainer -> native DLL -> production broker -> Google live/candidates/commit failed'}
 $conversion|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $build 'search-google-conversion-result.json') -Encoding utf8
}finally{$listener.Dispose()}
Write-Output 'PASS: production listener + AppContainer + native DLL: both identity checks, byte exchange, wrong package denial, extra server denial, occupied name denial. Installed IME unchanged.'
Write-Output 'PASS: AppContainer -> native DLL -> production conversion controller -> Google: live preedit, Space candidates, Enter commits Japanese. Learning disabled in this isolated test.'
# Keep this small fixture on E as verification evidence; all AppContainer profiles were removed by the probe.
