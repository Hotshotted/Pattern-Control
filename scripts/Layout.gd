class_name Layout
extends RefCounted
## Checks on an airport's ground layout (its runways, taxi network and ramp), shared by the smoke test and tools/layout_check.gd.
## `problems(a)` returns what is wrong with airport `a`, one line each (nothing: the layout is sound).

const FUNNEL_REACH := 3.6          # how far behind a runway end its approach funnel is kept clear (see Airfield.in_strip)
const SLAB := Vector2(1.4, 1.6)    # the ramp's slab: half width and half depth of its main part, times its scale
const SLAB_DEPTH := 6.3            # ...its whole depth with the second row of tie-downs and two rows of overflow bays (to the south), times its scale

const HUD_MARGIN_PX := 12.0
const HUD_RECTS_PX := [
	Rect2(20.0, 10.0, 80.0, 80.0),          # pause
	Rect2(255.0, 0.0, 570.0, 245.0),        # the timer / coins pill and the star bar
	Rect2(924.0, 20.0, 132.0, 150.0),       # the wind card
	Rect2(100.0, 262.0, 880.0, 90.0),       # the wind-shift banner (the widest it gets), just under the star bar
]

static var _hud_key := Vector3(-1.0, 0.0, 0.0)
static var _hud_rects: Array[Rect2] = []

## The interface's footprint on the field (see Airfield.in_strip): world rectangles, worked out once per view.
static func hud_world_rects(extra_px: float = 0.0) -> Array[Rect2]:
	var tn: Node = Engine.get_main_loop().root.get_node_or_null("Tuning") if Engine.get_main_loop() is SceneTree else null
	var ortho: float = tn.ortho_size if tn else 10.0          # (a bare --script run, tools/layout_check.gd, has no autoloads)
	var tilt: float = tn.camera_tilt_deg if tn else 10.0
	var key := Vector3(ortho, tilt, extra_px)
	if key == _hud_key:
		return _hud_rects            # (worked out once per view: a placement search asks thousands of times)
	_hud_key = key
	_hud_rects = _hud_world_rects(extra_px, ortho, tilt)
	return _hud_rects

static func _hud_world_rects(extra_px: float, ortho: float, tilt: float) -> Array[Rect2]:
	var k := ortho / 1080.0
	var kz := k / cos(deg_to_rad(tilt))
	var out: Array[Rect2] = []
	for r in HUD_RECTS_PX:
		var g: Rect2 = (r as Rect2).grow(HUD_MARGIN_PX + extra_px)
		out.append(Rect2((g.position.x - 540.0) * k, (g.position.y - 960.0) * kz, g.size.x * k, g.size.y * kz))
	return out


## Is `p` (with `r` to spare) under the interface?
static func in_hud(p: Vector2, r: float = 0.0) -> bool:
	for rc in hud_world_rects():
		if rc.grow(r).has_point(p):
			return true
	return false

static func slab(c: Vector2, s: float) -> Rect2:
	return Rect2(c - SLAB * s, Vector2(SLAB.x * 2.0, SLAB_DEPTH) * s)

# ---------- The ramp's places ----------

## Where aircraft park and how they get there, for the airport being looked at: every place has `via`, the ways in: [{"node" (a node of
## the taxi graph), "tail" (the points on from there)}]. {"hangar", "tie": [{pos, yaw, via}], "extra" (the "+N" spot), "over": [...]}.
## The hangar and the first row are entered by the west gates (see Taxi.Builder.gate): along an aisle, then into the spot.
static func ramp(n: Dictionary, ap: Dictionary) -> Dictionary:
	var c: Vector2 = ap["center"]
	var s: float = ap["s"]
	var g: Dictionary = n["gates"]
	var gx := c.x - 1.4 * s
	var y_h := c.y - 0.38 * s
	var y1 := c.y + 0.82 * s
	var y2 := c.y + 1.72 * s
	var out := {"tie": [], "over": []}
	var door := Vector2(c.x - 0.7 * s, c.y - 0.62 * s)
	out["hangar"] = {"pos": door, "yaw": 0.0, "via": [{"node": g["h"], "tail": PackedVector2Array([Vector2(c.x - 0.7 * s, y_h), door])}]}
	for row in 2:
		for k in 3:
			var x := c.x + (-0.9 + 0.9 * k) * s
			var p := Vector2(x, c.y + (1.28 + 0.95 * row) * s)
			var ay := y1 if row == 0 else y2
			(out["tie"] as Array).append({"pos": p, "yaw": PI, "via": [{"node": g["1" if row == 0 else "2"], "tail": PackedVector2Array([Vector2(x, ay), p])}]})
	var tag := c + Vector2(1.0 * s, 2.4 * s)
	out["extra"] = {"pos": tag, "yaw": PI, "via": [{"node": g["2"], "tail": PackedVector2Array([Vector2(c.x + 1.0 * s, y2), tag])}]}
	for row in 2:
		for k in 3:
			var x := c.x + (-0.9 + 0.9 * k) * s
			var p := Vector2(x, c.y + (3.3 + 0.95 * row) * s)
			var ay := c.y + (2.8 + 0.95 * row) * s
			(out["over"] as Array).append({"pos": p, "yaw": PI, "via": [{"node": g["3" if row == 0 else "4"], "tail": PackedVector2Array([Vector2(x, ay), p])}]})
	return out

