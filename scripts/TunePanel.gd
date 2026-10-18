class_name TunePanel
extends Node
## On-screen tuning panel, built ONLY when the page URL has ?tune (players never see it).
## A TUNE button (top-right) opens a panel over the paused game; closing it resumes. Each slider
## edits the matching Tuning value live. "Copy values" puts the values that differ from the
## defaults on the clipboard as text (and shows them), and "Reset" restores the defaults.
## Everything is created once at start-up, drawn during the pre-warm, and only shown / hidden after
## that, like every other pooled part of the game.

## Emitted after a value changed (by a slider or Reset), with the Tuning property name.
signal changed(property: String)

## [Tuning property, label, min, max, step]: the values tuned most.
const ENTRIES := [
	["spawn_interval_start", "Spawn gap at start (s)", 1.0, 12.0, 0.1],
	["spawn_interval_min", "Spawn gap, fastest (s)", 0.5, 6.0, 0.1],
	["spawn_ramp_seconds", "Ramp-up time (s)", 20.0, 400.0, 5.0],
	["max_planes", "Max planes at once", 2.0, 16.0, 1.0],
	["shift_seconds", "Shift length (s)", 30.0, 400.0, 5.0],
	["max_strikes", "Strikes to end the shift", 1.0, 10.0, 1.0],
	["timer_glider", "Timer: glider (s)", 5.0, 120.0, 1.0],
	["timer_heli", "Timer: helicopter (s)", 5.0, 120.0, 1.0],
	["timer_small", "Timer: small plane (s)", 5.0, 120.0, 1.0],
	["timer_medium", "Timer: medium plane (s)", 5.0, 120.0, 1.0],
	["timer_jet", "Timer: jet (s)", 5.0, 120.0, 1.0],
	["hold_drain_mult", "Holding timer drain (x)", 0.0, 1.0, 0.05],
	["timer_yellow_fraction", "Ring turns yellow at", 0.1, 0.9, 0.05],
	["timer_red_fraction", "Ring turns red at", 0.05, 0.6, 0.05],
	["divert_speed_mult", "Divert speed (x)", 1.0, 3.0, 0.1],
	["speed_slow", "Speed: slow", 0.5, 5.0, 0.1],
	["speed_medium", "Speed: medium", 0.5, 6.0, 0.1],
	["speed_fast", "Speed: fast", 0.5, 8.0, 0.1],
	["speed_ramp_max", "Speed ramp (x at full)", 1.0, 2.5, 0.05],
	["conflict_distance", "Conflict distance", 0.4, 2.0, 0.05],
	["warn_distance", "Warning distance", 0.8, 4.0, 0.1],
	["approach_radius", "Landing capture radius", 0.4, 2.0, 0.05],
	["hold_radius", "Holding circle radius", 0.5, 2.5, 0.05],
	["tap_radius", "Touch pick radius", 0.5, 2.0, 0.05],
	["path_spacing", "Path point spacing", 0.1, 0.8, 0.05],
	["plane_turn_rate", "Aircraft turn rate", 2.0, 20.0, 0.5],
	["landing_roll_time", "Landing roll (s)", 0.5, 4.0, 0.1],
	["entry_warning_seconds", "Entry warning lead (s)", 0.0, 6.0, 0.1],
	["entry_pulse_slow", "Entry glow pulse: slow (Hz)", 0.2, 10.0, 0.1],
	["entry_pulse_medium", "Entry glow pulse: medium (Hz)", 0.2, 10.0, 0.1],
	["entry_pulse_fast", "Entry glow pulse: fast (Hz)", 0.2, 10.0, 0.1],
	["path_fade_distance", "Path fade length near plane", 0.0, 4.0, 0.1],
	["path_fade_min", "Path opacity at the nose", 0.0, 1.0, 0.05],
]

## [Tuning property, label]: colours, edited with three (red, green, blue) sliders and a swatch.
const COLOR_ENTRIES := [
	["timer_color_ok", "Timer ring: plenty"],
	["timer_color_low", "Timer ring: low"],
	["timer_color_red", "Timer ring: nearly out"],
	["entry_color_slow", "Entry glow: slow"],
	["entry_color_medium", "Entry glow: medium"],
	["entry_color_fast", "Entry glow: fast"],
]

## [Tuning property, label]: on/off switches.
const TOGGLES := [
]

## Screen rect of the TUNE button, so the game can ignore touches that land on it.
static var _button_rect := Rect2()

## True if a touch at `pos` (viewport coordinates) is on the TUNE button.
static func button_hit(pos: Vector2) -> bool:
	return _button_rect.has_point(pos)

var is_open := false
var last_copied_text := ""          # what the Copy button last put on the clipboard
var _defaults := {}                 # property -> default value, captured at build time
var _sliders := {}                  # property -> HSlider
var _value_labels := {}             # property -> Label
var _color_sliders := {}            # property -> [R, G, B] HSliders
var _color_swatches := {}           # property -> ColorRect
var _toggles := {}                  # property -> CheckButton
var _button_layer: CanvasLayer
var _panel_layer: CanvasLayer
var _button: Button
var _panel: Control
var _out: Label

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused

