"""Recompute the controlled length-test metrics from its case log."""
import collections
import json
import pathlib
import statistics
import sys

directory = pathlib.Path(sys.argv[1])
rows = [json.loads(line) for line in (directory / "samples.jsonl").read_text(encoding="utf-8").splitlines()]
saved = json.loads((directory / "results.json").read_text(encoding="utf-8"))
assert rows == saved["rows"]
assert len(rows) == 123 and len({r["id"] for r in rows}) == 123
groups = collections.defaultdict(list)
for row in rows:
    expected_length = row["readingLength"]
    assert len(row["request"]["Reading"]) == expected_length
    assert row["candidateCoverage"] == (row["expected"] in row["request"]["Candidates"])
    if row["accepted"] is not None:
        assert row["accepted"] in row["request"]["Candidates"]
    if row["group"] == "growing" and expected_length > 100:
        assert row["evaluatorCalls"] == 0 and row["accepted"] is None
    key = int(row["id"].split("-")[-1])
    groups[(row["group"], key)].append(row)

summaries = []
for (group, value), items in groups.items():
    scored = [r for r in items if r["scorable"]]
    measured = [r for r in items if r["evaluatorCalls"] and r["httpEligible"]]
    summaries.append(dict(
        group=group, lengthOrCueDistance=value, stages=len(items),
        evaluatorCalls=sum(r["evaluatorCalls"] for r in items),
        httpEligibleCalls=sum(r["evaluatorCalls"] for r in measured),
        accepted=sum(r["accepted"] is not None for r in items),
        scorable=len(scored), correct=sum(r["correct"] is True for r in scored),
        baselineCorrect=sum(r["baselineCorrect"] is True for r in scored),
        regressions=sum(r["baselineCorrect"] is True and r["correct"] is False for r in scored),
        errors=sum(r["Error"] is not None for r in items),
        candidateCoverage=sum(r["candidateCoverage"] for r in items),
        medianModelMs=statistics.median(r["modelMs"] for r in measured) if measured else None,
        medianElapsedMs=statistics.median(r["elapsedMs"] for r in items),
        medianRawAnswerChars=statistics.median(len(r["rawAnswer"]) for r in items if r["rawAnswer"] is not None)
            if any(r["rawAnswer"] is not None for r in items) else None,
    ))

preferences = {}
for row in rows:
    if row["group"] == "growing":
        family = row["id"].rsplit("-", 1)[0]
        # Identify the candidate, without counting appended characters as a spelling change.
        preferences.setdefault(family, []).append(dict(length=row["readingLength"],
            candidateIndex=row["request"]["Candidates"].index(row["chosen"]), evaluated=row["accepted"] is not None))
result = dict(stages=len(rows), summaries=summaries, preferences=preferences)
(directory / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
for summary in summaries:
    print(json.dumps(summary, ensure_ascii=True))
