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
signal crashed(plane: Aircraft, kind: int)   # flew into terrain (kind 0) or a storm cell (kind 1)
signal go_around_warned(plane: Aircraft, reason: int)   # a go-around is coming in a second (the plane wobbles)
signal go_around_cancelled(plane: Aircraft)   # ...and the player redrew a cleaner final in time
signal go_around(plane: Aircraft, reason: int)   # climbing out: the runway was busy, or the approach was poor (Approach.Reason)
signal runway_conflict(a: Aircraft, b: Aircraft)   # landed on a crossing runway while it was busy
signal refused(plane: Aircraft, text: String, at: Vector2)   # a path / tap the aircraft can't follow (with why)
signal appeared(plane: Aircraft)       # it just came on screen (first-time tips hook in here)
signal snapped(plane: Aircraft, at: Vector2)   # a path locked onto a runway's extended centreline
signal touchdown(plane: Aircraft)      # the wheels just touched the runway (dust puff, a little pop)

const MAX_POOL := 16
const RAMP_MODELS := 24                # extra, complete aircraft models for the ramp: the ones that landed, taxiing and parked (see ramp_claim)
var pool_n := MAX_POOL                  # (the menu's scenic traffic keeps a small pool)
var go_around_warns := 0                # (statistics for the sims) warned / cancelled go-arounds this shift
var go_around_cancels := 0
var shadow_scale := 1.0                 # the aircraft's shadow offsets grow over a shift (see Shadow.offset_scale)
var scenic := false                     # the menu diorama: no timers, conflicts or random go-arounds
const MAX_HAZARDS := 16
const PLANE_Y := 0.35
const TOUCH_POP := 0.3
const TRAIL_N := 8                     # contrail puffs kept per aircraft
const TRAIL_EVERY := 0.1               # seconds between puffs
const MAX_BANK := 0.5                  # radians

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
var hz_vel := PackedVector2Array()        # storm cells drift
var hz_count := 0
var fog_amount := 0.0                     # 0..1, how thick the fog is right now
var fog_target := 0.0

var _busy_until := PackedFloat32Array()   # per runway: run time until it is free
var _last_td := PackedFloat32Array()      # per runway: run time of the last touchdown there
var approach := Approach.new()           # scratch approach scorer (one object, reused)
var go_rng := RandomNumberGenerator.new()   # the go-around dice (kept apart from the spawn draws)
var _occupant: Array[Aircraft] = []
var _nodes: Array[Node3D] = []
var _fuselages: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _plane_groups: Array[Node3D] = []
var _glider_groups: Array[Node3D] = []
var _jet_groups: Array[Node3D] = []
var _rotor_discs: Array[MeshInstance3D] = []
var _badges: Array[Node3D] = []
var _heli_groups: Array[Node3D] = []
var _float_groups: Array[Node3D] = []
var _rotors: Array[Node3D] = []
var _fus_mats: Array[StandardMaterial3D] = []       # per aircraft: the fuselage (white, or the livery's body colour)
var _heli_mats: Array[StandardMaterial3D] = []      # per aircraft: the helicopter's body (the runway's colour, or the livery's body colour)
var _stripe_mats: Array[StandardMaterial3D] = []
var _stripes: Array = []                  # per aircraft: the stripe boxes (shown for a custom livery)
var livery := 0                          # index into Cosmetics.LIVERIES
var _cand := PackedInt32Array()
var _draws := PackedFloat32Array()      # every random number a spawn() call may need, drawn up front
var all_students := false               # Bad Pilot Day: every aircraft is a student pilot
var grace_until := 0.0                  # run time until which conflicts are ignored (after an ad-continue)
var _body_mats: Array[StandardMaterial3D] = []
var _wing_mats: Array[StandardMaterial3D] = []
var beats: Array = []                  # the airport's intro beats for this shift: [[seconds, type], ...]
var _beat := 0
var _spawn_timer := 0.0
var _god := false
var _dt := 0.0                         # the step in progress (0 outside a step: animation holds)
var _shadows: Array[MeshInstance3D] = []
var _shadow_mats: Array[ShaderMaterial] = []
var _shadow_size: Array[Vector2] = []
var _prop_discs: Array[MeshInstance3D] = []
var _trail: MultiMeshInstance3D
var _trail_mm: MultiMesh
var _trail_pos := PackedVector2Array()
var _trail_y := PackedFloat32Array()
var _trail_age := PackedFloat32Array()
var _trail_peak := PackedFloat32Array()   # opacity a puff starts at (0 = unused)
var _trail_head := PackedInt32Array()
var _trail_clock := PackedFloat32Array()
var _ramp_first := 0                  # index of the first ramp model in the model arrays (_nodes, _body_mats...)
var _ramp_used := PackedByteArray()
var _ramp_shadows: Array[MeshInstance3D] = []

func _ready() -> void:
	rng.randomize()
	hz_pos.resize(MAX_HAZARDS)
	hz_r.resize(MAX_HAZARDS)
	hz_kind.resize(MAX_HAZARDS)
	hz_vel.resize(MAX_HAZARDS)
	_busy_until.resize(8)
	_last_td.resize(8)
	_last_td.fill(-1000.0)
	go_rng.randomize()
	_cand.resize(16)
	_draws.resize(40)
	for i in 8:
		_occupant.append(null)
	_god = DebugFlags.god_enabled() or scenic
	for i in pool_n:
		planes.append(Aircraft.new())
		_build_node()
	for n in _nodes:
		Prim.lift(n)          # (aircraft are drawn above the fog)
	_build_extras()
	_ramp_first = _nodes.size()
	if not scenic:
		_ramp_used.resize(RAMP_MODELS)
		for k in RAMP_MODELS:
			_build_node()
			var sh := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(1.0, 1.0)
			sh.mesh = pm
			sh.material_override = Shadow.material(Shadow.plane(), 0.9)
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_nodes[_ramp_first + k].add_child(sh)
			_ramp_shadows.append(sh)

