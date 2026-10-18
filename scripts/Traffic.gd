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

const MAX_POOL := 16
const PLANE_Y := 0.35

var planes: Array[Aircraft] = []
var run_time := 0.0
var auto_spawn := true
var spawn_until := INF               # no new planes after this run time (the shift length)
var half_w := 5.0
var half_h := 8.9
var rng := RandomNumberGenerator.new()
var wind: Wind                       # which runway ends can be landed on (null = all)

var _nodes: Array[Node3D] = []
var _fuselages: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _body_mats: Array[StandardMaterial3D] = []
var _wing_mats: Array[StandardMaterial3D] = []
var _spawn_timer := 0.0
var _god := false

func _ready() -> void:
	rng.randomize()
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
	_body_mats.append(body)
	_wing_mats.append(wing)
	var fus := Node3D.new()
	root.add_child(fus)
	_fuselages.append(fus)
	# The plane's nose points along local -z. Cylinders are stood on their side (x rotated 90 degrees).
	var tube := Prim.cyl(fus, 0.15, 0.15, 1.1, 6, Vector3.ZERO, body)
	tube.rotation.x = deg_to_rad(90.0)
	var nose := Prim.cyl(fus, 0.0, 0.15, 0.42, 6, Vector3(0, 0, -0.76), body)
	nose.rotation.x = deg_to_rad(-90.0)
	Prim.box(fus, Vector3(0.15, 0.1, 0.3), Vector3(0, 0.15, -0.32), Prim.mat(Color(0.12, 0.16, 0.22)), false)
	var wing_root := Node3D.new()
	root.add_child(wing_root)
	_wings.append(wing_root)
	Prim.box(wing_root, Vector3(1.5, 0.07, 0.36), Vector3(0, 0.02, -0.08), wing)
	var tail := Node3D.new()
	root.add_child(tail)
	Prim.box(tail, Vector3(0.62, 0.06, 0.2), Vector3(0, 0.02, 0.5), wing)
	Prim.box(tail, Vector3(0.06, 0.26, 0.22), Vector3(0, 0.16, 0.5), body)

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

## Put an aircraft on the field exactly as given (tests, and the spawner below).
func place(runway: int, pos: Vector2, heading: float, type: int, entered: bool = true) -> Aircraft:
	var p := _free_plane()
	if p == null:
		return null
	p.reset()
	p.state = Aircraft.State.FLY
	p.runway = runway
	p.type = type
	p.speed_class = Tuning.type_speed_class(type)
	p.speed = Tuning.type_speed(type)
	p.timer_max = Tuning.type_timer(type)
	p.timer_left = p.timer_max
	p.pos = pos
	p.entry = pos
	p.heading = heading
	p.vis_heading = heading
	p.entered = entered
	var i := planes.find(p)
	_body_mats[i].albedo_color = Airports.rw_color(runway)
	_wing_mats[i].albedo_color = Airports.rw_color(runway).lerp(Color.WHITE, 0.35)
	_set_model(i, p.speed_class)
	_nodes[i].visible = true
	_sync(p, i)
	return p

## The look of the three models: stubby props, medium, long and swept jets.
func _set_model(i: int, cls: int) -> void:
	var long: float = [0.85, 1.0, 1.3][cls]
	var span: float = [1.2, 1.0, 0.78][cls]
	_fuselages[i].scale = Vector3(1.0, 1.0, long)
	_wings[i].scale = Vector3(span, 1.0, 1.0)

## A new plane from a random screen edge. It starts far enough out that it reaches the edge in
## Tuning.entry_warning_seconds, and the overlay shows a glow at that entry point until it appears.
func spawn() -> Aircraft:
	var type := _pick_type()
	for attempt in 8:
		var e := rng.randf() * (4.0 * half_w + 4.0 * half_h)
		var entry := Vector2.ZERO
		var cx := half_w - 0.9
		var cz := half_h - 0.9
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
		var target := Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-4.0, 4.0))
		var dir := (target - entry).normalized()
		var dist := Tuning.type_speed(type) * Tuning.speed_mult(run_time) * Tuning.entry_warning_seconds
		var p := place(rng.randi() % Airports.rw_count(), entry - dir * dist, atan2(dir.x, -dir.y), type, false)
		if p != null:
			p.entry = entry
			spawned.emit(p)
		return p
	return null

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

