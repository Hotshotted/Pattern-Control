class_name LightOverlay
extends CanvasLayer
## Cozy Airfield: one light over the whole field (a ColorRect with shaders/light_overlay.gdshader): a warm glow in the upper-left
## corner, a cool shade in the lower-right and a little static film grain. It sits above the 3D field and below the paths, rings
## and the interface, so readability marks are not tinted. ?nolight switches it off.

const GRAIN := 128

var rect: ColorRect
var time := 0.0
var material: ShaderMaterial

static var _grain: ImageTexture

## The film grain: a small tiled noise image, made once (seeded, so it is the same every run and never changes per frame).
static func grain_texture() -> ImageTexture:
	if _grain == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260
		var img := Image.create(GRAIN, GRAIN, false, Image.FORMAT_L8)
		for y in GRAIN:
			for x in GRAIN:
				var v := rng.randf()
				img.set_pixel(x, y, Color(v, v, v, 1.0))
		_grain = ImageTexture.create_from_image(img)
	return _grain

func _ready() -> void:
	layer = 0
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/light_overlay.gdshader")
	material.set_shader_parameter("grain", grain_texture())
	material.set_shader_parameter("warm", Color("ffd68a"))
	material.set_shader_parameter("cool", Color("2f4a7a"))
	material.set_shader_parameter("warm_amount", 0.35)
	material.set_shader_parameter("cool_amount", 0.20)
	material.set_shader_parameter("grain_amount", 0.08)
	rect.material = material
	add_child(rect)
	rect.visible = DebugFlags.light_enabled()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	material.set_shader_parameter("view_size", get_viewport().get_visible_rect().size)

## Time of day (0 = the shift's start, 1 = its end): the warm glow goes 35% -> 50% and the cool shade 20% -> 30%, linearly.
func set_time(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	material.set_shader_parameter("warm_amount", lerpf(0.35, 0.50, t))
	material.set_shader_parameter("cool_amount", lerpf(0.20, 0.30, t))
	time = t

## Is the light on screen?
func is_on() -> bool:
	return rect != null and rect.visible