## Soft drop shadows (one quad each) and the contrails (one MultiMesh of round puffs for the whole pool).
func _build_extras() -> void:
	var sh := preload("res://shaders/shadow_blob.gdshader")
	for i in pool_n:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		mi.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = 3          # after the runways and aircraft (which sit at 2): depth-tested, so planes cover their own shadow
		m.set_shader_parameter("alpha", Shadow.ALPHA)
		m.set_shader_parameter("tex", Shadow.plane())
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_shadows.append(mi)
		_shadow_mats.append(m)
		_shadow_size.append(Vector2(1.5, 1.5))
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	var qm := PlaneMesh.new()
	qm.size = Vector2(1.0, 1.0)
	_trail_mm.mesh = qm
	_trail_mm.instance_count = pool_n * TRAIL_N
	_trail_mm.visible_instance_count = 0
	_trail = MultiMeshInstance3D.new()
	_trail.multimesh = _trail_mm
	var tm := ShaderMaterial.new()
	tm.shader = preload("res://shaders/puff.gdshader")
	tm.render_priority = 3
	_trail.material_override = tm
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	var n := pool_n * TRAIL_N
	_trail_pos.resize(n)
	_trail_y.resize(n)
	_trail_age.resize(n)
	_trail_peak.resize(n)
	_trail_head.resize(pool_n)
	_trail_clock.resize(pool_n)
	for k in n:
		_trail_age[k] = 99.0

