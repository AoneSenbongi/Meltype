// SPDX-License-Identifier: GPL-3.0-or-later
using System.Diagnostics;
using System.Text.Json;
using System.Text.Encodings.Web;
using Meltype.Composition;

namespace Meltype.Tests;

internal static class ContextLengthReplay
{
    internal sealed record Meaning(string Id, string Reading, string First, string Second, string Expected, string Cue);
    internal static readonly Meaning[] Meanings = [
        new("bridge", "はしをみた。", "橋を見た。", "箸を見た。", "橋を見た。", "それはかわのりょうがんをつなぐけんぞうぶつだった。"),
        new("chopsticks", "はしをみた。", "橋を見た。", "箸を見た。", "箸を見た。", "それはしょくじでごはんをつかむどうぐだった。"),
        new("river", "かわをみた。", "革を見た。", "川を見た。", "川を見た。", "そこにはやまからうみへながれるみずがあった。"),
        new("leather", "かわをみた。", "革を見た。", "川を見た。", "革を見た。", "それはくつやかばんをつくるためのどうぶつのひふだった。"),
        new("weather", "あついです。", "暑いです。", "厚いです。", "暑いです。", "きょうのきおんはさんじゅうごどをこえています。"),
        new("book", "あついです。", "暑いです。", "厚いです。", "厚いです。", "このほんはせんぺーじもあってぶあついのです。"),
        new("science", "かがくをまなぶ。", "化学を学ぶ。", "科学を学ぶ。", "科学を学ぶ。", "ぶつりやせいぶつもふくめてしぜんぜんたいをしらべます。"),
        new("chemistry", "かがくをまなぶ。", "化学を学ぶ。", "科学を学ぶ。", "化学を学ぶ。", "ぶっしつのはんのうやぶんしのこうぞうをしらべます。")
    ];
    private const string Filler = "そのときのようすをきろくした。あとでよみなおすためにくわしくかいておく。";
    internal static string Pad(int n) => string.Concat(Enumerable.Repeat(Filler, n / Filler.Length + 1))[..n];
    internal static ContextRequest Growing(Meaning m, int length)
    {
        var tail = Pad(50 - m.Reading.Length) + m.Cue + Pad(500);
        tail = tail[..(length - m.Reading.Length)];
        return new(m.Reading + tail, "", "", [m.First + tail, m.Second + tail]);
    }
    private sealed class Measured(IContextEvaluator inner) : IContextEvaluator
    {
        public int Calls;
        public double Milliseconds;
        public string? Answer, Error;
        public async Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token)
        {
            Calls++; var watch = Stopwatch.StartNew();
            try { return Answer = await inner.EvaluateAsync(request, token); }
            catch (Exception e) { Error = e.ToString(); throw; }
            finally { Milliseconds = watch.Elapsed.TotalMilliseconds; }
        }
    }
    internal static object Evaluate(string id, string group, ContextRequest request, string expected, bool scorable,
        IContextEvaluator model, bool bypassLengthGate = false)
    {
        var measured = new Measured(model);
        using var evaluation = new ContextEvaluation(measured);
        var watch = Stopwatch.StartNew();
        string? accepted = null;
        if (bypassLengthGate)
        {
            // Diagnostic only: call the same evaluator without the state-machine length gate.
            // Its candidate-length validation, HTTP settings and decoding cap are unchanged.
            try
            {
                using var timeout = new CancellationTokenSource(1500);
                var answer = measured.EvaluateAsync(request, timeout.Token).GetAwaiter().GetResult();
                if (answer is not null && request.Candidates.Contains(answer)) accepted = answer;
            }
            catch { /* Full diagnostic error is retained by Measured. */ }
        }
        else
        {
            evaluation.Update(request, Environment.TickCount64);
            while (evaluation.Pending && watch.ElapsedMilliseconds < 2500)
            {
                accepted = evaluation.Poll(Environment.TickCount64) ?? accepted;
                if (evaluation.Pending) Thread.Sleep(2);
            }
        }
        var chosen = accepted ?? request.Candidates[0];
        return new { id, group, readingLength = request.Reading.Length, leftLength = request.Left.Length,
            request, expected, scorable, candidateCoverage = request.Candidates.Contains(expected),
            bypassLengthGate, evaluatorCalls = measured.Calls,
            httpEligible = request.Candidates.All(c => c.Length <= 256), modelMs = measured.Milliseconds, measured.Error,
            rawAnswer = measured.Answer, accepted, chosen, correct = scorable ? (bool?)(chosen == expected) : null,
            baselineCorrect = scorable ? (bool?)(request.Candidates[0] == expected) : null,
            elapsedMs = watch.Elapsed.TotalMilliseconds,
            prompt = ZenzContextEvaluator.Prompt(request), pending = evaluation.Pending };
    }
    public static int Run(string endpoint, string output)
    {
        Directory.CreateDirectory(output);
        using var model = new ZenzContextEvaluator(new Uri(endpoint));
        var json = new JsonSerializerOptions { WriteIndented = false, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
        using var trace = new StreamWriter(Path.Combine(output, "samples.jsonl")) { AutoFlush = true };
        var rows = new List<object>();
        void Save(object row) { rows.Add(row); trace.WriteLine(JsonSerializer.Serialize(row, json)); }
        foreach (var m in Meanings)
        {
            foreach (var length in new[] { 20, 50, 80, 100, 101, 200, 400 })
            {
                var request = Growing(m, length);
                var expected = m.Expected + request.Reading[m.Reading.Length..];
                Save(Evaluate(m.Id + "-" + length, "growing", request, expected, length >= 50 + m.Cue.Length, model));
            }
            foreach (var distance in new[] { 0, 64, 128, 256, 400 })
            {
                var request = new ContextRequest(m.Reading, m.Cue + Pad(distance), "", [m.First, m.Second]);
                Save(Evaluate(m.Id + "-left-" + distance, "left-context", request, m.Expected, true, model));
            }
            foreach (var length in new[] { 200, 250, 400 })
            {
                var request = Growing(m, length);
                Save(Evaluate(m.Id + "-direct-" + length, "direct-diagnostic", request,
                    m.Expected + request.Reading[m.Reading.Length..], true, model, bypassLengthGate: true));
            }
        }
        // Only single-clause edits are offered, matching the production candidate limitation.
        foreach (var length in new[] { 50, 80, 100 })
        {
            var suffix = "しょくじのどうぐでごはんをたべた。どうぶつのひふでくつをつくった。";
            suffix += Pad(length - "はしとかわ。".Length - suffix.Length);
            var request = new ContextRequest("はしとかわ。" + suffix, "", "",
                ["橋と川。" + suffix, "箸と川。" + suffix, "橋と革。" + suffix]);
            Save(Evaluate("two-errors-" + length, "missing-combination", request, "箸と革。" + suffix, true, model));
        }
        File.WriteAllText(Path.Combine(output, "results.json"), JsonSerializer.Serialize(new
        {
            status = "completed", rows,
            limitations = new[] { "Controlled authored candidates; not actual Google candidates or app UI.",
                "Each checkpoint uses a fresh ContextEvaluation; accepted display carry-over is not simulated.",
                "Ambiguous prefixes are unscored. No model training. Left-context trials contain the cue in committed text.",
                "Only direct-diagnostic bypasses the state-machine length gate; it is not production behavior.",
                "Evaluator calls may be rejected before HTTP by candidate validation. Disabled requests are not model successes.",
                "Stability is assessed only from candidate choices, not human-perceived flicker." }
        }, new JsonSerializerOptions(json) { WriteIndented = true }));
        Console.WriteLine($"Saved {rows.Count} stages to {output}");
        return rows.Any(row => { var item = JsonSerializer.SerializeToElement(row); return
            !item.GetProperty("bypassLengthGate").GetBoolean() && item.GetProperty("Error").ValueKind != JsonValueKind.Null; }) ? 1 : 0;
    }
}
