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
}