## One pooled aircraft model (built once; only visibility, colours and transforms change in a run). Sunny Airfield: white
## bodies with the runway's colour on the nose cap, wingtips and fin (always), and the airline livery's colours on the fuselage and the stripe only; distinct silhouettes for the light
## plane, the swept-wing jet, the helicopter, the long-winged glider and the seaplane with floats; a prop disc on the prop
## planes, a rotor disc on the helicopter, and an orange "L" badge on a student pilot's wing.
## (`_body_mats` is the livery colour: it is what the emergency flash and the runway colour paint.)
func _build_node() -> void:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	_nodes.append(root)
	var white := Prim.mat(Color(0.97, 0.98, 1.0))
	var body := Prim.mat(Color.WHITE)               # livery colour: nose cap, stripe, helicopter body
	var wing := Prim.mat(Color(0.97, 0.98, 1.0))
	var dark := Prim.mat(Color(0.17, 0.29, 0.48))      # canopy
	var glass := Prim.mat(Color(0.62, 0.77, 1.0))
	var grey := Prim.mat(Color(0.8, 0.83, 0.89))       # floats, engines
	var fusm := Prim.mat(Color.WHITE)               # the fuselage: white, or the livery's body colour
	var helim := Prim.mat(Color.WHITE)              # the helicopter's body
	var stripem := Prim.mat(Color.WHITE)
	var stripe_boxes: Array[MeshInstance3D] = []
	_body_mats.append(body)
	_wing_mats.append(wing)
	_fus_mats.append(fusm)
	_heli_mats.append(helim)
	_stripe_mats.append(stripem)
	# The aircraft's nose points along local -z. Cylinders are stood on their side (x rotated 90 degrees).
	# --- light planes (small / medium / seaplane): straight wings, a prop disc, a tail with a coloured fin
	var group := Node3D.new()
	root.add_child(group)
	_plane_groups.append(group)
	var fus := Node3D.new()
	group.add_child(fus)
	_fuselages.append(fus)
	var tube := Prim.cyl(fus, 0.15, 0.15, 1.1, 8, Vector3.ZERO, fusm)
	tube.rotation.x = deg_to_rad(90.0)
	var nose := Prim.cyl(fus, 0.0, 0.15, 0.42, 8, Vector3(0, 0, -0.76), body)
	nose.rotation.x = deg_to_rad(-90.0)
	Prim.box(fus, Vector3(0.15, 0.1, 0.3), Vector3(0, 0.15, -0.32), dark, false)
	Prim.box(fus, Vector3(0.05, 0.04, 0.12), Vector3(-0.02, 0.2, -0.36), glass, false)
	var disc_m := StandardMaterial3D.new()          # propeller blur: a pale translucent disc at the nose
	disc_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_m.albedo_color = Color(1, 1, 1, 0.3)
	disc_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := Prim.cyl(fus, 0.3, 0.3, 0.015, 14, Vector3(0, 0, -0.98), disc_m, false)
	disc.rotation.x = deg_to_rad(90.0)
	_prop_discs.append(disc)
	var wing_root := Node3D.new()
	group.add_child(wing_root)
	_wings.append(wing_root)
	Prim.box(wing_root, Vector3(1.5, 0.07, 0.36), Vector3(0, 0.02, -0.08), wing)
	stripe_boxes.append(Prim.box(wing_root, Vector3(1.4, 0.075, 0.07), Vector3(0, 0.022, -0.1), stripem, false))
	for sx in [-1.0, 1.0]:
		Prim.box(wing_root, Vector3(0.16, 0.078, 0.37), Vector3(sx * 0.67, 0.02, -0.08), body, false)       # wingtips: always the runway's colour
	var tail := Node3D.new()
	group.add_child(tail)
	Prim.box(tail, Vector3(0.62, 0.06, 0.2), Vector3(0, 0.02, 0.5), wing)
	Prim.box(tail, Vector3(0.06, 0.26, 0.22), Vector3(0, 0.16, 0.5), body)
	stripe_boxes.append(Prim.box(fus, Vector3(0.07, 0.03, 0.95), Vector3(0, 0.155, 0.02), stripem, false))
	var floats := Node3D.new()      # seaplane floats
	group.add_child(floats)
	_float_groups.append(floats)
	for sx in [-1.0, 1.0]:
		Prim.box(floats, Vector3(0.14, 0.1, 0.9), Vector3(sx * 0.4, -0.1, -0.08), grey)
		Prim.box(floats, Vector3(0.05, 0.12, 0.05), Vector3(sx * 0.4, -0.02, -0.3), dark, false)
	# --- jet: a long body, swept-back wings with engine pods, a swept tail with the coloured fin
	var jet := Node3D.new()
	root.add_child(jet)
	_jet_groups.append(jet)
	var jt := Prim.cyl(jet, 0.13, 0.13, 1.5, 8, Vector3.ZERO, fusm)
	jt.rotation.x = deg_to_rad(90.0)
	var jn := Prim.cyl(jet, 0.0, 0.13, 0.5, 8, Vector3(0, 0, -0.98), body)
	jn.rotation.x = deg_to_rad(-90.0)
	Prim.box(jet, Vector3(0.12, 0.07, 0.2), Vector3(0, 0.12, -0.62), dark, false)
	for sx in [-1.0, 1.0]:
		var sw := Prim.box(jet, Vector3(0.82, 0.05, 0.3), Vector3(sx * 0.44, 0.0, 0.1), wing)
		sw.rotation.y = deg_to_rad(sx * 26.0)
		Prim.box(sw, Vector3(0.14, 0.054, 0.31), Vector3(sx * 0.34, 0.0, 0.0), body, false)       # wingtip: the runway's colour
		var eng := Prim.cyl(jet, 0.07, 0.07, 0.3, 6, Vector3(sx * 0.42, -0.04, -0.02), grey)
		eng.rotation.x = deg_to_rad(90.0)
		var ts := Prim.box(jet, Vector3(0.36, 0.04, 0.16), Vector3(sx * 0.2, 0.02, 0.68), body)
		ts.rotation.y = deg_to_rad(sx * 24.0)
	Prim.box(jet, Vector3(0.06, 0.28, 0.24), Vector3(0, 0.17, 0.66), body)
	stripe_boxes.append(Prim.box(jet, Vector3(0.06, 0.03, 1.15), Vector3(0, 0.13, 0.08), stripem, false))
	# --- glider: slim body, very long thin wings with coloured tips, T-tail
	var glider := Node3D.new()
	root.add_child(glider)
	_glider_groups.append(glider)
	var gt := Prim.cyl(glider, 0.07, 0.05, 1.2, 6, Vector3.ZERO, fusm)
	gt.rotation.x = deg_to_rad(90.0)
	Prim.box(glider, Vector3(2.6, 0.04, 0.2), Vector3(0, 0.08, -0.15), wing)
	for sx in [-1.0, 1.0]:
		Prim.box(glider, Vector3(0.3, 0.045, 0.2), Vector3(sx * 1.15, 0.08, -0.15), body, false)       # wingtips: the runway's colour
	Prim.box(glider, Vector3(0.12, 0.1, 0.28), Vector3(0, 0.13, -0.35), glass, false)
	Prim.box(glider, Vector3(0.6, 0.04, 0.14), Vector3(0, 0.3, 0.55), wing)
	Prim.box(glider, Vector3(0.04, 0.3, 0.16), Vector3(0, 0.17, 0.55), body)
	stripe_boxes.append(Prim.box(glider, Vector3(0.06, 0.03, 0.9), Vector3(0, 0.1, 0.05), stripem, false))
	# --- helicopter: a coloured stubby body, glass bubble, tail boom, a spinning rotor under a pale rotor disc
	var heli := Node3D.new()
	root.add_child(heli)
	_heli_groups.append(heli)
	var hb := Prim.cyl(heli, 0.26, 0.26, 0.7, 8, Vector3(0, 0.05, -0.1), helim)
	hb.rotation.x = deg_to_rad(90.0)
	Prim.box(heli, Vector3(0.3, 0.16, 0.22), Vector3(0, 0.12, -0.38), glass, false)
	Prim.box(heli, Vector3(0.1, 0.1, 0.8), Vector3(0, 0.08, 0.62), body)
	Prim.box(heli, Vector3(0.05, 0.3, 0.18), Vector3(0, 0.2, 0.98), body)
	for sx in [-1.0, 1.0]:
		Prim.box(heli, Vector3(0.05, 0.05, 0.6), Vector3(sx * 0.24, -0.16, -0.1), white, false)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 0.34, -0.1)
	heli.add_child(rotor)
	_rotors.append(rotor)
	Prim.box(rotor, Vector3(1.7, 0.03, 0.12), Vector3.ZERO, wing)
	Prim.box(rotor, Vector3(0.12, 0.03, 1.7), Vector3.ZERO, wing)
	var rotor_disc := Prim.cyl(heli, 0.88, 0.88, 0.01, 18, Vector3(0, 0.33, -0.1), disc_m, false)
	_rotor_discs.append(rotor_disc)
	# --- the student pilot's "L": an orange badge on the right wing (all types), white strokes
	var badge := Node3D.new()
	badge.position = Vector3(0.52, 0.12, -0.05)
	root.add_child(badge)
	_badges.append(badge)
	Prim.box(badge, Vector3(0.3, 0.03, 0.3), Vector3.ZERO, Prim.mat(Color("ff9f2e")), false)
	var lm := Prim.mat(Color.WHITE)
	Prim.box(badge, Vector3(0.06, 0.04, 0.2), Vector3(-0.05, 0.0, 0.0), lm, false)
	Prim.box(badge, Vector3(0.15, 0.04, 0.06), Vector3(0.0, 0.0, 0.07), lm, false)
	badge.visible = false
	_stripes.append(stripe_boxes)

# ---------- Spawning ----------