## Is `p` (a pavement point with `half` to spare) inside the approach funnel behind a runway end?
static func in_funnel(p: Vector2, half: float) -> bool:
	for i in Airports.rw_count():
		for e in 2:
			var thr := Airports.end_threshold(i, e)
			var out := -Airports.end_dir(i, e)          # away from the runway, behind the threshold
			var rel := p - thr
			var along := rel.dot(out)
			var lat := absf(rel.dot(Vector2(-out.y, out.x)))
			if along > 0.0 and along < FUNNEL_REACH + half and lat < Airports.rw_width(i) * 0.5 + 0.65 + 1.4 * minf(along, 3.4) / 3.4 + half:
				return true
	return false

# ---------- Props out of the paths ----------

## (The geometry lives here so the layout check, which runs without the autoloads, can use it: Airfield.in_strip calls it.)
static func in_strip(p: Vector2, r: float = 0.0, pads: bool = true, hud: bool = true) -> bool:
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		var dir := Vector2(sin(h), -cos(h))
		var rel := p - Airports.rw_center(i)
		var along := absf(rel.dot(dir))
		var lat := absf(rel.dot(Vector2(-dir.y, dir.x)))
		var half := Airports.rw_length(i) * 0.5
		var w: float = Airports.rw_width(i)
		if along < half + r and lat < w * 0.5 + 0.55 + r:
			return true
		if along >= half and along < half + 3.6 + r and lat < w * 0.5 + 0.65 + 1.4 * minf(along - half, 3.4) / 3.4 + r:
			return true
	for lane in Airports.lanes():
		var lh := deg_to_rad(lane["heading"])
		var ld := Vector2(sin(lh), -cos(lh))
		var lrel: Vector2 = p - (lane["center"] as Vector2)
		if absf(lrel.dot(Vector2(-ld.y, ld.x))) < lane["width"] * 0.5 + 1.0 + r and absf(lrel.dot(ld)) < lane["length"] * 0.5 + 1.0 + r:
			return true
	if pads:
		for pad in Airports.pads():
			if p.distance_to(pad["center"]) < pad["radius"] + 0.9 + r:
				return true
	return hud and Layout.in_hud(p, r)



## Where trees may stand (the scenery picks the ones that are clear of every path: see `tree_spots`).
const TREE_SPOTS := [Vector2(-4.4, 6.4), Vector2(-3.6, 7.6), Vector2(4.3, 6.9), Vector2(4.5, -6.5), Vector2(-4.4, -6.9), Vector2(3.7, -7.8), Vector2(-4.2, -3.9), Vector2(4.5, 4.4), Vector2(4.6, 8.0), Vector2(-4.6, 2.6), Vector2(-4.6, -1.5), Vector2(4.5, -4.9), Vector2(-2.0, -7.9), Vector2(1.5, -8.2)]
const APPROACH_REACH := 7.0       # how far out the approach corridors are kept clear of props (aircraft come in from there, low)
const APPROACH_HALF := 0.9
const TAXI_HALF := 0.85           # half width of the strip kept clear along every taxiway edge

## Is a prop of radius `r` at `p` in the way of anything an aircraft follows: the runways and their funnels, the lanes and pads, the interface, the
## approach corridors (straight out of every runway end, 7 units), the taxiways and the ramp's slab? Then it looks as if a plane flies through it.
static func prop_blocked(p: Vector2, r: float = 0.45, ground: bool = true) -> bool:
	if in_strip(p, r):
		return true
	for i in Airports.rw_count():
		for e in 2:
			var thr := Airports.end_threshold(i, e)
			var d := Airports.end_dir(i, e)
			var rel := p - thr
			var along := -rel.dot(d)            # (behind the threshold, where the approach comes from)
			var lat := absf(rel.dot(Vector2(-d.y, d.x)))
			if along > -0.2 and along < APPROACH_REACH + r and lat < APPROACH_HALF + r:
				return true
	if not ground:
		return false          # (scenery that stands on the ramp or by a taxiway on purpose is only kept out of the approach corridors)
	var n := Taxi.net()
	for ed in n.get("edges", []):
		var a := Taxi.pos(n, ed[0])
		var b := Taxi.pos(n, ed[1])
		var ab := b - a
		var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * u) < TAXI_HALF + r:
			return true
	var ap := Airports.apron()
	if not ap.is_empty() and slab(ap["center"], ap["s"]).grow(r + 0.3).has_point(p):
		return true
	return false

