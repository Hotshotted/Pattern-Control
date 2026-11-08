extends Node
## Everything that persists, in one versioned file (on the web, user:// lives in the browser's IndexedDB).
## Registered as the autoload `Save`. Version 1 held only the best score; version 2 was the airport game
## (coins, stars per airport, best landings, upgrades, unlocks, tips seen, the daily shift); version 3 has the
## timed-shift economy (best coin payout per airport) and the Bad Pilot Day record; version 4 the airport improvements
## (levels per airport, bought on its detail screen); version 5 the daily goals and the login streak; version 6 the airport mastery (landings per airport), lifetime stats and achievements. Older saves migrate on
## load: stars, coins, upgrades and unlocks carry over untouched, best landings stay as they were, and the
## new best-coins records start at zero. Unknown or missing fields fall back to defaults, so adding a field
## never breaks an old save.

const VERSION := 7
const AIRPORT_SLOTS := 6
const STARS_PER_AIRPORT := 3

var path := "user://pattern_work.json"
var day_override := -1               # tests / debug: pretend it is this day number
var coins := 0
var stars := PackedInt32Array()      # AIRPORT_SLOTS * 3 flags
var best := PackedInt32Array()       # best landings per airport
var best_coins := PackedInt32Array() # best shift payout per airport (version 3)
var upgrades := {}                   # Tower upgrade id -> level (0 to 5)
var improvements := {}               # airport index (as text) -> {improvement id -> level 0 to 3} (version 4)
var unlocks := {}                    # cosmetic id -> true (airport themes, liveries)
var equipped := {}                   # slot -> id
var tips_seen := {}                  # aircraft-type tips already shown
var bad_day := {}                    # Bad Pilot Day: the same fields, its own best and streak (version 3)
var goals_all := {}                  # today's daily goals at every airport: {"day", "by": {airport -> {"list", "chest"}}} (version 7: three a day at each airport)
var goals_ap := 0                    # ...the airport `goals` is about right now
## The three goals of `goals_ap` for today ({"list", "chest"}, or {} before they are made): every part of the game that reads "the goals" reads these.
var goals: Dictionary:
	get:
		return _dict((_dict(goals_all.get("by"))).get(str(goals_ap)))
	set(v):
		if not goals_all.has("by") or not (goals_all["by"] is Dictionary):
			goals_all = {"day": today(), "by": {}}
		goals_all["day"] = int(v.get("day", goals_all.get("day", today())))
		(goals_all["by"] as Dictionary)[str(goals_ap)] = v
var event_modifiers := true          # (the tests switch the weekly event's effects off to keep their pay exact)
var last_seen := 0                   # when the game was last played (unix seconds): the offline hangar income runs from it (version 7)
var event := {}                      # the weekly event: {"week", "points", "claimed": [bool x5]} (version 7)
var goal_streak := {}                # the daily-goal streak: {"count", "last", "freezes", "best"} (version 5)
var mastery := PackedInt32Array()    # landings made at each airport, ever (version 6)
var mastery_paid := PackedInt32Array()   # the highest mastery rank already paid at each airport
var ap_xp := PackedInt32Array()      # XP earned at each airport: its level 1 to 20 (Progression) (version 7)
var ap_half := PackedInt32Array()    # the progress bonuses paid at each airport (two a level, version 7)
var ap_xp_seen := PackedInt32Array() # the airport level the player has already been told about (level-up banners, unlock rewards)
var stats := {}                      # lifetime counters the achievements read (version 6)
var achievements := {}               # achievement id -> the day it was earned (version 6)
var shifts_played := 0
var no_engines_at := PackedByteArray()  # the "No engines" challenge switched on, per airport (it only counts at three stars)
var no_engines_bad := false            # ...and for Bad Pilot Day
var airport_plays := PackedInt32Array()   # shifts finished at each airport (the first one there is gentler)
var ads := {}                        # ad stub bookkeeping: shifts since the last interstitial
var selected_airport := 0
var sound_volume := 0.8              # pause-menu volume sliders, 0..1 (absent in older saves: the default)
var music_volume := 0.8
var ambience_volume := 0.8          # the fog ambience (the third pause-menu slider)

