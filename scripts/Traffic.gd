class_name Traffic
extends Node3D
## All the aircraft: the pool (built once), spawning, path following, holding patterns, landing,
## timers and the conflict check. Everything here is plain arithmetic on pooled objects: a run
## allocates nothing.

signal landed(plane: Aircraft)
signal conflict(a: Aircraft, b: Aircraft)
signal timed_out(plane: Aircraft)   # its timer ran out: it is diverted (a strike)
signal cleared(plane: Aircraft)       # a path just reached its approach end
signal wrong_runway(plane: Aircraft, runway: int)  # a path went for another colour's runway
signal inactive_end(plane: Aircraft, runway: int, end: int)  # ...or for an end the wind doesn't allow
signal rerouted(plane: Aircraft)   # the wind shifted: its path now ends on a closed end
signal spawned(plane: Aircraft)
signal crashed(plane: Aircraft)        # flew into terrain (or, later, a storm)
signal go_around(plane: Aircraft)      # reached a runway that was still busy
signal runway_conflict(a: Aircraft, b: Aircraft)   # landed on a crossing runway while it was busy
signal refused(plane: Aircraft, text: String, at: Vector2)   # a path / tap the aircraft can't follow (with why)
signal appeared(plane: Aircraft)       # it just came on screen (first-time tips hook in here)

const MAX_POOL := 16
const MAX_HAZARDS := 16
const PLANE_Y := 0.35

var planes: Array[Aircraft] = []
var run_time := 0.0
var auto_spawn := true
var spawn_until := INF               # no new planes after this run time (the shift length)
var half_w := 5.0
var half_h := 8.9
var rng := RandomNumberGenerator.new()
var wind: Wind                       # which runway ends can be landed on (null = all)

## No-fly zones (terrain now, storms later): circles. kind 0 = terrain.
var hz_pos := PackedVector2Array()
var hz_r := PackedFloat32Array()
var hz_kind := PackedInt32Array()
var hz_count := 0

var _busy_until := PackedFloat32Array()   # per runway: run time until it is free
var _occupant: Array[Aircraft] = []
var _nodes: Array[Node3D] = []
var _fuselages: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _plane_groups: Array[Node3D] = []
var _glider_groups: Array[Node3D] = []
var _heli_groups: Array[Node3D] = []
var _float_groups: Array[Node3D] = []
var _rotors: Array[Node3D] = []
var _cand := PackedInt32Array()
var _body_mats: Array[StandardMaterial3D] = []
var _wing_mats: Array[StandardMaterial3D] = []
var _spawn_timer := 0.0
var _god := false

func _ready() -> void:
	rng.randomize()
	hz_pos.resize(MAX_HAZARDS)
	hz_r.resize(MAX_HAZARDS)
	hz_kind.resize(MAX_HAZARDS)
	_busy_until.resize(8)
	_cand.resize(16)
	for i in 8:
		_occupant.append(null)
	_god = DebugFlags.god_enabled()
	for i in MAX_POOL:
		planes.append(Aircraft.new())
		_build_node()

