class_name Airports
extends RefCounted
## The airports: static layout data and the lookups the game uses (runway geometry, star thresholds, traffic mix).
## `current` is the airport being played. Runway headings are degrees, 0 = up the screen; a runway lands
## planes toward its heading, and its approach end (threshold) is the end they come from.
## (No Tuning references: the smoke test can read this class while it compiles.)

const ORANGE := Color("ff8a3d")
const BLUE := Color("3d8bff")
const PINK := Color(1.0, 0.45, 0.75)
const PAD_COLOR := Color("a06bff")      # helipads
const LANE_COLOR := Color("35c98a")     # seaplane lanes
const COUNT := 6

static var current := 0
static var _defs: Array[Dictionary] = []
static var _cross: Array = []               # per airport: Array of Array[bool] (runway i crosses runway j)

static func _rw(center: Vector2, heading: float, length: float, color: Color, name: String, width: float = 1.0) -> Dictionary:
	return {"center": center, "heading": heading, "length": length, "width": width, "color": color, "name": name}

static func _build() -> void:
	if not _defs.is_empty():
		return
	var M := Aircraft.Type.MEDIUM
	var S := Aircraft.Type.SMALL
	var J := Aircraft.Type.JET
	var G := Aircraft.Type.GLIDER
	var H := Aircraft.Type.HELI
	var P := Aircraft.Type.SEAPLANE
	_defs = [
		{   # 1: one runway, usable in both directions
			"name": "Grass Strip", "tag": "One runway, both directions",
			"runways": [_rw(Vector2(0.0, 0.8), 0.0, 7.0, ORANGE, "ORANGE", 1.1)],
			"pads": [], "lanes": [], "hazards": [], "decor": [],
			"tower": Vector2(2.6, -1.2), "windsock": Vector2(-2.6, 2.6),
			"ground": Color("84c26b"),
			"mix": {S: 0.7, G: 0.3},
			"unlock_stars": 0, "weather": [],
		},
		{   # 2: two crossing runways: simultaneous landings conflict
			"name": "County", "tag": "Crossing runways",
			"runways": [_rw(Vector2(0.0, 0.2), 0.0, 6.5, ORANGE, "ORANGE"), _rw(Vector2(0.0, 0.2), 55.0, 5.4, BLUE, "BLUE")],
			"pads": [], "lanes": [], "hazards": [],
			"decor": [{"shape": "box", "pos": Vector2(-3.3, -3.4), "size": Vector2(2.6, 3.4), "color": Color("d9c46a"), "y": 0.012},
					{"shape": "box", "pos": Vector2(3.4, 4.0), "size": Vector2(2.4, 3.2), "color": Color("a8d070"), "y": 0.012},
					{"shape": "box", "pos": Vector2(-3.5, 5.2), "size": Vector2(2.2, 2.4), "color": Color("e3cf7a"), "y": 0.012}],
			"tower": Vector2(3.2, -3.6), "windsock": Vector2(-3.3, 3.7),
			"ground": Color("8fc766"),
			"mix": {S: 0.35, M: 0.45, G: 0.2},
			"unlock_stars": 2, "weather": ["crosswind"],
		},
		{   # 3: parallel runways and a helipad
			"name": "Regional", "tag": "Parallel runways + helipad",
			"runways": [_rw(Vector2(-2.6, 0.3), 0.0, 7.8, ORANGE, "ORANGE"), _rw(Vector2(0.4, 0.3), 0.0, 7.8, BLUE, "BLUE")],
			"pads": [{"center": Vector2(3.5, 3.4), "radius": 0.85, "color": PAD_COLOR}], "lanes": [], "hazards": [],
			"decor": [{"shape": "disc", "pos": Vector2(3.5, 3.4), "r": 1.45, "color": Color("d3d9e2"), "sides": 16, "y": 0.012},
					{"shape": "box", "pos": Vector2(3.3, -2.4), "size": Vector2(2.4, 2.6), "color": Color("d3d9e2"), "y": 0.012}],
			"tower": Vector2(3.4, -2.4), "windsock": Vector2(2.2, 0.8),
			"ground": Color("78bb6c"),
			"mix": {S: 0.25, M: 0.35, J: 0.2, H: 0.2},
			"unlock_stars": 5, "weather": ["crosswind", "fog"],
		},
		{   # 4: terrain no-fly zones
			"name": "Mountain Field", "tag": "Keep clear of the mountains",
			"runways": [_rw(Vector2(-1.9, 0.6), 8.0, 6.2, ORANGE, "ORANGE"), _rw(Vector2(1.7, 0.6), 8.0, 6.2, BLUE, "BLUE")],
			"pads": [], "lanes": [],
			"hazards": [
				{"center": Vector2(-4.2, -6.0), "radius": 1.2}, {"center": Vector2(4.3, -5.6), "radius": 1.3},
				{"center": Vector2(0.55, -6.4), "radius": 0.8}, {"center": Vector2(-4.2, 5.6), "radius": 1.2},
				{"center": Vector2(4.3, 5.4), "radius": 1.2},
			],
			"decor": [{"shape": "disc", "pos": Vector2(-4.2, -6.0), "r": 1.9, "color": Color("a7a392"), "sides": 9, "y": 0.012},
					{"shape": "disc", "pos": Vector2(4.3, -5.6), "r": 2.0, "color": Color("a7a392"), "sides": 9, "y": 0.012},
					{"shape": "disc", "pos": Vector2(-4.2, 5.6), "r": 1.9, "color": Color("a7a392"), "sides": 9, "y": 0.012},
					{"shape": "disc", "pos": Vector2(4.3, 5.4), "r": 1.9, "color": Color("a7a392"), "sides": 9, "y": 0.012}],
			"tower": Vector2(0.0, 3.2), "windsock": Vector2(0.0, -1.2),
			"ground": Color("86b673"),
			"mix": {S: 0.3, M: 0.35, G: 0.35},
			"unlock_stars": 8, "weather": ["storm", "fog"],
		},
		{   # 5: an island in the water, with a seaplane lane
			"name": "Island", "tag": "Water landing lane",
			"runways": [_rw(Vector2(-1.6, 0.3), 0.0, 7.4, ORANGE, "ORANGE"), _rw(Vector2(1.6, 0.3), 0.0, 7.4, BLUE, "BLUE")],
			"pads": [],
			"lanes": [{"center": Vector2(0.2, 5.3), "heading": 90.0, "length": 6.0, "width": 1.0, "color": LANE_COLOR}],
			"hazards": [],
			"decor": [{"shape": "disc", "pos": Vector2(0.0, 0.3), "r": 4.4, "color": Color("84c26b"), "sides": 12, "y": 0.03},
					{"shape": "disc", "pos": Vector2(0.0, 0.3), "r": 4.9, "color": Color("f1dfa0"), "sides": 12, "y": 0.01}],
			"tower": Vector2(0.0, 0.3), "windsock": Vector2(0.0, -3.0),
			"ground": Color("3fa2d6"), "water": true,
			"mix": {S: 0.2, M: 0.25, J: 0.3, P: 0.25},
			"unlock_stars": 11, "weather": ["storm", "crosswind", "fog"],
		},
		{   # 6: long runways and multiples of everything
			"name": "International", "tag": "Everything, all at once",
			"runways": [_rw(Vector2(-3.4, 0.0), 0.0, 8.4, ORANGE, "ORANGE"), _rw(Vector2(-1.1, 0.0), 0.0, 8.4, BLUE, "BLUE"), _rw(Vector2(1.2, 0.0), 0.0, 8.4, PINK, "PINK")],
			"pads": [{"center": Vector2(3.9, -4.7), "radius": 0.7, "color": PAD_COLOR}, {"center": Vector2(3.9, -3.1), "radius": 0.7, "color": PAD_COLOR}],
			"lanes": [{"center": Vector2(3.9, 1.8), "heading": 0.0, "length": 4.0, "width": 0.9, "color": LANE_COLOR},
					{"center": Vector2(-0.6, 5.6), "heading": 90.0, "length": 6.4, "width": 0.9, "color": LANE_COLOR}],
			"hazards": [],
			"decor": [{"shape": "box", "pos": Vector2(3.2, -3.9), "size": Vector2(2.7, 4.6), "color": Color("c9cfda"), "y": 0.012},
					{"shape": "box", "pos": Vector2(3.9, 1.8), "size": Vector2(1.5, 4.8), "color": Color("3fa2d6"), "y": 0.02},
					{"shape": "box", "pos": Vector2(-0.4, 5.6), "size": Vector2(7.6, 1.8), "color": Color("3fa2d6"), "y": 0.02}],
			"tower": Vector2(2.6, -2.6), "windsock": Vector2(2.6, 3.0),
			"ground": Color("7fbf74"),
			"mix": {S: 0.1, M: 0.25, J: 0.3, H: 0.15, P: 0.2},
			"unlock_stars": 14, "weather": ["storm", "crosswind", "fog"],
		},
	]
	for d in _defs:
		var n: int = d["runways"].size()
		var m: Array = []
		for i in n:
			var row: Array = []
			for j in n:
				row.append(i != j and _segments_cross(d["runways"][i], d["runways"][j]))
			m.append(row)
		_cross.append(m)

