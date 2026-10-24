class_name LightOverlay
extends CanvasLayer
## Cozy Airfield: one light over the whole field (a ColorRect with shaders/light_overlay.gdshader): a warm glow in the upper-left
## corner and a cool shade in the lower-right. It sits above the 3D field and below the paths, rings
## and the interface, so readability marks are not tinted. No grain, no texture. ?nolight switches it off.

var rect: ColorRect
var material: ShaderMaterial
var time := 0.0

func _ready() -> void:
	layer = 0
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/light_overlay.gdshader")
	material.set_shader_parameter("warm", Color("ffd68a"))
	material.set_shader_parameter("cool", Color("2f4a7a"))
	material.set_shader_parameter("warm_amount", 0.35)
	material.set_shader_parameter("cool_amount", 0.20)
	rect.material = material
	add_child(rect)
	rect.visible = DebugFlags.light_enabled()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", vs.y / maxf(vs.x, 1.0))

## Time of day (0 = the shift's start, 1 = its end): the warm glow goes 35% -> 50% and the cool shade 20% -> 30%, linearly.
func set_time(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	material.set_shader_parameter("warm_amount", lerpf(0.35, 0.50, t))
	material.set_shader_parameter("cool_amount", lerpf(0.20, 0.30, t))
	time = t

## Is the light on screen?
func is_on() -> bool:
	return rect != null and rect.visible
