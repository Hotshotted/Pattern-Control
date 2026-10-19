class_name Shift
extends RefCounted
## One timed shift at an airport: the coin balance (landings pay, fines deduct), the three star thresholds and
## how far along they are. The balance may go negative during a shift; the payout floors at zero. Pure
## bookkeeping, no engine objects, so it can be tested on its own. Created once; reset per shift.

var thresholds := PackedInt32Array([0, 0, 0])   # coins needed for 1, 2 and 3 stars
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
var last_fine := 0               # the most recent fine, for the "refund" ad (0 = nothing to refund)
var refunded := 0
var just_stars := 0              # bitmask: stars reached by the latest call (for the "STAR!" feedback)

func _init() -> void:
	landed_by_type.resize(16)

func reset(star_thresholds: Array) -> void:
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
	last_fine = 0
	refunded = 0
	just_stars = 0

## The shift's coin total so far (negative after a bad fine).
func balance() -> int:
	return earned + bonus - fines

## What actually gets paid out: never below zero.
func payout() -> int:
	return maxi(balance(), 0)

## Stars reached by the current balance.
func stars() -> int:
	var b := balance()
	var n := 0
	for i in 3:
		if b >= thresholds[i]:
			n += 1
	return n

func star_reached(i: int) -> bool:
	return balance() >= thresholds[i]

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
	last_fine = amount
	match kind:
		"conflict":
			conflicts += 1
		"diversion":
			diversions += 1
		_:
			crashes += 1

## Give the last fine back (the rewarded ad). Returns the coins refunded (0 if none).
func refund_last() -> int:
	var r := last_fine
	if r <= 0:
		return 0
	fines -= r
	refunded += r
	last_fine = 0
	return r

func _note_stars(before: int) -> void:
	just_stars = 0
	for i in 3:
		if balance() >= thresholds[i] and before <= i:
			just_stars |= 1 << i

static func type_name(type: int) -> String:
	return ["glider", "helicopter", "small plane", "medium plane", "jet", "seaplane"][type] if type < 6 else "aircraft"
