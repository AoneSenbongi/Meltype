// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;
using Meltype.Config;

namespace Meltype.Tests;

internal static class InputPreferenceTests
{
    [Test]
    public static void Punctuation_AllPairs_AndEnglish()
    {
        foreach (var comma in new[] { '、', '，', ',' })
        foreach (var period in new[] { '。', '．', '.' })
        {
            var text = new CompositionText(CompositionDetector.CreateDefault())
                { Comma = () => comma, Period = () => period };
            foreach (var c in "nihongo,.") text.Append(c);
            Assert.Equal("にほんご" + comma + period, text.Display(true));
            text.Clear();
            foreach (var c in "hello,.") text.Append(c);
            Assert.Equal("hello,.", text.Display(true));
        }
    }

    [Test]
    public static void Preferences_SaveReload_StopAndKeepHistory()
    {
        var dir = Path.Combine(Path.GetTempPath(), "MeltypePreference-" + Guid.NewGuid());
        var path = Path.Combine(dir, "input-preferences.json");
        try
        {
            var store = new InputPreferenceStore(path);
            Assert.Equal("，", store.Current.Comma);
            Directory.CreateDirectory(dir);
            File.WriteAllText(path, "{\"LearningEnabled\":false,\"ConversionEngine\":\"Microsoft\"}");
            Assert.True(store.Current.DirectModeAutoDetect && store.Current.TabConversion, "旧設定では本家と同じ初期値を使う");
            store.Save(new InputPreferences { Comma = "、", Period = ".", LearningEnabled = false, DirectModeAutoDetect = false, TabConversion = false });
            var other = new InputPreferenceStore(path);
            Assert.Equal("、", other.Current.Comma);
            Assert.Equal(".", other.Current.Period);
            Assert.Equal(false, other.Current.LearningEnabled);
            store.Save(other.Current with { LearningEnabled = true });
            Assert.Equal(true, other.Current.LearningEnabled);
            Assert.True(!other.Current.DirectModeAutoDetect && !other.Current.TabConversion, "学習設定の変更は入力機能の選択を保持する");
            File.WriteAllText(path, "{broken");
            Assert.Equal(false, new InputPreferenceStore(path).Current.LearningEnabled);
        }
        finally
        {
            if (Directory.Exists(dir))
            {
                foreach (var file in Directory.GetFiles(dir)) File.Delete(file);
                Directory.Delete(dir);
            }
        }
    }

    [Test]
    public static void LearningEnabled_DoesNotSendClauseBoundariesToConverter()
    {
        // 本家 issue #2014: 確定した文節の区切りを変換エンジンに覚えさせると、誤った区切りが固定される。
        // 学習が ON でも、区切りは Meltype 側にだけ覚える (Shift+矢印で動かしたとき)。変換エンジンには送らない。
        var gate = new CaptureGate(() => { });
        var host = new CompositionTests.FakeHost();
        var learner = new LearningSpy();
        var controller = new CompositionController(gate, CompositionDetector.CreateDefault(), learner, host,
            new CompositionOptions { LearningEnabled = () => true });
        void Key(int code)
        {
            foreach (var up in new[] { false, true })
            {
                gate.OnKey(new Meltype.Input.KeyEvent(code, 0, false, up, false, 1000), e => e.IsDown);
                controller.Pump();
            }
        }
        foreach (var c in "nihongo") Key(char.ToUpperInvariant(c));
        Key(0x20); Key(0x0d);
        Assert.Equal(0, learner.Calls, "Google / Mozc には文節の区切りを学習させない");
        Assert.Equal("日本語", host.Document);
    }
    private sealed class LearningSpy : IKanjiConverter, ILearningConverter
    {
        public int Calls;
        public string? Convert(string reading) => "日本語";
        public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null) => [new(reading, "日本語")];
        public void Learn(string? context, IReadOnlyList<ConversionClause> clauses) => Interlocked.Increment(ref Calls);
    }
}
