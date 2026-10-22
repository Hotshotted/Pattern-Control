class_name Airfield
extends Node3D
## The static scenery of every airport. All six are built ONCE at start-up (hidden), and select() just
## switches which one is shown, so starting a shift anywhere creates nothing. An airport has: ground, water /
## island decor, runways (each in its colour, with a threshold block at BOTH approach ends: bright when that
## end is active in the current wind, dull when not), helipads, seaplane lanes, mountains, a control tower,
## a windsock that swings with the wind, and trees. A landing makes that end flash (glow()).

## One airport's nodes and the little state it animates.
class AirportScene:
	var root: Node3D
	var thr_mats: Array[StandardMaterial3D] = []   # runway * 2 + end
	var thr_colors: Array[Color] = []
	var glow_born: Array[int] = []
	var active: Array[bool] = []
	var sock: Node3D
	var ups: Array = []                 # [node, upgrade id, level it appears at]
	var dishes: Array[Node3D] = []      # radar dishes (they turn)
	var mast_lights: Array[StandardMaterial3D] = []   # comms mast beacons (they blink)
	var water := false
	var base_ground := Color.WHITE
	var ground_mat: StandardMaterial3D
	var stripe_mat: StandardMaterial3D
	var leaf_mat: StandardMaterial3D
	var leaf_mid: StandardMaterial3D        # the lighter crown layers (the highlight)
	var leaf_hi: StandardMaterial3D
	var patch_mat: StandardMaterial3D        # the darker mown patches
	var trunk_mat: StandardMaterial3D
	var tree_styles: Array = [[], [], []]   # per tree style: the holders to show
	var strips: Array = []              # taxiway strips [from, to] (world x, z): ground vehicles drive along them
	var veh: Array[Node3D] = []         # ground vehicles
	var veh_strip := PackedInt32Array()
	var veh_t := PackedFloat32Array()   # 0..2 along the strip and back
	var veh_speed := PackedFloat32Array()
	var veh_beacon: Array[StandardMaterial3D] = []
	var lights: MultiMeshInstance3D

var _hangar_at := Vector2(1000.0, 1000.0)   # where the hangar stands (kept clear of upgrade props)
var wind: Wind                        # set by Main
var variants: Array[AirportScene] = []
var cur: AirportScene
var selected := 0
var _sock_deg := 0.0

func _ready() -> void:
	var keep := Airports.current
	Prim.outlines = false        # Sunny Airfield: the ground and its props have soft shadows and highlights, never outlines
	for a in Airports.COUNT:
		Airports.current = a
		variants.append(_build_airport())
	Prim.outlines = true
	Airports.current = keep
	select(keep)

## Show airport `a` (Airports.current should already be `a`).
func select(a: int) -> void:
	selected = a
	for i in variants.size():
		variants[i].root.visible = i == a
	cur = variants[a]

func _build_airport() -> AirportScene:
	var v := AirportScene.new()
	var root := Node3D.new()
	add_child(root)
	v.root = root
	var ground := Airports.ground_color()
	v.base_ground = ground
	v.ground_mat = Prim.mat(ground)
	Prim.box(root, Vector3(40.0, 0.2, 70.0), Vector3(0, -0.1, 0), v.ground_mat, false)
	var stripe := Prim.mat(ground.lightened(0.07))
	v.stripe_mat = stripe
	var patch := Prim.mat(ground.darkened(0.06))
	v.patch_mat = patch
	var water: bool = Airports.def().get("water", false)
	v.water = water
	if not water:
		# Mown patches in slightly different greens: long diagonal bands, light and dark, the same on every visit.
		var rngp := RandomNumberGenerator.new()
		rngp.seed = 31 + Airports.current * 17
		for i in 9:
			var bandp := Prim.box(root, Vector3(rngp.randf_range(7.0, 15.0), 0.02, rngp.randf_range(1.6, 3.4)), Vector3(rngp.randf_range(-6.0, 6.0), 0.005 + 0.001 * i, rngp.randf_range(-9.0, 9.0)), stripe if i % 2 == 0 else patch, false)
			bandp.rotation.y = deg_to_rad(rngp.randf_range(-24.0, 24.0))
	else:
		var wave := Prim.mat(ground.lightened(0.14))
		v.stripe_mat = wave
		for i in 5:
			Prim.box(root, Vector3(9.0 + 2.0 * (i % 3), 0.02, 0.5), Vector3(-5.0 + 2.5 * i, 0.005, -8.0 + 4.1 * i), wave, false)
	for d in Airports.decor():
		var m := Prim.mat(d["color"])
		if d["shape"] == "disc":
			Prim.cyl(root, d["r"], d["r"], 0.06, d["sides"], Vector3(d["pos"].x, d["y"], d["pos"].y), m, false)
		else:
			Prim.box(root, Vector3(d["size"].x, 0.04, d["size"].y), Vector3(d["pos"].x, d["y"], d["pos"].y), m, false)
	for i in Airports.rw_count():
		_runway(v, i)
	for pad in Airports.pads():
		_pad(root, pad)
	for lane in Airports.lanes():
		_lane(root, lane)
	for h in Airports.hazards():
		_mountain(root, h["center"], h["radius"])
	_taxiways(v)
	_lights(v)
	_vehicles(v)
	var tp := Airports.tower_pos()
	_tower(root, Vector3(tp.x, 0.0, tp.y))
	_apron(v)
	var sp := Airports.windsock_pos()
	_windsock(v, Vector3(sp.x, 0.0, sp.y))
	if not water:
		_trees(v)
	_upgrade_props(v)
	return v

