class_name Achievements
extends RefCounted
## One-time achievements, in four groups (Landings, Skill, Airports, Collection) and three sizes (easy, medium, rare). Each pays coins once and
## about a third also give a cosmetic ("kind:id", see Cosmetics). Pure data and logic: `check` reads a flat stats dictionary the game builds
## (Save.ach_stats) and says which achievements have just been met.
##
## stats keys: landings, shifts, emergencies, quick_best (landings in quick succession), locked_best (locked finals in a row), nogo_shifts,
## clean_shifts, three_star_shifts, fast_hangar (seconds, 9999 if never), noeng_landings, noeng_intl, net_best, weather_shifts, bad_stars,
## goals_done, chests, streak_best, stars (total), airports_open, imp_full_one (an airport with every improvement at level 3), imp_full_all,
## tower_max (every Tower upgrade at level 5), rank5 (airports at mastery rank 5), liveries, themes (owned).

enum Group { LANDINGS, SKILL, AIRPORTS, COLLECTION }
const GROUP_NAMES := ["Landings", "Skill", "Airports", "Collection"]
const SIZE_NAMES := ["Easy", "Medium", "Rare"]

# {id, group, size (0 easy, 1 medium, 2 rare), name, text, key, "ge"/"le" value, coins, optional cosmetic}
const LIST := [
	# ----- Landings -----
	{"id": "a_first", "g": 0, "s": 0, "name": "First landing", "text": "Land an aircraft", "k": "landings", "ge": 1, "coins": 20},
	{"id": "a_l100", "g": 0, "s": 0, "name": "Regular", "text": "100 landings", "k": "landings", "ge": 100, "coins": 60},
	{"id": "a_l500", "g": 0, "s": 1, "name": "Busy tower", "text": "500 landings", "k": "landings", "ge": 500, "coins": 150},
	{"id": "a_l1000", "g": 0, "s": 1, "name": "Thousand", "text": "1,000 landings", "k": "landings", "ge": 1000, "coins": 250, "cos": "livery:lion"},
	{"id": "a_l2500", "g": 0, "s": 2, "name": "Air traffic veteran", "text": "2,500 landings", "k": "landings", "ge": 2500, "coins": 400},
	{"id": "a_l5000", "g": 0, "s": 2, "name": "Five thousand", "text": "5,000 landings", "k": "landings", "ge": 5000, "coins": 700, "cos": "windsock:rainbow"},
	{"id": "a_quick5", "g": 0, "s": 0, "name": "In quick succession", "text": "Land 5 aircraft in quick succession", "k": "quick_best", "ge": 5, "coins": 40},
	{"id": "a_emerg10", "g": 0, "s": 1, "name": "First responder", "text": "Land 10 emergency aircraft", "k": "emergencies", "ge": 10, "coins": 120},
	# ----- Skill -----
	{"id": "s_nogo", "g": 1, "s": 0, "name": "Smooth shift", "text": "Finish a shift with no go-arounds", "k": "nogo_shifts", "ge": 1, "coins": 60},
	{"id": "s_clean", "g": 1, "s": 0, "name": "Clean sheet", "text": "A shift with no fines (6+ landings)", "k": "clean_shifts", "ge": 1, "coins": 50},
	{"id": "s_3stars", "g": 1, "s": 0, "name": "Three-star shift", "text": "Earn 3 stars in one shift", "k": "three_star_shifts", "ge": 1, "coins": 80},
	{"id": "s_locked10", "g": 1, "s": 1, "name": "Locked on", "text": "10 locked finals in a row", "k": "locked_best", "ge": 10, "coins": 200, "cos": "livery:panda"},
	{"id": "s_fast_hangar", "g": 1, "s": 1, "name": "Quick turnaround", "text": "A full hangar in under 45 seconds", "k": "fast_hangar", "le": 45, "coins": 150, "cos": "livery:raven"},
	{"id": "s_net300", "g": 1, "s": 1, "name": "Big shift", "text": "Net 300 coins in one shift", "k": "net_best", "ge": 300, "coins": 150},
	{"id": "s_weather", "g": 1, "s": 1, "name": "Weather pilot", "text": "Earn a star in bad weather", "k": "weather_shifts", "ge": 1, "coins": 100},
	{"id": "s_noeng", "g": 1, "s": 1, "name": "Dead stick", "text": "Land a glider on No engines", "k": "noeng_landings", "ge": 1, "coins": 120},
	{"id": "s_noeng_intl", "g": 1, "s": 2, "name": "Silent at International", "text": "Land on No engines at International", "k": "noeng_intl", "ge": 1, "coins": 400, "cos": "windsock:midnight"},
	# ----- Airports -----
	{"id": "p_open3", "g": 2, "s": 0, "name": "Going places", "text": "Open three airports", "k": "airports_open", "ge": 3, "coins": 60},
	{"id": "p_open6", "g": 2, "s": 1, "name": "Network", "text": "Open all six airports", "k": "airports_open", "ge": 6, "coins": 150},
	{"id": "p_stars9", "g": 2, "s": 1, "name": "Nine stars", "text": "Earn 9 stars", "k": "stars", "ge": 9, "coins": 100},
	{"id": "p_stars18", "g": 2, "s": 2, "name": "Three stars everywhere", "text": "Earn all 18 stars", "k": "stars", "ge": 18, "coins": 500, "cos": "theme:dusk"},
	{"id": "p_imp_one", "g": 2, "s": 1, "name": "Fully equipped", "text": "Every improvement at one airport", "k": "imp_full_one", "ge": 1, "coins": 300, "cos": "hangar:plum"},
	{"id": "p_imp_all", "g": 2, "s": 2, "name": "Fully equipped, everywhere", "text": "Every improvement at all six airports", "k": "imp_full_all", "ge": 1, "coins": 800, "cos": "hangar:teal"},
	{"id": "p_tower5", "g": 2, "s": 2, "name": "Tower of power", "text": "Every Tower upgrade at level 5", "k": "tower_max", "ge": 1, "coins": 400},
	{"id": "p_rank5", "g": 2, "s": 1, "name": "Master of one", "text": "Reach mastery rank 5 at an airport", "k": "rank5", "ge": 1, "coins": 250, "cos": "theme:blossom"},
	{"id": "p_rank5_all", "g": 2, "s": 2, "name": "Master of all", "text": "Reach mastery rank 5 at every airport", "k": "rank5", "ge": 6, "coins": 800, "cos": "theme:lagoon"},
	# ----- Collection -----
	{"id": "c_livery3", "g": 3, "s": 0, "name": "Wardrobe", "text": "Own 4 liveries", "k": "liveries", "ge": 4, "coins": 60},
	{"id": "c_all_liveries", "g": 3, "s": 2, "name": "Every livery", "text": "Own every livery", "k": "liveries", "ge": 17, "coins": 400},
	{"id": "c_all_themes", "g": 3, "s": 1, "name": "Every skin", "text": "Own every airport skin", "k": "themes", "ge": 9, "coins": 300},
	{"id": "c_goals30", "g": 3, "s": 1, "name": "Goal getter", "text": "Finish 30 daily goals", "k": "goals_done", "ge": 30, "coins": 150},
	{"id": "c_streak7", "g": 3, "s": 1, "name": "A week of goals", "text": "A 7-day goals streak", "k": "streak_best", "ge": 7, "coins": 200},
	{"id": "c_bad", "g": 3, "s": 1, "name": "Bad day, good pilot", "text": "Earn a star on Bad Pilot Day", "k": "bad_stars", "ge": 1, "coins": 100},
	{"id": "c_chest5", "g": 3, "s": 1, "name": "Treasure", "text": "Open 5 bonus chests", "k": "chests", "ge": 5, "coins": 120},
]

static func count() -> int:
	return LIST.size()

static func def(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}

static func met(a: Dictionary, st: Dictionary) -> bool:
	var v := float(st.get(a["k"], 0))
	if a.has("ge"):
		return v >= float(a["ge"])
	return v <= float(a["le"]) and v > 0.0

## The achievements newly met by `st` (those not in `earned`).
static func check(st: Dictionary, earned: Dictionary) -> Array:
	var out: Array = []
	for a in LIST:
		if not earned.has(a["id"]) and met(a, st):
			out.append(a["id"])
	return out

## Progress toward one: {"value", "target", "frac"} (for the sheet's "37 / 100").
static func progress(a: Dictionary, st: Dictionary) -> Dictionary:
	if a.has("le"):
		return {"value": 0, "target": 1, "frac": 1.0 if met(a, st) else 0.0}
	var v := int(st.get(a["k"], 0))
	var t := int(a["ge"])
	return {"value": mini(v, t), "target": t, "frac": clampf(float(v) / float(t), 0.0, 1.0)}

static func in_group(g: int) -> Array:
	var out: Array = []
	for a in LIST:
		if int(a["g"]) == g:
			out.append(a)
	return out
