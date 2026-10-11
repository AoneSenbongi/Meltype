// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class NativeSnippetTransportTest
{
    public static async Task Run(string trace)
    {
        var name = "Meltype.SnippetTest." + Guid.NewGuid().ToString("N");
        using var server = MeltypeNativeBroker.CreateListener(name, false);
        using var client = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        var waiting = server.WaitForConnectionAsync();
        await client.ConnectAsync(5000); await waiting;
        var serving = MeltypeNativeBroker.Serve(server, false, CancellationToken.None, MeltypeNativeBroker.SearchPackageSid);
        using var output = new BinaryWriter(File.Create(trace), Encoding.Unicode);
        output.Write(Encoding.ASCII.GetBytes("MTTSF1\n"));
        bool active = false;
        string visible = null, committed = "";
        async Task Key(int vk, char character, bool boundary = false)
        {
            var request = new byte[32];
            int[] fields = {1, 0, vk, 0, character, boundary ? 4 : 0};
            Buffer.BlockCopy(fields, 0, request, 0, 24);
            await client.WriteAsync(request);
            var length = new byte[4]; await client.ReadExactlyAsync(length);
            int count = BitConverter.ToInt32(length);
            if (count < 20 || count > 1048576) throw new Exception("Invalid snippet reply size");
            var payload = new byte[count]; await client.ReadExactlyAsync(payload);
            using var reader = new BinaryReader(new MemoryStream(payload), Encoding.Unicode);
            if (reader.ReadInt32() != 0) throw new Exception("Registered snippet key unexpectedly replayed");
            int actions = reader.ReadInt32();
            for (int i = 0; i < actions; ++i) {
                int kind = reader.ReadInt32(), size = reader.ReadInt32();
                var text = Encoding.Unicode.GetString(reader.ReadBytes(size));
                if (kind == 0) { visible = text; active = true; }
                else if (kind == 1) { committed += text; active = false; }
                else if (kind == 2) { visible = null; if (!active) continue; active = false; }
                else throw new Exception("Unexpected snippet action");
                output.Write(kind); output.Write(size); output.Write(Encoding.Unicode.GetBytes(text));
            }
        }
        foreach (char c in ";sig") await Key(c == ';' ? 0xba : char.ToUpperInvariant(c), c, true);
        await Key(0x20, ' ');
        if (visible != "googleで検索\n署名") throw new Exception("Broker snippet expansion missing");
        await Key(0x1b, '\0'); if (visible != ";sig") throw new Exception("Broker snippet undo missing");
        await Key(0x09, '\0'); await Key(0x0d, '\r');
        if (committed != "googleで検索\n署名") throw new Exception("Broker multiline commit missing");
        foreach (char c in ";sig") await Key(c, c, true);
        await Key(0x1b, '\0');
        client.Dispose(); await serving;
    }
}
