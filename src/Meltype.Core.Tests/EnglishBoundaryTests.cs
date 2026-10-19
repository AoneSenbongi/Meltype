using Meltype.Input;

namespace Meltype.Tests;

internal static class EnglishBoundaryTests
{
    private static void Resize(CompositionTests.Keyboard k, int key)
    {
        k.Key(VirtualKeys.LShift);
        k.Press(key);
        k.Key(VirtualKeys.LShift, up: true);
    }

    [Test]
    public static void EnglishBoundary_LegacyEnglishClauseShrinksAndExpands()
    {
        var k = new CompositionTests.Keyboard(legacyGoogleConversion: true) { SeparateKeyRoles = true };
        k.Type("camera"); k.Press(VirtualKeys.Space);
        Assert.True(k.Host.View!.Converting && k.Host.View.Clauses!.Count == 1, "英語文節で変換を開始");
        Assert.Equal("camera", k.Showing, "操作前は英語のまま");
        Resize(k, VirtualKeys.Left);
        Assert.Equal(2, k.Host.View.Clauses!.Count, "英語誤判定の文節を縮める");
        Assert.Equal("かめ", k.Host.View.Clauses[0]);
        Assert.Equal("ら", k.Host.View.Clauses[1]);
        Resize(k, VirtualKeys.Right);
        Assert.Equal(1, k.Host.View.Clauses!.Count, "縮めた文節を伸ばして戻す");
        Assert.Equal("かめら", k.Showing);
        k.Type("\n");
        Assert.Equal("かめら", k.Host.Document);
    }

    [Test]
    public static void EnglishBoundary_JapaneseCanExpandIntoMisclassifiedEnglish()
    {
        var k = new CompositionTests.Keyboard(legacyGoogleConversion: true) { SeparateKeyRoles = true };
        k.Type("nihongocamera"); k.Press(VirtualKeys.Space);
        Assert.True(k.Host.View!.Clauses!.Count >= 2, "日英境界を持つ入力");
        Assert.Equal("camera", k.Host.View.Clauses[^1], "隣の文節は英語");
        var original = k.Showing;
        Resize(k, VirtualKeys.Right);
        Assert.True(k.Showing != original && !k.Showing.Contains("camera"), "日本語文節を英語部分へ伸ばせる");
        Assert.True(k.Showing.Contains("か"), "隣のローマ字の読みを使う");
    }

    [Test]
    public static void EnglishBoundary_ShiftArrowStartsResizeFromAutomaticEnglish()
    {
        var k = new CompositionTests.Keyboard(live: true, legacyGoogleConversion: true);
        k.Type("camera");
        Assert.Equal("camera", k.Showing);
        Resize(k, VirtualKeys.Left);
        Assert.True(k.Host.View is { Converting: true }, "英語表示中もShift+Leftで文節操作に入る");
        Assert.Equal(2, k.Host.View!.Clauses!.Count);
        Assert.Equal("かめら", k.Showing);
        k.Type("\n");
        Assert.Equal("かめら", k.Host.Document);
    }

    [Test]
    public static void EnglishBoundary_ImpossibleMovementKeepsEnglishLiteral()
    {
        foreach (var raw in new[] { "camera", "xyz" })
        {
            var k = new CompositionTests.Keyboard(legacyGoogleConversion: true) { SeparateKeyRoles = true };
            k.Type(raw); k.Press(VirtualKeys.Space);
            var before = k.Showing;
            Resize(k, VirtualKeys.Right);
            Assert.Equal(before, k.Showing, "後続がなければ表示を変えない");
            if (raw == "xyz") { Resize(k, VirtualKeys.Left); Assert.Equal(before, k.Showing, "かなの読みがない英字を保つ"); }
        }
    }
}
