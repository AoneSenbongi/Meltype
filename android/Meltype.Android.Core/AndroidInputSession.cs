// SPDX-License-Identifier: GPL-3.0-or-later
using Meltype.Composition;
using Meltype.Input;

namespace Meltype.AndroidCore;

// Calls are serialized by the Android service's worker. Operations target the current editor only.
public sealed class AndroidInputSession : ICompositionHost
{
    private readonly CaptureGate _gate = new(() => { });
    private readonly CompositionController _controller;
    private readonly Action<int, string, CompositionView?> _output;
    private char? _character;
    private long _time;
    private bool _english;
    public CompositionView? View { get; private set; }

    public AndroidInputSession(IKanjiConverter converter, Func<string, IReadOnlyList<string>> candidates,
        Action<int, string, CompositionView?> output)
    {
        _output = output;
        _controller = new CompositionController(_gate, CompositionDetector.CreateDefault(), converter, this,
            new CompositionOptions { FullWidthCommaPeriod = true, LiveConversion = () => true,
                MoreCandidates = candidates, AutoCorrect = () => false });
    }

    public void SetEnglish(bool english)
    {
        if (_english == english) return;
        _controller.CommitPending();
        _english = english;
    }

    public void Character(char character)
    {
        if (_english) { CommitText(character.ToString()); return; }
        Key(character switch
    {
        ' ' => 0x20, ',' => 0xBC, '.' => 0xBE, '?' or '/' => 0xBF,
        '-' => 0xBD, '\n' => 0x0D, _ => char.ToUpperInvariant(character)
        }, character);
    }

    public void Key(int code, char? character = null)
    {
        _character = character;
        if (_english) { Replay(new KeyEvent(code, 0, false, false, false, ++_time)); _character = null; return; }
        foreach (var up in new[] { false, true })
        {
            _gate.OnKey(new KeyEvent(code, 0, false, up, false, ++_time), e => e.IsDown);
            _controller.Pump();
        }
        _character = null;
    }

    public void Select(int index)
    {
        if (View is not { Converting: true }) return;
        _controller.SelectCandidate(index);
        _controller.CommitPending();
    }
    public void Commit() => _controller.CommitPending();
    public void Reset() { _controller.Reset(); _controller.ResetContext(); _gate.Abort(); View = null; }
    public void CommitText(string text) => _output(1, text, null);
    public void Show(CompositionView view) { View = view; _output(0, view.Text, view); }
    public void Hide() { View = null; _output(2, "", null); }
    public void DeleteBackward(int count) => _output(3, count.ToString(), null);
    public void Replay(KeyEvent e)
    {
        if (e.IsUp) return;
        if (e.Vk == 0x08) DeleteBackward(1);
        else if (e.Vk == 0x0D) _output(4, "", null);
        else if (_character is { } c) CommitText(c.ToString());
    }
    public void Replay(MouseButtonEvent e) { }
    public char? CharFromKey(KeyEvent e, bool shift) => _character;
    public void RequestSurroundingText(Action<string?, string?> callback) => callback(null, null);
}
