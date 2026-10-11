// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro

using Meltype.Config;
using Meltype.Input;
using Meltype.Composition;
using Meltype.IME;

namespace Meltype.Tests;

/// <summary>Windows 版だけのテスト。</summary>
internal static class WindowsTests
{
    [Test]
    public static void Main_RunsOnStaThread()
    {
        // クリップボード・UI は STA でないと動かない。Main の前にメソッドを足して、[STAThread] がそちらに付いていた (v1.2.0 の自己診断で失敗)
        var main = typeof(global::Meltype.Program).GetMethod("Main", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!;
        Assert.True(main.IsDefined(typeof(STAThreadAttribute), false), "Main に [STAThread]");
    }

    [Test]
    public static void Games_AreDetectedFromInstallFolder()
    {
        Assert.True(ForegroundTracker.LooksLikeGame(@"D:\SteamLibrary\steamapps\common\Apex Legends\r5apex.exe"), "Steam のゲーム");
        Assert.True(ForegroundTracker.LooksLikeGame(@"C:\Program Files\Epic Games\Fortnite\FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe"), "Epic のゲーム");
        Assert.True(ForegroundTracker.LooksLikeGame(@"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games\Rainbow Six Siege\RainbowSix.exe"), "Ubisoft のゲーム");
        Assert.True(ForegroundTracker.LooksLikeGame(@"C:\Program Files (x86)\SEGA\PHANTASYSTARONLINE2_JP\pso2_bin\pso2.exe"), "PSO2 NGS (専用のランチャー)");
        Assert.True(!ForegroundTracker.LooksLikeGame(@"C:\Program Files (x86)\Steam\steam.exe"), "Steam のクライアントは除く");
        Assert.True(!ForegroundTracker.LooksLikeGame(@"C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"), "ランチャーは除く");
        Assert.True(!ForegroundTracker.LooksLikeGame(@"C:\Program Files\Microsoft VS Code\Code.exe"), "ふつうのアプリ");

        var settings = new Settings();
        Assert.True(settings.IsGame("r5apex.exe", looksLikeGame: true), "ゲームのフォルダーなら止める");
        settings.StopInGames = false;
        Assert.True(!settings.IsGame("r5apex.exe", looksLikeGame: true), "設定で OFF にしたら止めない");
        settings.AppRules.Add(new AppRule { Process = "minecraft.exe", Enabled = true, Profile = AppProfile.Game });
        Assert.True(settings.IsGame("minecraft.exe", looksLikeGame: false), "アプリ別設定で「ゲーム」にしたら止める");
    }

    [Test]
    public static void MsIme_LongReading_IsSplitBeforeTheEngineLimit()
    {
        // #221: Microsoft IME の変換エンジンは 100 文字を超える読みを受け付けない (E_LARGEINPUT)。区切って渡す
        var sentence = "きょうはいいてんきですね、あしたもはれるといいですね。";
        var text = string.Concat(Enumerable.Repeat(sentence, 6)); // 162 文字
        var parts = Composition.MsImeKanjiConverter.SplitForEngine(text, 90);
        Assert.Equal(text, string.Concat(parts));
        Assert.True(parts.All(p => p.Length <= 90), string.Join(" / ", parts.Select(p => p.Length)));
        Assert.True(parts[0].EndsWith('。'), "文の切れ目で区切る: " + parts[0]);
        // 区切りの文字が無ければ上限で切る
        Assert.Equal("100,50", string.Join(",", Composition.MsImeKanjiConverter.SplitForEngine(new string('ー', 150), 100).Select(p => p.Length)));

        using var ime = new Composition.MsImeKanjiConverter();
        if (ime.Convert("てすと") is null) return; // Microsoft IME が無い環境
        var clauses = ime.ConvertClauses(text, "わたしは");
        Assert.True(clauses is { Count: > 0 }, "長い読みも文節に区切って変換できる");
        Assert.Equal(text, string.Concat(clauses!.Select(c => c.Reading)));
        Assert.True(string.Concat(clauses.Select(c => c.Text)).Contains("天気"), string.Concat(clauses.Select(c => c.Text)));
        Assert.True(ime.Convert(text)?.Contains("天気") == true, "全体の変換も");
    }

    [Test]
    public static void WebInputClassNames_AreTextInputs()
    {
        // #70: Chatwork の検索欄は Group で、クラス名 (sc-kzAZJu ijnNh inputLong) でしか入力欄と分からない
        foreach (var name in new[] { "sc-kzAZJu ijnNh inputLong", "input", "searchInput", "search-input", "chat_input", "input-field" })
            Assert.True(Composition.FocusInspector.LooksLikeInputClass(name), name);
        foreach (var name in new[] { "", "inputs", "input-group", "inputWrapper", "searchInputButton", "sc-kzAZJu ijnNh", "inputtable" })
            Assert.True(!Composition.FocusInspector.LooksLikeInputClass(name), name);
    }

    [Test]
    public static void StartupTask_IsLogonTriggerWithoutDelayAndAdmin()
    {
        // #283: サインインしたらすぐ起動するタスク。& などを含むユーザー名・パスでも XML として読める
        var xml = Startup.TaskXml(@"PC\R&D <user>", @"C:\Users\R&D\AppData\Local\Programs\Meltype\Meltype.exe");
        var document = System.Xml.Linq.XDocument.Parse(xml);
        System.Xml.Linq.XNamespace ns = "http://schemas.microsoft.com/windows/2004/02/mit/task";
        Assert.Equal(@"PC\R&D <user>", document.Descendants(ns + "LogonTrigger").Single().Element(ns + "UserId")!.Value);
        Assert.Equal("LeastPrivilege", document.Descendants(ns + "RunLevel").Single().Value, "管理者権限なし");
        Assert.True(!document.Descendants(ns + "Delay").Any(), "遅らせない");
        Assert.Equal(@"C:\Users\R&D\AppData\Local\Programs\Meltype\Meltype.exe", document.Descendants(ns + "Command").Single().Value);
        Assert.Equal(@"C:\Users\R&D\AppData\Local\Programs\Meltype", document.Descendants(ns + "WorkingDirectory").Single().Value);
    }

    [Test]
    public static void Startup_FallsBackToKeyboardWhenMeltypeImeIsUnusable()
    {
        // #366: 動作モードの初期値は Meltype IME。使えないときは、起動したときに Meltype キーボードに戻す
        var x64 = System.Runtime.InteropServices.Architecture.X64;
        var arm64 = System.Runtime.InteropServices.Architecture.Arm64;
        var fresh = new Settings();
        Assert.Equal(InputMode.Tsf, fresh.Mode, "初期値は Meltype IME");
        Assert.True(!global::Meltype.Program.ShouldFallBackToKeyboard(fresh, knownUnregistered: false, inUserLanguageList: true, x64), "登録済みで一覧にもある");
        Assert.True(global::Meltype.Program.ShouldFallBackToKeyboard(fresh, knownUnregistered: false, inUserLanguageList: true, arm64), "ARM64 は登録済みで一覧にあっても戻す");
        Assert.True(global::Meltype.Program.ShouldFallBackToKeyboard(fresh, knownUnregistered: true, inUserLanguageList: false, x64), "登録されていない");
        Assert.True(global::Meltype.Program.ShouldFallBackToKeyboard(fresh, knownUnregistered: false, inUserLanguageList: false, x64), "まだ切り替えたことがなく、一覧に無い");

        var introduced = new Settings { TsfIntroduced = true };
        Assert.True(!global::Meltype.Program.ShouldFallBackToKeyboard(introduced, knownUnregistered: false, inUserLanguageList: false, x64), "使っていた人は、一覧に無くても戻さない");
        Assert.True(global::Meltype.Program.ShouldFallBackToKeyboard(introduced, knownUnregistered: false, inUserLanguageList: true, arm64), "使っていた人も、ARM64 なら戻す");
        Assert.True(!global::Meltype.Program.ShouldFallBackToKeyboard(new Settings { Mode = InputMode.Keyboard }, knownUnregistered: true, inUserLanguageList: false, arm64), "Meltype キーボードはそのまま");
    }

    [Test]
    public static void AffinityCandidate_RejectsOtherProductsAndMenus()
    {
        Assert.True(FocusInspector.IsAffinityCanvasCandidate("AFFINITY.EXE", UiAutomation.ControlTypePane, "Static"), "大小文字と Pane");
        Assert.True(!FocusInspector.IsAffinityCanvasCandidate("Photo.exe", UiAutomation.ControlTypeText, "Static"), "旧製品は対象外");
        Assert.True(!FocusInspector.IsAffinityCanvasCandidate("Affinity.exe", 50009, "Static"), "メニューは対象外");
    }
    [Test]
    public static void AffinityIme_UsesOneDeadlineAndStopsAfterFailure()
    {
        double now = 0; var budgets = new List<uint>();
        var active = Imm32ImeController.HasInputContext(20, (_, remaining) => { budgets.Add(remaining); now += 9.75; return (true, 0); }, () => TimeSpan.FromMilliseconds(now));
        Assert.True(!active, "ゼロの応答は入力可能としない");
        Assert.True(string.Join(',', budgets) == "20,10", "残り 10.25ms は 10ms に切り捨て、0.5ms では問い合わせない");
        foreach (var success in new[] { false, true })
        {
            now = 0; var calls = 0;
            active = Imm32ImeController.HasInputContext(20, (_, _) => { calls++; now = success ? 21 : 0; return (success, 0x19); }, () => TimeSpan.FromMilliseconds(now));
            Assert.True(!active && calls == 1, "失敗や期限後の肯定結果を採用せず、追加の問い合わせをしない");
        }
    }
}
