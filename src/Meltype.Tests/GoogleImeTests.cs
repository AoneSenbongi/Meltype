// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;
using P = Meltype.Composition.GoogleImeConverter.Proto;

namespace Meltype.Tests;

internal static class GoogleImeTests
{
    [Test]
    public static void GooglePunctuation_RestoresWidthAndRejectsDifferentReadings()
    {
        foreach (var returned in new[] { "にほんご?", "にほんこ?", "ｎほんご?" })
        {
            var converter = new GoogleImeConverter(request => {
                var kind = P.Parse(request).Int(1);
                if (kind == 1) return P.Number(1, 12345);
                if (kind != 3) return [];
                var first = new byte[] { 19 }.Concat(P.String(4, "日本語")).Concat(P.String(6, returned[..^1])).Concat(new byte[] { 20 });
                var mark = new byte[] { 19 }.Concat(P.String(4, "?")).Concat(P.String(6, "?")).Concat(new byte[] { 20 });
                return P.Blob(5, first.Concat(mark).ToArray()).Concat(P.Blob(14, P.Blob(2, P.String(4, "?")))).ToArray();
            });
            var clauses = converter.ConvertClauses("にほんご？");
            if (returned == "にほんご?")
            {
                Assert.Equal("日本語？", string.Concat(clauses!.Select(c => c.Text)));
                Assert.Equal("にほんご？", string.Concat(clauses.Select(c => c.Reading)));
                Assert.Equal("？", converter.Candidates("？").Single());
            }
            else Assert.True(clauses is null, "記号の幅以外の読みの違いは拒否する");
        }
    }
    [Test]
    public static void GoogleProto_ReadsLargeSessionIdAndGroups()
    {
        var session = (1UL << 63) + 43;
        Assert.Equal(session, P.Parse(P.Number(1, session)).Int(1));
        var group = new byte[] { 19 }.Concat(P.String(4, "橋")).Concat(P.String(6, "はし")).Concat(new byte[] { 20 }).ToArray();
        Assert.Equal("橋", P.Parse(group).Groups(2).Single().Text(4));
    }

    [Test]
    public static void GoogleProto_RejectsTruncatedAndUnterminatedResponses()
    {
        foreach (var data in new byte[][] { [128], [0], [10, 4, 1], [19], [19, 28], [8, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255] })
        {
            var rejected = false;
            try { P.Parse(data); } catch (InvalidDataException) { rejected = true; }
            Assert.True(rejected, "Malformed response must be rejected");
        }
    }

    [Test]
    public static void GoogleFailure_DeletesPrivateSessionAndDoesNotWriteConfig()
    {
        var commands = new List<ulong>();
        var converter = new GoogleImeConverter(request =>
        {
            var kind = P.Parse(request).Int(1);
            commands.Add(kind);
            if (kind == 1) return P.Number(1, 12345);
            if (kind == 17) throw new IOException("simulated disconnect");
            return [];
        });
        Assert.True(converter.Convert("はし") is null, "Connection failure returns no conversion");
        Assert.Equal("1,17,2", string.Join(",", commands));
    }

    [Test]
    public static void GoogleInvalidReading_DoesNotContactServer()
    {
        var converter = new GoogleImeConverter(_ => throw new Exception("must not connect"));
        foreach (var reading in new[] { "", "あ\n", new string('あ', 101) })
            Assert.True(converter.Convert(reading) is null, "Invalid reading rejected before connection");
    }

    private static byte[] Preedit(string reading, string value) =>
        P.Blob(5, new byte[] { 19 }.Concat(P.String(4, value)).Concat(P.String(6, reading)).Concat(new byte[] { 20 }).ToArray());

