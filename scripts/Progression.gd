class_name Progression
extends RefCounted
## Each airport is a long-term home, not a level to clear. Every shift there earns XP (landings, a clean sheet, the shift's three star
## objectives, daily goals); XP is the airport's level, 1 to 20, and each level unlocks something concrete that the airport's detail
## screen and the results card name ("next unlock"):
##   odd levels 3..19   the next tier of the airport's improvements (improvement level 2 needs airport level 3, level 3 needs 5, ... level 10 needs 19)
##   level 2, 12        a step in the pay rate at this airport
##   level 4, 14        a new aircraft type in this airport's traffic (twin, bizjet, helicopter, glider tow, seaplane ...)
##   level 6, 8, 18, 20 a cosmetic: an airport-themed livery, windsock and two hangar paints
##   level 8            the NEXT airport opens (and a windsock); level 20 also puts a landmark on this airport's field
##   level 10, 16       a traffic step: busier hours, or a new weather in the mix
## Pure data and arithmetic: no Save / Tuning references (the smoke test and the sims read it).

const MAX_LEVEL := 20
const GATE_LEVEL := 8                  # the level at which the next airport opens

# ---------- XP ----------
const XP_LANDING := 4                  # every landing at the airport
const XP_CLEAN_SHEET := 25             # a shift with no fine at all
const XP_STAR := [25, 50, 100]         # the shift's star objectives (every time one is met, not only the first)
const XP_GOAL := [30, 60, 120]         # a daily goal of tier 0, 1, 2

## XP from level L to L + 1 at the first airport; it rises by XP_GROWTH a level, and an airport multiplies it (XP_SCALE).
const XP_BASE := 1650.0
const XP_GROWTH := 1.035
const XP_SCALE := [1.0, 1.0, 1.05, 1.1, 1.15, 1.2]
## The first levels at every airport come quickly (a share of the curve), so each new airport starts with a run of level-ups.
const EARLY := [0.16, 0.7]