## Create everything (called once by Main, only when ?tune is on).
func build() -> void:
	for e in ENTRIES:
		_defaults[e[0]] = Tuning.get(e[0])
	for t in TOGGLES:
		_defaults[t[0]] = Tuning.get(t[0])
	for c in COLOR_ENTRIES:
		_defaults[c[0]] = Tuning.get(c[0])
	# Shared look for every slider: a thick track and a big round handle (the default is tiny on a phone).
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.27, 0.36)
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.8, 0.5)
	fill.set_corner_radius_all(8)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	var knob := _circle_texture(52, Color(0.95, 0.97, 1.0))
	var tick_off := _ring_texture(52, Color(0.7, 0.75, 0.85))   # big, readable on/off icons for the switch
	var tick_on := _circle_texture(52, Color(0.25, 0.9, 0.5))
	# The panel: a dark overlay over the whole screen. Hidden until opened; layer 0 so that during
	# the start-up pre-warm it is drawn UNDER the splash screen.
	_panel_layer = CanvasLayer.new()
	_panel_layer.layer = 0
	add_child(_panel_layer)
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	_panel_layer.add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.11, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_top", 110)   # leaves room for the TUNE / CLOSE button
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(_make_label("TUNING  (live)", 44, HORIZONTAL_ALIGNMENT_LEFT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for e in ENTRIES:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		var name_label := _make_label(e[1], 32, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := _make_label("", 32, HORIZONTAL_ALIGNMENT_RIGHT)
		value_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
		head.add_child(name_label)
		head.add_child(value_label)
		row.add_child(head)
		var slider := HSlider.new()
		slider.min_value = e[2]
		slider.max_value = e[3]
		slider.step = e[4]
		slider.custom_minimum_size = Vector2(0, 60)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)
		for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
			slider.add_theme_icon_override(icon, knob)
		slider.value = Tuning.get(e[0])
		slider.value_changed.connect(_on_slider.bind(e[0]))
		row.add_child(slider)
		list.add_child(row)
		_sliders[e[0]] = slider
		_value_labels[e[0]] = value_label
		_show_value(e[0])
	for c in COLOR_ENTRIES:
		var crow := VBoxContainer.new()
		crow.add_theme_constant_override("separation", 4)
		var chead := HBoxContainer.new()
		var cname := _make_label(c[1], 32, HORIZONTAL_ALIGNMENT_LEFT)
		cname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chead.add_child(cname)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(90, 40)
		swatch.color = Tuning.get(c[0])
		chead.add_child(swatch)
		crow.add_child(chead)
		var sliders := HBoxContainer.new()
		sliders.add_theme_constant_override("separation", 10)
		var made: Array[HSlider] = []
		for ch in 3:
			var cs := HSlider.new()
			cs.min_value = 0.0
			cs.max_value = 1.0
			cs.step = 0.01
			cs.custom_minimum_size = Vector2(0, 60)
			cs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cs.add_theme_stylebox_override("slider", track)
			cs.add_theme_stylebox_override("grabber_area", fill)
			cs.add_theme_stylebox_override("grabber_area_highlight", fill)
			for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
				cs.add_theme_icon_override(icon, knob)
			cs.value = (Tuning.get(c[0]) as Color)[ch]
			cs.value_changed.connect(_on_color_slider.bind(c[0], ch))
			sliders.add_child(cs)
			made.append(cs)
		crow.add_child(sliders)
		list.add_child(crow)
		_color_sliders[c[0]] = made
		_color_swatches[c[0]] = swatch
	for t in TOGGLES:
		var check := CheckButton.new()
		check.text = t[1]
		check.add_theme_font_size_override("font_size", 32)
		check.custom_minimum_size = Vector2(0, 76)
		check.button_pressed = Tuning.get(t[0])
		check.add_theme_icon_override("unchecked", tick_off)
		check.add_theme_icon_override("checked", tick_on)
		check.toggled.connect(_on_toggle.bind(t[0]))
		list.add_child(check)
		_toggles[t[0]] = check
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	var reset := _make_button("Reset", 36)
	reset.pressed.connect(reset_defaults)
	var copy := _make_button("Copy values", 36)
	copy.pressed.connect(copy_values)
	buttons.add_child(reset)
	buttons.add_child(copy)
	column.add_child(buttons)
	_out = _make_label("", 26, HORIZONTAL_ALIGNMENT_LEFT)
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out.custom_minimum_size = Vector2(0, 150)
	column.add_child(_out)
	# The TUNE / CLOSE button, always on top, top-right. Hidden until the game has finished starting.
	_button_layer = CanvasLayer.new()
	_button_layer.layer = 20
	add_child(_button_layer)
	_button = _make_button("TUNE", 32)
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -190.0
	_button.offset_right = -20.0
	_button.offset_top = 20.0
	_button.offset_bottom = 96.0
	_button.pressed.connect(toggle)
	_button.visible = false
	_button_layer.add_child(_button)

func _process(_delta: float) -> void:
	_button_rect = _button.get_global_rect() if _button.visible else Rect2()

## Show or hide the TUNE button (hidden while the game is still starting up).
func set_available(on: bool) -> void:
	_button.visible = on

## Start-up pre-warm: draw the panel (under the splash) so its fonts and widgets are set up.
func prewarm_show(on: bool) -> void:
	_panel.visible = on

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

## Open the panel over the game and pause it.
func open() -> void:
	is_open = true
	_panel_layer.layer = 19
	_panel.visible = true
	_button.text = "CLOSE"
	_out.text = ""
	get_tree().paused = true

## Close the panel and resume the game.
func close() -> void:
	is_open = false
	_panel.visible = false
	_panel_layer.layer = 0
	_button.text = "TUNE"
	get_tree().paused = false

func _on_slider(value: float, property: String) -> void:
	Tuning.set(property, value)
	_show_value(property)
	changed.emit(property)

func _on_color_slider(value: float, property: String, channel: int) -> void:
	var col: Color = Tuning.get(property)
	col[channel] = value
	Tuning.set(property, col)
	_color_swatches[property].color = col
	changed.emit(property)

func _on_toggle(on: bool, property: String) -> void:
	Tuning.set(property, on)
	changed.emit(property)

## Put every tuned value back to its default (as captured when the panel was built).
func reset_defaults() -> void:
	for t in TOGGLES:
		var name: String = t[0]
		Tuning.set(name, _defaults[name])
		_toggles[name].set_pressed_no_signal(_defaults[name])
		changed.emit(name)
	for c in COLOR_ENTRIES:
		var cname: String = c[0]
		Tuning.set(cname, _defaults[cname])
		_color_swatches[cname].color = _defaults[cname]
		for ch in 3:
			_color_sliders[cname][ch].set_value_no_signal((_defaults[cname] as Color)[ch])
		changed.emit(cname)
	for e in ENTRIES:
		var property: String = e[0]
		Tuning.set(property, _defaults[property])
		_sliders[property].set_value_no_signal(_defaults[property])
		_show_value(property)
		changed.emit(property)
	_out.text = "Reset to defaults."

## The values that differ from the defaults, one "name = value" per line, ready to paste.
func changed_text() -> String:
	var lines: Array[String] = []
	for e in ENTRIES:
		var property: String = e[0]
		var v: float = Tuning.get(property)
		if not is_equal_approx(v, _defaults[property]):
			lines.append("%s = %s" % [property, _format(v, e[4])])
	for c in COLOR_ENTRIES:
		var cname: String = c[0]
		var cv: Color = Tuning.get(cname)
		if not cv.is_equal_approx(_defaults[cname]):
			lines.append("%s = Color(%.2f, %.2f, %.2f)" % [cname, cv.r, cv.g, cv.b])
	for t in TOGGLES:
		var name: String = t[0]
		if bool(Tuning.get(name)) != bool(_defaults[name]):
			lines.append("%s = %s" % [name, str(bool(Tuning.get(name))).to_lower()])
	return "(no changes)" if lines.is_empty() else "\n".join(lines)

## Copy the changed values to the clipboard and show them on screen too (in case the browser
## doesn't allow clipboard access).
func copy_values() -> void:
	last_copied_text = changed_text()
	DisplayServer.clipboard_set(last_copied_text)
	_out.text = "Copied:\n" + last_copied_text

func _show_value(property: String) -> void:
	var step: float = 0.0
	for e in ENTRIES:
		if e[0] == property:
			step = e[4]
	var v: float = Tuning.get(property)
	var text := _format(v, step)
	if not is_equal_approx(v, _defaults.get(property, v)):
		text += "   (default %s)" % _format(_defaults[property], step)
	_value_labels[property].text = text

## A number with as many decimals as the slider's step has (0.5 -> 1, 0.01 -> 2, 5 -> 0).
func _format(v: float, step: float) -> String:
	var decimals := 0
	var s := step
	while decimals < 4 and absf(s - roundf(s)) > 0.0001:
		s *= 10.0
		decimals += 1
	return ("%." + str(decimals) + "f") % v   # keeps trailing zeros: 0.50, not 0.5

func _make_label(text: String, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(170, 76)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

## A hollow ring, used as the "off" icon of the switch.
func _ring_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := (diameter - 1) * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x - c, y - c).length()
			var edge := clampf(c + 0.5 - d, 0.0, 1.0) * clampf(d - (c - 6.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, edge))
	return ImageTexture.create_from_image(img)

## A filled circle, used as the slider handle.
func _circle_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := (diameter - 1) * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x - c, y - c).length()
			img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(c + 0.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