static func _ends(r: Dictionary) -> Array[Vector2]:
	var h := deg_to_rad(r["heading"])
	var dir := Vector2(sin(h), -cos(h))
	return [r["center"] - dir * r["length"] * 0.5, r["center"] + dir * r["length"] * 0.5]

static func _segments_cross(a: Dictionary, b: Dictionary) -> bool:
	var ea := _ends(a)
	var eb := _ends(b)
	return Geometry2D.segment_intersects_segment(ea[0], ea[1], eb[0], eb[1]) != null

static func def(i: int = -1) -> Dictionary:
	_build()
	return _defs[current if i < 0 else i]

static func tag(i: int = -1) -> String:
	return def(i)["tag"]

## Which weather events can happen here, and how far apart they come (a smaller scale = more often).
static func weather_kinds() -> Array:
	return def().get("weather", [])

## The middle of the airfield (fog hides aircraft beyond a radius from here).
static func field_center() -> Vector2:
	var c := Vector2.ZERO
	var n := rw_count()
	for i in n:
		c += rw_center(i)
	return c / maxf(n, 1.0)

static func unlock_stars(i: int) -> int:
	return def(i)["unlock_stars"]

## Is airport `i` open, with `total_stars` stars in the save?
static func unlocked(i: int, total_stars: int) -> bool:
	return total_stars >= unlock_stars(i)

