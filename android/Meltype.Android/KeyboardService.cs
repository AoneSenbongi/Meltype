// SPDX-License-Identifier: GPL-3.0-or-later
using Android.App;
using Android.Content;
using Android.Graphics;
using Android.InputMethodServices;
using Android.OS;
using Android.Text;
using Android.Views;
using Android.Views.InputMethods;
using Android.Widget;
using Meltype.AndroidCore;
using Meltype.Composition;

namespace Meltype.Mobile;

[Service(Label = "Meltype Android 試作版", Permission = "android.permission.BIND_INPUT_METHOD", Exported = true)]
[IntentFilter(new[] { "android.view.InputMethod" })]
[MetaData("android.view.im", Resource = "@xml/input_method")]
public sealed class KeyboardService : InputMethodService
{
    private HandlerThread? _thread;
    private Handler? _worker, _main;
    private AndroidInputSession? _session;
    private LinearLayout? _candidates;
    private TextView? _status;
    private Button? _mode;
    private bool _english, _restricted, _caps, _ready;
    private bool _preeditActive;
    private int _generation;
    private int _jobGeneration;

    public override void OnCreate()
    {
        base.OnCreate();
        _main = new Handler(Looper.MainLooper!);
        _thread = new HandlerThread("MeltypeInput"); _thread.Start();
        _worker = new Handler(_thread.Looper!);
        _worker.Post(() =>
        {
            try
            {
                var mozc = MozcJniBridge.Create(this);
                _session = new AndroidInputSession(mozc, mozc.Candidates, Output);
                _main.Post(() => { _ready = true; Status(); });
            }
            catch (Exception) { _main.Post(() => { if (_status != null) _status.Text = "変換エンジンを起動できません。入力方法を切り替えてください。"; }); }
        });
    }
    public override View OnCreateInputView()
    {
        var root = new LinearLayout(this) { Orientation = Orientation.Vertical };
        root.SetBackgroundColor(Color.Rgb(242, 242, 242));
        _status = new TextView(this) { TextSize = 12 }; root.AddView(_status);
        var scroll = new HorizontalScrollView(this);
        _candidates = new LinearLayout(this) { Orientation = Orientation.Horizontal };
        _candidates.SetBackgroundColor(Color.White); scroll.AddView(_candidates);
        root.AddView(scroll, new LinearLayout.LayoutParams(-1, Dp(48)));
        foreach (var row in new[] { "1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm" })
        {
            var line = new LinearLayout(this);
            foreach (var c in row) AddKey(line, c.ToString(), () => Input(_caps ? char.ToUpperInvariant(c) : c));
            root.AddView(line);
        }
        var symbols = new LinearLayout(this);
        AddKey(symbols, "Shift", () => { _caps = !_caps; Status(); });
        foreach (var c in new[] { ',', '.', '?', '!', '-', '@', '/' }) AddKey(symbols, c.ToString(), () => Input(c));
        AddKey(symbols, "⌫", () => Special(0x08)); root.AddView(symbols);
        var controls = new LinearLayout(this);
        _mode = AddKey(controls, "日英切替", () =>
        {
            if (_restricted || !_ready) return;
            _english = !_english;
            var english = _english;
            Queue(() => _session?.SetEnglish(english)); Status();
        });
        AddKey(controls, "入力方法", () => ((InputMethodManager)GetSystemService(InputMethodService)!).ShowInputMethodPicker());
        AddKey(controls, "Space / 変換", () => Input(' '), 2);
        AddKey(controls, "←", () => Special(0x25));
        AddKey(controls, "→", () => Special(0x27));
        AddKey(controls, "Enter", () => Special(0x0D)); root.AddView(controls);
        Status(); return root;
    }
    private int Dp(int pixels) => (int)(pixels * Resources!.DisplayMetrics!.Density);
    private Button AddKey(LinearLayout row, string label, Action action, int weight = 1)
    {
        var key = new Button(this) { Text = label, TextSize = label.Length > 3 ? 11 : 18 };
        key.SetPadding(0, 0, 0, 0); key.Click += (_, _) => action();
        row.AddView(key, new LinearLayout.LayoutParams(0, Dp(48), weight)); return key;
    }
    public override bool OnEvaluateFullscreenMode() => false;
    public override void OnStartInput(EditorInfo? attribute, bool restarting)
    {
        base.OnStartInput(attribute, restarting);
        Interlocked.Increment(ref _generation);
        _preeditActive = false;
        var type = attribute?.InputType ?? InputTypes.Null;
        var inputClass = type & InputTypes.MaskClass;
        var variation = type & InputTypes.MaskVariation;
        _restricted = inputClass is InputTypes.ClassNumber or InputTypes.ClassPhone or InputTypes.ClassDatetime ||
            variation is InputTypes.TextVariationPassword or InputTypes.TextVariationVisiblePassword or InputTypes.TextVariationWebPassword;
        _candidates?.RemoveAllViews();
        var english = _english;
        _worker?.Post(() => { _session?.Reset(); _session?.SetEnglish(english); }); Status();
    }
    public override void OnFinishInput()
    {
        CurrentInputConnection?.FinishComposingText();
        _preeditActive = false;
        Interlocked.Increment(ref _generation);
        _worker?.Post(() => _session?.Reset());
        _candidates?.RemoveAllViews(); base.OnFinishInput();
    }
    public override void OnUpdateSelection(int oldSelStart, int oldSelEnd, int newSelStart, int newSelEnd, int candidatesStart, int candidatesEnd)
    {
        base.OnUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd);
        if (candidatesStart >= 0 && (newSelStart != candidatesEnd || newSelEnd != candidatesEnd))
        {
            CurrentInputConnection?.FinishComposingText();
            _preeditActive = false;
            Interlocked.Increment(ref _generation);
            _worker?.Post(() => _session?.Reset()); _candidates?.RemoveAllViews();
        }
    }
    private void Input(char c)
    {
        if (_restricted) { CurrentInputConnection?.CommitText(c.ToString(), 1); return; }
        Queue(() => _session?.Character(c));
    }
    private void Special(int key)
    {
        if (_restricted)
        {
            if (key == 0x08) CurrentInputConnection?.DeleteSurroundingTextInCodePoints(1, 0);
            else if (key == 0x0D) Enter();
            return;
        }
        Queue(() => _session?.Key(key));
    }
    private void Queue(Action action)
    {
        if (!_ready) return;
        var generation = Volatile.Read(ref _generation);
        _worker!.Post(() =>
        {
            if (generation != Volatile.Read(ref _generation)) return;
            _jobGeneration = generation; action();
        });
    }
    private void Output(int operation, string text, CompositionView? view)
    {
        var generation = _jobGeneration;
        _main!.Post(() =>
        {
            if (generation != Volatile.Read(ref _generation)) return;
            var editor = CurrentInputConnection; if (editor == null) return;
            if (operation == 0) { editor.SetComposingText(text, 1); _preeditActive = true; }
            else if (operation == 1) { editor.CommitText(text, 1); _preeditActive = false; }
            else if (operation == 2)
            {
                if (_preeditActive) editor.SetComposingText("", 1);
                editor.FinishComposingText(); _preeditActive = false;
            }
            else if (operation == 3) editor.DeleteSurroundingTextInCodePoints(int.Parse(text), 0);
            else if (operation == 4) Enter();
            _candidates?.RemoveAllViews();
            if (view is { Converting: true } && _candidates != null)
                for (var i = 0; i < Math.Min(view.Candidates.Count, 24); i++)
                {
                    var index = i; var button = new Button(this) { Text = view.Candidates[index] };
                    button.Click += (_, _) => Queue(() => _session?.Select(index));
                    _candidates.AddView(button);
                }
        });
    }
    private void Enter() { if (!SendDefaultEditorAction(true)) CurrentInputConnection?.CommitText("\n", 1); }
    private void Status()
    {
        if (_status != null) _status.Text = !_ready ? "変換エンジンを準備中…" : _restricted ? "直接入力" : "Meltype · " + (_english ? "ABC" : "日英自動判別") + (_caps ? " · Shift" : "");
        if (_mode != null) _mode.Text = _restricted || _english ? "英語 → 日英" : "日英 → 英語";
    }
    public override void OnDestroy()
    {
        Interlocked.Increment(ref _generation); _thread?.QuitSafely(); base.OnDestroy();
    }
}
