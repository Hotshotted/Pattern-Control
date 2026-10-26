#!/usr/bin/env python3
"""Gate on the median of several runs: median_gate.py LIMIT_MS report1.json report2.json ...

Each report is {name: worst_frame_ms}. A name passes when the median over the reports is within the limit (one noisy frame on a shared
CI runner cannot fail it; a frame that is slow in most runs does). Prints every run's numbers."""
import json, statistics, sys

limit = float(sys.argv[1])
reports = [json.load(open(f)) for f in sys.argv[2:]]
bad = []
for name in reports[0]:
    vals = [r[name] for r in reports if name in r]
    med = statistics.median(vals)
    flag = "" if med <= limit else "   <-- over the limit"
    print(f"  {name:14s} median {med:6.1f} ms   runs {', '.join(f'{v:.1f}' for v in vals)}{flag}")
    if med > limit:
        bad.append(name)
if bad:
    print(f"FAIL: median worst frame over {limit:g} ms: {', '.join(bad)}")
    sys.exit(1)
print(f"median worst frame within {limit:g} ms")
