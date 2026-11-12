class_name Dev
extends RefCounted
## The hidden dev menu's logic (the panel itself is DevMenu.gd): career presets, manual changes, scenario switches, time tools. Nothing here runs for a
## player: the menu opens only with ?dev in the page address, or after five quick taps on the build stamp (any build). The functions work on the Save
## and the Tuning directly and do no drawing, so the tests can call them without the panel.

static var unlocked := false          # the five-tap opened it in this session
static var speed := 1                 # game speed in a shift: 1, 2 or 4 (Main.step runs that many steps per frame)
static var event_override := ""       # a weekly event forced on (an id of Rhythm.EVENTS); "" = the real week's
static var scenario := {}             # what the next shift is started with (see Main.dev_start): consumed by Main.restart

static func available() -> bool:
	return unlocked or DebugFlags.dev_enabled()

# ---------- Career presets ----------

## Where the average bot is after `h` hours of continuous play (docs/content_audit.md, 10.2 / 11.1): the hours at which each airport opens
## (it opens at level 8 of the one before), level 8 at the next opening, level 20 for everything at 67 h, everything bought at 60 h.
const OPEN_H := [0.0, 2.1, 5.7, 8.7, 11.9, 15.2]
const LEVEL20_H := 67.0
const ALL_BOUGHT_H := 60.0
const PRESETS := [
	{"id": "fresh", "label": "Fresh start", "h": 0.0},
	{"id": "m30", "label": "30 min", "h": 0.5},
	{"id": "h2", "label": "2 h (County just opened)", "h": 2.2},
	{"id": "h10", "label": "10 h", "h": 10.0},
	{"id": "h30", "label": "30 h", "h": 30.0},
	{"id": "h60", "label": "60 h", "h": 60.0},
	{"id": "all", "label": "Everything done", "h": 999.0},
]

## The (fractional) level airport `a` has after `h` hours: 1 before it opens, 8 when the next airport opens, 20 at LEVEL20_H.
static func level_at(a: int, h: float) -> float:
	if h >= LEVEL20_H:
		return 20.0
	var t0: float = OPEN_H[a]
	var t8: float = OPEN_H[a + 1] if a < 5 else OPEN_H[5] + 3.3
	if a == 0:
		t0 = 0.0
	if h <= t0:
		return 1.0
	if h <= t8:
		return 1.0 + 7.0 * (h - t0) / (t8 - t0)
	return 8.0 + 12.0 * (h - t8) / (LEVEL20_H - t8)

static func preset_info(id: String) -> Dictionary:
	for p in PRESETS:
		if p["id"] == id:
			return p
	return {}

## Make the save match the average bot at preset `id`. Returns a one-line summary. The tutorial runs for "fresh" only; every tip counts as seen otherwise.
static func apply_preset(id: String) -> String:
	var info := preset_info(id)
	if info.is_empty():
		return "Unknown preset."
	var h: float = info["h"]
	Save.wipe_everything_quiet()
	if h <= 0.0:
		Save.sync_levels()
		return "Fresh start: a new save, Day 1 tutorial on."
	var done := h >= 999.0
	var hh := LEVEL20_H if done else h
	for a in Save.AIRPORT_SLOTS:
		var lv := level_at(a, hh)
		var whole := clampi(int(floor(lv)), 1, Progression.MAX_LEVEL)
		var frac := lv - float(whole)
		var xp := Progression.xp_at_level(a, whole)
		if whole < Progression.MAX_LEVEL:
			xp += int(frac * float(Progression.xp_to_next(a, whole)))
		Save.ap_xp[a] = xp
		Save.ap_xp_seen[a] = whole
		Save.ap_half[a] = 2 * (whole - 1)
	Save.sync_levels()
	Save.grant_level_rewards()
	var open: Array = []
	for a in Save.AIRPORT_SLOTS:
		if Save.airport_open(a):
			open.append(a)
	# Stars, records, mastery and the shifts behind them follow each open airport's level.
	for a in open:
		var lv := Save.ap_level(a)
		var need := [2, 6, 12]
		for i in 3:
			if done or lv >= need[i]:
				Save.award_star(a, i)
		Save.best[a] = maxi(roundi(float(Goals.TYPICAL_LANDINGS[a]) * (1.0 + float(lv) / 12.0)), 1)
		Save.best_coins[a] = roundi(float(Goals.AVG_PAY[a]) * float(Goals.TYPICAL_LANDINGS[a]) * (1.0 + float(lv) / 10.0))
		Save.mastery[a] = int(float(Save.ap_xp[a]) * 0.15)
		var rank := Mastery.rank(a, Save.mastery[a])
		Save.mastery_paid[a] = rank
		for r in range(1, rank + 1):
			var cid := Mastery.cosmetic_for(a, r)
			if cid != "":
				Save.unlocks[cid] = true
		Save.airport_plays[a] = maxi(int(float(Save.ap_xp[a]) / 110.0), 1)
		Save.shifts_played += Save.airport_plays[a]
	# Purchases: cheapest first, until the share of everything that the average bot has spent by then is used up.
	var share := 1.0 if done else clampf(h / ALL_BOUGHT_H, 0.0, 1.0)
	_buy_share(open, share)
	_buy_cosmetic_share(clampf(h / 10.0, 0.0, 1.0) if not done else 1.0)
	# About two shifts' pay in the bank (the average bot spends as it goes).
	Save.coins = 2 * Goals.unit_for(open, 1.0) * 2
	Save.stats["tutorial"] = 2
	for k in Tips.LIST:
		Save.tips_seen[k] = true
	for a in open:
		Save.stats["ema_land_%d" % a] = Goals.TYPICAL_LANDINGS[a] * 100
	Save.check_achievements()
	Save.stats["ach_seen"] = Save.achievements.size()
	Save.touch()
	Save.sync_levels()
	Save.write_file()
	return "%s: %d airport(s) open, levels %s, %d stars, %d tower levels, %d improvement levels, %d coins." % [info["label"], open.size(), levels_text(), Save.stars_total(), tower_levels(), improvement_levels(), Save.coins]