func _build_node() -> void:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	_nodes.append(root)
	var body := Prim.mat(Color.WHITE)
	var wing := Prim.mat(Color.WHITE)
	var dark := Prim.mat(Color(0.12, 0.16, 0.22))
	_body_mats.append(body)
	_wing_mats.append(wing)
	# The aircraft's nose points along local -z. Cylinders are stood on their side (x rotated 90 degrees).
	# --- planes (small / medium / jet / seaplane)
	var group := Node3D.new()
	root.add_child(group)
	_plane_groups.append(group)
	var fus := Node3D.new()
	group.add_child(fus)
	_fuselages.append(fus)
	var tube := Prim.cyl(fus, 0.15, 0.15, 1.1, 6, Vector3.ZERO, body)
	tube.rotation.x = deg_to_rad(90.0)
	var nose := Prim.cyl(fus, 0.0, 0.15, 0.42, 6, Vector3(0, 0, -0.76), body)
	nose.rotation.x = deg_to_rad(-90.0)
	Prim.box(fus, Vector3(0.15, 0.1, 0.3), Vector3(0, 0.15, -0.32), dark, false)
	var wing_root := Node3D.new()
	group.add_child(wing_root)
	_wings.append(wing_root)
	Prim.box(wing_root, Vector3(1.5, 0.07, 0.36), Vector3(0, 0.02, -0.08), wing)
	var tail := Node3D.new()
	group.add_child(tail)
	Prim.box(tail, Vector3(0.62, 0.06, 0.2), Vector3(0, 0.02, 0.5), wing)
	Prim.box(tail, Vector3(0.06, 0.26, 0.22), Vector3(0, 0.16, 0.5), body)
	var floats := Node3D.new()      # seaplane floats
	group.add_child(floats)
	_float_groups.append(floats)
	for sx in [-1.0, 1.0]:
		Prim.box(floats, Vector3(0.14, 0.1, 0.9), Vector3(sx * 0.4, -0.1, -0.08), body)
		Prim.box(floats, Vector3(0.05, 0.12, 0.05), Vector3(sx * 0.4, -0.02, -0.3), dark, false)
	# --- glider: slim body, very long thin wings, T-tail
	var glider := Node3D.new()
	root.add_child(glider)
	_glider_groups.append(glider)
	var gt := Prim.cyl(glider, 0.07, 0.05, 1.2, 5, Vector3.ZERO, body)
	gt.rotation.x = deg_to_rad(90.0)
	Prim.box(glider, Vector3(2.6, 0.04, 0.2), Vector3(0, 0.08, -0.15), wing)
	Prim.box(glider, Vector3(0.12, 0.1, 0.28), Vector3(0, 0.13, -0.35), dark, false)
	Prim.box(glider, Vector3(0.6, 0.04, 0.14), Vector3(0, 0.3, 0.55), wing)
	Prim.box(glider, Vector3(0.04, 0.3, 0.16), Vector3(0, 0.17, 0.55), body)
	# --- helicopter: stubby body, tail boom, a spinning rotor
	var heli := Node3D.new()
	root.add_child(heli)
	_heli_groups.append(heli)
	var hb := Prim.cyl(heli, 0.26, 0.26, 0.7, 6, Vector3(0, 0.05, -0.1), body)
	hb.rotation.x = deg_to_rad(90.0)
	Prim.box(heli, Vector3(0.3, 0.16, 0.22), Vector3(0, 0.1, -0.38), dark, false)
	Prim.box(heli, Vector3(0.1, 0.1, 0.8), Vector3(0, 0.08, 0.62), body)
	Prim.box(heli, Vector3(0.05, 0.3, 0.18), Vector3(0, 0.2, 0.98), wing)
	for sx in [-1.0, 1.0]:
		Prim.box(heli, Vector3(0.05, 0.05, 0.6), Vector3(sx * 0.24, -0.16, -0.1), dark, false)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 0.34, -0.1)
	heli.add_child(rotor)
	_rotors.append(rotor)
	Prim.box(rotor, Vector3(1.7, 0.03, 0.12), Vector3.ZERO, wing)
	Prim.box(rotor, Vector3(0.12, 0.03, 1.7), Vector3.ZERO, wing)

# ---------- Spawning ----------

func active_count() -> int:
	var n := 0
	for p in planes:
		if p.active():
			n += 1
	return n

func _free_plane() -> Aircraft:
	for p in planes:
		if not p.active():
			return p
	return null

## Put an aircraft on the field exactly as given (tests, and the spawner below). `target` is the index of the
## runway / helipad / lane it lands on (which one also gives its colour).
func place(target: int, pos: Vector2, heading: float, type: int, entered: bool = true) -> Aircraft:
	var p := _free_plane()
	if p == null:
		return null
	p.reset()
	p.state = Aircraft.State.FLY
	p.type = type
	p.tkind = Airports.kind_for(type)
	p.runway = target
	p.any_target = p.tkind != Aircraft.Kind.RUNWAY       # all helipads / lanes look alike
	p.speed_class = Tuning.type_speed_class(type)
	p.speed = Tuning.type_speed(type)
	p.timer_max = Tuning.type_timer(type) * Tuning.timer_mult()
	p.timer_left = p.timer_max
	p.pos = pos
	p.entry = pos
	p.heading = heading
	p.vis_heading = heading
	p.entered = entered
	var i := planes.find(p)
	_set_model(i, type, p.speed_class)
	_nodes[i].visible = true
	_sync(p, i)
	return p

