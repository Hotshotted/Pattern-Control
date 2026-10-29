class_name Airports
extends RefCounted
## The airports: static layout data and the lookups the game uses (runway geometry, star thresholds, traffic mix).
## `current` is the airport being played. Runway headings are degrees, 0 = up the screen; a runway lands
## planes toward its heading, and its approach end (threshold) is the end they come from.
## (No Tuning references: the smoke test can read this class while it compiles.)

const ORANGE := Color("f0803c")
const BLUE := Color("4c8fd6")
const PINK := Color(1.0, 0.45, 0.75)
const PAD_COLOR := Color("8e6bbe")      # helipads
const LANE_COLOR := Color("2ba3a6")     # seaplane lanes
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
			"tower": Vector2(2.6, -1.2), "windsock": Vector2(-2.6, 2.6), "apron": {"center": Vector2(3.36, -0.6), "s": 0.9},
			"ground": Color("b9dc72"),
			"mix": {S: 0.85, G: 0.15},
			# The opener stays the easy one: few gliders, with more time, a lenient approach and a better fare than elsewhere.
			"glider_timer": 0.75, "glider_go_around": 0.1, "glider_pay": 1.4,
			"unlock_stars": 0, "weather": [],
		},
		{   # 2: two crossing runways (aircraft rolling out on them never collide: only the air has conflicts)
			"name": "County", "tag": "Crossing runways",
			"runways": [_rw(Vector2(0.0, 0.2), 0.0, 6.5, ORANGE, "ORANGE"), _rw(Vector2(0.0, 0.2), 55.0, 5.4, BLUE, "BLUE")],
			"pads": [], "lanes": [], "hazards": [],
			"decor": [{"shape": "box", "pos": Vector2(-3.3, -3.4), "size": Vector2(2.6, 3.4), "color": Color("d9c46a"), "y": 0.012},
					{"shape": "box", "pos": Vector2(3.5, -4.6), "size": Vector2(2.4, 3.0), "color": Color("a8d070"), "y": 0.012},
					{"shape": "box", "pos": Vector2(-3.5, 5.2), "size": Vector2(2.2, 2.4), "color": Color("e3cf7a"), "y": 0.012}],
			"tower": Vector2(3.2, -3.6), "windsock": Vector2(-2.2, 4.6), "apron": {"center": Vector2(3.44, 1.62), "s": 0.85},
			"ground": Color("c0dc6e"),
			"mix": {S: 0.35, M: 0.45, G: 0.2},
			"unlock_stars": 2, "weather": ["crosswind"],
		},
		{   # 3: parallel runways and a helipad
			"name": "Regional", "tag": "Parallel runways + helipad",
			"runways": [_rw(Vector2(-2.6, 0.3), 0.0, 7.8, ORANGE, "ORANGE"), _rw(Vector2(0.4, 0.3), 0.0, 7.8, BLUE, "BLUE")],
			"pads": [{"center": Vector2(3.5, 5.0), "radius": 0.85, "color": PAD_COLOR}], "lanes": [], "hazards": [],
			"decor": [{"shape": "disc", "pos": Vector2(3.5, 3.4), "r": 1.45, "color": Color("d3d9e2"), "sides": 16, "y": 0.012}],
			"tower": Vector2(3.4, -2.4), "windsock": Vector2(2.5, 2.3), "apron": {"center": Vector2(3.55, -1.6), "s": 1.0},
			"ground": Color("b2db78"),
			"mix": {S: 0.25, M: 0.35, J: 0.2, H: 0.2},
			"unlock_stars": 4, "weather": ["crosswind", "fog"],
		},
		{   # 4: terrain no-fly zones
			"style": "alpine", "name": "Mountain Field", "tag": "Keep clear of the mountains",
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
			"tower": Vector2(0.0, 3.2), "windsock": Vector2(-3.7, -1.0), "apron": {"center": Vector2(4.09, 1.9), "s": 0.55},
			"ground": Color("b0cf86"),
			"mix": {S: 0.3, M: 0.35, G: 0.35},
			"unlock_stars": 7, "weather": ["storm", "fog"],
		},
		{   # 5: an island in the water, with a seaplane lane
			"style": "coastal", "name": "Island", "tag": "Water landing lane",
			"runways": [_rw(Vector2(-1.6, 0.3), 0.0, 7.4, ORANGE, "ORANGE"), _rw(Vector2(1.6, 0.3), 0.0, 7.4, BLUE, "BLUE")],
			"pads": [],
			"lanes": [{"center": Vector2(0.2, 5.3), "heading": 90.0, "length": 6.0, "width": 1.0, "color": LANE_COLOR}],
			"hazards": [],
			"decor": [{"shape": "disc", "pos": Vector2(0.5, 0.3), "r": 4.6, "color": Color("84c26b"), "sides": 12, "y": 0.012},
					{"shape": "disc", "pos": Vector2(0.5, 0.3), "r": 4.95, "color": Color("f1dfa0"), "sides": 12, "y": 0.006}],
			"tower": Vector2(0.0, 0.3), "windsock": Vector2(-3.4, -1.6), "apron": {"center": Vector2(4.14, -1.0), "s": 0.6},
			"ground": Color("5db8e0"), "water": true,
			"mix": {S: 0.2, M: 0.25, J: 0.3, P: 0.25},
			"unlock_stars": 10, "weather": ["storm", "crosswind", "fog"],
		},
		{   # 6: long runways and multiples of everything
			"name": "International", "tag": "Everything, all at once",
			"runways": [_rw(Vector2(-3.6, 0.0), 0.0, 8.4, ORANGE, "ORANGE"), _rw(Vector2(-1.3, 0.0), 0.0, 8.4, BLUE, "BLUE"), _rw(Vector2(1.0, 0.0), 0.0, 8.4, PINK, "PINK")],
			"pads": [{"center": Vector2(4.2, 4.5), "radius": 0.7, "color": PAD_COLOR}, {"center": Vector2(4.2, 6.0), "radius": 0.7, "color": PAD_COLOR}],
			"lanes": [{"center": Vector2(4.2, -3.9), "heading": 0.0, "length": 2.6, "width": 0.9, "color": LANE_COLOR},
					{"center": Vector2(-1.2, 5.6), "heading": 90.0, "length": 6.0, "width": 0.9, "color": LANE_COLOR}],
			"hazards": [],
			"decor": [{"shape": "box", "pos": Vector2(4.2, 4.4), "size": Vector2(2.0, 3.6), "color": Color("c9cfda"), "y": 0.012},
					{"shape": "box", "pos": Vector2(4.2, -3.9), "size": Vector2(1.5, 3.4), "color": Color("3fa2d6"), "y": 0.02},
					{"shape": "box", "pos": Vector2(-1.2, 5.6), "size": Vector2(7.2, 1.8), "color": Color("3fa2d6"), "y": 0.02}],
			"tower": Vector2(2.6, -2.6), "windsock": Vector2(4.3, 8.1), "apron": {"center": Vector2(3.78, -0.4), "s": 0.7},
			"ground": Color("b6dc7a"),
			"mix": {S: 0.1, M: 0.25, J: 0.3, H: 0.15, P: 0.2},
			"unlock_stars": 13, "weather": ["storm", "crosswind", "fog"],
		},
	]
	for k in _defs.size():
		_defs[k]["taxi"] = _taxi(k)
	for d in _defs:
		var n: int = d["runways"].size()
		var m: Array = []
		for i in n:
			var row: Array = []
			for j in n:
				row.append(i != j and _segments_cross(d["runways"][i], d["runways"][j]))
			m.append(row)
		_cross.append(m)

