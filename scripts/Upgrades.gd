class_name Upgrades
extends RefCounted
## The permanent airport upgrades bought with coins: ids, names, what they do and what they cost at each level.
## (Pure data, no Tuning / Save references. The effects are applied through Tuning's upgrade functions, and
## Airfield shows each upgrade on the airport.)

const MAX_LEVEL := 5
const IDS := ["radar", "approach", "tower", "comms", "holding", "turnoffs"]

## The Tower: six upgrades that work at every airport, five levels each. Levels 1 to 3 are the early game; levels 4 and 5 are worth having
## but cost a lot more (and add a little less than the one before).
const DATA := {
	"radar": {"name": "Radar", "costs": [160, 360, 700, 1700, 3400], "text": "See further"},
	"approach": {"name": "Approach Control", "costs": [200, 450, 800, 1900, 3850], "text": "Lined-up arrivals"},
	"tower": {"name": "Tower Staff", "costs": [120, 280, 550, 1300, 2650], "text": "Calmer traffic"},
	"comms": {"name": "Better Comms", "costs": [50, 140, 320, 770, 1540], "text": "Longer timers"},
	"holding": {"name": "Holding Fixes", "costs": [70, 180, 380, 900, 1800], "text": "Holds cost less time"},
	"turnoffs": {"name": "Fast Turnoffs", "costs": [90, 220, 450, 1100, 2150], "text": "Runways clear faster"},
}

static func upgrade_name(id: String) -> String:
	return DATA[id]["name"]

## The icon drawn on the upgrade's card (the HUD has one glyph per upgrade, named after it).
static func glyph(id: String) -> String:
	return id

static func description(id: String) -> String:
	return DATA[id]["text"]

## Price of going from `level` to `level + 1` (-1 at the top).
static func cost(id: String, level: int) -> int:
	return -1 if level >= MAX_LEVEL else DATA[id]["costs"][level]
