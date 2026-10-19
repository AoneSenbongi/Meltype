// SPDX-License-Identifier: GPL-3.0-or-later
using System.Diagnostics;
using System.Text.Json;
using System.Text.Encodings.Web;
using Meltype.Composition;

namespace Meltype.Tests;

internal static class ContextClauseReplay
{
    private sealed class Measured(IContextEvaluator inner) : IContextEvaluator
    {
        public readonly List<(int Stage, object Row)> Calls = [];
        public int Stage;
        public async Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token)
        {
            var stage = Stage;
            var clock = Stopwatch.StartNew(); string? answer = null, error = null;
            try { return answer = await inner.EvaluateAsync(request, token); }
            catch (Exception e) { error = e.ToString(); throw; }
            finally { lock (Calls) Calls.Add((stage, new { request, answer, error, elapsedMs = clock.Elapsed.TotalMilliseconds })); }
        }
    }
    private static readonly JsonSerializerOptions Json = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public static int Run(string endpoint, string output)
    {
        Directory.CreateDirectory(output);
        using var model = new ZenzContextEvaluator(new Uri(endpoint));
        var rows = new List<object>();
        using var trace = new StreamWriter(Path.Combine(output, "samples.jsonl")) { AutoFlush = true };
        void RunStage(string id, string group, int length, ContextClause[] clauses, string left, string expected,
            bool scorable, ClauseContextEvaluation evaluation, Measured measured)
        {
            var stage = ++measured.Stage;
            var clock = Stopwatch.StartNew();
            evaluation.Update(clauses, left, "", Environment.TickCount64);
            string? result = null;
            while (evaluation.Pending && clock.ElapsedMilliseconds < 2500)
            {
                result = evaluation.Poll(Environment.TickCount64) ?? result;
                if (evaluation.Pending) Thread.Sleep(2);
            }
            var baseline = string.Concat(clauses.Select(c => c.Candidates[0]));
            var chosen = result ?? baseline;
            // Cancellation completion may still be unwinding. Do not enumerate a list being written.
            lock (measured.Calls)
            {
                var row = new { id, group, length, clauses, left, expected, scorable,
                    chosen, correct = scorable ? (bool?)(chosen == expected) : null,
                    baselineCorrect = scorable ? (bool?)(baseline == expected) : null,
                    resultAvailable = result is not null, pending = evaluation.Pending,
                    elapsedMs = clock.Elapsed.TotalMilliseconds,
                    calls = measured.Calls.Where(c => c.Stage == stage).Select(c => c.Row).ToArray() };
                rows.Add(row); trace.WriteLine(JsonSerializer.Serialize(row, Json));
            }
        }
        foreach (var m in ContextLengthReplay.Meanings)
        {
            var measured = new Measured(model);
            using var evaluation = new ClauseContextEvaluation(measured);
            foreach (var length in new[] { 20, 50, 80, 100, 101, 200, 400 })
            {
                var full = ContextLengthReplay.Growing(m, length);
                var tail = full.Reading[m.Reading.Length..];
                RunStage(m.Id + "-" + length, "growing", length,
                    [new(m.Reading, [m.First, m.Second]), new(tail, [tail])], "", m.Expected + tail,
                    length >= 50 + m.Cue.Length, evaluation, measured);
            }
        }
        foreach (var m in ContextLengthReplay.Meanings)
            foreach (var distance in new[] { 0, 64, 128, 256, 400 })
            {
                var measured = new Measured(model);
                using var evaluation = new ClauseContextEvaluation(measured);
                RunStage(m.Id + "-left-" + distance, "left-context", distance,
                    [new(m.Reading, [m.First, m.Second])], m.Cue + ContextLengthReplay.Pad(distance), m.Expected,
                    true, evaluation, measured);
            }
        foreach (var length in new[] { 50, 80, 100, 200, 400 })
        {
            var measured = new Measured(model);
            using var evaluation = new ClauseContextEvaluation(measured);
            var tail = "しょくじのどうぐでごはんをたべた。どうぶつのひふでくつをつくった。";
            tail += ContextLengthReplay.Pad(length - "はしとかわ。".Length - tail.Length);
            RunStage("two-errors-" + length, "multiple-clauses", length,
                [new("はし", ["橋", "箸"]), new("と", ["と"]), new("かわ", ["川", "革"]), new("。" + tail, ["。" + tail])],
                "", "箸と革。" + tail, true, evaluation, measured);
        }
        File.WriteAllText(Path.Combine(output, "results.json"), JsonSerializer.Serialize(new
        {
            status = "completed", rows,
            limitations = new[] { "Controlled authored clauses/candidates; not real Google segmentation or a human usability test.",
                "Growing stages share one coordinator per meaning; other cases start fresh.",
                "Changing UI is atomic per batch, not per clause. A 1500ms batch budget may leave later clauses unchanged.",
                "Accuracy denominators are eight authored meanings, not independent everyday samples." }
        }, new JsonSerializerOptions(Json) { WriteIndented = true }));
        Console.WriteLine($"Saved {rows.Count} stages to {output}");
        return rows.Any(row => !JsonSerializer.SerializeToElement(row).GetProperty("resultAvailable").GetBoolean()) ? 1 : 0;
    }
}
