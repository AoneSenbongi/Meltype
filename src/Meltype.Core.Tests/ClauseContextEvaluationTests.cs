// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;

namespace Meltype.Tests;

internal static class ClauseContextEvaluationTests
{
    private sealed class LastCandidate : IContextEvaluator
    {
        public readonly List<ContextRequest> Requests = [];
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token)
        { Requests.Add(request); return Task.FromResult<string?>(request.Candidates[^1]); }
    }
    private sealed class Deferred : IContextEvaluator
    {
        public readonly List<TaskCompletionSource<string?>> Calls = [];
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token)
        {
            var task = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
            Calls.Add(task); return task.Task;
        }
    }
    private static ContextClause Bridge => new("はし", ["橋", "箸"]);
    private static ContextClause Leather => new("かわ", ["川", "革"]);

    [Test]
    public static void ClauseContextEvaluation_LongInputChangesMultipleClausesAndKeepsLiterals()
    {
        var model = new LastCandidate();
        using var evaluation = new ClauseContextEvaluation(model, 0);
        var text = ContextLengthReplay.Pad(400);
        evaluation.Update([Bridge, new("GitHub: ", ["GitHub: "]), Leather, new(text, [text])], "前" + text, "後" + text, 0);
        Assert.Equal("箸GitHub: 革" + text, evaluation.Poll(0));
        Assert.Equal(2, model.Requests.Count);
        Assert.True(model.Requests.All(r => r.Reading.Length <= 64 && r.Candidates.All(c => c.Length <= 64)), "Never generate the whole long input");
        Assert.True(model.Requests.All(r => r.Left.Length <= 256 && r.Right.Length <= 128), "Bound context separately from output");
        Assert.True(model.Requests[0].Right.Contains("GitHub: 川"), "Later text is context");
        Assert.True(model.Requests[1].Left.EndsWith("箸GitHub: "), "Earlier accepted clause is context");
    }
    [Test]
    public static void ClauseContextEvaluation_LateResultCannotReplaceNewInput()
    {
        var model = new Deferred();
        using var evaluation = new ClauseContextEvaluation(model, 0);
        evaluation.Update([Bridge], "", "食卓", 0); evaluation.Poll(0);
        evaluation.Update([Leather], "", "くつ", 1);
        model.Calls[0].SetResult("箸"); evaluation.Poll(1);
        model.Calls[1].SetResult("革");
        Assert.Equal("革", evaluation.Poll(2));
        Assert.True(!evaluation.Pending, "Old generation must not survive");
    }
    [Test]
    public static void ClauseContextEvaluation_TimeoutKeepsCompletedClausesAndIgnoresLateWork()
    {
        var model = new Deferred();
        using var evaluation = new ClauseContextEvaluation(model, 0, 10);
        evaluation.Update([Bridge, Leather], "", "", 0); evaluation.Poll(0);
        model.Calls[0].SetResult("箸");
        Assert.True(evaluation.Poll(1) is null, "Do not display half a batch");
        Assert.Equal("箸川", evaluation.Poll(10));
        model.Calls[1].SetResult("革");
        Assert.True(evaluation.Poll(11) is null && !evaluation.Pending, "Late second clause is discarded");
    }
    [Test]
    public static void ClauseContextEvaluation_InvalidOutputAndResetDoNotChangeText()
    {
        var model = new Deferred();
        using var evaluation = new ClauseContextEvaluation(model, 0);
        evaluation.Update([Bridge], "", "", 0); evaluation.Poll(0);
        model.Calls[0].SetResult("候補外");
        Assert.Equal("橋", evaluation.Poll(1));
        evaluation.Update([Leather], "", "", 2); evaluation.Poll(2);
        evaluation.Reset(); model.Calls[1].SetResult("革");
        Assert.True(evaluation.Poll(3) is null && !evaluation.Pending, "Reset blocks result application");
    }
    [Test]
    public static void ClauseContextEvaluation_ReevaluationKeepsStablePrefixUntilFinished()
    {
        var model = new Deferred();
        using var evaluation = new ClauseContextEvaluation(model, 0, 10);
        evaluation.Update([Bridge], "", "", 0); evaluation.Poll(0); model.Calls[0].SetResult("箸");
        Assert.Equal("箸", evaluation.Poll(1));
        evaluation.Update([Bridge, Leather], "", "", 2); evaluation.Poll(2);
        Assert.Equal("箸川", evaluation.Poll(12), "A timed-out reevaluation retains the stable accepted prefix");
        evaluation.Update([Bridge], "別の文脈", "", 20); evaluation.Poll(20);
        Assert.Equal("橋", evaluation.Poll(30), "Changed surrounding context invalidates the previous choice");
    }
    [Test]
    public static void ClauseContextEvaluation_ChangedBaselineAndTooLongClauseAreProtected()
    {
        var model = new LastCandidate();
        using var evaluation = new ClauseContextEvaluation(model, 0);
        var longText = new string('あ', 65);
        evaluation.Update([new(longText, [longText, new string('い', 65)])], "", "", 0);
        Assert.Equal(longText, evaluation.Poll(0));
        Assert.Equal(0, model.Requests.Count, "Long single clauses are not sent");
    }
}
