class_name Rhythm
extends RefCounted
## Reasons to come back, besides the shifts themselves (pure data and arithmetic, no Save / Tuning references):
##   offline hangar income   the planes parked in the hangars keep earning a trickle while the player is away, up to 8 hours, collected on return
##   the weekly event        one modifier a week for every airport (an airshow, a storm week, a fly-in ...) with a reward track earned by shifts
##   (the daily goals and the streak live in Goals / Save)

# ---------- offline hangar income ----------
const OFFLINE_CAP_HOURS := 8.0
const OFFLINE_MIN_SECONDS := 300.0            # shorter absences are not worth a screen
## Coins per parked plane per hour, as a share of the airport's average landing pay: a full hangar of ten planes away for 8 hours is about 4 shifts' worth.
const OFFLINE_RATE := 0.05

## {"total", "hours", "per": {airport: coins}} for `seconds` away with `capacity[a]` hangar places (0 where the airport is closed) and `mean_pay[a]` average pay.
static func offline_income(seconds: float, capacity: Array, mean_pay: Array) -> Dictionary:
	var hours := minf(maxf(seconds, 0.0) / 3600.0, OFFLINE_CAP_HOURS)
	var per := {}
	var total := 0
	for a in capacity.size():
		var c := int(capacity[a])
		if c <= 0:
			continue
		var coins := roundi(float(c) * float(mean_pay[a]) * OFFLINE_RATE * hours)
		if coins > 0:
			per[a] = coins
			total += coins
	return {"total": total, "hours": hours, "per": per}

# ---------- the weekly event ----------
## One a week, in this order, from the week number (days since 1970 / 7). "spawn": arrivals' spacing (< 1 busier), "pay": every landing's pay,
## "weather": how much more often weather comes (> 1 more), "xp": the XP of every shift.
const EVENTS := [
	{"id": "airshow", "name": "Airshow week", "text": "Busy skies: 15% more arrivals, landings pay 10% more", "spawn": 0.87, "pay": 1.10, "weather": 1.0, "xp": 1.0},
	{"id": "storm", "name": "Storm week", "text": "More weather, and landings pay 20% more", "spawn": 1.0, "pay": 1.20, "weather": 1.8, "xp": 1.0},
	{"id": "flyin", "name": "Fly-in week", "text": "Every shift earns 50% more XP", "spawn": 0.95, "pay": 1.0, "weather": 1.0, "xp": 1.5},
	{"id": "holiday", "name": "Holiday rush", "text": "Heavy traffic: 20% more arrivals, landings pay 15% more", "spawn": 0.83, "pay": 1.15, "weather": 1.0, "xp": 1.0},
	{"id": "calm", "name": "Calm skies week", "text": "A gentler week: landings pay 25% more, less weather", "spawn": 1.0, "pay": 1.25, "weather": 0.6, "xp": 1.0},
]

static func week_of(day: int) -> int:
	return day / 7

static func event_for_week(week: int) -> Dictionary:
	return EVENTS[posmod(week, EVENTS.size())]

## The reward track: every `points` reached gives a reward, in average-shift pays at the best open airport ("unit" coins) or XP at the airport played.
## A shift earns 1 point, and 1 more for each star (so 1 to 4).
const TRACK := [
	{"points": 6, "unit": 1.0, "text": "1 shift's pay"},
	{"points": 16, "unit": 2.0, "text": "2 shifts' pay"},
	{"points": 30, "unit": 3.0, "text": "3 shifts' pay"},
	{"points": 48, "unit": 5.0, "text": "5 shifts' pay"},
	{"points": 70, "unit": 8.0, "text": "8 shifts' pay"},
]

static func points_for_shift(stars: int) -> int:
	return 1 + clampi(stars, 0, 3)

static func reward_coins(track_i: int, unit: int) -> int:
	return maxi(roundi(float(unit) * float(TRACK[track_i]["unit"]) / 5.0) * 5, 5)
