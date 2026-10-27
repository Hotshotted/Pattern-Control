class_name Taxi
extends RefCounted
## One airport's taxi network: the graph the landed aircraft follow, and the geometry of the pavement and lines that are drawn for it.
## The graph lives in the airport's data (Airports: `def["taxi"]`): nodes (name -> point), edges ([a, b, letter]), the nodes that lie on a
## runway's centreline (`rw`: a turn-off, or the middle of a crossing) and the gates where the ramp's aisles begin. A taxiway is a
## ribbon of WIDTH along its edges; where edges meet, and where a taxiway meets a runway's edge, the corners are rounded (FILLET).
## Pure functions of that data, so the tests can check every airport without drawing it.

const WIDTH := 0.5                 # a taxiway's width
const TURN_R := 0.3                # the radius of the yellow line's curves, and of an aircraft's turns on them
const FILLET := 0.3                # the radius of the pavement's rounded corners
const HOLD_OFF := 0.4              # where the hold-short line is: this far outside a runway's edge
const STOP_BACK := 0.8             # an aircraft rolls out to a point this far before the turn-off's node
const ROLL_FRAC := [0.3, 0.4, 0.55]   # how much of the runway an aircraft of speed class 0 / 1 / 2 uses before it can turn off

# ---------- The graph ----------

static func net(i: int = -1) -> Dictionary:
	return Airports.def(i).get("taxi", {})

static func pos(n: Dictionary, name: String) -> Vector2:
	return n["nodes"][name]

## name -> Array of [neighbour, length, edge index]
static func adjacency(n: Dictionary) -> Dictionary:
	if n.has("_adj"):
		return n["_adj"]
	var adj := {}
	for name in n["nodes"]:
		adj[name] = []
	var edges: Array = n["edges"]
	for k in edges.size():
		var a: String = edges[k][0]
		var b: String = edges[k][1]
		var l: float = pos(n, a).distance_to(pos(n, b))
		adj[a].append([b, l, k])
		adj[b].append([a, l, k])
	n["_adj"] = adj
	return adj

## The shortest way between two nodes: their names, in order (empty if there is none).
static func shortest(n: Dictionary, from: String, to: String) -> Array[String]:
	var adj := adjacency(n)
	var dist := {from: 0.0}
	var prev := {}
	var open: Array[String] = [from]
	var done := {}
	while not open.is_empty():
		var u := open[0]
		for o in open:
			if dist[o] < dist[u]:
				u = o
		open.erase(u)
		if done.has(u):
			continue
		done[u] = true
		if u == to:
			break
		for nb in adj[u]:
			var v: String = nb[0]
			var nd: float = dist[u] + nb[1]
			if not dist.has(v) or nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				open.append(v)
	var out: Array[String] = []
	if not dist.has(to):
		return out
	var at := to
	while true:
		out.push_front(at)
		if at == from:
			break
		at = prev[at]
	return out