## The tree spots of airport `a` that are clear (what the scenery plants).
static func tree_spots(a: int) -> Array[Vector2]:
	var keep := Airports.current
	Airports.current = a
	var out: Array[Vector2] = []
	for t in TREE_SPOTS:
		if not prop_blocked(t, 0.45):
			out.append(t)
	Airports.current = keep
	return out

## Props (world x, z) that stand in an aircraft's way: one line each. Used by the layout check and the smoke test, with the props actually planted.
static func prop_problems(a: int, props: Array, r: float = 0.3, ground: bool = true) -> Array[String]:
	var out: Array[String] = []
	var keep := Airports.current
	Airports.current = a
	for p in props:
		if prop_blocked(p, r, ground):
			out.append("a prop at (%.1f, %.1f) is in a runway funnel, an approach corridor, a taxiway or the ramp" % [p.x, p.y])
	Airports.current = keep
	return out

## Samples along every taxi edge, a point each 0.1.
static func edge_samples(n: Dictionary) -> Array:
	var out: Array = []
	for e in n["edges"]:
		var a := Taxi.pos(n, e[0])
		var b := Taxi.pos(n, e[1])
		var l := a.distance_to(b)
		var k := maxi(ceili(l / 0.1), 1)
		for q in k + 1:
			out.append([a.lerp(b, float(q) / float(k)), e])
	return out

static func on_pavement(n: Dictionary, p: Vector2, slab_r: Rect2, slack: float) -> bool:
	for i in Airports.rw_count():
		if Taxi.in_box(p, Taxi.rw_box(i, slack)):
			return true
	if Taxi.on_taxiway(n, p, slack):
		return true
	return slab_r.grow(slack).has_point(p)

