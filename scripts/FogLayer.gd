class_name FogLayer
extends MeshInstance3D
## The atmospheric fog: a single big translucent quad above the field, with a shader that makes soft drifting
## waves of mist (shaders/fog_layer.gdshader). It is drawn after the opaque ground and scenery (so they are
## dimmed) and before everything lifted by Prim.lift (aircraft, runways, pads) and the path ribbons, so those
## stay fully readable. Hidden (and free) while there is no fog.

const PRIORITY := -20                  # before the ribbons (-1 / 0) and the lifted aircraft / runways (2+)

var traffic: Traffic
var wind: Wind
var _mat: ShaderMaterial

func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(90.0, 90.0)
	mesh = quad
	position = Vector3(0.0, 0.6, 0.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/fog_layer.gdshader")
	_mat.render_priority = PRIORITY
	material_override = _mat
	visible = false

var _amount := -1.0                  # what the shader has now (it is only written when it changes)
var _max_alpha := -1.0
var _drift := Vector2.INF

func _process(_delta: float) -> void:
	if traffic == null:
		return
	var a := traffic.fog_amount
	visible = a > 0.002
	if not visible:
		return
	if a != _amount:
		_amount = a
		_mat.set_shader_parameter("amount", a)
	if Tuning.fog_max_alpha != _max_alpha:
		_max_alpha = Tuning.fog_max_alpha
		_mat.set_shader_parameter("max_alpha", _max_alpha)
	if wind != null:
		var d := Vector2(sin(deg_to_rad(wind.toward_deg())), -cos(deg_to_rad(wind.toward_deg()))) * 0.6
		if d != _drift:
			_drift = d
			_mat.set_shader_parameter("drift", d)

func shader_material() -> ShaderMaterial:
	return _mat