static func path_points(n: Dictionary, names: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for nm in names:
		out.append(pos(n, nm))
	return out

# ---------- Turn-offs ----------

## The turn-off an aircraft of speed class `cls` takes when it lands on end `e` of runway `i`: the first node on the runway's centreline
## that is far enough along (ROLL_FRAC of the runway) to roll out to, or else the farthest one. {"node", "d" (from the threshold), "rw"}.
static func turn_off(i: int, e: int, cls: int) -> Dictionary:
	var n := net()
	var thr := Airports.end_threshold(i, e)
	var dir := Airports.end_dir(i, e)
	var need: float = Airports.rw_length(i) * float(ROLL_FRAC[clampi(cls, 0, 2)])
	var best := {}
	var far := {}
	for name in n["rw"]:
		if int(n["rw"][name]) != i or not n["exits"].has(name):
			continue
		var d := (pos(n, name) - thr).dot(dir)
		if d < STOP_BACK + 0.4:
			continue
		var c := {"node": name, "d": d, "rw": i}
		if d >= need and (best.is_empty() or d < float(best["d"])):
			best = c
		if far.is_empty() or d > float(far["d"]):
			far = c
	return best if not best.is_empty() else far

## Where the landing roll ends: on the runway, a little before the turn-off's node.
static func stop_point(i: int, e: int, cls: int) -> Vector2:
	var t := turn_off(i, e, cls)
	if t.is_empty():
		return Airports.end_far(i, e)
	return pos(net(), t["node"]) - Airports.end_dir(i, e) * STOP_BACK

# ---------- Smoothing ----------

## A polyline with its corners rounded: each corner is replaced by an arc of radius `r` (smaller if the segments are short).
static func smooth(pts: PackedVector2Array, r: float = TURN_R) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for k in range(1, pts.size() - 1):
		var a := pts[k - 1]
		var b := pts[k]
		var c := pts[k + 1]
		var d1 := (b - a)
		var d2 := (c - b)
		var l1 := d1.length()
		var l2 := d2.length()
		if l1 < 0.0001 or l2 < 0.0001:
			continue
		d1 /= l1
		d2 /= l2
		var turn := absf(d1.angle_to(d2))
		if turn < 0.05:
			out.append(b)
			continue
		var t := minf(r * tan(turn * 0.5), minf(l1, l2) * 0.45)
		out.append_array(arc(b, d1, d2, t))
	out.append(pts[pts.size() - 1])
	return out

## The arc that rounds the corner `b` between a path arriving along d1 and leaving along d2, from `t` before the corner to `t` after it.
static func arc(b: Vector2, d1: Vector2, d2: Vector2, t: float) -> PackedVector2Array:
	var turn := absf(d1.angle_to(d2))
	var out := PackedVector2Array()
	var reff := t / tan(turn * 0.5)
	var t1 := b - d1 * t
	var sgn := 1.0 if d1.cross(d2) > 0.0 else -1.0
	var nrm := Vector2(-d1.y, d1.x) * sgn            # toward the inside of the turn
	var ctr := t1 + nrm * reff
	var a0 := (t1 - ctr).angle()
	var steps := maxi(ceili(turn / 0.3), 2)
	for s in steps + 1:
		var ang := a0 + sgn * turn * float(s) / float(steps)
		out.append(ctr + Vector2(cos(ang), sin(ang)) * reff)
	return out

static func length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
	return total

## The point and direction `d` along a polyline.
static func at(pts: PackedVector2Array, d: float) -> Array:
	var left := maxf(d, 0.0)
	for k in pts.size() - 1:
		var seg := pts[k].distance_to(pts[k + 1])
		if left <= seg or k == pts.size() - 2:
			var t := (pts[k + 1] - pts[k]).normalized() if seg > 0.0001 else Vector2(0, -1)
			return [pts[k] + t * minf(left, seg), t]
		left -= seg
	return [pts[0], Vector2(0, -1)]

# ---------- Runways on the ground ----------

static func rw_box(i: int, margin: float = 0.0) -> Array:
	var h := deg_to_rad(Airports.rw_heading_deg(i))
	return [Airports.rw_center(i), Vector2(sin(h), -cos(h)), Airports.rw_length(i) * 0.5 + margin, Airports.rw_width(i) * 0.5 + margin]

static func in_box(p: Vector2, box: Array) -> bool:
	var dir: Vector2 = box[1]
	var rel: Vector2 = p - (box[0] as Vector2)
	return absf(rel.dot(dir)) <= float(box[2]) and absf(rel.dot(Vector2(-dir.y, dir.x))) <= float(box[3])

## The stretches of runway `i`'s line `x` to the right of its centre, from local z `z0` to `z1`, that no other runway covers (with `margin`
## to spare), as [[from, to], ...]: where runways cross, one intersection is drawn, so lines and dashes stop at the other's edge.
static func clear_runs(i: int, x: float, z0: float, z1: float, margin: float) -> Array:
	var h := deg_to_rad(Airports.rw_heading_deg(i))
	var dir := Vector2(sin(h), -cos(h))
	var right := Vector2(cos(h), sin(h))
	var c := Airports.rw_center(i)
	var out: Array = []
	var start := NAN
	var z := z0
	var last := z0
	while z <= z1 + 0.0001:
		var p := c + right * x - dir * z          # local +z is the end-0 side
		var covered := false
		for j in Airports.rw_count():
			if j != i and in_box(p, rw_box(j, margin)):
				covered = true
		if covered:
			if not is_nan(start):
				out.append([start, last])
				start = NAN
		elif is_nan(start):
			start = z
		last = z
		z += 0.04
	if not is_nan(start):
		out.append([start, z1])
	return out

## The hold-short point on the edge from node `far` (on the taxiway side) to node `at` (on a runway): HOLD_OFF before the runway's edge.
static func hold_point(n: Dictionary, far: String, at: String) -> Vector2:
	var a := pos(n, far)
	var b := pos(n, at)
	var l := a.distance_to(b)
	var u := (b - a) / maxf(l, 0.0001)
	var box := rw_box(int(n["rw"][at]))
	var d := 0.0
	while d < l and not in_box(a + u * d, box):
		d += 0.02
	return a + u * maxf(d - HOLD_OFF, 0.0)

## The route of an aircraft that landed on end `e` of runway `i` (speed class `cls`) to a ramp place with the ways in `via`
## ([{"node", "tail"}], see Layout.ramp): out to the turn-off, along the graph to the nearest way in, then the tail; corners rounded.
## {"route": points, "holds": [{"rw", "hold", "clear"}] (distances along the route)}.
static func plan(i: int, e: int, cls: int, via: Array) -> Dictionary:
	var n := net()
	var t := turn_off(i, e, cls)
	var best := PackedVector2Array()
	if t.is_empty():
		return {"route": PackedVector2Array([Airports.end_far(i, e)]), "holds": []}
	for w in via:
		var names := shortest(n, t["node"], w["node"])
		if names.is_empty():
			continue
		var pts := PackedVector2Array([stop_point(i, e, cls)])
		pts.append_array(path_points(n, names))
		pts.append_array(w["tail"])
		var r := smooth(pts)
		if best.is_empty() or length(r) < length(best):
			best = r
	return {"route": best, "holds": holds(best, i)}

## Where a route has to stop short of a runway it crosses, and where it is clear again: [{"rw", "hold" (distance along the route), "clear"}].
## `own` is the runway it left (a turn-off is not a crossing): it is skipped until the route has left it.
static func holds(route: PackedVector2Array, own: int) -> Array:
	var out: Array = []
	var total := length(route)
	for i in Airports.rw_count():
		var box := rw_box(i, HOLD_OFF * 0.0)
		var inside := false
		var start := 0.0
		var d := 0.0
		var ever_out := i != own
		var step := 0.05
		while d <= total + 0.0001:
			var p: Vector2 = at(route, d)[0]
			var now := in_box(p, rw_box(i, 0.0))
			if not ever_out and not now:
				ever_out = true
			if ever_out:
				if now and not inside:
					inside = true
					start = d
				elif not now and inside:
					inside = false
					out.append({"rw": i, "hold": maxf(start - HOLD_OFF, 0.0), "clear": d})
			d += step
		if inside:
			out.append({"rw": i, "hold": maxf(start - HOLD_OFF, 0.0), "clear": total})
	return out

# ---------- Pavement and lines ----------

## The rays leaving node `name`: [direction, half width, length cap] for every edge, plus the runway both ways at a node on one.
static func rays(n: Dictionary, name: String) -> Array:
	var out: Array = []
	var p := pos(n, name)
	for nb in adjacency(n)[name]:
		var d: Vector2 = pos(n, nb[0]) - p
		var l := d.length()
		out.append({"dir": d / l, "half": WIDTH * 0.5, "cap": l * 0.45, "edge": nb[2], "runway": false})
	var ap := Airports.apron()
	if not ap.is_empty() and (n["gates"] as Dictionary).values().has(name):
		# a gate sits on the ramp's edge: the edge is a straight border the taxiway's corners are rounded against
		var sl := Layout.slab(ap["center"], float(ap["s"]))
		var best := 99.0
		var tan_d := Vector2.ZERO
		for sd in [[Vector2(1, 0), sl.end.x], [Vector2(-1, 0), -sl.position.x], [Vector2(0, 1), sl.end.y], [Vector2(0, -1), -sl.position.y]]:
			var dd := absf((p).dot(sd[0]) - float(sd[1]))
			if dd < best:
				best = dd
				tan_d = Vector2(-(sd[0] as Vector2).y, (sd[0] as Vector2).x)
		for sg in [-1.0, 1.0]:
			out.append({"dir": tan_d * sg, "half": 0.0, "cap": 99.0, "edge": -1, "runway": true, "slab": true})
	if n["rw"].has(name):
		var box := rw_box(int(n["rw"][name]))
		var u: Vector2 = box[1]
		for s in [-1.0, 1.0]:
			out.append({"dir": u * s, "half": float(box[3]), "cap": 99.0, "edge": -1, "runway": true})
	return out

## The rounded corner between two rays from a node (their sides' intersection, rounded off with `r`): a fan of triangles' points
## [corner, tangent 1, arc..., tangent 2], or nothing if they are (nearly) one straight line.
static func fillet(p: Vector2, ra: Dictionary, rb: Dictionary, r: float) -> PackedVector2Array:
	var d1: Vector2 = ra["dir"]
	var d2: Vector2 = rb["dir"]
	var phi := absf(d1.angle_to(d2))
	if phi > 2.95 or phi < 0.2:
		return PackedVector2Array()
	var sgn := 1.0 if d1.cross(d2) > 0.0 else -1.0
	var n1 := Vector2(-d1.y, d1.x) * sgn          # the side of ray 1 that faces ray 2
	var n2 := Vector2(-d2.y, d2.x) * -sgn          # the side of ray 2 that faces ray 1
	var a1: Vector2 = n1 * float(ra["half"])
	var a2: Vector2 = n2 * float(rb["half"])
	# the corner: p + a1 + d1 * t = p + a2 + d2 * u
	var cr := d1.cross(d2)
	if absf(cr) < 0.0001:
		return PackedVector2Array()
	var diff := a2 - a1
	var t := diff.cross(d2) / cr
	var c := p + a1 + d1 * t
	if t < 0.0:
		return PackedVector2Array()
	var tl := r / tan(phi * 0.5)
	var u := (diff.cross(d1)) / cr
	if t < tl * 0.2 and u < tl * 0.2:
		pass
	var ctr := c + (d1 + d2).normalized() * (r / sin(phi * 0.5))
	var t1 := c + d1 * tl
	var t2 := c + d2 * tl
	var out := PackedVector2Array()
	out.append(c)
	out.append(t1)
	var a_start := (t1 - ctr).angle()
	var sweep := wrapf((t2 - ctr).angle() - a_start, -PI, PI)
	var steps := maxi(ceili(absf(sweep) / 0.3), 2)
	for s in range(1, steps):
		var ang := a_start + sweep * float(s) / float(steps)
		out.append(ctr + Vector2(cos(ang), sin(ang)) * r)
	out.append(t2)
	return out

## The yellow centrelines of the whole network: polylines (every edge trimmed where it curves into the next, and the curves).
static func lines(n: Dictionary) -> Array:
	var out: Array = []
	var edges: Array = n["edges"]
	var trims := {}                 # "edge:node" -> how far the straight part stops short of the node
	var arcs: Array = []
	for name in n["nodes"]:
		var p := pos(n, name)
		var rs := rays(n, name)
		for a in rs.size():
			for b in range(a + 1, rs.size()):
				var ra: Dictionary = rs[a]
				var rb: Dictionary = rs[b]
				if ra["runway"] and rb["runway"]:
					continue
				if ra.has("slab") or rb.has("slab"):
					continue
				if (ra["runway"] or rb["runway"]) and not n["exits"].has(name):
					continue
				var d1: Vector2 = ra["dir"]
				var d2: Vector2 = rb["dir"]
				var turn := PI - absf(d1.angle_to(d2))
				if turn < 0.05:
					continue
				var t := minf(TURN_R * tan(turn * 0.5), minf(float(ra["cap"]), float(rb["cap"])))
				for rr in [ra, rb]:
					if int(rr["edge"]) >= 0:
						var key := "%d:%s" % [int(rr["edge"]), name]
						trims[key] = maxf(float(trims.get(key, 0.0)), t)
				arcs.append([p, d1, d2, t, turn])
	for k in edges.size():
		var a: String = edges[k][0]
		var b: String = edges[k][1]
		var pa := pos(n, a)
		var pb := pos(n, b)
		var dir := (pb - pa).normalized()
		out.append(PackedVector2Array([pa + dir * float(trims.get("%d:%s" % [k, a], 0.0)), pb - dir * float(trims.get("%d:%s" % [k, b], 0.0))]))
	for ar in arcs:
		var p: Vector2 = ar[0]
		var d1: Vector2 = ar[1]
		var d2: Vector2 = ar[2]
		var t: float = ar[3]
		var turn: float = ar[4]
		out.append(arc(p, -d1, d2, t))
	return out

## Is `p` on a taxiway (or its joints) of this airport, within `margin` of the edge of the ribbon?
static func on_taxiway(n: Dictionary, p: Vector2, margin: float = 0.0) -> bool:
	for e in n["edges"]:
		var a := pos(n, e[0])
		var b := pos(n, e[1])
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) <= WIDTH * 0.5 + margin:
			return true
	return false

