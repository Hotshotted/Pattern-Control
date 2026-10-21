class_name Diorama
extends Node3D
## The menu's living backdrop: the current airport with a small aircraft landing and rolling out, another taxiing off the
## runway, the windsock swinging (the airfield already does that) and clouds drifting over. It has its own small pool of
## aircraft (a second, scenic Traffic with no timers, conflicts or scoring) and a few cloud quads. Built once and
## pre-warmed; during a shift it is hidden and does nothing.

const CLOUDS := 5
const MAX_ALPHA := 0.5

var traffic: Traffic
var wind: Wind
var active := false
var _clouds: Array[MeshInstance3D] = []
var _cloud_mats: Array[ShaderMaterial] = []
var _fade := 0.0
var _next := 1.0
var _airport := -1
var _taxi: Aircraft
var _taxi_left := 0.0
var _rng := RandomNumberGenerator.new()
var _prewarming := false
var _landing := false              # an aircraft is on final or rolling out

func _ready() -> void:
	_rng.seed = 7
	traffic = Traffic.new()
	traffic.scenic = true
	traffic.pool_n = 3
	traffic.auto_spawn = false
	add_child(traffic)
	traffic.landed.connect(_on_landed)
	var sh := preload("res://shaders/cloud.gdshader")
	for i in CLOUDS:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(5.0 + 1.2 * (i % 3), 2.6 + 0.5 * (i % 2))
		mi.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = -10
		m.set_shader_parameter("seed", float(i) * 1.7)
		m.set_shader_parameter("alpha", 0.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_clouds.append(mi)
		_cloud_mats.append(m)
		mi.position = Vector3(-7.0 + i * 3.6, 2.6, -9.0 + i * 4.3)
	visible = true

func _process(delta: float) -> void:
	tick(delta)

## Advance the scene (the tests call this directly).
func tick(delta: float) -> void:
	if _prewarming:
		return
	_fade = move_toward(_fade, 1.0 if active else 0.0, delta / 0.6)
	if _airport != Airports.current:
		_airport = Airports.current
		reset()
	if _fade <= 0.0 and not active:
		if traffic.active_count() > 0:
			reset()
		for c in _clouds:
			c.visible = false
		return
	var drift := Vector3(0.28, 0.0, 0.1)
	if wind != null:
		var tw := deg_to_rad(wind.toward_deg())
		drift = Vector3(sin(tw), 0.0, -cos(tw)) * 0.3
	for i in CLOUDS:
		var c := _clouds[i]
		c.visible = true
		c.position += drift * delta * (0.7 + 0.15 * i)
		if absf(c.position.x) > 9.0:
			c.position.x = -signf(c.position.x) * 8.5
		if absf(c.position.z) > 13.0:
			c.position.z = -signf(c.position.z) * 12.5
		_cloud_mats[i].set_shader_parameter("alpha", MAX_ALPHA * _fade)
	if not active:
		return
	traffic.step(delta)
	if _taxi != null:
		_taxi_left -= delta
		if not _taxi.active() or _taxi_left <= 0.0:
			if _taxi.active():
				traffic.lose(_taxi)
			_taxi = null
	_next -= delta
	if _next <= 0.0 and not _landing:
		_land()
		_next = _rng.randf_range(2.5, 5.0)

## A fresh start (the airport changed, or the menu closed): nothing in the air.
func reset() -> void:
	traffic.release_all()
	_taxi = null
	_landing = false
	_next = 0.8

## One aircraft on a stabilised final onto a runway end the wind allows.
func _land() -> void:
	var n := Airports.rw_count()
	if n <= 0:
		return
	var r := _rng.randi() % n
	var e := 0
	if wind != null and not wind.is_active(r, 0):
		e = 1
	var thr := Airports.end_threshold(r, e)
	var dir := Airports.end_dir(r, e)
	var types := [Aircraft.Type.SMALL, Aircraft.Type.MEDIUM, Aircraft.Type.JET]
	var type: int = types[_rng.randi() % 3]
	var p := traffic.place(r, thr - dir * 4.0, atan2(dir.x, -dir.y), type, true)
	if p == null:
		return
	p.timer_left = 999.0
	p.push(thr)
	p.push(Airports.end_far(r, e))
	p.cleared = true
	p.land_end = e
	_landing = true

## Touchdown and rollout are done: the aircraft turns off and taxis away along the runway edge.
func _on_landed(p: Aircraft) -> void:
	_landing = false
	var side := Vector2(-sin(p.heading), cos(p.heading)) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var t := traffic.place(p.runway, p.pos, p.heading, Aircraft.Type.SMALL, true)
	if t == null:
		return
	t.speed = 0.35
	t.timer_left = 999.0
	var fwd := Vector2(sin(p.heading), -cos(p.heading))
	t.push(p.pos + fwd * 0.25 + side * 0.35)
	t.push(p.pos + fwd * 0.3 + side * 2.2)
	_taxi = t
	_taxi_left = 5.0

## The start-up pre-warm: everything drawn once.
func prewarm(on: bool) -> void:
	_prewarming = on
	if on:
		traffic.prewarm_show()
	else:
		traffic.prewarm_hide()
	for i in CLOUDS:
		_clouds[i].visible = on
		_cloud_mats[i].set_shader_parameter("alpha", MAX_ALPHA if on else 0.0)