## Aircraft still to land or be lost (a diverting one counts as lost).
func remaining() -> int:
	var n := 0
	for p in planes:
		if p.state != Aircraft.State.IDLE and p.state != Aircraft.State.DIVERT:
			n += 1
	return n

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
	p.prev_vis = heading
	p.entered = entered
	var i := planes.find(p)
	_set_model(i, type, p.speed_class)
	_nodes[i].visible = true
	_sync(p, i)
	return p

## Set a material's colour only when it changes: writing a material parameter every frame re-uploads it, and with a dozen aircraft
## times three colours that is churn a phone's browser does not need.
func _paint(m: StandardMaterial3D, c: Color) -> void:
	if m.albedo_color != c:
		m.albedo_color = c

## Paint every aircraft in an airline livery (the fuselage's body colour and the stripe; the standard one has neither).
func set_livery(index: int) -> void:
	livery = index
	for i in range(_ramp_first, _nodes.size()):
		for box in _stripes[i]:
			box.visible = Cosmetics.LIVERIES[livery]["stripe"] != null
	for i in pool_n:
		for box in _stripes[i]:
			box.visible = Cosmetics.LIVERIES[livery]["stripe"] != null          # (the standard livery has no coloured stripe)
		var p := planes[i]
		if p.active():
			_sync(p, i)

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
	var is_plane := type != Aircraft.Type.GLIDER and type != Aircraft.Type.HELI and type != Aircraft.Type.JET
	_plane_groups[i].visible = is_plane
	_jet_groups[i].visible = type == Aircraft.Type.JET
	_rotor_discs[i].visible = type == Aircraft.Type.HELI
	_glider_groups[i].visible = type == Aircraft.Type.GLIDER
	_heli_groups[i].visible = type == Aircraft.Type.HELI
	_float_groups[i].visible = type == Aircraft.Type.SEAPLANE
	_prop_discs[i].visible = type == Aircraft.Type.SMALL or type == Aircraft.Type.MEDIUM or type == Aircraft.Type.SEAPLANE
	var long: float = [0.85, 1.0, 1.3][cls]
	var span: float = [1.2, 1.0, 0.78][cls]
	_fuselages[i].scale = Vector3(1.0, 1.0, long)
	_wings[i].scale = Vector3(span, 1.0, 1.0)
	_jet_groups[i].scale = Vector3(1.0, 1.0, 0.9 + 0.1 * long)
	if i < _shadow_size.size():
		match type:
			Aircraft.Type.GLIDER:
				_shadow_size[i] = Vector2(2.7, 1.5)
			Aircraft.Type.HELI:
				_shadow_size[i] = Vector2(1.5, 1.5)
			_:
				_shadow_size[i] = Vector2(1.5 * span, 1.35 * long)

## A new plane from a random screen edge. It starts far enough out that it reaches the edge in
## Tuning.entry_warning_seconds, and the overlay shows a glow at that entry point until it appears.
func spawn(force_type: int = -1) -> Aircraft:
	# Every call draws the same number of random values, so a seeded run (the daily shift) always produces the
	# same sequence of arrivals, whatever the player did in between.
	for k in 40:
		_draws[k] = rng.randf()
	var type := _pick_type(_draws[0]) if force_type < 0 else force_type
	var target := _pick_target(type, _draws[1])
	if target < 0:       # (e.g. no helipad here): an ordinary plane instead
		type = Aircraft.Type.SMALL
		target = _pick_target(type, _draws[1])
	var spec := Tuning.specials_mult()
	var emergency := type != Aircraft.Type.GLIDER and run_time >= Tuning.emergency_start_time and _draws[2] < Tuning.emergency_chance * spec
	var vip := not emergency and type != Aircraft.Type.GLIDER and _draws[3] < Tuning.vip_chance * spec
	var lined := Airports.kind_for(type) == Aircraft.Kind.RUNWAY and _draws[4] < Tuning.approach_bias()
	for attempt in 8:
		var e := _draws[5 + attempt * 3] * (4.0 * half_w + 4.0 * half_h)
		var entry := Vector2.ZERO
		var aim_override := Vector2.INF
		if lined and attempt < 4:       # Approach Control: come in along an active runway's approach line
			var line := _approach_line(target, _draws[29], _draws[30])
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
		if _crowded(entry) or Airfield.in_hud(entry):       # (not under the interface: the pause button, the pill, the wind card)
			continue
		var aim := Vector2(lerpf(-2.5, 2.5, _draws[6 + attempt * 3]), lerpf(-4.0, 4.0, _draws[7 + attempt * 3]))
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
			if not emergency:
				p.student = all_students or (not vip and p.tkind == Aircraft.Kind.RUNWAY and type != Aircraft.Type.GLIDER and _draws[31] < Tuning.student_chance)
			spawned.emit(p)
		return p
	return null

## Where an arrival lined up with `runway`'s active approach would enter the screen, and where it aims
## (a little off the threshold). [INF, INF] if no end of that runway is open.
func _approach_line(runway: int, r_end: float, r_jitter: float) -> Array[Vector2]:
	var ends := 0
	var pick := -1
	for e in 2:
		if wind == null or wind.is_active(runway, e):
			ends += 1
			if pick < 0 or r_end < 0.5:
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
	return [thr - dir * t, thr + side * lerpf(-0.6, 0.6, r_jitter)]

## Which runway / helipad / lane a new aircraft of this type is for (-1 if the airport has none that suit it).
func _pick_target(type: int, r: float) -> int:
	var kind := Airports.kind_for(type)
	var n := 0
	for i in Airports.land_count(kind):
		if kind != Aircraft.Kind.RUNWAY or Airports.suitable_runway(type, i):
			_cand[n] = i
			n += 1
	return -1 if n == 0 else _cand[mini(int(r * n), n - 1)]

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

