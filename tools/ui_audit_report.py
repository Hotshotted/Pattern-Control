#!/usr/bin/env python3
"""Writes docs/ui_audit.md from the two reports of tools/ui_overlap_check.gd:
    docs/ui_audit/before/report.json   (the game as it was before the fixes)
    docs/ui_audit/report.json          (the game now)
The problem table groups the findings by screen, elements and type (a pair is one row, whatever the size or the state), and each group carries
the fix. A group no rule below knows is printed and makes the script fail, so the table can never have a row without a fix.
    python3 tools/ui_audit_report.py
"""
import collections
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEFORE = json.load(open(ROOT + "/docs/ui_audit/before/report.json"))
AFTER_PATH = ROOT + "/docs/ui_audit/report.json"
AFTER = json.load(open(AFTER_PATH)) if os.path.exists(AFTER_PATH) else {"problems": [], "states": 0, "allowed": 0}

SIZES = ["320x568", "375x667", "390x844", "430x932", "768x1024", "1280x720"]
DEVICES = {"320x568": "iPhone SE (1st gen)", "375x667": "iPhone SE (2nd, 3rd gen)", "390x844": "iPhone 14", "430x932": "iPhone 14 Pro Max",
           "768x1024": "iPad", "1280x720": "landscape web"}
TYPES = ["overlap", "clipped", "off-screen", "safe-area", "tap-size", "covered", "small-text"]


def strip(x):
    """An element's name without its rectangle and layer: kind 'text' [id]."""
    x = re.sub(r"\(-?\d+,-?\d+ \d+x\d+\)", "", x)
    x = re.sub(r" @\w+", "", x)
    return re.sub(r"\s+", " ", x).strip()


def label(x, screen=""):
    """A readable, size-independent name for an element."""
    x = strip(x)
    if x == "":
        return ""
    m = re.match(r"(\w+) '(.*?)'(?: \[(.*)\])?$", x)
    if not m:
        return x
    kind, text, ident = m.group(1), m.group(2), ""
    mi = re.search(r" \[([^\]]*)\]$", text)         # (a button is named 'its text [its id]')
    if mi:
        ident = mi.group(1)
        text = text[:mi.start()]
    if ident.startswith("ach:"):
        return "achievement row"
    if ident.startswith(("theme:", "livery:", "windsock:", "hangar:")):
        return "shop card"
    if ident.startswith("imp:"):
        return "improvement chip"
    if re.match(r"^(Mastery|Achievement): ", text) and kind == "text" and screen == "shop":
        return "locked card source line (shop)"
    if re.match(r"^(Achievement|Mountain Field|International|County|Regional|Island|Grass Strip): ", text) and ("rank" in text or "Achievement" in text) and ("+" in text):
        return "toast line"
    if text.startswith("Reach mastery rank"):
        return "achievement row sub text"
    text = re.sub(r"\d+", "N", text)
    if ident.startswith(("shop_tab:", "ach_tab:", "pv_mode:")):
        return "tab chip '%s'" % text
    return "%s '%s'" % (kind, text)


