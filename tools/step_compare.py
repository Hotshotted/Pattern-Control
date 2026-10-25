#!/usr/bin/env python3
"""Compares the economy survey at 60, 30 and 20 simulated frames a second (see tools/economy_sim.gd `fps=` and `totals`): the
landings, crashes and gross coins over all bots and airports must agree with the 60 fps run within 5%.
   python3 tools/step_compare.py sim_60.txt sim_30.txt sim_20.txt"""
import sys
import collections

LIMIT = 0.05
KEYS = ["landed", "crashes", "coins"]

def load(path):
    total = collections.Counter()
    rows = 0
    for line in open(path):
        if not line.startswith("TOTALS"):
            continue
        rows += 1
        for kv in line.split()[3:]:
            k, v = kv.split("=")
            total[k] += int(v)
    return total, rows

def main():
    files = sys.argv[1:]
    runs = [load(f) for f in files]
    base, rows = runs[0]
    print("%d bot/airport rows per run" % rows)
    print("%-12s" % "" + "".join("%12s" % f.split("/")[-1] for f in files))
    for k in ["landed", "spawned", "conflicts", "crashes", "diversions", "coins", "paid"]:
        print("%-12s" % k + "".join("%12d" % r[0][k] for r in runs) + ("   <- checked" if k in KEYS else ""))
    bad = []
    for f, (r, n) in zip(files[1:], runs[1:]):
        if n != rows:
            bad.append("%s has %d rows, not %d" % (f, n, rows))
        for k in KEYS:
            diff = abs(r[k] - base[k]) / max(base[k], 1)
            print("%s %-8s differs by %.1f%%" % (f.split("/")[-1], k, 100 * diff))
            if diff > LIMIT:
                bad.append("%s: %s differs by %.1f%% (limit %d%%)" % (f, k, 100 * diff, 100 * LIMIT))
    if bad:
        print("FAIL: " + "; ".join(bad))
        sys.exit(1)
    print("OK: landings, crashes and coins agree within 5%% at 60, 30 and 20 fps")

main()