## A drag starts: the plane forgets its old route (a plane in a holding pattern leaves it).
func begin_path(p: Aircraft) -> void:
	p.clear_path()
	p.wrong_shown = false
	p.inactive_shown = false
	if p.state == Aircraft.State.HOLD:
		p.state = Aircraft.State.FLY

## The finger is now at `world`: lay path points up to it. Returns true when the path has
## reached an ACTIVE approach end of the plane's runway (it is cleared to land; the drag is over).
func extend_path(p: Aircraft, world: Vector2) -> bool:
	if p.cleared:
		return true
	var last := p.last_point()
	var r := Tuning.approach_radius
	for e in 2:
		if _dist_to_segment(Airports.end_threshold(p.runway, e), last, world) <= r:
			if wind == null or wind.is_active(p.runway, e):
				p.push(Airports.end_threshold(p.runway, e))
				p.push(Airports.end_far(p.runway, e))
				p.cleared = true
				p.land_end = e
				cleared.emit(p)
				return true
			elif not p.inactive_shown:
				p.inactive_shown = true
				inactive_end.emit(p, p.runway, e)
	if not p.wrong_shown:
		for k in Airports.rw_count():
			if k == p.runway:
				continue
			for e in 2:
				if _dist_to_segment(Airports.end_threshold(k, e), last, world) <= r:
					p.wrong_shown = true
					wrong_runway.emit(p, k)
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

## The wind shifted: aircraft cleared to land on an end that just closed lose that clearance. Their path
## stays (drawn dashed red) but no longer ends on the runway: the player has to draw a new one.
func reroute_closed_ends() -> int:
	var n := 0
	if wind == null:
		return 0
	for p in planes:
		if p.state == Aircraft.State.FLY and p.cleared and not wind.is_active(p.runway, p.land_end):
			p.count = maxi(p.count - 2, 0)   # drop the approach end and the far end
			if p.count == 0:
				p.head = 0
			p.cleared = false
			p.path_invalid = true
			rerouted.emit(p)
			n += 1
	return n

## The finger lifted: finish the path at the finger.
func end_path(p: Aircraft, world: Vector2) -> void:
	if p.cleared or not p.active():
		return
	if p.last_point().distance_to(world) > 0.05:
		p.push(world, 2)

## A tap: start (or stop) circling in place.
func toggle_hold(p: Aircraft) -> void:
	if p.cleared:
		return
	if p.state == Aircraft.State.HOLD:
		p.state = Aircraft.State.FLY
		return
	if p.state != Aircraft.State.FLY:
		return
	p.clear_path()
	var dir := Vector2(sin(p.heading), -cos(p.heading))
	var right := Vector2(-dir.y, dir.x)          # clockwise on the screen
	p.hold_center = p.pos + right * Tuning.hold_radius
	p.hold_angle = (p.pos - p.hold_center).angle()
	p.state = Aircraft.State.HOLD

static func _dist_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.000001 else clampf((pt - a).dot(ab) / l2, 0.0, 1.0)
	return pt.distance_to(a + ab * t)

# ---------- Simulation ----------