## One airport's taxi network (see Taxi): each is one deliberate layout. Distances along a runway are from its centre, north positive.
static func _taxi(k: int) -> Dictionary:
	var d: Dictionary = _defs[k]
	var rws: Array = d["runways"]
	var b := Taxi.Builder.new()
	b.runways = rws
	var ap: Dictionary = d["apron"]
	var c: Vector2 = ap["center"]
	var sc: float = ap["s"]
	match k:
		0:   # Grass Strip: one runway, one taxiway beside it on the ramp's side, a connector at each end and one at the middle
			var r: Dictionary = rws[0]
			var ys := b.gate_ys(c, sc)
			b.beside("a", 0, 1.45, [2.5, r["center"].y - ys["1"], -2.6], {"h": r["center"].y - ys["h"], "2": r["center"].y - ys["2"]}, ["A", "B", "C"])
			b.gate("h", c, sc, "a_th")
			b.gate("1", c, sc, "a_c1")
			b.gate("2", c, sc, "a_t2")
		1:   # County: two runways crossing in an X; the ramp sits in the wide south-east corner between them
			var ys1 := b.gate_ys(c, sc)
			var hub := Vector2(1.6, ys1["h"])
			b.node("hub", hub)
			b.node("ea", Vector2(1.6, ys1["1"]))
			b.node("eb", Vector2(1.6, ys1["2"]))
			var r2: Dictionary = rws[1]
			var h2 := deg_to_rad(r2["heading"])
			var n2 := Vector2(cos(h2), sin(h2))
			b.node("r2x", Taxi.rp(r2, (hub - (r2["center"] as Vector2)).cross(n2), 0.0), 1, true)
			b.edge("r2x", "hub", "A")
			b.node("a1x", Vector2(0.0, hub.y), 0, true)
			b.edge("a1x", "hub", "B")
			b.node("a2x", Vector2(0.0, ys1["2"]), 0, true)
			b.edge("a2x", "eb", "C")
			b.edge("hub", "ea")
			b.edge("ea", "eb")
			b.gate("h", c, sc, "hub")
			b.gate("1", c, sc, "ea")
			b.gate("2", c, sc, "eb")
		2:   # Regional: two parallel runways with a taxiway between them; the ramp is east of the second
			var r1: Dictionary = rws[1]
			var ysr := b.gate_ys(c, sc)
			var cy: float = r1["center"].y
			b.beside("e", 1, 1.1, [3.3, cy - ysr["1"], -3.3], {"h": cy - ysr["h"], "2": cy - ysr["2"], "k": -1.5}, ["A", "B", "C"])
			b.beside("m", 0, 1.5, [3.3, cy - ysr["1"], -3.3], {"k": -1.5}, ["D", "E", "F"])
			b.crossing("xk", 1, -1.5, "m_tk", "e_tk", "G")
			b.gate("h", c, sc, "e_th")
			b.gate("1", c, sc, "e_c1")
			b.gate("2", c, sc, "e_t2")
		3:   # Mountain Field: two parallel runways (a little off north) with a taxiway between them; the small ramp is east
			var r1m: Dictionary = rws[1]
			var ysm := b.gate_ys(c, sc)
			var off_e := 1.25
			var sh := Taxi.s_at_y(r1m, off_e, ysm["h"])
			var s1 := Taxi.s_at_y(r1m, off_e, ysm["1"])
			var s2 := Taxi.s_at_y(r1m, off_e, ysm["2"])
			var sk := 0.5
			b.beside("e", 1, off_e, [2.3, sh, s2], {"1": s1, "k": sk}, ["A", "B", "C"])
			var h8 := deg_to_rad(r1m["heading"])
			var shift := ((rws[1]["center"] as Vector2) - (rws[0]["center"] as Vector2)).dot(Vector2(sin(h8), -cos(h8)))
			var sep := ((rws[1]["center"] as Vector2) - (rws[0]["center"] as Vector2)).dot(Vector2(cos(h8), sin(h8)))
			b.beside("m", 0, sep * 0.5, [2.3, -0.9, -2.1], {"k": sk + shift}, ["D", "E", "F"])
			b.crossing("xk", 1, sk, "m_tk", "e_tk", "G")
			b.gate("h", c, sc, "e_c1")
			b.gate("1", c, sc, "e_t1")
			b.gate("2", c, sc, "e_c2")
		4:   # Island: two parallel runways with a taxiway between them and the ramp on the east shore
			var r1i: Dictionary = rws[1]
			var ysi := b.gate_ys(c, sc)
			var cyi: float = r1i["center"].y
			b.beside("e", 1, 1.2, [2.7, cyi - ysi["1"], -2.9], {"h": cyi - ysi["h"], "2": cyi - ysi["2"], "k": -1.7}, ["A", "B", "C"])
			b.beside("m", 0, 1.6, [2.7, 0.2, -2.9], {"k": -1.7}, ["D", "E", "F"])
			b.crossing("xk", 1, -1.7, "m_tk", "e_tk", "G")
			b.gate("h", c, sc, "e_th")
			b.gate("1", c, sc, "e_c1")
			b.gate("2", c, sc, "e_t2")
		5:   # International: three parallel runways, a taxiway between each pair, crossing taxiways, the ramp east
			var r2i: Dictionary = rws[2]
			var ysn := b.gate_ys(c, sc)
			var cyn: float = r2i["center"].y
			b.beside("a", 2, 1.2, [3.4, cyn - ysn["h"], -3.4], {"1": cyn - ysn["1"], "2": cyn - ysn["2"], "k": -2.7}, ["A", "B", "C"])
			b.beside("b", 1, 1.15, [3.4, 0.0, -3.4], {"k1": -1.9, "k": -2.7}, ["D", "E", "F"])
			b.beside("c", 0, 1.15, [3.4, 0.0, -3.4], {"k1": -1.9}, ["G", "H", "J"])
			b.crossing("x1", 1, -1.9, "c_tk1", "b_tk1", "K")
			b.crossing("x2", 2, -2.7, "b_tk", "a_tk", "L")
			b.gate("h", c, sc, "a_c1")
			b.gate("1", c, sc, "a_t1")
			b.gate("2", c, sc, "a_t2")
	return b.done()

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

