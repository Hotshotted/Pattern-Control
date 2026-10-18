class_name Shift
extends RefCounted
## One play at an airport: the counters (landed, strikes), the three star goals and how far along they
## are. Pure bookkeeping, no engine objects, so it can be tested on its own. Created once; reset per shift.

enum Goal { PENDING, MET, FAILED }

var goals: Array = []
var landed := 0
var landed_by_type := PackedInt32Array()
var strikes := 0
var completed := false          # the shift ran its full length (needed for "no strikes")
var met := PackedInt32Array()   # per goal: 0 pending / 1 met / 2 failed

func _init() -> void:
	landed_by_type.resize(16)
	met.resize(3)

func reset(goal_list: Array) -> void:
	goals = goal_list
	landed = 0
	landed_by_type.fill(0)
	strikes = 0
	completed = false
	met.fill(0)

func on_landed(type: int) -> void:
	landed += 1
	landed_by_type[type] += 1
	_evaluate()

func on_strike() -> void:
	strikes += 1
	_evaluate()

func finish(full_length: bool) -> void:
	completed = full_length
	_evaluate()

## Progress and target of a goal ("land 25": 12 / 25). "No strikes": strikes so far / 0.
func progress(i: int) -> int:
	var g: Dictionary = goals[i]
	match g["kind"]:
		"land":
			return landed
		"land_type":
			return landed_by_type[g["type"]]
		_:
			return strikes

func target(i: int) -> int:
	var g: Dictionary = goals[i]
	return 0 if g["kind"] == "no_strikes" else g["n"]

func state(i: int) -> int:
	return met[i]

## Goals reached so far (the "no strikes" star only counts once the shift is complete).
func stars() -> int:
	var n := 0
	for i in goals.size():
		if met[i] == Goal.MET:
			n += 1
	return n

## Indices of goals that became met by the latest call (for the "star!" feedback): returns a bitmask.
var just_met := 0

func _evaluate() -> void:
	just_met = 0
	for i in goals.size():
		if met[i] != Goal.PENDING:
			continue
		var g: Dictionary = goals[i]
		if g["kind"] == "no_strikes":
			if strikes > 0:
				met[i] = Goal.FAILED
			elif completed:
				met[i] = Goal.MET
				just_met |= 1 << i
		elif progress(i) >= target(i):
			met[i] = Goal.MET
			just_met |= 1 << i

static func type_name(type: int) -> String:
	return ["glider", "helicopter", "small plane", "medium plane", "jet", "seaplane"][type] if type < 6 else "aircraft"

func goal_text(i: int) -> String:
	var g: Dictionary = goals[i]
	match g["kind"]:
		"land":
			return "Land %d aircraft" % g["n"]
		"land_type":
			return "Land %d %ss" % [g["n"], type_name(g["type"])]
		_:
			return "No strikes"
