class_name Hud
extends CanvasLayer
## All the 2D text: score, alert banner, menu, game-over, floating popups, build stamp and the
## ?perf readout. Every label is created once; showing / hiding is all that happens in a run.

signal play_pressed

const POPUP_POOL := 6

var _score: Label
var _best: Label
var _alert: Label
var _menu: Control
var _menu_best: Label
var _over: Control
var _over_head: Label
var _over_body: Label
var _flash: ColorRect
var _splash: Control
var _perf_label: Label
var _pop_labels: Array[Label] = []
var _pop_born := PackedInt64Array()
var _pop_from := PackedVector2Array()
var _punch_ms := -10000
var _flash_ms := -10000
var _perf_worst := 0.0
var _perf_window_start := 0
var _perf_shown := 0.0
var _hitch_log: Array[String] = []
var _hitch_count := 0
var _clock_text := ""
var _alert_on := false

func _ready() -> void:
	layer = 2
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0.1, 0.1, 0.0)
	add_child(_flash)
	_score = _label(130, HORIZONTAL_ALIGNMENT_CENTER)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.offset_left = -300
	_score.offset_right = 300
	_score.offset_top = 40
	_score.pivot_offset = Vector2(300, 80)
	_best = _label(34, HORIZONTAL_ALIGNMENT_CENTER)
	_best.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_best.offset_left = -300
	_best.offset_right = 300
	_best.offset_top = 190
	_best.modulate = Color(1, 1, 1, 0.7)
	_alert = _label(54, HORIZONTAL_ALIGNMENT_CENTER)
	_alert.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert.offset_left = -400
	_alert.offset_right = 400
	_alert.offset_top = 240
	_alert.text = "TRAFFIC!"
	_alert.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	_alert.visible = false
	for i in POPUP_POOL:
		var l := _label(76, HORIZONTAL_ALIGNMENT_CENTER)
		l.size = Vector2(500, 100)
		l.pivot_offset = Vector2(250, 50)
		l.visible = false
		_pop_labels.append(l)
	_pop_born.resize(POPUP_POOL)
	_pop_from.resize(POPUP_POOL)
	_build_menu()
	_build_over()
	_build_stamp()
	set_score(0)

func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.08, 0.12, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(shade)
	var title := _label(120, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "PATTERN\nWORK"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.offset_left = -480
	title.offset_right = 480
	title.offset_top = -560
	title.offset_bottom = -260
	title.reparent(_menu, false)
	var how := _label(44, HORIZONTAL_ALIGNMENT_CENTER)
	how.text = "Drag from a plane to the\nrunway of its colour.\n\nTap a plane to hold it in a circle.\nFlashing planes are low on fuel.\n\nKeep them apart."
	how.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	how.offset_left = -480
	how.offset_right = 480
	how.offset_top = -200
	how.offset_bottom = 330
	how.reparent(_menu, false)
	var go := _label(76, HORIZONTAL_ALIGNMENT_CENTER)
	go.text = "TAP TO START"
	go.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	go.offset_left = -480
	go.offset_right = 480
	go.offset_top = 380
	go.offset_bottom = 480
	go.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	go.reparent(_menu, false)
	_menu_best = _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_best.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu_best.offset_left = -480
	_menu_best.offset_right = 480
	_menu_best.offset_top = 500
	_menu_best.offset_bottom = 560
	_menu_best.reparent(_menu, false)
	_menu.visible = false

func _build_over() -> void:
	_over = Control.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.02, 0.02, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(shade)
	_over_head = _label(100, HORIZONTAL_ALIGNMENT_CENTER)
	_over_head.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_over_head.offset_left = -500
	_over_head.offset_right = 500
	_over_head.offset_top = -420
	_over_head.offset_bottom = -200
	_over_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_head.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	_over_head.reparent(_over, false)
	_over_body = _label(60, HORIZONTAL_ALIGNMENT_CENTER)
	_over_body.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_over_body.offset_left = -500
	_over_body.offset_right = 500
	_over_body.offset_top = -150
	_over_body.offset_bottom = 300
	_over_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_body.reparent(_over, false)
	_over.visible = false

## Small "commit . build time" tag bottom-left (BuildInfo.gd is rewritten by the workflow), with any
## active debug flags under it; plus the ?perf readout top-left.
func _build_stamp() -> void:
	var l := _label(26, HORIZONTAL_ALIGNMENT_LEFT)
	l.text = "%s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME]
	var flags := DebugFlags.summary()
	if flags != "":
		l.text += "\n" + flags
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	l.offset_left = 14
	l.offset_top = -48 if flags == "" else -84
	l.modulate = Color(1, 1, 1, 0.55)
	if DebugFlags.perf_enabled():
		_perf_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT)
		_perf_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_perf_label.offset_left = 14
		_perf_label.offset_top = 14
		_perf_label.modulate = Color(0.6, 1, 0.6, 0.9)

# ---------- Screens ----------

func show_menu(best: int) -> void:
	_menu_best.text = "Best: %d" % best if best > 0 else ""
	_menu.visible = true
	_over.visible = false

func show_over(header: String, reason: String, score: int, best: int, is_best: bool) -> void:
	_over_head.text = header
	_over_body.text = "%s\n\nPlanes landed: %d\n%s\n\nTap to fly again" % [reason, score, "NEW BEST!" if is_best else "Best: %d" % best]
	_over.visible = true
	_menu.visible = false