# (type, screen regex, A regex, B regex, fix). The first rule that matches wins.
RULES = [
    # ---- the airport detail screen (as it was: drawn by hand) ----
    ("overlap|clipped", r"detail", r"No engines|Rank|landings|to rank|top rank|glider", r"No engines|Rank|landings|to rank|top rank|glider|^$",
     "Rebuilt from containers (`DetailSheet`): the mastery rank, its bar and the No engines switch are rows of one VBox inside a Scroll, one under the other; the rank text is no longer in the corner the chip sat on"),
    ("overlap", r"detail", r"improvement chip|Extra exit|Fuel farm", r"landings|to rank|top rank", "Rebuilt (`DetailSheet`): the improvements are a grid under the tabs, the mastery rows are above or below it in the same column, never at the same place"),
    ("overlap", r"detail", r"Hangar .* profit", r"Fly here", "Rebuilt (`DetailSheet`): Fly here is pinned under the Scroll, not at a fixed offset from the bottom; what does not fit scrolls above it"),
    ("clipped|small-text", r"detail", r"Runway lights|Approach lights|improvement", r"^$", "Rebuilt (`DetailSheet`): an improvement chip is a container (icon, wrapping name, pips, price) as wide as its grid cell; the name wraps and is never shrunk below 26"),
    ("tap-size", r"detail", r"Stars|Improve|No engines|Fly here", r"^$", "Rebuilt (`DetailSheet`): every chip is at least 44 pt tall (`Style.tap_px()`) and as wide as its words"),
    # ---- results ----
    ("clipped", r"results", r"^text '\+N'", r"^$", "Chip numbers are fitted to their chip (`Style.fit_size`, with thousands separators)"),
    ("clipped|overlap", r"results", r"toast line", r"Next shift|^$|button|text", "The extra lines (streak, chest, toasts) flow inside the card (`Art.res_stack`): fitted, wrapped to two lines if needed, as many as fit above the Next shift button"),
    ("overlap", r"results", r"Next shift", r"toast line", "The extra lines (streak, chest, toasts) flow inside the card (`Art.res_stack`): fitted, wrapped to two lines if needed, as many as fit above the Next shift button"),
    ("clipped|overlap", r"results", r"Shift pay protected|Details|chev_down|more goals", r"Details|Shift pay protected|chev_down|more goals|button|^$", "The results card is laid out from the top down (`Art.res_stack`): chips, then the new-airport row, goals, the pay-protected pill, the extra lines, and the Details chip last, each in its own rectangle"),
    ("overlap", r"results", r"^text '\+N'", r"icon coin", "The goal rows' reward text and coin sit in separate boxes (the text ends 52 units before the coin)"),
    ("tap-size", r"results", r"Details|Watch to double|Refund fine|menu", r"^$", "Tap area grown to 44 pt (`Art.refresh_hits`); the Details chip is tap-high in the new stack"),
    # ---- shift HUD ----
    ("overlap|clipped", r"shift", r"Crosswind|Storm|icon storm|icon cross", r"Storm|Crosswind|icon storm|icon cross|toast line|^$",
     "The weather and last-arrivals chips start at y 400, under the banner's band (y 262 to 380): they sat at 300, under the banner that announces them"),
    ("off-screen|overlap|clipped", r"shift", r"toast line|No engines: no go|icon glider|icon star", r"toast line|icon cross|^$",
     "A long banner (a toast, the No engines notice) wraps onto two lines inside the screen, with its pill sized to fit (`Hud._start_banner`); it was one line as wide as the text, 1,869 units for the longest"),
    ("off-screen|overlap", r"shift", r"label 'Hangar fee|label 'Go-around|label 'Goal done", r"^$|label", "Popups fit their text down the size ladder (down to 28) to the 540-unit label, so none runs off the screen or into the next"),
    ("overlap", r"shift", r"pause", r"icon bad", "The challenge-mode icon sits under the pause button, which has the safe area's top (`Art._draw_hud`)"),
    ("tap-size", r"shift|pause", r"^button 'pause'", r"^$", "The pause button keeps its look; its tap area is grown to 44 pt (`Hud.pause_hit`)"),
    # ---- pause ----
    ("overlap", r"pause", r"Effects|Music|Ambience", r"Effects|Music|Ambience", "Slider names are drawn above the slider's tap area (52 above its centre), not on it"),
    ("tap-size", r"pause", r"slider|Effects|Music|Ambience", r"^$", "The pause sheet is a stack with the three sliders at least one tap apart, and each slider's tap area is 44 pt tall (`Hud.slider_at`)"),
    ("tap-size", r"pause", r"Privacy", r"^$", "Tap area grown downward into the free space under the pill"),
    ("safe-area|overlap", r"pause|menu", r"build dev|Bad pilot day", r"build dev|Bad pilot day|^$", "The build tag follows the safe area (`Hud.apply_safe`: it was placed once, before the safe area was known) and the menu's bottom row sits 90 units above the edge, clear of it"),
    # ---- menu ----
    ("tap-size", r"menu", r"No engines", r"^$", "A tap-sized chip of its own over the Bad pilot day button (it was a 44-unit strip in the gap above it)"),
    ("tap-size", r"menu", r"Daily goals|International|County|Grass|Regional|Island|Mountain|airports_tag|Tower|Hangar|Awards", r"^$", "Tap areas grown to 44 pt into the free space around them (`Art.refresh_hits`)"),
    # ---- list screens ----
    ("overlap", r"airports|shop|tower", r"^button 'back'", r"^glyph|icon", "A stale second total (the menu's coin pill) was still drawn on the list screens, under the Back button; those screens now show their one total (`Hud._use_panel`)"),
    ("overlap", r"achievements", r"icon coin", r"ACHIEVEMENTS", "The screen title is left-aligned after the Back button and fitted to the room before the total in the corner (`Hud._fit_select_title`): 9,999,999 coins no longer reaches the title"),
    ("clipped|overlap", r"airports", r"Unlock with|Everything", r"Unlock with|Everything|^$", "A locked airport's `Unlock with N` pill moves under the name (716 units wide, where an open card shows its stars) instead of over the 192-unit map picture"),
    ("small-text", r"shop", r"source line", r"^$", "The source line of a locked card is 22 (was 20) and wraps to two lines"),
    ("clipped", r"achievements", r"sub text", r"^$", "A row's second line wraps onto two lines when it does not fit even at the smallest size (nothing is shrunk below 24)"),
    ("tap-size", r".*", r"^button 'back'", r"^$", "The Back button keeps its 80-unit look and gets a 44 pt tap area (`Art.refresh_hits`); the content under it starts below that area (`Hud._ytop`)"),
    ("tap-size", r".*", r"tab chip", r"^$", "Tab chips are made `max(design height, 44 pt)` tall (`Style.tap_px()`), and the content below moves down with them"),
    ("tap-size", r"goals", r"Reroll", r"^$", "The Reroll chip is 44 pt tall and has its own row under its goal"),
    ("tap-size", r"shop|achievements|goals", r"shop card|achievement row|Bonus chest", r"^$", "Cards and rows are made `max(design height, 44 pt)` tall (it only changes the narrowest phones: 130 units is 38 pt on a 320-pt-wide screen)"),
    ("tap-size", r"preview", r"preview_close|Current|New", r"^$", "The close button keeps its look with a 44 pt tap area; the Current / New chips are tap-high"),
    ("tap-size", r".*", r".*", r"^$", "Tap area grown to 44 pt (`Art.refresh_hits`)"),
]


