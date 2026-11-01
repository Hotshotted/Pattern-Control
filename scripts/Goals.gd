class_name Goals
extends RefCounted
## The daily goals: three a day (one easy, one medium, one hard), drawn from a pool of templates and filled with values that fit
## the player's progress. Pure data and logic (no autoload is touched, so the tests can drive it directly): the caller passes in a
## context `ctx` describing the player and gets plain dictionaries back, which Save stores.
##
## ctx = {"open": [airport indexes the player has unlocked], "types": {airport: [aircraft types it spawns]}, "weather": {airport: bool},
##        "typical": {airport: landings in an ordinary shift}, "star1": {airport: landings for star 1}, "t2": {airport: net coins for star 2},
##        "noeng": bool (a glider airport with the No engines challenge switched on exists), "unit": coins (one easy goal's reward)}
##
## A goal: {"id": template id, "tier": 0..2, "ap": airport or -1, "n": target, "p": progress, "done": bool, "reward": coins, "rr": rerolled}.
## Events the game feeds in (see apply):
##   {"t": "land", "ap", "type", "emergency", "vip", "student", "no_engines", "streak"}
##   {"t": "shift", "ap", "landed", "go_arounds", "fines", "stars", "net", "hangar_full", "locked_run", "weather", "bad"}

enum Tier { EASY, MEDIUM, HARD }
const TIER_NAMES := ["Easy", "Medium", "Hard"]
const MULT := [1.0, 2.0, 4.0]         # the rewards: about 1x, 2x and 4x an average shift's pay at the best open airport
const CHEST := 2.0                    # the bonus chest for all three: this many easy goals' worth
const REROLLS_PER_GOAL := 1

## What an average player's shift pays at each airport (the career bot's average, survey) and how many aircraft it lands.
const AVG_PAY := [55, 64, 69, 56, 107, 150]
const TYPICAL_LANDINGS := [5, 6, 8, 6, 12, 13]

