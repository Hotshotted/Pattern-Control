class_name Hud
extends CanvasLayer
## All the 2D interface: coin total, star bar, shift clock, menu, shift results, floating popups,
## build stamp and the ?perf readout. Every node is created once; showing / hiding (and redrawing
## the little art control) is all that happens in a run.

signal play_pressed

const POPUP_POOL := 8

## The drawn parts of the HUD: shift bar, strike boxes, star goals and the big result stars.
class Art extends Control:
	var shift_frac := 0.0
	var show_play := false           # shift bar and the coin / star bar
	var balance := 0                 # the shift's coin total so far
	var thresholds := PackedInt32Array([0, 0, 0])   # coins for 1, 2, 3 stars
	var threshold_text := PackedStringArray(["", "", ""])
	var goal_text := PackedStringArray(["", "", ""])
	var goal_state := PackedInt32Array([0, 0, 0])      # results rows: 0 not reached / 1 reached
	var show_result := false
	var result_y := 640.0
	var wind_toward := 0.0           # compass direction the wind blows toward (the arrow)
	var wind_text := "WIND 000"
	var wind_warn := false
	var show_wind := false
	var _pts := PackedVector2Array()
	var _font: Font

	# Buttons / cards (fixed pool; set per screen). state: 0 normal, 1 disabled, 2 accent.
	const MAX_BTN := 12
	var btn_rect: Array[Rect2] = []
	var btn_id := PackedStringArray()
	var btn_text := PackedStringArray()
	var btn_sub := PackedStringArray()
	var btn_state := PackedInt32Array()
	var btn_stars := PackedInt32Array()      # -1: none, 0..3: stars earned (drawn on cards)
	var btn_icon := PackedInt32Array()       # -1: none, 0..5: an animal pilot portrait, 100+: a theme's colour swatch
	var pilot_animal := -1                   # the pilot shown in the corner while playing
	var pilot_bounce := 0.0                  # 1 -> 0 after a landing
	var result_animal := -1
	var result_quote := ""
	var btn_count := 0

	func _init() -> void:
		for i in MAX_BTN:
			btn_rect.append(Rect2())
		btn_id.resize(MAX_BTN)
		btn_text.resize(MAX_BTN)
		btn_sub.resize(MAX_BTN)
		btn_state.resize(MAX_BTN)
		btn_stars.resize(MAX_BTN)
		btn_icon.resize(MAX_BTN)
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

	func clear_buttons() -> void:
		btn_count = 0
		queue_redraw()

	func add_button(id: String, text: String, rect: Rect2, state: int = 0, sub: String = "", stars: int = -1, icon: int = -1) -> void:
		if btn_count >= MAX_BTN:
			return
		btn_id[btn_count] = id
		btn_text[btn_count] = text
		btn_sub[btn_count] = sub
		btn_rect[btn_count] = rect
		btn_state[btn_count] = state
		btn_stars[btn_count] = stars
		btn_icon[btn_count] = icon
		btn_count += 1
		queue_redraw()

	## Index of the button under `pos`, or -1.
	func button_at(pos: Vector2) -> int:
		for k in btn_count:
			if btn_rect[k].has_point(pos):
				return k
		return -1

	func _draw_buttons() -> void:
		for k in btn_count:
			var r := btn_rect[k]
			var st := btn_state[k]
			var fill := Color(0.12, 0.16, 0.24, 0.94) if st == 0 else (Color(0.07, 0.08, 0.1, 0.9) if st == 1 else Color(0.12, 0.42, 0.3, 0.96))
			var border := Color(0.7, 0.8, 0.95, 0.9) if st != 1 else Color(0.35, 0.37, 0.42, 0.9)
			draw_rect(r, fill)
			draw_rect(r, border, false, 4.0)
			var tcol := Color.WHITE if st != 1 else Color(0.55, 0.57, 0.62)
			var left := btn_sub[k] != "" or btn_stars[k] >= 0
			var has_icon := btn_icon[k] >= 0
			var ty := r.position.y + (r.size.y * 0.42 if btn_sub[k] != "" else r.size.y * 0.62)
			var tx := r.position.x + (28.0 if left else 0.0) + (110.0 if has_icon else 0.0)
			var tw := r.size.x - 56.0 - (110.0 if has_icon else 0.0) if left else r.size.x
			if has_icon:
				_draw_icon(btn_icon[k], Vector2(r.position.x + 70.0, r.position.y + r.size.y * 0.5), minf(r.size.y * 0.36, 52.0))
			var align := HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
			draw_string_outline(_font, Vector2(tx, ty), btn_text[k], align, tw, 46, 8, Color.BLACK)
			draw_string(_font, Vector2(tx, ty), btn_text[k], align, tw, 46, tcol)
			if btn_sub[k] != "":
				var sy := r.position.y + r.size.y * 0.8
				draw_string(_font, Vector2(tx, sy), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, tw - 170.0, 26, Color(0.8, 0.85, 0.95) if st != 1 else Color(0.6, 0.62, 0.68))
			if btn_stars[k] >= 0:
				for i in 3:
					star(Vector2(r.end.x - 150.0 + i * 56.0, r.position.y + r.size.y * 0.5), 22.0, Color(1.0, 0.84, 0.15) if i < btn_stars[k] else Color(0.28, 0.3, 0.36))

	## A card's icon: an animal pilot portrait, or a theme's two colours.
	func _draw_icon(icon: int, c: Vector2, r: float) -> void:
		if icon < 100:
			Portraits.draw(self, c, r, icon)
		else:
			var t: Dictionary = Cosmetics.THEMES[icon - 100]
			var g: Color = t["ground"] if t["ground"] != null else Color(0.4, 0.65, 0.4)
			draw_circle(c, r + 3.0, Color.BLACK)
			draw_circle(c, r, g)
			draw_circle(c + Vector2(r * 0.35, -r * 0.2), r * 0.45, t["leaf"])
			draw_circle(c + Vector2(-r * 0.4, r * 0.35), r * 0.3, (t["bg"] as Color).lightened(0.2))

	## The coin bar: it fills as the balance grows, with a star at each threshold (lit once reached).
	func _draw_star_bar() -> void:
		var w := minf(size.x - 220.0, 640.0)
		var x0 := size.x * 0.5 - w * 0.5
		var y := 236.0
		var top := float(maxi(thresholds[2], 1))
		draw_rect(Rect2(x0, y, w, 20.0), Color(0, 0, 0, 0.55))
		var f := clampf(float(balance) / top, 0.0, 1.0)
		draw_rect(Rect2(x0, y, w * f, 20.0), Color(1.0, 0.84, 0.15, 0.9))
		draw_rect(Rect2(x0, y, w, 20.0), Color(0.9, 0.9, 0.95, 0.7), false, 3.0)
		for i in 3:
			var x := x0 + w * float(thresholds[i]) / top
			var lit := balance >= thresholds[i]
			star(Vector2(x, y + 10.0), 25.0 if lit else 20.0, Color(1.0, 0.84, 0.15) if lit else Color(0.3, 0.32, 0.4))
			draw_string_outline(_font, Vector2(x - 50.0, y + 64.0), threshold_text[i], HORIZONTAL_ALIGNMENT_CENTER, 100.0, 24, 6, Color.BLACK)
			draw_string(_font, Vector2(x - 50.0, y + 64.0), threshold_text[i], HORIZONTAL_ALIGNMENT_CENTER, 100.0, 24, Color(1, 0.95, 0.7) if lit else Color.WHITE)

	func size_x() -> float:
		return maxf(size.x - 100.0, 200.0)

	func _draw_wind() -> void:
		var c := Vector2(size.x - 92.0, 196.0)
		draw_circle(c, 56.0, Color(0.03, 0.05, 0.08, 0.5))
		var ring := Color(1.0, 0.9, 0.3) if wind_warn and int(Time.get_ticks_msec() / 250.0) % 2 == 0 else Color(0.85, 0.9, 1.0, 0.8)
		draw_arc(c, 56.0, 0.0, TAU, 40, ring, 4.0)
		var d := Vector2(sin(deg_to_rad(wind_toward)), -cos(deg_to_rad(wind_toward)))
		var n := Vector2(-d.y, d.x)
		draw_line(c - d * 34.0, c + d * 10.0, Color(0, 0, 0), 12.0)
		draw_line(c - d * 34.0, c + d * 10.0, Color.WHITE, 6.0)
		_pts[0] = c + d * 40.0
		_pts[1] = c + d * 8.0 + n * 20.0
		_pts[2] = c + d * 8.0 - n * 20.0
		draw_colored_polygon(_tri(), Color.WHITE)
		draw_string_outline(_font, Vector2(c.x - 90.0, c.y + 92.0), wind_text, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 30, 8, Color.BLACK)
		draw_string(_font, Vector2(c.x - 90.0, c.y + 92.0), wind_text, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 30, Color(1, 0.95, 0.7) if wind_warn else Color.WHITE)

	var _tri_pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

	func _tri() -> PackedVector2Array:
		_tri_pts[0] = _pts[0]
		_tri_pts[1] = _pts[1]
		_tri_pts[2] = _pts[2]
		return _tri_pts

	func _draw() -> void:
		_draw_buttons()
		if show_play and pilot_animal >= 0:
			Portraits.draw(self, Vector2(size.x - 84.0, size.y - 150.0 - 22.0 * sin(pilot_bounce * PI)), 52.0, pilot_animal)
		if show_result and result_animal >= 0:
			Portraits.draw(self, Vector2(size.x * 0.5, result_y + 470.0), 70.0, result_animal)
			draw_string_outline(_font, Vector2(size.x * 0.5 - 450.0, result_y + 590.0), result_quote, HORIZONTAL_ALIGNMENT_CENTER, 900.0, 30, 8, Color.BLACK)
			draw_string(_font, Vector2(size.x * 0.5 - 450.0, result_y + 590.0), result_quote, HORIZONTAL_ALIGNMENT_CENTER, 900.0, 30, Color(0.9, 0.95, 1.0))
		if show_wind:
			_draw_wind()
		if show_play:
			draw_rect(Rect2(0, 0, size.x, 14), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(0, 0, size.x * clampf(shift_frac, 0.0, 1.0), 14), Color(0.4, 0.85, 1.0, 0.9))
			_draw_star_bar()
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
var _wind_banner: Label
var _wind_secs := -1
var _tip: Label
var _event_banner: Label
var _event_text := ""
var _tip_until := 0
var _menu: Control
var _menu_info: Label
var _select: Control
var _ad: Control
var _ad_title: Label
var _ad_sub: Label
var _ad_bar: ColorRect
var _select_info: Label
var _select_title: Label
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
	_wind_banner = _label(46, HORIZONTAL_ALIGNMENT_CENTER)
	_wind_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wind_banner.offset_left = -480
	_wind_banner.offset_right = 480
	_wind_banner.offset_top = 480
	_wind_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	_wind_banner.visible = false
	_event_banner = _label(44, HORIZONTAL_ALIGNMENT_CENTER)
	_event_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_event_banner.offset_left = -480
	_event_banner.offset_right = 480
	_event_banner.offset_top = 545
	_event_banner.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_event_banner.visible = false
	_tip = _label(36, HORIZONTAL_ALIGNMENT_CENTER)
	_tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.offset_left = -500
	_tip.offset_right = 500
	_tip.offset_top = -230
	_tip.offset_bottom = -120
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
	_tip.visible = false
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
	_build_select()
	_build_ad()
	move_child(_art, _select.get_index() + 1)   # the art (goals, buttons, stars) is drawn above the screen shades
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
	how.text = "Drag from an aircraft to the runway\nof its colour to land it. Each landing pays.\nTap an aircraft to hold it in a circle.\nA timer ring that runs out: diverted (-20).\nA conflict costs 100 and both aircraft.\nEarn stars before the clock runs out."
	_centered(how, -270, 250)
	var go := _label(76, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	go.text = "TAP TO START SHIFT"
	_centered(go, 300, 400)
	go.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_menu_info = _label(40, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	_centered(_menu_info, 430, 560)
	_menu.visible = false

func _build_select() -> void:
	_select = Control.new()
	_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_select.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_select)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.08, 0.12, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select.add_child(shade)
	_select_title = _label(90, HORIZONTAL_ALIGNMENT_CENTER, _select)
	_select_title.text = "AIRPORTS"
	_select_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_select_title.offset_left = -500
	_select_title.offset_right = 500
	_select_title.offset_top = 40
	_select_info = _label(40, HORIZONTAL_ALIGNMENT_CENTER, _select)
	_select_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_select_info.offset_left = -500
	_select_info.offset_right = 500
	_select_info.offset_top = 150
	_select.visible = false

## The fake "Ad playing" screen (no real ads yet) and the "undo the conflict?" prompt.
func _build_ad() -> void:
	_ad = Control.new()
	_ad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ad)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ad.add_child(shade)
	_ad_title = _label(110, HORIZONTAL_ALIGNMENT_CENTER, _ad)
	_ad_title.text = "AD PLAYING"
	_centered(_ad_title, -300, -120)
	_ad_sub = _label(44, HORIZONTAL_ALIGNMENT_CENTER, _ad)
	_centered(_ad_sub, -80, 140)
	_ad_bar = ColorRect.new()
	_ad_bar.color = Color(0.4, 0.85, 1.0)
	_ad_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_ad_bar.offset_left = -400
	_ad_bar.offset_right = 400
	_ad_bar.offset_top = 200
	_ad_bar.offset_bottom = 230
	_ad_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ad.add_child(_ad_bar)
	_ad.visible = false