func _ready() -> void:
	load_file()

func _defaults() -> void:
	coins = 0
	stars.resize(AIRPORT_SLOTS * STARS_PER_AIRPORT)
	stars.fill(0)
	best.resize(AIRPORT_SLOTS)
	best.fill(0)
	best_coins.resize(AIRPORT_SLOTS)
	best_coins.fill(0)
	mastery.resize(AIRPORT_SLOTS)
	mastery.fill(0)
	mastery_paid.resize(AIRPORT_SLOTS)
	mastery_paid.fill(0)
	ap_xp.resize(AIRPORT_SLOTS)
	ap_xp.fill(0)
	ap_xp_seen.resize(AIRPORT_SLOTS)
	ap_xp_seen.fill(1)
	ap_half.resize(AIRPORT_SLOTS)
	ap_half.fill(0)
	airport_plays.resize(AIRPORT_SLOTS)
	airport_plays.fill(0)
	no_engines_at.resize(AIRPORT_SLOTS)
	no_engines_at.fill(0)
	no_engines_bad = false
	upgrades = {}
	improvements = {}
	unlocks = {}
	equipped = {}
	tips_seen = {}
	bad_day = {}
	goals_all = {}
	goals_ap = 0
	last_seen = 0
	event = {}
	goal_streak = {}
	stats = {}
	achievements = {}
	shifts_played = 0
	selected_airport = 0
	sound_volume = 0.8
	music_volume = 0.8
	ambience_volume = 0.8
	ads = {}
	sync_levels()

func load_file() -> void:
	_defaults()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	var version := int(data.get("version", 1))
	if version < 2:
		best[0] = int(data.get("best", 0))   # version 1: a single best score, kept for the first airport
		return
	coins = int(data.get("coins", 0))
	var s: Array = data.get("stars", [])
	for i in mini(s.size(), stars.size()):
		stars[i] = int(s[i])
	var b: Array = data.get("best", [])
	for i in mini(b.size(), best.size()):
		best[i] = int(b[i])
	var bc: Array = data.get("best_coins", [])      # (absent in a version 2 save: the records start fresh)
	for i in mini(bc.size(), best_coins.size()):
		best_coins[i] = int(bc[i])
	var ml: Array = data.get("mastery", [])
	for i in mini(ml.size(), mastery.size()):
		mastery[i] = int(ml[i])
	var mp: Array = data.get("mastery_paid", [])
	for i in mini(mp.size(), mastery_paid.size()):
		mastery_paid[i] = int(mp[i])
	if data.has("ap_xp"):
		var xs: Array = data.get("ap_xp", [])
		for i in mini(xs.size(), ap_xp.size()):
			ap_xp[i] = int(xs[i])
	else:                         # a version 6 save: the landings and stars already made count as XP, so nobody starts at level 1 with a lot of history
		for i in AIRPORT_SLOTS:
			ap_xp[i] = mastery[i] * Progression.XP_LANDING + stars_of(i) * 120
	var hs: Array = data.get("ap_half", [])
	for i in AIRPORT_SLOTS:
		ap_xp_seen[i] = ap_level(i)
		ap_half[i] = int(hs[i]) if i < hs.size() else 2 * (ap_level(i) - 1)         # (a save that predates the halfway bonus starts after the levels it already has)
	stats = _dict(data.get("stats"))
	achievements = _dict(data.get("achievements"))
	var ap: Array = data.get("airport_plays", [])
	for i in mini(ap.size(), airport_plays.size()):
		airport_plays[i] = int(ap[i])
	var ne: Array = data.get("no_engines_at", [])
	for i in mini(ne.size(), no_engines_at.size()):
		no_engines_at[i] = 1 if int(ne[i]) != 0 else 0
	no_engines_bad = bool(data.get("no_engines_bad", false))
	upgrades = _dict(data.get("upgrades"))
	improvements = _dict(data.get("improvements"))
	unlocks = _dict(data.get("unlocks"))
	equipped = _dict(data.get("equipped"))
	tips_seen = _dict(data.get("tips_seen"))
	bad_day = _dict(data.get("bad_day"))
	goals_all = _dict(data.get("goals"))
	last_seen = int(data.get("last_seen", 0))
	event = _dict(data.get("event"))
	if not goals_all.has("by"):             # (version 6: one set of goals for the whole game: they start again)
		goals_all = {}
	goal_streak = _dict(data.get("streak"))
	shifts_played = int(data.get("shifts_played", 0))
	selected_airport = clampi(int(data.get("selected_airport", 0)), 0, AIRPORT_SLOTS - 1)
	ads = _dict(data.get("ads"))
	sound_volume = clampf(float(data.get("sound_volume", 0.8)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", 0.8)), 0.0, 1.0)
	ambience_volume = clampf(float(data.get("ambience_volume", 0.8)), 0.0, 1.0)
	grant_level_rewards()
	sync_levels()

func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}

func write_file() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"version": VERSION, "coins": coins, "stars": Array(stars), "best": Array(best), "best_coins": Array(best_coins),
			"upgrades": upgrades, "improvements": improvements, "unlocks": unlocks, "equipped": equipped, "tips_seen": tips_seen,
			"bad_day": bad_day, "goals": goals_all, "last_seen": last_seen, "event": event, "streak": goal_streak, "mastery": Array(mastery), "mastery_paid": Array(mastery_paid), "ap_xp": Array(ap_xp), "ap_half": Array(ap_half), "stats": stats, "achievements": achievements, "shifts_played": shifts_played, "airport_plays": Array(airport_plays), "no_engines_at": Array(no_engines_at), "no_engines_bad": no_engines_bad, "selected_airport": selected_airport, "ads": ads,
			"sound_volume": sound_volume, "music_volume": music_volume, "ambience_volume": ambience_volume,
		}))

