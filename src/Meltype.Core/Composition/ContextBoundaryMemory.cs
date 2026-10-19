using System.Text.Json;
using Meltype.Config;

namespace Meltype.Composition;

// Experimental component. Not connected to product while comparison runs.
public sealed class ContextBoundaryMemory
{
    public sealed record Entry(string Reading, int[] Lengths, string Left, string Right);
    private readonly object _gate = new();
    private readonly string? _path;
    private readonly List<Entry> _entries = [];
    private const int Capacity = 1024;
    public int Count { get { lock (_gate) return _entries.Count; } }

    public ContextBoundaryMemory(string? path)
    {
        _path = path;
        if (path is null) return;
        try {
            if (!File.Exists(path) || new FileInfo(path).Length > 4 * 1024 * 1024) return;
            var entries = JsonSerializer.Deserialize(File.ReadAllText(path), BoundaryJsonContext.Default.Entries);
            if (entries is null) return;
            foreach (var e in entries.TakeLast(Capacity))
                if (e is not null && Valid(e.Reading, e.Lengths) && e.Left is not null && e.Right is not null)
                    Add(e.Reading, e.Lengths, Left(e.Left), Right(e.Right));
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { }
    }

    public bool Remember(string reading, int[] lengths, string left, string right)
    {
        if (!Valid(reading, lengths)) return false;
        lock (_gate) {
            if (!Add(reading, lengths, Left(left), Right(right))) return false;
            if (_path is not null) {
                var temp = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try {
                    Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(_path))!);
                    File.WriteAllText(temp, JsonSerializer.Serialize(_entries, BoundaryJsonContext.Default.Entries));
                    File.Move(temp, _path, true);
                } catch (Exception e) when (e is IOException or UnauthorizedAccessException) {
                    // Keep the in-memory correction if persistence is unavailable.
                } finally {
                    try { if (File.Exists(temp)) File.Delete(temp); }
                    catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
                }
            }
            return true;
        }
    }

    public int[]? Find(string reading, string left, string right)
    {
        var query = Features(Left(left) + Right(right));
        if (query.Count == 0) return null;
        lock (_gate) {
            var ranked = _entries.Where(e => e.Reading == reading)
                .GroupBy(e => string.Join(",", e.Lengths))
                .Select(g => (Entry: g.First(), Score: g.Max(e => Similarity(query, Features(e.Left + e.Right)))))
                .OrderByDescending(e => e.Score).ToArray();
            if (ranked.Length == 0 || ranked[0].Score < .45 ||
                ranked.Length > 1 && ranked[0].Score - ranked[1].Score < .12) return null;
            return (int[])ranked[0].Entry.Lengths.Clone();
        }
    }

    private bool Add(string reading, int[] lengths, string left, string right)
    {
        if (string.IsNullOrWhiteSpace(left + right)) return false;
        _entries.RemoveAll(e => e.Reading == reading && e.Left == left && e.Right == right);
        _entries.Add(new(reading, (int[])lengths.Clone(), left, right));
        if (_entries.Count > Capacity) _entries.RemoveRange(0, _entries.Count - Capacity);
        return true;
    }

    private static bool Valid(string? reading, int[]? lengths) =>
        reading is { Length: >= 2 and <= 64 } && reading.All(c => c is >= 'ぁ' and <= 'ゖ' or 'ー') &&
        lengths is { Length: >= 1 and <= 32 } && lengths.All(n => n > 0 && n <= 64) && lengths.Sum() == reading.Length;
    private static string Left(string s) => s.Length > 256 ? s[^256..] : s;
    private static string Right(string s) => s.Length > 128 ? s[..128] : s;
    private static HashSet<string> Features(string s)
    {
        var f = new HashSet<string>();
        for (var i = 0; i < s.Length; i++) {
            if (i + 1 < s.Length) f.Add(s.Substring(i, 2));
            if (s[i] is >= '\u4e00' and <= '\u9fff') f.Add(s[i].ToString());
        }
        return f;
    }
    private static double Similarity(HashSet<string> a, HashSet<string> b) =>
        a.Count == 0 || b.Count == 0 ? 0 : a.Count(b.Contains) / Math.Sqrt((double)a.Count * b.Count);
}
