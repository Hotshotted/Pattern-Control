class_name Ramp
extends RefCounted
## The hangar and the ramp. A shift's landings park the landed aircraft: the hangar takes as many as break the shift even (the number
## of landings whose pay covers the shift's cost, its one-star threshold), then the tie-downs on the apron (6), then the overflow spots
## on the grass along the taxiway (up to 6), then everything else is only counted, as the "+N" by the apron. Helicopters go to a marked
## heli spot, seaplanes to the dock (where there is one). Pure bookkeeping plus the taxi-route geometry, so it can be tested on its own.
## Created once; reset per shift (in place).

const TIES := 6
const OVERS := 6
const HELI_SPOTS := 1
const TAXI_MARGIN := 0.5          # how far a taxi route keeps from a runway's edge (and from the end of it)
const EXIT_BEYOND := 0.65         # the aircraft rolls on this far past the far end, then turns onto the taxi route

var cap := 1                      # the hangar's capacity (the break-even landing count)
var landed := 0
var hangar := 0
var ties := 0
var overs := 0
var heli_n := 0
var dock_n := 0
var extra := 0
var over_slots := OVERS           # the overflow spots this airport has room for
var dock_slots := 0               # the docks (coastal only)
var heli_slots := 0
var tie_slots := TIES

## The average pay of an aircraft at airport `i` (its traffic mix).
static func mean_pay(i: int = -1) -> float:
	var mix: Dictionary = Airports.mix(i)
	var total := 0.0
	var pay := 0.0
	for t in mix:
		total += float(mix[t])
		pay += float(mix[t]) * Tuning.landing_pay(int(t))
	return pay / maxf(total, 0.0001)

## The shift's cost: the coins it must earn to break even (the first star's threshold). The hangar holds as many aircraft as it takes
## to pay it: the number of average landings that cover the cost.
static func shift_cost(i: int = -1) -> int:
	return int(Tuning.star_thresholds(i)[0])

static func capacity(i: int = -1) -> int:
	return maxi(ceili(float(shift_cost(i)) / mean_pay(i)), 1)

func reset(cap_: int, over_slots_: int, dock_slots_: int, heli_slots_: int, tie_slots_: int = TIES) -> void:
	cap = cap_
	tie_slots = clampi(tie_slots_, 0, TIES)
	over_slots = clampi(over_slots_, 0, OVERS)
	dock_slots = dock_slots_
	heli_slots = heli_slots_
	landed = 0
	hangar = 0
	ties = 0
	overs = 0
	heli_n = 0
	dock_n = 0
	extra = 0

## Where the next landed aircraft of `type` parks: {"kind": "hangar" | "tie" | "over" | "heli" | "dock" | "extra", "idx": slot}.
func place(type: int) -> Dictionary:
	landed += 1
	if hangar < cap:
		hangar += 1
		return {"kind": "hangar", "idx": hangar - 1}
	if type == Aircraft.Type.HELI and heli_n < heli_slots:
		heli_n += 1
		return {"kind": "heli", "idx": heli_n - 1}
	if type == Aircraft.Type.SEAPLANE and dock_n < dock_slots:
		dock_n += 1
		return {"kind": "dock", "idx": dock_n - 1}
	if ties < tie_slots:
		ties += 1
		return {"kind": "tie", "idx": ties - 1}
	if overs < over_slots:
		overs += 1
		return {"kind": "over", "idx": overs - 1}
	extra += 1
	return {"kind": "extra", "idx": extra - 1}

## Aircraft parked outside the hangar (all of it: tie-downs, grass, heli spot, dock and the "+N").
func on_ramp() -> int:
	return ties + overs + heli_n + dock_n + extra

func hangar_full() -> bool:
	return hangar >= cap

## The results card's line about it.
func summary() -> String:
	if hangar_full():
		return "Hangar full" + (" · %d on the ramp" % on_ramp() if on_ramp() > 0 else "")
	return "Hangar %d / %d" % [hangar, cap]

# ---------- Taxi routes ----------

## The no-go boxes of taxi routes: every runway, grown by `margin` all round: [centre, direction, half length, half width].
static func runway_boxes(margin: float) -> Array:
	var out: Array = []
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		out.append([Airports.rw_center(i), Vector2(sin(h), -cos(h)), Airports.rw_length(i) * 0.5 + margin, Airports.rw_width(i) * 0.5 + margin])
	return out

