class_name ExtLabel
extends Label
## A display-face label over the field in the Cozy Airfield look: cream letters (the label's own colour) standing on a stacked warm
## extrusion (#C9641F down to #803D11) with a soft shadow. This script draws the whole thing itself (shadow, extrusion, then the face),
## after the label's own text, so the face stays on top whatever order the engine draws them in.

var depth := 5

func _draw() -> void:
	if text == "":
		return
	var f := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	var a := get_theme_color("font_color").a
	var asc := f.get_ascent(fs)
	var h := f.get_height(fs) + get_theme_constant("line_spacing")
	var lines := text.split("\n")
	var y0 := asc + ((size.y - h * lines.size()) * 0.5 if vertical_alignment == VERTICAL_ALIGNMENT_CENTER else 0.0)
	var step := maxf(fs / 28.0, 1.5)
	for li in lines.size():
		var y := y0 + li * h
		draw_string(f, Vector2(0.0, y + step * depth + 3.0), lines[li], horizontal_alignment, size.x, fs, Color(0.2, 0.1, 0.02, 0.22 * a))
		for i in range(depth, 0, -1):
			var c := Style.EXT_TOP.lerp(Style.EXT_BOTTOM, float(i - 1) / maxf(depth - 1, 1))
			draw_string(f, Vector2(0.0, y + step * i), lines[li], horizontal_alignment, size.x, fs, Color(c, a))
		draw_string(f, Vector2(0.0, y), lines[li], horizontal_alignment, size.x, fs, get_theme_color("font_color"))