# ---------- Stars ----------

## Is airport `i` open? The first is; each next one opens at level 8 of the one before it (the debug unlock opens them all).
func airport_open(i: int) -> bool:
	if i <= 0 or unlocks.has("all_airports") or DebugFlags.airports_enabled():
		return true
	return i < AIRPORT_SLOTS and ap_level(i - 1) >= Progression.GATE_LEVEL

# ---------- The weekly event ----------

## The event of this week, and the player's state in it: {"event": definition, "points", "claimed": [...], "week"} (a new week starts fresh).
func event_state() -> Dictionary:
	var wk := Rhythm.week_of(today())
	if int(event.get("week", -1)) != wk:
		event = {"week": wk, "points": 0, "claimed": [false, false, false, false, false]}
	return {"event": Rhythm.event_for_week(wk), "week": wk, "points": int(event["points"]), "claimed": event["claimed"]}

## A shift of `stars` stars was finished in the event week: its points count; the track's rewards that came within reach are paid. Returns
## [{"i": track index, "coins": n}] for the rewards just earned.
func event_add_shift(stars: int, unit: int) -> Array:
	event_state()
	event["points"] = int(event["points"]) + Rhythm.points_for_shift(stars)
	var out := []
	for i in Rhythm.TRACK.size():
		if int(event["points"]) >= int(Rhythm.TRACK[i]["points"]) and not bool(event["claimed"][i]):
			event["claimed"][i] = true
			var c := Rhythm.reward_coins(i, unit)
			add_coins(c)
			out.append({"i": i, "coins": c})
	return out

## Tell the airports which event is on (the traffic, the pay and the weather follow it).
func sync_event() -> void:
	Airports.event = Rhythm.event_for_week(Rhythm.week_of(today())) if event_modifiers else {}

# ---------- Offline income ----------

func now_unix() -> int:
	return int(Time.get_unix_time_from_system())

## The game is being played now: the offline clock restarts from this moment.
func touch() -> void:
	last_seen = now_unix()