## Make this the aircraft's `emergency` (short timer, any suitable runway) and / or `vip`.
func make_special(p: Aircraft, emergency: bool, vip: bool) -> void:
	p.emergency = emergency
	p.vip = vip
	if emergency:
		p.any_target = true
		p.timer_max = Tuning.type_timer(p.type) * Tuning.timer_mult() * Tuning.emergency_timer_mult
		p.timer_left = p.timer_max

## Show the right model for the type: stubby props / medium / long jets; floats for seaplanes; a glider; a helicopter.
func _set_model(i: int, type: int, cls: int) -> void:
	var is_plane := type != Aircraft.Type.GLIDER and type != Aircraft.Type.HELI
	_plane_groups[i].visible = is_plane
	_glider_groups[i].visible = type == Aircraft.Type.GLIDER
	_heli_groups[i].visible = type == Aircraft.Type.HELI
	_float_groups[i].visible = type == Aircraft.Type.SEAPLANE
	var long: float = [0.85, 1.0, 1.3][cls]
	var span: float = [1.2, 1.0, 0.78][cls]
	_fuselages[i].scale = Vector3(1.0, 1.0, long)
	_wings[i].scale = Vector3(span, 1.0, 1.0)

## A new plane from a random screen edge. It starts far enough out that it reaches the edge in
## Tuning.entry_warning_seconds, and the overlay shows a glow at that entry point until it appears.
func spawn() -> Aircraft:
	var type := _pick_type()
	var target := _pick_target(type)
	if target < 0:       # (e.g. no helipad here): an ordinary plane instead
		type = Aircraft.Type.SMALL
		target = _pick_target(type)
	var spec := Airports.specials()
	var emergency := type != Aircraft.Type.GLIDER and run_time >= Tuning.emergency_start_time and rng.randf() < Tuning.emergency_chance * spec
	var vip := not emergency and type != Aircraft.Type.GLIDER and rng.randf() < Tuning.vip_chance * spec
	var lined := Airports.kind_for(type) == Aircraft.Kind.RUNWAY and rng.randf() < Tuning.approach_bias()
	for attempt in 8:
		var e := rng.randf() * (4.0 * half_w + 4.0 * half_h)
		var entry := Vector2.ZERO
		var aim_override := Vector2.INF
		if lined and attempt < 4:       # Approach Control: come in along an active runway's approach line
			var line := _approach_line(target)
			if line[0] != Vector2.INF:
				entry = line[0]
				aim_override = line[1]
		var cx := half_w - 0.9
		var cz := half_h - 0.9
		if aim_override == Vector2.INF:
			if e < 2.0 * half_w:
				entry = Vector2(clampf(-half_w + e, -cx, cx), -half_h)
			elif e < 4.0 * half_w:
				entry = Vector2(clampf(-half_w + e - 2.0 * half_w, -cx, cx), half_h)
			elif e < 4.0 * half_w + 2.0 * half_h:
				entry = Vector2(-half_w, clampf(-half_h + e - 4.0 * half_w, -cz, cz))
			else:
				entry = Vector2(half_w, clampf(-half_h + e - 4.0 * half_w - 2.0 * half_h, -cz, cz))
		if _crowded(entry):
			continue
		var aim := Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-4.0, 4.0))
		if aim_override != Vector2.INF:
			aim = aim_override
		var dir := (aim - entry).normalized()
		if _hits_hazard(entry, dir):
			continue
		var dist := Tuning.type_speed(type) * Tuning.speed_mult(run_time) * Tuning.traffic_speed_mult() * Tuning.entry_lead()
		var p := place(target, entry - dir * dist, atan2(dir.x, -dir.y), type, false)
		if p != null:
			p.entry = entry
			make_special(p, emergency, vip)
			spawned.emit(p)
		return p
	return null

