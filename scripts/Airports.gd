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
				{"center": Vector2(-2.1, 0.6), "heading": 0.0, "length": 6.0, "width": 1.0, "color": ORANGE, "name": "ORANGE"},
				{"center": Vector2(2.1, 0.6), "heading": 0.0, "length": 6.0, "width": 1.0, "color": BLUE, "name": "BLUE"},
			],
			"tower": Vector2(0.0, 0.6),
			"windsock": Vector2(0.0, 4.4),
			## Wind: a smaller scale means wind shifts come more often.
			"wind_scale": 1.0,
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

## A runway has two ENDS you can land toward: end 0 lands along `heading` (approach from behind it), end 1 the
## opposite way. Which ends are usable depends on the wind (see Wind.gd).
static func end_heading_deg(i: int, e: int) -> float:
	return fposmod(rw_heading_deg(i) + 180.0 * e, 360.0)

static func end_dir(i: int, e: int) -> Vector2:
	var h := deg_to_rad(end_heading_deg(i, e))
	return Vector2(sin(h), -cos(h))

## The approach end of end `e`: where a path must finish to land there (planes land away from it).
static func end_threshold(i: int, e: int) -> Vector2:
	return rw_center(i) - end_dir(i, e) * rw_length(i) * 0.5

## ...and where the landing roll finishes (the far end of the runway).
static func end_far(i: int, e: int) -> Vector2:
	return rw_center(i) + end_dir(i, e) * rw_length(i) * 0.5

static func tower_pos() -> Vector2:
	return def()["tower"]

static func windsock_pos() -> Vector2:
	return def()["windsock"]

static func wind_scale() -> float:
	return def().get("wind_scale", 1.0)

## Smallest angle between two compass directions, degrees (0..180).
static func angle_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))

## Can a plane land on every runway of this airport with the wind from `deg`? (Each runway needs an end within `tol`.)
static func wind_ok(deg: float, tol: float) -> bool:
	for i in rw_count():
		var any := false
		for e in 2:
			if angle_diff(end_heading_deg(i, e), deg) <= tol:
				any = true
		if not any:
			return false
	return true

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


static func goals(i: int = -1) -> Array:
	return def(i)["goals"]

static func mix(i: int = -1) -> Dictionary:
	return def(i)["mix"]