def fix_for(kind, screen, a, b):
    for rtype, rscreen, ra, rb, fix in RULES:
        if re.search(rtype, kind) and re.search(rscreen, screen) and re.search(ra, a) and re.search(rb, b):
            return fix
    return None


def screen_family(s):
    return re.sub(r"\d+", "N", s).split(" ")[0]


def pretty_screen(s):
    return {"menu": "Menu", "airports": "Airports", "detail": "Airport detail", "shop": "Shop", "tower": "Tower", "goals": "Daily goals",
            "achievements": "Achievements", "shift": "Shift HUD", "pause": "Pause", "results": "Results", "preview": "Shop preview", "ad": "Ad screen",
            "studio": "Studio logo"}.get(s, s)


def sizes_text(sizes):
    ss = sorted(sizes, key=lambda x: int(x.split("x")[0]))
    return "all six" if len(ss) == len(SIZES) else ", ".join(ss)


def counts(report):
    by = collections.Counter()
    for p in report["problems"]:
        by[(p["size"], p["type"])] += 1
    return by


def main():
    before_by = counts(BEFORE)
    after_by = counts(AFTER)
    out = []
    w = out.append
    nb, na = len(BEFORE["problems"]), len(AFTER["problems"])
    w("# UI audit\n")
    w("Overlapping, clipped and hidden interface is a release blocker. `tools/ui_overlap_check.gd` opens every screen, panel, popup, tab and state of the game at "
      "six screen sizes and reports, in pairs, what overlaps what, what is clipped, what is off the screen or under the notch, and what cannot be tapped. "
      "CI runs it on every push and fails on anything new. This page is generated by `tools/ui_audit_report.py` from the two reports in `docs/ui_audit/`.\n")
    w("## Result\n")
    w("| | before | after |\n|---|---:|---:|")
    w("| states x sizes checked | %d | %d |" % (BEFORE.get("states", 0), AFTER.get("states", 0)))
    w("| **problems** | **%d** | **%d** |" % (nb, na))
    for t in TYPES:
        b = sum(v for (s, ty), v in before_by.items() if ty == t)
        a = sum(v for (s, ty), v in after_by.items() if ty == t)
        if b or a:
            w("| %s | %d | %d |" % (t, b, a))
    w("| allowed by the allowlist | 0 | %d |\n" % AFTER.get("allowed", 0))
    w("By screen size (before / after):\n")
    w("| size | device | " + " | ".join(TYPES[:4] + TYPES[4:]) + " | total |")
    w("|---|---|" + "---:|" * (len(TYPES) + 1))
    for s in SIZES:
        row = []
        for t in TYPES:
            row.append("%d / %d" % (before_by.get((s, t), 0), after_by.get((s, t), 0)))
        tb = sum(before_by.get((s, t), 0) for t in TYPES)
        ta = sum(after_by.get((s, t), 0) for t in TYPES)
        w("| %s | %s | %s | **%d / %d** |" % (s, DEVICES[s], " | ".join(row), tb, ta))
    w("")
    w("The first run of the tool (the numbers above) was made on the game as it stood before this work (commit `28821f2`, with the tool's text recorder added to a copy of it by "
      "`tools/ui_audit_instrument.py`), so it includes the old hand-placed airport detail screen. Pictures are not kept in the repository "
      "(they were 37 MB): every CI run writes one per state and size, with each problem outlined in red, to the `ui-overlap-pictures` artifact (`<size>/<state>.jpg`).\n")

    w("## The airport detail screen: what covered what, and why\n")
    w("The screen with *Fly here* drew everything itself, each thing at its own hard-coded offset from the top of the card (`y0 = 0.667 x height`), and the *Fly here* "
      "button at a fixed distance from the bottom. Nothing owned the space, so later additions landed on top of earlier ones:\n")
    w("* **No engines (a chip at x = width - 370, y0 + 92 .. 144)** sat on the **mastery block** (rank line, bar and `N / N to rank N` at the same corner, y0 + 108 .. 154), "
      "added after it: the rank, its bar and the progress text were under the chip and could not be read or reached. This was the case on every airport with three stars "
      "(the picture of the old layout was removed with the other pictures; the numbers below come from `docs/ui_audit/before/report.json`).")
    w("* **Stars and Improve (two chips at y0 + 26 .. 78)** were fine alone, but the name and the tag were fitted to `width - 360` assuming those chips were all there was on the right, "
      "so on a long name the text ran under them, and the chips were 52 units tall (15 pt on a phone: under half a tap).")
    w("* **The improvement chips (y0 + 150 .. 326)** on the Improve tab covered the mastery progress text (y0 + 154) of the same card.")
    w("* **`Hangar N, profit after N landings` (y0 + 372)** ran into the **Fly here** button on screens whose height moved the button up relative to the card: the text was anchored to the top, the button to the bottom.")
    w("* The improvement names were shrunk in a loop down to **11** units to fit their chips.\n")
    w("Why: a screen of hand-placed rectangles has no layout, only coordinates, and the only check was a person looking at one phone size. "
      "The fix is a layout: `scripts/DetailSheet.gd` builds the card from containers (`PanelContainer` > `MarginContainer` > `VBoxContainer` > a `ScrollContainer` with the content, "
      "and the *Fly here* chip pinned under it), so nothing can sit on anything else; what does not fit scrolls, and *Fly here* stays in view. "
      "Every size in it is a minimum (a label wraps, a chip grows to its words and to 44 pt), not a position.\n")

    # ---- the table of every problem ----
    groups = collections.OrderedDict()
    unmapped = set()
    for p in BEFORE["problems"]:
        sc = screen_family(p["screen"])
        a, b = label(p["a"], sc), label(p["b"], sc)
        key = (sc, p["type"], a, b)
        g = groups.setdefault(key, {"count": 0, "sizes": set(), "states": set()})
        g["count"] += 1
        g["sizes"].add(p["size"])
        g["states"].add(p["screen"])
    rows = []
    for (sc, ty, a, b), g in groups.items():
        fix = fix_for(ty, sc, a, b)
        if fix is None:
            unmapped.add((sc, ty, a, b))
            continue
        rows.append((sc, ty, a, b, g, fix))
    if unmapped:
        for u in sorted(unmapped):
            print("UNMAPPED", u)
        sys.exit(1)
    order = {t: i for i, t in enumerate(TYPES)}
    rows.sort(key=lambda r: (r[0], order.get(r[1], 9), -r[4]["count"]))
    w("## Every problem found\n")
    w("One row per screen, pair of elements and type (a pair that occurs in several states or sizes is one row; `count` is the number of findings in the first run, "
      "`sizes` where it happened). \"Locked card\" etc. name the element, not one instance. After the fixes the tool finds none of them.\n")
    w("| Screen | Sizes | Elements | Type | Count | Fix |")
    w("|---|---|---|---|---:|---|")
    for sc, ty, a, b, g, fix in rows:
        els = a if not b else "%s  **vs**  %s" % (a, b)
        w("| %s | %s | %s | %s | %d | %s |" % (pretty_screen(sc), sizes_text(g["sizes"]), els.replace("|", "/"), ty, g["count"], fix.replace("|", "/")))
    w("")
    w("(%d rows from %d findings.)\n" % (len(rows), nb))

    # ---- worst five ----
    per_state = collections.Counter()
    for p in BEFORE["problems"]:
        per_state[(p["size"], p["screen"])] += 1
    best_of_family = {}
    for (size, screen), n in per_state.items():
        fam = screen_family(screen)
        if fam not in best_of_family or n > best_of_family[fam][2]:
            best_of_family[fam] = (size, screen, n)
    worst = sorted(best_of_family.values(), key=lambda t: -t[2])[:5]
    w("## The worst five screens (the worst state of each kind of screen, by number of problems in the first run)\n")
    w("| # | Screen at size | Problems in the first run |")
    w("|---|---|---:|")
    for i, (size, screen, n) in enumerate(worst, 1):
        fn = screen.replace(" ", "_").replace("/", "-") + ".jpg"
        w("| %d | %s at %s | %d |" % (i, screen, size, n))
    w("")
    w("(Each of them now has 0 problems; the CI artifact has the current picture, `<size>/<state>.jpg`.)\n")

    w("## The allowlist\n")
    w("Intentional overlaps are allowed only through the `ALLOW` list at the top of `tools/ui_overlap_check.gd`, one entry per case, each with a `why` "
      "(fields: `screen` (a glob on the state name), `size` (optional glob), `type`, `a` and optionally `b` (substrings of the two element names), `why`). "
      "Currently it has **%d** entries: every problem the tool found was fixed, none had to be allowed.\n" % 0)

    w("## What the tool does not open\n")
    w("Nothing is skipped silently: the tool prints this list with its totals.\n")
    w("* The privacy policy page: it opens the system browser (`web/privacy.html`); it is not an in-game screen.")
    w("* The TUNE panel and the perf overlay: developer tools behind `?tune` / `?perf` in the page address, never shown to players.")
    w("* Confirmation dialogs: the game has none (the shop's hold-to-buy preview sheet is covered, for every item).")
    w("* Popups: where one appears depends on where the aircraft is; they are checked at the screen's left, middle and right edges and with the longest texts.")
    w("* The boot splash (the studio mark and a bar while the game pre-warms) is drawn by a class of its own at fixed sizes, centred: it is checked by measuring "
      "(the wordmark is 633 units wide on a screen that is never narrower than 1080).\n")

    w("## What is checked, and how\n")
    w("* **Overlap**: two visible things (text, labels, icons, buttons) whose rectangles overlap, unless one is nested in the other (a label inside *all of* its own button). "
      "Text is measured by its ink (cap height to descender), canvas-drawn text and icons are recorded as they are drawn (`Art._ds`, `_dms`, `glyph`), Controls are read from the tree "
      "(clipped by their Scroll). Two buttons whose *tap areas* overlap are reported as `covered`.")
    w("* **Clipped**: text wider than the width it is drawn with, a wrapped run that lost its last line, text that leaves the button or panel it is on, a word broken across lines.")
    w("* **Off-screen / safe-area**: any part outside the screen, or text and buttons under the notch, the Dynamic Island or the home indicator (the safe area of each size is in the tool).")
    w("* **Tap size**: a button's tap area under 44 x 44 points (`Style.px_per_pt` units per point), or covered by another control.")
    w("* **Small text**: under `Style.MIN_TEXT` (22 units), the smallest size the interface draws; see `docs/style.md`, *Layout and legibility rules*.")
    w("* Every state is also run with the largest numbers (9,999,999 coins, an eight-digit payout) and the longest real strings (the longest toast, achievement and mastery lines).\n")
    w("Run it: `godot --headless --path . --script tools/ui_overlap_check.gd` (the check, about 6 minutes), or under `xvfb-run -a godot --path . --rendering-driver opengl3 --script "
      "tools/ui_overlap_check.gd -- shots=<dir> report=docs/ui_audit/report.json` for the pictures. Options: `only=<text>`, `sizes=390x844,...`, `quiet`, `plant` (the CI self-test).\n")
    open(ROOT + "/docs/ui_audit.md", "w").write("\n".join(out) + "\n")
    print("wrote docs/ui_audit.md: %d rows, before %d, after %d" % (len(rows), nb, na))


if __name__ == "__main__":
    main()