## Trees at a few fixed spots, each in three styles (round, pine, cactus): the theme picks which one shows.
func _trees(v: AirportScene) -> void:
	v.leaf_mat = Prim.mat(Color("3e8a48"))
	v.leaf_mid = Prim.mat(v.leaf_mat.albedo_color.lightened(0.18))
	v.leaf_hi = Prim.mat(v.leaf_mat.albedo_color.lightened(0.38))
	v.trunk_mat = Prim.mat(Color(0.45, 0.3, 0.18))
	for t in [Vector2(-4.4, 6.4), Vector2(-3.6, 7.6), Vector2(4.3, 6.9), Vector2(4.5, -6.5), Vector2(-4.4, -6.9), Vector2(3.7, -7.8), Vector2(-4.2, -3.9), Vector2(4.5, 4.4)]:
		var blocked := false
		for st in v.strips:
			var sa: Vector2 = st[0]
			var sab: Vector2 = (st[1] as Vector2) - sa
			var su := clampf((t - sa).dot(sab) / maxf(sab.length_squared(), 0.0001), 0.0, 1.0)
			if t.distance_to(sa + sab * su) < 1.0:
				blocked = true
		for h in Airports.hazards():
			if (h["center"] as Vector2).distance_to(t) < h["radius"] + 0.7:
				blocked = true
		if blocked:
			continue
		var round_t := Node3D.new()         # style 0: a cluster of round crowns, each with a shadow, a lighter middle and a highlight
		round_t.position = Vector3(t.x, 0.0, t.y)
		v.root.add_child(round_t)
		_shadow(round_t, 0.12, 0.1, 0.62, 0.62, 0.22, 0.02)
		_shadow(round_t, 0.42, 0.34, 0.4, 0.4, 0.2, 0.02)
		Prim.cyl(round_t, 0.34, 0.4, 0.55, 10, Vector3(0.0, 0.3, 0.0), v.leaf_mat, false)
		Prim.cyl(round_t, 0.22, 0.28, 0.1, 10, Vector3(-0.04, 0.6, -0.04), v.leaf_mid, false)
		Prim.cyl(round_t, 0.1, 0.12, 0.06, 8, Vector3(-0.09, 0.67, -0.09), v.leaf_hi, false)
		Prim.cyl(round_t, 0.22, 0.26, 0.4, 9, Vector3(0.4, 0.22, 0.32), v.leaf_mat, false)
		Prim.cyl(round_t, 0.12, 0.17, 0.08, 9, Vector3(0.37, 0.43, 0.29), v.leaf_mid, false)
		var pine := Node3D.new()            # style 1: a pine
		pine.position = Vector3(t.x, 0.0, t.y)
		v.root.add_child(pine)
		Prim.cyl(pine, 0.05, 0.05, 0.4, 5, Vector3(0, 0.2, 0), v.trunk_mat)
		Prim.cyl(pine, 0.0, 0.42, 0.9, 6, Vector3(0, 0.85, 0), v.leaf_mat)
		var cactus := Node3D.new()          # style 2: a cactus
		cactus.position = Vector3(t.x, 0.0, t.y)
		v.root.add_child(cactus)
		Prim.cyl(cactus, 0.12, 0.14, 0.8, 6, Vector3(0, 0.4, 0), v.leaf_mat)
		Prim.box(cactus, Vector3(0.3, 0.1, 0.1), Vector3(-0.2, 0.5, 0), v.leaf_mat, false)
		Prim.box(cactus, Vector3(0.1, 0.3, 0.1), Vector3(-0.32, 0.65, 0), v.leaf_mat, false)
		Prim.box(cactus, Vector3(0.3, 0.1, 0.1), Vector3(0.2, 0.38, 0), v.leaf_mat, false)
		Prim.box(cactus, Vector3(0.1, 0.26, 0.1), Vector3(0.32, 0.5, 0), v.leaf_mat, false)
		v.tree_styles[0].append(round_t)
		v.tree_styles[1].append(pine)
		v.tree_styles[2].append(cactus)

