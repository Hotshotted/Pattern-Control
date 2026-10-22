extends Node
## Everything that persists, in one versioned file (on the web, user:// lives in the browser's IndexedDB).
## Registered as the autoload `Save`. Version 1 held only the best score; version 2 was the airport game
## (coins, stars per airport, best landings, upgrades, unlocks, tips seen, the daily shift); version 3 has the
## timed-shift economy (best coin payout per airport) and the Bad Pilot Day record. Older saves migrate on
## load: stars, coins, upgrades and unlocks carry over untouched, best landings stay as they were, and the
## new best-coins records start at zero. Unknown or missing fields fall back to defaults, so adding a field
## never breaks an old save.

const VERSION := 3
const AIRPORT_SLOTS := 6
const STARS_PER_AIRPORT := 3

var path := "user://pattern_work.json"
var day_override := -1               # tests / debug: pretend it is this day number
var coins := 0
var stars := PackedInt32Array()      # AIRPORT_SLOTS * 3 flags
var best := PackedInt32Array()       # best landings per airport
var best_coins := PackedInt32Array() # best shift payout per airport (version 3)
var upgrades := {}                   # upgrade id -> level
var unlocks := {}                    # cosmetic id -> true (airport themes, liveries)
var equipped := {}                   # slot -> id
var tips_seen := {}                  # aircraft-type tips already shown
var daily := {}                      # {"done_day": int, "streak": int, "best": int, "best_day": int}
var bad_day := {}                    # Bad Pilot Day: the same fields, its own best and streak (version 3)
var shifts_played := 0
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
	upgrades = {}
	unlocks = {}
	equipped = {}
	tips_seen = {}
	daily = {}
	bad_day = {}
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
	upgrades = _dict(data.get("upgrades"))
	unlocks = _dict(data.get("unlocks"))
	equipped = _dict(data.get("equipped"))
	tips_seen = _dict(data.get("tips_seen"))
	daily = _dict(data.get("daily"))
	bad_day = _dict(data.get("bad_day"))
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
			"upgrades": upgrades, "unlocks": unlocks, "equipped": equipped, "tips_seen": tips_seen,
			"daily": daily, "bad_day": bad_day, "shifts_played": shifts_played, "airport_plays": Array(airport_plays), "selected_airport": selected_airport, "ads": ads,
			"sound_volume": sound_volume, "music_volume": music_volume, "ambience_volume": ambience_volume,
		}))

# ---------- Stars ----------

## Is airport `i` open? (By total stars; the debug unlock opens them all.)
func airport_open(i: int) -> bool:
	return Airports.unlocked(i, stars_total()) or unlocks.has("all_airports")

# ---------- Daily shift and Bad Pilot Day ----------
# Both are one seeded shift per day with a streak and a best; they keep separate records (daily / bad_day).

## Days since 1970 (UTC): the daily shift's id.
func today() -> int:
	return day_override if day_override >= 0 else int(Time.get_unix_time_from_system() / 86400.0)

func record(kind: String) -> Dictionary:
	return bad_day if kind == "bad" else daily

func daily_done_today(kind: String = "daily") -> bool:
	return int(record(kind).get("done_day", -1)) == today()

## Streak as it would read right now (a missed day resets it).
func daily_streak(kind: String = "daily") -> int:
	var rec := record(kind)
	var last := int(rec.get("done_day", -100))
	return int(rec.get("streak", 0)) if last >= today() - 1 else 0

## Record a completed one (at least one star): returns the streak after it. Call once per day.
func daily_complete(coins_made: int, kind: String = "daily") -> int:
	var rec := record(kind)
	var streak := daily_streak(kind) + 1
	rec["streak"] = streak
	rec["done_day"] = today()
	rec["best"] = maxi(coins_made, int(rec.get("best", 0)))
	rec["best_day"] = today()
	return streak

## Record a played one that did not complete (still counts toward its best).
func daily_note_score(coins_made: int, kind: String = "daily") -> void:
	var rec := record(kind)
	rec["best"] = maxi(coins_made, int(rec.get("best", 0)))

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
func buy_cosmetic(kind: String, id: String, price: int) -> bool:
	if owns(kind, id) or coins < price:
		return false
	coins -= price
	unlocks[kind + ":" + id] = true
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

func reset_all() -> void:
	_defaults()
	write_file()