static func problems(a: int) -> Array[String]:
	var out: Array[String] = []
	out.append_array(prop_problems(a, tree_spots(a)))
	var keep := Airports.current
	Airports.current = a
	var n := Taxi.net()
	var ap := Airports.apron()
	var c: Vector2 = ap["center"]
	var sc: float = ap["s"]
	var sl := slab(c, sc)
	# the graph: one piece, every gate in it
	var gates: Dictionary = n["gates"]
	for k in ["h", "1", "2"]:
		if not gates.has(k):
			out.append("no gate %s" % k)
	var seen := {}
	var open: Array = [gates.get("h", "")]
	while not open.is_empty():
		var u: String = open.pop_back()
		if seen.has(u) or not n["nodes"].has(u):
			continue
		seen[u] = true
		for nb in Taxi.adjacency(n)[u]:
			open.append(nb[0])
	for name in n["nodes"]:
		if not seen.has(name):
			out.append("node %s is not joined to the ramp" % name)
	# every runway end: an exit that reaches every gate, over pavement
	for i in Airports.rw_count():
		for e in 2:
			for cls in 3:
				var t := Taxi.turn_off(i, e, cls)
				if t.is_empty():
					out.append("runway %d end %d (class %d) has no exit" % [i, e, cls])
					continue
				for gk in gates:
					var names := Taxi.shortest(n, t["node"], gates[gk])
					if names.is_empty():
						out.append("exit %s cannot reach gate %s" % [t["node"], gk])
						continue
					var pts := PackedVector2Array([Taxi.stop_point(i, e, cls)])
					pts.append_array(Taxi.path_points(n, names))
					var route := Taxi.smooth(pts)
					var d := 0.0
					var tot := Taxi.length(route)
					while d <= tot:
						var p: Vector2 = Taxi.at(route, d)[0]
						if not on_pavement(n, p, sl, 0.06):
							out.append("route %d/%d class %d to gate %s leaves the pavement at (%.2f, %.2f)" % [i, e, cls, gk, p.x, p.y])
							break
						d += 0.05
					# a route that crosses another runway has a hold-short line before it
					for j in Airports.rw_count():
						if j == i:
							continue
						var crosses := false
						var dd := 0.0
						while dd <= tot:
							if Taxi.in_box(Taxi.at(route, dd)[0], Taxi.rw_box(j)):
								crosses = true
								break
							dd += 0.05
						if crosses:
							var hl := Taxi.holds(route, i)
							var found := false
							for h in hl:
								if h["rw"] == j:
									found = true
							if not found:
								out.append("route %d/%d to gate %s crosses runway %d with no hold-short" % [i, e, gk, j])
	# the ramp's places: the hangar, the tie-downs, the "+N" spot and the overflow spots, each reached over pavement from every runway end
	var rm := ramp(n, ap)
	var places: Array = [["hangar", rm["hangar"]], ["extra", rm["extra"]]]
	for k in (rm["tie"] as Array).size():
		places.append(["tie %d" % k, rm["tie"][k]])
	for k in (rm["over"] as Array).size():
		places.append(["over %d" % k, rm["over"][k]])
	for pl in places:
		var spot: Dictionary = pl[1]
		if pl[0] != "hangar" and (in_funnel(spot["pos"], 0.2) or in_hud(spot["pos"], 0.2)):
			out.append("%s sits in a funnel or under the interface" % pl[0])
		for pad in Airports.pads():
			if (spot["pos"] as Vector2).distance_to(pad["center"]) < float(pad["radius"]) + 1.2:
				out.append("%s is too close to a helipad" % pl[0])
	for pad in Airports.pads():
		var nearest := Vector2(clampf(pad["center"].x, sl.position.x, sl.end.x), clampf(pad["center"].y, sl.position.y, sl.end.y))
		if nearest.distance_to(pad["center"]) < float(pad["radius"]) + 0.6:
			out.append("the ramp touches a helipad")
	for i in Airports.rw_count():
		for e in 2:
			for cls in [0, 2]:
				for pl in places:
					var plan := Taxi.plan(i, e, cls, pl[1]["via"])
					var route: PackedVector2Array = plan["route"]
					if route.size() < 2:
						out.append("runway %d end %d class %d has no route to %s" % [i, e, cls, pl[0]])
						continue
					var d2 := 0.0
					var tot2 := Taxi.length(route)
					var bad_pt := false
					while d2 <= tot2 and not bad_pt:
						var pp: Vector2 = Taxi.at(route, d2)[0]
						if not on_pavement(n, pp, sl, 0.06) and not (pl[0] == "hangar" and sl.grow(0.5).has_point(pp)):
							out.append("route %d/%d class %d to %s leaves the pavement at (%.2f, %.2f)" % [i, e, cls, pl[0], pp.x, pp.y])
							bad_pt = true
						d2 += 0.1
	# pavement stays out of the funnels, off the interface, off the mountains, clear of pads and lanes, inside the screen
	var bad_funnel := 0
	var bad_hud := 0
	for s in edge_samples(n):
		var p: Vector2 = s[0]
		if in_funnel(p, Taxi.WIDTH * 0.5):
			bad_funnel += 1
		if in_hud(p, Taxi.WIDTH * 0.5):
			bad_hud += 1
		if absf(p.x) > 4.85:
			out.append("taxiway at (%.2f, %.2f) is off the screen" % [p.x, p.y])
			break
		for hz in Airports.hazards():
			if p.distance_to(hz["center"]) < float(hz["radius"]) + 0.3:
				out.append("taxiway at (%.2f, %.2f) is in a mountain" % [p.x, p.y])
				break
		for pad in Airports.pads():
			if p.distance_to(pad["center"]) < float(pad["radius"]) + 0.5:
				out.append("taxiway at (%.2f, %.2f) is on a helipad" % [p.x, p.y])
				break
	if bad_funnel > 0:
		out.append("%d taxiway points are inside an approach funnel" % bad_funnel)
	if bad_hud > 0:
		out.append("%d taxiway points are under the interface" % bad_hud)
	# the slab: on the screen, outside the funnels and the interface, clear of pads
	for corner in [sl.position, Vector2(sl.end.x, sl.position.y), sl.end, Vector2(sl.position.x, sl.end.y)]:
		if in_funnel(corner, 0.0):
			out.append("the ramp's corner (%.2f, %.2f) is inside an approach funnel" % [corner.x, corner.y])
		if in_hud(corner, 0.0):
			out.append("the ramp's corner (%.2f, %.2f) is under the interface" % [corner.x, corner.y])
	if sl.end.x > 5.0:
		out.append("the ramp reaches x = %.2f" % sl.end.x)
	# a parallel taxiway keeps off its runway (only connectors and crossings touch one)
	for e in n["edges"]:
		if n["rw"].has(e[0]) or n["rw"].has(e[1]):
			continue
		var pa := Taxi.pos(n, e[0])
		var pb := Taxi.pos(n, e[1])
		var q := 0
		while q <= 10:
			var pp := pa.lerp(pb, float(q) / 10.0)
			for i in Airports.rw_count():
				if Taxi.in_box(pp, Taxi.rw_box(i, Taxi.WIDTH * 0.5 + 0.2)):
					out.append("taxiway %s-%s runs onto runway %d" % [e[0], e[1], i])
					q = 99
					break
			q += 1
	# every connector that meets a runway has its letter
	for e in n["edges"]:
		if (n["rw"].has(e[0]) or n["rw"].has(e[1])) and String(e[2]) == "":
			out.append("the junction %s-%s has no taxiway letter" % [e[0], e[1]])
	Airports.current = keep
	return out
