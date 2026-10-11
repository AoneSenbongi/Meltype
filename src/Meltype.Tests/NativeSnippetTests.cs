// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;
using Meltype.Input;
namespace Meltype.Tests;

internal static class NativeSnippetTests
{
    private sealed class Host : ICompositionHost
    {
        public CompositionView? View;
        public string Committed = "";
        public void Show(CompositionView view) => View = view;
        public void Hide() => View = null;
        public void CommitText(string text) => Committed += text;
        public void DeleteBackward(int count) => throw new Exception("Must use TSF composition instead of deleting committed text");
        public void Replay(KeyEvent e) { }
        public void Replay(MouseButtonEvent e) { }
        public char? CharFromKey(KeyEvent e, bool shift) => null;
        public void RequestSurroundingText(Action<string?, string?> callback) => callback(null, null);
    }
    [Test]
    public static void NativeSnippet_ExpansionUndoAndMultilineCommit()
    {
        var store = new SnippetStore(null); store.Set("sig", "署名\n担当者");
        var host = new Host(); var session = new NativeSnippetSession(() => store, host);
        foreach (var c in ";sig") Assert.True(session.Handle(c == ';' ? 0xba : char.ToUpperInvariant(c), c, false, true), "名前を未確定範囲に表示する");
        Assert.Equal(";sig", host.View?.Text);
        Assert.True(session.Handle(0x20, ' ', false, false), "Spaceで展開する"); Assert.Equal("署名\n担当者", host.View?.Text);
        Assert.True(session.Handle(0x1b, '\0', false, false), "Escで復元する"); Assert.Equal(";sig", host.View?.Text);
        Assert.True(session.Handle(0x09, '\0', false, false), "Tabで展開する"); Assert.Equal("署名\n担当者", host.View?.Text);
        Assert.True(session.Handle(0x0d, '\r', false, false), "Enterで確定する"); Assert.Equal("署名\n担当者", host.Committed);
        Assert.True(host.View is null, "確定後の表示を消す");
    }
    [Test]
    public static void NativeSnippet_ProtectsCodeUnknownNamesAndReloads()
    {
        var store = new SnippetStore(null); store.Set("ty", "古い");
        var host = new Host(); var session = new NativeSnippetSession(() => store, host);
        Assert.True(!session.Handle(0xba, ';', false, false), "コード内のセミコロンは展開しない");
        foreach (var c in ";ty") session.Handle(c, c, false, true);
        store.Set("ty", "新しい"); session.Handle(0x20, ' ', false, false);
        Assert.Equal("新しい", host.View?.Text);
        session.Commit();
        foreach (var c in ";unknown") session.Handle(c, c, false, true);
        Assert.True(!session.Handle(0x20, ' ', false, false), "未登録の名前のSpaceは入力先へ渡す");
        Assert.Equal("新しい;unknown", host.Committed);
        foreach (var c in ";ty") session.Handle(c, c, false, true);
        session.Handle(0x08, '\0', false, false); Assert.Equal(";t", host.View?.Text);
        session.Handle(0x1b, '\0', false, false); Assert.True(host.View is null, "名前入力中のEscで取消する");
    }
}