## Where an arrival lined up with `runway`'s active approach would enter the screen, and where it aims
## (a little off the threshold). [INF, INF] if no end of that runway is open.
func _approach_line(runway: int) -> Array[Vector2]:
	var ends := 0
	var pick := -1
	for e in 2:
		if wind == null or wind.is_active(runway, e):
			ends += 1
			if pick < 0 or rng.randf() < 0.5:
				pick = e
	if pick < 0 or ends == 0:
		return [Vector2.INF, Vector2.INF]
	var thr := Airports.end_threshold(runway, pick)
	var dir := Airports.end_dir(runway, pick)
	# Walk backwards along the approach until the ray leaves the screen.
	var t := INF
	for s in [-1.0, 1.0]:
		if absf(dir.x) > 0.0001:
			var tx: float = (thr.x - s * half_w) / dir.x
			if tx > 0.0:
				t = minf(t, tx)
		if absf(dir.y) > 0.0001:
			var ty: float = (thr.y - s * half_h) / dir.y
			if ty > 0.0:
				t = minf(t, ty)
	if t == INF:
		return [Vector2.INF, Vector2.INF]
	var side := Vector2(-dir.y, dir.x)
	return [thr - dir * t, thr + side * rng.randf_range(-0.6, 0.6)]

## Which runway / helipad / lane a new aircraft of this type is for (-1 if the airport has none that suit it).
func _pick_target(type: int) -> int:
	var kind := Airports.kind_for(type)
	var n := 0
	for i in Airports.land_count(kind):
		if kind != Aircraft.Kind.RUNWAY or Airports.suitable_runway(type, i):
			_cand[n] = i
			n += 1
	return -1 if n == 0 else _cand[rng.randi() % n]

## Would a straight flight from `from` along `dir` pass through a no-fly zone?
func _hits_hazard(from: Vector2, dir: Vector2) -> bool:
	for k in hz_count:
		if _dist_to_segment(hz_pos[k], from, from + dir * 40.0) < hz_r[k] + 0.9:
			return true
	return false

## Is `entry` too close to a plane on screen, or to another plane's entry point?
func _crowded(entry: Vector2) -> bool:
	for p in planes:
		if not p.active():
			continue
		var at := p.pos if p.entered else p.entry
		if at.distance_to(entry) < Tuning.spawn_clear_distance:
			return true
	return false

## A random aircraft type from the airport's mix.
func _pick_type() -> int:
	var mix: Dictionary = Airports.mix()
	var total := 0.0
	for k in mix:
		total += mix[k]
	var r := rng.randf() * total
	var last := Aircraft.Type.SMALL
	for k in mix:
		last = k
		r -= mix[k]
		if r <= 0.0:
			return k
	return last

# ---------- Player actions ----------

## The nearest plane the finger can grab, or null.
func pick(world: Vector2) -> Aircraft:
	var best: Aircraft = null
	var best_d := Tuning.tap_radius
	for p in planes:
		if p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD:
			if not p.entered:
				continue
			var d := p.pos.distance_to(world)
			if d <= best_d:
				best_d = d
				best = p
	return best

## A drag starts: the plane forgets its old route (a plane in a holding pattern leaves it). Returns false if
## the aircraft refuses (a glider only gets its first path).
func begin_path(p: Aircraft) -> bool:
	if p.type == Aircraft.Type.GLIDER and p.locked:
		refused.emit(p, "Glider: first path only", p.pos)
		return false
	p.clear_path()
	p.wrong_shown = false
	p.inactive_shown = false
	if p.state == Aircraft.State.HOLD:
		p.state = Aircraft.State.FLY
		p.hovering = false
	return true