    private static GoogleImeConverter LearningMock(List<string> commands, bool candidateExists = true, bool sameBoundary = true,
        Func<bool>? learningEnabled = null, Action? highlighted = null)
    {
        var selected = "構成";
        return new GoogleImeConverter(request =>
        {
            var input = P.Parse(request);
            var kind = input.Int(1);
            var command = input.Message(4).Int(1);
            commands.Add($"{kind}:{command}");
            if (kind == 1) return P.Number(1, 12345);
            if (kind == 17) { Assert.Equal(0UL, input.Message(9).Int(23)); return []; }
            if (kind == 5 && command == 4) { selected = "校正"; highlighted?.Invoke(); return Preedit("こうせい", selected); }
            if (kind == 5 && command == 2) return P.Blob(4, P.Number(1, 1).Concat(P.String(2, selected)).ToArray());
            if (kind == 3)
            {
                var candidates = candidateExists ? P.Blob(14, P.Blob(2, P.Number(1, 7).Concat(P.String(4, "校正")).ToArray())) : [];
                return Preedit(sameBoundary ? "こうせい" : "こう", selected).Concat(candidates).ToArray();
            }
            return [];
        }, learning: true) { LearningEnabled = learningEnabled ?? (() => true) };
    }

    [Test]
    public static void GoogleLearning_CommitsOnlyAnExactlyMatchedCandidate()
    {
        var commands = new List<string>();
        var converter = LearningMock(commands);
        Assert.True(converter.TryLearn(null, [new("こうせい", "校正")]), "Matching candidate learned");
        Assert.Equal("6:0,1:0,17:0,5:22,5:26,3:0,5:4,5:2,8:0,2:0", string.Join(",", commands));
    }
    [Test]
    public static void GoogleLearning_StopBeforeSubmit()
    {
        var enabled = false;
        var commands = new List<string>();
        var converter = LearningMock(commands, learningEnabled: () => enabled, highlighted: () => enabled = false);
        Assert.True(!converter.TryLearn(null, [new("こうせい", "校正")]), "Stopped learning must not contact Google");
        Assert.Equal(0, commands.Count);
        enabled = true;
        Assert.True(!converter.TryLearn(null, [new("こうせい", "校正")]), "Stop during candidate selection must cancel submit");
        Assert.True(!commands.Contains("5:2") && !commands.Contains("8:0"), "No submission or persistence after stop");
    }

    [Test]
    public static void GoogleLearning_SkipsMissingCandidatesAndChangedBoundaries()
    {
        foreach (var missing in new[] { true, false })
        {
            var commands = new List<string>();
            var converter = LearningMock(commands, candidateExists: !missing, sameBoundary: missing);
            Assert.True(!converter.TryLearn(null, [new("こうせい", "校正")]), "Unmatched conversion must not be learned");
            Assert.True(!commands.Contains("5:2") && !commands.Contains("8:0"), "No submit or persistence on mismatch");
            Assert.Equal("2:0", commands.Last(), "Private session always deleted");
        }
    }

    [Test]
    public static void GoogleLearning_ReadOnlyModeNeverSubmits()
    {
        var converter = new GoogleImeConverter(_ => throw new Exception("must not contact server"));
        Assert.True(!converter.TryLearn(null, [new("こうせい", "校正")]), "Learning is opt-in");
    }

    [Test]
    public static void GoogleLearning_RespectsGlobalReadOnlyConfiguration()
    {
        foreach (var config in new[] { P.Number(50, 1), P.Number(20, 1) })
        {
            var calls = new List<ulong>();
            var converter = new GoogleImeConverter(request =>
            {
                var kind = P.Parse(request).Int(1);
                calls.Add(kind);
                return P.Blob(9, config);
            }, learning: true);
            Assert.True(!converter.TryLearn(null, [new("こうせい", "校正")]), "Global learning prohibition must be respected");
            Assert.Equal("6", string.Join(",", calls), "Read configuration only, without submitting");
        }
    }

