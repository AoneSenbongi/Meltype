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
using Meltype.Composition;
using Meltype.Input;

public static class MeltypeNativeBroker
{
    public static string PipeName => "Meltype.NativeComposition." + WindowsIdentity.GetCurrent().User.Value;
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
    private static async Task Serve(NamedPipeServerStream pipe, bool learning, CancellationToken stop)
    {
        using (pipe)
        {
            var host = new Host();
            var gate = new CaptureGate(() => { });
            var google = new GoogleImeConverter(learning);
            var controller = new CompositionController(gate, CompositionDetector.CreateDefault(), google, host,
                new CompositionOptions { FullWidthCommaPeriod = true, LiveConversion = () => true, MoreCandidates = google.Candidates, AutoCorrect = () => false });
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
        var connections = new List<Task>();
        try
        {
            while (!stop.IsCancellationRequested)
            {
                var pipe = new NamedPipeServerStream(PipeName, PipeDirection.InOut, 16, PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                try { await pipe.WaitForConnectionAsync(stop); }
                catch { pipe.Dispose(); throw; }
                connections.RemoveAll(t => t.IsCompleted);
                connections.Add(Task.Run(() => Serve(pipe, learning, stop)));
            }
        }
        catch (OperationCanceledException) { }
        await Task.WhenAll(connections);
    }
}