# Aircraft.Type: GLIDER 0, HELI 1, SMALL 2, MEDIUM 3, JET 4, SEAPLANE 5. Kinds:
#   land      count landings that match (airport / type / flag)         shifts    count finished shifts (at an airport)
#   stars     count the stars the shifts earn                           streak    one landing as the Nth in quick succession
#   shift_if  one shift that ends with a condition ("if": [[key, op, value], ...] on the shift event)
# "n": absolute target (a [lo, hi] range) or "per": that many ordinary shifts' worth of landings (at the goal's airport or the best one).
const TEMPLATES := [
	# ----- easy: doable in one ordinary shift -----
	{"id": "e_land_ap", "tier": 0, "kind": "land", "ap": true, "per": 0.8, "text": "Land {n} aircraft at {ap}"},
	{"id": "e_land_any", "tier": 0, "kind": "land", "per": 1.2, "text": "Land {n} aircraft today"},
	{"id": "e_small", "tier": 0, "kind": "land", "type": 2, "n": [3, 5], "text": "Land {n} small planes"},
	{"id": "e_medium", "tier": 0, "kind": "land", "type": 3, "n": [2, 4], "text": "Land {n} medium aircraft"},
	{"id": "e_heli", "tier": 0, "kind": "land", "type": 1, "n": [2, 3], "text": "Land {n} helicopters"},
	{"id": "e_glider", "tier": 0, "kind": "land", "type": 0, "n": [2, 3], "text": "Land {n} gliders"},
	{"id": "e_shift", "tier": 0, "kind": "shifts", "ap": true, "n": [1, 1], "text": "Finish a shift at {ap}"},
	{"id": "e_nofine", "tier": 0, "kind": "shift_if", "if": [["fines", "==", 0], ["landed", ">=", 1]], "n": [1, 1], "text": "Finish a shift with no fines"},
	{"id": "e_emerg", "tier": 0, "kind": "land", "flag": "emergency", "n": [1, 1], "text": "Land an emergency aircraft"},
	# ----- medium: two or three shifts -----
	{"id": "m_land_ap", "tier": 1, "kind": "land", "ap": true, "per": 2.2, "text": "Land {n} aircraft at {ap}"},
	{"id": "m_land_any", "tier": 1, "kind": "land", "per": 3.0, "text": "Land {n} aircraft today"},
	{"id": "m_stars2", "tier": 1, "kind": "stars", "n": [2, 2], "text": "Earn {n} stars today"},
	{"id": "m_shifts3", "tier": 1, "kind": "shifts", "n": [3, 3], "text": "Finish {n} shifts today"},
	{"id": "m_jets", "tier": 1, "kind": "land", "type": 4, "n": [3, 5], "text": "Land {n} jets"},
	{"id": "m_seaplane", "tier": 1, "kind": "land", "type": 5, "n": [3, 4], "text": "Land {n} seaplanes"},
	{"id": "m_heli", "tier": 1, "kind": "land", "type": 1, "n": [4, 6], "text": "Land {n} helicopters"},
	{"id": "m_emerg", "tier": 1, "kind": "land", "flag": "emergency", "n": [2, 3], "text": "Land {n} emergency aircraft"},
	{"id": "m_vip", "tier": 1, "kind": "land", "flag": "vip", "n": [1, 1], "text": "Land a VIP"},
	{"id": "m_student", "tier": 1, "kind": "land", "flag": "student", "n": [2, 4], "text": "Land {n} student pilots"},
	{"id": "m_hangar", "tier": 1, "kind": "shift_if", "ap": true, "if": [["hangar_full", "==", 1]], "n": [1, 1], "text": "Fill the hangar at {ap}"},
	{"id": "m_quick3", "tier": 1, "kind": "streak", "n": [3, 3], "text": "Land 3 aircraft in quick succession"},
	{"id": "m_nofine_ap", "tier": 1, "kind": "shift_if", "ap": true, "if": [["fines", "==", 0], ["landed", ">=", 3]], "n": [1, 1], "text": "Finish a shift at {ap} with no fines"},
	# ----- hard: a skill test -----
	{"id": "h_nogo", "tier": 2, "kind": "shift_if", "if": [["go_arounds", "==", 0], ["landed", ">=", 4]], "n": [1, 1], "text": "Finish a shift with no go-arounds"},
	{"id": "h_locked3", "tier": 2, "kind": "shift_if", "if": [["locked_run", ">=", 3]], "n": [1, 1], "text": "Finish a shift with 3 locked finals in a row"},
	{"id": "h_noeng", "tier": 2, "kind": "land", "type": 0, "flag": "no_engines", "n": [1, 1], "text": "Land a glider on No engines"},
	{"id": "h_3stars", "tier": 2, "kind": "shift_if", "if": [["stars", ">=", 3]], "n": [1, 1], "text": "Earn 3 stars in one shift"},
	{"id": "h_net", "tier": 2, "kind": "shift_if", "ap": true, "net": true, "n": [1, 1], "text": "Net {x} coins in one shift at {ap}"},
	{"id": "h_quick5", "tier": 2, "kind": "streak", "n": [5, 5], "text": "Land 5 aircraft in quick succession"},
	{"id": "h_weather", "tier": 2, "kind": "shift_if", "ap": true, "weather": true, "if": [["weather", "==", 1], ["stars", ">=", 1]], "n": [1, 1], "text": "Earn a star at {ap} through bad weather"},
	{"id": "h_clean_hangar", "tier": 2, "kind": "shift_if", "if": [["hangar_full", "==", 1], ["fines", "==", 0]], "n": [1, 1], "text": "Fill the hangar with no fines"},
	{"id": "h_bad", "tier": 2, "kind": "shift_if", "if": [["bad", "==", 1], ["stars", ">=", 1]], "n": [1, 1], "text": "Earn a star on Bad Pilot Day"},
]

static func template(id: String) -> Dictionary:
	for t in TEMPLATES:
		if t["id"] == id:
			return t
	return {}

static func template_count() -> int:
	return TEMPLATES.size()

## The reward unit for a player: an average shift's pay at the best open airport (times a tuning factor the caller applies).
static func unit_for(open: Array, factor: float = 1.0) -> int:
	var best := 0
	for a in open:
		best = maxi(best, AVG_PAY[clampi(int(a), 0, AVG_PAY.size() - 1)])
	return maxi(roundi(best * factor / 5.0) * 5, 5)

static func reward_for(tier: int, unit: int) -> int:
	return maxi(roundi(unit * MULT[clampi(tier, 0, 2)] / 5.0) * 5, 5)

static func chest_for(unit: int) -> int:
	return maxi(roundi(unit * CHEST / 5.0) * 5, 5)

# ---------- Generating ----------

## Is `t` usable for this player? (Only unlocked airports; only aircraft those airports bring; the No engines goal only when it can be done.)
static func eligible(t: Dictionary, ctx: Dictionary) -> bool:
	var open: Array = ctx["open"]
	if open.is_empty():
		return false
	if t.has("type"):
		var any := false
		for a in open:
			if (ctx["types"].get(a, []) as Array).has(int(t["type"])):
				any = true
		if not any:
			return false
	if t.get("flag", "") == "no_engines" and not bool(ctx.get("noeng", false)):
		return false
	if t.get("flag", "") == "student" and open.size() < 2:
		return false              # (students are rare on the opening airport)
	if t.get("weather", false):
		var w := false
		for a in open:
			if bool(ctx["weather"].get(a, false)):
				w = true
		if not w:
			return false
	return true

