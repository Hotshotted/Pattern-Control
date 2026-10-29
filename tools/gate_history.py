#!/usr/bin/env python3
"""Build tools/gate_history.json from the result lines of ten green runs:
    gate_history.py OUT.json LINES.txt
LINES.txt holds, for each run, the lines the "Result" step of the Gate calibration workflow (or a copy of what median_gate.py printed)
ends with: a `CAL n=...` line starting the run, then its `CAL GATE_DATA {...}` lines (labels boot and panel; `old` is ignored).
The history is {"headroom": 1.25, "runs": [{name: median ratio}, ...]}: tools/median_gate.py limits each name to the highest ratio of the
last ten runs times the headroom."""
import json, re, sys

out, src = sys.argv[1], sys.argv[2]
runs = []
cur = None
for line in open(src):
    line = line.strip()
    m = re.search(r"CAL n=(\S+)", line)
    if m:
        cur = {}
        runs.append(cur)
        continue
    m = re.search(r"GATE_DATA (\{.*\})", line)
    if m and cur is not None:
        d = json.loads(m.group(1))
        if d.get("label") in ("boot", "panel", "gate"):
            cur.update(d["ratios"])
runs = [r for r in runs if r]
json.dump({"headroom": 1.25, "runs": runs[-10:], "note": "median ratio (frame ms / reference ms) of each name in ten green runs; the limit is the highest times headroom"}, open(out, "w"), indent=1, sort_keys=True)
print(f"{len(runs[-10:])} runs, names: {sorted({k for r in runs for k in r})}")
