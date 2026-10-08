$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $root 'experimental-build'
$core = Join-Path $build 'Meltype.Core.dll'
$app = Join-Path $build 'Meltype.dll'
[Reflection.Assembly]::LoadFrom($core) | Out-Null
[Reflection.Assembly]::LoadFrom($app) | Out-Null
$references = @($core,$app) + @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
$test = @'
public static class NativePredictionViewTest {
    public static void Run() {
        Check(new Meltype.Composition.CompositionView("きょ", System.Array.Empty<string>(), -1, false, "", Predictions: new[] {"今日", "今日は"}, SelectedPrediction: -1), true, -1, new[] {"今日", "今日は"});
        Check(new Meltype.Composition.CompositionView("今日は", System.Array.Empty<string>(), -1, false, "", Predictions: new[] {"今日", "今日は"}, SelectedPrediction: 1), true, 1, new[] {"今日", "今日は"});
        Check(new Meltype.Composition.CompositionView("橋", new[] {"橋", "箸"}, 0, true, "", Predictions: new[] {"今日は"}, SelectedPrediction: 0), true, 0, new[] {"橋", "箸"});
        Check(new Meltype.Composition.CompositionView("きょ", System.Array.Empty<string>(), -1, false, ""), false, -1, System.Array.Empty<string>());
        Check(null, false, -1, System.Array.Empty<string>());
    }
    static void Check(Meltype.Composition.CompositionView view, bool visible, int selected, string[] expected) {
        using var stream = new System.IO.MemoryStream();
        using (var writer = new System.IO.BinaryWriter(stream, System.Text.Encoding.Unicode, true)) MeltypeNativeBroker.WriteCandidateView(writer, view);
        stream.Position = 0;
        using var reader = new System.IO.BinaryReader(stream, System.Text.Encoding.Unicode);
        if (reader.ReadInt32() != (visible ? 1 : 0) || reader.ReadInt32() != selected || reader.ReadInt32() != expected.Length) throw new System.Exception("Candidate view state mismatch");
        foreach (var text in expected) {
            var actual = System.Text.Encoding.Unicode.GetString(reader.ReadBytes(reader.ReadInt32()));
            if (actual != text) throw new System.Exception("Candidate text mismatch");
        }
        if (stream.Position != stream.Length) throw new System.Exception("Trailing protocol bytes");
    }
}
'@
Add-Type -TypeDefinition ((Get-Content (Join-Path $root 'native/tsf/NativeBroker.cs') -Raw) + $test) -ReferencedAssemblies $references
[NativePredictionViewTest]::Run()
Write-Output 'PASS: predictions visible before conversion, selection transmitted, conversion precedence, empty view hidden; protocol v1 retained.'
