// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;
using Meltype.Input;

namespace Meltype.Tests;

internal static class RomanMonitorTests
{
    private sealed class Broken : IContextEvaluator
    {
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken cancellation) => throw new IOException("offline");
    }

    [Test]
    public static void RomanMonitor_TimeoutAndFailureKeepOriginalAndCannotRewriteCommit()
    {
        foreach (var failure in new[] { false, true })
        {
            var delayed = new Model(delayed: true);
            IContextEvaluator evaluator = failure ? new Broken() : delayed;
            var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: evaluator);
            keyboard.Type("onegaishimsu");
            var original = keyboard.Showing;
            keyboard.Type("\n");
            keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 2000);
            Assert.Equal(original, keyboard.Host.Document, "No unverified correction on timeout or synchronous error");
            delayed.Completion.SetResult("おねがいします");
            keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 2500);
            Assert.Equal(original, keyboard.Host.Document);
            Assert.True(!keyboard.Controller.ContextEvaluationPending, "Pending state is released");
        }
    }

    [Test]
    public static void RomanMonitor_ContinuingInputAndSpacePreserveCommitOrder()
    {
        var delayed = new Model(delayed: true);
        var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: delayed);
        keyboard.Type("onegaishimsu");
        var original = keyboard.Showing;
        keyboard.Type("\nk");
        Assert.Equal(original, keyboard.Host.Document, "The requested Enter precedes later typing");
        var next = keyboard.Showing;
        delayed.Completion.SetResult("おねがいします");
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal(next, keyboard.Showing);
        Assert.Equal(original, keyboard.Host.Document);

        var space = new CompositionTests.Keyboard(live: true, contextEvaluator: new Model());
        space.Type("onegaishimsu ");
        Assert.Equal("おねがいします ", space.Host.Document, "Space preserves its separator");
    }

    [Test]
    public static void RomanMonitor_ExplicitMemoryAndEnterAsShownTakePrecedence()
    {
        var memory = new LanguageMemory(null);
        memory.Remember("onegaishimsu", true, true);
        var detector = CompositionDetector.CreateDefault(); detector.Memory = memory;
        var model = new Model();
        var keyboard = new CompositionTests.Keyboard(live: true, languages: memory, contextEvaluator: model, detectorOverride: detector);
        keyboard.Type("onegaishimsu");
        var original = keyboard.Showing;
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal(original, keyboard.Showing);
        Assert.True(!model.Requests.Any(r => r.RomanTypo), "Explicit English memory is protected");

        var shown = new CompositionTests.Keyboard(live: true, contextEvaluator: new Model(delayed: true));
        shown.EnterCommitsAsShown = true;
        shown.Type("onegaishimsu");
        var before = shown.Showing;
        shown.Type("\n");
        Assert.Equal(before, shown.Host.Document);
        Assert.True(!shown.Controller.ContextEvaluationPending, "Commit cancels background work");
    }

    [Test]
    public static void RomanMonitor_CandidateExceptionIsNarrowAndOptional()
    {
        var request = new ContextRequest("おねがいします", "", "", ["onegaishimsu", "お願いします"], RomanTypo: true);
        Assert.True(ZenzContextEvaluator.AllowsCandidate(request, "お願いします"), "Allow the bounded repair");
        Assert.True(!ZenzContextEvaluator.AllowsCandidate(request with { RomanTypo = false }, "お願いします"), "Default literal preservation remains");
        foreach (var output in new[] { "100円", "GitHub", "お願いします!", "お願いします\n" })
            Assert.True(!ZenzContextEvaluator.AllowsCandidate(request, output), output);
        Assert.True(!ZenzContextEvaluator.AllowsCandidate(request with { Candidates = ["https://x", "お願いします"] }, "お願いします"), "URL is never a typo hypothesis");
    }

    private sealed class Model(bool delayed = false) : IContextEvaluator
    {
        public readonly List<ContextRequest> Requests = [];
        public readonly TaskCompletionSource<string?> Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken cancellation)
        {
            Requests.Add(request);
            return delayed ? Completion.Task : Task.FromResult(request.Candidates.FirstOrDefault(c => c == "おねがいします"));
        }
    }

    [Test]
    public static void RomanMonitor_RechecksEnglishMemoryWithoutLearningModelChoice()
    {
        var memory = new LanguageMemory(null);
        memory.Remember("onegaishimsu", true, false);
        memory.Remember("onegaishimsu", true, false);
        var detector = CompositionDetector.CreateDefault(); detector.Memory = memory;
        var model = new Model();
        var keyboard = new CompositionTests.Keyboard(live: true, languages: memory, contextEvaluator: model, detectorOverride: detector);
        keyboard.Type("onegaishimsu");
        Assert.Equal("onegaishimsu", keyboard.Showing, "Reproduce the learned English classification");
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal("おねがいします", keyboard.Showing);
        Assert.True(model.Requests.Any(r => r.Candidates.Contains("おねがいします")), "Offer a corrected reading despite learned English");
        var version = memory.Version;
        keyboard.Type("\n");
        Assert.Equal("おねがいします", keyboard.Host.Document);
        Assert.Equal(version, memory.Version, "Model inference must not become language preference");
    }

    [Test]
    public static void RomanMonitor_PreservesWordsProtectedInputAndExplicitModes()
    {
        foreach (var input in new[] { "meeting", "github", "camera", "https://example.com", "ps5", "ABC" })
        {
            var model = new Model();
            var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: model);
            keyboard.Type(input);
            var before = keyboard.Showing;
            keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
            Assert.Equal(before, keyboard.Showing, input);
            Assert.True(!model.Requests.Any(r => r.Candidates.Contains("おねがいします")), input);
        }
        var explicitModel = new Model();
        var explicitKeyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: explicitModel);
        explicitKeyboard.Type("onegaishimsu");
        explicitKeyboard.Press(VirtualKeys.F10);
        explicitKeyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal("onegaishimsu", explicitKeyboard.Showing);
    }

    [Test]
    public static void RomanMonitor_EnterWaitsForResultAndDoesNotSendAnotherEnter()
    {
        var model = new Model(delayed: true);
        var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: model);
        keyboard.Type("onegaishimsu\n");
        Assert.Equal("", keyboard.Host.Document, "Keep composition until the bounded evaluation finishes");
        model.Completion.SetResult("おねがいします");
        keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal("おねがいします", keyboard.Host.Document);
        Assert.True(!keyboard.Controller.IsComposing, "Commit exactly once");
    }

    [Test]
    public static void RomanMonitor_AbandonAndBackspaceDiscardLateInference()
    {
        foreach (var abandon in new[] { true, false })
        {
            var model = new Model(delayed: true);
            var keyboard = new CompositionTests.Keyboard(live: true, contextEvaluator: model);
            keyboard.Type("onegaishimsu");
            keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
            if (abandon) keyboard.Controller.Abandon("test focus changed");
            else keyboard.Press(VirtualKeys.Back);
            var before = keyboard.Showing;
            model.Completion.SetResult("おねがいします");
            keyboard.Controller.PollContextEvaluation(Environment.TickCount64 + 600);
            Assert.Equal(before, keyboard.Showing, "Never apply a result after edits or focus changes");
            Assert.Equal("", keyboard.Host.Document);
        }
    }
}
