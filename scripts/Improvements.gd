class_name Improvements
extends RefCounted
## The improvements of one airport: five of them at every airport, eight to ten levels deep, bought on the airport's Improve sheet with
## coins. Unlike the Tower upgrades (which work everywhere) they only work at the airport they were bought for, and the airport wears them:
## Airfield draws each level in that airport's own style. Each level costs about 1.5 times the one before, and the airport's level gates how deep
## you can go (Progression.imp_gate: improvement level n needs airport level 2n - 1). Pure data, no Tuning / Save references.
##   hangar     more hangar bays: room for more aircraft, and the ones that park in the new bays pay a hangar fee   (10 levels)
##   rwlights   runway lights: fewer go-arounds in fog, storms, crosswinds and at dusk                             (8 levels)
##   applights  approach lights: a wider catch for the path snapping onto a final                                   (8 levels)
##   fuel       fuel farm: arrivals start with longer timers                                                        (8 levels)
##   exit       extra exit: a shorter rollout and a faster taxi                                                     (8 levels)

const MAX_LEVEL := 10                    # the deepest any improvement goes
const IDS := ["hangar", "rwlights", "applights", "fuel", "exit"]
const GROWTH := 1.5                      # the price of a level over the one before, for levels 2 to 5...
const GROWTH_LATE := 1.3                 # ...and after level 5, so the deep levels stay in reach

const DATA := {
	"hangar": {"name": "Hangar bay", "levels": 10, "mult": 1.0, "per": "+1 hangar spot"},
	"rwlights": {"name": "Runway lights", "levels": 8, "mult": 2.9, "per": "fewer go-arounds in bad light"},
	"applights": {"name": "Approach lights", "levels": 8, "mult": 3.1, "per": "paths snap on from further"},
	"fuel": {"name": "Fuel farm", "levels": 8, "mult": 3.9, "per": "longer timers"},
	"exit": {"name": "Extra exit", "levels": 8, "mult": 5.2, "per": "shorter rollout, quicker taxi"},
}

## What each level adds, as the game applies it (Tuning.imp_*): the totals at the top level are about 1.25 times what three levels were worth
## before this was deepened (hangar 10 spots, go-arounds -75% in bad light, snap radius +112%, timers +30%, rollout -45% and taxi +37%).
const PER_LEVEL := {"hangar": 1.0, "rwlights": 0.094, "applights": 0.14, "fuel": 0.0375, "exit_roll": 0.056, "exit_taxi": 0.047}

## The price of level 1 at each airport (a later airport pays more per shift, so its improvements pay back as fast): hangar level 1 is the first
## thing to buy, priced so the average player has it after the first shift (see docs/content_audit.md).
const L1_PRICE := [44, 74, 83, 92, 108, 124]

static func improvement_name(id: String) -> String:
	return DATA[id]["name"]

static func max_level(id: String) -> int:
	return int(DATA[id]["levels"])

## The one-line effect of reaching `level` (1-based): what it adds, and the total then.
static func effect_text(id: String, level: int) -> String:
	var l := clampi(level, 1, max_level(id))
	match id:
		"hangar":
			return "+1 hangar spot (%d in all)" % l
		"rwlights":
			return "%d%% fewer go-arounds in bad light (%d%% in all)" % [roundi(float(PER_LEVEL["rwlights"]) * 100.0), roundi(float(PER_LEVEL["rwlights"]) * 100.0 * l)]
		"applights":
			return "Paths snap on from %d%% further (+%d%% in all)" % [roundi(float(PER_LEVEL["applights"]) * 100.0), roundi(float(PER_LEVEL["applights"]) * 100.0 * l)]
		"fuel":
			return "Timers +%.1f%% (+%d%% in all)" % [float(PER_LEVEL["fuel"]) * 100.0, roundi(float(PER_LEVEL["fuel"]) * 100.0 * l)]
		"exit":
			return "Roll -%d%%, taxi +%d%% (-%d%% / +%d%% in all)" % [roundi(float(PER_LEVEL["exit_roll"]) * 100.0), roundi(float(PER_LEVEL["exit_taxi"]) * 100.0), roundi(float(PER_LEVEL["exit_roll"]) * 100.0 * l), roundi(float(PER_LEVEL["exit_taxi"]) * 100.0 * l)]
	return ""

## A short effect line for a row ("+1 hangar spot"): the same without the running total.
static func short_effect(id: String, level: int) -> String:
	var t := effect_text(id, level)
	var k := t.find(" (")
	return t if k < 0 else t.substr(0, k)

static func description(id: String) -> String:
	return DATA[id]["per"]

## Price of going from `level` to `level + 1` at `airport` (-1 at the top): the airport's level-1 price, the improvement's own factor, 1.5 times more each level.
static func cost(airport: int, id: String, level: int) -> int:
	if level >= max_level(id):
		return -1
	var base := float(L1_PRICE[clampi(airport, 0, L1_PRICE.size() - 1)]) * float(DATA[id]["mult"])
	return maxi(roundi(base * level_factor(level) / 5.0) * 5, 5)

## The price of level `level` + 1 over the price of level 1: x1.5 a level up to level 5, x1.3 a level after.
static func level_factor(level: int) -> float:
	return pow(GROWTH, float(mini(level, 4))) * pow(GROWTH_LATE, float(maxi(level - 4, 0)))

## What every improvement of an airport costs in all.
static func total_cost(airport: int) -> int:
	var n := 0
	for id in IDS:
		for l in max_level(id):
			n += cost(airport, id, l)
	return n

## Levels in all (the most any airport can have).
static func total_levels() -> int:
	var n := 0
	for id in IDS:
		n += max_level(id)
	return n
