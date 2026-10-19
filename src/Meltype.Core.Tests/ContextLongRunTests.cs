// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;
using System.Text.Json;

namespace Meltype.Tests;

internal static class ContextLongRunTests
{
    private sealed class Baseline : IContextEvaluator
    {
        public int Calls;
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken cancellation)
        { Calls++; return Task.FromResult<string?>(request.Candidates[0]); }
    }

    private static ContextReplay.Case Item(string id, string left, bool reviewed = true) =>
        new(id, "stream", "bridge", "はしをみた", left, "", ["橋を見た", "箸を見た"], "箸を見た", Reviewed: reviewed);

    [Test]
    public static void ContextLongRun_ThousandCasesSurviveConcurrentProgressReader()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-long-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "status.json"); File.WriteAllText(path, "{}");
        using var stop = new CancellationTokenSource();
        var reader = Task.Run(() =>
        {
            while (!stop.IsCancellationRequested)
            {
                try { using var file = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read); Thread.Sleep(2); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        });
        try
        {
            var stream = Enumerable.Range(0, 1000).Select(i => Item("stream-" + i, "学習" + i)).ToArray();
            Assert.Equal(0, ContextLongRun.Execute(stream, [Item("probe", "別文脈")], new Baseline(), directory, [0, 100, 300, 1000]));
            using var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(directory, "terminal.json")));
            Assert.Equal("completed", json.RootElement.GetProperty("status").GetString());
            Assert.Equal(1000, json.RootElement.GetProperty("processed").GetInt32());
            Assert.Equal(1001, File.ReadLines(Path.Combine(directory, "samples.jsonl")).Count());
        }
        finally { stop.Cancel(); reader.GetAwaiter().GetResult(); Directory.Delete(directory, true); }
    }

    [Test]
    public static void ContextLongRun_LockedProgressFileDoesNotAbortOrHideFinalResult()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-long-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var status = Path.Combine(directory, "status.json");
        File.WriteAllText(status, "{}");
        try
        {
            // A reader without FILE_SHARE_DELETE reproduces Windows refusing destination replacement.
            using (var reader = File.Open(status, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                Assert.Equal(0, ContextLongRun.Execute([Item("a", "学習")], [Item("p", "別文脈")], new Baseline(), directory, [0, 1]));
                using var terminal = JsonDocument.Parse(File.ReadAllText(Path.Combine(directory, "terminal.json")));
                Assert.Equal("completed", terminal.RootElement.GetProperty("status").GetString());
                Assert.Equal(1, terminal.RootElement.GetProperty("processed").GetInt32());
                Assert.True(terminal.RootElement.GetProperty("progressWriteSkips").GetInt32() > 0, "Progress writes were blocked but evaluation continued");
            }
        }
        finally { Directory.Delete(directory, true); }
    }

    [Test]
    public static void ContextLongRun_CheckpointsUseOnlyPastEventsAndDoNotTrainOnProbes()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-long-" + Guid.NewGuid().ToString("N"));
        var model = new Baseline();
        try
        {
            Assert.Equal(0, ContextLongRun.Execute([Item("a", "学習一"), Item("b", "学習二")], [Item("p", "未学習")], model, directory, [0, 1, 2]));
            using var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(directory, "results.json")));
            var root = json.RootElement;
            Assert.Equal(2, root.GetProperty("processed").GetInt32());
            Assert.Equal("completed", root.GetProperty("status").GetString());
            var snapshots = root.GetProperty("checkpoints").EnumerateArray().ToArray();
            Assert.Equal(12, snapshots.Length, "Four policies at three checkpoints");
            Assert.Equal(0, snapshots.Single(s => s.GetProperty("checkpoint").GetInt32() == 0 && s.GetProperty("policy").GetString() == "explicit-only").GetProperty("correct").GetInt32());
            Assert.Equal(1, snapshots.Single(s => s.GetProperty("checkpoint").GetInt32() == 1 && s.GetProperty("policy").GetString() == "explicit-only").GetProperty("correct").GetInt32());
            Assert.Equal(0, snapshots.Single(s => s.GetProperty("checkpoint").GetInt32() == 2 && s.GetProperty("policy").GetString() == "contextual-explicit").GetProperty("memoryUses").GetInt32(), "Unseen exact context must stay unseen");
            Assert.Equal(3, model.Calls, "Each stream case and each fixed probe makes one real request");
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }

    [Test]
    public static void ContextLongRun_CancelIsNotReportedAsCompletion()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-long-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory); File.WriteAllText(Path.Combine(directory, "cancel.request"), "stop");
        try
        {
            Assert.Equal(2, ContextLongRun.Execute([Item("a", "学習")], [Item("p", "別文脈")], new Baseline(), directory, [0, 1]));
            using var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(directory, "status.json")));
            Assert.Equal("cancelled", json.RootElement.GetProperty("status").GetString());
            Assert.Equal(0, json.RootElement.GetProperty("processed").GetInt32());
        }
        finally { Directory.Delete(directory, true); }
    }
}