## An aircraft type from the airport's mix (`r` is a random number 0..1).
func _pick_type(r: float) -> int:
	var mix: Dictionary = Airports.mix()
	var total := 0.0
	for k in mix:
		total += mix[k]
	var x := r * total
	var last := Aircraft.Type.SMALL
	for k in mix:
		last = k
		x -= mix[k]
		if x <= 0.0:
			return k
	return last

# ---------- Player actions ----------

## The nearest plane the finger can grab, or null.
func pick(world: Vector2) -> Aircraft:
	var best: Aircraft = null
	var best_d := Tuning.tap_radius
	for p in planes:
		if p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD:
			if not p.entered or p.fogged:
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
	if p.ga_pending:
		p.ga_redrawn = true
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
## The finger is at `raw`; the path follows `world` (the finger's smoothed position).
func extend_path(p: Aircraft, world: Vector2, raw: Vector2 = Vector2(INF, INF)) -> bool:
	if p.cleared:
		return true
	if raw.x == INF:
		raw = world
	var last := p.last_point()
	var kind := p.tkind
	if kind != Aircraft.Kind.PAD and _try_snap(p, last, raw):
		return true
	var radius := Tuning.pad_capture_radius if kind == Aircraft.Kind.PAD else Tuning.approach_radius
	for idx in Airports.land_count(kind):
		if idx != p.runway and not p.any_target:
			continue
		if kind == Aircraft.Kind.RUNWAY and not Airports.suitable_runway(p.type, idx):
			continue
		for e in Airports.land_ends(kind):
			var thr := Airports.land_threshold(kind, idx, e)
			if _dist_to_segment(thr, last, raw) <= radius:
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
		_check_refusals(p, last, raw)
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

## Snap: the finger is within `snap_radius` of the extended centreline of an open end of this aircraft's runway, behind its
## threshold and heading for it: the path locks onto the centreline and the aircraft is cleared to land.
func _try_snap(p: Aircraft, last: Vector2, raw: Vector2) -> bool:
	var kind := p.tkind
	var move := raw - last
	for idx in Airports.land_count(kind):
		if idx != p.runway and not p.any_target:
			continue
		if kind == Aircraft.Kind.RUNWAY and not Airports.suitable_runway(p.type, idx):
			continue
		for e in Airports.land_ends(kind):
			var thr := Airports.land_threshold(kind, idx, e)
			var h := deg_to_rad(Airports.land_heading_deg(kind, idx, e))
			var dir := Vector2(sin(h), -cos(h))
			var rel := raw - thr
			var u := -rel.dot(dir)
			var lat := absf(rel.dot(Vector2(-dir.y, dir.x)))
			if u < Tuning.snap_min_reach or u > Tuning.snap_reach or lat > Tuning.snap_radius:
				continue
			if move.length() > 0.05 and move.normalized().dot(dir) < 0.35:
				continue
			if not _end_active(kind, idx, e):
				continue
			var at := thr - dir * u
			if last.distance_to(at) > 0.05:
				p.push(at, 2)
			p.push(thr)
			p.push(Airports.land_far(kind, idx, e))
			p.cleared = true
			p.runway = idx
			p.land_end = e
			if p.type == Aircraft.Type.GLIDER:
				p.locked = true
			snapped.emit(p, at)
			cleared.emit(p)
			return true
	return false

## The path went for a place this aircraft can't use: say why (once per drag).
func _check_refusals(p: Aircraft, last: Vector2, raw: Vector2) -> void:
	for kind in 3:
		for idx in Airports.land_count(kind):
			for e in Airports.land_ends(kind):
				var radius := Tuning.pad_capture_radius if kind == Aircraft.Kind.PAD else Tuning.approach_radius
				var thr := Airports.land_threshold(kind, idx, e)
				if _dist_to_segment(thr, last, raw) > radius:
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
	if p.ga_pending:       # holding is an answer too: the warning is cancelled
		p.ga_pending = false
		go_around_cancels += 1
		go_around_cancelled.emit(p)
	p.fade_path(Tuning.path_fade_seconds)
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
	hz_vel.fill(Vector2.ZERO)
	for h in Airports.hazards():
		add_hazard(h["center"], h["radius"], 0)

## A storm cell: a no-fly zone that drifts with `vel`. Returns its hazard index (-1 if the table is full).
func add_storm(c: Vector2, r: float, vel: Vector2) -> int:
	var k := add_hazard(c, r, 1)
	if k >= 0:
		hz_vel[k] = vel
	return k

func storm_count() -> int:
	var n := 0
	for k in hz_count:
		if hz_kind[k] == 1:
			n += 1
	return n

func clear_storms() -> void:
	for k in range(hz_count - 1, -1, -1):
		if hz_kind[k] == 1:
			_remove_hazard(k)

func _remove_hazard(k: int) -> void:
	hz_count -= 1
	hz_pos[k] = hz_pos[hz_count]
	hz_r[k] = hz_r[hz_count]
	hz_kind[k] = hz_kind[hz_count]
	hz_vel[k] = hz_vel[hz_count]

func add_hazard(c: Vector2, r: float, kind: int) -> int:
	if hz_count >= MAX_HAZARDS:
		return -1
	hz_pos[hz_count] = c
	hz_r[hz_count] = r
	hz_kind[hz_count] = kind
	hz_vel[hz_count] = Vector2.ZERO
	hz_count += 1
	return hz_count - 1

func release_all() -> void:
	go_around_warns = 0
	go_around_cancels = 0
	fog_amount = 0.0
	fog_target = 0.0
	_busy_until.fill(0.0)
	_last_td.fill(-1000.0)
	for i in 8:
		_occupant[i] = null
	for i in pool_n:
		planes[i].reset()
		_nodes[i].visible = false
		_shadows[i].visible = false
	for k in _trail_age.size():
		_trail_age[k] = 99.0
	_trail_mm.visible_instance_count = 0
	run_time = 0.0
	_beat = 0
	_spawn_timer = Tuning.first_spawn_delay

