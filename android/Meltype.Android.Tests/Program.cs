// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.AndroidCore;
using Meltype.Composition;

var converter = new FakeConverter();
var document = "";
var preedit = "";
var session = new AndroidInputSession(converter, _ => [], (operation, text, _) =>
{
    if (operation == 0) preedit = text;
    if (operation == 1) { document += text; preedit = ""; }
    if (operation == 2) preedit = "";
});
void Type(string raw) { foreach (var c in raw) session.Character(c); }
void Equal(string expected, string actual)
{
    if (expected != actual) throw new Exception($"Expected {expected}, got {actual}");
}
Type("kyouha"); Equal("今日は", preedit);
session.SetEnglish(true); Equal("今日は", document);
Type("nihongo,."); Equal("今日はnihongo,.", document);
Equal("", preedit);
session.SetEnglish(false);
Type("nihongo"); Equal("日本語", preedit);
Type("?"); Equal("日本語？", preedit);
session.Commit(); Equal("今日はnihongo,.日本語？", document);
session.Reset();
Type("kyouhagoogledekensaku"); Equal("今日はgoogleで検索", preedit);
Type("."); Equal("今日はgoogleで検索．", preedit);
session.Key(0x1B); Equal("", preedit);
Console.WriteLine("PASS: automatic detection, punctuation, mode toggle, preserving pending input, cancellation");

sealed class FakeConverter : IKanjiConverter
{
    public string? Convert(string reading) => string.Concat(ConvertClauses(reading)!.Select(c => c.Text));
    public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null) =>
        new[] { new ConversionClause(reading, reading.Replace("きょうは", "今日は").Replace("にほんご", "日本語").Replace("けんさく", "検索")) };
}