## Is this end of this place open? (Runway ends depend on the wind; pads and lanes are always open.)
func _end_active(kind: int, idx: int, end: int) -> bool:
	return kind != Aircraft.Kind.RUNWAY or wind == null or wind.is_active(idx, end)

## The finger is now at `world`: lay path points up to it. Returns true when the path has
## reached an ACTIVE approach end of the place the aircraft lands on (it is cleared to land; the drag is over).
func extend_path(p: Aircraft, world: Vector2) -> bool:
	if p.cleared:
		return true
	var last := p.last_point()
	var kind := p.tkind
	var radius := Tuning.pad_capture_radius if kind == Aircraft.Kind.PAD else Tuning.approach_radius
	for idx in Airports.land_count(kind):
		if idx != p.runway and not p.any_target:
			continue
		if kind == Aircraft.Kind.RUNWAY and not Airports.suitable_runway(p.type, idx):
			continue
		for e in Airports.land_ends(kind):
			var thr := Airports.land_threshold(kind, idx, e)
			if _dist_to_segment(thr, last, world) <= radius:
				if _end_active(kind, idx, e):
					p.push(thr)
					p.push(Airports.land_far(kind, idx, e))
					p.cleared = true
					p.runway = idx
					p.land_end = e
					if p.type == Aircraft.Type.GLIDER:
						p.locked = true
					cleared.emit(p)
					return true
				elif not p.inactive_shown:
					p.inactive_shown = true
					inactive_end.emit(p, idx, e)
	if not p.wrong_shown:
		_check_refusals(p, last, world)
	var d := world - last
	var len := d.length()
	if len >= Tuning.path_spacing:
		var dir := d / len
		var k := 1
		while k * Tuning.path_spacing <= len:
			if not p.push(last + dir * (k * Tuning.path_spacing), 2):
				break
			k += 1
	return false

## The path went for a place this aircraft can't use: say why (once per drag).
func _check_refusals(p: Aircraft, last: Vector2, world: Vector2) -> void:
	for kind in 3:
		for idx in Airports.land_count(kind):
			for e in Airports.land_ends(kind):
				var radius := Tuning.pad_capture_radius if kind == Aircraft.Kind.PAD else Tuning.approach_radius
				var thr := Airports.land_threshold(kind, idx, e)
				if _dist_to_segment(thr, last, world) > radius:
					continue
				var text := ""
				if kind == Aircraft.Kind.RUNWAY:
					if p.tkind == Aircraft.Kind.PAD:
						text = "Helicopters land on the helipad"
					elif p.tkind == Aircraft.Kind.LANE:
						text = "Seaplanes land on water"
					elif p.type == Aircraft.Type.JET and not Airports.is_long(idx):
						text = "Too short for jets"
					elif idx != p.runway and not p.any_target:
						p.wrong_shown = true
						wrong_runway.emit(p, idx)
						return
				elif kind == Aircraft.Kind.PAD and p.tkind != Aircraft.Kind.PAD:
					text = "Helipad: helicopters only"
				elif kind == Aircraft.Kind.LANE and p.tkind != Aircraft.Kind.LANE:
					text = "Water lane: seaplanes only"
				if text != "":
					p.wrong_shown = true
					refused.emit(p, text, thr)
					return

## The wind shifted: aircraft cleared to land on an end that just closed lose that clearance. Their path
## stays (drawn dashed red) but no longer ends on the runway: the player has to draw a new one.
func reroute_closed_ends() -> int:
	var n := 0
	if wind == null:
		return 0
	for p in planes:
		if p.state == Aircraft.State.FLY and p.cleared and p.tkind == Aircraft.Kind.RUNWAY and not wind.is_active(p.runway, p.land_end):
			p.count = maxi(p.count - 2, 0)   # drop the approach end and the far end
			if p.count == 0:
				p.head = 0
			p.cleared = false
			p.path_invalid = true
			rerouted.emit(p)
			n += 1
	return n

