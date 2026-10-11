// SPDX-License-Identifier: GPL-3.0-or-later
namespace Meltype.Composition;

/// <summary>Native TSFの未確定範囲で本家の定型文を展開する。</summary>
public sealed class NativeSnippetSession(Func<SnippetStore> load, ICompositionHost host)
{
    private string? _typed;
    private string? _expanded;
    public bool Active => _typed is not null;

    public bool Handle(int vk, char character, bool up, bool boundary)
    {
        if (up) return Active;
        if (_typed is null)
        {
            if (character != ';' || !boundary || load().Count == 0) return false;
            _typed = ";"; Show(_typed); return true;
        }
        if (vk == 0x1b)
        {
            if (_expanded is not null) { _expanded = null; Show(_typed); }
            else { _typed = null; host.Hide(); }
            return true;
        }
        if (_expanded is not null)
        {
            Commit(); return vk == 0x0d;
        }
        if (vk == 0x20 || vk == 0x09)
        {
            var text = load().Get(_typed[1..]);
            if (text is null) { Commit(); return false; }
            _expanded = text; Show(text); return true;
        }
        if (vk == 0x08)
        {
            _typed = _typed[..^1];
            if (_typed.Length == 0) { _typed = null; host.Hide(); }
            else Show(_typed);
            return true;
        }
        if (character != '\0' && SnippetStore.IsNameChar(character))
        {
            _typed += character; Show(_typed); return true;
        }
        Commit(); return vk == 0x0d;
    }
    public void Commit()
    {
        if (_typed is null) return;
        host.CommitText(_expanded ?? _typed); host.Hide();
        _typed = null; _expanded = null;
    }
    private void Show(string text) => host.Show(new CompositionView(text, [], -1, false, "定型文"));
}
