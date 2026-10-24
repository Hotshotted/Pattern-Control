class_name CloudShadows
extends Node3D
## Three small cloud shadows drifting slowly across the ground, with the wind: soft-edged dark shapes (the shadow colour at about 12%).
## Nothing white and nothing over the whole field: there is no haze or fog layer in the game. They are drawn on the ground, before the
## runways, paths and aircraft (which are lifted above them) and below the interface; ?nolife and the web wind test take them away.

const COUNT := 3
const ALPHA := 0.12
const SPEED := 0.12                       # units a second
const PRIORITY := -20                     # after the ground and its scenery, before the path ribbons (-1 / 0) and the lifted aircraft / runways (2+)
const SIZES := [Vector2(3.4, 2.1), Vector2(2.8, 1.8), Vector2(3.8, 2.3)]

var wind: Wind
var _shadows: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []

func _ready() -> void:
	var sh := preload("res://shaders/cloud_shadow.gdshader")
	for i in COUNT:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = SIZES[i]
		mi.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = PRIORITY
		m.set_shader_parameter("seed", float(i) * 1.7)
		m.set_shader_parameter("alpha", ALPHA)
		m.set_shader_parameter("tint", Shadow.COLOR)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(-4.0 + i * 3.8, 0.12, -8.0 + i * 8.0)
		add_child(mi)
		_shadows.append(mi)
		_mats.append(m)

func _process(delta: float) -> void:
	var on := DebugFlags.life_enabled() and not DebugFlags.windtest_enabled()
	var drift := Vector3(0.9, 0.0, 0.3).normalized()
	if wind != null:
		var tw := deg_to_rad(wind.toward_deg())
		drift = Vector3(sin(tw), 0.0, -cos(tw))
	for i in COUNT:
		var mi := _shadows[i]
		mi.visible = on
		if not on:
			continue
		mi.position += drift * (SPEED * (0.8 + 0.2 * i)) * delta
		if absf(mi.position.x) > 7.0:
			mi.position.x = -signf(mi.position.x) * 6.5
		if absf(mi.position.z) > 12.5:
			mi.position.z = -signf(mi.position.z) * 12.0

func count() -> int:
	return COUNT

func material(i: int) -> ShaderMaterial:
	return _mats[i]

func shadow(i: int) -> MeshInstance3D:
	return _shadows[i]
