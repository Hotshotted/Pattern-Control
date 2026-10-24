class_name Shadow
extends RefCounted
## Cozy Airfield shadows: blue-grey #3B4A6B at 26%, soft-edged, thrown toward the lower-right (a building's shadow is half as long
## as the building is high). The soft edges are baked into small textures ONCE; nothing is ever blurred at run time.

const COLOR := Color("3b4a6b")
const ALPHA := 0.26
const SIZE := 64

## Every shadow with an offset from the thing that casts it, so the offsets can grow as the sun gets lower over a shift:
## [node, its base position, the offset it already has (x, z)].
static var _casters: Array = []
static var _time := -1.0
const OFFSET_GROWTH := 0.3          # the offsets are 30% longer at the end of a shift

static var _disc: Texture2D
static var _rect: Texture2D
static var _plane: Texture2D

## The shapes are baked to assets/textures/*.png by tools/bake_textures.gd (run it after changing a formula below) and loaded: nothing
## is computed on the player's phone. (If a file is missing the shape is computed, so a fresh checkout still runs.)
const BAKED := "res://assets/textures/shadow_%s.png"

static func _image(f: Callable) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((x + 0.5) / SIZE * 2.0 - 1.0, (y + 0.5) / SIZE * 2.0 - 1.0)
			var a := clampf(f.call(p), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return img

static func _make(shape: String, f: Callable) -> Texture2D:
	var path := BAKED % shape
	if ResourceLoader.exists(path):
		return load(path)
	return ImageTexture.create_from_image(_image(f))

static func _disc_f(p: Vector2) -> float:
	return 1.0 - smoothstep(0.3, 1.0, p.length())

static func _rect_f(p: Vector2) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - Vector2(0.62, 0.62)
	var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
	return 1.0 - smoothstep(-0.05, 0.38, sd)

static func _plane_f(p: Vector2) -> float:
	var fus := 1.0 - (p / Vector2(0.16, 0.95)).length()
	var wng := 1.0 - (p / Vector2(0.95, 0.2)).length()
	var tail := 1.0 - ((p - Vector2(0.0, 0.75)) / Vector2(0.35, 0.1)).length()
	return smoothstep(0.0, 0.55, maxf(maxf(fus, wng), tail))

## The images the bake tool writes: shape name -> Image.
static func baked_images() -> Dictionary:
	return {"disc": _image(_disc_f), "rect": _image(_rect_f), "plane": _image(_plane_f)}

## A soft round shadow (trees, tanks, the pad, a mountain).
static func disc() -> Texture2D:
	if _disc == null:
		_disc = _make("disc", _disc_f)
	return _disc

## A soft rounded rectangle filling the middle 62% of the quad (buildings, the tower, trucks).
static func rect() -> Texture2D:
	if _rect == null:
		_rect = _make("rect", _rect_f)
	return _rect

## A soft little aircraft: a fuselage, a wing and a tail (the nose is up in the texture).
static func plane() -> Texture2D:
	if _plane == null:
		_plane = _make("plane", _plane_f)
	return _plane

## The material of a ground shadow: unshaded, translucent, textured with one of the baked shapes. `alpha_scale` 1 = the standard 26%.
static func material(tex: Texture2D, alpha_scale: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(COLOR, ALPHA * alpha_scale)
	m.albedo_texture = tex
	return m

## Remember a shadow quad whose position includes `offset` (x, z) from its caster.
static func register(node: MeshInstance3D, offset: Vector2) -> void:
	_casters.append([node, node.position, offset])
	if _time > 0.0:
		_place(_casters[_casters.size() - 1], 1.0 + OFFSET_GROWTH * _time)

static func _place(c: Array, scale: float) -> void:
	var n: MeshInstance3D = c[0]
	if is_instance_valid(n):
		var base: Vector3 = c[1]
		var off: Vector2 = c[2]
		n.position = base + Vector3(off.x, 0.0, off.y) * (scale - 1.0)

## How much longer the offsets are at shift time `t` (0..1).
static func offset_scale(t: float) -> float:
	return 1.0 + OFFSET_GROWTH * clampf(t, 0.0, 1.0)

## The shift is `t` of the way through (0..1): every registered shadow moves out to its offset at that time.
static func set_time(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	if absf(t - _time) < 0.002:
		return
	_time = t
	var s := offset_scale(t)
	var i := 0
	while i < _casters.size():
		if not is_instance_valid(_casters[i][0]):
			_casters.remove_at(i)
			continue
		_place(_casters[i], s)
		i += 1