## The fake ad: `title` says what it is for; `progress` (0..1) fills the bar.
func show_ad(title: String) -> void:
	_menu.visible = false
	_over.visible = false
	_select.visible = false
	_art.show_play = false
	_art.show_result = false
	_art.show_wind = false
	_art.clear_buttons()
	_ad_sub.text = title + "\n\n(stub: no real ad is shown)"
	_ad_bar.offset_right = -400
	_ad.visible = true

func set_ad_progress(f: float) -> void:
	_ad_bar.offset_right = -400.0 + 800.0 * clampf(f, 0.0, 1.0)

func hide_ad() -> void:
	_ad.visible = false

## Back to the shift after the ad: the HUD of a running shift, nothing else.
func resume_play() -> void:
	_ad.visible = false
	_over.visible = false
	_art.clear_buttons()
	_art.show_play = true
	_art.show_wind = true
	_art.show_result = false
	_art.queue_redraw()

## Results: the rewarded "double the coins" offer (once per shift).
func set_double_button(on: bool, coins: int) -> void:
	_art.clear_buttons()
	var vp := get_viewport().get_visible_rect().size
	if on:
		_art.add_button("ad_double", "WATCH AD: DOUBLE COINS (+%d)" % coins, Rect2(vp.x * 0.5 - 420.0, vp.y * 0.5 + 690.0, 840.0, 110.0), 2)
	_art.add_button("menu", "MENU", Rect2(vp.x * 0.5 - 170.0, vp.y * 0.5 + 820.0, 340.0, 100.0))
	_art.queue_redraw()