## Dress every airport in a theme: ground, scenery style and colours (no new nodes).
func apply_theme(index: int) -> void:
	var t: Dictionary = Cosmetics.THEMES[index]
	for v in variants:
		var ground: Color = v.base_ground
		if t["ground"] != null and not v.water:
			ground = t["ground"]
		elif v.water:
			ground = v.base_ground * (t["tint"] as Color)
		v.ground_mat.albedo_color = ground
		v.stripe_mat.albedo_color = ground.lightened(0.07) if not v.water else ground.lightened(0.14)
		if v.patch_mat != null:
			v.patch_mat.albedo_color = ground.darkened(0.06)
		if v.leaf_mat != null:
			v.leaf_mat.albedo_color = t["leaf"]
			v.leaf_mid.albedo_color = (t["leaf"] as Color).lightened(0.18)
			v.leaf_hi.albedo_color = (t["leaf"] as Color).lightened(0.38)
			v.trunk_mat.albedo_color = t["trunk"]
		for st in 3:
			for holder in v.tree_styles[st]:
				holder.visible = st == t["style"]

func _runway(v: AirportScene, i: int) -> void:
	var col := Airports.rw_color(i)
	var root := Node3D.new()
	root.position = Vector3(Airports.rw_center(i).x, 0.0, Airports.rw_center(i).y)
	root.rotation.y = -deg_to_rad(Airports.rw_heading_deg(i))
	v.root.add_child(root)
	var len := Airports.rw_length(i)
	var w := Airports.rw_width(i)
	Prim.box(root, Vector3(w + 0.16, 0.11, len + 0.16), Vector3(0, 0.055, 0), Prim.mat(Tuning.runway_asphalt.darkened(0.3)), false)       # the darker rim
	Prim.box(root, Vector3(w, 0.12, len), Vector3(0, 0.06, 0), Prim.mat(Tuning.runway_asphalt), false)
	var edge := Prim.mat(col)
	for s in [-1.0, 1.0]:
		Prim.box(root, Vector3(0.08, 0.13, len - 0.1), Vector3(s * (w * 0.5 - 0.1), 0.065, 0), edge, false)
	var white := Prim.mat(Color(0.93, 0.93, 0.9))
	# End 0 is approached from behind its landing direction (local +z end); end 1 from the other side (-z).
	for e in 2:
		var sign := 1.0 if e == 0 else -1.0
		var thr := Prim.mat(col)
		thr.emission_enabled = true
		thr.emission = col
		thr.emission_energy_multiplier = 0.0
		v.thr_mats.append(thr)
		v.thr_colors.append(col)
		v.glow_born.append(0)
		v.active.append(true)
		Prim.box(root, Vector3(w - 0.3, 0.14, 0.5), Vector3(0, 0.07, sign * (len * 0.5 - 0.35)), thr, false)
		for k in 4:   # piano keys just past the threshold block
			Prim.box(root, Vector3(0.08, 0.14, 0.4), Vector3(-0.27 + k * 0.18, 0.07, sign * (len * 0.5 - 0.9)), white, false)
	for k in 5:
		Prim.box(root, Vector3(0.09, 0.14, 0.36), Vector3(0, 0.07, (k - 2) * 1.0), white, false)
	# Approach chevrons in the runway's colour: three Vs on the grass before each end, pointing at the runway.
	var chev := Prim.mat(col.lerp(v.base_ground, 0.15))
	for e in 2:
		var sg := 1.0 if e == 0 else -1.0
		for k in 3:
			for sd in [-1.0, 1.0]:
				var arm := Prim.box(root, Vector3(0.5, 0.03, 0.09), Vector3(sd * 0.2, 0.02, sg * (len * 0.5 + 0.95 + k * 0.42) + sg * 0.1), chev, false)
				arm.rotation.y = deg_to_rad(sg * sd * 32.0)
	Prim.lift(root)       # runways are drawn above the fog

## A parallel taxiway beside each runway that has room for one: asphalt strip, yellow centre dashes and two stubs to the
## runway. All of it lies on the ground, under everything that moves.
func _taxiways(v: AirportScene) -> void:
	if v.water:
		return
	var asphalt := Prim.mat(Color("4a5265"))
	var yellow := Prim.mat(Color("ffd23f"))
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		var dir := Vector2(sin(h), -cos(h))
		var perp := Vector2(cos(h), sin(h))
		var c := Airports.rw_center(i)
		var len := Airports.rw_length(i)
		var w := Airports.rw_width(i)
		var half := len * 0.34
		for side in [1.0, -1.0]:
			var off: float = w * 0.5 + 0.95
			var a: Vector2 = c + perp * off * side - dir * half
			var b: Vector2 = c + perp * off * side + dir * half
			var free := true
			for f in [0.0, 0.5, 1.0]:
				if not _spot_free(a.lerp(b, f), 0.4, 8.6):
					free = false
			if not free:
				continue
			var n := Node3D.new()
			n.position = Vector3(c.x, 0.0, c.y)
			n.rotation.y = -h
			v.root.add_child(n)
			Prim.box(n, Vector3(0.6, 0.05, half * 2.0), Vector3(side * off, 0.03, 0), asphalt, false)
			var stub := off - w * 0.5
			for z in [-half, half]:
				Prim.box(n, Vector3(stub + 0.3, 0.05, 0.6), Vector3(side * (w * 0.5 + stub * 0.5 - 0.15), 0.032, z), asphalt, false)
			for k in int(half * 2.0 / 0.6):
				Prim.box(n, Vector3(0.05, 0.06, 0.24), Vector3(side * off, 0.05, -half + 0.3 + k * 0.6), yellow, false)
			v.strips.append([a, b])
			break