func step(delta: float) -> void:
	run_time += delta
	_dt = delta
	if auto_spawn and run_time < spawn_until:
		var quiet := false
		if _beat < beats.size():
			# A new mechanic arrives once, alone: nothing else is sent just before it or for a while after.
			var bt: float = beats[_beat][0]
			if run_time >= bt - Tuning.beat_quiet_lead:
				quiet = true
				if run_time >= bt and (active_count() == 0 or run_time >= bt + Tuning.beat_quiet_lead):
					if spawn(int(beats[_beat][1])) != null:
						_beat += 1
						_spawn_timer = maxf(_spawn_timer, Tuning.beat_gap)
		if not quiet:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				if active_count() < mini(Tuning.max_planes_eff(), pool_n) and spawn() != null:
					_spawn_timer = Tuning.spawn_interval(run_time) * Tuning.traffic_spawn_mult() * rng.randf_range(0.75, 1.25)
				else:
					_spawn_timer = 0.25
	_update_weather(delta)
	var mult := Tuning.speed_mult(run_time) * Tuning.traffic_speed_mult()
	for i in pool_n:
		var p := planes[i]
		if not p.active():
			continue
		p.age += delta
		if p.climb > 0.0:
			p.climb = maxf(p.climb - delta, 0.0)
		if p.pop_t > 0.0:
			p.pop_t = maxf(p.pop_t - delta, 0.0)
		if p.red_pulse_t >= 0.0:
			p.red_pulse_t += delta
			if p.red_pulse_t > Tuning.red_pulse_seconds:
				p.red_pulse_t = -1.0
		elif not p.red_seen and p.entered and (p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD) and p.timer_frac() <= Tuning.timer_red_fraction:
			p.red_seen = true               # the ring just turned red: one pulse
			p.red_pulse_t = 0.0
		_move(p, delta, mult)
		if p.active():
			if p.ga_pending:
				_tick_telegraph(p, delta)
			if p.active() and p.cleared and p.state == Aircraft.State.FLY and p.can_go_around():
				_score_approach(p, mult)
			_sync(p, i)
	_check_conflicts()
	_update_trails(delta)
	_dt = 0.0

## Storm cells drift (and leave); the fog thickens or clears (it hides nothing: it is only drawn behind everything).
func _update_weather(dt: float) -> void:
	for k in range(hz_count - 1, -1, -1):
		if hz_kind[k] == 1:
			hz_pos[k] += hz_vel[k] * dt
			if absf(hz_pos[k].x) > half_w + hz_r[k] + 2.0 or absf(hz_pos[k].y) > half_h + hz_r[k] + 2.0:
				_remove_hazard(k)
	fog_amount = move_toward(fog_amount, fog_target, dt / maxf(Tuning.fog_fade_seconds, 0.1))

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
			if p.ground and not p.touched:
				p.touched = true
				p.pop_t = TOUCH_POP
				touchdown.emit(p)
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
				crashed.emit(p, hz_kind[k])
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
		if not p.can_go_around():       # gliders and emergencies have no go-around: no room, so they are lost
			crashed.emit(p, 2)
			_remove(p)
			return false
		_start_go_around(p, Approach.Reason.BUSY)
		return false
	for j in Airports.rw_count():
		if j != r and Airports.runways_cross(r, j) and run_time < _busy_until[j] and _occupant[j] != null and _occupant[j] != p:
			runway_conflict.emit(p, _occupant[j])
			return false
	_busy_until[r] = run_time + Tuning.landing_roll_time + Tuning.runway_clear()
	_last_td[r] = run_time
	_occupant[r] = p
	return true

## Score a cleared runway approach every frame (for the path tint); at short final, roll the go-around dice once.
func _score_approach(p: Aircraft, mult: float) -> void:
	if p.count < 2:
		return
	var dist := 0.0               # path length from the aircraft to the threshold
	var prev := p.pos
	for k in p.count - 1:
		var q := p.pts[p.head + k]
		dist += prev.distance_to(q)
		prev = q
	var arrive := run_time + dist / maxf(p.speed * mult, 0.01)
	approach.evaluate(p, arrive - _last_td[p.runway], wind.from_deg if wind != null else -1.0)
	# Fog makes a POOR approach a little riskier; a clean one has no chance to multiply, so it is unaffected.
	var chance := minf(approach.chance * lerpf(1.0, Tuning.fog_poor_go_around_mult, fog_amount), Tuning.go_around_max)
	if p.student:
		if all_students:
			chance = minf(chance * Tuning.bad_day_go_around_mult + Tuning.bad_day_go_around_floor, Tuning.go_around_max)
		else:
			chance = minf(chance * Tuning.student_go_around_mult + Tuning.student_go_around_floor, Tuning.go_around_max)
		if Tuning.go_around_max <= 0.0:
			chance = 0.0
		if approach.reason == Approach.Reason.NONE:
			approach.reason = Approach.Reason.STUDENT
	if scenic:
		chance = 0.0
	p.ga_chance = chance
	p.ga_band = approach.band(chance)
	# The dice roll one telegraph earlier than the go-around itself: the plane wobbles for that second.
	var lead := p.speed * mult * Tuning.go_around_telegraph
	if p.ga_pending:
		if p.ga_redrawn and chance < p.ga_roll * Tuning.go_around_cancel_factor:
			p.ga_pending = false           # a cleaner final, in time: it lands after all
			p.ga_checked = true
			go_around_cancels += 1
			go_around_cancelled.emit(p)
		elif dist <= Tuning.short_final_distance:
			_fire_go_around(p)
	elif not p.ga_checked and dist <= Tuning.short_final_distance + lead:
		p.ga_checked = true
		if go_rng.randf() < chance:
			if Tuning.go_around_telegraph <= 0.0 or dist <= Tuning.short_final_distance:
				_start_go_around(p, approach.reason)
			else:
				p.ga_pending = true
				p.ga_t = Tuning.go_around_telegraph
				p.ga_reason = approach.reason
				p.ga_roll = chance
				p.ga_redrawn = false
				go_around_warns += 1
				go_around_warned.emit(p, approach.reason)