func set_results_text(text: String) -> void:
	_over_body.text = text

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

func show_menu(airport_name: String, coins: int, stars: int, best: int, tag: String = "") -> void:
	_select.visible = false
	_menu_info.text = "%s\n%s\nCoins %d    Stars %d%s" % [airport_name, tag, coins, stars, ("    Best %d" % best) if best > 0 else ""]
	_art.clear_buttons()
	_layout_menu_buttons()
	_menu.visible = true
	_over.visible = false
	_art.show_play = false
	_art.show_result = false
	_art.show_wind = false
	_wind_banner.visible = false
	_art.queue_redraw()

## The end-of-shift screen: header, why it ended, the three star goals and the totals.
func show_results(header: String, reason: String, shift: Shift, coins_earned: int, coins_total: int, best: int, new_best: bool, animal: int = -1, quote: String = "", doubled: bool = false) -> void:
	_art.result_animal = animal
	_art.result_quote = quote
	_over_head.text = header
	_over_body.text = "%s\n\nPayout +%d coins%s   (total %d)\n%s\n\nTap anywhere to fly again" % [reason, coins_earned, "  (doubled!)" if doubled else "", coins_total, "NEW BEST!" if new_best else "best payout %d" % best]
	for i in 3:
		_art.goal_state[i] = 1 if shift.balance() >= shift.thresholds[i] else 0
		_art.goal_text[i] = "%d coins" % shift.thresholds[i]
	_art.show_play = false
	_art.show_result = true
	_art.show_wind = false
	_wind_banner.visible = false
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	_art.add_button("menu", "MENU", Rect2(vp.x * 0.5 - 170.0, vp.y * 0.5 + 800.0, 340.0, 100.0))
	_art.queue_redraw()
	_over.visible = true
	_menu.visible = false

