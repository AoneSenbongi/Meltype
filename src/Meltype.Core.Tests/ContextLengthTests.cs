// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;

namespace Meltype.Tests;

internal static class ContextLengthTests
{
    private sealed class StablePrefixConverter : IKanjiConverter
    {
        public string? Convert(string reading) => null;
        public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null) =>
            reading.StartsWith("きょうは") ? (reading.Length == 4
                ? [new("きょうは", "今日は")]
                : [new("きょうは", "今日は"), new(reading[4..], reading[4..])]) : null;
    }
    private sealed class KanaPrefix : IContextEvaluator
    {
        public int Calls;
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token)
        {
            Calls++;
            return Task.FromResult(request.Candidates.FirstOrDefault(c => c.StartsWith("きょうは")));
        }
    }
    [Test]
    public static void ContextLength_ControllerKeepsAcceptedPrefixAndEvaluatesBeyond100()
    {
        var model = new KanaPrefix();
        var keyboard = new CompositionTests.Keyboard(live: true, converter: new StablePrefixConverter(), contextEvaluator: model);
        keyboard.Type("kyouha");
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.True(keyboard.Showing!.StartsWith("きょうは"), "Initial correction applies");
        keyboard.Type(string.Concat(Enumerable.Repeat("ka", 96)));
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal(2, model.Calls, "100-character reading is evaluated");
        keyboard.Type("ka");
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal(3, model.Calls, "101-character input must still evaluate its short clause");
        Assert.True(keyboard.Showing!.StartsWith("きょうは"), "Accepted prefix is retained, not necessarily reverted");
        keyboard.Type(string.Concat(Enumerable.Repeat("ka", 299)));
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal(4, model.Calls, "400-character input evaluates a short clause without generating its fixed tail");
        var visible = keyboard.Showing;
        keyboard.Type("\n");
        Assert.Equal(visible, keyboard.Host.Document, "Long input commits the visible text");
    }

    private sealed class TwoClauses : IKanjiConverter
    {
        public string? Convert(string reading) => null;
        public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null) =>
            reading == "かわとはし" ? [new("かわ", "川"), new("と", "と"), new("はし", "橋")] : null;
    }
    private sealed class ChooseReading : IContextEvaluator
    {
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token) => Task.FromResult<string?>(request.Reading);
    }
    [Test]
    public static void ContextLength_ControllerCanChangeTwoClausesWithoutWholeSentenceCombinations()
    {
        var keyboard = new CompositionTests.Keyboard(live: true, converter: new TwoClauses(), contextEvaluator: new ChooseReading());
        keyboard.Type("kawatohashi");
        Assert.Equal("川と橋", keyboard.Showing);
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal("かわとはし", keyboard.Showing, "Both candidate changes are combined in one display update");
        keyboard.Type("\n");
        Assert.Equal("かわとはし", keyboard.Host.Document);
    }

    private sealed class Baseline : IContextEvaluator
    {
        public int Calls;
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token)
        { Calls++; return Task.FromResult<string?>(request.Candidates[0]); }
    }
    [Test]
    public static void ContextLength_LegacyWholeRequestBoundaryIs100Not101()
    {
        var model = new Baseline();
        using var evaluation = new ContextEvaluation(model, debounceMs: 0);
        var m = ContextLengthReplay.Meanings[0];
        evaluation.Update(ContextLengthReplay.Growing(m, 100), 0);
        Assert.True(evaluation.Poll(0) is not null, "100 characters are evaluated");
        Assert.Equal(1, model.Calls);
        evaluation.Update(ContextLengthReplay.Growing(m, 101), 1);
        Assert.True(evaluation.Poll(1) is null && !evaluation.Pending, "101 characters disable evaluation");
        Assert.Equal(1, model.Calls, "Long input must not be counted as evaluated");
    }
    [Test]
    public static void ContextLength_CorpusStagesHaveExactLengthsAndKeepSamePrefix()
    {
        foreach (var m in ContextLengthReplay.Meanings)
        {
            string previous = "";
            foreach (var length in new[] { 20, 50, 80, 100, 101, 200, 400 })
            {
                var request = ContextLengthReplay.Growing(m, length);
                Assert.Equal(length, request.Reading.Length);
                Assert.True(request.Reading.StartsWith(previous), "Stages extend the same reading");
                Assert.True(request.Candidates.All(c => ZenzContextEvaluator.PreservesLiteralText(request.Candidates[0], c)), "Literal text is fixed");
                previous = request.Reading;
            }
        }
    }
    [Test]
    public static void ContextLength_DistantCommittedCueIsCutFromPrompt()
    {
        var request = new ContextRequest("はしをみた", "食卓の箸。" + ContextLengthReplay.Pad(256), "", ["橋を見た", "箸を見た"]);
        Assert.True(!ZenzContextEvaluator.Prompt(request).Contains("食卓"), "Distant cue is truncated");
        Assert.True(ZenzContextEvaluator.Prompt(request with { Left = "食卓の箸。" }).Contains("食卓"), "Nearby cue remains visible");
    }
}
