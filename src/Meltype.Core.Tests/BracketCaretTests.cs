// SPDX-License-Identifier: GPL-3.0-or-later
namespace Meltype.Tests;

internal static class BracketCaretTests
{
    [Test]
    public static void BracketCaret_TrailingPairAfterSentenceMovesOnce()
    {
        foreach (var enabled in new[] { false, true })
        {
            var k = new CompositionTests.Keyboard(legacyGoogleConversion: true) { CursorIntoBrackets = enabled };
            k.Type("nihongo[]\n");
            Assert.True(k.Host.Document.EndsWith("「」"), "sentence ends with empty pair");
            Assert.Equal(enabled ? 1 : 0, k.Host.Events.Count(e => e == "down:25"));
        }
    }

    [Test]
    public static void BracketCaret_ShiftedParenthesesCommitAndMoveOnce()
    {
        foreach (var fullWidth in new[] { false, true })
        {
            var k = new CompositionTests.Keyboard(legacyGoogleConversion: true)
            { CursorIntoBrackets = true, FullWidthParentheses = fullWidth };
            k.Type("()\n");
            Assert.Equal(fullWidth ? "（）" : "()", k.Host.Document);
            Assert.Equal(1, k.Host.Events.Count(e => e == "down:25"), "one caret move after pair commit");
        }
    }

    [Test]
    public static void BracketCaret_DisabledOrNonemptyPairDoesNotMove()
    {
        foreach (var (text, enabled) in new[] { ("()", false), ("(a)", true), ("(", true) })
        {
            var k = new CompositionTests.Keyboard(legacyGoogleConversion: true) { CursorIntoBrackets = enabled };
            k.Type(text + "\n");
            Assert.Equal(0, k.Host.Events.Count(e => e == "down:25"));
        }
    }
}
