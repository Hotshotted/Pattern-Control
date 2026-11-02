#!/usr/bin/env python3
"""Gate frame measurements as a ratio to a reference workload, and on the raw milliseconds:
    median_gate.py [--history tools/gate_history.json] [--label NAME] report1.json report2.json ...

Each report (written by tools/web_boot_check.js / web_panel_check.js) is
    {"ref_ms": the reference workload's time on this runner during that run, "values": {name: worst_frame_ms}}.
A frame time in the game's own code depends on how fast the shared runner is at that moment (the same build measures 22 to 37 ms),
so every value is divided by its run's reference (tools/web_ref.js: a fixed workload timed in the same browser under the same CPU
slowdown) and the gate is on the MEDIAN over the reports (one noisy run cannot fail it; a frame that is slow in most runs does).
The raw milliseconds stay in the log.

The rule (limits from the history file, see tools/gate_history.py):
  * A name FAILS only when BOTH its median ratio is over its limit (the highest ratio it had in the last ten green runs, plus 25% headroom)
    AND its median raw time is over the raw ceiling (33 ms for shift frames and panels). A fast reference makes every ratio look worse with
    unchanged timings; a raw time under the ceiling is never a failure by itself. A name with no raw ceiling ("raw_ceiling_exempt" in the
    history, the mean frame) is gated on its ratio alone.
  * If the runner's reference workload (median over the reports) is more than 20% outside its usual range (history "ref_ms_range" and
    "ref_tolerance"), the run is logged as UNRELIABLE RUNNER, the ratio check is skipped, and every name is gated on raw ms only (a name with
    no raw ceiling is not gated on such a run).
  * A name with no history is only reported.
The last line printed, GATE_DATA, is that run's median ratios as JSON (what a history run is)."""
import json, statistics, sys

DEFAULTS = {"headroom": 1.25, "runs": [], "raw_ceiling_ms": 33.0, "raw_ceiling_exempt": [], "ref_ms_range": None, "ref_tolerance": 0.20}


def runner_state(ref_median, history):
    """(unreliable, text): is the reference more than `ref_tolerance` outside the usual range?"""
    rng = history.get("ref_ms_range")
    tol = float(history.get("ref_tolerance", 0.20))
    if not rng:
        return False, ""
    lo, hi = float(rng[0]), float(rng[1])
    if ref_median < lo * (1.0 - tol) or ref_median > hi * (1.0 + tol):
        return True, (f"UNRELIABLE RUNNER: the reference workload ({ref_median:.1f} ms) is more than {tol * 100:.0f}% outside its usual "
                      f"{lo:.1f} to {hi:.1f} ms: the ratio check is skipped for this run, gating on raw ms only")
    return False, ""


def verdict(name, ratio_med, raw_med, limit, unreliable, history):
    """-> (fails, note) for one name."""
    ceiling = None if name in history.get("raw_ceiling_exempt", []) else float(history.get("raw_ceiling_ms", 33.0))
    if unreliable:
        if ceiling is None:
            return False, "   (not gated on an unreliable runner: it has no raw ceiling)"
        if raw_med > ceiling:
            return True, f"   <-- FAIL: raw {raw_med:.1f} ms is over the {ceiling:g} ms ceiling (unreliable runner, raw only)"
        return False, ""
    over_ratio = limit is not None and ratio_med > limit
    if not over_ratio:
        return False, ""
    if ceiling is None:
        return True, "   <-- FAIL: ratio over its limit"
    if raw_med > ceiling:
        return True, f"   <-- FAIL: ratio over its limit and raw {raw_med:.1f} ms over the {ceiling:g} ms ceiling"
    return False, f"   (ratio over its limit, but raw {raw_med:.1f} ms is under the {ceiling:g} ms ceiling: passes)"


def main(argv):
    args = argv
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
    history = dict(DEFAULTS)
    try:
        if history_file:
            history.update(json.load(open(history_file)))
    except FileNotFoundError:
        pass
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
    ref_med = statistics.median(refs)
    print(f"{label}: reference workload per run {', '.join(f'{x:.1f}' for x in refs)} ms (median {ref_med:.1f})")
    unreliable, why = runner_state(ref_med, history)
    if unreliable:
        print(why)
    for name in reports[0]["values"]:
        raws = [r["values"][name] for r in reports if name in r["values"]]
        ratios = [r["values"][name] / r["ref_ms"] for r in reports if name in r["values"]]
        med = statistics.median(ratios)
        raw_med = statistics.median(raws)
        data[name] = round(med, 4)
        lim = limits.get(name)
        fails, note = verdict(name, med, raw_med, lim, unreliable, history)
        if fails:
            bad.append(name)
        lim_txt = f"limit {lim:.3f}" if lim is not None else "no history: reported only"
        print(f"  {name:14s} median ratio {med:6.3f} ({lim_txt})   raw ms {', '.join(f'{v:.1f}' for v in raws)} (median {raw_med:.1f})   ratios {', '.join(f'{v:.3f}' for v in ratios)}{note}")
    print("GATE_DATA " + json.dumps({"label": label, "ref_ms": round(ref_med, 1), "ratios": data, "unreliable_runner": unreliable}, sort_keys=True))
    if bad:
        print(f"FAIL: {', '.join(bad)} (ratio over its limit AND raw ms over the ceiling; on an unreliable runner raw ms only)")
        sys.exit(1)
    print("frame times within their limits" if (limits or unreliable) else "no history yet: nothing gated")


if __name__ == "__main__":
    main(sys.argv[1:])
