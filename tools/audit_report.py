#!/usr/bin/env python3
"""Summarise tools/audit_sim.gd career output:  audit_report.py DIR   (DIR holds career_<bot>_<policy>.txt files)
Prints, per career: minutes to unlock each airport, stars, the share of shifts with a net <= 0 (the star metric) and the share
paid by the pay floor, and the minutes to buy every upgrade / cosmetic."""
import glob, os, sys

def parse(path):
    rows, events = [], []
    for line in open(path):
        if line.startswith("CAREER"):
            parts = line.split()
            d = {"who": parts[1], "policy": parts[2]}
            for p in parts[3:]:
                if "=" in p:
                    k, v = p.split("=", 1)
                    try:
                        d[k] = float(v)
                    except ValueError:
                        d[k] = v
            rows.append(d)
        elif line.startswith("EVENT"):
            events.append(line.split())
    return rows, events

def summarise(path):
    rows, ev = parse(path)
    n = len(rows)
    unlock = {" ".join(e[5:-2]): float(e[3]) for e in ev if e[4] == "unlock"}
    first = lambda kind: next((float(e[3]) for e in ev if e[4] == kind), None)
    return dict(n=n, minutes=rows[-1]["min"], unlock=unlock, stars=int(sum(r["new_stars"] for r in rows)),
                neg=sum(1 for r in rows if r["net"] <= 0) / n, floor=sum(1 for r in rows if r["paid"] > r["net"]) / n,
                nopay=sum(1 for r in rows if r["paid"] <= 0) / n, all_up=first("all-upgrades"), all_cos=first("all-cosmetics"), all_stars=first("all-stars"))

if __name__ == "__main__":
    for f in sorted(glob.glob(os.path.join(sys.argv[1], "career_*.txt"))):
        s = summarise(f)
        print(os.path.basename(f)[7:-4], "shifts %d, %.0f min, %d stars, net<=0 %.0f%%, pay from the floor %.0f%%, no pay %.0f%%" % (s["n"], s["minutes"], s["stars"], 100 * s["neg"], 100 * s["floor"], 100 * s["nopay"]),
              "| unlocked (min):", ", ".join("%s %.0f" % (k, v) for k, v in s["unlock"].items()),
              "| all upgrades", s["all_up"], "all cosmetics", s["all_cos"], "all stars", s["all_stars"])
