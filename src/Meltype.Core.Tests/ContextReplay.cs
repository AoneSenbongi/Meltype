// SPDX-License-Identifier: GPL-3.0-or-later
using System.Diagnostics;
using System.Text.Encodings.Web;
using System.Text.Json;
using Meltype.Composition;

namespace Meltype.Tests;

/// <summary>Controlled learning stress test, not an estimate of everyday IME accuracy.</summary>
internal static class ContextReplay
{
    internal sealed record Case(string Id, string Split, string Family, string Reading, string Left, string Right,
        string[] Candidates, string Expected, bool Explicit = false, bool Undo = false, bool Reviewed = false);

    internal sealed class Feedback(string policy)
    {
        private readonly Dictionary<string, Dictionary<string, int>> _entries = new(StringComparer.Ordinal);
        private string Key(Case c) => policy == "contextual-explicit" ? c.Reading + "\u0001" + c.Left + "\u0001" + c.Right : c.Reading;
        public void Learn(Case c)
        {
            if (policy is "none" or "baseline" || c.Undo || (policy != "all-commits" && !c.Explicit)) return;
            var key = Key(c);
            if (!_entries.TryGetValue(key, out var counts)) _entries[key] = counts = new(StringComparer.Ordinal);
            counts[c.Expected] = counts.GetValueOrDefault(c.Expected) + 1;
        }
        public string? Recall(Case c) => _entries.GetValueOrDefault(Key(c))?.OrderByDescending(p => p.Value).Select(p => p.Key).FirstOrDefault();
    }

    public static int Run(string corpus, string endpoint, string output)
    {
        var cases = JsonSerializer.Deserialize<Case[]>(File.ReadAllText(corpus), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        var training = cases.Where(c => c.Split == "train").ToArray();
        var tests = cases.Where(c => c.Split == "test").ToArray();
        if (cases.Select(c => c.Id).Distinct().Count() != cases.Length || tests.Any(t => training.Any(c => c.Left == t.Left && c.Right == t.Right && c.Reading == t.Reading)))
            throw new InvalidDataException("Duplicate IDs or train/test overlap");
        using var model = new ZenzContextEvaluator(new Uri(endpoint));
        var observations = new List<object>();
        foreach (var c in tests)
        {
            var clock = Stopwatch.StartNew();
            string? answer = null; string? error = null;
            try { answer = model.EvaluateAsync(new(c.Reading, c.Left, c.Right, c.Candidates), CancellationToken.None).GetAwaiter().GetResult(); }
            catch (Exception e) { error = e.GetType().Name; }
            clock.Stop();
            var accepted = answer is not null && c.Candidates.Contains(answer, StringComparer.Ordinal);
            observations.Add(new { c.Id, c.Family, c.Reading, c.Left, c.Right, c.Expected, Baseline = c.Candidates[0], Model = answer,
                CandidateCoverage = c.Candidates.Contains(c.Expected), Accepted = accepted, Error = error, ElapsedMs = clock.Elapsed.TotalMilliseconds });
        }
        var raw = JsonSerializer.SerializeToElement(observations);
        var summaries = new List<object>();
        foreach (var policy in new[] { "baseline", "none", "all-commits", "explicit-only", "contextual-explicit" })
        {
            var feedback = new Feedback(policy);
            for (var epoch = 0; epoch < 20; epoch++) foreach (var c in training) feedback.Learn(c);
            var outputs = tests.Select((c, i) =>
            {
                var result = raw[i];
                var llm = result.GetProperty("Accepted").GetBoolean() ? result.GetProperty("Model").GetString()! : c.Candidates[0];
                var memory = feedback.Recall(c);
                var chosen = policy == "baseline" ? c.Candidates[0] : memory is not null && c.Candidates.Contains(memory) ? memory : llm;
                return new { c.Id, Chosen = chosen, Correct = chosen == c.Expected,
                    Regression = c.Candidates[0] == c.Expected && chosen != c.Expected, UsedMemory = memory is not null && chosen == memory };
            }).ToArray();
            summaries.Add(new { Policy = policy, Total = tests.Length, Correct = outputs.Count(o => o.Correct),
                Regressions = outputs.Count(o => o.Regression), MemoryUses = outputs.Count(o => o.UsedMemory), Outputs = outputs });
        }
        var sorted = raw.EnumerateArray().Select(r => r.GetProperty("ElapsedMs").GetDouble()).Order().ToArray();
        var report = new { Kind = "controlled-candidate-learning-stress-test", TrainingCases = training.Length, TestCases = tests.Length,
            Epochs = 20, ModelRequests = tests.Length, Timings = new { MedianMs = sorted[sorted.Length / 2], P95Ms = sorted[(int)((sorted.Length - 1) * .95)] },
            Limitations = new[] { "Hand-authored candidates; coverage is not real Google engine coverage.",
                "No human usability score; no claim of everyday accuracy.", "Contextual memory uses exact context; it is not semantic generalization.",
                "Policies share the same raw model results for paired comparison; no production histories are changed." },
            Summaries = summaries, Observations = observations };
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        File.WriteAllText(output, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        foreach (var summary in summaries) Console.WriteLine(JsonSerializer.SerializeToElement(summary).GetRawText().Split(",\"Outputs\"")[0] + "}");
        Console.WriteLine($"Model median={sorted[sorted.Length / 2]:F1}ms, p95={sorted[(int)((sorted.Length - 1) * .95)]:F1}ms; {output}");
        return raw.EnumerateArray().Any(r => r.GetProperty("Error").ValueKind != JsonValueKind.Null || !r.GetProperty("Accepted").GetBoolean()) ? 1 : 0;
    }
}
