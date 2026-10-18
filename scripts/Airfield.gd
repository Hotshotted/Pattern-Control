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

var wind: Wind                        # set by Main
var variants: Array[AirportScene] = []
var cur: AirportScene
var selected := 0
var _sock_deg := 0.0

func _ready() -> void:
	var keep := Airports.current
	for a in Airports.COUNT:
		Airports.current = a
		variants.append(_build_airport())
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
	Prim.box(root, Vector3(40.0, 0.2, 70.0), Vector3(0, -0.1, 0), Prim.mat(ground), false)
	var stripe := Prim.mat(ground.lightened(0.07))
	var water: bool = Airports.def().get("water", false)
	if not water:
		for i in range(-5, 6):   # mowing stripes
			if i % 2 == 0:
				Prim.box(root, Vector3(40.0, 0.02, 3.0), Vector3(0, 0.005, i * 3.0), stripe, false)
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
	var tp := Airports.tower_pos()
	_tower(root, Vector3(tp.x, 0.0, tp.y))
	var sp := Airports.windsock_pos()
	_windsock(v, Vector3(sp.x, 0.0, sp.y))
	if not water:
		_trees(root)
	return v

func _trees(root: Node3D) -> void:
	var leaf := Prim.mat(Color(0.2, 0.46, 0.25))
	var trunk := Prim.mat(Color(0.45, 0.3, 0.18))
	for t in [Vector2(-4.4, 6.4), Vector2(-3.6, 7.6), Vector2(4.3, 6.9), Vector2(4.5, -6.5), Vector2(-4.4, -6.9), Vector2(3.7, -7.8), Vector2(-4.2, -3.9), Vector2(4.5, 4.4)]:
		var blocked := false
		for h in Airports.hazards():
			if (h["center"] as Vector2).distance_to(t) < h["radius"] + 0.7:
				blocked = true
		if blocked:
			continue
		Prim.cyl(root, 0.05, 0.05, 0.4, 5, Vector3(t.x, 0.2, t.y), trunk)
		Prim.cyl(root, 0.0, 0.42, 0.9, 6, Vector3(t.x, 0.85, t.y), leaf)

func _runway(v: AirportScene, i: int) -> void:
	var col := Airports.rw_color(i)
	var root := Node3D.new()
	root.position = Vector3(Airports.rw_center(i).x, 0.0, Airports.rw_center(i).y)
	root.rotation.y = -deg_to_rad(Airports.rw_heading_deg(i))
	v.root.add_child(root)
	var len := Airports.rw_length(i)
	var w := Airports.rw_width(i)
	Prim.box(root, Vector3(w, 0.12, len), Vector3(0, 0.06, 0), Prim.mat(Tuning.runway_asphalt))
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

## A round helipad with an H.
func _pad(root: Node3D, pad: Dictionary) -> void:
	var c: Vector2 = pad["center"]
	var r: float = pad["radius"]
	Prim.cyl(root, r, r, 0.1, 14, Vector3(c.x, 0.05, c.y), Prim.mat(Tuning.runway_asphalt))
	Prim.cyl(root, r * 0.86, r * 0.86, 0.12, 14, Vector3(c.x, 0.05, c.y), Prim.mat(pad["color"]), false)
	Prim.cyl(root, r * 0.74, r * 0.74, 0.14, 14, Vector3(c.x, 0.06, c.y), Prim.mat(Tuning.runway_asphalt), false)
	var white := Prim.mat(Color(0.95, 0.95, 0.92))
	Prim.box(root, Vector3(0.1, 0.16, r * 0.9), Vector3(c.x - r * 0.28, 0.07, c.y), white, false)
	Prim.box(root, Vector3(0.1, 0.16, r * 0.9), Vector3(c.x + r * 0.28, 0.07, c.y), white, false)
	Prim.box(root, Vector3(r * 0.56, 0.16, 0.1), Vector3(c.x, 0.07, c.y), white, false)