static func levels_text() -> String:
	var parts: Array[String] = []
	for a in Save.AIRPORT_SLOTS:
		parts.append(str(Save.ap_level(a)))
	return "/".join(parts)

static func tower_levels() -> int:
	var n := 0
	for id in Upgrades.IDS:
		n += Save.upgrade_level(id)
	return n

static func improvement_levels() -> int:
	var n := 0
	for a in Save.AIRPORT_SLOTS:
		n += Save.imp_total(a)
	return n

## The price of everything that can be bought with coins at the open airports (improvements and the tower).
static func total_price(open: Array) -> int:
	var n := 0
	for a in open:
		n += Improvements.total_cost(a)
	for id in Upgrades.IDS:
		for l in Upgrades.MAX_LEVEL:
			n += Upgrades.cost(id, l)
	return n

static func _buy_share(open: Array, share: float) -> void:
	var budget := int(float(total_price(open)) * share)
	var guard := 0
	while guard < 2000:
		guard += 1
		var best_price := 1 << 30
		var best_kind := ""
		var best_ap := -1
		var best_id := ""
		for id in Upgrades.IDS:
			var p := Upgrades.cost(id, Save.upgrade_level(id))
			if p >= 0 and p < best_price:
				best_price = p
				best_kind = "u"
				best_id = id
		for a in open:
			for id in Improvements.IDS:
				if Save.imp_unlocked(a, id):
					var p := Improvements.cost(a, id, Save.imp_level(a, id))
					if p >= 0 and p < best_price:
						best_price = p
						best_kind = "i"
						best_ap = a
						best_id = id
		if best_kind == "" or best_price > budget:
			break
		budget -= best_price
		if best_kind == "u":
			Save.upgrades[best_id] = Save.upgrade_level(best_id) + 1
		else:
			var d = Save.improvements.get(str(best_ap))
			if not (d is Dictionary):
				d = {}
				Save.improvements[str(best_ap)] = d
			d[best_id] = Save.imp_level(best_ap, best_id) + 1

static func _buy_cosmetic_share(share: float) -> void:
	var items: Array = []
	var total := 0
	for kind in ["theme", "livery", "windsock", "hangar", "prop"]:
		for d in Cosmetics.items(kind):
			if Cosmetics.source(d) == "shop" and int(d.get("cost", 0)) > 0:
				items.append([int(d["cost"]), kind, str(d["id"])])
				total += int(d["cost"])
	items.sort_custom(func(x, y): return x[0] < y[0])
	var budget := int(float(total) * share)
	for it in items:
		if it[0] > budget:
			break
		budget -= it[0]
		Save.unlocks[str(it[1]) + ":" + str(it[2])] = true

# ---------- Manual changes ----------

static func add_coins(n: int) -> void:
	Save.add_coins(n)
	Save.write_file()

## Set airport `a`'s level (1 to 20) exactly: its XP is the start of that level, the progress bonuses and the cosmetics up to it are counted as paid.
static func set_level(a: int, level: int) -> void:
	var lv := clampi(level, 1, Progression.MAX_LEVEL)
	Save.ap_xp[a] = Progression.xp_at_level(a, lv)
	Save.ap_xp_seen[a] = lv
	Save.ap_half[a] = 2 * (lv - 1)
	Save.sync_levels()
	Save.grant_level_rewards()
	Save.write_file()

static func unlock_all_airports() -> void:
	Save.unlocks["all_airports"] = true
	Save.write_file()

# ---------- Time ----------

## Pretend the game was closed for `hours`: the welcome-back screen shows what the hangars earned (Main collects it on the menu).
static func fake_offline(hours: float) -> void:
	Save.last_seen = Save.now_unix() - int(hours * 3600.0)
	Save.write_file()

## Advance one day: the daily goals, the streak and the weekly event follow the new day number.
static func advance_day() -> int:
	Save.day_override = Save.today() + 1
	Save.sync_event()
	Save.write_file()
	return Save.day_override

# ---------- Scenarios ----------

const WINDS := [["", "Wind as usual"], ["calm", "Calm: into the wind"], ["cross", "Crosswind on the main runway"], ["tail", "Wind from behind: usual end closed"]]
const WEATHER := [["", "No forced weather"], ["crosswind", "Gusty crosswind (needs 2+ runways)"], ["storm", "Storm cell"], ["fog", "Fog"]]
## What a skipped shift looks like: [id, label, landed share of the one-star count, stars].
const SCORES := [["poor", "Poor (0 stars)", 0.6, 0], ["average", "Average (1 star)", 1.0, 1], ["good", "Good (2 stars)", 1.6, 2], ["three", "3 stars", 2.6, 3]]

## The wind direction a forced wind sets at the current airport (its main runway is runway 0): end 0's heading is the wind, so end 0 is used.
static func forced_wind_deg(kind: String) -> float:
	var h := Airports.end_heading_deg(0, 0)
	match kind:
		"calm":
			return fposmod(h, 360.0)
		"cross":                 # as far off the runway as the wind still allows it: every approach has a big crosswind
			return fposmod(h + Tuning.wind_tolerance_deg - 2.0, 360.0)
		"tail":                   # from the other way: end 0 closes, the far end takes the traffic
			return fposmod(h + 180.0, 360.0)
	return -1.0