## The airport select screen: one card per airport (stars earned, best, or what unlocks it).
func show_select(total_stars: int, open: PackedByteArray, stars: PackedInt32Array, best: PackedInt32Array, selected: int) -> void:
	_menu.visible = false
	_over.visible = false
	_select.visible = true
	_art.show_play = false
	_art.show_result = false
	_art.show_wind = false
	_select_title.text = "AIRPORTS"
	_select_info.text = "Stars %d    Coins %d" % [total_stars, Save.coins]
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	for i in Airports.COUNT:
		var r := Rect2(40.0, 230.0 + i * 190.0, vp.x - 80.0, 170.0)
		if open[i] != 0:
			var sub := Airports.tag(i) + ("    best %d" % best[i] if best[i] > 0 else "")
			_art.add_button("airport:%d" % i, "%d  %s" % [i + 1, Airports.airport_name(i)], r, 2 if i == selected else 0, sub, stars[i])
		else:
			_art.add_button("locked:%d" % i, "%d  %s" % [i + 1, Airports.airport_name(i)], r, 1, "Locked: needs %d stars (you have %d)" % [Airports.unlock_stars(i), total_stars], -1)
	_art.add_button("back", "BACK", Rect2(vp.x * 0.5 - 170.0, 230.0 + Airports.COUNT * 190.0 + 20.0, 340.0, 100.0))
	_art.queue_redraw()

