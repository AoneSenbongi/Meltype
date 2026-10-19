"""Verify clause replay logs and recompute grouped results."""
import collections
import json
import pathlib
import statistics
import sys

directory = pathlib.Path(sys.argv[1])
rows = [json.loads(x) for x in (directory / "samples.jsonl").read_text(encoding="utf-8").splitlines()]
assert rows == json.loads((directory / "results.json").read_text(encoding="utf-8"))["rows"]
assert len(rows) == 101 and len({r["id"] for r in rows}) == 101
groups = collections.defaultdict(list)
for row in rows:
    assert row["resultAvailable"] and not row["pending"]
    # Prove that the combined output can be built from exactly one candidate per clause.
    positions = {0}
    for clause in row["clauses"]:
        positions = {p + len(c) for p in positions for c in clause["Candidates"] if row["chosen"].startswith(c, p)}
    assert len(row["chosen"]) in positions
    if row["scorable"]:
        assert row["correct"] == (row["chosen"] == row["expected"])
    for call in row["calls"]:
        request = call["request"]
        assert 0 < len(request["Reading"]) <= 64
        assert len(request["Left"]) <= 256 and len(request["Right"]) <= 128
        assert 2 <= len(request["Candidates"]) <= 5
        assert all(0 < len(c) <= 64 for c in request["Candidates"])
        if call["answer"] is not None:
            assert call["answer"] in request["Candidates"]
    groups[(row["group"], row["length"])].append(row)

summary = []
for (group, length), items in groups.items():
    calls = [call for item in items for call in item["calls"]]
    summary.append(dict(group=group, length=length, stages=len(items),
        scorable=sum(r["scorable"] for r in items),
        correct=sum(r["correct"] is True for r in items),
        baselineCorrect=sum(r["baselineCorrect"] is True for r in items),
        calls=len(calls), errors=sum(c["error"] is not None for c in calls),
        medianElapsedMs=statistics.median(r["elapsedMs"] for r in items),
        medianModelMs=statistics.median(c["elapsedMs"] for c in calls) if calls else None))
result = dict(stages=len(rows), calls=sum(len(r["calls"]) for r in rows), summaries=summary)
(directory / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
for item in summary:
    print(json.dumps(item))
