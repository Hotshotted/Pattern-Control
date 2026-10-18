class_name Hud
extends CanvasLayer
## All the 2D interface: score, shift bar, strikes, star goals, menu, shift results, floating popups,
## build stamp and the ?perf readout. Every node is created once; showing / hiding (and redrawing
## the little art control) is all that happens in a run.

signal play_pressed

const POPUP_POOL := 8

## The drawn parts of the HUD: shift bar, strike boxes, star goals and the big result stars.
class Art extends Control:
	var shift_frac := 0.0
	var show_play := false           # shift bar, strikes, goals
	var strikes := 0
	var max_strikes := 3
	var goal_text := PackedStringArray(["", "", ""])
	var goal_state := PackedInt32Array([0, 0, 0])      # 0 pending / 1 met / 2 failed
	var show_result := false
	var result_y := 640.0
	var _pts := PackedVector2Array()
	var _font: Font

	func _init() -> void:
		_pts.resize(10)
		_font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func star(c: Vector2, r: float, fill: Color, outline: bool = true) -> void:
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			var rr := r if k % 2 == 0 else r * 0.45
			_pts[k] = c + Vector2(cos(a), sin(a)) * rr
		if outline:
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0
				var rr := (r if k % 2 == 0 else r * 0.45) + 4.0
				_pts[k] = c + Vector2(cos(a), sin(a)) * rr
			draw_colored_polygon(_pts, Color.BLACK)
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0
				_pts[k] = c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45)
		draw_colored_polygon(_pts, fill)

	func _goal_row(y: float, i: int, x: float, size: int) -> void:
		var st := goal_state[i]
		var fill := Color(1.0, 0.84, 0.15) if st == 1 else (Color(0.45, 0.2, 0.2) if st == 2 else Color(0.28, 0.3, 0.36))
		star(Vector2(x + 22.0, y), 22.0, fill)
		var tcol := Color(1, 0.95, 0.6) if st == 1 else (Color(1, 0.55, 0.5) if st == 2 else Color.WHITE)
		draw_string_outline(_font, Vector2(x + 60.0, y + size * 0.35), goal_text[i], HORIZONTAL_ALIGNMENT_LEFT, size_x(), size, 8, Color.BLACK)
		draw_string(_font, Vector2(x + 60.0, y + size * 0.35), goal_text[i], HORIZONTAL_ALIGNMENT_LEFT, size_x(), size, tcol)

	func size_x() -> float:
		return maxf(size.x - 100.0, 200.0)

	func _draw() -> void:
		if show_play:
			draw_rect(Rect2(0, 0, size.x, 14), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(0, 0, size.x * clampf(shift_frac, 0.0, 1.0), 14), Color(0.4, 0.85, 1.0, 0.9))
			var n := max_strikes
			var x0 := size.x * 0.5 - (n - 1) * 36.0
			for k in n:
				var r := Rect2(x0 + k * 72.0 - 26.0, 212.0, 52.0, 52.0)
				draw_rect(r, Color(0, 0, 0, 0.55))
				draw_rect(r, Color(0.9, 0.9, 0.95, 0.7), false, 3.0)
				if k < strikes:
					draw_line(r.position + Vector2(8, 8), r.end - Vector2(8, 8), Color(1, 0.2, 0.15), 8.0)
					draw_line(Vector2(r.end.x - 8, r.position.y + 8), Vector2(r.position.x + 8, r.end.y - 8), Color(1, 0.2, 0.15), 8.0)
			draw_rect(Rect2(8.0, 276.0, 560.0, 190.0), Color(0.03, 0.05, 0.08, 0.45))
			for i in 3:
				_goal_row(310.0 + i * 56.0, i, 22.0, 32)
		if show_result:
			for i in 3:
				var met := goal_state[i] == 1
				star(Vector2(size.x * 0.5 + (i - 1) * 190.0, result_y - (40.0 if i == 1 else 0.0)), 80.0, Color(1.0, 0.84, 0.15) if met else Color(0.25, 0.27, 0.33))
			for i in 3:
				_goal_row(result_y + 130.0 + i * 64.0, i, size.x * 0.5 - 360.0, 38)

var _art: Art
var _score: Label
var _best: Label
var _alert: Label
var _menu: Control
var _menu_info: Label
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
	_art = Art.new()
	add_child(_art)
	_score = _label(130, HORIZONTAL_ALIGNMENT_CENTER)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.offset_left = -300
	_score.offset_right = 300
	_score.offset_top = 30
	_score.pivot_offset = Vector2(300, 80)
	_best = _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	_best.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_best.offset_left = -300
	_best.offset_right = 300
	_best.offset_top = 175
	_best.modulate = Color(1, 1, 1, 0.7)
	_alert = _label(54, HORIZONTAL_ALIGNMENT_CENTER)
	_alert.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert.offset_left = -400
	_alert.offset_right = 400
	_alert.offset_top = 275
	_alert.text = "TRAFFIC!"
	_alert.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	_alert.visible = false
	for i in POPUP_POOL:
		var l := _label(72, HORIZONTAL_ALIGNMENT_CENTER)
		l.size = Vector2(560, 100)
		l.pivot_offset = Vector2(280, 50)
		l.visible = false
		_pop_labels.append(l)
	_pop_born.resize(POPUP_POOL)
	_pop_from.resize(POPUP_POOL)
	_build_menu()
	_build_over()
	_build_stamp()
	set_landed(0)