## Which pilot sits in the corner while you play (an animal 0..5), with a hop after each landing.
func set_pilot(animal: int) -> void:
	_art.pilot_animal = animal
	_art.queue_redraw()

func pilot_hop() -> void:
	_art.pilot_bounce = 1.0

## A generic list screen: optional tab buttons, then cards {id, title, sub, state, stars, icon}, then Back.
func show_list(title: String, info: String, tabs: Array, cards: Array) -> void:
	_menu.visible = false
	_over.visible = false
	_select.visible = true
	_art.show_play = false
	_art.show_result = false
	_art.show_wind = false
	_select_title.text = title
	_select_info.text = info
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	var y := 210.0
	if not tabs.is_empty():
		var w := (vp.x - 80.0 - 20.0 * (tabs.size() - 1)) / tabs.size()
		for k in tabs.size():
			_art.add_button(tabs[k]["id"], tabs[k]["title"], Rect2(40.0 + k * (w + 20.0), y, w, 90.0), 2 if tabs[k]["selected"] else 0)
		y += 120.0
	for c in cards:
		_art.add_button(c["id"], c["title"], Rect2(40.0, y, vp.x - 80.0, 150.0), c["state"], c["sub"], c.get("stars", -1), c.get("icon", -1))
		y += 160.0
	_art.add_button("back", "BACK", Rect2(vp.x * 0.5 - 170.0, y + 10.0, 340.0, 100.0))
	_art.queue_redraw()

## The upgrade shop: one card per upgrade with its level, what it does and the next price.
func show_upgrades(coins: int, levels: PackedInt32Array) -> void:
	_menu.visible = false
	_over.visible = false
	_select.visible = true
	_art.show_play = false
	_art.show_result = false
	_art.show_wind = false
	_select_title.text = "UPGRADES"
	_select_info.text = "Coins %d" % coins
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	for i in Upgrades.IDS.size():
		var id: String = Upgrades.IDS[i]
		var lvl := levels[i]
		var price := Upgrades.cost(id, lvl)
		var r := Rect2(40.0, 230.0 + i * 190.0, vp.x - 80.0, 170.0)
		var sub := Upgrades.description(id)
		var state := 0
		if price < 0:
			sub = "MAX - " + sub
			state = 1
		elif coins < price:
			sub = "%d coins (need %d more) - %s" % [price, price - coins, sub]
			state = 1
		else:
			sub = "BUY for %d coins - %s" % [price, sub]
			state = 2
		_art.add_button("upg:" + id, "%s   Lv %d" % [Upgrades.upgrade_name(id), lvl], r, state, sub, lvl)
	_art.add_button("back", "BACK", Rect2(vp.x * 0.5 - 170.0, 230.0 + Upgrades.IDS.size() * 190.0 + 20.0, 340.0, 100.0))
	_art.queue_redraw()

