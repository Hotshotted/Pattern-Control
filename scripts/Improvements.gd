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
	"hangar": {"name": "Hangar bay", "text": "More room, and a fee for each", "costs": [140, 280, 560]},
	"rwlights": {"name": "Runway lights", "text": "Fewer go-arounds in bad light", "costs": [105, 210, 420]},
	"applights": {"name": "Approach lights", "text": "Paths snap on from further", "costs": [105, 210, 420]},
	"fuel": {"name": "Fuel farm", "text": "Longer timers", "costs": [140, 280, 560]},
	"exit": {"name": "Extra exit", "text": "Short rollout, quick taxi", "costs": [175, 350, 700]},
}

## How much dearer an airport's improvements are than the first airport's. (Dearer, but the airport earns more per minute, so they pay back sooner.)
const AIRPORT_COST := [0.5, 0.7, 1.0, 1.4, 1.9, 2.6]

## What reaching a level adds, in one line ("+2 hangar spots"), for the Improve sheet's rows and their next-level preview.
const EFFECT := {
	"hangar": "+2 hangar spots",
	"rwlights": "20% fewer go-arounds in bad light",
	"applights": "Paths snap on from 30% further",
	"fuel": "+8% on every aircraft's timer",
	"exit": "12% shorter roll, 10% faster taxi",
}

static func max_level(_id: String) -> int:
	return MAX_LEVEL

## The one-line effect of reaching `level` (1-based).
static func effect_text(id: String, _level: int) -> String:
	return EFFECT[id]

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