static func _hits_box(a: Vector2, b: Vector2, box: Array) -> bool:
	var dir: Vector2 = box[1]
	var n := Vector2(-dir.y, dir.x)
	var c: Vector2 = box[0]
	var la := Vector2((a - c).dot(dir), (a - c).dot(n))
	var lb := Vector2((b - c).dot(dir), (b - c).dot(n))
	var d := lb - la
	var t0 := 0.0
	var t1 := 1.0
	for ax in 2:
		var hi: float = box[2] if ax == 0 else box[3]
		var q := la[ax]
		var p := d[ax]
		if absf(p) < 0.000001:
			if q < -hi or q > hi:
				return false
		else:
			var ta := (-hi - q) / p
			var tb := (hi - q) / p
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	return true

## Does the straight segment a-b run over a runway (grown by `margin`)?
static func crosses_runway(a: Vector2, b: Vector2, margin: float = 0.0) -> bool:
	for box in runway_boxes(margin):
		if _hits_box(a, b, box):
			return true
	return false

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _edge_ok(a: Vector2, b: Vector2, boxes: Array) -> bool:
	for box in boxes:
		if _hits_box(a, b, box):
			return false
	for hz in Airports.hazards():
		if _seg_dist(hz["center"], a, b) < float(hz["radius"]) + 0.25:
			return false
	return true

static func _node_ok(p: Vector2, boxes: Array, half_w: float, half_h: float) -> bool:
	if absf(p.x) > half_w or absf(p.y) > half_h:
		return false
	for box in boxes:
		var dir: Vector2 = box[1]
		var rel: Vector2 = p - (box[0] as Vector2)
		if absf(rel.dot(dir)) < float(box[2]) - 0.01 and absf(rel.dot(Vector2(-dir.y, dir.x))) < float(box[3]) - 0.01:
			return false
	for hz in Airports.hazards():
		if p.distance_to(hz["center"]) < float(hz["radius"]) + 0.25:
			return false
	return true

## The shortest route from `from` to `to` that never crosses a runway (nor a mountain): straight when it can be, else around the
## corners of the runways' no-go boxes. Returns the points from `from` to `to`, or nothing if `to` cannot be reached.
static func route(from: Vector2, to: Vector2, margin: float = TAXI_MARGIN) -> PackedVector2Array:
	var boxes := runway_boxes(margin)
	var nodes: Array[Vector2] = [from, to]
	for box in boxes:
		var dir: Vector2 = box[1]
		var n := Vector2(-dir.y, dir.x)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p: Vector2 = (box[0] as Vector2) + dir * (float(box[2]) + 0.12) * sx + n * (float(box[3]) + 0.12) * sz
				if _node_ok(p, boxes, 5.6, 9.4):
					nodes.append(p)
	var n_count := nodes.size()
	var dist := PackedFloat32Array()
	dist.resize(n_count)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n_count)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n_count)
	dist[0] = 0.0
	for _step in n_count:
		var u := -1
		for k in n_count:
			if done[k] == 0 and (u < 0 or dist[k] < dist[u]):
				u = k
		if u < 0 or dist[u] == INF:
			break
		done[u] = 1
		if u == 1:
			break
		for k in n_count:
			if done[k] == 0 and _edge_ok(nodes[u], nodes[k], boxes):
				var nd := dist[u] + nodes[u].distance_to(nodes[k])
				if nd < dist[k]:
					dist[k] = nd
					prev[k] = u
	var out := PackedVector2Array()
	if dist[1] == INF:
		return out          # (no way there: the goal is inside a runway's no-go box)
	var chain: Array[int] = []
	var at := 1
	while at >= 0:
		chain.append(at)
		at = prev[at]
	for k in range(chain.size() - 1, -1, -1):
		out.append(nodes[chain[k]])
	return out

static func route_length(r: PackedVector2Array) -> float:
	var total := 0.0
	for k in r.size() - 1:
		total += r[k].distance_to(r[k + 1])
	return total

## The whole taxi route of an aircraft that rolled out at `far` (heading `dir`): on past the end, around the runways to `goal`,
## then the apron's `tail` to the spot.
static func taxi_route(far: Vector2, dir: Vector2, goal: Vector2, tail: PackedVector2Array, runway_exit: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(far)
	var start := far
	if runway_exit:
		start = far + dir * EXIT_BEYOND
		out.append(start)
	var mid := route(start, goal)
	if mid.is_empty():
		return mid
	for k in range(1, mid.size()):
		out.append(mid[k])
	out.append_array(tail)
	return out
