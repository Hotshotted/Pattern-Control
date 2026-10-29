class_name Shift
extends RefCounted
## One timed shift at an airport: the coin balance (landings pay, fines deduct), the three star thresholds and
## how far along they are. The balance may go negative during a shift; the payout never falls below a share of the gross. Pure
## bookkeeping, no engine objects, so it can be tested on its own. Created once; reset per shift.

var thresholds := PackedInt32Array([0, 0, 0])   # star 1: landings to finish the shift with; stars 2 and 3: net coins
var landed := 0
var landed_by_type := PackedInt32Array()
var landed_vip := 0              # VIP flights landed with their bonus intact
var landed_emergency := 0
var landed_student := 0
var earned := 0                  # landing pay
var bonus := 0                   # quick-succession and special-aircraft bonuses
var fines := 0                   # total fines so far (a positive number)
var conflicts := 0
var diversions := 0
var crashes := 0
var biggest_fine := 0            # the largest single fine so far, for the results-screen "refund" ad (0 = nothing to refund)
var refunded := 0
var time_bonus := 0              # coins for clearing the sky before par
var early_seconds := 0
var overtime_penalty := 0        # coins lost to overtime (grows live after par)
var overtime_seconds := 0
var keep_fraction := 0.25        # the share of the gross (landing pay, bonuses, early bonus) that a completed shift always pays, whatever the fines
var just_stars := 0              # bitmask: stars reached by the latest call (for the "STAR!" feedback)

func _init() -> void:
	landed_by_type.resize(16)

func reset(star_thresholds: Array, keep: float = 0.25) -> void:
	keep_fraction = keep
	for i in 3:
		thresholds[i] = star_thresholds[i]
	landed = 0
	landed_by_type.fill(0)
	landed_vip = 0
	landed_emergency = 0
	landed_student = 0
	earned = 0
	bonus = 0
	fines = 0
	conflicts = 0
	diversions = 0
	crashes = 0
	biggest_fine = 0
	refunded = 0
	time_bonus = 0
	early_seconds = 0
	overtime_penalty = 0
	overtime_seconds = 0
	just_stars = 0

## The shift's coin total so far (negative after a bad fine).
func balance() -> int:
	return earned + bonus + time_bonus - fines - overtime_penalty

## Past par: whole seconds over, each costing `rate` coins (updated live, so the balance shows it).
func set_overtime(seconds: float, rate: int) -> void:
	overtime_seconds = maxi(floori(seconds), 0)
	overtime_penalty = overtime_seconds * rate

## The sky is clear at `t`: before par, every whole second early earns `rate` coins.
func set_finish(t: float, par: float, rate: int) -> void:
	early_seconds = maxi(floori(par - t), 0)
	time_bonus = early_seconds * rate

## Everything the shift earned before fines and overtime.
func gross() -> int:
	return earned + bonus + time_bonus

## The guaranteed part: a fixed share of the gross, paid no matter the fines or overtime.
func kept() -> int:
	return floori(gross() * keep_fraction)

## What actually gets paid out: the net after fines and overtime, but never less than the guaranteed share.
## Stars use balance() (the net), so fines and crashes still count against them.
func payout() -> int:
	return maxi(balance(), kept())

## The floor is what pays: the fines took the net below the guaranteed share ("Shift pay protected").
func is_protected() -> bool:
	return kept() > balance()

## Stars reached so far. Star 1 is for finishing the shift with enough landings (thresholds[0]); stars 2 and 3 are skill:
## the net coins after fines (thresholds[1], thresholds[2]). A star needs the ones before it.
func stars() -> int:
	var n := 0
	for i in 3:
		if not star_reached(i):
			break
		n += 1
	return n

func star_reached(i: int) -> bool:
	if i == 0:
		return landed >= thresholds[0]
	return star_reached(i - 1) and balance() >= thresholds[i]

func on_landed(type: int, base: int, extra: int, vip: bool = false, emergency: bool = false, student: bool = false) -> void:
	var before := stars()
	landed += 1
	landed_by_type[type] += 1
	if vip:
		landed_vip += 1
	if emergency:
		landed_emergency += 1
	if student:
		landed_student += 1
	earned += base
	bonus += extra
	_note_stars(before)

## A fine of `amount` coins. kind: "conflict", "diversion" or "crash".
func fine(amount: int, kind: String) -> void:
	fines += amount
	biggest_fine = maxi(biggest_fine, amount)
	match kind:
		"conflict":
			conflicts += 1
		"diversion":
			diversions += 1
		_:
			crashes += 1

## Give the biggest fine back (the rewarded ad on the results screen). Returns the coins refunded (0 if none).
func refund_biggest() -> int:
	var r := biggest_fine
	if r <= 0:
		return 0
	fines -= r
	refunded += r
	biggest_fine = 0
	return r

func _note_stars(before: int) -> void:
	just_stars = 0
	var now := stars()
	for i in 3:
		if i >= before and i < now:
			just_stars |= 1 << i

static func type_name(type: int) -> String:
	return ["glider", "helicopter", "small plane", "medium plane", "jet", "seaplane"][type] if type < 6 else "aircraft"
