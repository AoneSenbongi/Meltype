// SPDX-License-Identifier: GPL-3.0-or-later
using System.Diagnostics;
using System.Text.Encodings.Web;
using System.Text.Json;
using Meltype.Composition;

namespace Meltype.Tests;

internal static class ContextLongRun
{
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping, PropertyNameCaseInsensitive = true };
    private static readonly string[] Policies = ["none", "all-commits", "explicit-only", "contextual-explicit"];
    private static bool SaveSnapshot(string path, object value)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            for (var attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    File.WriteAllText(temporary, JsonSerializer.Serialize(value, Json));
                    File.Move(temporary, path, overwrite: true);
                    return true;
                }
                catch (Exception e) when (e is UnauthorizedAccessException || e is IOException)
                {
                    if (attempt < 2) Thread.Sleep(5 + attempt * 10);
                }
            }
            return false;
        }
        finally
        {
            try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
    private sealed record Corpus(ContextReplay.Case[] Stream, ContextReplay.Case[] Probes);
    private sealed record Observation(string Id, string Expected, string Baseline, string Chosen, bool Accepted, string? Error, double ElapsedMs);
    private sealed class Live(string policy)
    {
        public string Policy { get; } = policy;
        public int Correct { get; set; }
        public int Regressions { get; set; }
        public int MemoryUses { get; set; }
        public int Corrections { get; set; }
    }

    public static int Run(string corpusPath, string endpoint, string output)
    {
        var corpus = JsonSerializer.Deserialize<Corpus>(File.ReadAllText(corpusPath), Json)!;
        if (corpus.Stream.Length != 1000 || corpus.Probes.Length != 40) throw new InvalidDataException("Expected 1000 stream cases and 40 held-out probes.");
        using var model = new ZenzContextEvaluator(new Uri(endpoint));
        return Execute(corpus.Stream, corpus.Probes, model, output, [0, 100, 300, 1000]);
    }

    internal static int Execute(ContextReplay.Case[] stream, ContextReplay.Case[] probes, IContextEvaluator model, string output, int[] checkpoints)
    {
        static string Key(ContextReplay.Case c) => JsonSerializer.Serialize(new[] { c.Reading, c.Left, c.Right });
        if (stream.Concat(probes).Select(c => c.Id).Distinct().Count() != stream.Length + probes.Length ||
            stream.Select(Key).Distinct().Count() != stream.Length || probes.Any(p => stream.Any(c => Key(c) == Key(p))))
            throw new InvalidDataException("Duplicate stream inputs, IDs or train/probe overlap.");
        Directory.CreateDirectory(output);
        var clock = Stopwatch.StartNew();
        var feedback = Policies.ToDictionary(p => p, p => new ContextReplay.Feedback(p));
        var live = Policies.ToDictionary(p => p, p => new Live(p));
        var snapshots = new List<object>(); var timings = new List<double>();
        var probeResults = new List<Observation>();
        int processed = 0, requests = 0, failures = 0, consecutiveFailures = 0, progressWriteSkips = 0;
        string stage = "評価用40例を準備中", status = "running", message = "";
        string lastReading = "", lastExpected = "", lastChosen = "";
        var jsonl = new JsonSerializerOptions(Json) { WriteIndented = false };
        using var samples = new StreamWriter(Path.Combine(output, "samples.jsonl"), append: false) { AutoFlush = true };

        object Report() => new
        {
            status, stage, message, runnerPid = Environment.ProcessId, processed, total = stream.Length,
            probesProcessed = probeResults.Count, probesTotal = probes.Length, modelRequests = requests, failures, progressWriteSkips,
            elapsedSeconds = clock.Elapsed.TotalSeconds,
            remainingSeconds = requests == 0 || status != "running" ? (double?)null : clock.Elapsed.TotalSeconds / requests * Math.Max(0, stream.Length + probes.Length - requests),
            medianMs = timings.Count == 0 ? 0 : timings.Order().ElementAt(timings.Count / 2),
            p95Ms = timings.Count == 0 ? 0 : timings.Order().ElementAt((int)((timings.Count - 1) * .95)),
            lastReading, lastExpected, lastChosen, live = live.Values, checkpoints = snapshots,
            limitations = new[] { "Synthetic: 20 homophone pairs, 200 semantic examples, five variants = 1000 distinct input contexts.",
                "Not 1000 independent meanings or a measure of everyday accuracy.", "Weights are fixed; only external feedback changes.",
                "Simulated correction rate 25%; no actual user histories used.", "Exact-context memory has no semantic generalization.",
                "Fixed held-out model results are shared across checkpoints; probes never train feedback." }
        };
        void Progress() { if (!SaveSnapshot(Path.Combine(output, "status.json"), Report())) progressWriteSkips++; }
        void CancelIfRequested() { if (File.Exists(Path.Combine(output, "cancel.request"))) throw new OperationCanceledException(); }
        Observation Evaluate(ContextReplay.Case c)
        {
            CancelIfRequested();
            var timer = Stopwatch.StartNew(); string? answer = null, error = null;
            try { using var timeout = new CancellationTokenSource(5000); answer = model.EvaluateAsync(new(c.Reading, c.Left, c.Right, c.Candidates), timeout.Token).GetAwaiter().GetResult(); }
            catch (Exception e) { error = e.ToString(); }
            timer.Stop(); requests++; timings.Add(timer.Elapsed.TotalMilliseconds);
            var accepted = answer is not null && c.Candidates.Contains(answer, StringComparer.Ordinal);
            if (!accepted) { failures++; consecutiveFailures++; error ??= "InvalidOrEmptyModelOutput"; }
            else consecutiveFailures = 0;
            lastReading = c.Reading; lastExpected = c.Expected; lastChosen = accepted ? answer! : c.Candidates[0];
            return new(c.Id, c.Expected, c.Candidates[0], lastChosen, accepted, error, timer.Elapsed.TotalMilliseconds);
        }
        void Snapshot(int count)
        {
            foreach (var policy in Policies)
            {
                int correct = 0, regressions = 0, used = 0;
                for (int i = 0; i < probes.Length; i++)
                {
                    var c = probes[i]; var raw = probeResults[i];
                    var memory = feedback[policy].Recall(c);
                    var use = memory is not null && c.Candidates.Contains(memory);
                    var chosen = use ? memory! : raw.Chosen;
                    if (chosen == c.Expected) correct++;
                    if (raw.Chosen == c.Expected && chosen != c.Expected) regressions++;
                    if (use) used++;
                }
                snapshots.Add(new { checkpoint = count, policy, total = probes.Length, correct, regressions, memoryUses = used });
            }
        }
        try
        {
            Progress();
            foreach (var c in probes)
            {
                var result = Evaluate(c); probeResults.Add(result);
                samples.WriteLine(JsonSerializer.Serialize(new { phase = "probe", item = c, result }, jsonl));
                Progress();
                if (consecutiveFailures >= 5) throw new IOException("モデル要求が5件連続で失敗しました。");
            }
            if (checkpoints.Contains(0)) Snapshot(0);
            stage = "1000件の入力・学習を実行中"; Progress();
            foreach (var c in stream)
            {
                var raw = Evaluate(c); var decisions = new List<object>();
                foreach (var policy in Policies)
                {
                    var memory = feedback[policy].Recall(c);
                    var use = memory is not null && c.Candidates.Contains(memory);
                    var chosen = use ? memory! : raw.Chosen;
                    var corrected = c.Reviewed && chosen != c.Expected;
                    var committed = corrected ? c.Expected : chosen;
                    var row = live[policy];
                    if (chosen == c.Expected) row.Correct++;
                    if (raw.Chosen == c.Expected && chosen != c.Expected) row.Regressions++;
                    if (use) row.MemoryUses++;
                    if (corrected) row.Corrections++;
                    if (raw.Accepted) feedback[policy].Learn(c with { Expected = committed, Explicit = corrected });
                    decisions.Add(new { policy, chosen, committed, corrected, undone = c.Undo, usedMemory = use });
                }
                processed++;
                samples.WriteLine(JsonSerializer.Serialize(new { phase = "stream", index = processed, item = c, raw, decisions }, jsonl));
                if (checkpoints.Contains(processed)) Snapshot(processed);
                Progress();
                if (consecutiveFailures >= 5) throw new IOException("モデル要求が5件連続で失敗しました。");
            }
            status = failures == 0 ? "completed" : "completed_with_errors";
            stage = failures == 0 ? "完了" : "完了（要求失敗あり）";
            message = "1000件の実行が終了しました。チャットへ「終わった」と伝えてください。";
        }
        catch (OperationCanceledException) { status = "cancelled"; stage = "停止"; message = "停止要求により終了しました。途中結果を保存しました。"; }
        catch (Exception e) { status = "failed"; stage = "異常終了"; message = e.Message; }
        if (!SaveSnapshot(Path.Combine(output, "results.json"), Report()))
        { status = "failed"; stage = "結果保存に失敗"; message = "結果JSONを保存できませんでした。samples.jsonlに途中結果があります。"; }
        // A fresh final path remains available even when a reader keeps status.json locked.
        var finalSaved = SaveSnapshot(Path.Combine(output, "terminal.json"), Report());
        Progress();
        if (!finalSaved) return 1;
        return status == "cancelled" ? 2 : status == "failed" ? 1 : 0;
    }
}