## Runway edge lights and the approach strobes: one MultiMesh per airport; the shader makes them shimmer / run.
func _lights(v: AirportScene) -> void:
	var pts: Array = []        # [Vector3 position, phase, strobe]
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		var dir := Vector2(sin(h), -cos(h))
		var perp := Vector2(cos(h), sin(h))
		var c := Airports.rw_center(i)
		var len := Airports.rw_length(i)
		var w := Airports.rw_width(i)
		var lz := -len * 0.5 + 0.35
		var k := 0
		while lz < len * 0.5 - 0.2:
			for side in [-1.0, 1.0]:
				var p: Vector2 = c - dir * lz + perp * side * (w * 0.5 + 0.06)
				pts.append([Vector3(p.x, 0.15, p.y), float(k % 7) / 7.0, 0.0])
			lz += 0.8
			k += 1
		for e in 2:
			var sign := 1.0 if e == 0 else -1.0
			for j in 8:
				var p2: Vector2 = c - dir * (sign * (len * 0.5 + 0.55 + j * 0.5))
				pts.append([Vector3(p2.x, 0.04, p2.y), float(7 - j) / 8.0, 1.0])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.04, 0.09)
	mm.mesh = bm
	mm.instance_count = pts.size()
	for k in pts.size():
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, pts[k][0]))
		mm.set_instance_color(k, Color(pts[k][1], pts[k][2], 0.0, 1.0))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/runway_lights.gdshader")
	mat.render_priority = 3
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.root.add_child(mi)
	v.lights = mi

## A couple of ground vehicles driving up and down the first taxiway: a yellow fuel truck with a blue cab, and a white van.
func _vehicles(v: AirportScene) -> void:
	if v.strips.is_empty():
		return
	for k in 2:
		var n := Node3D.new()
		v.root.add_child(n)
		if k == 0:      # the fuel truck: a long yellow tank behind a blue cab
			Prim.box(n, Vector3(0.22, 0.1, 0.36), Vector3(0, 0.1, 0.1), Prim.mat(Color("ffc933")), false)
			Prim.box(n, Vector3(0.2, 0.1, 0.14), Vector3(0, 0.1, -0.16), Prim.mat(Color("3d8bff")), false)
			Prim.box(n, Vector3(0.14, 0.02, 0.3), Vector3(0, 0.16, 0.1), Prim.mat(Color("ffe27a")), false)
		else:
			Prim.box(n, Vector3(0.2, 0.1, 0.34), Vector3(0, 0.1, 0), Prim.mat(Color("f3f7ff")), false)
			Prim.box(n, Vector3(0.18, 0.09, 0.12), Vector3(0, 0.15, -0.1), Prim.mat(Color(0.2, 0.28, 0.38)), false)
		var bm := Prim.mat(Color(1.0, 0.25, 0.2))
		Prim.box(n, Vector3(0.06, 0.05, 0.06), Vector3(0, 0.22, 0.12), bm, false)
		v.veh.append(n)
		v.veh_beacon.append(bm)
		v.veh_strip.append(0)
		v.veh_t.append(0.0 if k == 0 else 1.1)
		v.veh_speed.append(0.07 if k == 0 else 0.05)
	_place_vehicles(v)

func _place_vehicles(v: AirportScene) -> void:
	for k in v.veh.size():
		var st: Array = v.strips[v.veh_strip[k]]
		var a: Vector2 = st[0]
		var b: Vector2 = st[1]
		var t := v.veh_t[k]
		var u := t if t < 1.0 else 2.0 - t
		var p := a.lerp(b, u)
		var d := (b - a) * (1.0 if t < 1.0 else -1.0)
		v.veh[k].position = Vector3(p.x, 0.0, p.y)
		v.veh[k].rotation.y = -atan2(d.x, -d.y)

## A cheap breath of life: vehicles roll along the taxiway, their beacons blink.
func _animate_ground(delta: float, now: int) -> void:
	var on := int(now / 350.0) % 2 == 0
	for k in cur.veh.size():
		cur.veh_t[k] = fposmod(cur.veh_t[k] + cur.veh_speed[k] * delta, 2.0)
		cur.veh_beacon[k].albedo_color = Color(1.0, 0.25, 0.2) if on else Color(0.3, 0.08, 0.06)
	if not cur.veh.is_empty():
		_place_vehicles(cur)