## A strip of water marked out for seaplanes.
func _lane(root: Node3D, lane: Dictionary) -> void:
	var n := Node3D.new()
	n.position = Vector3(lane["center"].x, 0.0, lane["center"].y)
	n.rotation.y = -deg_to_rad(lane["heading"])
	root.add_child(n)
	var len: float = lane["length"]
	var w: float = lane["width"]
	Prim.box(n, Vector3(w, 0.05, len), Vector3(0, 0.05, 0), Prim.mat(Color(0.3, 0.68, 0.85)), false)
	var edge := Prim.mat(lane["color"])
	for s in [-1.0, 1.0]:
		Prim.box(n, Vector3(0.07, 0.08, len), Vector3(s * w * 0.5, 0.06, 0), edge, false)
		for k in 3:
			Prim.cyl(n, 0.1, 0.1, 0.2, 5, Vector3(s * (w * 0.5 + 0.18), 0.1, (k - 1) * len * 0.42), Prim.mat(Color(1.0, 0.5, 0.15)))
	var white := Prim.mat(Color(0.95, 0.97, 1.0))
	for k in int(len / 1.0) - 1:
		Prim.box(n, Vector3(0.08, 0.08, 0.34), Vector3(0, 0.07, -len * 0.5 + 0.9 + k * 1.0), white, false)

## A low-poly mountain: two peaks with snow caps. Its radius is the no-fly zone.
func _mountain(root: Node3D, c: Vector2, r: float) -> void:
	var rock := Prim.mat(Color(0.48, 0.46, 0.44))
	var rock2 := Prim.mat(Color(0.56, 0.54, 0.5))
	var snow := Prim.mat(Color(0.96, 0.97, 1.0))
	Prim.cyl(root, 0.0, r * 0.95, r * 1.5, 7, Vector3(c.x, r * 0.75, c.y), rock)
	Prim.cyl(root, 0.0, r * 0.4, r * 0.55, 7, Vector3(c.x, r * 1.25, c.y), snow)
	Prim.cyl(root, 0.0, r * 0.6, r * 0.9, 6, Vector3(c.x + r * 0.55, r * 0.45, c.y + r * 0.2), rock2)

func _tower(root: Node3D, at: Vector3) -> void:
	var base := Prim.mat(Color(0.85, 0.83, 0.78))
	Prim.box(root, Vector3(0.9, 0.5, 0.7), at + Vector3(0, 0.25, 0), base)
	Prim.cyl(root, 0.13, 0.17, 0.9, 6, at + Vector3(0, 0.95, 0), Prim.mat(Color(0.7, 0.7, 0.72)))
	Prim.box(root, Vector3(0.56, 0.24, 0.56), at + Vector3(0, 1.52, 0), Prim.mat(Color(0.4, 0.7, 0.85)))
	Prim.cyl(root, 0.0, 0.42, 0.22, 4, at + Vector3(0, 1.75, 0), Prim.mat(Color(0.8, 0.25, 0.2)))

## A pole with a striped cone on top. The cone's pivot turns to point downwind.
func _windsock(v: AirportScene, at: Vector3) -> void:
	Prim.cyl(v.root, 0.04, 0.05, 1.3, 5, at + Vector3(0, 0.65, 0), Prim.mat(Color(0.8, 0.8, 0.82)))
	var sock := Node3D.new()
	sock.position = at + Vector3(0, 1.3, 0)
	v.root.add_child(sock)
	v.sock = sock
	var orange := Prim.mat(Color(1.0, 0.45, 0.1))
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

func reset() -> void:
	for v in variants:
		v.glow_born.fill(0)

func _process(delta: float) -> void:
	if cur == null:
		return
	var now := Time.get_ticks_msec()
	for k in cur.thr_mats.size():
		var age := (now - cur.glow_born[k]) / 600.0
		var flash := 0.0 if cur.glow_born[k] == 0 or age >= 1.0 else 2.5 * (1.0 - age)
		var m := cur.thr_mats[k]
		var on := cur.active[k]
		m.albedo_color = cur.thr_colors[k] if on else Color(0.38, 0.39, 0.42)
		m.emission_energy_multiplier = (0.45 if on else 0.0) + flash
	if wind != null and cur.sock != null:
		_sock_deg += wrapf(wind.toward_deg() - _sock_deg, -180.0, 180.0) * minf(delta * 2.5, 1.0)
		var wiggle := sin(now / 260.0) * 6.0
		cur.sock.rotation.y = -deg_to_rad(_sock_deg + wiggle)
		cur.sock.rotation.x = deg_to_rad(sin(now / 190.0) * 4.0)