func hide_screens() -> void:
	_menu.visible = false
	_over.visible = false

func reset_for_run(best: int) -> void:
	hide_screens()
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_flash.color.a = 0.0
	_alert.visible = false
	_alert_on = false
	set_score(0)
	set_best(best)

func set_best(best: int) -> void:
	_best.text = "best %d" % best if best > 0 else ""

func set_score(n: int, punch: bool = false) -> void:
	_score.text = str(n)
	if punch and not DebugFlags.off("popup"):
		_punch_ms = Time.get_ticks_msec()

func set_alert(on: bool) -> void:
	_alert_on = on
	_alert.visible = on

## A floating word that rises from a screen position and fades.
func popup(text: String, color: Color, at: Vector2) -> void:
	if DebugFlags.off("popup"):
		return
	var best := 0
	for i in POPUP_POOL:
		if _pop_born[i] == 0:
			best = i
			break
		if _pop_born[i] < _pop_born[best]:
			best = i
	var l := _pop_labels[best]
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.position = at - Vector2(250, 50)
	_pop_from[best] = l.position
	_pop_born[best] = Time.get_ticks_msec()
	l.visible = true

## A quick colour wash over the whole screen.
func flash(color: Color) -> void:
	_flash.color = Color(color.r, color.g, color.b, 0.0)
	_flash_ms = Time.get_ticks_msec()

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var pk := (now - _punch_ms) / (Tuning.score_punch * 1000.0)
	_score.scale = Vector2.ONE * (1.0 + 0.45 * (1.0 - pk) * (1.0 - pk) if pk < 1.0 else 1.0)
	var fa := (now - _flash_ms) / 450.0
	_flash.color.a = 0.45 * (1.0 - fa) if fa < 1.0 else 0.0
	for i in POPUP_POOL:
		if _pop_born[i] == 0:
			continue
		var a := (now - _pop_born[i]) / (Tuning.popup_time * 1000.0)
		if a >= 1.0:
			_pop_born[i] = 0
			_pop_labels[i].visible = false
			continue
		var l := _pop_labels[i]
		l.position = _pop_from[i] + Vector2(0, -150.0 * a)
		l.modulate.a = 1.0 - maxf(a - 0.5, 0.0) * 2.0
		l.scale = Vector2.ONE * (1.0 + 0.3 * (1.0 - a) * (1.0 - a))
	if _alert_on:
		_alert.modulate.a = 0.5 + 0.5 * sin(now / 90.0)
	_update_perf(delta)

# ---------- ?perf ----------

func note_hitch(raw: float, used: float, why: String, context: String) -> void:
	_hitch_count += 1
	var line := "#%d %.0f ms (simulated %.0f ms) %s | %s" % [_hitch_count, raw * 1000.0, used * 1000.0, why, context]
	_hitch_log.append(line)
	if _hitch_log.size() > 5:
		_hitch_log.pop_front()
	print("[hitch] " + line)   # (also in the browser console)

func set_clock(sim: float, wall: float) -> void:
	_clock_text = "sim %.1f s / wall %.1f s" % [sim, wall]

func _update_perf(delta: float) -> void:
	if _perf_label == null:
		return
	_perf_worst = maxf(_perf_worst, delta * 1000.0)
	var now := Time.get_ticks_msec()
	if now - _perf_window_start > 3000:
		_perf_shown = _perf_worst
		_perf_worst = 0.0
		_perf_window_start = now
	_perf_label.text = "worst frame (3s): %.0f ms   %.0f fps\n%s\nhitches (over 50 ms):\n%s" % [_perf_shown, Engine.get_frames_per_second(), _clock_text, "\n".join(_hitch_log)]

# ---------- Start-up pre-warm ----------

## A splash (nearly opaque, so what is behind it is really drawn) while every label, popup and screen
## is shown once, building the font glyph caches.
func begin_prewarm() -> void:
	prewarm_popups()
	_score.text = "0123456789"
	_alert.visible = true
	show_over("MID-AIR CONFLICT", "Out of fuel\nPlanes landed: 0123456789\nNEW BEST! Best: 0123456789\nTap to fly again", 0, 0, true)
	_menu.visible = true
	_over.visible = true
	_best.text = "best 0123456789"
	_splash = Control.new()
	_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.16, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(bg)
	var title := Label.new()
	title.text = "PATTERN WORK\nloading..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 90)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(title)
	add_child(_splash)

func prewarm_popups() -> void:
	var vp := get_viewport().get_visible_rect().size
	var words := ["+1", "+1  x2", "SAVED! +1", "WRONG RUNWAY", "x3", "CONFLICT"]
	for i in POPUP_POOL:
		popup(words[i], Color(1, 0.9, 0.3), Vector2(vp.x * 0.5, vp.y * (0.3 + 0.08 * i)))
	flash(Color(1, 0.1, 0.1))
	set_score(0, true)

func end_prewarm() -> void:
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_alert.visible = false
	_alert_on = false
	_over.visible = false
	_menu.visible = false
	_flash_ms = -10000
	if is_instance_valid(_splash):
		_splash.queue_free()
