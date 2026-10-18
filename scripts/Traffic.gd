class_name Traffic
extends Node3D
## All the aircraft: the pool (built once), spawning, path following, holding patterns, landing,
## fuel and the conflict check. Everything here is plain arithmetic on pooled objects: a run
## allocates nothing.

signal landed(plane: Aircraft)
signal conflict(a: Aircraft, b: Aircraft)
signal fuel_out(plane: Aircraft)
signal cleared(plane: Aircraft)       # a path just reached its approach end
signal wrong_runway(plane: Aircraft)  # a path went for the other colour's runway
signal spawned(plane: Aircraft)

const MAX_POOL := 16
const PLANE_Y := 0.35
const FLASH_COLOR := Color(1.0, 0.12, 0.1)

var planes: Array[Aircraft] = []
var run_time := 0.0
var auto_spawn := true
var half_w := 5.0
var half_h := 8.9
var rng := RandomNumberGenerator.new()

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

## Put a plane on the field exactly as given (tests, and the spawner below).
func place(runway: int, pos: Vector2, heading: float, speed_class: int, low_fuel: bool, entered: bool = true) -> Aircraft:
	var p := _free_plane()
	if p == null:
		return null
	p.reset()
	p.state = Aircraft.State.FLY
	p.runway = runway
	p.speed_class = speed_class
	p.speed = Tuning.class_speed(speed_class)
	p.pos = pos
	p.heading = heading
	p.vis_heading = heading
	p.entered = entered
	p.low_fuel = low_fuel
	p.fuel_left = Tuning.lowfuel_seconds if low_fuel else 0.0
	var i := planes.find(p)
	_body_mats[i].albedo_color = Tuning.runway_colors[runway]
	_wing_mats[i].albedo_color = Tuning.runway_colors[runway].lerp(Color.WHITE, 0.35)
	var long: float = [0.85, 1.0, 1.3][speed_class]
	var span: float = [1.2, 1.0, 0.78][speed_class]
	_fuselages[i].scale = Vector3(1.0, 1.0, long)
	_wings[i].scale = Vector3(span, 1.0, 1.0)
	_nodes[i].visible = true
	_sync(p, i)
	return p

## A new plane from a random screen edge, heading in over the field, in a random runway's colour.
func spawn() -> Aircraft:
	var cls := _pick_class()
	for attempt in 8:
		var e := rng.randf() * (4.0 * half_w + 4.0 * half_h)
		var margin := 1.0
		var pos := Vector2.ZERO
		if e < 2.0 * half_w:
			pos = Vector2(-half_w + e, -half_h - margin)
		elif e < 4.0 * half_w:
			pos = Vector2(-half_w + e - 2.0 * half_w, half_h + margin)
		elif e < 4.0 * half_w + 2.0 * half_h:
			pos = Vector2(-half_w - margin, -half_h + e - 4.0 * half_w)
		else:
			pos = Vector2(half_w + margin, -half_h + e - 4.0 * half_w - 2.0 * half_h)
		if _crowded(pos):
			continue
		var target := Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-4.0, 4.0))
		var d := target - pos
		var p := place(rng.randi() % 2, pos, atan2(d.x, -d.y), cls, rng.randf() < Tuning.lowfuel_chance(run_time), false)
		if p != null:
			spawned.emit(p)
		return p
	return null

func _crowded(pos: Vector2) -> bool:
	for p in planes:
		if p.active() and p.pos.distance_to(pos) < Tuning.spawn_clear_distance:
			return true
	return false

func _pick_class() -> int:
	var r := rng.randf()
	var w: Array[float] = Tuning.speed_weights
	var total := w[0] + w[1] + w[2]
	r *= total
	if r < w[0]:
		return 0
	return 1 if r < w[0] + w[1] else 2

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
	if p.state == Aircraft.State.HOLD:
		p.state = Aircraft.State.FLY

