#!/usr/bin/env python3
"""Gate frame measurements as a ratio to a reference workload:
    median_gate.py [--history tools/gate_history.json] [--label NAME] report1.json report2.json ...

Each report (written by tools/web_boot_check.js / web_panel_check.js) is
    {"ref_ms": the reference workload's time on this runner during that run, "values": {name: worst_frame_ms}}.
A frame time in the game's own code depends on how fast the shared runner is at that moment (the same build measures 22 to 37 ms),
so every value is divided by its run's reference (tools/web_ref.js: a fixed workload timed in the same browser under the same CPU
slowdown) and the gate is on the MEDIAN RATIO over the reports (one noisy run cannot fail it; a frame that is slow in most runs does).
The raw milliseconds stay in the log.

The limit of each name is set from the history file: the highest ratio that name had in the last ten green runs, plus 25% headroom
(history = {"headroom": 1.25, "runs": [{name: ratio, ...}, ...]}, newest last; refresh it with tools/gate_history.py).
A name with no history is only reported. The last line printed, GATE_DATA, is that run's median ratios as JSON (what a history run is)."""
import json, statistics, sys

args = sys.argv[1:]
history_file = None
label = "gate"
while args and args[0].startswith("--"):
    if args[0] == "--history":
        history_file = args[1]
        args = args[2:]
    elif args[0] == "--label":
        label = args[1]
        args = args[2:]
    else:
        sys.exit("unknown option " + args[0])
reports = [json.load(open(f)) for f in args]
try:
    history = json.load(open(history_file)) if history_file else {"headroom": 1.25, "runs": []}
except FileNotFoundError:
    history = {"headroom": 1.25, "runs": []}
headroom = float(history.get("headroom", 1.25))
runs = history.get("runs", [])[-10:]

limits = {}
for name in reports[0]["values"]:
    seen = [r[name] for r in runs if name in r]
    if seen:
        limits[name] = max(seen) * headroom

bad = []
data = {}
refs = [r["ref_ms"] for r in reports]
print(f"{label}: reference workload per run {', '.join(f'{x:.1f}' for x in refs)} ms (median {statistics.median(refs):.1f})")
for name in reports[0]["values"]:
    raws = [r["values"][name] for r in reports if name in r["values"]]
    ratios = [r["values"][name] / r["ref_ms"] for r in reports if name in r["values"]]
    med = statistics.median(ratios)
    data[name] = round(med, 4)
    lim = limits.get(name)
    flag = ""
    if lim is not None and med > lim:
        flag = "   <-- over the limit"
        bad.append(name)
    lim_txt = f"limit {lim:.3f}" if lim is not None else "no history: reported only"
    print(f"  {name:14s} median ratio {med:6.3f} ({lim_txt})   raw ms {', '.join(f'{v:.1f}' for v in raws)}   ratios {', '.join(f'{v:.3f}' for v in ratios)}{flag}")
print("GATE_DATA " + json.dumps({"label": label, "ref_ms": round(statistics.median(refs), 1), "ratios": data}, sort_keys=True))
if bad:
    print(f"FAIL: median frame ratio over its limit ({headroom:g} x the worst of the last {len(runs)} green runs): {', '.join(bad)}")
    sys.exit(1)
print("frame ratios within their limits" if limits else "no history yet: nothing gated")
