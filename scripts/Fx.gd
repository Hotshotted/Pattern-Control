class_name Fx
extends Node3D
## Landing / crash particle bursts (CPUParticles3D). Everything is created ONCE at start-up and
## reused round-robin, so a landing allocates nothing.

const EMITTERS := 4
const PUFFS := 3
const SPARKLES := 3

var _emitters: Array[CPUParticles3D] = []
var _next := 0
var _puffs: Array[CPUParticles3D] = []
var _sparkles: Array[CPUParticles3D] = []
var _next_puff := 0
var _next_sparkle := 0

## A round dot texture (a soft rim when `soft`, else a crisp edge): the particles are dots, never squares.
func _dot_texture(soft: bool) -> Texture2D:
	# (a plain RGBA8 image made once: a GradientTexture2D is filled in lazily, which some phones' browsers draw as a missing texture)
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var edge := 0.3 if soft else 0.85
	for y in 48:
		for x in 48:
			var d := Vector2((x + 0.5) / 24.0 - 1.0, (y + 0.5) / 24.0 - 1.0).length()
			var al := 1.0 if d <= edge else clampf(1.0 - (d - edge) / (1.0 - edge), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, al))
	return ImageTexture.create_from_image(img)

## A four-pointed sparkle: the gold celebration stars.
func _star_texture() -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 48:
			var u := absf((x + 0.5) / 24.0 - 1.0)
			var v := absf((y + 0.5) / 24.0 - 1.0)
			var d := pow(u, 0.55) + pow(v, 0.55)
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 6.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _dot_texture(false)
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
	# Touchdown dust: soft grey-white puffs that swell and fade.
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_texture = _dot_texture(true)
	var pquad := QuadMesh.new()
	pquad.size = Vector2(0.4, 0.4)
	pquad.material = pmat
	var pramp := Gradient.new()
	pramp.colors = PackedColorArray([Color(0.95, 0.93, 0.88, 0.0), Color(0.95, 0.93, 0.88, 0.55), Color(0.95, 0.93, 0.88, 0.0)])
	pramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	for i in PUFFS:
		var p := CPUParticles3D.new()
		p.mesh = pquad
		p.color_ramp = pramp
		p.scale_amount_curve = grow
		p.amount = 9
		p.lifetime = 0.8
		p.one_shot = true
		p.explosiveness = 0.9
		p.local_coords = false
		p.direction = Vector3(0, 0.4, 0)
		p.spread = 90.0
		p.initial_velocity_min = 0.3
		p.initial_velocity_max = 1.3
		p.gravity = Vector3.ZERO
		p.emitting = false
		add_child(p)
		_puffs.append(p)
	# Celebration sparkles: small gold stars thrown up and falling back.
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = _star_texture()
	var squad := QuadMesh.new()
	squad.size = Vector2(0.3, 0.3)
	squad.material = smat
	var sramp := Gradient.new()
	sramp.colors = PackedColorArray([Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.8, 0.2, 1.0), Color(1.0, 0.8, 0.2, 0.0)])
	sramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	for i in SPARKLES:
		var p := CPUParticles3D.new()
		p.mesh = squad
		p.color_ramp = sramp
		p.amount = 14
		p.lifetime = 0.9
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.direction = Vector3(0, 1, 0)
		p.spread = 70.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0, -7.0, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.2
		p.emitting = false
		add_child(p)
		_sparkles.append(p)
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

## A puff of dust at a spot (the touchdown).
func puff(at: Vector2) -> void:
	if DebugFlags.off("burst"):
		return
	var p := _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % PUFFS
	p.position = Vector3(at.x, 0.3, at.y)
	p.restart()
	p.emitting = true

## Gold sparkles thrown up from a spot (a landing, a star).
func sparkle(at: Vector2) -> void:
	if DebugFlags.off("burst"):
		return
	var p := _sparkles[_next_sparkle]
	_next_sparkle = (_next_sparkle + 1) % SPARKLES
	p.position = Vector3(at.x, 0.5, at.y)
	p.restart()
	p.emitting = true

func clear() -> void:
	for p in _emitters:
		p.emitting = false
	for p in _puffs:
		p.emitting = false
	for p in _sparkles:
		p.emitting = false

## Pre-warm: every emitter drawing at once.
func prewarm(at: Vector2) -> void:
	for i in EMITTERS:
		burst(at + Vector2(-2.0 + i * 1.4, 0.0), Airports.rw_color(i % Airports.rw_count()), i == 3)
	for i in PUFFS:
		puff(at + Vector2(-1.0 + i * 1.0, 1.2))
	for i in SPARKLES:
		sparkle(at + Vector2(-1.0 + i * 1.0, -1.2))
