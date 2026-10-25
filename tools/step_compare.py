#!/usr/bin/env python3
"""Compares the economy survey at 60, 30 and 20 simulated frames a second (see tools/economy_sim.gd `fps=` and `totals`): the
landings, crashes and gross coins over all bots and airports must agree with the 60 fps run within 5%.
A step size changes when things happen by up to one step, and a shift is chaotic: a few events later the two runs are different
samples of the same game (each run is exactly repeatable, but a different step size is a different sample). Counts of N events then
differ by about sqrt(2N) with no bias at all, which is more than 5% of 130 crashes. So a difference over 5% fails only if it is also
beyond 2.5 standard errors of that sampling noise (landings and crashes: sqrt(a + b); coins: the landings' relative error). A real
bias (a system that pays or crashes differently at a bigger step) shows in the 5% of the counts that are big enough to measure, and
tools/step_micro.gd checks every system on its own, exactly.
   python3 tools/step_compare.py sim_60.txt sim_30.txt sim_20.txt"""
import sys
import collections

LIMIT = 0.05
SIGMAS = 2.5
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
            n = r["landed"] + base["landed"] if k == "coins" else r[k] + base[k]
            rel_noise = (2.0 / max(n / 2.0, 1.0)) ** 0.5 if k == "coins" else (max(n, 1) ** 0.5) / max(base[k], 1)
            z = diff / max(rel_noise, 1e-9)
            print("%s %-8s differs by %.1f%% (%.1f standard errors of the sampling noise)" % (f.split("/")[-1], k, 100 * diff, z))
            if diff > LIMIT and z > SIGMAS:
                bad.append("%s: %s differs by %.1f%% (limit %d%%; %.1f standard errors)" % (f, k, 100 * diff, 100 * LIMIT, z))
    if bad:
        print("FAIL: " + "; ".join(bad))
        sys.exit(1)
    print("OK: landings, crashes and coins agree at 60, 30 and 20 fps (within 5%, or within the sampling noise)")

main()
