class_name Airports
extends RefCounted
## The airports: static layout data and the lookups the game uses (runway geometry, goals, traffic mix).
## `current` is the airport being played. Runway headings are degrees, 0 = up the screen; a runway lands
## planes toward its heading, and its approach end (threshold) is the end they come from.
## (No Tuning references: the smoke test can read this class while it compiles.)

const ORANGE := Color(1.0, 0.56, 0.12)
const BLUE := Color(0.2, 0.66, 1.0)
const COUNT := 1

static var current := 0
static var _defs: Array[Dictionary] = []

static func _build() -> void:
	if not _defs.is_empty():
		return
	_defs = [
		{
			"name": "Home Field",
			"runways": [
				{"center": Vector2(-2.1, 1.4), "heading": 6.0, "length": 6.0, "width": 1.0, "color": ORANGE, "name": "ORANGE"},
				{"center": Vector2(2.1, -1.4), "heading": 186.0, "length": 6.0, "width": 1.0, "color": BLUE, "name": "BLUE"},
			],
			## What the aircraft mix is: Aircraft.Type -> weight.
			"mix": {Aircraft.Type.SMALL: 0.4, Aircraft.Type.MEDIUM: 0.4, Aircraft.Type.JET: 0.2},
			## Three star goals. kind: "land" (n aircraft), "land_type" (n of a type), "no_strikes" (finish the shift with none).
			"goals": [
				{"kind": "land", "n": 25},
				{"kind": "land_type", "type": Aircraft.Type.JET, "n": 4},
				{"kind": "no_strikes"},
			],
		},
	]

static func def(i: int = -1) -> Dictionary:
	_build()
	return _defs[current if i < 0 else i]

static func airport_name(i: int = -1) -> String:
	return def(i)["name"]

static func rw_count() -> int:
	return def()["runways"].size()

static func rw(i: int) -> Dictionary:
	return def()["runways"][i]

static func rw_color(i: int) -> Color:
	return rw(i)["color"]

static func rw_name(i: int) -> String:
	return rw(i)["name"]

static func rw_center(i: int) -> Vector2:
	return rw(i)["center"]

static func rw_length(i: int) -> float:
	return rw(i)["length"]

static func rw_width(i: int) -> float:
	return rw(i)["width"]

static func rw_heading_deg(i: int) -> float:
	return rw(i)["heading"]

static func rw_dir(i: int) -> Vector2:
	var h := deg_to_rad(rw_heading_deg(i))
	return Vector2(sin(h), -cos(h))

## The approach end: where a path must finish to land a plane here.
static func rw_threshold(i: int) -> Vector2:
	return rw_center(i) - rw_dir(i) * rw_length(i) * 0.5

static func rw_end(i: int) -> Vector2:
	return rw_center(i) + rw_dir(i) * rw_length(i) * 0.5

static func goals(i: int = -1) -> Array:
	return def(i)["goals"]

static func mix(i: int = -1) -> Dictionary:
	return def(i)["mix"]
