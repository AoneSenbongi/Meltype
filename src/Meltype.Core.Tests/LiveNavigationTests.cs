using Meltype.Composition;
using Meltype.Input;

namespace Meltype.Tests;

internal static class LiveNavigationTests
{
    private sealed class ChangingConverter : IKanjiConverter
    {
        public int WholeCalls;
        public string? Convert(string reading) => reading switch { "せんか" => "専科", "せん" => "千", _ => null };
        public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null)
        {
            if (reading != "ひるまっくにせんか") return null;
            return ++WholeCalls == 1
                ? [new("ひるまっくに", "昼マックに"), new("せんか", "専科")]
                : [new("ひるま", "昼間"), new("っくに", "っくに"), new("せんか", "専科")];
        }
    }

    [Test]
    public static void LiveNavigation_ArrowKeepsDisplayedBoundariesAndSpaceCorrectsOnlyTarget()
    {
        var engine = new ChangingConverter();
        var k = new CompositionTests.Keyboard(live: true, converter: engine, legacyGoogleConversion: true);
        k.Type("hirumakkunisennka");
        Assert.Equal("昼マックに専科", k.Showing);
        var calls = engine.WholeCalls;
        k.Press(VirtualKeys.Left);
        Assert.Equal("昼マックに専科", k.Showing);
        Assert.Equal("昼マックに|専科", string.Join("|", k.Host.View!.Clauses!));
        Assert.Equal(calls, engine.WholeCalls, "Selecting a live clause must not reconvert the sentence");
        for (var i = 0; i < 30 && k.Showing != "昼マックにせんか"; i++) k.Press(VirtualKeys.Space);
        Assert.Equal("昼マックにせんか", k.Showing);
        k.Press(VirtualKeys.Return);
        Assert.Equal("昼マックにせんか", k.Host.Document);
    }

    private sealed class KanaModel : IContextEvaluator
    {
        public Task<string?> EvaluateAsync(ContextRequest request, CancellationToken token) =>
            Task.FromResult<string?>(request.Candidates.Contains("せんか") ? "せんか" : request.Candidates[0]);
    }

    [Test]
    public static void LiveNavigation_ArrowKeepsModelChoiceInsteadOfRestoringEngineChoice()
    {
        var k = new CompositionTests.Keyboard(live: true, converter: new ChangingConverter(), legacyGoogleConversion: true, contextEvaluator: new KanaModel());
        k.Type("hirumakkunisennka");
        k.Controller.PollContextEvaluation(Environment.TickCount64 + 300);
        Assert.Equal("昼マックにせんか", k.Showing);
        k.Press(VirtualKeys.Left);
        Assert.Equal("昼マックにせんか", k.Showing);
        k.Press(VirtualKeys.Return);
        Assert.Equal("昼マックにせんか", k.Host.Document);
    }

    [Test]
    public static void LiveNavigation_UpDownCandidatesAndShiftArrowsResize()
    {
        var k = new CompositionTests.Keyboard(live: true, converter: new ChangingConverter(), legacyGoogleConversion: true,
            tabConversion: true);
        k.Type("hirumakkunisennka");
        k.Press(VirtualKeys.Left);
        var first = k.Showing;
        var next = k.Host.View!.Candidates[1];
        k.Press(VirtualKeys.Down);
        Assert.Equal("昼マックに" + next, k.Showing);
        Assert.Equal(2, k.Host.View!.Clauses!.Count, "Down changes a candidate without changing boundaries");
        k.Press(VirtualKeys.Up);
        Assert.Equal(first, k.Showing);
        k.Key(VirtualKeys.LShift); k.Press(VirtualKeys.Left); k.Key(VirtualKeys.LShift, up: true);
        Assert.Equal("昼マックに|千|か", string.Join("|", k.Host.View!.Clauses!));
        k.Key(VirtualKeys.LShift); k.Press(VirtualKeys.Right); k.Key(VirtualKeys.LShift, up: true);
        Assert.Equal("昼マックに|専科", string.Join("|", k.Host.View!.Clauses!));
        for (var i = 0; i < 30 && k.Showing != "昼マックにせんか"; i++) k.Press(VirtualKeys.Tab);
        Assert.Equal("昼マックにせんか", k.Showing);
        k.Press(VirtualKeys.Return);
        Assert.Equal("昼マックにせんか", k.Host.Document);
    }
}
