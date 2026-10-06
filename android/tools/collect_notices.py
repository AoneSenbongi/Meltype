"""Collect the original license notices shipped with the built Mozc dependencies."""
import pathlib
import sys

destination = pathlib.Path(sys.argv[1])
parts = ["Meltype Android prototype\nBased on Meltype by Yukishiro, GPL-3.0-or-later.\n"
         "Mozc: Copyright Google LLC, BSD-3-Clause.\n"
         "Mozc source: https://github.com/google/mozc/tree/60fe4012e5eaa26805dbbb8e5548cbe6db4aaf98\n"]
seen = set()
for directory in sys.argv[2:]:
    root = pathlib.Path(directory)
    if not root.exists():
        raise SystemExit(f"Notice source does not exist: {root}")
    for path in root.rglob("*"):
        name = path.name.lower()
        if not path.is_file() or not (name.startswith(("license", "licence", "copying", "copyright", "notice", "thirdpartynotices")) or
                                     name == "readme.txt" and "dictionary_oss" in path.parts):
            continue
        if path.stat().st_size > 2_000_000:
            continue
        content = path.read_text(encoding="utf-8", errors="replace")
        if content in seen:
            continue
        seen.add(content)
        parts.append(f"\n===== {path.relative_to(root)} =====\n{content}\n")
if len(seen) < 3:
    raise SystemExit("Too few third-party license notices were found")
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text("\n".join(parts), encoding="utf-8")