## What the parked planes earned since the game was last played ({"total", "hours", "per"}: Rhythm.offline_income), or an empty result for a short absence or a first
## run. `capacity` and `mean_pay` per airport come from the caller (this class does not know the hangars).
func offline_pending(capacity: Array, mean_pay: Array) -> Dictionary:
	if last_seen <= 0:
		return {"total": 0}
	var secs := float(now_unix() - last_seen)
	if secs < Rhythm.OFFLINE_MIN_SECONDS:
		return {"total": 0}
	var caps := []
	for a in AIRPORT_SLOTS:
		caps.append(int(capacity[a]) if airport_open(a) else 0)
	return Rhythm.offline_income(secs, caps, mean_pay)

# ---------- Airport levels (XP) ----------

func ap_level(i: int) -> int:
	return Progression.level_for(i, ap_xp[clampi(i, 0, AIRPORT_SLOTS - 1)])

## Tell the airports (traffic, weather, pay) what level each is at.
func sync_levels() -> void:
	for a in AIRPORT_SLOTS:
		Airports.levels[a] = ap_level(a)
	sync_event()

## The level's progress at airport `i`: {"level", "into", "need", "left", "frac"} (Progression.progress).
func ap_progress(i: int) -> Dictionary:
	return Progression.progress(i, ap_xp[clampi(i, 0, AIRPORT_SLOTS - 1)])

## Earn `n` XP at airport `i`. Returns {"from", "to" (levels), "unlocks": [one entry per level reached: Progression.unlock_for + "level"]}; the cosmetics
## those levels give are yours at once.
func add_xp(i: int, n: int, pay_half: bool = true) -> Dictionary:
	var a := clampi(i, 0, AIRPORT_SLOTS - 1)
	var before := ap_level(a)
	ap_xp[a] += maxi(n, 0)
	var after := ap_level(a)
	var out := {"from": before, "to": after, "unlocks": [], "half": []}
	for lv in range(before + 1, after + 1):
		var u := Progression.unlock_for(a, lv)
		u["level"] = lv
		out["unlocks"].append(u)
	# progress bonuses: a third and two thirds of the way through a level's XP, one and a half average shifts' pay at this airport each
	# (`ap_half` counts the bonuses paid: two a level)
	for m in range(ap_half[a] + 1, 2 * (Progression.MAX_LEVEL - 1) + 1):
		var lv := (m - 1) / 2 + 1
		var j := (m - 1) % 2 + 1
		if lv > after or ap_xp[a] < Progression.xp_at_level(a, lv) + Progression.xp_to_next(a, lv) * j / 3:
			break
		var hc: int = roundi(float(Goals.AVG_PAY[a]) * 1.5) if pay_half else 0
		add_coins(hc)
		ap_half[a] = m
		if hc > 0:
			out["half"].append({"level": lv, "coins": hc, "part": j})
	grant_level_rewards()
	sync_levels()
	return out

## Hand over every cosmetic the airports' levels have given so far (a save that already had the levels gets them too).
func grant_level_rewards() -> void:
	for a in AIRPORT_SLOTS:
		var lv := ap_level(a)
		for l in [6, 8, 18, 20]:
			if lv >= l:
				var u := Progression.unlock_for(a, l)
				if u.has("cosmetic"):
					unlocks[u["cosmetic"]] = true

# ---------- Bad Pilot Day ----------
# One seeded shift per day with a streak and a best (its own record, bad_day). The old Daily Shift was retired for the daily goals.

## The day number: days since 1970 by the local clock, so a day turns over at local midnight (the goals, the streak and Bad Pilot Day).
func today() -> int:
	if day_override >= 0:
		return day_override
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	return int(floor((Time.get_unix_time_from_system() + bias_minutes * 60.0) / 86400.0))

func record(_kind: String) -> Dictionary:
	return bad_day

func daily_done_today(kind: String = "bad") -> bool:
	return int(record(kind).get("done_day", -1)) == today()

## Streak as it would read right now (a missed day resets it).
func daily_streak(kind: String = "bad") -> int:
	var rec := record(kind)
	var last := int(rec.get("done_day", -100))
	return int(rec.get("streak", 0)) if last >= today() - 1 else 0

## Record a completed one (at least one star): returns the streak after it. Call once per day.
func daily_complete(coins_made: int, kind: String = "bad") -> int:
	var rec := record(kind)
	var streak := daily_streak(kind) + 1
	rec["streak"] = streak
	rec["done_day"] = today()
	rec["best"] = maxi(coins_made, int(rec.get("best", 0)))
	rec["best_day"] = today()
	return streak