## The id of the enabled button under `pos` ("" if none).
func button_at(pos: Vector2) -> String:
	var k := _art.button_at(pos)
	if k < 0 or _art.btn_state[k] == 1:
		return ""
	return _art.btn_id[k]

## True if `pos` is on any button (even a disabled one): the tap belongs to the UI, not the game.
func ui_hit(pos: Vector2) -> bool:
	return _art.button_at(pos) >= 0

## The menu's buttons, two per row. (Later features add their own entries here.)
const MENU_BUTTONS := [["airports", "AIRPORTS"], ["upgrades", "UPGRADES"], ["shop", "SHOP"], ["daily", "DAILY SHIFT"], ["bad", "BAD PILOT DAY"]]
var daily_label := "DAILY SHIFT"
var daily_sub := ""
var bad_sub := ""

func _layout_menu_buttons() -> void:
	var vp := get_viewport().get_visible_rect().size
	var n := MENU_BUTTONS.size()
	for k in n:
		var id: String = MENU_BUTTONS[k][0]
		var w := 420.0
		var alone := k == n - 1 and n % 2 == 1          # a last button on its own row is centred
		var col := 0 if alone else k % 2
		var row := k / 2
		var cols := 1 if alone else 2
		var x0 := vp.x * 0.5 - (cols * w + (cols - 1) * 30.0) * 0.5
		var label: String = daily_label if id == "daily" else MENU_BUTTONS[k][1]
		var sub := daily_sub if id == "daily" else (bad_sub if id == "bad" else "")
		_art.add_button(id, label, Rect2(x0 + col * (w + 30.0), vp.y * 0.5 + 585.0 + row * 120.0, w, 100.0), 0, sub)

func hide_screens() -> void:
	_menu.visible = false
	_over.visible = false
	_select.visible = false
	_ad.visible = false
	_art.clear_buttons()
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
	_art.show_wind = true
	_wind_banner.visible = false
	_wind_secs = -1
	_art.wind_warn = false
	_tip.visible = false
	_event_text = ""
	_event_banner.visible = false
	_art.shift_frac = 0.0
	_secs_left = -1
	_last_bal = 0
	set_landed(0)
	set_timer(int(Tuning.shift_seconds))
	_art.balance = 0
	_score.text = "0"
	_score.add_theme_color_override("font_color", Color.WHITE)

func set_best(_best_coins: int) -> void:
	pass

var _landed := 0
var _secs_left := -1

## The small line under the coin total: the shift clock and how many have landed.
func _refresh_status() -> void:
	_best.text = "%d:%02d     landed %d" % [maxi(_secs_left, 0) / 60, maxi(_secs_left, 0) % 60, _landed]

func set_landed(n: int, punch: bool = false) -> void:
	_landed = n
	_refresh_status()
	if punch and not DebugFlags.off("popup"):
		_punch_ms = Time.get_ticks_msec()

## The shift clock, whole seconds left (only touches the label when the second changes).
func set_timer(secs_left: int) -> void:
	if secs_left != _secs_left:
		_secs_left = secs_left
		_refresh_status()
		_best.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if secs_left <= 15 else Color.WHITE)

## The wind widget: an arrow showing where the air is going and the "WIND 270" label.
func set_wind(from_deg: float, toward_deg: float) -> void:
	_art.wind_toward = toward_deg
	_art.wind_text = "WIND " + Wind.label(from_deg)
	_art.queue_redraw()

## The banner for an announced wind shift ("Wind shifting to 270  in 6s"); `secs` < 0 hides it.
func set_wind_warning(next_deg: float, secs: int) -> void:
	_art.wind_warn = secs >= 0
	if secs < 0:
		_wind_banner.visible = false
		_wind_secs = -1
		return
	if secs != _wind_secs:
		_wind_secs = secs
		_wind_banner.text = "Wind shifting to %s  in %ds" % [Wind.label(next_deg), secs]
	_wind_banner.visible = true

