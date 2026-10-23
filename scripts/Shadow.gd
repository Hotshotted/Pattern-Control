class_name Shadow
extends RefCounted
## Cozy Airfield shadows: blue-grey #3B4A6B at 26%, soft-edged, thrown toward the lower-right (a building's shadow is half as long
## as the building is high). The soft edges are baked into small textures ONCE; nothing is ever blurred at run time.

const COLOR := Color("3b4a6b")
const ALPHA := 0.26
const SIZE := 64

static var _disc: ImageTexture
static var _rect: ImageTexture
static var _plane: ImageTexture

static func _make(f: Callable) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((x + 0.5) / SIZE * 2.0 - 1.0, (y + 0.5) / SIZE * 2.0 - 1.0)
			var a := clampf(f.call(p), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

## A soft round shadow (trees, tanks, the pad, a mountain).
static func disc() -> ImageTexture:
	if _disc == null:
		_disc = _make(func(p: Vector2) -> float: return 1.0 - smoothstep(0.3, 1.0, p.length()))
	return _disc

## A soft rounded rectangle filling the middle 62% of the quad (buildings, the tower, trucks).
static func rect() -> ImageTexture:
	if _rect == null:
		_rect = _make(func(p: Vector2) -> float:
			var q := Vector2(absf(p.x), absf(p.y)) - Vector2(0.62, 0.62)
			var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			return 1.0 - smoothstep(-0.05, 0.38, sd))
	return _rect

## A soft little aircraft: a fuselage, a wing and a tail (the nose is up in the texture).
static func plane() -> ImageTexture:
	if _plane == null:
		_plane = _make(func(p: Vector2) -> float:
			var fus := 1.0 - (p / Vector2(0.16, 0.95)).length()
			var wng := 1.0 - (p / Vector2(0.95, 0.2)).length()
			var tail := 1.0 - ((p - Vector2(0.0, 0.75)) / Vector2(0.35, 0.1)).length()
			return smoothstep(0.0, 0.55, maxf(maxf(fus, wng), tail)))
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