## Record a played one that did not complete (still counts toward its best).
func daily_note_score(coins_made: int, kind: String = "bad") -> void:
	var rec := record(kind)
	rec["best"] = maxi(coins_made, int(rec.get("best", 0)))

# ---------- Airport mastery ----------

func mastery_landings(airport: int) -> int:
	return mastery[clampi(airport, 0, AIRPORT_SLOTS - 1)]

func mastery_rank(airport: int) -> int:
	return Mastery.rank(airport, mastery_landings(airport))

## One more landing at `airport`. Returns what a new rank paid: {"ranks": [ranks reached], "coins": n, "cosmetics": ["kind:id", ...]} (empty ranks: nothing new).
func add_mastery_landing(airport: int, avg_pay: int) -> Dictionary:
	var a := clampi(airport, 0, AIRPORT_SLOTS - 1)
	mastery[a] += 1
	var out := {"ranks": [], "coins": 0, "cosmetics": []}
	var r := Mastery.rank(a, mastery[a])
	while mastery_paid[a] < r:
		mastery_paid[a] += 1
		var rr: int = mastery_paid[a]
		out["ranks"].append(rr)
		var c := Mastery.coins_for(a, rr, avg_pay)
		out["coins"] += c
		add_coins(c)
		var cid := Mastery.cosmetic_for(a, rr)
		if cid != "":
			unlocks[cid] = true
			out["cosmetics"].append(cid)
	return out

## The pay bonus mastery gives at `airport`: its rank's, and a little more for each airport at rank 5 (the gold badge's global bonus).
func mastery_pay_bonus(airport: int) -> float:
	var b := Mastery.pay_bonus(mastery_rank(airport))
	for a in AIRPORT_SLOTS:
		if mastery_rank(a) >= Mastery.MAX_RANK:
			b += Mastery.GLOBAL_BONUS
	return b

func mastery_total_landings() -> int:
	var n := 0
	for v in mastery:
		n += v
	return n

# ---------- Achievements ----------