## The finger lifted: finish the path at the finger. (A glider's first path is final.)
func end_path(p: Aircraft, world: Vector2) -> void:
	if not p.active():
		return
	if p.type == Aircraft.Type.GLIDER:
		p.locked = true
	if p.cleared:
		return
	if p.last_point().distance_to(world) > 0.05:
		p.push(world, 2)

## A tap: start (or stop) circling in place; a helicopter hovers instead. Gliders can't hold; a VIP that is
## held loses its bonus.
func toggle_hold(p: Aircraft) -> void:
	if p.cleared:
		return
	if p.type == Aircraft.Type.GLIDER:
		refused.emit(p, "Gliders can't hold", p.pos)
		return
	if p.state == Aircraft.State.HOLD:
		p.state = Aircraft.State.FLY
		p.hovering = false
		return
	if p.state != Aircraft.State.FLY:
		return
	p.clear_path()
	if p.vip and p.vip_ok:
		p.vip_ok = false
		refused.emit(p, "VIP delayed: bonus lost", p.pos)
	if p.type == Aircraft.Type.HELI:
		p.hovering = true
		p.hold_center = p.pos
	else:
		var dir := Vector2(sin(p.heading), -cos(p.heading))
		var right := Vector2(-dir.y, dir.x)          # clockwise on the screen
		p.hold_center = p.pos + right * Tuning.hold_radius_eff()
		p.hold_angle = (p.pos - p.hold_center).angle()
	p.state = Aircraft.State.HOLD

static func _dist_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.000001 else clampf((pt - a).dot(ab) / l2, 0.0, 1.0)
	return pt.distance_to(a + ab * t)

# ---------- Simulation ----------

## The current airport's terrain becomes the no-fly zones.
func load_terrain() -> void:
	hz_count = 0
	for h in Airports.hazards():
		add_hazard(h["center"], h["radius"], 0)

func add_hazard(c: Vector2, r: float, kind: int) -> int:
	if hz_count >= MAX_HAZARDS:
		return -1
	hz_pos[hz_count] = c
	hz_r[hz_count] = r
	hz_kind[hz_count] = kind
	hz_count += 1
	return hz_count - 1

func release_all() -> void:
	_busy_until.fill(0.0)
	for i in 8:
		_occupant[i] = null
	for i in MAX_POOL:
		planes[i].reset()
		_nodes[i].visible = false
	run_time = 0.0
	_spawn_timer = Tuning.first_spawn_delay

func step(delta: float) -> void:
	run_time += delta
	if auto_spawn and run_time < spawn_until:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			if active_count() < mini(int(Tuning.max_planes), MAX_POOL) and spawn() != null:
				_spawn_timer = Tuning.spawn_interval(run_time) * Airports.spawn_mult() * Tuning.traffic_spawn_mult() * rng.randf_range(0.75, 1.25)
			else:
				_spawn_timer = 0.25
	var mult := Tuning.speed_mult(run_time) * Tuning.traffic_speed_mult()
	for i in MAX_POOL:
		var p := planes[i]
		if not p.active():
			continue
		p.age += delta
		_move(p, delta, mult)
		if p.active():
			_sync(p, i)
	_check_conflicts()

