// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using Meltype.Composition;
using Meltype.Input;

public static class NativeCompositionTrace
{
    public static string RunPrediction(string path)
    {
        using var stream = File.Create(path);
        using var writer = new BinaryWriter(stream, Encoding.Unicode);
        writer.Write(Encoding.ASCII.GetBytes("MTTSF1\n"));
        var host = new Host(writer);
        var gate = new CaptureGate(() => { });
        var google = new GoogleImeConverter(learning: false);
        var phrases = new PhraseHistory(null);
        const string prediction = "今日はgoogleで検索";
        phrases.Remember("きょうはぐーぐるでけんさく", prediction);
        var controller = new CompositionController(gate, CompositionDetector.CreateDefault(), google, host,
            new CompositionOptions { LiveConversion = () => true, MoreCandidates = google.Candidates, AutoCorrect = () => false,
                Predictor = new Predictor(phrases, null, null), Predictions = () => true, LearningEnabled = () => false });
        long time = 1000;
        void Key(int vk)
        {
            foreach (var up in new[] { false, true })
            {
                gate.OnKey(new KeyEvent(vk, 0, false, up, false, time++), e => !e.IsUp);
                controller.Pump();
            }
        }
        foreach (var c in "kyouha") Key(char.ToUpperInvariant(c));
        var live = host.View?.Text;
        if (host.View?.Predictions?.Contains(prediction) != true || host.Commits != 0) throw new InvalidOperationException("Prediction missing during Google live conversion");
        Key(0x09);
        if (host.View?.Text != prediction || host.View.SelectedPrediction != 0) throw new InvalidOperationException("Tab preview differs from selected prediction");
        Key(0x1B);
        if (host.View?.Text != live || host.View.SelectedPrediction != -1) throw new InvalidOperationException("Escape did not restore typed preview");
        Key(0x09);
        Key(0x0D);
        if (host.Document != prediction || host.Commits != 1 || phrases.Count != 1) throw new InvalidOperationException("Prediction commit differs from preview");
        foreach (var c in "nihongo") Key(char.ToUpperInvariant(c));
        Key(0x1B);
        if (host.View != null || host.Cancels != 1) throw new InvalidOperationException("Cancellation removed the wrong composition");
        return "PASS: Google live conversion + prediction Tab preview, Escape restore, Enter commit; isolated phrase fixture, learning disabled.";
    }
    private sealed class Host : ICompositionHost
    {
        private readonly BinaryWriter _trace;
        public Host(BinaryWriter trace) => _trace = trace;
        public CompositionView View;
        public string Document = "";
        public int Updates, Commits, Cancels;
        private string _lastPreedit;
        private bool _active;
        private void Write(int operation, string text)
        {
            var bytes = Encoding.Unicode.GetBytes(text);
            _trace.Write(operation);
            _trace.Write(bytes.Length);
            _trace.Write(bytes);
        }
        public void CommitText(string text)
        {
            Write(1, text);
            Commits++;
            Document += text;
            _active = false;
            _lastPreedit = null;
        }
        public void Show(CompositionView view)
        {
            View = view;
            if (view.Text == _lastPreedit && _active) return;
            Write(0, view.Text);
            Updates++;
            _lastPreedit = view.Text;
            _active = true;
        }
        public void Hide()
        {
            View = null;
            if (_active) { Write(2, ""); Cancels++; }
            _active = false;
            _lastPreedit = null;
        }
        public void DeleteBackward(int count) => throw new InvalidOperationException("Trace does not support deleting committed text");
        public void Replay(KeyEvent e) { if (!e.IsUp) throw new InvalidOperationException("Unexpected replay in fixture"); }
        public void Replay(MouseButtonEvent e) => throw new InvalidOperationException("No mouse input in fixture");
        public char? CharFromKey(KeyEvent e, bool shift) => e.Vk is >= 0x41 and <= 0x5A ? (char)(e.Vk + (shift ? 0 : 32)) : e.Vk == 0x20 ? ' ' : null;
        public void RequestSurroundingText(Action<string, string> callback) => callback(null, null);
    }

    public static string Run(string path)
    {
        using var stream = File.Create(path);
        using var writer = new BinaryWriter(stream, Encoding.Unicode);
        writer.Write(Encoding.ASCII.GetBytes("MTTSF1\n"));
        var host = new Host(writer);
        var gate = new CaptureGate(() => { });
        var google = new GoogleImeConverter(learning: false);
        var controller = new CompositionController(gate, CompositionDetector.CreateDefault(), google, host,
            new CompositionOptions { LiveConversion = () => true, MoreCandidates = google.Candidates, AutoCorrect = () => false });
        long time = 1000;
        void Key(int vk)
        {
            foreach (var up in new[] { false, true })
            {
                gate.OnKey(new KeyEvent(vk, 0, false, up, false, time++), e => !e.IsUp);
                controller.Pump();
            }
        }
        foreach (var c in "kyouhagoogledekensaku") Key(char.ToUpperInvariant(c));
        var live = host.View?.Text ?? "";
        if (!live.Contains("google") || !live.Contains("検索")) throw new InvalidOperationException("Google live conversion or English detection missing: " + live);
        if (host.Commits != 0) throw new InvalidOperationException("Typing must remain uncommitted");
        Key(0x20);
        if (host.View is not { Converting: true } || host.View.Candidates.Count == 0) throw new InvalidOperationException("Space did not show candidates");
        Key(0x0D);
        if (host.Document != live || host.Commits != 1) throw new InvalidOperationException("Commit differs from preview");
        foreach (var c in "nihongo") Key(char.ToUpperInvariant(c));
        Key(0x1B);
        if (host.View != null || host.Cancels != 1) throw new InvalidOperationException("Escape did not cancel");
        return $"Google -> Meltype trace passed: {host.Updates} preedit updates, {host.Commits} commit, {host.Cancels} cancellation; live={live}; learning=false";
    }
}