static func _pick_airport(t: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> int:
	var open: Array = ctx["open"]
	var pool: Array = []
	for a in open:
		if t.get("weather", false) and not bool(ctx["weather"].get(a, false)):
			continue
		pool.append(int(a))
	if pool.is_empty():
		pool = open.duplicate()
	# (the newer airports are picked more often: they are where the player is)
	var weights: Array = []
	var total := 0.0
	for a in pool:
		var w := 1.0 + float(a) * 0.5
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

## One goal from template `t`, filled in for this player.
static func fill(t: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var g := {"id": t["id"], "tier": int(t["tier"]), "ap": -1, "n": 1, "p": 0, "done": false, "rr": false}
	if t.get("ap", false):
		g["ap"] = _pick_airport(t, ctx, rng)
	if t.has("per"):
		var a: int = g["ap"]
		if a < 0:
			a = 0
			for o in ctx["open"]:
				a = maxi(a, int(o))
		var typ: float = float(ctx["typical"].get(a, TYPICAL_LANDINGS[clampi(a, 0, 5)]))
		g["n"] = maxi(roundi(typ * float(t["per"])), 2)
	else:
		var r: Array = t["n"]
		g["n"] = rng.randi_range(int(r[0]), int(r[1]))
	if t.get("net", false):
		g["x"] = int(ctx["t2"].get(g["ap"], 100))
	g["reward"] = reward_for(int(t["tier"]), int(ctx["unit"]))
	return g

## The three goals of day `day` (the same day gives the same goals, for the same progress).
static func make_day(day: int, ctx: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 7919 + 17
	var list: Array = []
	var used := {}
	for tier in 3:
		list.append(_draw(tier, ctx, rng, used))
	return {"day": day, "list": list, "chest": false}

static func _draw(tier: int, ctx: Dictionary, rng: RandomNumberGenerator, used: Dictionary) -> Dictionary:
	var pool: Array = []
	for t in TEMPLATES:
		if int(t["tier"]) == tier and not used.has(t["id"]) and eligible(t, ctx):
			pool.append(t)
	if pool.is_empty():
		for t in TEMPLATES:
			if int(t["tier"]) == tier and eligible(t, ctx):
				pool.append(t)
	var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	used[t["id"]] = true
	return fill(t, ctx, rng)

## Replace goal `i` with another of the same tier (once per goal per day; a finished goal cannot be rerolled). Returns true if it did.
static func reroll(day_goals: Dictionary, i: int, ctx: Dictionary) -> bool:
	var list: Array = day_goals["list"]
	if i < 0 or i >= list.size():
		return false
	var g: Dictionary = list[i]
	if bool(g.get("done", false)) or bool(g.get("rr", false)):
		return false
	var used := {}
	for o in list:
		used[o["id"]] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = int(day_goals["day"]) * 104729 + i * 31 + 5
	var fresh := _draw(int(g["tier"]), ctx, rng, used)
	fresh["rr"] = true
	list[i] = fresh
	return true

# ---------- Text ----------

static func text(g: Dictionary, airport_name: String = "") -> String:
	var t := template(g["id"])
	if t.is_empty():
		return ""
	return str(t["text"]).replace("{n}", str(int(g["n"]))).replace("{ap}", airport_name).replace("{x}", str(int(g.get("x", 0))))

static func progress_text(g: Dictionary) -> String:
	if bool(g.get("done", false)):
		return "Done"
	if int(g["n"]) <= 1:
		return ""
	return "%d / %d" % [int(g["p"]), int(g["n"])]

# ---------- Progress ----------

static func _cond(c: Array, ev: Dictionary) -> bool:
	var v := float(ev.get(c[0], 0))
	if ev.get(c[0], 0) is bool:
		v = 1.0 if ev[c[0]] else 0.0
	var w := float(c[2])
	match c[1]:
		"==": return is_equal_approx(v, w)
		">=": return v >= w
		"<=": return v <= w
	return false

## Feed one game event in; returns the indexes (0..2) of the goals that became done by it.
static func apply(day_goals: Dictionary, ev: Dictionary) -> Array:
	var finished: Array = []
	var list: Array = day_goals["list"]
	for i in list.size():
		var g: Dictionary = list[i]
		if bool(g.get("done", false)):
			continue
		var t := template(g["id"])
		if t.is_empty():
			continue
		var inc := 0
		match t["kind"]:
			"land":
				if ev["t"] == "land" and (int(g["ap"]) < 0 or int(ev["ap"]) == int(g["ap"])):
					var ok := true
					if t.has("type") and int(ev["type"]) != int(t["type"]):
						ok = false
					if t.has("flag") and not bool(ev.get(t["flag"], false)):
						ok = false
					inc = 1 if ok else 0
			"streak":
				if ev["t"] == "land" and int(ev.get("streak", 0)) >= int(g["n"]):
					inc = int(g["n"])
			"shifts":
				if ev["t"] == "shift" and int(ev.get("landed", 0)) >= 1 and (int(g["ap"]) < 0 or int(ev["ap"]) == int(g["ap"])):
					inc = 1
			"stars":
				if ev["t"] == "shift":
					inc = int(ev.get("stars", 0))
			"shift_if":
				if ev["t"] == "shift" and (int(g["ap"]) < 0 or int(ev["ap"]) == int(g["ap"])):
					var ok2 := true
					for c in t.get("if", []):
						if not _cond(c, ev):
							ok2 = false
					if t.get("net", false) and int(ev.get("net", 0)) < int(g.get("x", 0)):
						ok2 = false
					inc = 1 if ok2 else 0
		if inc > 0:
			g["p"] = mini(int(g["p"]) + inc, int(g["n"]))
			if int(g["p"]) >= int(g["n"]):
				g["done"] = true
				finished.append(i)
	return finished

static func done_count(day_goals: Dictionary) -> int:
	var n := 0
	for g in day_goals["list"]:
		if bool(g.get("done", false)):
			n += 1
	return n

# ---------- The streak ----------
## A day counts when the player finishes at least one daily goal. Day 1 to 7 pay more each day (a cosmetic on day 7 the first time round);
## the chain loops after day 7 (day 7 then pays a big pile of coins instead). Missing a day sends it back to day 1, unless a streak
## freeze covers the day: one is earned with each completed week (up to MAX_FREEZES), and they are spent automatically.

const STREAK_LEN := 7
const DAY_MULT := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]     # days 1 to 6, times the unit
const DAY7_COSMETIC_COINS := 3.0                        # (if every cosmetic is owned already)
const DAY7_LOOP := 5.0                                  # day 7 on the second round and later, times the unit
const MAX_FREEZES := 2

## The streak as the menu shows it today: {"count" (what a day done today would extend; 0 if it has been lost), "done_today", "freezes",
## "next_pos" (which day of the week today's goal would be), "at_risk" (a day was missed and a freeze covers it)}.
static func streak_state(s: Dictionary, today: int) -> Dictionary:
	var last := int(s.get("last", -1000))
	var count := int(s.get("count", 0))
	var freezes := int(s.get("freezes", 0))
	var out := {"count": count, "done_today": last == today, "freezes": freezes, "next_pos": 1, "at_risk": false}
	if last == today:
		out["next_pos"] = (count - 1) % STREAK_LEN + 1
		return out
	var missed := today - 1 - last
	if count > 0 and missed > 0:
		if freezes >= missed:
			out["at_risk"] = true
		else:
			out["count"] = 0
	if count == 0:
		out["count"] = 0
	out["next_pos"] = (int(out["count"])) % STREAK_LEN + 1
	return out

## Today's first finished goal: advance the streak. Returns {"already", "count", "pos", "freeze_used", "reset", "new_freeze"}.
static func streak_advance(s: Dictionary, today: int) -> Dictionary:
	var last := int(s.get("last", -1000))
	var count := int(s.get("count", 0))
	var freezes := int(s.get("freezes", 0))
	var res := {"already": false, "freeze_used": 0, "reset": false, "new_freeze": false}
	if last == today:
		res["already"] = true
		res["count"] = count
		res["pos"] = (count - 1) % STREAK_LEN + 1
		return res
	if count <= 0:
		count = 1
	else:
		var gap := today - last
		if gap == 1:
			count += 1
		elif gap > 1:
			var missed := gap - 1
			if freezes >= missed:
				freezes -= missed
				res["freeze_used"] = missed
				count += 1
			else:
				count = 1
				res["reset"] = true
	var pos := (count - 1) % STREAK_LEN + 1
	if pos == STREAK_LEN and freezes < MAX_FREEZES:
		freezes += 1
		res["new_freeze"] = true
	s["count"] = count
	s["last"] = today
	s["freezes"] = freezes
	s["best"] = maxi(int(s.get("best", 0)), count)
	res["count"] = count
	res["pos"] = pos
	return res

## What day `pos` of the chain (reached as streak day `count`) pays: {"coins": n, "cosmetic": bool (a cosmetic instead of coins; coins is the fallback)}.
static func day_reward(pos: int, count: int, unit: int) -> Dictionary:
	if pos < STREAK_LEN:
		return {"coins": maxi(roundi(unit * DAY_MULT[pos - 1] / 5.0) * 5, 5), "cosmetic": false}
	if count <= STREAK_LEN:
		return {"coins": maxi(roundi(unit * DAY7_COSMETIC_COINS / 5.0) * 5, 5), "cosmetic": true}
	return {"coins": maxi(roundi(unit * DAY7_LOOP / 5.0) * 5, 5), "cosmetic": false}