## A round helipad with an H: a light concrete disc, a ring and an H in the pad's purple.
func _pad(root: Node3D, pad: Dictionary) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var c: Vector2 = pad["center"]
	var r: float = pad["radius"]
	_shadow(holder, c.x + 0.08, c.y + 0.07, r * 2.5, r * 2.5, 0.2, 0.02)
	Prim.cyl(holder, r * 1.06, r * 1.06, 0.1, 16, Vector3(c.x, 0.05, c.y), Prim.mat(Tuning.runway_asphalt.darkened(0.3)), false)
	Prim.cyl(holder, r, r, 0.11, 16, Vector3(c.x, 0.055, c.y), Prim.mat(Color("e9edf4")), false)
	Prim.cyl(holder, r * 0.84, r * 0.84, 0.12, 16, Vector3(c.x, 0.06, c.y), Prim.mat(pad["color"]), false)
	Prim.cyl(holder, r * 0.74, r * 0.74, 0.13, 16, Vector3(c.x, 0.065, c.y), Prim.mat(Color("e9edf4")), false)
	var mark := Prim.mat(pad["color"])
	Prim.box(holder, Vector3(0.1, 0.16, r * 0.9), Vector3(c.x - r * 0.28, 0.07, c.y), mark, false)
	Prim.box(holder, Vector3(0.1, 0.16, r * 0.9), Vector3(c.x + r * 0.28, 0.07, c.y), mark, false)
	Prim.box(holder, Vector3(r * 0.56, 0.16, 0.1), Vector3(c.x, 0.07, c.y), mark, false)
	Prim.lift(holder)       # pads are drawn above the fog

## A strip of water marked out for seaplanes.
func _lane(root: Node3D, lane: Dictionary) -> void:
	var n := Node3D.new()
	n.position = Vector3(lane["center"].x, 0.0, lane["center"].y)
	n.rotation.y = -deg_to_rad(lane["heading"])
	root.add_child(n)
	var len: float = lane["length"]
	var w: float = lane["width"]
	Prim.box(n, Vector3(w, 0.05, len), Vector3(0, 0.05, 0), Prim.mat(Color("62b8e2")), false)
	var edge := Prim.mat(lane["color"])
	for s in [-1.0, 1.0]:
		Prim.box(n, Vector3(0.07, 0.08, len), Vector3(s * w * 0.5, 0.06, 0), edge, false)
		for k in 3:
			Prim.cyl(n, 0.1, 0.1, 0.2, 5, Vector3(s * (w * 0.5 + 0.18), 0.1, (k - 1) * len * 0.42), Prim.mat(Color(1.0, 0.5, 0.15)))
	var white := Prim.mat(Color(0.95, 0.97, 1.0))
	for k in int(len / 1.0) - 1:
		Prim.box(n, Vector3(0.08, 0.08, 0.34), Vector3(0, 0.07, -len * 0.5 + 0.9 + k * 1.0), white, false)
	Prim.lift(n)            # lanes are drawn above the fog

## A low-poly mountain: two peaks with snow caps and a soft shadow. Its radius is the no-fly zone.
func _mountain(root: Node3D, c: Vector2, r: float) -> void:
	var rock := Prim.mat(Color(0.56, 0.54, 0.52))
	var rock2 := Prim.mat(Color(0.66, 0.63, 0.58))
	var snow := Prim.mat(Color(0.97, 0.98, 1.0))
	_shadow(root, c.x + r * 0.22, c.y + r * 0.2, r * 2.5, r * 2.3, 0.22, 0.02)
	Prim.cyl(root, 0.0, r * 0.95, r * 1.5, 7, Vector3(c.x, r * 0.75, c.y), rock, false)
	Prim.cyl(root, 0.0, r * 0.4, r * 0.55, 7, Vector3(c.x, r * 1.25, c.y), snow, false)
	Prim.cyl(root, 0.0, r * 0.6, r * 0.9, 6, Vector3(c.x + r * 0.55, r * 0.45, c.y + r * 0.2), rock2, false)

## A soft round shadow lying on the ground (build time): centre (x, z), size (w, d), `alpha` of ink, height `y`.
func _shadow(parent: Node3D, x: float, z: float, w: float, d: float, alpha: float, y: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/prop_shadow.gdshader")
	m.set_shader_parameter("alpha", alpha)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)

## The tower: a pale base, a shaft and a blue octagonal cab with a white dot on its roof (and a soft shadow).
func _tower(root: Node3D, at: Vector3) -> void:
	_shadow(root, at.x + 0.2, at.z + 0.2, 2.2, 1.8, 0.22, 0.05)
	Prim.box(root, Vector3(1.0, 0.1, 0.8), at + Vector3(0, 0.05, 0), Prim.mat(Color("cfd5df")), false)     # the apron it stands on
	Prim.box(root, Vector3(0.9, 0.5, 0.7), at + Vector3(0, 0.3, 0), Prim.mat(Color("e9edf4")), false)
	Prim.box(root, Vector3(0.9, 0.04, 0.7), at + Vector3(0, 0.56, 0), Prim.mat(Color("f7f9fc")), false)
	Prim.cyl(root, 0.14, 0.18, 0.8, 8, at + Vector3(0, 0.95, 0), Prim.mat(Color("d6dbe4")), false)
	Prim.cyl(root, 0.34, 0.3, 0.26, 8, at + Vector3(0, 1.45, 0), Prim.mat(Color("5aa0ff")), false)
	Prim.cyl(root, 0.4, 0.4, 0.06, 8, at + Vector3(0, 1.62, 0), Prim.mat(Color("d6dbe4")), false)
	Prim.cyl(root, 0.26, 0.3, 0.06, 8, at + Vector3(0, 1.68, 0), Prim.mat(Color("7db6ff")), false)
	Prim.cyl(root, 0.08, 0.08, 0.03, 8, at + Vector3(0, 1.72, 0), Prim.mat(Color.WHITE), false)