func _move(p: Aircraft, dt: float, mult: float) -> void:
	var speed := p.speed * mult
	match p.state:
		Aircraft.State.FLY:
			if p.count > 0:
				_follow(p, speed * dt)
			else:
				_fly_straight(p, speed * dt, dt)
		Aircraft.State.HOLD:
			if p.hovering:
				pass          # a helicopter hovers: no movement at all
			else:
				_circle(p, speed, dt)
		Aircraft.State.DIVERT:
			var out := Vector2(sin(p.heading), -cos(p.heading))
			p.pos += out * speed * Tuning.divert_speed_mult * dt
			if absf(p.pos.x) > half_w + 2.5 or absf(p.pos.y) > half_h + 2.5:
				_remove(p)
				return
		Aircraft.State.LANDING:
			p.roll_t += dt / (Tuning.pad_land_seconds if p.tkind == Aircraft.Kind.PAD else Tuning.landing_roll_time)
			var e := 1.0 - (1.0 - minf(p.roll_t, 1.0)) * (1.0 - minf(p.roll_t, 1.0))
			p.pos = p.roll_from.lerp(Airports.land_far(p.tkind, p.runway, p.land_end), e)
			p.ground = p.roll_t >= Tuning.touchdown_fraction
			if p.roll_t >= 1.0:
				landed.emit(p)
				_remove(p)
				return
	if not p.entered and absf(p.pos.x) < half_w - 0.2 and absf(p.pos.y) < half_h - 0.2:
		p.entered = true
		appeared.emit(p)
	# The timer runs from the moment it is on screen; circling burns it more slowly.
	if p.entered and (p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD) and not _god:
		p.timer_left -= dt * (Tuning.hold_drain() if p.state == Aircraft.State.HOLD else 1.0)
		if p.timer_left <= 0.0:
			_divert(p)
			timed_out.emit(p)
	if p.entered and (p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD) and not _god:
		for k in hz_count:
			if p.pos.distance_to(hz_pos[k]) < hz_r[k] + Tuning.hazard_margin:
				crashed.emit(p)
				_remove(p)
				return
	var diff := wrapf(p.heading - p.vis_heading, -PI, PI)
	var turn := Tuning.plane_turn_rate * dt
	p.vis_heading += clampf(diff, -turn, turn)

func _circle(p: Aircraft, speed: float, dt: float) -> void:
	var hr := Tuning.hold_radius_eff()
	p.hold_angle += speed / hr * dt
	p.pos = p.hold_center + Vector2(cos(p.hold_angle), sin(p.hold_angle)) * hr
	p.heading = atan2(-sin(p.hold_angle), -cos(p.hold_angle))

func _follow(p: Aircraft, dist: float) -> void:
	var left := dist
	while left > 0.0 and p.count > 0:
		var to := p.pts[p.head] - p.pos
		var l := to.length()
		if l <= left:
			p.pos = p.pts[p.head]
			left -= l
			if l > 0.001:
				p.heading = atan2(to.x, -to.y)
			p.pop()
			if p.cleared and p.count == 1:        # reached the approach end: only the runway's far end is left
				if not _begin_landing(p):
					return
				p.clear_path()
				p.cleared = true
				p.state = Aircraft.State.LANDING
				p.roll_t = 0.0
				p.roll_from = p.pos
				if p.tkind != Aircraft.Kind.PAD:
					p.heading = deg_to_rad(Airports.land_heading_deg(p.tkind, p.runway, p.land_end))
				return
		else:
			p.pos += to / l * left
			p.heading = atan2(to.x, -to.y)
			left = 0.0

## The aircraft is at the approach end. If its runway is still busy it goes around; if a CROSSING runway is
## busy that is a runway conflict; otherwise the runway is taken for the landing roll. Returns true to land.
func _begin_landing(p: Aircraft) -> bool:
	if p.tkind != Aircraft.Kind.RUNWAY:
		return true
	var r := p.runway
	if run_time < _busy_until[r] and _occupant[r] != p:
		p.clear_path()
		go_around.emit(p)
		return false
	for j in Airports.rw_count():
		if j != r and Airports.runways_cross(r, j) and run_time < _busy_until[j] and _occupant[j] != null and _occupant[j] != p:
			runway_conflict.emit(p, _occupant[j])
			return false
	_busy_until[r] = run_time + Tuning.landing_roll_time + Tuning.runway_clear()
	_occupant[r] = p
	return true

func _fly_straight(p: Aircraft, dist: float, dt: float) -> void:
	if p.entered:
		var m := Tuning.edge_turn_margin
		var dir := Vector2(sin(p.heading), -cos(p.heading))
		if (absf(p.pos.x) > half_w - m or absf(p.pos.y) > half_h - m) and dir.dot(p.pos) > 0.0:
			var want := atan2(-p.pos.x, p.pos.y)
			var diff := wrapf(want - p.heading, -PI, PI)
			var t := dist / Tuning.edge_turn_radius
			p.heading += clampf(diff, -t, t)
	p.pos += Vector2(sin(p.heading), -cos(p.heading)) * dist

