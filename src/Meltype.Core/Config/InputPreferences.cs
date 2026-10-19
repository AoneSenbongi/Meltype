// SPDX-License-Identifier: GPL-3.0-or-later
using System.Text.Json;

namespace Meltype.Config;

public sealed record InputPreferences
{
    public string Comma { get; init; } = "，";
    public string Period { get; init; } = "．";
    public bool LearningEnabled { get; init; } = true;
    public string ConversionEngine { get; init; } = "Google";
    public bool DirectModeAutoDetect { get; init; } = true;
    public bool TabConversion { get; init; } = true;
    public bool CalculatorCandidates { get; init; } = true;
    public bool EscStepsBack { get; init; }
    public bool EscRevertsSelectedClause { get; init; }
    public bool EnterCommitsAsShown { get; init; }
    public bool AlphanumericKeyStartsAsTyped { get; init; }
    public bool FunctionKeysAffectSelectedClause { get; init; } = true;
    public bool ShiftSpaceHalfWidth { get; init; }
    public bool FullWidthParentheses { get; init; }
    public bool FullWidthSlash { get; init; }
    public bool SquareBrackets { get; init; }
    public bool CursorIntoBrackets { get; init; }
    public bool EnglishFirstInput { get; init; }
    public string ControlKeyBindings { get; init; } = "";
    public InputPreferences Validate() => this with
    {
        Comma = Comma is "、" or "，" or "," ? Comma : "，",
        Period = Period is "。" or "．" or "." ? Period : "．",
        ConversionEngine = ConversionEngine is "Google" or "Microsoft" ? ConversionEngine : "Google"
    };
}

public sealed class InputPreferenceStore(string path)
{
    private readonly object _gate = new();
    public InputPreferences Current
    {
        get
        {
            lock (_gate)
            {
                try
                {
                    if (!File.Exists(path)) return new();
                    if (new FileInfo(path).Length > 4096) return new() { LearningEnabled = false };
                    return (JsonSerializer.Deserialize<InputPreferences>(File.ReadAllText(path)) ??
                        new InputPreferences { LearningEnabled = false }).Validate();
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
                { return new() { LearningEnabled = false }; }
            }
        }
    }
    public void Save(InputPreferences value)
    {
        lock (_gate)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
            var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temp, JsonSerializer.Serialize(value.Validate()));
                File.Move(temp, path, overwrite: true);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
}
