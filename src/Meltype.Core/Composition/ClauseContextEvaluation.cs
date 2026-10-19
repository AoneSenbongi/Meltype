// SPDX-License-Identifier: GPL-3.0-or-later
using System.Text.Json;

namespace Meltype.Composition;

public sealed record ContextClause(string Reading, IReadOnlyList<string> Candidates);

/// <summary>Owner-thread coordinator. Only short clauses are generated; surrounding text is context.</summary>
public sealed class ClauseContextEvaluation(IContextEvaluator evaluator, int debounceMs = 180, int timeoutMs = 1500) : IDisposable
{
    private ContextClause[]? _clauses;
    private string[] _values = [];
    private string _left = "", _right = "";
    private string? _key;
    private long _due, _deadline;
    private int _index;
    private bool _started, _done;
    private Task<string?>? _task;
    private CancellationTokenSource? _cancel;
    public bool Pending => _clauses is not null && !_done;
    public IReadOnlyList<ContextClause>? ResultClauses { get; private set; }

    public void Update(IReadOnlyList<ContextClause> clauses, string left, string right, long now)
    {
        var key = JsonSerializer.Serialize(new { clauses, left, right });
        if (key == _key) return;
        var previous = _clauses; var values = _values;
        var sameContext = _left == left && _right == right;
        Reset(); _key = key; _left = left; _right = right;
        if (clauses.Count == 0 || clauses.Any(c => c.Candidates.Count == 0)) return;
        _clauses = clauses.Select(c => c with { Candidates = c.Candidates.ToArray() }).ToArray();
        _values = _clauses.Select(c => c.Candidates[0]).ToArray();
        if (sameContext && previous is not null)
        {
            for (var i = 0; i < Math.Min(previous.Length, _clauses.Length); i++)
            {
                if (previous[i].Reading != _clauses[i].Reading || previous[i].Candidates[0] != _clauses[i].Candidates[0]) break;
                if (_clauses[i].Candidates.Contains(values[i], StringComparer.Ordinal)) _values[i] = values[i];
            }
        }
        _due = now + debounceMs;
    }

    private static bool Eligible(ContextClause clause) => clause.Reading.Length is > 0 and <= 64 &&
        clause.Candidates.Count is >= 2 and <= 5 && clause.Candidates.All(c => c.Length is > 0 and <= 64 &&
            !c.Any(char.IsControl) && ZenzContextEvaluator.PreservesLiteralText(clause.Candidates[0], c));
    private static string Last(string text, int count) => text[^Math.Min(count, text.Length)..];
    private static string First(string text, int count) => text[..Math.Min(count, text.Length)];

    public string? Poll(long now)
    {
        if (!Pending || _clauses is null) return null;
        if (!_started)
        {
            if (now < _due) return null;
            _started = true; _deadline = now + timeoutMs;
            _cancel = new CancellationTokenSource(timeoutMs);
        }
        while (true)
        {
            if (now >= _deadline) return Finish();
            if (_task is not null)
            {
                if (!_task.IsCompleted) return null;
                if (_task.IsCompletedSuccessfully && _task.Result is { } result &&
                    _clauses[_index].Candidates.Contains(result, StringComparer.Ordinal)) _values[_index] = result;
                else Observe(_task);
                _task = null; _index++;
            }
            while (_index < _clauses.Length && !Eligible(_clauses[_index])) _index++;
            if (_index == _clauses.Length) return Finish();
            var clause = _clauses[_index];
            var left = Last(_left + string.Concat(_values.Take(_index)), 256);
            var right = First(string.Concat(_values.Skip(_index + 1)) + _right, 128);
            try { _task = evaluator.EvaluateAsync(new(clause.Reading, left, right, clause.Candidates), _cancel!.Token); }
            catch (Exception e)
            {
                Diagnostics.Log.Warn("文節補正を採用できませんでした: " + e.GetType().Name);
                _index++;
            }
            // A synchronous test evaluator can finish here; real inference returns to the owner loop.
        }
    }

    private string Finish()
    {
        _done = true; _cancel?.Cancel();
        ResultClauses = _clauses!.Select((c, i) => new ContextClause(c.Reading, [_values[i]])).ToArray();
        if (_task is not null) Observe(_task);
        _task = null;
        return string.Concat(_values);
    }
    private static void Observe(Task task) => _ = task.ContinueWith(t => _ = t.Exception,
        CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    public void Reset()
    {
        _cancel?.Cancel(); _cancel?.Dispose(); _cancel = null;
        if (_task is not null) Observe(_task);
        _task = null; _clauses = null; _values = []; _key = null; _index = 0; _started = _done = false;
        ResultClauses = null;
    }
    public void Dispose() => Reset();
}
