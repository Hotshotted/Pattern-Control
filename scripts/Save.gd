extends Node
## Everything that persists, in one versioned file (on the web, user:// lives in the browser's IndexedDB).
## Registered as the autoload `Save`. Version 1 held only the best score; version 2 is the airport game:
## coins, stars per airport, best landings per airport, upgrades, unlocks, tips seen and the daily shift.
## Unknown or missing fields fall back to defaults, so adding a field never breaks an old save.

const VERSION := 2
const AIRPORT_SLOTS := 6
const STARS_PER_AIRPORT := 3

var path := "user://pattern_work.json"
var coins := 0
var stars := PackedInt32Array()      # AIRPORT_SLOTS * 3 flags
var best := PackedInt32Array()       # best landings per airport
var upgrades := {}                   # upgrade id -> level
var unlocks := {}                    # cosmetic id -> true (airport themes, liveries)
var equipped := {}                   # slot -> id
var tips_seen := {}                  # aircraft-type tips already shown
var daily := {}                      # {"day": int, "best": int, "streak": int, "last_streak_day": int}
var shifts_played := 0

func _ready() -> void:
	load_file()

func _defaults() -> void:
	coins = 0
	stars.resize(AIRPORT_SLOTS * STARS_PER_AIRPORT)
	stars.fill(0)
	best.resize(AIRPORT_SLOTS)
	best.fill(0)
	upgrades = {}
	unlocks = {}
	equipped = {}
	tips_seen = {}
	daily = {}
	shifts_played = 0

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
	upgrades = _dict(data.get("upgrades"))
	unlocks = _dict(data.get("unlocks"))
	equipped = _dict(data.get("equipped"))
	tips_seen = _dict(data.get("tips_seen"))
	daily = _dict(data.get("daily"))
	shifts_played = int(data.get("shifts_played", 0))

func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}

func write_file() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"version": VERSION, "coins": coins, "stars": Array(stars), "best": Array(best),
			"upgrades": upgrades, "unlocks": unlocks, "equipped": equipped, "tips_seen": tips_seen,
			"daily": daily, "shifts_played": shifts_played,
		}))

# ---------- Stars ----------

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

func best_for(airport: int) -> int:
	return best[airport]

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

func reset_all() -> void:
	_defaults()
	write_file()