func _label(size: int, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(l)
	return l

func _centered(l: Label, top: float, bottom: float) -> void:
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = top
	l.offset_bottom = bottom
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.08, 0.12, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(shade)
	var title := _label(120, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	title.text = "PATTERN\nWORK"
	_centered(title, -620, -320)
	var how := _label(42, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	how.text = "Drag from an aircraft to the runway\nof its colour to land it.\nTap an aircraft to hold it in a circle.\nWatch the timer rings:\nwhen one runs out it is diverted (a strike).\n3 strikes end the shift.\nKeep them apart."
	_centered(how, -270, 250)
	var go := _label(76, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	go.text = "TAP TO START SHIFT"
	_centered(go, 300, 400)
	go.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_menu_info = _label(40, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	_centered(_menu_info, 430, 560)
	_menu.visible = false

func _build_over() -> void:
	_over = Control.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.06, 0.66)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(shade)
	_over_head = _label(96, HORIZONTAL_ALIGNMENT_CENTER, _over)
	_centered(_over_head, -700, -480)
	_over_head.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_over_body = _label(46, HORIZONTAL_ALIGNMENT_CENTER, _over)
	_centered(_over_body, 360, 800)
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

func show_menu(airport_name: String, coins: int, stars: int, best: int) -> void:
	_menu_info.text = "%s\nCoins %d    Stars %d%s" % [airport_name, coins, stars, ("    Best %d" % best) if best > 0 else ""]
	_menu.visible = true
	_over.visible = false
	_art.show_play = false
	_art.show_result = false
	_art.queue_redraw()

## The end-of-shift screen: header, why it ended, the three star goals and the totals.
func show_results(header: String, reason: String, shift: Shift, coins_earned: int, coins_total: int, best: int, new_best: bool) -> void:
	_over_head.text = header
	_over_body.text = "%s\n\nAircraft landed: %d%s\nCoins +%d   (total %d)\n\nTap to continue" % [reason, shift.landed, "   NEW BEST!" if new_best else "   best %d" % best, coins_earned, coins_total]
	for i in 3:
		_art.goal_state[i] = shift.state(i)
		_art.goal_text[i] = shift.goal_text(i)
	_art.show_play = false
	_art.show_result = true
	_art.queue_redraw()
	_over.visible = true
	_menu.visible = false

func hide_screens() -> void:
	_menu.visible = false
	_over.visible = false
	_art.show_result = false

func reset_for_run(best: int) -> void:
	hide_screens()
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_flash.color.a = 0.0
	_alert.visible = false
	_alert_on = false
	_art.show_play = true
	_art.shift_frac = 0.0
	set_landed(0)
	set_best(best)

func set_best(best: int) -> void:
	_best.text = "best %d" % best if best > 0 else ""

func set_landed(n: int, punch: bool = false) -> void:
	_score.text = str(n)
	if punch and not DebugFlags.off("popup"):
		_punch_ms = Time.get_ticks_msec()

func set_alert(on: bool) -> void:
	_alert_on = on
	_alert.visible = on

## The three goal rows and the strike boxes (called when something changes, not every frame).
func set_shift(shift: Shift, max_strikes: int) -> void:
	for i in 3:
		_art.goal_state[i] = shift.state(i)
		var prog := ""
		if shift.goals[i]["kind"] != "no_strikes":
			prog = "  %d/%d" % [mini(shift.progress(i), shift.target(i)), shift.target(i)]
		_art.goal_text[i] = shift.goal_text(i) + prog
	_art.strikes = shift.strikes
	_art.max_strikes = max_strikes
	_art.queue_redraw()

func set_shift_fraction(f: float) -> void:
	if absf(f - _art.shift_frac) > 0.002:
		_art.shift_frac = f
		_art.queue_redraw()

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
	var vp := get_viewport().get_visible_rect().size
	l.position = Vector2(clampf(at.x - 280.0, 0.0, maxf(vp.x - 560.0, 0.0)), clampf(at.y - 50.0, 20.0, maxf(vp.y - 160.0, 20.0)))
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
	_menu_info.text = "Home Field Regional County Island International\nCoins 0123456789    Stars 0123456789    Best 0123456789"
	_over_head.text = "SHIFT COMPLETE  3 STRIKES  MID-AIR CONFLICT"
	_over_body.text = "Two aircraft got too close. Aircraft landed: 0123456789   NEW BEST!\nCoins +0123456789   (total 0123456789)\n\nTap to continue"
	for i in 3:
		_art.goal_text[i] = "Land 0123 aircraft  0123/0123 No strikes helicopters jets gliders"
		_art.goal_state[i] = i
	_art.show_play = true
	_art.show_result = true
	_art.strikes = 2
	_art.queue_redraw()
	_best.text = "best 0123456789"
	_menu.visible = true
	_over.visible = true
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
	var words := ["+1", "+1  x2", "Diverted", "WRONG RUNWAY", "STAR!", "CONFLICT", "+25", "SHIFT COMPLETE"]
	for i in POPUP_POOL:
		popup(words[i], Color(1, 0.9, 0.3), Vector2(vp.x * 0.5, vp.y * (0.3 + 0.07 * i)))
	flash(Color(1, 0.1, 0.1))
	set_landed(0, true)

func end_prewarm() -> void:
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_alert.visible = false
	_alert_on = false
	_over.visible = false
	_menu.visible = false
	_art.show_play = false
	_art.show_result = false
	_art.queue_redraw()
	_flash_ms = -10000
	if is_instance_valid(_splash):
		_splash.queue_free()