static func xp_to_next(ap: int, level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	var early: float = float(EARLY[level - 1]) if level <= EARLY.size() else 1.0
	return maxi(roundi(XP_BASE * pow(XP_GROWTH, float(level - 1)) * float(XP_SCALE[clampi(ap, 0, XP_SCALE.size() - 1)]) * early / 5.0) * 5, 5)

## XP needed in all to reach `level` (level 1 = 0).
static func xp_at_level(ap: int, level: int) -> int:
	var n := 0
	for l in range(1, mini(level, MAX_LEVEL)):
		n += xp_to_next(ap, l)
	return n

static func level_for(ap: int, xp: int) -> int:
	var l := 1
	var left := xp
	while l < MAX_LEVEL and left >= xp_to_next(ap, l):
		left -= xp_to_next(ap, l)
		l += 1
	return l

## {"level", "into" (XP since this level), "need" (XP from this level to the next, 0 at the top), "left" (XP to go), "frac" 0..1}.
static func progress(ap: int, xp: int) -> Dictionary:
	var l := level_for(ap, xp)
	if l >= MAX_LEVEL:
		return {"level": l, "into": 0, "need": 0, "left": 0, "frac": 1.0}
	var into := xp - xp_at_level(ap, l)
	var need := xp_to_next(ap, l)
	return {"level": l, "into": into, "need": need, "left": need - into, "frac": clampf(float(into) / float(need), 0.0, 1.0)}

## XP a shift is worth: its landings, a clean sheet, the star objectives it met (0..3 of them, as flags), and the goals it finished (their tiers).
static func shift_xp(landed: int, clean: bool, stars_met: Array, goal_tiers: Array) -> int:
	var n := landed * XP_LANDING
	if clean and landed > 0:
		n += XP_CLEAN_SHEET
	for k in mini(stars_met.size(), 3):
		if stars_met[k]:
			n += int(XP_STAR[k])
	for t in goal_tiers:
		n += int(XP_GOAL[clampi(int(t), 0, 2)])
	return n

# ---------- the unlocks ----------
const KIND_TIER := "tier"
const KIND_PAY := "pay"
const KIND_AIRCRAFT := "aircraft"
const KIND_COSMETIC := "cosmetic"
const KIND_GATE := "gate"
const KIND_TRAFFIC := "traffic"

## Airport level needed for improvement level n (1-based) of improvement `id`: level 1 from the start, then every second airport level. The hangar bay and
## the approach lights open on odd levels (2n - 1), the runway lights, fuel farm and extra exit on even ones (2n - 2), so every level opens something to buy.
static func imp_gate(n: int, id: String = "hangar") -> int:
	if n <= 1:
		return 1
	return 2 * n - 1 if (id == "hangar" or id == "applights") else 2 * n - 2

## The highest improvement level the airport's level allows for `id`.
static func imp_cap(level: int, id: String = "hangar") -> int:
	var n := 1
	while n < 10 and imp_gate(n + 1, id) <= level:
		n += 1
	return n

## What a level opens to buy: [[improvement id, level n], ...].
static func imp_unlocks_at(level: int) -> Array:
	var out := []
	for id in ["hangar", "rwlights", "applights", "fuel", "exit"]:
		for n in range(2, 11):
			if imp_gate(n, id) == level and not (n > 8 and id != "hangar"):
				out.append([id, n])
	return out

## Pay rate at the airport: steps at levels 2, 12 and 20.
const PAY_STEPS := {2: 0.08, 12: 0.12, 20: 0.15}
static var flat_pay := false             # (the smoke test's older sections count exact coins: the level's pay steps are off there)

static func pay_mult(level: int) -> float:
	if flat_pay:
		return 1.0
	var m := 1.0
	for l in PAY_STEPS:
		if level >= int(l):
			m *= 1.0 + float(PAY_STEPS[l])
	return m

## The aircraft each airport starts with (Aircraft.Type values: GLIDER 0, HELI 1, SMALL 2, MEDIUM 3, JET 4, SEAPLANE 5), and the ones that join
## at levels 4 and 14: [type, name of the new traffic]. Every airport has all of its own mix (Airports) by level 14.
const T_GLIDER := 0
const T_HELI := 1
const T_SMALL := 2
const T_MEDIUM := 3
const T_JET := 4
const T_SEAPLANE := 5
const AIRCRAFT := [
	{"start": [T_SMALL], "l4": [T_GLIDER, "Glider tows"], "l14": [T_MEDIUM, "Twin props"]},                       # Grass Strip
	{"start": [T_SMALL, T_MEDIUM], "l4": [T_GLIDER, "Glider tows"], "l14": [T_JET, "Bizjets"]},                    # County
	{"start": [T_SMALL, T_MEDIUM], "l4": [T_HELI, "Helicopters"], "l14": [T_JET, "Bizjets"]},                      # Regional
	{"start": [T_SMALL], "l4": [T_GLIDER, "Glider tows"], "l14": [T_MEDIUM, "Twin props"]},                        # Mountain Field
	{"start": [T_SMALL, T_MEDIUM], "l4": [T_SEAPLANE, "Seaplanes"], "l14": [T_JET, "Bizjets"]},                    # Island
	{"start": [T_SMALL, T_MEDIUM, T_JET], "l4": [T_HELI, "Helicopters"], "l14": [T_SEAPLANE, "Seaplanes"]},        # International
]

## The weather an airport adds at level 16 (an airport that has it all gets busier hours again instead): "" for none.
const WEATHER_L16 := ["crosswind", "fog", "storm", "crosswind", "", ""]

const NAMES := ["Grass Strip", "County", "Regional", "Mountain Field", "Island", "International"]
const WEATHER_NAMES := {"crosswind": "Crosswinds", "fog": "Fog", "storm": "Storms"}

## Cosmetics ("kind:id", name, what it is) given at levels 6, 8, 18 and 20 at each airport: an airport-themed livery, windsock and two hangar paints
## (their data is in Cosmetics, with the source "level").
const COSMETICS := [
	[["livery:lark", "Meadow Lark", "livery"], ["windsock:sunset", "Sunset sock", "windsock"], ["hangar:sand", "Sand roof", "hangar paint"], ["hangar:clay", "Clay roof", "hangar paint"]],
	[["livery:wren", "County Wren", "livery"], ["windsock:ocean", "Ocean sock", "windsock"], ["hangar:brick", "Brick roof", "hangar paint"], ["hangar:moss", "Moss roof", "hangar paint"]],
	[["livery:swift", "Regional Swift", "livery"], ["windsock:berry", "Berry sock", "windsock"], ["hangar:sage", "Sage roof", "hangar paint"], ["hangar:sky", "Cloud roof", "hangar paint"]],
	[["livery:ibex", "Peak Ibex", "livery"], ["windsock:mint", "Mint sock", "windsock"], ["hangar:navy", "Navy roof", "hangar paint"], ["hangar:ink", "Ink roof", "hangar paint"]],
	[["livery:gull", "Island Gull", "livery"], ["windsock:slate", "Slate sock", "windsock"], ["hangar:rose", "Rose roof", "hangar paint"], ["hangar:lilac", "Lilac roof", "hangar paint"]],
	[["livery:eagle", "Global Eagle", "livery"], ["windsock:gold", "Gold sock", "windsock"], ["hangar:ivory", "Ivory roof", "hangar paint"], ["hangar:amber", "Amber roof", "hangar paint"]],
]

## What each level unlocks at airport `ap`: {"kind", "title" (one line), "detail"}; level 1 has none.
static func unlock_for(ap: int, level: int) -> Dictionary:
	var a := clampi(ap, 0, 5)
	var nm: String = NAMES[a]
	var cos: Array = COSMETICS[a]
	if level < 2 or level > MAX_LEVEL:
		return {}
	var more := _imp_text(level)
	if level % 2 == 1:
		var n := (level + 1) / 2
		return {"kind": KIND_TIER, "title": "Improvements level %d" % n if more == "" else more, "detail": "%s at %s can go deeper" % [more if more != "" else "Improvements", nm], "tier": n}
	var u := _headline(a, level, nm, cos)
	if more != "" and not u.is_empty():
		u["detail"] = "%s  \u00b7  also opens: %s" % [u["detail"], more]
		u["imps"] = imp_unlocks_at(level)
	return u

## "Hangar bay 3, Approach lights 3" for the improvement levels that open at `level` ("" for none).
static func _imp_text(level: int) -> String:
	var names := {"hangar": "Hangar bay", "rwlights": "Runway lights", "applights": "Approach lights", "fuel": "Fuel farm", "exit": "Extra exit"}
	var parts := PackedStringArray()
	for e in imp_unlocks_at(level):
		parts.append("%s %d" % [names[e[0]], int(e[1])])
	return ", ".join(parts)

static func _headline(a: int, level: int, nm: String, cos: Array) -> Dictionary:
	match level:
		2:
			return {"kind": KIND_PAY, "title": "Pay rate +%d%%" % roundi(float(PAY_STEPS[2]) * 100.0), "detail": "Every landing at %s pays more" % nm}
		12:
			return {"kind": KIND_PAY, "title": "Pay rate +%d%%" % roundi(float(PAY_STEPS[12]) * 100.0), "detail": "Every landing at %s pays more" % nm}
		4:
			var t: Array = AIRCRAFT[a]["l4"]
			return {"kind": KIND_AIRCRAFT, "title": "New traffic: %s" % t[1], "detail": "%s join the arrivals at %s" % [t[1], nm], "type": int(t[0])}
		14:
			var t2: Array = AIRCRAFT[a]["l14"]
			return {"kind": KIND_AIRCRAFT, "title": "New traffic: %s" % t2[1], "detail": "%s join the arrivals at %s" % [t2[1], nm], "type": int(t2[0])}
		6:
			return {"kind": KIND_COSMETIC, "title": "New livery: %s" % cos[0][1], "detail": "A livery for your fleet, themed for %s" % nm, "cosmetic": cos[0][0]}
		8:
			if a < 5:
				return {"kind": KIND_GATE, "title": "%s opens" % NAMES[a + 1], "detail": "Your next home airport is open, and a windsock: %s" % cos[1][1], "cosmetic": cos[1][0], "opens": a + 1}
			return {"kind": KIND_COSMETIC, "title": "New windsock: %s" % cos[1][1], "detail": "A windsock for every field", "cosmetic": cos[1][0]}
		10:
			return {"kind": KIND_TRAFFIC, "title": "Busier hours", "detail": "Arrivals come about 8%% closer together at %s" % nm, "spawn": 0.92}
		16:
			var w: String = WEATHER_L16[a]
			if w != "":
				return {"kind": KIND_TRAFFIC, "title": "New weather: %s" % WEATHER_NAMES[w], "detail": "%s days join the weather at %s" % [WEATHER_NAMES[w], nm], "weather": w}
			return {"kind": KIND_TRAFFIC, "title": "Rush hour", "detail": "Arrivals come about 8%% closer again at %s" % nm, "spawn": 0.92}
		18:
			return {"kind": KIND_COSMETIC, "title": "New hangar paint: %s" % cos[2][1], "detail": "A roof colour for every hangar", "cosmetic": cos[2][0]}
		20:
			return {"kind": KIND_PAY, "title": "Pay +%d%%, a landmark and %s" % [roundi(float(PAY_STEPS[20]) * 100.0), cos[3][1]], "detail": "The field gets its landmark; %s is yours" % cos[3][1], "cosmetic": cos[3][0], "landmark": true}
	return {}

## The next level above `level` that unlocks something (every level does): {"level", ...unlock}, or {} at the top.
static func next_unlock(ap: int, level: int) -> Dictionary:
	if level >= MAX_LEVEL:
		return {}
	var u := unlock_for(ap, level + 1)
	u["level"] = level + 1
	return u

## All the cosmetics the levels give, "kind:id" -> [airport, level].
static func level_cosmetics() -> Dictionary:
	var out := {}
	for a in 6:
		for lv in [6, 8, 18, 20]:
			var u := unlock_for(a, lv)
			if u.has("cosmetic"):
				out[u["cosmetic"]] = [a, lv]
	return out

# ---------- what a level changes in play ----------

## The airport's traffic at `level`: its mix (Airports.mix: type -> weight) cut to the aircraft that have joined by then.
static func mix_at(ap: int, level: int, full: Dictionary) -> Dictionary:
	var a := clampi(ap, 0, 5)
	var have: Array = (AIRCRAFT[a]["start"] as Array).duplicate()
	if level >= 4:
		have.append(int((AIRCRAFT[a]["l4"] as Array)[0]))
	if level >= 14:
		have.append(int((AIRCRAFT[a]["l14"] as Array)[0]))
	var out := {}
	for t in full:
		if have.has(int(t)):
			out[t] = full[t]
	if out.is_empty():
		for t in full:
			out[t] = full[t]
	return out

## Arrivals' spacing: 1 at levels 1 to 9, 0.92 from level 10 (busier hours), and again from level 16 where no new weather joins.
static func spawn_scale(ap: int, level: int) -> float:
	var s := 1.0
	if level >= 10:
		s *= 0.92
	if level >= 16 and WEATHER_L16[clampi(ap, 0, 5)] == "":
		s *= 0.92
	return s

## The weather the airport has at `level`: its own, plus the one added at level 16.
static func weather_at(ap: int, level: int, base: Array) -> Array:
	var out := base.duplicate()
	var w: String = WEATHER_L16[clampi(ap, 0, 5)]
	if level >= 16 and w != "" and not out.has(w):
		out.append(w)
	return out

# ---------- the star objectives (three named objectives per airport, met in a shift) ----------
const STAR_NAMES := [
	["Smooth start", "Busy morning", "Grass Strip ace"],
	["First crossing", "Clean crossing", "County ace"],
	["Hangar full", "Parallel flow", "Regional ace"],
	["Ridge clear", "Mountain hours", "Mountain ace"],
	["Island hop", "Sea breeze", "Island ace"],
	["First wave", "Rush hour", "International ace"],
]
