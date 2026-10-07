// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental broker for an in-process TSF frontend. Uses the existing Meltype controller.
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Security.Principal;
using System.Security.AccessControl;
using System.Runtime.InteropServices;
using System.ComponentModel;
using Microsoft.Win32.SafeHandles;
using Meltype.Composition;
using Meltype.Input;

public static class MeltypeNativeBroker
{
    // This Windows 10 package was verified from SearchApp's token and package identity.
    public static string SearchPackageSid => PackageSid("Microsoft.Windows.Search_cw5n1h2txyewy");
    [StructLayout(LayoutKind.Sequential)] private struct SecurityAttributes { public int Length; public IntPtr Descriptor; public int Inherit; }
    [DllImport("userenv",CharSet=CharSet.Unicode)] private static extern int DeriveAppContainerSidFromAppContainerName(string name,out IntPtr sid);
    [DllImport("advapi32")] private static extern IntPtr FreeSid(IntPtr sid);
    [DllImport("kernel32")] private static extern IntPtr LocalFree(IntPtr value);
    [DllImport("kernel32")] private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32",SetLastError=true)] private static extern IntPtr OpenProcess(uint rights,bool inherit,uint pid);
    [DllImport("kernel32")] private static extern bool CloseHandle(IntPtr value);
    [DllImport("advapi32",SetLastError=true)] private static extern bool OpenProcessToken(IntPtr process,uint rights,out IntPtr token);
    [DllImport("advapi32",SetLastError=true)] private static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,int length,out int needed);
    [DllImport("advapi32")] private static extern uint GetSecurityInfo(IntPtr value,int kind,uint info,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
    [DllImport("advapi32")] private static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
    [DllImport("advapi32",SetLastError=true)] private static extern bool GetSecurityDescriptorDacl(IntPtr descriptor,out bool present,out IntPtr dacl,out bool defaulted);
    [DllImport("advapi32")] private static extern uint SetSecurityInfo(IntPtr value,int kind,uint info,IntPtr owner,IntPtr group,IntPtr dacl,IntPtr sacl);
    [DllImport("advapi32",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string text,uint revision,out IntPtr descriptor,out uint bytes);
    [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr CreateNamedPipe(string name,uint mode,uint type,uint instances,uint output,uint input,uint timeout,ref SecurityAttributes attributes);
    [DllImport("kernel32",SetLastError=true)] private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe,out uint pid);

    public static string PackageSid(string name)
    {
        var result=DeriveAppContainerSidFromAppContainerName(name,out var sid);
        if(result<0) Marshal.ThrowExceptionForHR(result);
        try { return new SecurityIdentifier(sid).Value; } finally { FreeSid(sid); }
    }
    private static void GrantQuery(IntPtr handle,string packageSid,int rights)
    {
        var result=GetSecurityInfo(handle,6,4,out _,out _,out _,out _,out var descriptor);
        if(result!=0) throw new Win32Exception((int)result);
        try {
            var bytes=new byte[GetSecurityDescriptorLength(descriptor)];
            Marshal.Copy(descriptor,bytes,0,bytes.Length);
            var security=new RawSecurityDescriptor(bytes,0);
            if(security.DiscretionaryAcl==null) throw new UnauthorizedAccessException("Missing object ACL");
            security.DiscretionaryAcl.InsertAce(0,new CommonAce(AceFlags.None,AceQualifier.AccessAllowed,rights,new SecurityIdentifier(packageSid),false,null));
            bytes=new byte[security.BinaryLength]; security.GetBinaryForm(bytes,0);
            var updated=Marshal.AllocHGlobal(bytes.Length);
            try {
                Marshal.Copy(bytes,0,updated,bytes.Length);
                if(!GetSecurityDescriptorDacl(updated,out var present,out var acl,out _) || !present) throw new UnauthorizedAccessException("Missing updated ACL");
                result=SetSecurityInfo(handle,6,4,IntPtr.Zero,IntPtr.Zero,acl,IntPtr.Zero);
                if(result!=0) throw new Win32Exception((int)result);
            } finally { Marshal.FreeHGlobal(updated); }
        } finally { LocalFree(descriptor); }
    }
    public static void AllowSearchPeerQuery(string packageSid)
    {
        GrantQuery(GetCurrentProcess(),packageSid,0x1000);
        if(!OpenProcessToken(GetCurrentProcess(),0x60008,out var token)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try { GrantQuery(token,packageSid,8); } finally { CloseHandle(token); }
    }
    public static NamedPipeServerStream CreateSearchListener(string name,bool first,string packageSid)
    {
        // 0x12019b excludes FILE_CREATE_PIPE_INSTANCE. Keep remote clients out.
        var user=WindowsIdentity.GetCurrent().User.Value;
        var sddl="D:P(A;;GA;;;"+user+")(A;;0x12019b;;;"+new SecurityIdentifier(packageSid).Value+")S:(ML;;NW;;;LW)";
        if(!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl,1,out var descriptor,out _)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            var attributes=new SecurityAttributes {Length=Marshal.SizeOf<SecurityAttributes>(),Descriptor=descriptor};
            var raw=CreateNamedPipe(@"\\.\pipe\"+name,3|0x40000000u|(first?0x80000u:0),8,32,4096,4096,0,ref attributes);
            if(raw==new IntPtr(-1)) {
                var error=Marshal.GetLastWin32Error();
                if(error==5) throw new UnauthorizedAccessException("Pipe creation denied");
                throw new Win32Exception(error);
            }
            var handle=new SafePipeHandle(raw,true);
            try {return new NamedPipeServerStream(PipeDirection.InOut,true,false,handle);}
            catch {handle.Dispose();throw;}
        } finally {LocalFree(descriptor);}
    }
    public static async Task<NamedPipeServerStream> WaitForSearchListener(string name, bool first, string packageSid, CancellationToken stop)
    {
        while (true)
        {
            stop.ThrowIfCancellationRequested();
            try { return CreateSearchListener(name, first, packageSid); }
            catch (Win32Exception e) when (!first && e.NativeErrorCode == 231)
            {
                await Task.Delay(100, stop);
            }
        }
    }
    private static byte[] TokenInfo(IntPtr token,int kind)
    {
        GetTokenInformation(token,kind,IntPtr.Zero,0,out var needed);
        if(needed<=0) throw new Win32Exception(Marshal.GetLastWin32Error());
        var buffer=Marshal.AllocHGlobal(needed);
        try {
            if(!GetTokenInformation(token,kind,buffer,needed,out needed)) throw new Win32Exception(Marshal.GetLastWin32Error());
            // SID-bearing structures reference memory inside this buffer. Copy their SID,
            // not the pointer, before freeing the native token information.
            if(kind==1 || kind==25 || kind==31) return Encoding.ASCII.GetBytes(new SecurityIdentifier(Marshal.ReadIntPtr(buffer)).Value);
            var result=new byte[needed]; Marshal.Copy(buffer,result,0,needed); return result;
        } finally {Marshal.FreeHGlobal(buffer);}
    }
    public static bool IsTrustedClient(NamedPipeServerStream pipe,string packageSid)
    {
        IntPtr process=IntPtr.Zero,token=IntPtr.Zero;
        try {
            if(!GetNamedPipeClientProcessId(pipe.SafePipeHandle,out var pid)) return false;
            process=OpenProcess(0x1000,false,pid);
            if(process==IntPtr.Zero || !OpenProcessToken(process,8,out token)) return false;
            if(Encoding.ASCII.GetString(TokenInfo(token,1))!=WindowsIdentity.GetCurrent().User.Value) return false;
            if(BitConverter.ToInt32(TokenInfo(token,29),0)!=0) return Encoding.ASCII.GetString(TokenInfo(token,31))==packageSid;
            var integrity=Encoding.ASCII.GetString(TokenInfo(token,25)).Split('-');
            return int.Parse(integrity[integrity.Length-1],System.Globalization.CultureInfo.InvariantCulture)>=8192;
        } catch(Win32Exception) {return false;}
        finally {if(token!=IntPtr.Zero)CloseHandle(token);if(process!=IntPtr.Zero)CloseHandle(process);}
    }
    public static string PipeName => "Meltype.NativeComposition." + WindowsIdentity.GetCurrent().User.Value;
    public static NamedPipeServerStream CreateListener(string name, bool first)
        => new NamedPipeServerStream(name, PipeDirection.InOut, 32, PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly | (first ? PipeOptions.FirstPipeInstance : 0));
    private sealed class Host : ICompositionHost
    {
        public readonly List<(int Kind, string Text)> Actions = new();
        public CompositionView View;
        public char Character;
        public bool Shift, ReplayCurrent;
        public void CommitText(string text) => Actions.Add((1, text));
        public void Show(CompositionView view) { View = view; Actions.Add((0, view.Text)); }
        public void Hide() { View = null; Actions.Add((2, "")); }
        public void DeleteBackward(int count) => Actions.Add((3, count.ToString(System.Globalization.CultureInfo.InvariantCulture)));
        public void Replay(KeyEvent e) { ReplayCurrent = true; }
        public void Replay(MouseButtonEvent e) => throw new InvalidOperationException("Mouse replay is not used by TSF");
        public char? CharFromKey(KeyEvent e, bool shift) => Character == 0 ? null : Character;
        public bool IsShiftDown() => Shift;
        public void RequestSurroundingText(Action<string, string> callback) => callback(null, null);
    }
    internal static async Task Serve(NamedPipeServerStream pipe, bool learning, CancellationToken stop, string packageSid)
    {
        using (pipe)
        {
            if(!IsTrustedClient(pipe,packageSid)) return;
            var host = new Host();
            var gate = new CaptureGate(() => { });
            var preferences = new Meltype.Config.InputPreferenceStore(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MeltypeNativeGoogle", "input-preferences.json"));
            var google = new GoogleImeConverter(learning) { LearningEnabled = () => preferences.Current.LearningEnabled };
            var controller = new CompositionController(gate, CompositionDetector.CreateDefault(), google, host,
                new CompositionOptions { FullWidthCommaPeriod = true, Comma = () => preferences.Current.Comma[0],
                    Period = () => preferences.Current.Period[0], LearningEnabled = () => preferences.Current.LearningEnabled,
                    LiveConversion = () => true, MoreCandidates = google.Candidates, AutoCorrect = () => false });
            var request = new byte[32];
            try
            {
                while (!stop.IsCancellationRequested)
                {
                    await pipe.ReadExactlyAsync(request, stop);
                    using var input = new BinaryReader(new MemoryStream(request), Encoding.Unicode);
                    if (input.ReadInt32() != 1) throw new InvalidDataException("Protocol version");
                    var operation = input.ReadInt32();
                    var vk = input.ReadInt32();
                    var scan = input.ReadInt32();
                    host.Character = (char)input.ReadInt32();
                    var flags = input.ReadInt32();
                    var time = input.ReadInt64();
                    host.Shift = (flags & 2) != 0;
                    host.Actions.Clear();
                    host.ReplayCurrent = false;
                    if (operation == 0)
                    {
                        gate.OnKey(new KeyEvent(vk, scan, false, (flags & 1) != 0, false, time), e => !e.IsUp);
                        controller.Pump();
                    }
                    else if (operation == 1) controller.CommitPending();
                    else throw new InvalidDataException("Operation");
                    using var buffer = new MemoryStream();
                    using (var output = new BinaryWriter(buffer, Encoding.Unicode, leaveOpen: true))
                    {
                        output.Write(host.ReplayCurrent ? 1 : 0);
                        output.Write(host.Actions.Count);
                        foreach (var action in host.Actions)
                        {
                            output.Write(action.Kind);
                            WriteText(output, action.Text);
                        }
                        output.Write(host.View?.Converting == true ? 1 : 0);
                        output.Write(host.View?.SelectedIndex ?? -1);
                        var candidates = host.View?.Candidates;
                        var count = Math.Min(candidates?.Count ?? 0, 256);
                        output.Write(count);
                        for (var i = 0; i < count; i++) WriteText(output, candidates[i]);
                    }
                    if (buffer.Length > 1048576) throw new InvalidDataException("Response too large");
                    var payload = buffer.ToArray();
                    await pipe.WriteAsync(BitConverter.GetBytes(payload.Length), stop);
                    await pipe.WriteAsync(payload, stop);
                    await pipe.FlushAsync(stop);
                }
            }
            catch (Exception e) when (e is IOException || e is OperationCanceledException) { }
            catch (Exception e) { Console.Error.WriteLine("Native broker client error: " + e.GetType().Name); }
            // A disconnected client has no submit/learning operation. Its controller is discarded.
        }
    }
    private static void WriteText(BinaryWriter writer, string value)
    {
        var bytes = Encoding.Unicode.GetBytes(value);
        writer.Write(bytes.Length);
        writer.Write(bytes);
    }
    public static void Run(bool learning)
    {
        using var stopEvent = new EventWaitHandle(false, EventResetMode.ManualReset, "Local\\" + PipeName + ".Stop");
        stopEvent.Reset();
        using var cancellation = new CancellationTokenSource();
        var waiter = ThreadPool.RegisterWaitForSingleObject(stopEvent, (_, _) => cancellation.Cancel(), null, -1, true);
        try { RunAsync(learning, cancellation.Token).GetAwaiter().GetResult(); }
        finally { waiter.Unregister(null); }
    }
    private static async Task RunAsync(bool learning, CancellationToken stop)
    {
        var searchSid=SearchPackageSid;
        AllowSearchPeerQuery(searchSid);
        var connections = new List<Task>();
        var first = true;
        try
        {
            while (!stop.IsCancellationRequested)
            {
                var pipe = await WaitForSearchListener(PipeName, first, searchSid, stop);
                first = false;
                try { await pipe.WaitForConnectionAsync(stop); }
                catch { pipe.Dispose(); throw; }
                connections.RemoveAll(t => t.IsCompleted);
                connections.Add(Task.Run(() => Serve(pipe, learning, stop, searchSid)));
            }
        }
        catch (OperationCanceledException) { }
        await Task.WhenAll(connections);
    }
}