static func pads() -> Array:
	return def()["pads"]

static func lanes() -> Array:
	return def()["lanes"]

static func hazards() -> Array:
	return def()["hazards"]

static func decor() -> Array:
	return def()["decor"]

static func ground_color() -> Color:
	return def()["ground"]

## Do runways i and j of the current airport cross? (A simultaneous landing on both is a conflict.)
static func runways_cross(i: int, j: int) -> bool:
	_build()
	return _cross[current][i][j]

## Jets need a long runway.
static func is_long(i: int) -> bool:
	return rw_length(i) >= 7.4

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


# ---------- Landing places: runways, helipads and water lanes ----------

static func land_count(kind: int) -> int:
	match kind:
		Aircraft.Kind.RUNWAY:
			return rw_count()
		Aircraft.Kind.PAD:
			return pads().size()
		_:
			return lanes().size()

## Ends you can land toward: two for a runway or lane, one for a pad.
static func land_ends(kind: int) -> int:
	return 1 if kind == Aircraft.Kind.PAD else 2

static func _lane_dir(i: int, e: int) -> Vector2:
	var h := deg_to_rad(fposmod(lanes()[i]["heading"] + 180.0 * e, 360.0))
	return Vector2(sin(h), -cos(h))

## Where a path must finish to land on end `e` of this place (a pad: its centre).
static func land_threshold(kind: int, i: int, e: int) -> Vector2:
	match kind:
		Aircraft.Kind.RUNWAY:
			return end_threshold(i, e)
		Aircraft.Kind.PAD:
			return pads()[i]["center"]
		_:
			return lanes()[i]["center"] - _lane_dir(i, e) * lanes()[i]["length"] * 0.5

## ...and where the landing roll finishes.
static func land_far(kind: int, i: int, e: int) -> Vector2:
	match kind:
		Aircraft.Kind.RUNWAY:
			return end_far(i, e)
		Aircraft.Kind.PAD:
			return pads()[i]["center"]
		_:
			return lanes()[i]["center"] + _lane_dir(i, e) * lanes()[i]["length"] * 0.5

static func land_heading_deg(kind: int, i: int, e: int) -> float:
	match kind:
		Aircraft.Kind.RUNWAY:
			return end_heading_deg(i, e)
		Aircraft.Kind.PAD:
			return 0.0
		_:
			return fposmod(lanes()[i]["heading"] + 180.0 * e, 360.0)

static func land_color(kind: int, i: int) -> Color:
	match kind:
		Aircraft.Kind.RUNWAY:
			return rw_color(i) if i < rw_count() else ORANGE
		Aircraft.Kind.PAD:
			return pads()[i]["color"] if i < pads().size() else PAD_COLOR
		_:
			return lanes()[i]["color"] if i < lanes().size() else LANE_COLOR

## The kind of place a type lands on.
static func kind_for(type: int) -> int:
	if type == Aircraft.Type.HELI:
		return Aircraft.Kind.PAD
	if type == Aircraft.Type.SEAPLANE:
		return Aircraft.Kind.LANE
	return Aircraft.Kind.RUNWAY

## Can this type use runway `i`? (Jets need a long one.)
static func suitable_runway(type: int, i: int) -> bool:
	return type != Aircraft.Type.JET or is_long(i)

static func mix(i: int = -1) -> Dictionary:
	return def(i)["mix"]
