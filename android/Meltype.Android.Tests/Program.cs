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

var liveDocument = "";
var live = new AndroidInputSession(new FakeConverter(), reading => reading switch
{
    "にほんご" => ["日本語", "日本語版"],
    "でけんさく" => ["で検索", "で探索"],
    _ => [],
}, (operation, text, _) => { if (operation == 1) liveDocument += text; });
foreach (var c in "nihongo") live.Character(c);
if (live.View is not { Converting: false } || !live.View.Candidates.Contains("日本語版")) throw new Exception("Live candidates are not visible before Space.");
Equal("", liveDocument);
live.Select(live.View.Candidates.ToList().IndexOf("日本語版"));
Equal("日本語版", liveDocument);
liveDocument = ""; live.Reset();
foreach (var c in "kyouhagoogledekensaku") live.Character(c);
if (live.View is not { Converting: false } || !live.View.Candidates.Contains("で探索")) throw new Exception("Mixed live candidates are missing.");
live.Select(live.View.Candidates.ToList().IndexOf("で探索"));
Equal("今日はgoogleで探索", liveDocument);
live.SetEnglish(true); live.Character('a');
if (live.View != null) throw new Exception("English mode retained Japanese candidates.");
Console.WriteLine("PASS: live candidates before Space, no early commit, candidate selection preserves mixed text, English mode clears candidates");

sealed class FakeConverter : IKanjiConverter
{
    public string? Convert(string reading) => string.Concat(ConvertClauses(reading)!.Select(c => c.Text));
    public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null) =>
        new[] { new ConversionClause(reading, reading.Replace("きょうは", "今日は").Replace("にほんご", "日本語").Replace("けんさく", "検索")) };
}