## Hangar and apron: a pale hangar with a ridged roof on a concrete apron beside the tower, if there is room.
func _apron(v: AirportScene) -> void:
	_hangar_at = Vector2(1000.0, 1000.0)
	var tp := Airports.tower_pos()
	for off in [Vector2(-1.7, 0.6), Vector2(1.7, 0.6), Vector2(-1.7, -0.9), Vector2(1.7, -0.9), Vector2(0.0, 1.9), Vector2(0.0, -1.9)]:
		var p: Vector2 = tp + off
		if not _spot_free(p, 0.85):
			continue
		_hangar_at = p
		var n := Node3D.new()
		n.position = Vector3(p.x, 0.0, p.y)
		v.root.add_child(n)
		_shadow(n, 0.18, 0.2, 2.5, 2.1, 0.2, 0.03)
		Prim.box(n, Vector3(1.5, 0.05, 1.3), Vector3(0, 0.025, 0), Prim.mat(Color("cfd5df")), false)
		Prim.box(n, Vector3(1.1, 0.4, 0.8), Vector3(0, 0.25, -0.1), Prim.mat(Color("e4e9f1")), false)
		var ridge := Prim.mat(Color("c3cad6"))
		for k in 5:
			Prim.box(n, Vector3(1.1, 0.03, 0.05), Vector3(0, 0.46, -0.4 + k * 0.16), ridge, false)
		Prim.box(n, Vector3(1.1, 0.04, 0.05), Vector3(0, 0.45, -0.5), Prim.mat(Color("f7f9fc")), false)
		Prim.box(n, Vector3(0.7, 0.28, 0.04), Vector3(0, 0.2, 0.32), Prim.mat(Color("8d97aa")), false)       # the hangar door
		break

## A pole with a striped cone on top. The cone's pivot turns to point downwind.
func _windsock(v: AirportScene, at: Vector3) -> void:
	_shadow(v.root, at.x + 0.25, at.z + 0.2, 0.7, 0.7, 0.2, 0.02)
	Prim.cyl(v.root, 0.04, 0.05, 1.3, 5, at + Vector3(0, 0.65, 0), Prim.mat(Color(0.8, 0.8, 0.82)))
	var sock := Node3D.new()
	sock.position = at + Vector3(0, 1.3, 0)
	v.root.add_child(sock)
	v.sock = sock
	var orange := Prim.mat(Color("ff6a3d"))
	var white := Prim.mat(Color(0.97, 0.97, 0.95))
	var radii := [0.22, 0.17, 0.12, 0.07]
	for k in 3:
		var seg := Prim.cyl(sock, radii[k + 1], radii[k], 0.32, 6, Vector3(0, 0, -(0.16 + k * 0.32)), orange if k % 2 == 0 else white)
		seg.rotation.x = deg_to_rad(-90.0)

## A landing happened on this end: flash its threshold.
func glow(runway: int, end: int) -> void:
	if DebugFlags.off("glow"):
		return
	if runway * 2 + end < cur.glow_born.size():
		cur.glow_born[runway * 2 + end] = Time.get_ticks_msec()

## Bright thresholds on the ends the wind allows, dull ones on the others.
func show_active(w: Wind) -> void:
	for r in Airports.rw_count():
		for e in 2:
			cur.active[r * 2 + e] = w.is_active(r, e)

## The pre-warm draws every airport at once; afterwards only the current one stays visible.
func show_all(on: bool) -> void:
	for i in variants.size():
		variants[i].root.visible = on or i == selected
		for u in variants[i].ups:      # (every upgrade's scenery is drawn too, so none of it is first seen mid-game)
			u[0].visible = true if on else Save.upgrade_level(u[1]) >= u[2]

func reset() -> void:
	for v in variants:
		v.glow_born.fill(0)

