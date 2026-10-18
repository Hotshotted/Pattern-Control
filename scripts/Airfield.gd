class_name Airfield
extends Node3D
## The static scene: grass, two runways (each in its colour, with a coloured threshold at the
## approach end), a control tower and a few trees. Built once. A landing makes that runway's
## threshold flash (glow()).

var _glow_mats: Array[StandardMaterial3D] = []
var _glow_born: Array[int] = []

func _ready() -> void:
	var grass := Prim.mat(Tuning.grass_color)
	Prim.box(self, Vector3(40.0, 0.2, 70.0), Vector3(0, -0.1, 0), grass, false)
	var stripe := Prim.mat(Tuning.grass_color.lightened(0.07))
	for i in range(-5, 6):   # mowing stripes
		if i % 2 == 0:
			Prim.box(self, Vector3(40.0, 0.02, 3.0), Vector3(0, 0.005, i * 3.0), stripe, false)
	for i in Airports.rw_count():
		_glow_born.append(0)
		_runway(i)
	_tower(Vector3(0.0, 0.0, 0.2))
	var leaf := Prim.mat(Color(0.2, 0.46, 0.25))
	var trunk := Prim.mat(Color(0.45, 0.3, 0.18))
	for t in [Vector2(-4.4, 6.4), Vector2(-3.6, 7.6), Vector2(4.3, 6.9), Vector2(4.5, -6.5), Vector2(-4.4, -6.9), Vector2(3.7, -7.8), Vector2(-4.2, -3.9), Vector2(4.5, 4.4)]:
		Prim.cyl(self, 0.05, 0.05, 0.4, 5, Vector3(t.x, 0.2, t.y), trunk)
		Prim.cyl(self, 0.0, 0.42, 0.9, 6, Vector3(t.x, 0.85, t.y), leaf)

func _runway(i: int) -> void:
	var col := Airports.rw_color(i)
	var root := Node3D.new()
	root.position = Vector3(Airports.rw_center(i).x, 0.0, Airports.rw_center(i).y)
	root.rotation.y = -deg_to_rad(Airports.rw_heading_deg(i))
	add_child(root)
	var len := Airports.rw_length(i)
	var w := Airports.rw_width(i)
	Prim.box(root, Vector3(w, 0.12, len), Vector3(0, 0.06, 0), Prim.mat(Tuning.runway_asphalt))
	var edge := Prim.mat(col)
	for s in [-1.0, 1.0]:
		Prim.box(root, Vector3(0.08, 0.13, len - 0.1), Vector3(s * (w * 0.5 - 0.1), 0.065, 0), edge, false)
	# The approach end is behind the landing direction: local +z (planes fly toward -z).
	var thr := Prim.mat(col)
	thr.emission_enabled = true
	thr.emission = col
	thr.emission_energy_multiplier = 0.0
	_glow_mats.append(thr)
	Prim.box(root, Vector3(w - 0.3, 0.14, 0.5), Vector3(0, 0.07, len * 0.5 - 0.35), thr, false)
	var white := Prim.mat(Color(0.93, 0.93, 0.9))
	for k in 5:
		Prim.box(root, Vector3(0.09, 0.14, 0.36), Vector3(0, 0.07, len * 0.5 - 1.2 - k * 1.0), white, false)
	for k in 4:   # piano keys just past the threshold block
		Prim.box(root, Vector3(0.08, 0.14, 0.4), Vector3(-0.27 + k * 0.18, 0.07, len * 0.5 - 0.9), white, false)

func _tower(at: Vector3) -> void:
	var base := Prim.mat(Color(0.85, 0.83, 0.78))
	Prim.box(self, Vector3(0.9, 0.5, 0.7), at + Vector3(0, 0.25, 0), base)
	Prim.cyl(self, 0.13, 0.17, 0.9, 6, at + Vector3(0, 0.95, 0), Prim.mat(Color(0.7, 0.7, 0.72)))
	Prim.box(self, Vector3(0.56, 0.24, 0.56), at + Vector3(0, 1.52, 0), Prim.mat(Color(0.4, 0.7, 0.85)))
	Prim.cyl(self, 0.0, 0.42, 0.22, 4, at + Vector3(0, 1.75, 0), Prim.mat(Color(0.8, 0.25, 0.2)))

## A landing happened on this runway: flash its threshold.
func glow(runway: int) -> void:
	if DebugFlags.off("glow"):
		return
	_glow_born[runway] = Time.get_ticks_msec()

func reset() -> void:
	_glow_born.fill(0)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in _glow_born.size():
		var age := (now - _glow_born[i]) / 600.0
		_glow_mats[i].emission_energy_multiplier = 0.0 if _glow_born[i] == 0 or age >= 1.0 else 2.5 * (1.0 - age)