## Timer out: the aircraft leaves the airspace, away from the field.
func _divert(p: Aircraft) -> void:
	p.clear_path()
	p.state = Aircraft.State.DIVERT
	p.warn = 0.0
	p.timer_left = 0.0
	if p.pos.length() > 0.5:
		p.heading = atan2(p.pos.x, -p.pos.y)

func _remove(p: Aircraft) -> void:
	var i := planes.find(p)
	p.reset()
	_nodes[i].visible = false

func _check_conflicts() -> void:
	for p in planes:
		p.warn = 0.0
		p.warn_other = null
	var cd := Tuning.conflict_distance
	var wd := Tuning.warn_distance
	for i in MAX_POOL:
		var a := planes[i]
		if not a.can_conflict():
			continue
		for j in range(i + 1, MAX_POOL):
			var b := planes[j]
			if not b.can_conflict():
				continue
			var d := a.pos.distance_to(b.pos)
			if d < wd:
				var w := clampf((wd - d) / maxf(wd - cd, 0.01), 0.0, 1.0)
				if w > a.warn:
					a.warn = w
					a.warn_other = b
				if w > b.warn:
					b.warn = w
					b.warn_other = a
				if d < cd and not _god:
					conflict.emit(a, b)
					return

## Copy a plane's state onto its node (position, heading, size, colours, spinning rotor, emergency flash).
func _sync(p: Aircraft, i: int) -> void:
	var n := _nodes[i]
	var alt := 1.0 if p.state != Aircraft.State.LANDING else 1.0 - 0.35 * minf(p.roll_t / maxf(Tuning.touchdown_fraction, 0.01), 1.0)
	n.position = Vector3(p.pos.x, PLANE_Y * alt, p.pos.y)
	n.rotation.y = -p.vis_heading
	n.scale = Vector3.ONE * (0.9 + 0.1 * alt)
	var base := Airports.land_color(p.tkind, p.runway)
	var wing := base.lerp(Color.WHITE, 0.35)
	if p.emergency and p.state != Aircraft.State.LANDING and sin(TAU * 3.0 * p.age) > 0.0:
		base = Color(1.0, 0.12, 0.1)
		wing = Color.WHITE
	_body_mats[i].albedo_color = base
	_wing_mats[i].albedo_color = wing
	if p.type == Aircraft.Type.HELI:
		_rotors[i].rotation.y = p.age * 22.0

## The pre-warm: every pooled plane drawn at once, alternating normal and flashing.
func prewarm_show() -> void:
	var types := [Aircraft.Type.SMALL, Aircraft.Type.MEDIUM, Aircraft.Type.JET, Aircraft.Type.GLIDER, Aircraft.Type.HELI, Aircraft.Type.SEAPLANE]
	for i in MAX_POOL:
		var p := planes[i]
		p.reset()
		p.state = Aircraft.State.FLY
		p.type = types[i % 6]
		p.tkind = Airports.kind_for(p.type)
		p.runway = 0
		p.speed_class = Tuning.type_speed_class(p.type)
		p.timer_max = Tuning.type_timer(p.type)
		p.timer_left = p.timer_max * [1.0, 0.4, 0.15, 0.7][i % 4]   # every ring colour
		p.pos = Vector2(-3.6 + (i % 4) * 2.4, -6.0 + (i / 4) * 3.0)
		p.heading = i * 0.4
		p.vis_heading = p.heading
		p.age = i * 0.07
		p.entered = i % 4 != 3          # a few still outside: their entry glows are drawn (all three colours)
		p.entry = Vector2(-4.0 + (i % 3) * 4.0, -half_h) if i % 4 == 3 else p.pos
		p.emergency = i % 5 == 2
		p.vip = i % 5 == 4
		p.vip_ok = i % 10 != 4
		_nodes[i].visible = true
		_set_model(i, p.type, p.speed_class)
		_sync(p, i)

func prewarm_hide() -> void:
	release_all()