func _process(delta: float) -> void:
	if cur == null:
		return
	var now := Time.get_ticks_msec()
	for d in cur.dishes:
		d.rotation.y += delta * 1.8
	var blink := 1.6 if int(now / 600.0) % 2 == 0 else 0.0
	for lm in cur.mast_lights:
		lm.emission_energy_multiplier = blink
		lm.albedo_color = Color(1.0, 0.2, 0.15) if blink > 0.0 else Color(0.55, 0.16, 0.13)
	for k in cur.thr_mats.size():
		var age := (now - cur.glow_born[k]) / 600.0
		var flash := 0.0 if cur.glow_born[k] == 0 or age >= 1.0 else 2.5 * (1.0 - age)
		var m := cur.thr_mats[k]
		var on := cur.active[k]
		m.albedo_color = cur.thr_colors[k] if on else Color(0.38, 0.39, 0.42)
		m.emission_energy_multiplier = (0.45 if on else 0.0) + flash
	_animate_ground(delta, now)
	if wind != null and cur.sock != null:
		_sock_deg += wrapf(wind.toward_deg() - _sock_deg, -180.0, 180.0) * minf(delta * 2.5, 1.0)
		var wiggle := sin(now / 260.0) * 6.0
		cur.sock.rotation.y = -deg_to_rad(_sock_deg + wiggle)
		cur.sock.rotation.x = deg_to_rad(sin(now / 190.0) * 4.0)


# ---------- Upgrade scenery: each purchased upgrade can be seen on the airport ----------