func release_all() -> void:
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
				_spawn_timer = Tuning.spawn_interval(run_time) * rng.randf_range(0.75, 1.25)
			else:
				_spawn_timer = 0.25
	var mult := Tuning.speed_mult(run_time)
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
			p.hold_angle += speed / Tuning.hold_radius * dt
			p.pos = p.hold_center + Vector2(cos(p.hold_angle), sin(p.hold_angle)) * Tuning.hold_radius
			p.heading = atan2(-sin(p.hold_angle), -cos(p.hold_angle))
		Aircraft.State.DIVERT:
			var out := Vector2(sin(p.heading), -cos(p.heading))
			p.pos += out * speed * Tuning.divert_speed_mult * dt
			if absf(p.pos.x) > half_w + 2.5 or absf(p.pos.y) > half_h + 2.5:
				_remove(p)
				return
		Aircraft.State.LANDING:
			p.roll_t += dt / Tuning.landing_roll_time
			var e := 1.0 - (1.0 - minf(p.roll_t, 1.0)) * (1.0 - minf(p.roll_t, 1.0))
			p.pos = p.roll_from.lerp(Airports.end_far(p.runway, p.land_end), e)
			p.ground = p.roll_t >= Tuning.touchdown_fraction
			if p.roll_t >= 1.0:
				landed.emit(p)
				_remove(p)
				return
	if not p.entered and absf(p.pos.x) < half_w - 0.2 and absf(p.pos.y) < half_h - 0.2:
		p.entered = true
	# The timer runs from the moment it is on screen; circling burns it more slowly.
	if p.entered and (p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD) and not _god:
		p.timer_left -= dt * (Tuning.hold_drain_mult if p.state == Aircraft.State.HOLD else 1.0)
		if p.timer_left <= 0.0:
			_divert(p)
			timed_out.emit(p)
	var diff := wrapf(p.heading - p.vis_heading, -PI, PI)
	var turn := Tuning.plane_turn_rate * dt
	p.vis_heading += clampf(diff, -turn, turn)

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
				p.clear_path()
				p.cleared = true
				p.state = Aircraft.State.LANDING
				p.roll_t = 0.0
				p.roll_from = p.pos
				p.heading = deg_to_rad(Airports.end_heading_deg(p.runway, p.land_end))
				return
		else:
			p.pos += to / l * left
			p.heading = atan2(to.x, -to.y)
			left = 0.0

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

## Copy a plane's state onto its node (position, heading, size, colours).
func _sync(p: Aircraft, i: int) -> void:
	var n := _nodes[i]
	var alt := 1.0 if p.state != Aircraft.State.LANDING else 1.0 - 0.35 * minf(p.roll_t / maxf(Tuning.touchdown_fraction, 0.01), 1.0)
	n.position = Vector3(p.pos.x, PLANE_Y * alt, p.pos.y)
	n.rotation.y = -p.vis_heading
	n.scale = Vector3.ONE * (0.9 + 0.1 * alt)
	_body_mats[i].albedo_color = Airports.rw_color(p.runway)
	_wing_mats[i].albedo_color = Airports.rw_color(p.runway).lerp(Color.WHITE, 0.35)

## The pre-warm: every pooled plane drawn at once, alternating normal and flashing.
func prewarm_show() -> void:
	for i in MAX_POOL:
		var p := planes[i]
		p.reset()
		p.state = Aircraft.State.FLY
		p.runway = i % Airports.rw_count()
		p.type = [Aircraft.Type.SMALL, Aircraft.Type.MEDIUM, Aircraft.Type.JET][i % 3]
		p.speed_class = Tuning.type_speed_class(p.type)
		p.timer_max = Tuning.type_timer(p.type)
		p.timer_left = p.timer_max * [1.0, 0.4, 0.15, 0.7][i % 4]   # every ring colour
		p.pos = Vector2(-3.6 + (i % 4) * 2.4, -6.0 + (i / 4) * 3.0)
		p.heading = i * 0.4
		p.vis_heading = p.heading
		p.age = i * 0.07
		p.entered = i % 4 != 3          # a few still outside: their entry glows are drawn (all three colours)
		p.entry = Vector2(-4.0 + (i % 3) * 4.0, -half_h) if i % 4 == 3 else p.pos
		_nodes[i].visible = true
		_set_model(i, p.speed_class)
		_sync(p, i)

func prewarm_hide() -> void:
	release_all()
