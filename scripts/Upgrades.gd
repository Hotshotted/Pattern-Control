class_name Upgrades
extends RefCounted
## The permanent airport upgrades bought with coins: ids, names, what they do and what they cost at each level.
## (Pure data, no Tuning / Save references. The effects are applied through Tuning's upgrade functions, and
## Airfield shows each upgrade on the airport.)

const MAX_LEVEL := 3
const IDS := ["radar", "approach", "tower", "comms", "holding", "turnoffs"]

const DATA := {
	"radar": {"name": "Radar", "costs": [160, 360, 700], "text": "See further"},
	"approach": {"name": "Approach Control", "costs": [200, 450, 800], "text": "Lined-up arrivals"},
	"tower": {"name": "Tower Staff", "costs": [120, 280, 550], "text": "Calmer traffic"},
	"comms": {"name": "Better Comms", "costs": [50, 140, 320], "text": "Longer timers"},
	"holding": {"name": "Holding Fixes", "costs": [70, 180, 380], "text": "Holds cost less time"},
	"turnoffs": {"name": "Fast Turnoffs", "costs": [90, 220, 450], "text": "Runways clear faster"},
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
