class_name Fx
extends Node3D
## Landing / crash particle bursts (CPUParticles3D). Everything is created ONCE at start-up and
## reused round-robin, so a landing allocates nothing.

const EMITTERS := 4

var _emitters: Array[CPUParticles3D] = []
var _next := 0

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	var ramp := Gradient.new()   # full colour -> same colour fading out
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	for i in EMITTERS:
		var p := CPUParticles3D.new()
		p.mesh = quad
		p.color_ramp = ramp
		p.amount = Tuning.burst_count
		p.lifetime = Tuning.burst_lifetime
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 6.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.3
		p.emitting = false
		add_child(p)
		_emitters.append(p)

## A burst of `color` at a spot on the field (world x, z).
func burst(at: Vector2, color: Color, big: bool = false) -> void:
	if DebugFlags.off("burst"):
		return
	var p := _emitters[_next]
	_next = (_next + 1) % EMITTERS
	p.position = Vector3(at.x, 0.6, at.y)
	p.color = color
	p.initial_velocity_max = 9.0 if big else 6.0
	p.restart()
	p.emitting = true

func clear() -> void:
	for p in _emitters:
		p.emitting = false

## Pre-warm: every emitter drawing at once.
func prewarm(at: Vector2) -> void:
	for i in EMITTERS:
		burst(at + Vector2(-2.0 + i * 1.4, 0.0), Tuning.runway_colors[i % 2], i == 3)
