// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class NativePrivacyTransportTest
{
    public static async Task Run(string fixture, string mode)
    {
        var name = "Meltype.PrivacyTest." + Guid.NewGuid().ToString("N");
        using var server = MeltypeNativeBroker.CreateListener(name, false);
        using var client = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        var waiting = server.WaitForConnectionAsync();
        await client.ConnectAsync(5000); await waiting;
        // Only Microsoft conversion and fixture-local histories are used here.
        var serving = MeltypeNativeBroker.Serve(server, true, CancellationToken.None, MeltypeNativeBroker.SearchPackageSid);
        async Task<string> Key(int vk, char character, int flags)
        {
            var request = new byte[32];
            int[] fields = {1, 0, vk, 0, character, flags};
            Buffer.BlockCopy(fields, 0, request, 0, 24);
            Buffer.BlockCopy(BitConverter.GetBytes(Environment.TickCount64), 0, request, 24, 8);
            await client.WriteAsync(request);
            var length = new byte[4]; await client.ReadExactlyAsync(length);
            var payload = new byte[BitConverter.ToInt32(length)]; await client.ReadExactlyAsync(payload);
            using var reader = new BinaryReader(new MemoryStream(payload), Encoding.Unicode);
            string Text() => Encoding.Unicode.GetString(reader.ReadBytes(reader.ReadInt32()));
            reader.ReadInt32(); var actions = reader.ReadInt32();
            for (int i=0; i<actions; i++) { reader.ReadInt32(); Text(); }
            reader.ReadInt32(); reader.ReadInt32(); var candidates=reader.ReadInt32();
            for(int i=0; i<candidates; i++) Text();
            var typed="";
            if((flags&32)!=0) {
                if(reader.BaseStream.Position==reader.BaseStream.Length) throw new Exception("Typed-key capability has no response field");
                typed=Text();
            }
            if(reader.BaseStream.Position!=reader.BaseStream.Length) throw new Exception("Unexpected trailing protocol bytes");
            return typed;
        }
        try {
            int capability=mode=="Private"?0:32;
            string typed="";
            foreach(char c in "nihongo") typed=await Key(char.ToUpperInvariant(c),c,64|capability);
            if(mode!="Private" && typed!="nihongo") throw new Exception("Typed romaji did not reach the candidate header");
            await Key(0x20,' ',64|capability); await Key(0x0d,'\0',64|capability);
            if(mode!="Typed" && File.Exists(Path.Combine(fixture,"phrases.txt"))) throw new Exception("Private input wrote phrase learning");
            foreach(char c in "nihongo") await Key(char.ToUpperInvariant(c),c,0);
            await Key(0x20,' ',0); await Key(0x0d,'\0',0);
            if(mode!="Typed" && !File.Exists(Path.Combine(fixture,"phrases.txt"))) throw new Exception("Normal input did not resume phrase learning");
        } finally { client.Dispose(); await serving; }
    }
}