    public static int VerifyLearning()
    {
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);
        var converter = new GoogleImeConverter(learning: true);
        var before = converter.Convert("こうせい");
        Assert.True(converter.Candidates("こうせい").Contains("校正"), "Google has the selected candidate");
        Assert.True(converter.TryLearn(null, [new("こうせい", "校正")]), "Submit and sync succeeded");
        var after = new GoogleImeConverter(learning: true).Convert("こうせい");
        Console.WriteLine($"Google学習: こうせい ({before} → {after})");
        foreach (var entry in Diagnostics.Log.Snapshot()) Console.WriteLine(entry);
        Assert.Equal("校正", after, "A new normal session uses the learned candidate");
        Console.WriteLine("Google本体への学習追加・新しいセッションへの反映: PASS");
        return 0;
    }

    // Explicit command only: does not run in the regular offline test suite.
    public static int VerifyInstalledGoogle()
    {
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);
        var converter = new GoogleImeConverter();
        var clauses = converter.ConvertClauses("きょうはいいてんき");
        Assert.True(clauses is { Count: > 0 }, "Installed Google must return clauses");
        Assert.Equal("今日はいい天気", string.Concat(clauses!.Select(c => c.Text)));
        foreach (var clause in clauses)
        {
            var candidates = converter.Candidates(clause.Reading);
            Assert.True(candidates.Contains(clause.Text), "Each clause must have candidates");
            Console.WriteLine($"{clause.Reading}: {string.Join(", ", candidates.Take(5))}");
        }
        var bridge = converter.Candidates("はし");
        Assert.True(bridge.Contains("橋") && bridge.Contains("箸") && bridge.Contains("端"), "Google alternative candidates");
        Assert.Equal("3時", converter.Convert("3じ"), "Numbers mixed with Japanese");
        foreach (var (key, mark, fullWidth) in new[] { (",", "、", false), (".", "。", false), (",", "，", true), (".", "．", true), ("?", "？", true), ("!", "！", true), ("?!?", "？！？", true) })
        foreach (var space in new[] { false, true })
        {
            var live = new CompositionTests.Keyboard(live: true, converter: converter, moreCandidates: converter.Candidates, fullWidthCommaPeriod: fullWidth);
            live.Type("kyouhaiitenki");
            var before = live.Showing;
            Assert.Equal("今日はいい天気", before);
            live.Type(key);
            Assert.Equal(before + mark, live.Showing, "Punctuation must preserve live conversion");
            Assert.Equal(0, live.Host.Output.Count, "Punctuation must not commit");
            if (space) { live.Type(" "); Assert.Equal(before + mark, live.Showing, "Space preserves converted text and punctuation"); }
            live.Type("\n");
            Assert.Equal(before + mark, live.Host.Document, "Enter preserves converted text and punctuation");
        }
        foreach (var comma in new[] { '、', '，', ',' })
        foreach (var period in new[] { '。', '．', '.' })
        foreach (var key in new[] { ',', '.' })
        {
            var live = new CompositionTests.Keyboard(live: true, converter: converter, moreCandidates: converter.Candidates, comma: comma, period: period);
            live.Type("kyouhaiitenki");
            live.Type(key.ToString());
            var expected = "今日はいい天気" + (key == ',' ? comma : period);
            Assert.Equal(expected, live.Showing, "Selected punctuation preserves live conversion");
            live.Type(" \n");
            Assert.Equal(expected, live.Host.Document, "Selected punctuation survives Space and commit");
        }
        var mixedLive = new CompositionTests.Keyboard(live: true, converter: converter, moreCandidates: converter.Candidates, fullWidthCommaPeriod: true);
        mixedLive.Type("kyouhagoogledekensaku");
        var mixedBefore = mixedLive.Showing;
        mixedLive.Type("?");
        Assert.Equal(mixedBefore + "？", mixedLive.Showing, "日英混在のライブ変換も保持する");
        mixedLive.Type("\n");
        Assert.Equal(mixedBefore + "？", mixedLive.Host.Document);
        var keyboard = new CompositionTests.Keyboard(live: false, converter: converter, moreCandidates: converter.Candidates);
        keyboard.Type("kyouhagithubnipushshita ");
        keyboard.Type("\n");
        var output = string.Concat(keyboard.Host.Output);
        Console.WriteLine("日英混在: " + output);
        Assert.Equal("今日はgithubにpushした", output);
        foreach (var entry in Diagnostics.Log.Snapshot()) Console.WriteLine(entry);
        Console.WriteLine("Google本体との接続・文節変換・候補取得・日英混在入力: PASS");
        return 0;
    }
}