## The warning second is running: when it is up (and the final was not redrawn cleaner) the go-around happens.
func _tick_telegraph(p: Aircraft, dt: float) -> void:
	if p.state != Aircraft.State.FLY:
		p.ga_pending = false
		return
	p.ga_t -= dt
	if p.ga_t <= 0.0:
		_fire_go_around(p)

func _fire_go_around(p: Aircraft) -> void:
	p.ga_pending = false
	_start_go_around(p, p.ga_reason)

## Climb out along the runway heading with the remaining timer; the path is gone, so a new one is needed.
func _start_go_around(p: Aircraft, reason: int) -> void:
	p.clear_path()
	p.heading = deg_to_rad(Airports.land_heading_deg(p.tkind, p.runway, p.land_end))
	p.climb = Tuning.go_around_climb_seconds
	p.go_arounds += 1
	go_around.emit(p, reason)

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

## An aircraft is lost (a conflict or a crash): it leaves the field at once.
func lose(p: Aircraft) -> void:
	if p.active():
		_remove(p)

func _remove(p: Aircraft) -> void:
	var i := planes.find(p)
	p.reset()
	_nodes[i].visible = false
	_shadows[i].visible = false

func _check_conflicts() -> void:
	for p in planes:
		p.warn = 0.0
		p.warn_other = null
	var cd := Tuning.conflict_distance
	var wd := Tuning.warn_distance
	for i in pool_n:
		var a := planes[i]
		if not a.can_conflict():
			continue
		for j in range(i + 1, pool_n):
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
				if d < cd and not _god and run_time >= grace_until:
					conflict.emit(a, b)
					return

## Copy a plane's state onto its node (position, heading, bank, pitch, size, colours, spinning rotor, emergency flash),
## its shadow and the prop blur.
func _sync(p: Aircraft, i: int) -> void:
	var n := _nodes[i]
	n.visible = not p.fogged
	var landing := p.state == Aircraft.State.LANDING
	var alt := 1.0 if not landing else 1.0 - 0.35 * minf(p.roll_t / maxf(Tuning.touchdown_fraction, 0.01), 1.0)
	var lift_f := 0.0 if p.climb <= 0.0 else sin(PI * clampf(p.climb / maxf(Tuning.go_around_climb_seconds, 0.1), 0.0, 1.0))
	var lift := 0.3 * lift_f
	# Bank into turns: roll follows how fast the drawn heading is turning, eased.
	if _dt > 0.0:
		var yaw_rate := wrapf(p.vis_heading - p.prev_vis, -PI, PI) / _dt
		var target := 0.0
		if not landing and p.state != Aircraft.State.IDLE:
			target = clampf(yaw_rate * (0.2 if p.type == Aircraft.Type.HELI else 0.3), -MAX_BANK, MAX_BANK)
		p.bank = lerpf(p.bank, target, 1.0 - exp(-9.0 * _dt))
		p.prev_vis = p.vis_heading
	# Nose up a touch on a go-around climb and in the flare just before touchdown.
	var pitch := 0.22 * lift_f
	if landing:
		pitch = 0.14 * (1.0 - minf(p.roll_t / maxf(Tuning.touchdown_fraction, 0.01), 1.0))
	var h := PLANE_Y * alt + lift
	n.position = Vector3(p.pos.x, h, p.pos.y)
	var wobble := deg_to_rad(Tuning.telegraph_wobble_deg) * sin(p.age * 38.0) * clampf(1.0 - p.ga_t / maxf(Tuning.go_around_telegraph, 0.01) * 0.5, 0.5, 1.0) if p.ga_pending else 0.0
	n.rotation = Vector3(pitch, -p.vis_heading, -p.bank + wobble)
	var pop := 1.0 + 0.22 * sin(PI * clampf(1.0 - p.pop_t / TOUCH_POP, 0.0, 1.0)) if p.pop_t > 0.0 else 1.0
	n.scale = Vector3.ONE * (0.9 + 0.1 * alt) * pop
	# The shadow: on the ground, further away (and fainter) the higher the aircraft is.
	var sh := _shadows[i]
	sh.visible = n.visible
	var up := (h - PLANE_Y * 0.65) / 0.5
	sh.position = Vector3(p.pos.x + (0.03 + 0.4 * up) * shadow_scale, 0.14, p.pos.y + (0.02 + 0.3 * up) * shadow_scale)       # (hugging the wheels on the ground, further away the higher it flies)
	sh.rotation.y = -p.vis_heading
	sh.scale = Vector3(_shadow_size[i].x, 1.0, _shadow_size[i].y) * (0.9 + 0.1 * alt)
	_shadow_mats[i].set_shader_parameter("alpha", Shadow.ALPHA - 0.08 * clampf(up, 0.0, 1.5))       # blue-grey at 26%: fainter the higher it flies
	var base := Airports.land_color(p.tkind, p.runway)
	if p.emergency and p.state != Aircraft.State.LANDING and sin(TAU * 3.0 * p.age) > 0.0:
		base = Color(1.0, 0.12, 0.1)
	_paint(_body_mats[i], base)
	var lv: Dictionary = Cosmetics.LIVERIES[livery]
	_paint(_fus_mats[i], lv["body"] if lv["body"] != null else Color.WHITE)
	_paint(_heli_mats[i], lv["body"] if lv["body"] != null else base)
	_paint(_stripe_mats[i], lv["stripe"] if lv["stripe"] != null else Color.WHITE)
	_badges[i].visible = p.student
	if p.type == Aircraft.Type.HELI:
		_rotors[i].rotation.y = p.age * 22.0