## The finger is now at `world`: lay path points up to it. Returns true when the path has
## reached the plane's approach end (it is cleared to land; the drag is over).
func extend_path(p: Aircraft, world: Vector2) -> bool:
	if p.cleared:
		return true
	var last := p.last_point()
	var r := Tuning.approach_radius
	var thr := Tuning.runway_threshold(p.runway)
	if _dist_to_segment(thr, last, world) <= r:
		p.push(thr)
		p.push(Tuning.runway_end(p.runway))
		p.cleared = true
		cleared.emit(p)
		return true
	if not p.wrong_shown and _dist_to_segment(Tuning.runway_threshold(1 - p.runway), last, world) <= r:
		p.wrong_shown = true
		wrong_runway.emit(p)
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
	if auto_spawn:
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
		Aircraft.State.LANDING:
			p.roll_t += dt / Tuning.landing_roll_time
			var e := 1.0 - (1.0 - minf(p.roll_t, 1.0)) * (1.0 - minf(p.roll_t, 1.0))
			p.pos = p.roll_from.lerp(Tuning.runway_end(p.runway), e)
			p.ground = p.roll_t >= Tuning.touchdown_fraction
			if p.roll_t >= 1.0:
				landed.emit(p)
				_remove(p)
				return
	if not p.entered and absf(p.pos.x) < half_w - 0.2 and absf(p.pos.y) < half_h - 0.2:
		p.entered = true
	if p.low_fuel and p.state != Aircraft.State.LANDING and not _god:
		p.fuel_left -= dt
		if p.fuel_left <= 0.0:
			fuel_out.emit(p)
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
				p.heading = deg_to_rad(Tuning.runway_headings_deg[p.runway])
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

## Copy a plane's state onto its node (position, heading, size, low-fuel flash).
func _sync(p: Aircraft, i: int) -> void:
	var n := _nodes[i]
	var alt := 1.0 if p.state != Aircraft.State.LANDING else 1.0 - 0.35 * minf(p.roll_t / maxf(Tuning.touchdown_fraction, 0.01), 1.0)
	n.position = Vector3(p.pos.x, PLANE_Y * alt, p.pos.y)
	n.rotation.y = -p.vis_heading
	n.scale = Vector3.ONE * (0.9 + 0.1 * alt)
	var base: Color = Tuning.runway_colors[p.runway]
	var wing := base.lerp(Color.WHITE, 0.35)
	if p.low_fuel and p.state != Aircraft.State.LANDING:
		var frac := clampf(p.fuel_left / maxf(Tuning.lowfuel_seconds, 1.0), 0.0, 1.0)
		var hz := lerpf(Tuning.lowfuel_flash_hz_max, Tuning.lowfuel_flash_hz_min, frac)
		if sin(TAU * hz * p.age) > 0.0:
			base = FLASH_COLOR
			wing = Color.WHITE
	_body_mats[i].albedo_color = base
	_wing_mats[i].albedo_color = wing

## The pre-warm: every pooled plane drawn at once, alternating normal and flashing.
func prewarm_show() -> void:
	for i in MAX_POOL:
		var p := planes[i]
		p.reset()
		p.state = Aircraft.State.FLY
		p.runway = i % 2
		p.speed_class = i % 3
		p.pos = Vector2(-3.6 + (i % 4) * 2.4, -6.0 + (i / 4) * 3.0)
		p.heading = i * 0.4
		p.vis_heading = p.heading
		p.low_fuel = i % 3 == 0
		p.fuel_left = Tuning.lowfuel_seconds * 0.5
		p.age = i * 0.07
		p.entered = true
		_nodes[i].visible = true
		_fuselages[i].scale = Vector3(1.0, 1.0, [0.85, 1.0, 1.3][p.speed_class])
		_wings[i].scale = Vector3([1.2, 1.0, 0.78][p.speed_class], 1.0, 1.0)
		_sync(p, i)

func prewarm_hide() -> void:
	release_all()
