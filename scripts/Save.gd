extends Node
## Everything that persists, in one versioned file (on the web, user:// lives in the browser's IndexedDB).
## Registered as the autoload `Save`. Version 1 held only the best score; version 2 was the airport game
## (coins, stars per airport, best landings, upgrades, unlocks, tips seen, the daily shift); version 3 has the
## timed-shift economy (best coin payout per airport) and the Bad Pilot Day record; version 4 the airport improvements
## (levels per airport, bought on its detail screen); version 5 the daily goals and the login streak. Older saves migrate on
## load: stars, coins, upgrades and unlocks carry over untouched, best landings stay as they were, and the
## new best-coins records start at zero. Unknown or missing fields fall back to defaults, so adding a field
## never breaks an old save.

const VERSION := 5
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
var goals := {}                      # today's three daily goals: {"day", "list", "chest"} (version 5)
var goal_streak := {}                # the daily-goal streak: {"count", "last", "freezes", "best"} (version 5)
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
	goals = {}
	goal_streak = {}
	shifts_played = 0
	selected_airport = 0
	sound_volume = 0.8
	music_volume = 0.8
	ambience_volume = 0.8
	ads = {}

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
	goals = _dict(data.get("goals"))
	goal_streak = _dict(data.get("streak"))
	shifts_played = int(data.get("shifts_played", 0))
	selected_airport = clampi(int(data.get("selected_airport", 0)), 0, AIRPORT_SLOTS - 1)
	ads = _dict(data.get("ads"))
	sound_volume = clampf(float(data.get("sound_volume", 0.8)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", 0.8)), 0.0, 1.0)
	ambience_volume = clampf(float(data.get("ambience_volume", 0.8)), 0.0, 1.0)

func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}

func write_file() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"version": VERSION, "coins": coins, "stars": Array(stars), "best": Array(best), "best_coins": Array(best_coins),
			"upgrades": upgrades, "improvements": improvements, "unlocks": unlocks, "equipped": equipped, "tips_seen": tips_seen,
			"bad_day": bad_day, "goals": goals, "streak": goal_streak, "shifts_played": shifts_played, "airport_plays": Array(airport_plays), "no_engines_at": Array(no_engines_at), "no_engines_bad": no_engines_bad, "selected_airport": selected_airport, "ads": ads,
			"sound_volume": sound_volume, "music_volume": music_volume, "ambience_volume": ambience_volume,
		}))

# ---------- Stars ----------

## Is airport `i` open? (By total stars; the debug unlock opens them all.)
func airport_open(i: int) -> bool:
	return Airports.unlocked(i, stars_total()) or unlocks.has("all_airports") or DebugFlags.airports_enabled()

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

# ---------- Daily goals and the streak ----------

## Today's goals, made fresh when the day has changed (the context says what the player has unlocked, see Goals).
func ensure_goals(ctx: Dictionary) -> void:
	if int(goals.get("day", -1)) != today() or (goals.get("list", []) as Array).is_empty():
		goals = Goals.make_day(today(), ctx)

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
	if was == 0:
		var sr := Goals.streak_advance(goal_streak, today())
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
	return unlocks.has(kind + ":" + id) or (kind == "theme" and id == "classic") or (kind == "livery" and id == "standard")

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
	return clampi(int(d.get(id, 0)), 0, Improvements.MAX_LEVEL) if d is Dictionary else 0

## Buy the next level of an airport's improvement. Returns false (and changes nothing) if the airport is closed, it is maxed or too dear.
func buy_improvement(airport: int, id: String) -> bool:
	if airport < 0 or airport >= AIRPORT_SLOTS or not airport_open(airport):
		return false
	var lvl := imp_level(airport, id)
	var price := Improvements.cost(airport, id, lvl)
	if price < 0 or coins < price:
		return false
	coins -= price
	var d = improvements.get(str(airport))
	if not (d is Dictionary):
		d = {}
		improvements[str(airport)] = d
	d[id] = lvl + 1
	write_file()
	return true

## How many improvement levels an airport has (0 to 15).
func imp_total(airport: int) -> int:
	var n := 0
	for id in Improvements.IDS:
		n += imp_level(airport, id)
	return n

func reset_all() -> void:
	_defaults()
	write_file()
