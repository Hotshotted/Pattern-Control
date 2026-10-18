class_name Upgrades
extends RefCounted
## The permanent airport upgrades bought with coins: ids, names, what they do and what they cost at each level.
## (Pure data, no Tuning / Save references. The effects are applied through Tuning's upgrade functions, and
## Airfield shows each upgrade on the airport.)

const MAX_LEVEL := 3
const IDS := ["radar", "approach", "tower", "comms", "holding", "turnoffs"]

const DATA := {
	"radar": {"name": "Radar", "costs": [250, 600, 1200], "text": "Wider view, earlier arrival warnings"},
	"approach": {"name": "Approach Control", "costs": [250, 600, 1200], "text": "Arrivals line up with active runways"},
	"tower": {"name": "Tower Staff", "costs": [200, 500, 1000], "text": "Slightly slower, thinner traffic"},
	"comms": {"name": "Better Comms", "costs": [150, 400, 900], "text": "Every aircraft timer lasts longer"},
	"holding": {"name": "Holding Fixes", "costs": [150, 400, 900], "text": "Holding: slower timers, tighter circles"},
	"turnoffs": {"name": "Fast Turnoffs", "costs": [150, 400, 900], "text": "Runways clear faster after landing"},
}

static func upgrade_name(id: String) -> String:
	return DATA[id]["name"]

static func description(id: String) -> String:
	return DATA[id]["text"]

## Price of going from `level` to `level + 1` (-1 at the top).
static func cost(id: String, level: int) -> int:
	return -1 if level >= MAX_LEVEL else DATA[id]["costs"][level]
