// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;

namespace Meltype.Tests;

internal static class ContextEvaluationTests
{
    private sealed class Counting : IKanjiConverter
    {
        public int Calls;
        private readonly CompositionTests.FakeConverter _inner = new();
        public string? Convert(string reading) { Calls++; return _inner.Convert(reading); }
        public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null) { Calls++; return _inner.ConvertClauses(reading, context); }
    }

    [Test]
    public static void ContextEvaluation_LearningDoesNotLeakAcrossContextsOrKeepUndoneChoices()
    {
        var global = new ContextReplay.Feedback("explicit-only");
        var contextual = new ContextReplay.Feedback("contextual-explicit");
        var training = new ContextReplay.Case("train", "train", "test", "はしをみた", "川のそば", "", ["橋を見た", "箸を見た"], "橋を見た", true);
        global.Learn(training); contextual.Learn(training);
        var other = training with { Left = "食卓の上" };
        Assert.Equal("橋を見た", global.Recall(other), "Global preference carries over even when meaning changes");
        Assert.True(contextual.Recall(other) is null, "Another context must be evaluated again");
        contextual.Learn(training with { Expected = "箸を見た", Undo = true });
        Assert.Equal("橋を見た", contextual.Recall(training), "An undone event does not replace the earlier valid preference");
    }

    [Test]
    public static void ContextEvaluation_DoesNotRepeatSynchronousEngineCalls()
    {
        var plain = new Counting(); var enabled = new Counting();
        new CompositionTests.Keyboard(live: true, converter: plain).Type("kyouhagoogledekensaku");
        new CompositionTests.Keyboard(live: true, converter: enabled, contextEvaluator: new ChooseKana()).Type("kyouhagoogledekensaku");
        Assert.Equal(plain.Calls, enabled.Calls, "Evaluation must reuse the existing live-conversion results");
    }

    private sealed class ChooseKana : IContextEvaluator
    {
        public readonly List<ContextRequest> Requests = [];
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken cancellation)
        {
            Requests.Add(request);
            return Task.FromResult<string?>(request.Candidates.FirstOrDefault(c => c.StartsWith("きょうは", StringComparison.Ordinal)));
        }
    }

    [Test]
    public static void ContextEvaluation_ControllerKeepsCorrectionWhileRomanSuffixIsIncomplete()
    {
        var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: new ChooseKana());
        keyboard.Type("kyouha");
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal("きょうは", keyboard.Showing);
        keyboard.Type("g");
        Assert.Equal("きょうはg", keyboard.Showing, "Do not flicker back to the original spelling for each pending consonant");
    }

    [Test]
    public static void ContextEvaluation_ControllerPreservesEnglishAndCommitsVisibleResult()
    {
        var model = new ChooseKana();
        var phrases = new PhraseHistory(null);
        var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: model, predictor: new Predictor(phrases, null, null));
        keyboard.Type("kyouhagoogledekensaku");
        Assert.Equal("今日はgoogleで検索", keyboard.Showing);
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal("きょうはgoogleで検索", keyboard.Showing);
        Assert.True(model.Requests.Any(r => r.Right.Contains("google") || r.Left.Contains("google")), "Model sees surrounding mixed-language content");
        Assert.True(model.Requests.All(r => !r.Candidates.Any(c => c.Contains("google"))), "English stays outside generated clauses");
        keyboard.Type("\n");
        Assert.Equal("きょうはgoogleで検索", keyboard.Host.Document, "Enter commits exactly the visible presentation");
        Assert.Equal(0, phrases.Count, "Automatic model choice is not a user preference");
        Assert.True(!keyboard.Controller.ContextEvaluationPending, "Commit cancels pending work");
    }

    [Test]
    public static void ContextEvaluation_ControllerKeepsManualSelection()
    {
        var model = new ChooseKana();
        var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: model) { ContinueAfterConversion = true };
        keyboard.Type("kyouha ");
        keyboard.Type("ha");
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal(0, model.Requests.Count, "Do not override a manually opened conversion");
        keyboard.Type("\n");
    }

    private sealed class Deferred : IContextEvaluator
    {
        public readonly List<(ContextRequest Request, TaskCompletionSource<string?> Result)> Calls = [];
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken cancellation)
        {
            var result = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
            Calls.Add((request, result));
            return result.Task; // Deliberately ignores cancellation to reproduce a late server response.
        }
    }

    [Test]
    public static void ContextEvaluation_LateResultCannotReplaceNewInput()
    {
        var model = new Deferred();
        using var evaluation = new ContextEvaluation(model, debounceMs: 0);
        var old = new ContextRequest("はし", "", "", ["橋", "箸"]);
        evaluation.Update(old, 0); evaluation.Poll(0);
        evaluation.Update(old with { Reading = "はしでたべる", Candidates = ["橋で食べる", "箸で食べる"] }, 1);
        model.Calls[0].Result.SetResult("箸");
        Assert.True(evaluation.Poll(1) is null, "Old generation must not apply");
        model.Calls[1].Result.SetResult("箸で食べる");
        Assert.Equal("箸で食べる", evaluation.Poll(2));
    }

    [Test]
    public static void ContextEvaluation_RejectsOutputOutsideCandidateListAndTimeout()
    {
        var model = new Deferred();
        using var evaluation = new ContextEvaluation(model, debounceMs: 0, timeoutMs: 10);
        evaluation.Update(new("はし", "", "", ["橋", "箸"]), 0); evaluation.Poll(0);
        model.Calls[0].Result.SetResult("未入力の文章");
        Assert.True(evaluation.Poll(1) is null, "Cannot introduce arbitrary output");
        evaluation.Update(new("かわ", "", "", ["川", "革"]), 2); evaluation.Poll(2);
        Assert.True(evaluation.Poll(13) is null && !evaluation.Pending, "Finite deadline");
        model.Calls[1].Result.SetResult("革");
        Assert.True(evaluation.Poll(14) is null, "Timed-out output must stay discarded");
    }

    [Test]
    public static void ContextEvaluation_ResetAndChangedContextInvalidateResults()
    {
        var model = new Deferred();
        using var evaluation = new ContextEvaluation(model, debounceMs: 0);
        var request = new ContextRequest("あつい", "本は", "", ["暑い", "厚い"]);
        evaluation.Update(request, 0); evaluation.Poll(0);
        evaluation.Reset(); model.Calls[0].Result.SetResult("厚い");
        Assert.True(evaluation.Poll(1) is null, "Commit/cancel must invalidate pending evaluation");
        evaluation.Update(request, 2); evaluation.Poll(2);
        evaluation.Update(request with { Left = "今日は" }, 3);
        model.Calls[1].Result.SetResult("厚い");
        Assert.True(evaluation.Poll(3) is null, "Left context is part of request identity");
    }

    [Test]
    public static void ContextEvaluation_CommonLiteralPrefixIsPrefilledInsteadOfGenerated()
    {
        var request = new ContextRequest("GitHub: はしをみた", "川の両岸をつなぐ建造物を探した。", "", ["GitHub: 橋を見た", "GitHub: 箸を見た"]);
        Assert.True(ZenzContextEvaluator.Prompt(request).EndsWith("\uEE01GitHub: "), "Prefill the fixed literal prefix");
        Assert.Equal("root ::= \"橋を見た\" | \"箸を見た\"", ZenzContextEvaluator.Grammar(request));
    }

    [Test]
    public static void ContextEvaluation_GrammarAndPromptPreserveMixedText()
    {
        Assert.True(!ZenzContextEvaluator.PreservesLiteralText("C＋＋の仕様", "C＋+の仕様"), "Do not change technical punctuation");
        Assert.True(!ZenzContextEvaluator.PreservesLiteralText("100円", "1000円"), "Do not change numbers");
        Assert.True(ZenzContextEvaluator.PreservesLiteralText("GitHubの使用", "GitHubの仕様"), "Japanese spelling may change around literal tokens");
        var request = new ContextRequest("きょうはGitHubでさぎょう", "開発中。", "します", ["今日はGitHubで作業", "今日はGitHubで左業"]);
        var prompt = ZenzContextEvaluator.Prompt(request);
        Assert.True(prompt.Contains("キョウハGitHubデサギョウ") && prompt.Contains("開発中。") && prompt.Contains("します"), "Whole reading and both contexts");
        var grammar = ZenzContextEvaluator.Grammar(request);
        Assert.True(grammar.Contains("GitHub") && !grammar.Contains("左業します"), "Only complete supplied candidate strings");
        var rejected = false;
        try { using var remote = new ZenzContextEvaluator(new Uri("https://example.com/")); }
        catch (ArgumentException) { rejected = true; }
        Assert.True(rejected, "Only explicit local endpoints are permitted");
    }
}