func set_alert(on: bool) -> void:
	_alert_on = on
	_alert.visible = on

## The coin total (red when negative), the star bar and the results rows: called when something changes.
func set_shift(shift: Shift) -> void:
	var bal := shift.balance()
	_score.text = str(bal)
	_score.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if bal < 0 else Color.WHITE)
	_art.balance = bal
	for i in 3:
		_art.thresholds[i] = shift.thresholds[i]
		_art.threshold_text[i] = str(shift.thresholds[i])
		_art.goal_state[i] = 1 if bal >= shift.thresholds[i] else 0
		_art.goal_text[i] = "%d coins" % shift.thresholds[i]
	_art.queue_redraw()
	if bal != _last_bal:
		_last_bal = bal
		_punch_ms = Time.get_ticks_msec()

var _last_bal := 0

## The rewarded "refund your last fine" button (amount 0 hides it).
func set_refund_offer(amount: int) -> void:
	_art.clear_buttons()
	if amount > 0:
		var vp := get_viewport().get_visible_rect().size
		_art.add_button("ad_refund", "WATCH AD: REFUND -%d" % amount, Rect2(vp.x * 0.5 - 330.0, vp.y - 340.0, 660.0, 100.0), 2)
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

## The weather banner ("Fog in 4s" / "Fog: 12s"); "" hides it. Only touches the label when the text changes.
func set_event_banner(text: String, warning: bool = false) -> void:
	if text == _event_text:
		return
	_event_text = text
	_event_banner.visible = text != ""
	_event_banner.text = text
	_event_banner.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4) if warning else Color(0.75, 0.88, 1.0))

## A one-line tip about an aircraft type seen for the first time.
func show_tip(text: String) -> void:
	_tip.text = text
	_tip.visible = true
	_tip.modulate.a = 1.0
	_tip_until = Time.get_ticks_msec() + int(Tuning.tip_seconds * 1000.0)

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
	if _art.pilot_bounce > 0.0:
		_art.pilot_bounce = maxf(_art.pilot_bounce - delta * 2.5, 0.0)
		_art.queue_redraw()
	if _tip.visible:
		var left := _tip_until - now
		if left <= 0:
			_tip.visible = false
		else:
			_tip.modulate.a = clampf(left / 600.0, 0.0, 1.0)
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

func set_perf_clock(sim: float, wall: float) -> void:
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
	_over_head.text = "SHIFT COMPLETE"
	_over_body.text = "Landings +0123456789  Bonuses +0123456789  Fines -0123456789\nPayout +0123456789 coins  (doubled!)   (total 0123456789)\nNEW BEST!  best payout 0123456789\n\nTap anywhere to fly again"
	_art.thresholds[0] = 100
	_art.thresholds[1] = 200
	_art.thresholds[2] = 300
	for i in 3:
		_art.threshold_text[i] = str(100 * (i + 1))
		_art.goal_text[i] = "%d coins" % (100 * (i + 1))
		_art.goal_state[i] = i % 2
	_art.balance = 150
	_art.show_play = true
	_art.show_result = true
	_art.show_wind = true
	_art.wind_warn = true
	_wind_banner.text = "Wind shifting to 270  in 8s"
	_wind_banner.visible = true
	set_event_banner("Gusty crosswind: ORANGE runway closing in 6s", true)
	set_refund_offer(100)
	_art.queue_redraw()
	_best.text = "best 0123456789"
	_menu.visible = true
	_over.visible = true
	_select.visible = true
	var open := PackedByteArray([1, 1, 0, 1, 0, 1])
	var st := PackedInt32Array([3, 2, 0, 1, 0, 3])
	show_select(14, open, st, PackedInt32Array([12, 5, 0, 9, 0, 33]), 1)
	_menu.visible = true
	_over.visible = true
	_ad_sub.text = "Reward: undo the conflict and keep flying\n\n(stub: no real ad is shown)"
	_ad.visible = true
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

func prewarm_tip() -> void:
	show_tip("Emergency! Flashing aircraft can use any suitable runway. Land them fast. 0123456789")

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
	_art.show_wind = false
	_wind_banner.visible = false
	_art.queue_redraw()
	_flash_ms = -10000
	if is_instance_valid(_splash):
		_splash.queue_free()
