param()
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class MeltypeSearchTokenDiagnostics {
 [DllImport("kernel32",SetLastError=true)] static extern IntPtr OpenProcess(uint rights,bool inherit,int pid);
 [DllImport("kernel32")] static extern bool CloseHandle(IntPtr handle);
 [DllImport("advapi32",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint rights,out IntPtr token);
 [DllImport("advapi32",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr buffer,int length,out int needed);
 [DllImport("advapi32")] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
 [DllImport("advapi32")] static extern IntPtr GetSidSubAuthority(IntPtr sid,uint index);
 [DllImport("kernel32",CharSet=CharSet.Unicode)] static extern int GetPackageFamilyName(IntPtr process,ref uint length,System.Text.StringBuilder name);
 public static string Inspect(int pid) {
  var process=OpenProcess(0x1000,false,pid);
  if(process==IntPtr.Zero) return "ProcessQueryError="+Marshal.GetLastWin32Error();
  IntPtr token=IntPtr.Zero;
  try {
   if(!OpenProcessToken(process,8,out token)) return "TokenQueryError="+Marshal.GetLastWin32Error();
   int needed; var value=Marshal.AllocHGlobal(4);
   bool app=false; int level=-1;
   try {if(!GetTokenInformation(token,29,value,4,out needed))return "ContainerQueryError="+Marshal.GetLastWin32Error();app=Marshal.ReadInt32(value)!=0;}finally{Marshal.FreeHGlobal(value);}
   GetTokenInformation(token,25,IntPtr.Zero,0,out needed);
   value=Marshal.AllocHGlobal(needed);
   try {if(!GetTokenInformation(token,25,value,needed,out needed))return "IntegrityQueryError="+Marshal.GetLastWin32Error(); var sid=Marshal.ReadIntPtr(value);level=Marshal.ReadInt32(GetSidSubAuthority(sid,(uint)(Marshal.ReadByte(GetSidSubAuthorityCount(sid))-1)));}finally{Marshal.FreeHGlobal(value);}
   string packageSid="", family="";
   if(app) {
    GetTokenInformation(token,31,IntPtr.Zero,0,out needed);
    value=Marshal.AllocHGlobal(needed);
    try {if(!GetTokenInformation(token,31,value,needed,out needed))return "PackageSidQueryError="+Marshal.GetLastWin32Error();packageSid=new System.Security.Principal.SecurityIdentifier(Marshal.ReadIntPtr(value)).Value;}finally{Marshal.FreeHGlobal(value);}
    uint length=0;
    if(GetPackageFamilyName(process,ref length,null)==122) {
     var name=new System.Text.StringBuilder((int)length);
     if(GetPackageFamilyName(process,ref length,name)==0)family=name.ToString();
    }
   }
   return "AppContainer="+app+"; Integrity="+level+"; PackageFamily="+family+"; PackageSid="+packageSid;
  }finally{if(token!=IntPtr.Zero)CloseHandle(token);CloseHandle(process);}
 }
}
"@
$search = @(Get-CimInstance Win32_Process | Where-Object Name -match '^Search(App|UI|Host)\.exe$')
foreach ($process in $search) {
    $loaded = $null
    try { $loaded = [bool]((Get-Process -Id $process.ProcessId).Modules | Where-Object ModuleName -eq 'MeltypeNative64.dll') } catch { }
    [pscustomobject]@{Process=$process.Name;ProcessId=$process.ProcessId;Security=[MeltypeSearchTokenDiagnostics]::Inspect($process.ProcessId);NativeDllLoaded=$loaded}
}
$key='Software\Classes\CLSID\{F2D11628-2679-4DCC-9327-657EF2C1A450}\InprocServer32'
foreach ($hive in @('CurrentUser','LocalMachine')) {
    $registry=[Microsoft.Win32.Registry]::$hive.OpenSubKey($key)
    try { [pscustomobject]@{Hive=$hive;DllPath=if($registry){$registry.GetValue('')}else{$null}} } finally {if($registry){$registry.Dispose()}}
}
