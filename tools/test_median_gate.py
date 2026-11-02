#!/usr/bin/env python3
"""Checks of the gate rule in tools/median_gate.py (run by CI before the timing gates):  python3 tools/test_median_gate.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "median_gate.py")
HIST = os.path.join(HERE, "gate_history.json")
history = json.load(open(HIST))
LIM = {}
for r in history["runs"][-10:]:
    for k, v in r.items():
        LIM[k] = max(LIM.get(k, 0.0), v)
LIM = {k: v * history["headroom"] for k, v in LIM.items()}
failures = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        failures.append(what)


def run(ref, values, hist=HIST):
    """Three reports with the same reference and `values` (name: worst frame ms in every report); returns (exit code, output)."""
    with tempfile.TemporaryDirectory() as d:
        files = []
        for i in range(3):
            f = os.path.join(d, "r%d.json" % i)
            json.dump({"ref_ms": ref, "values": values}, open(f, "w"))
            files.append(f)
        p = subprocess.run([sys.executable, GATE, "--history", hist, "--label", "panel"] + files, capture_output=True, text=True)
        return p.returncode, p.stdout


results_limit = LIM["Results"]
# a normal runner (80 ms reference): the ratio limit and the raw ceiling both matter
code, out = run(80.0, {"Results": 0.99 * results_limit * 80.0 + 0.0})          # a ratio just under the limit
check(code == 0, "a normal runner, ratio under its limit: passes")
over_raw = results_limit * 80.0 * 1.1
code, out = run(80.0, {"Results": over_raw})                                   # ratio over the limit; raw = %.1f
check((code == 1) == (over_raw > 33.0), "a normal runner, ratio over its limit: fails only if the raw time (%.1f ms) is over 33 ms" % over_raw)
code, out = run(80.0, {"Airports": 20.0})                                      # 0.25 ratio, over the 0.182 limit, but only 20 ms
check(code == 0 and "passes" in out, "a normal runner, ratio over its limit but raw 20 ms under the ceiling: passes")
code, out = run(80.0, {"Airports": 45.0})
check(code == 1 and "FAIL: ratio over its limit and raw 45.0 ms over the 33 ms ceiling" in out, "a normal runner, ratio over and raw 45 ms over the ceiling: fails")
code, out = run(80.0, {"Hangar": 40.0})
check(code == 1, "...a panel that is slow in raw terms and over its ratio limit fails (Hangar 40 ms)")
code, out = run(80.0, {"Results": 36.0})
check(code == 0, "a raw time over the ceiling is not a failure while the ratio is within its limit (Results 36 ms on an 80 ms runner)")
# the mean frame has no raw ceiling: the ratio alone
code, out = run(80.0, {"shift mean": 0.3 * 80.0})
check(code == 1, "'shift mean' (no raw ceiling) fails on its ratio alone")
# an unreliable runner: the fast reference of the 2 November run (53.5 ms; usual 68.3 to 87.1)
code, out = run(53.5, {"Airports": 25.0, "Results": 20.0})         # (ratios 0.47 and 0.37: far over their limits, but only 25 and 20 ms)
check(code == 0 and "UNRELIABLE RUNNER" in out and "ratio check is skipped" in out, "a fast reference (53.5 ms) is logged as an unreliable runner and the ratios are skipped")
code, out = run(53.5, {"Results": 40.6})
check(code == 1 and "unreliable runner, raw only" in out, "...and a raw time over 33 ms (40.6 ms) still fails there")
code, out = run(53.5, {"shift mean": 30.0})
check(code == 0 and "not gated on an unreliable runner" in out, "...while a name with no raw ceiling is not gated there")
code, out = run(54.0, {"Results": 10.0})
check("UNRELIABLE" in out, "54.0 ms is more than 20% under the lowest usual 68.3 ms")
code, out = run(55.0, {"Results": 10.0})
check("UNRELIABLE" not in out, "55.0 ms is within 20% of the lowest usual 68.3 ms")
code, out = run(106.0, {"Results": 10.0})
check("UNRELIABLE" in out, "a reference over 20% above the highest usual 87.1 ms is unreliable too")
check(json.loads([l for l in out.splitlines() if l.startswith("GATE_DATA")][0][10:])["unreliable_runner"] is True, "GATE_DATA records it")
# no history: nothing gated (the calibration and bisect workflows run this way)
code, out = subprocess.run([sys.executable, GATE, "--label", "x", "/dev/stdin"], input=json.dumps({"ref_ms": 80.0, "values": {"Results": 60.0}}), capture_output=True, text=True).returncode, ""
check(code == 0, "no history file: nothing is gated")
print("%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