## Is the point `p` clear of runways, pads, lanes, mountains, the tower and the windsock (with `r` to spare)?
func _spot_free(p: Vector2, r: float, bound: float = 6.0) -> bool:
	for i in Airports.rw_count():
		var a := Airports.end_threshold(i, 0)
		var b := Airports.end_far(i, 0)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) < Airports.rw_width(i) * 0.5 + r + 0.15:
			return false
	for pad in Airports.pads():
		if p.distance_to(pad["center"]) < pad["radius"] + r:
			return false
	for lane in Airports.lanes():
		var h := deg_to_rad(lane["heading"])
		var dir := Vector2(sin(h), -cos(h))
		var a2: Vector2 = lane["center"] - dir * lane["length"] * 0.5
		var ab2: Vector2 = dir * lane["length"]
		var t2 := clampf((p - a2).dot(ab2) / maxf(ab2.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a2 + ab2 * t2) < lane["width"] * 0.5 + r + 0.3:
			return false
	for hz in Airports.hazards():
		if p.distance_to(hz["center"]) < hz["radius"] + r:
			return false
	if p.distance_to(Airports.tower_pos()) < 0.8 + r or p.distance_to(Airports.windsock_pos()) < 0.5 + r or p.distance_to(_hangar_at) < 1.0 + r:
		return false
	return absf(p.x) < 4.6 and absf(p.y) < bound

## Up to `n` free spots on rings around `c`, at least `spacing` apart.
func _find_spots(c: Vector2, n: int, r: float, spacing: float, radii: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for ring in radii:
		for k in 12:
			var p: Vector2 = c + Vector2(cos(k * TAU / 12.0 + 0.4), sin(k * TAU / 12.0 + 0.4)) * ring
			if not _spot_free(p, r):
				continue
			var ok := true
			for q in out:
				if q.distance_to(p) < spacing:
					ok = false
			if ok:
				out.append(p)
				if out.size() >= n:
					return out
	return out

func _upgrade_props(v: AirportScene) -> void:
	var root := v.root
	var tower := Airports.tower_pos()
	var metal := Prim.mat(Color(0.78, 0.8, 0.84))
	var dark := Prim.mat(Color(0.2, 0.22, 0.26))
	# Radar: up to three turning dishes around the tower.
	var spots := _find_spots(tower, 3, 0.35, 0.8, [1.2, 1.6, 2.1])
	for k in spots.size():
		var holder := Node3D.new()
		holder.position = Vector3(spots[k].x, 0.0, spots[k].y)
		root.add_child(holder)
		Prim.cyl(holder, 0.05, 0.06, 0.7, 5, Vector3(0, 0.35, 0), metal)
		var turret := Node3D.new()
		turret.position = Vector3(0, 0.78, 0)
		holder.add_child(turret)
		var dish := Prim.cyl(turret, 0.36, 0.04, 0.16, 8, Vector3(0, 0.0, -0.1), metal)
		dish.rotation.x = deg_to_rad(-62.0)
		Prim.box(turret, Vector3(0.05, 0.05, 0.3), Vector3(0, 0.12, -0.12), dark, false)
		v.dishes.append(turret)
		v.ups.append([holder, "radar", k + 1])
	# Better Comms: radio masts with blinking beacons.
	spots = _find_spots(tower, 3, 0.3, 0.8, [2.4, 2.9, 3.4])
	for k in spots.size():
		var holder := Node3D.new()
		holder.position = Vector3(spots[k].x, 0.0, spots[k].y)
		root.add_child(holder)
		Prim.cyl(holder, 0.03, 0.07, 1.6, 4, Vector3(0, 0.8, 0), metal)
		Prim.box(holder, Vector3(0.5, 0.04, 0.04), Vector3(0, 1.25, 0), metal, false)
		var lm := Prim.mat(Color(1.0, 0.2, 0.15))
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.15, 0.1)
		lm.emission_energy_multiplier = 0.0
		v.mast_lights.append(lm)
		Prim.cyl(holder, 0.07, 0.07, 0.12, 6, Vector3(0, 1.64, 0), lm, false)
		v.ups.append([holder, "comms", k + 1])
	# Tower Staff: a terminal annex, then a bigger one, then a flag.
	spots = _find_spots(tower, 3, 0.55, 1.0, [1.9, 2.4, 2.9])
	for k in spots.size():
		var holder := Node3D.new()
		holder.position = Vector3(spots[k].x, 0.0, spots[k].y)
		root.add_child(holder)
		if k == 2:
			Prim.cyl(holder, 0.03, 0.03, 1.1, 4, Vector3(0, 0.55, 0), metal, false)
			Prim.box(holder, Vector3(0.5, 0.3, 0.03), Vector3(0.25, 0.95, 0), Prim.mat(Color(0.9, 0.2, 0.2)), false)
		else:
			Prim.box(holder, Vector3(0.9 + 0.3 * k, 0.4, 0.55), Vector3(0, 0.2, 0), Prim.mat(Color(0.88, 0.85, 0.78)))
			Prim.box(holder, Vector3(0.96 + 0.3 * k, 0.1, 0.62), Vector3(0, 0.45, 0), Prim.mat(Color(0.55, 0.3, 0.25)))
		v.ups.append([holder, "tower", k + 1])
	# Holding Fixes: marker cones (two more each level) out in the airspace.
	var cone_a := Prim.mat(Color(1.0, 0.5, 0.1))
	var cone_b := Prim.mat(Color(0.97, 0.97, 0.95))
	var fix_pos: Array[Vector2] = []
	for z in [-1.5, 1.0, -3.2, 2.6, -4.6, 4.4, 0.0, -2.2, 3.4, -5.4, 5.4]:
		for x in [-4.2, 4.2, -3.6, 3.6]:
			fix_pos.append(Vector2(x, z))
	var placed := 0
	for p in fix_pos:
		if placed >= 6 or not _spot_free(p, 0.5):
			continue
		var near_other := false
		for u in v.ups:
			if u[1] == "holding" and Vector2(u[0].position.x, u[0].position.z).distance_to(p) < 1.6:
				near_other = true
		if near_other:
			continue
		var holder := Node3D.new()
		holder.position = Vector3(p.x, 0.0, p.y)
		root.add_child(holder)
		Prim.cyl(holder, 0.0, 0.22, 0.5, 6, Vector3(0, 0.25, 0), cone_a)
		Prim.cyl(holder, 0.0, 0.12, 0.2, 6, Vector3(0, 0.44, 0), cone_b, false)
		v.ups.append([holder, "holding", 1 + placed / 2])
		placed += 1
	# Approach Control: rows of approach lights behind every runway end (3, 6, then 9 of them).
	var light := Prim.mat(Color(1.0, 0.95, 0.7))
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for r in Airports.rw_count():
		for e in 2:
			var thr := Airports.end_threshold(r, e)
			var dir := Airports.end_dir(r, e)
			var side := Vector2(-dir.y, dir.x)
			for k in 9:
				var p := thr - dir * (0.9 + k * 0.42) + side * (0.0 if k % 3 == 0 else (0.3 if k % 3 == 1 else -0.3))
				if not _spot_free(p, 0.1, 8.0):
					continue
				var node := Prim.box(root, Vector3(0.14, 0.1, 0.14), Vector3(p.x, 0.05, p.y), light, false)
				v.ups.append([node, "approach", 1 + k / 3])
	# Fast Turnoffs: angled exit taxiways off each runway (2, 4, then 6).
	var taxi := Prim.mat(Tuning.runway_asphalt.lightened(0.05))
	for r in Airports.rw_count():
		var rr := Node3D.new()
		rr.position = Vector3(Airports.rw_center(r).x, 0.0, Airports.rw_center(r).y)
		rr.rotation.y = -deg_to_rad(Airports.rw_heading_deg(r))
		root.add_child(rr)
		var len := Airports.rw_length(r)
		var w := Airports.rw_width(r)
		for k in 6:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var z := (0.34 - 0.07 * (k / 2)) * len * (1.0 if (k / 2) % 2 == 0 else -1.0)
			var strip := Prim.box(rr, Vector3(0.32, 0.1, 1.3), Vector3(sx * (w * 0.5 + 0.35), 0.05, z), taxi)
			strip.rotation.y = deg_to_rad(sx * 35.0)
			v.ups.append([strip, "turnoffs", 1 + k / 2])

## Show each upgrade's scenery that has been bought (called at start-up and after a purchase).
func show_upgrades() -> void:
	for v in variants:
		for u in v.ups:
			u[0].visible = Save.upgrade_level(u[1]) >= u[2]

func upgrade_nodes_visible(id: String) -> int:
	var n := 0
	for u in cur.ups:
		if u[1] == id and u[0].visible:
			n += 1
	return n