func stat_add(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n

func stat_max(key: String, v: int) -> void:
	stats[key] = maxi(int(stats.get(key, 0)), v)

## The numbers the achievements read: the counters kept as the game is played, and what the save itself says.
func ach_stats() -> Dictionary:
	var st: Dictionary = stats.duplicate()
	st["landings"] = mastery_total_landings()
	st["fast_hangar"] = int(stats.get("fast_hangar", 9999))
	st["stars"] = stars_total()
	var open_n := 0
	var full_n := 0
	var rank5 := 0
	for i in AIRPORT_SLOTS:
		if airport_open(i):
			open_n += 1
		var all3 := true
		for iid in Improvements.IDS:
			if imp_level(i, iid) < Improvements.max_level(iid):
				all3 = false
		if all3:
			full_n += 1
		if mastery_rank(i) >= Mastery.MAX_RANK:
			rank5 += 1
	st["airports_open"] = open_n
	st["imp_full_one"] = 1 if full_n >= 1 else 0
	st["imp_full_all"] = 1 if full_n >= AIRPORT_SLOTS else 0
	var tmax := true
	for uid in Upgrades.IDS:
		if upgrade_level(uid) < Upgrades.MAX_LEVEL:
			tmax = false
	st["tower_max"] = 1 if tmax else 0
	st["rank5"] = rank5
	var lv := 0
	for l in Cosmetics.LIVERIES:
		if owns("livery", l["id"]):
			lv += 1
	var th := 0
	for t in Cosmetics.THEMES:
		if owns("theme", t["id"]):
			th += 1
	st["liveries"] = lv
	st["themes"] = th
	st["streak_best"] = int(goal_streak.get("best", 0))
	return st

## Check every achievement now; pay and record the new ones. Returns [{"id", "coins", "cosmetic"}].
func check_achievements() -> Array:
	var out: Array = []
	for id in Achievements.check(ach_stats(), achievements):
		var a := Achievements.def(id)
		achievements[id] = today()
		add_coins(int(a["coins"]))
		var cid: String = a.get("cos", "")
		if cid != "":
			unlocks[cid] = true
		out.append({"id": id, "coins": int(a["coins"]), "cosmetic": cid})
	return out

# ---------- Daily goals and the streak ----------

## Today's goals, made fresh when the day has changed (the context says what the player has unlocked, see Goals).
func ensure_goals(ctx: Dictionary) -> void:
	goals_ap = int(ctx.get("ap", goals_ap))
	if int(goals_all.get("day", -1)) != today() or not goals_all.has("by"):
		goals_all = {"day": today(), "by": {}}
	if (_dict((goals_all["by"] as Dictionary).get(str(goals_ap))).get("list", []) as Array).is_empty():
		(goals_all["by"] as Dictionary)[str(goals_ap)] = Goals.make_day(today(), ctx)

## Today's goals at airport `ap` (made if they are not yet): {"list", "chest"}.
func goals_for(ap: int, ctx: Dictionary) -> Dictionary:
	var keep := goals_ap
	ctx["ap"] = ap
	ensure_goals(ctx)
	var g := goals
	goals_ap = keep
	return g

## One free reroll per goal per day.
func reroll_goal(i: int, ctx: Dictionary) -> bool:
	ensure_goals(ctx)
	return Goals.reroll(goals, i, ctx)

## The cheapest cosmetic not owned yet ("theme:autumn"), or "" if every one is owned.
func cheapest_unowned_cosmetic() -> String:
	var best := ""
	var best_cost := 1 << 30
	for t in Cosmetics.THEMES:
		if t["id"] != "classic" and not owns("theme", t["id"]) and int(t["cost"]) < best_cost:
			best = "theme:" + t["id"]
			best_cost = int(t["cost"])
	for l in Cosmetics.LIVERIES:
		if l["id"] != "standard" and not owns("livery", l["id"]) and int(l["cost"]) < best_cost:
			best = "livery:" + l["id"]
			best_cost = int(l["cost"])
	return best

## A game event happened (a landing, the end of a shift): move the goals along and pay what finished. Returns
## {"finished": [{"i", "id", "reward"}], "coins": everything paid, "chest": the chest, "streak": {...} (the day's first goal), "cosmetic": id}.
func goal_event(ev: Dictionary, ctx: Dictionary) -> Dictionary:
	ensure_goals(ctx)
	var out := {"finished": [], "coins": 0, "chest": 0, "streak": {}, "cosmetic": "", "streak_coins": 0}
	var was := Goals.done_count(goals)
	var fin := Goals.apply(goals, ev)
	if fin.is_empty():
		return out
	var paid := 0
	for i in fin:
		var g: Dictionary = goals["list"][i]
		out["finished"].append({"i": i, "id": g["id"], "reward": int(g["reward"])})
		paid += int(g["reward"])
	var sr0 := {}
	if was == 0:
		sr0 = Goals.streak_advance(goal_streak, today())     # (the day's first goal at any airport carries the streak: later airports' first goals find it done)
	if was == 0 and not bool(sr0.get("already", false)):
		var sr := sr0
		var dr := Goals.day_reward(int(sr["pos"]), int(sr["count"]), int(ctx["unit"]))
		sr["reward"] = dr
		if dr["cosmetic"]:
			var cid := cheapest_unowned_cosmetic()
			if cid != "":
				unlocks[cid] = true
				out["cosmetic"] = cid
				dr["coins"] = 0
		out["streak"] = sr
		out["streak_coins"] = int(dr["coins"])
		paid += int(dr["coins"])
	if Goals.done_count(goals) >= (goals["list"] as Array).size() and not bool(goals.get("chest", false)):
		goals["chest"] = true
		out["chest"] = Goals.chest_for(int(ctx["unit"]))
		paid += int(out["chest"])
	out["coins"] = paid
	add_coins(paid)
	return out

# ---------- Cosmetics ----------

func owns(kind: String, id: String) -> bool:
	return unlocks.has(kind + ":" + id) or (kind == "theme" and id == "classic") or (id == "standard" and kind != "theme")

func equipped_id(kind: String) -> String:
	return str(equipped.get(kind, "classic" if kind == "theme" else "standard"))

func equip(kind: String, id: String) -> bool:
	if not owns(kind, id):
		return false
	equipped[kind] = id
	write_file()
	return true

## Buy (and equip) a cosmetic. Returns false if already owned or too expensive.
func buy_cosmetic(kind: String, id: String, price: int, equip_now: bool = true) -> bool:
	if owns(kind, id) or coins < price:
		return false
	coins -= price
	unlocks[kind + ":" + id] = true
	if equip_now:
		equipped[kind] = id
	write_file()
	return true

func has_star(airport: int, i: int) -> bool:
	return stars[airport * STARS_PER_AIRPORT + i] != 0

func award_star(airport: int, i: int) -> bool:
	## Returns true the first time this star is earned.
	var k := airport * STARS_PER_AIRPORT + i
	if stars[k] != 0:
		return false
	stars[k] = 1
	return true

func stars_of(airport: int) -> int:
	var n := 0
	for i in STARS_PER_AIRPORT:
		n += stars[airport * STARS_PER_AIRPORT + i]
	return n

## Is the "No engines" challenge on for this airport's shifts? (It is offered once the airport has three stars.)
func no_engines_on(airport: int) -> bool:
	return no_engines_at[airport] != 0 and stars_of(airport) >= STARS_PER_AIRPORT

func stars_total() -> int:
	var n := 0
	for v in stars:
		n += v
	return n

# ---------- Coins, bests ----------

func add_coins(n: int) -> void:
	coins = maxi(coins + n, 0)

func spend(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	return true

## Record a finished shift's landings. Returns true if it is a new best for that airport.
func submit_best(airport: int, landed: int) -> bool:
	if landed > best[airport]:
		best[airport] = landed
		return true
	return false

## Record a shift's coin payout. Returns true if it is a new best for that airport.
func submit_best_coins(airport: int, payout: int) -> bool:
	if payout > best_coins[airport]:
		best_coins[airport] = payout
		return true
	return false

func best_coins_for(airport: int) -> int:
	return best_coins[airport]

func best_for(airport: int) -> int:
	return best[airport]

## Buy the next level of an upgrade. Returns false (and changes nothing) if maxed or too expensive.
func buy_upgrade(id: String) -> bool:
	var lvl := upgrade_level(id)
	var price := Upgrades.cost(id, lvl)
	if price < 0 or coins < price:
		return false
	coins -= price
	upgrades[id] = lvl + 1
	write_file()
	return true

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

## The level of one of an airport's improvements (0 = not bought).
func imp_level(airport: int, id: String) -> int:
	var d = improvements.get(str(airport))
	return clampi(int(d.get(id, 0)), 0, Improvements.max_level(id)) if d is Dictionary else 0

## Can the next level of this improvement be bought here yet? (The airport's level gates how deep: Progression.imp_gate.)
func imp_unlocked(airport: int, id: String) -> bool:
	var lvl := imp_level(airport, id)
	return lvl < Improvements.max_level(id) and Progression.imp_gate(lvl + 1, id) <= ap_level(airport)

## Buy the next level of an airport's improvement. Returns false (and changes nothing) if the airport is closed, it is maxed or too dear.
func buy_improvement(airport: int, id: String) -> bool:
	if airport < 0 or airport >= AIRPORT_SLOTS or not airport_open(airport):
		return false
	var lvl := imp_level(airport, id)
	var price := Improvements.cost(airport, id, lvl)
	if price < 0 or coins < price or not imp_unlocked(airport, id):
		return false
	coins -= price
	var d = improvements.get(str(airport))
	if not (d is Dictionary):
		d = {}
		improvements[str(airport)] = d
	d[id] = lvl + 1
	write_file()
	return true

## How many improvement levels an airport has (0 to 42).
func imp_total(airport: int) -> int:
	var n := 0
	for id in Improvements.IDS:
		n += imp_level(airport, id)
	return n

func reset_all() -> void:
	_defaults()
	write_file()
