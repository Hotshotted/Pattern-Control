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
	[35, 150, 320, 610, 965],          # Grass Strip
	[90, 370, 805, 1530, 2415],        # County
	[55, 230, 505, 965, 1520],         # Regional
	[25, 70, 160, 310, 485],           # Mountain Field (a short shift: its stars come quickly)
	[80, 300, 665, 1265, 2000],         # Island
	[140, 505, 1125, 2140, 3380],        # International
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


## The pay bonus a rank gives at its airport (ranks 1..5): a landing there pays this much more.
const PAY_BONUS := [0.01, 0.02, 0.03, 0.04, 0.06]
## ...and rank 5 at an airport also adds this to the pay at every airport (a small global bonus, gold badge).
const GLOBAL_BONUS := 0.01

static func pay_bonus(r: int) -> float:
	return 0.0 if r <= 0 else PAY_BONUS[mini(r, MAX_RANK) - 1]

## What each rank gives at an airport, one line: the pay, the cosmetic or landmark, the badge.
static func reward_text(ap: int, r: int) -> String:
	var t := "Pay +%d%% here" % roundi(pay_bonus(r) * 100.0)
	if r == 3:
		t += ", a livery"
	elif r == 4:
		t += ", a pennant on the tower"
	elif r == 5:
		t += ", a gold plaque, a field detail and +%d%% pay at every airport" % roundi(GLOBAL_BONUS * 100.0)
	return t
