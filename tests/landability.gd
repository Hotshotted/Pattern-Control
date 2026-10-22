extends RefCounted
## Landability: for every airport, runway end, wind direction that can make that end active, and aircraft type that
## can arrive there, is there a way in from every entry edge? A way in is a path E -> W -> threshold: it leaves the screen
## edge at E, flies straight to a waypoint W on the extended runway centreline, then lands along it. It must
##   * keep clear of terrain (no-fly circles, with a margin for the aircraft),
##   * have a straight final at least as long as the aircraft wants (Tuning.final_need_*),
##   * stay on screen, and
##   * score as a clean approach in the game's own Approach scorer (no turn penalty, no short-final penalty).
## Storms are checked as a second pass: with a storm cell parked at each of eight places around the field, a route must
## still exist from at least one entry whenever the storm is not sitting on the corridor itself.
## (This script holds no class names that need the autoloads at compile time: Tuning and Approach come in as objects.)

const CLEAR := 0.25            # extra room kept around terrain (the aircraft's own size)
const D_STEP := 0.25
const D_MAX := 14.0
const ENTRY_STEP := 1.0

var tun: Node
var approach                  # an Approach instance (the game's scorer)
var half_w := 5.0
var half_h := 8.9
var plane := RefCounted        # (unused: placeholder so the object keeps one shape)
var scratch                    # an Aircraft used to score paths
var allow_turn := 0.0          # the turn penalty a path may carry (0 = clean; a short tablet view needs a little)

func setup(tuning: Node, approach_obj, aircraft_obj, hw: float, hh: float) -> void:
	tun = tuning
	approach = approach_obj
	scratch = aircraft_obj
	half_w = hw
	half_h = hh

## Where aircraft can come in: points all round the screen edge, as the spawner picks them.
func entries() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cx := half_w - 0.9
	var cz := half_h - 0.9
	var x := -cx
	while x <= cx + 0.001:
		out.append(Vector2(x, -half_h))
		out.append(Vector2(x, half_h))
		x += ENTRY_STEP
	var z := -cz
	while z <= cz + 0.001:
		out.append(Vector2(-half_w, z))
		out.append(Vector2(half_w, z))
		z += ENTRY_STEP
	return out

static func seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## No-fly circles [[centre, radius]] for the current airport plus any storm cells [[centre, radius]].
func circles(storms: Array) -> Array:
	var out: Array = []
	var m: float = tun.hazard_margin + CLEAR
	for h in Airports.hazards():
		out.append([h["center"], h["radius"] + m])
	for s in storms:
		out.append([s[0], s[1] + m])
	return out

func clear(a: Vector2, b: Vector2, circ: Array) -> bool:
	for c in circ:
		if seg_dist(a, b, c[0]) < c[1]:
			return false
	return true

## Entry points the spawner would use: not inside a no-fly circle.
func usable(ents: Array, circ: Array) -> Array:
	var out: Array = []
	for en in ents:
		var ok := true
		for c in circ:
			if en.distance_to(c[0]) < c[1]:
				ok = false
		if ok:
			out.append(en)
	return out

func on_screen(p: Vector2) -> bool:
	return absf(p.x) <= half_w + 0.001 and absf(p.y) <= half_h + 0.001

## The straight final an aircraft of this type wants.
func need_len(type: int) -> float:
	return tun.final_need_base + tun.final_need_per_speed * tun.type_speed(type)

## Score a path (waypoints, then the threshold and the far end) exactly as the game would; true if its approach is
## geometrically clean (no short-final penalty, and a turn penalty of at most `allow_turn`).
func clean(type: int, pts: Array, thr: Vector2, far: Vector2, runway: int, end: int) -> bool:
	var p = scratch
	p.reset()
	p.state = 1
	p.type = type
	p.tkind = 0
	p.runway = runway
	p.land_end = end
	p.speed = tun.type_speed(type)
	p.pos = pts[0]
	for k in range(1, pts.size()):
		p.push(pts[k])
	p.push(thr)
	p.push(far)
	p.cleared = true
	approach.evaluate(p, 999.0, -1.0)
	return approach.pen_turn <= allow_turn and approach.pen_len == 0.0

## A search context for one set of no-fly circles: a grid of free points a path may bend at, and what each entry sees.
func prepare(circ: Array) -> Dictionary:
	var grid: Array[Vector2] = []
	var x := -half_w
	while x <= half_w + 0.001:
		var y := -half_h
		while y <= half_h + 0.001:
			var v := Vector2(x, y)
			var free := true
			for c in circ:
				if v.distance_to(c[0]) < c[1]:
					free = false
			if free:
				grid.append(v)
			y += 1.0
		x += 1.0
	return {"circ": circ, "grid": grid, "seen": {}}

func _seen(ctx: Dictionary, e: Vector2) -> Array:
	if not ctx["seen"].has(e):
		var out: Array = []
		var grid: Array = ctx["grid"]
		for k in grid.size():
			if clear(e, grid[k], ctx["circ"]):
				out.append(k)
		ctx["seen"][e] = out
	return ctx["seen"][e]