## Contrails: every aircraft in the air leaves a short fading string of soft puffs (jets the most; gliders and
## helicopters none). The whole pool is one MultiMesh, rewritten from preallocated arrays.
func _update_trails(dt: float) -> void:
	var any := false
	for i in pool_n:
		var p := planes[i]
		var peak := 0.0
		if p.active() and p.state != Aircraft.State.LANDING and p.entered:
			match p.type:
				Aircraft.Type.JET:
					peak = 0.6
				Aircraft.Type.MEDIUM:
					peak = 0.28
				Aircraft.Type.SMALL, Aircraft.Type.SEAPLANE:
					peak = 0.16
		if peak > 0.0:
			_trail_clock[i] += dt
			if _trail_clock[i] >= TRAIL_EVERY:
				_trail_clock[i] = 0.0
				var k := i * TRAIL_N + _trail_head[i]
				_trail_head[i] = (_trail_head[i] + 1) % TRAIL_N
				var back := Vector2(-sin(p.vis_heading), cos(p.vis_heading)) * 0.5
				_trail_pos[k] = p.pos + back
				_trail_y[k] = PLANE_Y + 0.3 * p.climb
				_trail_age[k] = 0.0
				_trail_peak[k] = peak
	var life := TRAIL_N * TRAIL_EVERY
	var vis := 0
	for k in pool_n * TRAIL_N:
		if _trail_age[k] >= life:
			_trail_peak[k] = 0.0
			continue
		_trail_age[k] += dt
		var f := clampf(_trail_age[k] / life, 0.0, 1.0)
		var size := 0.16 + 0.34 * f
		_trail_mm.set_instance_transform(vis, Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), Vector3(_trail_pos[k].x, _trail_y[k], _trail_pos[k].y)))
		_trail_mm.set_instance_color(vis, Color(1, 1, 1, _trail_peak[k] * (1.0 - f)))
		vis += 1
		any = true
	_trail_mm.visible_instance_count = vis
	_trail.visible = any

## The pre-warm: every pooled plane drawn at once, alternating normal and flashing.
func prewarm_show() -> void:
	var types := [Aircraft.Type.SMALL, Aircraft.Type.MEDIUM, Aircraft.Type.JET, Aircraft.Type.GLIDER, Aircraft.Type.HELI, Aircraft.Type.SEAPLANE]
	for i in pool_n:
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


# ---------- The ramp's aircraft: the very models that landed ----------

## A model of the ramp pool for an aircraft that has just landed (its index in the model arrays), or -1 if all are in use.
func ramp_claim() -> int:
	for k in _ramp_used.size():
		if _ramp_used[k] == 0:
			_ramp_used[k] = 1
			return _ramp_first + k
	return -1

func ramp_release(i: int) -> void:
	if i >= _ramp_first and i < _ramp_first + _ramp_used.size():
		_ramp_used[i - _ramp_first] = 0
		_nodes[i].visible = false

func ramp_free_all() -> void:
	for k in _ramp_used.size():
		_ramp_used[k] = 0
		_nodes[_ramp_first + k].visible = false

func ramp_in_use() -> int:
	var n := 0
	for k in _ramp_used.size():
		n += _ramp_used[k]
	return n

func ramp_node(i: int) -> Node3D:
	return _nodes[i]

## Dress model `i` as the aircraft that landed: the same model for its type and speed class, its runway's livery colour, the airline
## livery's body and stripe, the student badge.
func ramp_configure(i: int, type: int, cls: int, kind: int, runway: int, student: bool) -> void:
	_set_model(i, type, cls)
	var base := Airports.land_color(kind, runway)
	_paint(_body_mats[i], base)
	var lv: Dictionary = Cosmetics.LIVERIES[livery]
	_paint(_fus_mats[i], lv["body"] if lv["body"] != null else Color.WHITE)
	_paint(_heli_mats[i], lv["body"] if lv["body"] != null else base)
	_paint(_stripe_mats[i], lv["stripe"] if lv["stripe"] != null else Color.WHITE)
	_badges[i].visible = student
	var long: float = [0.85, 1.0, 1.3][cls]
	var span: float = [1.2, 1.0, 0.78][cls]
	var sh := _ramp_shadows[i - _ramp_first]
	match type:
		Aircraft.Type.GLIDER:
			sh.scale = Vector3(2.7, 1.0, 1.5)
		Aircraft.Type.HELI:
			sh.scale = Vector3(1.5, 1.0, 1.5)
		_:
			sh.scale = Vector3(1.5 * span, 1.0, 1.35 * long)
	_nodes[i].visible = true

## Put model `i` on the ground at `pos`, nose along `heading`, at `scale` (a hovering helicopter is a little higher); `moving` shows
## the prop and rotor blur and turns the rotor.
func ramp_place(i: int, pos: Vector2, heading: float, scale: float, hover: float, moving: bool, clock: float, type: int) -> void:
	var n := _nodes[i]
	n.position = Vector3(pos.x, 0.16 * scale + 0.02 + hover, pos.y)
	n.rotation = Vector3(0.0, -heading, 0.0)
	n.scale = Vector3.ONE * scale
	var sh := _ramp_shadows[i - _ramp_first]
	sh.position = Vector3(0.1, -(n.position.y - 0.026) / maxf(scale, 0.01) - hover * 0.0, 0.08)
	_prop_discs[i].visible = moving and (type == Aircraft.Type.SMALL or type == Aircraft.Type.MEDIUM or type == Aircraft.Type.SEAPLANE)
	_rotor_discs[i].visible = moving and type == Aircraft.Type.HELI
	if type == Aircraft.Type.HELI and moving:
		_rotors[i].rotation.y = clock * 22.0
