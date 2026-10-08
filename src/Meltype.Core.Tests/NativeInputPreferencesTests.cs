// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;

namespace Meltype.Tests;

internal static class NativeInputPreferencesTests
{
    [Test]
    public static void NativeInput_FullWidthCommaPeriod()
    {
        foreach (var (raw, expected) in new[] { ("nihongo,nihongo.", "にほんご，にほんご．"), (",.", "，．"), ("google.com", "google.com"), ("1,000.25", "1,000.25") })
        {
            var text = new CompositionText(CompositionDetector.CreateDefault()) { FullWidthCommaPeriod = true };
            foreach (var c in raw) text.Append(c);
            Assert.Equal(expected, text.Display(final: true));
        }
    }
    [Test]
    public static void NativeInput_ArrowSequences()
    {
        foreach (var (raw, expected) in new[] { ("zh", "←"), ("zj", "↓"), ("zk", "↑"), ("zl", "→"), ("zhzjzkzl", "←↓↑→") })
        {
            var k = new CompositionTests.Keyboard();
            k.Type(raw);
            Assert.Equal(expected, k.Showing);
            k.Type("\n");
            Assert.Equal(expected, k.Host.Document);
        }
        var english = new CompositionTests.Keyboard();
        english.Type("puzzle\n");
        Assert.True(!english.Host.Document.Contains('→'), "英単語の途中のzlは矢印にしない");
    }

    [Test]
    public static void NativeInput_ArrowsInsideJapaneseWithoutSpace()
    {
        foreach (var (raw, expected) in new[] { ("nihongozlnihongo", "にほんご→にほんご"), ("nihongozhzjzkzlnihongo", "にほんご←↓↑→にほんご") })
        {
            var text = new CompositionText(CompositionDetector.CreateDefault());
            foreach (var c in raw) text.Append(c);
            Assert.Equal(expected, text.Display(final: true));
        }
    }

    [Test]
    public static void NativeInput_OpeningBracketFollowsNextLanguage()
    {
        foreach (var (raw, expected) in new[] { ("[nihongo", "「にほんご"), ("[nihongo]", "「にほんご」"), ("[google", "[google"), ("[google]", "[google]"), ("[hello world]", "[hello world]") })
        {
            var k = new CompositionTests.Keyboard(legacyGoogleConversion: true);
            k.Type(raw);
            Assert.Equal(expected, k.Host.Document + k.Showing);
            k.Type("\n");
            Assert.Equal(expected, k.Host.Document);
        }
    }

    [Test]
    public static void NativeInput_LegacyGoogleKeepsPreviousLanguageDecisions()
    {
        // 公開1.0.5の実アセンブリとの比較で確認した判定。1.1.0の判定改善はNative版に適用しない。
        foreach (var (raw, expected) in new[] { ("hosuthingu", "ほすthinぐ"), ("reflectsareta", "reflectsareta"), ("shiranhito", "しらんひと") })
        {
            var text = new CompositionText(CompositionDetector.CreateDefault(legacyGoogleConversion: true));
            foreach (var c in raw) text.Append(c);
            Assert.Equal(expected, text.Display(final: true));
        }
    }

    [Test]
    public static void NativeInput_PredictionDoesNotOverrideLegacyLiveConversion()
    {
        var phrases = new PhraseHistory(null);
        phrases.Remember("きょうはいいてんき", "今日は良い天気");
        var k = new CompositionTests.Keyboard(live: true, legacyGoogleConversion: true,
            predictor: new Predictor(phrases, null, null));
        k.Type("kyouha");
        Assert.Equal("今日は", k.Showing, "選ぶまでは変換エンジンの結果を維持する");
        Assert.True(k.Host.View!.Predictions!.Contains("今日は良い天気"), "予測は別の候補として表示する");
        k.Press(Input.VirtualKeys.Tab);
        Assert.Equal("今日は良い天気", k.Showing);
        k.Press(Input.VirtualKeys.Escape);
        Assert.Equal("今日は", k.Showing);
        k.Press(Input.VirtualKeys.Space);
        Assert.Equal("今日は", k.Showing, "Spaceも従来の変換結果を使う");
    }
}
