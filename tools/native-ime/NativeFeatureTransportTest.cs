// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;

public static class NativeFeatureTransportTest
{
    public static async Task Baseline()
    {
        var name = "Meltype.FeatureBaseline." + Guid.NewGuid().ToString("N");
        using var server = MeltypeNativeBroker.CreateListener(name, false);
        using var client = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        var waiting = server.WaitForConnectionAsync();
        await client.ConnectAsync(5000); await waiting;
        var serving = MeltypeNativeBroker.Serve(server, false, CancellationToken.None, MeltypeNativeBroker.SearchPackageSid);
        using var request = new MemoryStream();
        using (var writer = new BinaryWriter(request, Encoding.Unicode, true)) {
            foreach (int v in new[] { 1, 0, (int)'K', 0, (int)'k', 8 }) writer.Write(v);
            writer.Write(Environment.TickCount64);
        }
        await client.WriteAsync(request.ToArray());
        var length = new byte[4]; await client.ReadExactlyAsync(length);
        var payload = new byte[BitConverter.ToInt32(length)]; await client.ReadExactlyAsync(payload);
        client.Dispose(); await serving;
        if ((BitConverter.ToInt32(payload) & 1) == 0) throw new Exception("Direct mode k must immediately pass through while undecided");
    }

    public static async Task Run(string executable, string trace, string dll, string log, string fixture, string mode = "--features", bool learning = true)
    {
        var name = "Meltype.FeatureTest." + Guid.NewGuid().ToString("N");
        using var stop = new CancellationTokenSource();
        var connections = new System.Collections.Generic.List<Task>();
        async Task Listen() {
            while (!stop.IsCancellationRequested) {
                var server = MeltypeNativeBroker.CreateListener(name, false);
                try {
                    await server.WaitForConnectionAsync(stop.Token);
                    connections.Add(Task.Run(() => MeltypeNativeBroker.Serve(server, learning, stop.Token, MeltypeNativeBroker.SearchPackageSid)));
                } catch (OperationCanceledException) { server.Dispose(); break; }
            }
        }
        var listening = Listen();
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var arg in new[] { trace, dll, mode, "\\\\.\\pipe\\" + name, fixture }) info.ArgumentList.Add(arg);
        using var process = Process.Start(info);
        var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
        try {
            await process.WaitForExitAsync();
            File.WriteAllText(log, await output + await error);
            if (process.ExitCode != 0) throw new Exception("Native feature TSF tests failed (exit " + process.ExitCode + "); see " + log);
        } finally { stop.Cancel(); await listening; await Task.WhenAll(connections); }
    }
}
