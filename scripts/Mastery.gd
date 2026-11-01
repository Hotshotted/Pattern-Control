class_name Mastery
extends RefCounted
## Airport mastery: five ranks per airport, earned from the landings made there (every landing counts, whatever the mode). The thresholds
## are per airport: rank 3 comes about when an average player wins that airport's third star, and rank 5 takes about three times as many
## landings as that. Rank 1 to 5 pay coins (a multiple of an average shift's pay there); ranks 3 and 5 also give an airport-themed cosmetic
## (a livery at rank 3, a field detail at rank 5), and rank 5 puts a small gold plaque on that airport's tower.
## Pure data: no Save / Tuning references.

const MAX_RANK := 5
## Cumulative landings for rank 1..5 at each airport.
const THRESHOLDS := [
	[15, 65, 140, 265, 420],          # Grass Strip
	[40, 160, 350, 665, 1050],        # County
	[25, 100, 220, 420, 660],         # Regional
	[10, 30, 70, 135, 210],           # Mountain Field (a short shift: its stars come quickly)
	[35, 130, 290, 550, 870],         # Island
	[60, 220, 490, 930, 1470],        # International
]
const RANK_NAMES := ["Newcomer", "Regular", "Veteran", "Expert", "Master"]
## Coins at ranks 1..5, in average-shift pays at that airport (Goals.AVG_PAY).
const COIN_MULT := [1.0, 2.0, 3.0, 4.0, 6.0]
## What ranks 3 and 5 give at each airport: [rank 3, rank 5] as "kind:id".
const REWARDS := [
	["livery:bee", "windsock:meadow"],
	["livery:hare", "hangar:barley"],
	["livery:heron", "windsock:sky"],
	["livery:goat", "hangar:pine"],
	["livery:seal", "windsock:coral"],
	["livery:crane", "hangar:steel"],
]

static func rank(ap: int, landings: int) -> int:
	var t: Array = THRESHOLDS[clampi(ap, 0, THRESHOLDS.size() - 1)]
	var r := 0
	for i in t.size():
		if landings >= int(t[i]):
			r = i + 1
	return r

## How far along: {"rank", "into" (landings since this rank), "need" (landings from this rank to the next; 0 at the top), "frac" 0..1}.
static func progress(ap: int, landings: int) -> Dictionary:
	var t: Array = THRESHOLDS[clampi(ap, 0, THRESHOLDS.size() - 1)]
	var r := rank(ap, landings)
	if r >= MAX_RANK:
		return {"rank": r, "into": 0, "need": 0, "frac": 1.0}
	var lo := 0 if r == 0 else int(t[r - 1])
	var hi := int(t[r])
	return {"rank": r, "into": landings - lo, "need": hi - lo, "frac": clampf(float(landings - lo) / float(hi - lo), 0.0, 1.0)}

static func total_to_max() -> int:
	var n := 0
	for t in THRESHOLDS:
		n += int(t[MAX_RANK - 1])
	return n

static func coins_for(ap: int, r: int, avg_pay: int) -> int:
	return maxi(roundi(avg_pay * COIN_MULT[clampi(r, 1, MAX_RANK) - 1] / 5.0) * 5, 5)

## The cosmetic ("kind:id") that reaching rank `r` at airport `ap` gives, or "".
static func cosmetic_for(ap: int, r: int) -> String:
	if r == 3:
		return REWARDS[ap][0]
	if r == 5:
		return REWARDS[ap][1]
	return ""

static func rank_name(r: int) -> String:
	return "Unranked" if r <= 0 else RANK_NAMES[mini(r, MAX_RANK) - 1]
