// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;
using Meltype.Config;

namespace Meltype.Tests;

internal static class NativeEngineTests
{
    [Test]
    public static void NativeEngine_MicrosoftConvertsAcrossCallerThreads()
    {
        using var engine = new NativeEngineConverter("Microsoft", false, () => false);
        Assert.Equal("日本語", Task.Run(() => engine.Convert("にほんご")).GetAwaiter().GetResult());
        var clauses = Task.Run(() => engine.ConvertClauses("きょうはいいてんき")).GetAwaiter().GetResult();
        Assert.True(clauses is { Count: > 0 } && string.Concat(clauses.Select(c => c.Text)) != "きょうはいいてんき", "Microsoftの文節変換を使う");
        var candidates = Task.Run(() => engine.Candidates("はし")).GetAwaiter().GetResult();
        Assert.True(candidates.Count > 1 && candidates.Contains("橋"), "本家のWindows候補APIを使う");
        engine.Learn(null, [new("にほんご", "日本語")]);
        Assert.Equal("日本語", engine.Convert("にほんご"), "学習無効でも変換できる");
    }
    [Test]
    public static void NativeEngine_PreferencesRemainCompatible()
    {
        Assert.Equal("Google", new InputPreferences().ConversionEngine);
        Assert.Equal("Microsoft", (new InputPreferences { ConversionEngine = "Microsoft" }).Validate().ConversionEngine);
        Assert.Equal("Google", (new InputPreferences { ConversionEngine = "unknown" }).Validate().ConversionEngine);
    }
}
