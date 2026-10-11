// SPDX-License-Identifier: GPL-3.0-or-later
using System.Collections.Concurrent;

namespace Meltype.Composition;

/// <summary>Each TSF connection owns its selected engine and Microsoft COM apartment.</summary>
public sealed class NativeEngineConverter : IKanjiConverter, ILearningConverter, IDisposable
{
    private readonly GoogleImeConverter? _google;
    private readonly BlockingCollection<Action>? _work;
    private readonly Thread? _thread;
    private MsImeKanjiConverter? _microsoft;
    private WinRtCandidates? _candidates;

    public NativeEngineConverter(string engine, bool learning, Func<bool> learningEnabled)
    {
        if (engine != "Microsoft")
        {
            _google = new GoogleImeConverter(learning) { LearningEnabled = learningEnabled };
            return;
        }
        _work = new BlockingCollection<Action>();
        _thread = new Thread(() =>
        {
            using var converter = new MsImeKanjiConverter();
            using var candidates = new WinRtCandidates();
            _microsoft = converter; _candidates = candidates;
            foreach (var action in _work.GetConsumingEnumerable()) action();
        }) { IsBackground = true, Name = "Meltype Microsoft conversion" };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
    }
    private T OnMicrosoft<T>(Func<T> action)
    {
        var result = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        _work!.Add(() =>
        {
            try { result.SetResult(action()); }
            catch (Exception ex) { result.SetException(ex); }
        });
        return result.Task.GetAwaiter().GetResult();
    }
    public string? Convert(string reading) => _google is not null
        ? _google.Convert(reading) : OnMicrosoft(() => _microsoft!.Convert(reading));
    public IReadOnlyList<ConversionClause>? ConvertClauses(string reading, string? context = null) => _google is not null
        ? _google.ConvertClauses(reading, context) : OnMicrosoft(() => _microsoft!.ConvertClauses(reading, context));
    public IReadOnlyList<string> Candidates(string reading) => _google is not null
        ? _google.Candidates(reading) : OnMicrosoft(() => _candidates!.Get(reading));
    public void Learn(string? context, IReadOnlyList<ConversionClause> clauses) => _google?.Learn(context, clauses);
    public void Dispose()
    {
        if (_work is null) return;
        _work.CompleteAdding();
        _thread!.Join();
        _work.Dispose();
    }
}
