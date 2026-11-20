// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro

using System.Text.Json;
using Meltype.Config;

namespace Meltype.Composition;

/// <summary>
/// Shift+矢印で動かした文節の区切りを、打った元ローマ字ごとに覚える。
/// %LOCALAPPDATA%\Meltype\clause-boundaries.json に保存する。
/// </summary>
public sealed class ClauseBoundaryHistory
{
    /// <summary>学習した文節 1 つ。Raw は打った元ローマ字、Reading は文節の読み、Text は確定するときに選んだ文字列。</summary>
    public sealed record Part(string Reading, string Raw, string Text, bool IsEnglish);

    internal sealed class Entry
    {
        public List<Part> Parts { get; set; } = [];
        public DateTime Used { get; set; }
    }

    private const int MaxEntries = 2000;
    private readonly string? _path;
    private readonly Dictionary<string, Entry> _entries = new(StringComparer.OrdinalIgnoreCase);

    public ClauseBoundaryHistory(string? path)
    {
        _path = path;
        Config.DataFile.Load(path, "文節区切りの学習データ", content =>
        {
            var loaded = JsonSerializer.Deserialize(content, Config.ClauseBoundaryJsonContext.Default.Boundaries);
            if (loaded is null) return;
            foreach (var (raw, entry) in loaded)
                if (Valid(raw, entry)) _entries[raw] = entry;
        });
    }

    /// <summary>学習した内容が変わるたびに増える (変換結果のキャッシュを捨てるため)。</summary>
    public int Version { get; private set; }

    public int Count => _entries.Count;

    /// <summary>打った元ローマ字に対応する文節の区切り。無ければ null。</summary>
    public IReadOnlyList<Part>? Find(string raw) =>
        raw.Length > 0 && _entries.TryGetValue(raw, out var entry) ? entry.Parts : null;

    /// <summary>文節の区切りを覚える。次から同じ文字列を打ったとき、この区切りで変換する。</summary>
    public void Remember(string raw, IReadOnlyList<Part> parts)
    {
        var entry = new Entry { Parts = parts.ToList(), Used = DateTime.UtcNow };
        if (!Valid(raw, entry)) return;
        _entries[raw] = entry;
        if (_entries.Count > MaxEntries)
        {
            foreach (var old in _entries.OrderBy(e => e.Value.Used).Take(_entries.Count - MaxEntries * 9 / 10).Select(e => e.Key).ToList())
                _entries.Remove(old);
        }
        Version++;
        Save();
    }

    public void Forget(string raw)
    {
        if (!_entries.Remove(raw)) return;
        Version++;
        Save();
    }

    /// <summary>学習した区切りの一覧 (新しく使ったものから)。</summary>
    public IReadOnlyList<(string Raw, IReadOnlyList<Part> Parts, DateTime Used)> Entries() =>
        _entries.OrderByDescending(e => e.Value.Used)
            .Select(e => (e.Key, (IReadOnlyList<Part>)e.Value.Parts, e.Value.Used)).ToList();

    public void Clear()
    {
        _entries.Clear();
        Version++;
        Save();
    }

    /// <summary>sinceUtc より後に覚えた区切りを忘れる (トレイの「最近の学習を消す」)。忘れた数を返す。</summary>
    public int ForgetSince(DateTime sinceUtc)
    {
        var recent = _entries.Where(e => e.Value.Used >= sinceUtc).Select(e => e.Key).ToList();
        foreach (var raw in recent) _entries.Remove(raw);
        if (recent.Count == 0) return 0;
        Version++;
        Save();
        return recent.Count;
    }

    private static bool Valid(string raw, Entry? entry) =>
        raw.Length is >= 2 and <= 128 &&
        entry is not null && entry.Parts.Count is >= 2 and <= 32 &&
        entry.Parts.All(p => p is not null && p.Reading.Length > 0 && p.Raw.Length > 0 && p.Text.Length > 0);

    private void Save()
    {
        if (_path is null) return;
        try
        {
            Config.DataFile.Write(_path, temp => File.WriteAllText(temp, JsonSerializer.Serialize(_entries, Config.ClauseBoundaryJsonContext.Default.Boundaries)));
        }
        catch (Exception ex)
        {
            Diagnostics.Log.Warn($"文節区切りの学習データを保存できませんでした: {ex.Message}");
        }
    }
}