# ---------- Building the data ----------

## A point on a runway: `s` along its heading from its centre, `off` to the right of the heading.
static func rp(r: Dictionary, s: float, off: float = 0.0) -> Vector2:
	var h := deg_to_rad(r["heading"])
	return (r["center"] as Vector2) + Vector2(sin(h), -cos(h)) * s + Vector2(cos(h), sin(h)) * off

## How far along runway `r` (from its centre) the line `off` to its right passes the world height `y`.
static func s_at_y(r: Dictionary, off: float, y: float) -> float:
	var h := deg_to_rad(r["heading"])
	var u := Vector2(sin(h), -cos(h))
	var n := Vector2(cos(h), sin(h))
	return (y - (r["center"] as Vector2).y - n.y * off) / u.y

## The data being assembled. `done()` gives the airport's `taxi` dictionary.
class Builder:
	var nodes := {}
	var edges: Array = []
	var rw := {}                 # node -> the runway whose centreline it lies on
	var exits: Array = []        # the nodes on a runway where an aircraft can leave it
	var gates := {}              # "hangar" / "tie1" / "tie2" -> the node at the ramp's edge
	var letters: Array = []      # [connector's edge index, letter] for the signs
	var runways: Array = []

	func node(name: String, p: Vector2, runway: int = -1, exit: bool = false) -> void:
		nodes[name] = p
		if runway >= 0:
			rw[name] = runway
			if exit:
				exits.append(name)

	func edge(a: String, b: String, letter: String = "") -> void:
		edges.append([a, b, letter])

	## A taxiway beside runway `ri`, `off` to its right (negative: left), with a connector to the runway at every `conns` position
	## (metres... world units along the heading from the centre; nodes `tag_x<k>` on the runway, `tag_c<k>` on the parallel) and extra
	## joints `tag_t<key>` at the positions in `taps` (key -> position). The parallel runs from its first joint to its last, in order.
	func beside(tag: String, ri: int, off: float, conns: Array, taps: Dictionary, letters_: Array) -> void:
		var r: Dictionary = runways[ri]
		var all: Array = []
		for k in conns.size():
			all.append([float(conns[k]), "%s_c%d" % [tag, k], k])
		for key in taps:
			all.append([float(taps[key]), "%s_t%s" % [tag, key], -1])
		all.sort_custom(func(a, b): return a[0] < b[0])
		var prev := ""
		for item in all:
			var pn: String = item[1]
			node(pn, Taxi.rp(r, item[0], off))
			if int(item[2]) >= 0:
				var k: int = item[2]
				var xn := "%s_x%d" % [tag, k]
				node(xn, Taxi.rp(r, item[0], 0.0), ri, true)
				edge(xn, pn, String(letters_[k]) if k < letters_.size() else "")
			if prev != "":
				edge(prev, pn, "")
			prev = pn

	## A taxiway that crosses runway `ri` at `s` from the `off_a` side to the `off_b` side, between two existing nodes: the middle is a
	## node on the runway's centreline.
	func crossing(name: String, ri: int, s: float, a: String, b: String, letter: String = "") -> void:
		var r: Dictionary = runways[ri]
		node(name, Taxi.rp(r, s, 0.0), ri, false)
		edge(a, name, letter)
		edge(name, b, letter)

	## The ramp's three gates on its west edge (`c`, scale `sc`): the hangar's aisle, the first and the second tie-down aisle.
	func gate_ys(c: Vector2, sc: float) -> Dictionary:
		return {"h": c.y - 0.38 * sc, "1": c.y + 0.82 * sc, "2": c.y + 1.72 * sc, "3": c.y + 2.8 * sc, "4": c.y + 3.75 * sc}

	func gate(key: String, c: Vector2, sc: float, from: String) -> void:
		var y: float = gate_ys(c, sc)[key]
		var gname := "g_" + key
		node(gname, Vector2(c.x - 1.4 * sc, y))
		edge(from, gname, "")
		gates[key] = gname
		if key == "2":          # the service road down the ramp's west edge to the rows of overflow bays
			for k in ["3", "4"]:
				node("g_" + k, Vector2(c.x - 1.4 * sc, gate_ys(c, sc)[k]))
				gates[k] = "g_" + k
			edge("g_2", "g_3", "")
			edge("g_3", "g_4", "")

	func done() -> Dictionary:
		return {"nodes": nodes, "edges": edges, "rw": rw, "exits": exits, "gates": gates}
