// SPDX-License-Identifier: GPL-3.0-or-later
using Android.App;
using Android.Content;
using Android.OS;
using Android.Provider;
using Android.Text;
using Android.Views.InputMethods;
using Android.Widget;
using Meltype.AndroidCore;

namespace Meltype.Mobile;

[Activity(Label = "Meltype Android 試作版", MainLauncher = true, Exported = true)]
public sealed class MainActivity : Activity
{
    protected override void OnCreate(Bundle? savedInstanceState)
    {
        base.OnCreate(savedInstanceState);
        var layout = new LinearLayout(this) { Orientation = Orientation.Vertical };
        layout.SetPadding(24, 24, 24, 24);
        layout.AddView(new TextView(this) { Text = "Meltype Android 試作版", TextSize = 24 });
        layout.AddView(new TextView(this) { Text = "QWERTYで日本語と英語を混ぜて入力できます。日英切替ボタンで英語だけの入力にも切り替えられます。" });
        Button Add(string text, Action action)
        {
            var button = new Button(this) { Text = text };
            button.Click += (_, _) => action(); layout.AddView(button); return button;
        }
        Add("1. キーボードを有効にする", () => StartActivity(new Intent(Settings.ActionInputMethodSettings)));
        Add("2. キーボードを選ぶ", () => ((InputMethodManager)GetSystemService(InputMethodService)!).ShowInputMethodPicker());
        var editor = new EditText(this) { Hint = "試し書き：kyouhagoogledekensaku", InputType = InputTypes.ClassText | InputTypes.TextFlagMultiLine };
        layout.AddView(editor, new LinearLayout.LayoutParams(-1, 200));
        Add("ライセンス", () =>
        {
            var text = ReadAsset("LICENSE.txt") + "\n\n" + ReadAsset("THIRD_PARTY_NOTICES.txt");
            var scroll = new ScrollView(this); scroll.AddView(new TextView(this) { Text = text, TextSize = 12 });
            new AlertDialog.Builder(this).SetTitle("Meltype / Mozc / 同梱ライブラリ").SetView(scroll).SetPositiveButton("閉じる", (_, _) => { }).Show();
        });
        layout.AddView(new TextView(this) { Text = "雪代／Yukishiro氏のMeltypeを基にした非公式Forkです。変換にはOSS版Mozcを使用し、入力は端末内で処理します。" });
        SetContentView(layout);
        if (Intent?.GetBooleanExtra("selftest", false) == true) RunSelfTest(editor);
    }
    private string ReadAsset(string name)
    {
        using var reader = new StreamReader(Assets!.Open(name)); return reader.ReadToEnd();
    }
    private void RunSelfTest(EditText editor)
    {
        var path = Path.Combine(FilesDir!.AbsolutePath, "selftest.txt");
        Task.Run(() =>
        {
            try
            {
                var converter = MozcJniBridge.Create(this, learning: false);
                var preview = "";
                var session = new AndroidInputSession(converter, converter.Candidates, (operation, text, _) => { if (operation == 0) preview = text; });
                foreach (var c in "kyouhagoogledekensaku") session.Character(c);
                if (!preview.Contains("google") || !preview.Contains("検索")) throw new Exception("Mixed live conversion failed: " + preview);
                foreach (var c in ",.?")
                {
                    session.Character(c);
                    if (!preview.Contains("検索")) throw new Exception("Punctuation removed conversion");
                }
                var output = preview;
                RunOnUiThread(() =>
                {
                    try
                    {
                        var connection = editor.OnCreateInputConnection(new EditorInfo())!;
                        connection.SetComposingText(output, 1);
                        if (editor.Text != output) throw new Exception("Editor composition failed");
                        connection.CommitText(output, 1);
                        if (editor.Text != output) throw new Exception("Editor commit duplicated composition");
                        File.WriteAllText(path, "PASS: JNI dictionary, mixed live conversion, punctuation, Android editor composition and commit\n" + output);
                    }
                    catch (Exception ex) { File.WriteAllText(path, "FAIL: " + ex); }
                });
            }
            catch (Exception ex) { File.WriteAllText(path, "FAIL: " + ex); }
        });
    }
}
