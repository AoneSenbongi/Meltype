// SPDX-License-Identifier: GPL-3.0-or-later
using System.Text.Json;
using Meltype.Config;

namespace Meltype.Tests;

internal static class NativePreReleaseTests
{
    private sealed class NumericConverter : Meltype.Composition.IKanjiConverter
    {
        public List<string> Readings { get; } = [];
        public IReadOnlyList<Meltype.Composition.ConversionClause>? ConvertClauses(string reading, string? context = null) =>
            Convert(reading) is { } result ? [new(reading, result)] : null;
        public string? Convert(string reading) { Readings.Add(reading); return reading switch {
            "ばい" => "倍", "びょう" => "秒", "じかん" => "時間", "えん" => "円",
            "0.75ばい" => "0.75倍", "2.0びょう" => "2.0秒", "0.5じかん" => "0.5時間", "100えん" => "100円", _ => null
        }; }
    }

    [Test]
    public static void NativePreRelease_NumericUnitsKeepLiveConversion()
    {
        foreach (var (raw, expected) in new[] { ("0.75bai", "0.75倍"), ("2.0byou", "2.0秒"), ("0.5jikann", "0.5時間"), ("100enn", "100円") })
        {
            var converter = new NumericConverter();
            var keyboard = new CompositionTests.Keyboard(live: true, converter: converter, legacyGoogleConversion: true);
            keyboard.Type(raw);
            Assert.Equal(expected, keyboard.Showing, raw + "のライブ変換: " + string.Join(" | ", converter.Readings));
            keyboard.Type("\n");
            Assert.Equal(expected, keyboard.Host.Document, raw + "の確定");
        }
    }

    [Test]
    public static void NativePreRelease_PreferencesRoundTripAndLegacyDefaults()
    {
        var folder = Path.Combine(Path.GetTempPath(), "Meltype-pre2-" + Guid.NewGuid());
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, "input-preferences.json");
        try
        {
            File.WriteAllText(path, "{\"ConversionEngine\":\"Google\",\"DirectModeAutoDetect\":false,\"TabConversion\":true}");
            var store = new InputPreferenceStore(path);
            using (var old = JsonDocument.Parse(JsonSerializer.Serialize(store.Current)))
            {
                Assert.True(old.RootElement.TryGetProperty("CalculatorCandidates", out var calc) && calc.GetBoolean(), "計算候補の既定値");
                Assert.True(old.RootElement.GetProperty("FunctionKeysAffectSelectedClause").GetBoolean(), "現行の文節Fキーを維持");
                Assert.True(!old.RootElement.GetProperty("ShiftSpaceHalfWidth").GetBoolean(), "Shift+Spaceの全角を維持");
            }
            File.WriteAllText(path, "{\"ConversionEngine\":\"Microsoft\",\"DirectModeAutoDetect\":false,\"LearningEnabled\":false,\"CalculatorCandidates\":false,\"EscStepsBack\":true,\"EnterCommitsAsShown\":true,\"SquareBrackets\":true,\"ControlKeyBindings\":\"T=F6;Y=F7\"}");
            store.Save(store.Current);
            using var value = JsonDocument.Parse(File.ReadAllText(path));
            Assert.Equal("Microsoft", value.RootElement.GetProperty("ConversionEngine").GetString());
            Assert.True(!value.RootElement.GetProperty("LearningEnabled").GetBoolean(), "学習停止を保持");
            Assert.True(!value.RootElement.GetProperty("DirectModeAutoDetect").GetBoolean(), "英語直接入力を保持");
            Assert.True(!value.RootElement.GetProperty("CalculatorCandidates").GetBoolean(), "計算候補OFFを保存");
            foreach (var name in new[] { "EscStepsBack", "EnterCommitsAsShown", "SquareBrackets" })
                Assert.True(value.RootElement.GetProperty(name).GetBoolean(), name);
            Assert.Equal("T=F6;Y=F7", value.RootElement.GetProperty("ControlKeyBindings").GetString());
        }
        finally { Directory.Delete(folder, recursive: true); }
    }
}
