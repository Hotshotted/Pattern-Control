class_name Improvements
extends RefCounted
## The improvements of one airport: five of them at every airport, three levels each, bought on the airport's detail screen with
## coins. Unlike the Tower upgrades (which work everywhere) they only work at the airport they were bought for, and the airport
## wears them: Airfield draws each in that airport's own style. Pure data, no Tuning / Save references.
##   hangar     more hangar bays: room for more aircraft, and the ones that park in the new bays pay a hangar fee
##   rwlights   runway lights: fewer go-arounds in fog, storms, crosswinds and at dusk
##   applights  approach lights: a wider catch for the path snapping onto a final
##   fuel       fuel farm: arrivals start with longer timers
##   exit       extra exit: a shorter rollout and a faster taxi

const MAX_LEVEL := 3
const IDS := ["hangar", "rwlights", "applights", "fuel", "exit"]

## Prices of levels 1, 2 and 3 at the first airport; a later airport multiplies them (AIRPORT_COST).
const DATA := {
	"hangar": {"name": "Hangar bay", "text": "More room, and a fee for each", "costs": [200, 400, 800]},
	"rwlights": {"name": "Runway lights", "text": "Fewer go-arounds in bad light", "costs": [150, 300, 600]},
	"applights": {"name": "Approach lights", "text": "Paths snap on from further", "costs": [150, 300, 600]},
	"fuel": {"name": "Fuel farm", "text": "Longer timers", "costs": [200, 400, 800]},
	"exit": {"name": "Extra exit", "text": "Short rollout, quick taxi", "costs": [250, 500, 1000]},
}

## How much dearer an airport's improvements are than the first airport's. (Dearer, but the airport earns more per minute, so they pay back sooner.)
const AIRPORT_COST := [0.5, 0.7, 1.0, 1.4, 1.9, 2.6]

static func improvement_name(id: String) -> String:
	return DATA[id]["name"]

static func description(id: String) -> String:
	return DATA[id]["text"]

## Price of going from `level` to `level + 1` at `airport` (-1 at the top).
static func cost(airport: int, id: String, level: int) -> int:
	if level >= MAX_LEVEL:
		return -1
	return maxi(roundi(float(DATA[id]["costs"][level]) * float(AIRPORT_COST[clampi(airport, 0, AIRPORT_COST.size() - 1)]) / 5.0) * 5, 5)

## What every improvement of an airport costs in all.
static func total_cost(airport: int) -> int:
	var n := 0
	for id in IDS:
		for l in MAX_LEVEL:
			n += cost(airport, id, l)
	return n
