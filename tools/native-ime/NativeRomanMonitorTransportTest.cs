// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class NativeRomanMonitorTransportTest
{
    public static async Task Run()
    {
        var name = "Meltype.RomanMonitorTest." + Guid.NewGuid().ToString("N");
        using var server = MeltypeNativeBroker.CreateListener(name, false);
        using var client = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        var connection = server.WaitForConnectionAsync();
        await client.ConnectAsync(5000); await connection;
        var serving = MeltypeNativeBroker.Serve(server, false, CancellationToken.None, MeltypeNativeBroker.SearchPackageSid);
        var committed = "";
        async Task<int> Send(int operation, int vk = 0, char character = '\0', int flags = 0)
        {
            var request = new byte[32];
            Buffer.BlockCopy(new int[] { 1, operation, vk, 0, character, flags }, 0, request, 0, 24);
            Buffer.BlockCopy(BitConverter.GetBytes(Environment.TickCount64), 0, request, 24, 8);
            await client.WriteAsync(request);
            var length = new byte[4]; await client.ReadExactlyAsync(length);
            var bytes = new byte[BitConverter.ToInt32(length)]; await client.ReadExactlyAsync(bytes);
            using var reader = new BinaryReader(new MemoryStream(bytes), Encoding.Unicode);
            string Text() => Encoding.Unicode.GetString(reader.ReadBytes(reader.ReadInt32()));
            int status = reader.ReadInt32(), count = reader.ReadInt32();
            for (int i = 0; i < count; ++i)
            {
                int action = reader.ReadInt32(); var value = Text();
                if (action == 1) committed += value;
            }
            return status;
        }
        try
        {
            foreach (char c in "onegaishimsu")
            {
                await Send(0, char.ToUpperInvariant(c), c);
                await Send(0, char.ToUpperInvariant(c), c, 1);
            }
            int status = await Send(0, 0x0D);
            await Send(0, 0x0D, flags: 1);
            var deadline = Environment.TickCount64 + 3000;
            while ((status & 8) != 0 && Environment.TickCount64 < deadline)
            { await Task.Delay(10); status = await Send(5); }
            if (committed != "お願いします" && committed != "おねがいします")
                throw new Exception("Real broker did not commit the verified typo correction: " + committed);
            if ((status & 8) != 0) throw new Exception("Model polling did not terminate");
            var once = committed;
            await Send(5);
            if (committed != once) throw new Exception("Timer committed twice");
            Console.WriteLine("PASS: product broker key/Enter/poll transport commits the real model correction once: " + committed);
        }
        finally { client.Dispose(); await serving; }
    }
}