## A path from entry `e` onto runway end (r, end) for `type`: the waypoints before the threshold on success
## ([] if none): at most one bend (V) on the way to a waypoint W on the extended centreline.
func runway_path(r: int, end: int, type: int, e: Vector2, ctx: Dictionary) -> Array:
	var circ: Array = ctx["circ"]
	var thr := Airports.end_threshold(r, end)
	var far := Airports.end_far(r, end)
	var dir := Airports.end_dir(r, end)
	if clear(e, thr, circ) and clean(type, [e], thr, far, r, end):
		return [e]                         # already lined up with the runway
	var grid: Array = ctx["grid"]
	var seen := _seen(ctx, e)
	var d := need_len(type) + 0.1
	while d <= D_MAX:
		var w := thr - dir * d
		if not on_screen(w) or not clear(w, thr, circ):
			return []                      # the corridor is cut off: a longer one is too
		if clear(e, w, circ) and clean(type, [e, w], thr, far, r, end):
			return [w]
		for k in seen:
			var v: Vector2 = grid[k]
			if clear(v, w, circ) and clean(type, [e, v, w], thr, far, r, end):
				return [v, w]
		d += D_STEP
	return []

## Helipads and water lanes: a straight flight, or one bend round the terrain.
func place_path(kind: int, idx: int, e: Vector2, circ: Array) -> bool:
	var target: Vector2 = Airports.land_threshold(kind, idx, 0)
	if clear(e, target, circ):
		return true
	for k in 16:
		var w := target + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * 3.0
		if on_screen(w) and clear(e, w, circ) and clear(w, target, circ):
			return true
	return false

## Every aircraft type that can arrive at airport `i`: its traffic mix plus the types its intro beats bring in.
func arriving_types(i: int) -> Array:
	var out: Array = []
	for t in Airports.mix(i).keys():
		if not out.has(t):
			out.append(t)
	for b in tun.airport_profiles[i]["beats"]:
		if not out.has(int(b[1])):
			out.append(int(b[1]))
	return out

## Wind directions (from, degrees) the game can pick at the current airport.
func winds() -> Array:
	var out: Array = []
	for k in 36:
		if Airports.wind_ok(k * 10.0, tun.wind_tolerance_deg):
			out.append(k * 10.0)
	return out

## Run everything for airport `i`. Returns {"checked": n, "failures": [strings], "storm_blocked": n, "lines": [strings]}.
func run(i: int) -> Dictionary:
	Airports.current = i
	var res := {"checked": 0, "failures": [], "storm_blocked": 0, "lines": []}
	var base := circles([])
	var ctx_base := prepare(base)
	var ents := usable(entries(), base)
	var types := arriving_types(i)
	var win := winds()
	if win.is_empty():
		res["failures"].append("%s: no wind direction keeps every runway usable" % Airports.airport_name(i))
	# Which ends can a wind activate?
	var end_winds := {}
	for w in win:
		for r in Airports.rw_count():
			var any := false
			for e in 2:
				if Airports.angle_diff(Airports.end_heading_deg(r, e), w) <= tun.wind_tolerance_deg:
					end_winds[r * 2 + e] = end_winds.get(r * 2 + e, 0) + 1
					any = true
			if not any:
				res["failures"].append("%s: wind %d closes runway %d (no active end)" % [Airports.airport_name(i), int(w), r])
	for t in types:
		var kind: int = Airports.kind_for(t)
		if kind == 0:
			for r in Airports.rw_count():
				if not Airports.suitable_runway(t, r):
					continue
				for e in 2:
					var winds_n: int = end_winds.get(r * 2 + e, 0)
					if winds_n == 0:
						res["failures"].append("%s: runway %d end %d is never active" % [Airports.airport_name(i), r, e])
						continue
					var bad := 0
					for en in ents:
						if runway_path(r, e, t, en, ctx_base).is_empty():
							bad += 1
					res["checked"] += winds_n * ents.size()
					if bad > 0:
						res["failures"].append("%s: %s on runway %d end %d: %d of %d entries have no clean approach (for %d wind directions)" % [Airports.airport_name(i), _type_name(t), r, e, bad, ents.size(), winds_n])
					# Storms: parked at eight places round the field.
					var fc := Airports.field_center()
					for k in 8:
						var storm := [[fc + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * 3.5, tun.storm_radius]]
						var circ := circles(storm)
						var ctx_s := prepare(circ)
						var any := false
						for en in usable(ents, circ):
							if not runway_path(r, e, t, en, ctx_s).is_empty():
								any = true
								break
						if not any:
							res["storm_blocked"] += 1
							if Airports.hazards().size() > 0 and not _storm_on_corridor(r, e, t, storm[0]):
								res["failures"].append("%s: %s on runway %d end %d: a storm at probe %d leaves no route although it is off the corridor" % [Airports.airport_name(i), _type_name(t), r, e, k])
		else:
			for p in Airports.land_count(kind):
				var bad2 := 0
				for en in ents:
					if not place_path(kind, p, en, base):
						bad2 += 1
				res["checked"] += ents.size()
				if bad2 > 0:
					res["failures"].append("%s: %s to place %d: %d entries blocked" % [Airports.airport_name(i), _type_name(t), p, bad2])
	return res

func _storm_on_corridor(r: int, end: int, type: int, storm: Array) -> bool:
	var thr := Airports.end_threshold(r, end)
	var dir := Airports.end_dir(r, end)
	var far_pt := thr - dir * (need_len(type) + 0.3)
	return seg_dist(far_pt, thr, storm[0]) < storm[1] + tun.hazard_margin + CLEAR

func _type_name(t: int) -> String:
	return ["glider", "helicopter", "small", "medium", "jet", "seaplane"][t]
