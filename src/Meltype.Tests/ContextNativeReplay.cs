// SPDX-License-Identifier: GPL-3.0-or-later
using System.Diagnostics;
using System.Text.Json;
using Meltype.Composition;
using Meltype.Input;

namespace Meltype.Tests;

internal static class ContextNativeReplay
{
    private sealed class MeasuredConverter(GoogleImeConverter inner) : IKanjiConverter
    {
        public int MaximumReadingLength;
        public string? Convert(string reading) { MaximumReadingLength = Math.Max(MaximumReadingLength, reading.Length); return inner.Convert(reading); }
        public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null)
        { MaximumReadingLength = Math.Max(MaximumReadingLength, reading.Length); return inner.ConvertClauses(reading, context); }
    }
    private sealed class Host : ICompositionHost
    {
        public char Character;
        public CompositionView? View;
        public string Committed = "";
        public readonly List<string> Frames = [];
        public void Show(CompositionView view) { View = view; if (Frames.LastOrDefault() != view.Text) Frames.Add(view.Text); }
        public void Hide() => View = null;
        public void CommitText(string text) => Committed += text;
        public void DeleteBackward(int count) => throw new InvalidOperationException("Committed text cannot be rewritten");
        public void Replay(KeyEvent e) { }
        public void Replay(MouseButtonEvent e) => throw new InvalidOperationException();
        public char? CharFromKey(KeyEvent e, bool shift) => Character == 0 ? null : Character;
        public void RequestSurroundingText(Action<string?, string?> callback) => callback(null, null);
    }

    public static int Run(string endpoint, string output, bool longInput = false, bool romanTypos = false)
    {
        using var model = new ZenzContextEvaluator(new Uri(endpoint));
        var rows = new List<object>();
        var inputs = romanTypos ? new[] { "onegaishimsu", "sumimasne", "arigatpu", "meeting", "github", "camera", "kyou" } : longInput
            ? new[] { 6, 16 }.Select(n => "kawadekutsuwotsukuru" + string.Concat(Enumerable.Repeat("soshitesonotokinoyousuwokuwashikukirokushiteoku", n)))
            : ["hashidetaberu", "hashiwowataru", "kawadekutsuwotsukuru", "kawadeoyogu", "kyouhagoogledekensaku", "GitHubnoshiyouwokakuninshimasu", "C++noshiyouwoyomimasu"];
        foreach (var input in inputs)
        {
            var converter = new GoogleImeConverter(learning: false);
            var measured = new MeasuredConverter(converter);
            var host = new Host(); var gate = new CaptureGate(() => { });
            var controller = new CompositionController(gate, CompositionDetector.CreateDefault(legacyGoogleConversion: true), measured, host,
                new CompositionOptions { LiveConversion = () => true, LearningEnabled = () => false, AutoCorrect = () => false,
                    ContextEvaluator = model, ContextCandidates = converter.CachedCandidates, MoreCandidates = converter.Candidates });
            void Key(char ch)
            {
                host.Character = ch;
                var vk = ch == '\n' ? VirtualKeys.Return : char.IsAsciiLetter(ch) ? char.ToUpperInvariant(ch) : ch;
                foreach (var up in new[] { false, true }) { gate.OnKey(new KeyEvent(vk, 0, false, up, false, Environment.TickCount64), e => !e.IsUp); controller.Pump(); }
            }
            var clock = Stopwatch.StartNew();
            foreach (var ch in input) Key(ch);
            var typingMs = clock.Elapsed.TotalMilliseconds;
            var baseline = host.View?.Text;
            var wait = Stopwatch.StartNew();
            while (controller.ContextEvaluationPending && wait.ElapsedMilliseconds < 2500)
            { controller.PollContextEvaluation(Environment.TickCount64); Thread.Sleep(5); }
            var evaluated = host.View?.Text;
            Key('\n');
            if (host.Committed != evaluated) throw new InvalidOperationException($"Commit differs from visible result: {input}: visible={evaluated}, commit={host.Committed}, baseline={baseline}");
            rows.Add(new { Input = input, measured.MaximumReadingLength, Baseline = baseline, Evaluated = evaluated, host.Committed, TypingMs = typingMs,
                WaitMs = wait.Elapsed.TotalMilliseconds, Frames = host.Frames.ToArray(), Pending = controller.ContextEvaluationPending });
            controller.Reset();
        }
        File.WriteAllText(output, JsonSerializer.Serialize(rows, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        foreach (var row in rows) Console.WriteLine(JsonSerializer.Serialize(row));
        return 0;
    }
}