## The index of the airport with this name (0 if there is none).
static func index_of(airport_name_: String) -> int:
	_build()
	for i in COUNT:
		if _defs[i]["name"] == airport_name_:
			return i
	return 0

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

## The approach guide in front of a runway end: three chevrons on the extended centreline, each a V whose point is toward the threshold,
## closer together as they near it. `pos` is where a chevron stands, `dir` the way its point faces (always toward the threshold).
const CHEVRON_DIST := [3.1, 2.1, 1.3]          # behind the threshold, farthest first (gaps 1.0, 0.8)

static func approach_chevrons(i: int, e: int) -> Array:
	var thr := end_threshold(i, e)
	var dir := end_dir(i, e)
	var out: Array = []
	for d in CHEVRON_DIST:
		out.append({"pos": thr - dir * float(d), "dir": dir, "dist": float(d)})
	return out

## The approach end of end `e`: where a path must finish to land there (planes land away from it).
static func end_threshold(i: int, e: int) -> Vector2:
	return rw_center(i) - end_dir(i, e) * rw_length(i) * 0.5

## ...and where the landing roll finishes (the far end of the runway).
static func end_far(i: int, e: int) -> Vector2:
	return rw_center(i) + end_dir(i, e) * rw_length(i) * 0.5

static func tower_pos() -> Vector2:
	var ap: Dictionary = def().get("apron", {})
	if ap.is_empty():
		return def()["tower"]
	return (ap["center"] as Vector2) + Vector2(0.95, -1.0) * float(ap["s"])

## The look of an airport: "countryside" (the default), "coastal" (the island) or "alpine" (the mountain field).
static func style(i: int = -1) -> String:
	return def(i).get("style", "countryside")

## The airport's apron (where the tower, hangar, FBO and the parked planes are): {"center": Vector2, "s": scale}, or {} if none.
static func apron() -> Dictionary:
	return def().get("apron", {})

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

## A glider's ring as a share of a small plane's at this airport (the opener's is longer); -1 = the general one (Tuning.glider_timer_frac).
static func glider_timer_own(i: int = -1) -> float:
	return float(def(i).get("glider_timer", -1.0))

## ...and the share of the go-around chance a glider keeps there; -1 = the general one (Tuning.glider_go_around_mult).
static func glider_go_around_own(i: int = -1) -> float:
	return float(def(i).get("glider_go_around", -1.0))

## ...and its pay multiplier for a glider's landing (1 = the general fare).
static func glider_pay_own(i: int = -1) -> float:
	return float(def(i).get("glider_pay", 1.0))

static func mix(i: int = -1) -> Dictionary:
	return def(i)["mix"]
