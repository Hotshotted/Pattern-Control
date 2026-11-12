class_name Hud
extends CanvasLayer
## All the 2D interface. The rules it follows on every screen: one primary element (big, high contrast), the rest
## smaller and quieter; icons over words; three text sizes (XL / M / S) and a small fixed colour set; one banner
## and one tip at a time; numbers roll up instead of jumping. Every node is created once; showing / hiding (and
## redrawing the art control) is all that happens in a run.

signal play_pressed

const POPUP_POOL := 8
const MAX_POPUPS_SHOWN := 3

# The three text sizes, and the colours (everything on screen comes from these).
const SZ_XL := Style.SZ_XL
const SZ_M := Style.SZ_M
const SZ_S := Style.SZ_S
const C_TEXT := Style.TEXT
const C_SOFT := Style.TEXT_SOFT
const C_QUIET := Style.TEXT_QUIET
const C_GOLD := Style.ACCENT
const C_GREEN := Style.SUCCESS
const C_RED := Style.DANGER
const C_PANEL := Color(Style.SURFACE_DARK, 1.0)
const C_GOLD_TXT := Color("8a5a05")      # gold text on cream (the bright gold is for coins and stars)
const C_CREAM := Style.WORLD_TEXT        # text over the field
const C_LINE := Style.LINE
const C_DIM := Style.SCRIM

## The drawn parts of the HUD: icons, buttons and cards, the star bar, the results and the little pills.
class Art extends Control:
	const CONFETTI := 72
	const STAR_T0 := 0.35            # when the first results star lands, and the gap between stars
	const STAR_GAP := 0.5
	const RES_UP := 0.9               # results tally: the earnings count up for this long...
	const RES_FINE_AT := 1.25         # ...the fines beat starts this long after the count began (a ticket stamp, the total counts down)...
	const RES_FINE_LEN := 0.8         # ...for this long, and then the final total settles
	const RES_DONE := 4.3             # everything is in (the rows, the unlock card and taps to skip wait for this)
	const SLAM := 0.2
	# ---- the HUD of a running shift ----
	var show_play := false
	var balance := 0                 # the shift's coin total (the target; `bar_shown` rolls towards it)
	var bar_shown := 0.0
	var thresholds := PackedInt32Array([0, 0, 0])   # star 1: landings; stars 2 and 3: net coins
	var star_on := PackedByteArray([0, 0, 0])       # which stars the shift has reached right now
	var landed := 0                                 # landings so far (the count toward star 1)
	var wind_toward := 0.0
	var wind_shown := 0.0               # the arrow's drawn direction: it turns smoothly to wind_toward
	var wind_text := "000"
	var wind_warn := false
	var wind_pulse := -1.0                 # the wind dial pulses once (0..1) when a student appears: land into the wind
	var show_wind := false
	var coin_icon := Vector2(-100.0, -100.0)   # where the coin icon next to the total goes
	var mode_glyph := ""             # "daily" / "bad" while playing one of those
	var chip_finale := ""            # "4" (aircraft still to clear), "" = none
	var chip_finale_red := false
	var chip_weather := ""
	var chip_weather_glyph := "storm"
	var banner_text := ""            # the one banner showing (drawn as a pill behind the banner label)
	var banner_glyph := ""
	var banner_alpha := 0.0
	var banner_color := Color.WHITE
	var banner_rect := Rect2()
	var banner_lines := 1            # 2: a long banner (a toast) wrapped onto two lines of a smaller size
	var tip_alpha := 0.0
	var tip_glyph := ""
	var tip_text := ""
	var tip_rect := Rect2()
	var tip_lines := 1
	var tip_focus := Vector2(INF, INF)         # a tip about a thing: a pulsing ring on it (screen position), and the card sits next to it
	var tip_focus_r := 90.0
	var tut_dim := 0.0                          # Day 1: the game dims (0..1) behind a lesson
	var ghost_pts := PackedVector2Array()       # Day 1: the ghost finger's path (screen) and how far along it is (0..1; -1 = none)
	var ghost_t := -1.0
	var skip_rect := Rect2()                    # Day 1: the Skip button (empty = none)
	var details_lines := PackedStringArray()
	# ---- the pause menu ----
	var show_pause := false
	var icon_id := ""                  # set: this Art is only that glyph, filling its box (see DetailSheet.Icon)
	var icon_col := Color.WHITE
	var pv_on := false                 # the shop's preview sheet is up (see Hud.show_preview)
	var pv := {}
	var pv_t := 0.0
	var pv_ok_t := -1.0                # seconds since the purchase (the success animation), < 0 = none
	var pv_hold := 0.0                 # the buy button's fill, 0..1
	var res_layer := 0                 # the results card is two layers: 1 = the part that never changes (title, star outlines, card, chip boxes and labels), 2 = the rest; 0 = both
	var warm := false                  # (the start-up pre-warm draws the pause sheet and sliders too, under the shift's interface)
	var pause_rect := Rect2(Style.GUTTER * 0.5, 10.0, 80.0, 80.0)   # the pause button, top-left (the wind dial is on the right)
	var slider_rect: Array[Rect2] = [Rect2(), Rect2(), Rect2()]      # 0 effects, 1 music, 2 ambience
	var slider_val := PackedFloat32Array([0.8, 0.8, 0.8])
	var slider_glyph := PackedStringArray(["speaker", "note", "wind"])
	var slider_name := PackedStringArray(["Effects", "Music", "Ambience"])
	# ---- the results ----
	var show_result := false
	var res_t := 0.0                 # seconds since the results appeared (drives the reveal)
	var res_stars := 0
	var res_total := 0
	var res_new_best := false
	var res_best := 0
	var res_doubled := false
	var details_open := false
	var details_rect := Rect2()
	# ---- menu / list headers ----
	var header_glyph := ""           # a small coin / star total in the corner of the list screens and the menu
	var header_text := ""
	var header2_glyph := ""
	var header2_text := ""
	var lockup := false              # the menu's logo lockup (tag, PATTERN, WORK) is drawn
	var dock_rect := Rect2()         # the menu's bottom dock of colour tiles (empty = none)
	var res_chips := PackedInt32Array([0, 0, 0])   # results: landings, early clear, fines
	var res_sub := ""                # results: "Grass Strip · 14 landed"
	var res_sub_two := false          # ...and whether it needs two lines (measured once when the results are set, not every frame)
	var res_unlock := ""             # results: a new airport opened (shown as a card)
	var res_goal: Dictionary = {}    # results: the nearest goal ({"text", "glyph", "frac0", "frac1", "tail", "ready"}): a bar that fills as the coins land
	var res_rows: Array = []         # results: what the shift earned besides the pay, a row each ({"glyph", "text", "coins"}): goals, the streak day, the bonus chest, achievements, mastery ranks
	var res_pills := 0               # results: how many rewarded-ad pills sit under the Next shift button (0 to 2)
	var res_protected := 0           # results: coins the pay floor added (0 = the net was above the floor)
	var pause_card := Rect2()        # the sheet behind the pause menu's sliders
	var _pts := PackedVector2Array()
	var _p3 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _p4 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _p5 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var press_k := -1                  # the button being pressed (drawn pushed in), -1 none
	var press_t := 0.0
	var rel_k := -1                    # the button just released (it bounces back)
	var rel_t := 99.0
	var last_draw_us := 0                # how long the last draw of the art took (microseconds)
	var fc_pos := PackedVector2Array()       # flying coins: where, and how big (0 = not flying)
	var fc_s := PackedFloat32Array()
	var tk_pos := PackedVector2Array()       # flying tickets (a fine popping near its plane, then dropping into the fines counter)
	var tk_s := PackedFloat32Array()
	var fines_total_target := 0
	var tickets_target := 0
	var tickets_shown := 0                  # the fines counter by the HUD: tickets given, and the fines and overtime so far (it catches up as a ticket lands)
	var fines_shown := 0
	var tk_punch := -1.0
	var res_gross := 0                      # results: the earnings before the fines, and the part of them the fines took (what was really deducted)
	var res_fines_eff := 0
	var star_t := PackedFloat32Array([-1.0, -1.0, -1.0])   # seconds since each star on the bar lit (< 0 = not animating)
	var cf_pos := PackedVector2Array()       # confetti
	var cf_rot := PackedFloat32Array()
	var cf_col := PackedColorArray()
	var cf_size := PackedVector2Array()
	var cf_on := PackedByteArray()
	var unlock_name := ""            # the new-airport reveal (empty = none)
	var unlock_t := -1.0
	var logo_t := -1.0                 # the title intro (studio mark, then the game's logo); < 0 = off
	var btn_age := 99.0                # seconds since the screen's buttons appeared (they pop in, staggered)
	var top := 0.0                     # safe-area insets (notch, corners, home indicator)
	var left := 0.0
	var right := 0.0
	var _gp := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _gc := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var _sheen_s: StyleBoxFlat
	var _sheen_m: StyleBoxFlat
	var _sheen_l: StyleBoxFlat
	var _sb_lip: StyleBoxFlat
	var _sb_logo: StyleBoxFlat
	var _sb_track: StyleBoxFlat
	var _sb_fill: StyleBoxFlat
	var _sb_lip_gold: StyleBoxFlat
	var _sb_ghost: StyleBoxFlat
	var _sb_normal: StyleBoxFlat
	var _sb_disabled: StyleBoxFlat
	var _sb_accent: StyleBoxFlat
	var _sb_primary: StyleBoxFlat
	var _sb_gold: StyleBoxFlat
	var _sb_pill: StyleBoxFlat
	var _sb_hold: StyleBoxFlat
	var _sb_stage: StyleBoxFlat
	var _sb_flat_accent: StyleBoxFlat
	var _sb_banner: StyleBoxFlat
	var _sb_tip: StyleBoxFlat
	var _sb_sheet: StyleBoxFlat
	var _sb_tile: StyleBoxFlat       # Sunny Airfield colour tiles: an ink border, a lip under them
	var _sb_tile_lip: StyleBoxFlat
	var _sb_dock: StyleBoxFlat
	var _sb_hdr: StyleBoxFlat        # the coin / star pills in the corners
	var _sb_chip: StyleBoxFlat
	var _sb_card: StyleBoxFlat
	var _sb_tag: StyleBoxFlat
	var _sheen_o: StyleBoxFlat
	var _sb_slider: StyleBoxFlat
	var _sb_vig: StyleBoxFlat
	var _sb_vig_veil: StyleBoxFlat
	var _sb_plate: StyleBoxFlat
	var lockup_airport := ""          # the menu: the selected airport's name and stars, under the title
	var lockup_stars := 0
	var _sb_lockpill: StyleBoxFlat
	var _sb_unlock: StyleBoxFlat

	# Buttons / cards (fixed pool; set per screen). state: 0 normal, 1 disabled, 2 accent.
	# kind: 0 plain button, 1 card (icon, name, one line, pips / stars / cost), 2 the primary button, 3 round icon button, 4 small chip.
	const MAX_BTN := 40
	var btn_rect: Array[Rect2] = []
	var btn_hit: Array[Rect2] = []           # where a tap counts: the button, grown to the 44-point tap size (Style.tap_px) where it is smaller, without reaching another button
	var btn_id := PackedStringArray()
	var btn_text := PackedStringArray()
	var btn_sub := PackedStringArray()
	var btn_state := PackedInt32Array()
	var btn_stars := PackedInt32Array()      # -1: none, 0..3: stars earned (drawn on cards)
	var btn_icon := PackedInt32Array()       # -1: none, 0..5: an animal pilot portrait, 100+: a theme's colour swatch
	var btn_kind := PackedInt32Array()
	var btn_glyph := PackedStringArray()
	var btn_pips := PackedInt32Array()       # -1: none, else upgrade level (five pips)
	var btn_cost := PackedInt32Array()       # -1: none, 0: "MAX", else a price (coin icon + number)
	var btn_badge := PackedInt32Array()      # round buttons: 0 none, >0 a streak number, -1 a tick (done today)
	var btn_lock := PackedInt32Array()       # cards: >0 a locked card showing a padlock and this many stars needed
	var btn_tint := PackedColorArray()       # colour tiles / card icons: the tile colour (alpha 0 = default)
	var btn_tint2 := PackedColorArray()      # compact cosmetic cards: the second swatch colour (a windsock's second stripe, a hangar's wall)
	var btn_map := PackedInt32Array()        # cards: -1 none, else an airport index: its mini-map is drawn as the icon
	var btn_count := 0

	func _init() -> void:
		for i in MAX_BTN:
			btn_rect.append(Rect2())
			btn_hit.append(Rect2())
		for a in [btn_id, btn_text, btn_sub, btn_glyph]:
			a.resize(MAX_BTN)
		for a in [btn_state, btn_stars, btn_icon, btn_kind, btn_pips, btn_cost, btn_badge, btn_lock, btn_map]:
			a.resize(MAX_BTN)
		btn_tint.resize(MAX_BTN)
		btn_tint2.resize(MAX_BTN)
		_pts.resize(10)
		fc_pos.resize(10)
		cf_pos.resize(CONFETTI)
		cf_rot.resize(CONFETTI)
		cf_col.resize(CONFETTI)
		cf_size.resize(CONFETTI)
		cf_on.resize(CONFETTI)
		fc_s.resize(10)
		tk_pos.resize(6)
		tk_s.resize(6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sb_normal = _cream(22, 4, Style.SURFACE_DARK)
		_sb_disabled = _cream(22, 4, Color("e0d1b4"), false)
		_sb_accent = Style.box(Style.SURFACE_DARK, Style.ORANGE, 22, 5)
		_sb_primary = Style.box(Style.ORANGE, Style.ORANGE, Style.R_L, 0, false)
		_sb_lip = Style.box(Style.ORANGE_EDGE, Style.ORANGE_EDGE, Style.R_L, 0)
		_sb_lip_gold = Style.box(Style.ACCENT_DARK, Style.ACCENT_DARK, Style.R_M, 0)
		_sb_gold = _cream(22, 4, Color("fbe9b4"))
		_sb_track = Style.box(Color(Style.INK, 0.55), Color(Style.INK, 0.8), 11, 2, false)
		_sb_fill = Style.box(Style.ACCENT, Style.ACCENT, 11, 0, false)
		_sb_logo = Style.box(Style.SURFACE_DARK_2, Style.ACCENT, Style.R_L, 4)
		_sb_ghost = _cream(Style.R_PILL, 4, Color(Style.SURFACE_DARK, 0.92))
		_sb_pill = _flat(Style.R_PILL, Color(Style.SURFACE_DARK, 0.94))
		_sb_sheet = _cream(Style.R_L, 0, Style.SURFACE_DARK)          # (a surface that holds things: a soft shadow, no bottom edge: only what you can tap has an edge)
		_sb_banner = Style.box(Style.SURFACE_DARK, Style.WARNING, Style.R_PILL, 4, false)
		_sb_tip = Style.box(Style.SURFACE_DARK, Style.SUCCESS, Style.R_PILL, 4, false)
		_sb_stage = _flat(36, Color.WHITE)
		_sb_hold = _flat(Style.R_L, Color(1.0, 0.86, 0.45, 0.6))
		_sb_flat_accent = Style.box(Style.SURFACE_DARK, Style.ORANGE, 22, 5, false)
		_sb_tile = Style.box(Style.PRIMARY, Style.INK, 34, 6, false)
		_sb_tile_lip = Style.box(Style.INK, Style.INK, 34, 0, false)
		_sb_dock = _cream(56, 6, Style.SURFACE_DARK)
		_sb_hdr = _flat(Style.R_PILL, Color(Style.SURFACE_DARK, 0.94))
		_sb_chip = Style.box(Style.SURFACE_DARK_2, Style.SURFACE_DARK_2, 40, 0, false)
		_sb_card = _cream(52, 0, Style.SURFACE_DARK)
		_sb_tag = Style.box(Style.DANGER, Style.INK, 999, 5, false)
		_sb_unlock = Style.box(Style.SURFACE_DARK_2, Color(Style.ACCENT_DARK, 0.9), 60, 4, false)
		_sb_lockpill = Style.box(Color(Style.INK, 0.86), Color(Style.INK, 0.86), Style.R_PILL, 0, false)
		_sb_vig = Style.box(Color.WHITE, Style.EDGE, 26, 4, false)
		_sb_vig_veil = Style.box(Color(Style.INK, 0.5), Color(Style.INK, 0.5), 26, 0, false)
		_sb_slider = Style.box(Color(0.88, 0.8, 0.64), Style.EDGE, 11, 2, false)
		_sb_plate = Style.box(Color(0.2, 0.12, 0.04, 0.4), Color(1, 0.96, 0.87, 0.35), 100, 3, false)
		_sheen_s = Style.sheen(Style.R_S, 0.4)
		_sheen_m = Style.sheen(Style.R_M, 0.55)
		_sheen_l = Style.sheen(Style.R_L, 0.5)
		_sheen_o = Style.sheen(Style.R_L, 0.4)
		_sheen_o.bg_color = Color(1.0, 0.8, 0.55, 0.42)

	## A cream surface: a solid bottom edge (#C9A46E) and a soft warm drop shadow. The gradient comes from the sheen drawn on top.
	func _cream(radius: int, edge: int, fill: Color, shadow: bool = true) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = Style.EDGE
		sb.border_width_bottom = edge
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		if shadow:
			sb.shadow_color = Style.SHADOW_COLOR
			sb.shadow_size = Style.SHADOW_SIZE
			sb.shadow_offset = Style.SHADOW_OFFSET
		return sb

	## A flat cream shape for things that only show something: no bottom edge, no shadow (those belong to what you can tap).
	func _flat(radius: int, fill: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		return sb

	## Small tracked capitals: the letters spaced apart, one by one.
	func tracked(s: String, pos: Vector2, size_px: int, col: Color, track: float) -> void:
		size_px = maxi(size_px, Style.SZ_CAPTION)
		var f := Style.font_for(s, size_px)
		var x := pos.x
		for i in s.length():
			var ch := s.substr(i, 1)
			_ds(f, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, col, "caption")
			x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x + track

	## A panel with its soft highlight: a rounded cap at the top fading down into the face (the style's gradient).
	func panel(sb: StyleBoxFlat, r: Rect2, sheen_sb: StyleBoxFlat = null) -> void:
		_dsb(sb, r)
		var sh := sheen_sb if sheen_sb != null else _sheen_m
		var inset := float(sb.border_width_left) + 2.0
		var rad := float(sh.corner_radius_top_left)
		var h := maxf(r.size.y * 0.5 - inset, rad + 2.0)
		var x0 := r.position.x + inset
		var x1 := r.end.x - inset
		var y0 := r.position.y + inset
		_dsb(sh, Rect2(x0, y0, x1 - x0, rad))
		var a := sh.bg_color.a
		_gp[0] = Vector2(x0, y0 + rad)
		_gp[1] = Vector2(x1, y0 + rad)
		_gp[2] = Vector2(x1, y0 + h)
		_gp[3] = Vector2(x0, y0 + h)
		_gc[0] = Color(sh.bg_color.r, sh.bg_color.g, sh.bg_color.b, a)
		_gc[1] = _gc[0]
		_gc[2] = Color(sh.bg_color.r, sh.bg_color.g, sh.bg_color.b, 0.0)
		_gc[3] = _gc[2]
		draw_polygon(_gp, _gc)

	# ---------- the audit's text recorder (see tools/ui_overlap_check.gd) ----------
	# Every string the art draws goes through _ds / _dms: when `rec_on` is set the run is noted (its box, size, width limit, whether it
	# overflows that limit), so the overlap check can see canvas-drawn text as well as the Controls.
	var rec_on := false
	var rec_texts: Array = []
	var rec_glyphs: Array = []
	var rec_boxes: Array = []                      # the panels, cards and pills drawn (the audit checks that text stays inside the box it is on)

	func _dsb(sb: StyleBox, r: Rect2) -> void:
		if rec_on:
			rec_boxes.append(rec_xf * r)
		draw_style_box(sb, r)
	var rec_xf := Transform2D.IDENTITY             # the transform the drawing is under (the recorder maps the boxes through it)

	func _dst(pos: Vector2, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> void:
		rec_xf = Transform2D(rot, scl, 0.0, pos)
		draw_set_transform(pos, rot, scl)

	## The floor of a text's role (Style: caption 11 pt, body 15 pt, button label 17 pt; a heading is as designed): text is never drawn under it.
	## A string that is the label of one of this layer's buttons is a button label; "caption" is passed by the few call sites that draw one.
	func role_size(s: String, size_px: int, role: String = "") -> int:
		if role == "" and size_px >= 54:
			return size_px
		if role == "":
			role = "body"
			for k in btn_count:
				if btn_text[k] == s:
					role = "button"
					break
		return maxi(size_px, Style.min_size(role))

	func _ds(f: Font, pos: Vector2, s: String, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, size_px: int = 16, col: Color = Color.WHITE, role: String = "") -> void:
		size_px = role_size(s, size_px, role)
		if rec_on and s != "" and col.a > 0.05:
			rec_text(f, pos, s, align, width, size_px, 1, role)
		draw_string(f, pos, s, align, width, size_px, col)

	func _dms(f: Font, pos: Vector2, s: String, align: int, width: float, size_px: int, max_lines: int, col: Color = Color.WHITE, role: String = "") -> void:
		size_px = role_size(s, size_px, role)
		if rec_on and s != "" and col.a > 0.05:
			rec_text(f, pos, s, align, width, size_px, max_lines, role)
		draw_multiline_string(f, pos, s, align, width, size_px, max_lines, col)

	func _has_descender(s: String) -> bool:
		for ch in "gjpqyQ,;()":
			if s.contains(ch):
				return true
		return false

	## Note a text run: `pos` is the baseline start, as for draw_string; `max_lines` > 1 for a wrapped run.
	func rec_text(f: Font, pos: Vector2, s: String, align: int, width: float, size_px: int, max_lines: int, role: String = "") -> void:
		var asc := f.get_ascent(size_px)
		var h := asc + f.get_descent(size_px)
		var nat := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var lines := 1
		var tw := nat
		if max_lines > 1 and width > 0.0:
			var ms := f.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, -1)
			lines = maxi(roundi(ms.y / maxf(f.get_height(size_px), 1.0)), 1)
			tw = minf(nat, width) if lines > 1 else nat
		var x0 := pos.x
		if width > 0.0:
			match align:
				HORIZONTAL_ALIGNMENT_CENTER:
					x0 = pos.x + (width - tw) * 0.5
				HORIZONTAL_ALIGNMENT_RIGHT:
					x0 = pos.x + width - tw
		var over := (width > 0.0 and max_lines <= 1 and nat > width + 0.5) or (max_lines > 1 and lines > max_lines)
		var nl := float(mini(lines, maxi(max_lines, 1)))
		var ink_top := pos.y - 0.74 * float(size_px)            # (the ink, not the line box: capitals reach 0.74 of the size above the baseline,
		var ink_bot := pos.y + (h - asc) * (nl - 1.0) + float(size_px) * (0.22 if _has_descender(s) else 0.04) + (nl - 1.0) * asc * 0.0       #  descenders 0.22 below)
		var rr := rec_xf * Rect2(x0, ink_top, tw, maxf(ink_bot - ink_top, 4.0))
		rec_texts.append({"text": s, "rect": rr, "size": roundi(float(size_px) * rec_xf.get_scale().y), "limit": width * rec_xf.get_scale().x, "natural": nat * rec_xf.get_scale().x, "over": over, "role": role})

	# ---------- text ----------

	func text(s: String, pos: Vector2, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
		var f := Style.font_for(s, size_px)
		draw_string_outline(f, pos, s, align, width, size_px, maxi(size_px / 8, 4), Color(Style.INK, col.a))
		_ds(f, pos, s, align, width, size_px, col)

	## Text on a cream surface: brown, no outline.
	func ptext(s: String, pos: Vector2, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, role: String = "") -> void:
		_ds(Style.font_for(s, size_px), pos, s, align, width, size_px, col, role)

	## Text on the primary button: white with a slight dark shadow.
	func btext(s: String, pos: Vector2, size_px: int, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
		var f := Style.display()
		_ds(f, pos + Vector2(0, 4), s, align, width, size_px, Color(Style.ORANGE_EDGE.r * 0.6, Style.ORANGE_EDGE.g * 0.5, 0.05, 0.5))
		_ds(f, pos, s, align, width, size_px, Color.WHITE)

	func text_width(s: String, size_px: int) -> float:
		size_px = role_size(s, size_px)
		return Style.font_for(s, size_px).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

	# ---------- shapes ----------

	func star(c: Vector2, r: float, fill: Color, outline: bool = true, rot: float = 0.0) -> void:
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0 + rot
			var rr := (r if k % 2 == 0 else r * 0.45) + (4.0 if outline else 0.0)
			_pts[k] = c + Vector2(cos(a), sin(a)) * rr
		if outline:
			draw_colored_polygon(_pts, Color(Style.INK, fill.a))
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0 + rot
				_pts[k] = c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45)
		draw_colored_polygon(_pts, fill)

	func tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
		_p3[0] = a
		_p3[1] = b
		_p3[2] = c
		draw_colored_polygon(_p3, col)

	func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
		_p4[0] = a
		_p4[1] = b
		_p4[2] = c
		_p4[3] = d
		draw_colored_polygon(_p4, col)

	func line3(a: Vector2, b: Vector2, c: Vector2, col: Color, w: float) -> void:
		_line[0] = a
		_line[1] = b
		_line[2] = c
		draw_polyline(_line, col, w)

	## Icons: small pictures that stand in for words. `r` is the radius of the box they fit in.
	func glyph(id: String, c: Vector2, r: float, col: Color = Color.WHITE) -> void:
		if rec_on and col.a > 0.05:
			var gr := r * (1.0 if id == "coin" or id == "star" or id == "star_off" else 0.8)       # (the other pictures fill about four fifths of their box)
			rec_glyphs.append({"id": id, "rect": rec_xf * Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0)})
		var w := maxf(r * 0.16, 3.0)
		match id:
			"coin":      # a real coin: gold with a darker rim and a three-blade propeller mark
				draw_circle(c, r, Color(Style.ACCENT_DARK, col.a))
				draw_circle(c, r - maxf(r * 0.14, 2.0), Color(Style.ACCENT, col.a))
				draw_arc(c, r * 0.72, 0.0, TAU, 20, Color(Style.ACCENT_DARK, col.a * 0.55), maxf(r * 0.07, 1.5))
				for q in 3:
					var qa := q * TAU / 3.0 - PI * 0.5
					var qd := Vector2(cos(qa), sin(qa))
					var qn := Vector2(-qd.y, qd.x)
					tri(c + qn * r * 0.1, c - qn * r * 0.1, c + qd * r * 0.55 + qn * r * 0.14, Color(Style.ACCENT_DARK, col.a))
				draw_circle(c, r * 0.13, Color(Style.ACCENT_DARK, col.a))
			"ticket":        # a parking-ticket: a slip with a notch on each side and two lines of print
				var slip := Rect2(c.x - r * 0.95, c.y - r * 0.6, r * 1.9, r * 1.2)
				draw_rect(slip, col)
				draw_circle(Vector2(slip.position.x, c.y), r * 0.22, Color(Style.INK, col.a * 0.55))
				draw_circle(Vector2(slip.end.x, c.y), r * 0.22, Color(Style.INK, col.a * 0.55))
				draw_line(Vector2(c.x - r * 0.45, c.y - r * 0.18), Vector2(c.x + r * 0.45, c.y - r * 0.18), Color(Style.INK, col.a * 0.7), maxf(r * 0.12, 1.5))
				draw_line(Vector2(c.x - r * 0.45, c.y + r * 0.2), Vector2(c.x + r * 0.2, c.y + r * 0.2), Color(Style.INK, col.a * 0.7), maxf(r * 0.12, 1.5))
			"star":
				star(c, r, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, col.a), true)
			"star_off":
				star(c, r, Color(Style.WORLD_TEXT, col.a), true)
			"clock":
				draw_arc(c, r, 0.0, TAU, 28, col, w)
				draw_line(c, c + Vector2(0, -r * 0.65), col, w)
				draw_line(c, c + Vector2(r * 0.45, r * 0.2), col, w)
			"pause":
				draw_rect(Rect2(c.x - r * 0.55, c.y - r * 0.7, r * 0.4, r * 1.4), col)
				draw_rect(Rect2(c.x + r * 0.15, c.y - r * 0.7, r * 0.4, r * 1.4), col)
			"play":
				tri(c + Vector2(-r * 0.5, -r * 0.7), c + Vector2(-r * 0.5, r * 0.7), c + Vector2(r * 0.75, 0), col)
			"back":
				line3(c + Vector2(r * 0.4, -r * 0.7), c + Vector2(-r * 0.4, 0), c + Vector2(r * 0.4, r * 0.7), col, w * 1.6)
			"chev_down":
				line3(c + Vector2(-r * 0.7, -r * 0.3), c + Vector2(0, r * 0.4), c + Vector2(r * 0.7, -r * 0.3), col, w * 1.4)
			"chev_r":
				line3(c + Vector2(-r * 0.4, -r * 0.7), c + Vector2(r * 0.4, 0), c + Vector2(-r * 0.4, r * 0.7), col, w * 1.6)
			"chev_up":
				line3(c + Vector2(-r * 0.7, r * 0.3), c + Vector2(0, -r * 0.4), c + Vector2(r * 0.7, r * 0.3), col, w * 1.4)
			"home":
				tri(c + Vector2(-r * 0.9, -r * 0.05), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.9, -r * 0.05), col)
				draw_rect(Rect2(c.x - r * 0.6, c.y - r * 0.05, r * 1.2, r * 0.85), col)
				draw_rect(Rect2(c.x - r * 0.17, c.y + r * 0.3, r * 0.34, r * 0.5), Color(Style.INK, col.a))
			"restart":
				draw_arc(c, r * 0.7, -PI * 0.15, PI * 1.5, 24, col, w * 1.5)
				tri(c + Vector2(r * 0.95, -r * 0.05), c + Vector2(r * 0.3, -r * 0.2), c + Vector2(r * 0.85, -r * 0.8), col)
			"lock":
				draw_rect(Rect2(c.x - r * 0.65, c.y - r * 0.1, r * 1.3, r * 0.95), col)
				draw_arc(c + Vector2(0, -r * 0.1), r * 0.45, PI, TAU, 12, col, w * 1.3)
			"check":
				line3(c + Vector2(-r * 0.7, 0.0), c + Vector2(-r * 0.2, r * 0.55), c + Vector2(r * 0.8, -r * 0.55), col, w * 1.8)
			"plane":
				draw_line(c + Vector2(0, -r * 0.9), c + Vector2(0, r * 0.8), col, w * 1.8)
				tri(c + Vector2(-r * 0.95, r * 0.15), c + Vector2(r * 0.95, r * 0.15), c + Vector2(0, -r * 0.3), col)
				tri(c + Vector2(-r * 0.4, r * 0.85), c + Vector2(r * 0.4, r * 0.85), c + Vector2(0, r * 0.5), col)
			"ad":
				draw_rect(Rect2(c.x - r * 0.9, c.y - r * 0.6, r * 1.8, r * 1.2), col, false, w)
				tri(c + Vector2(-r * 0.25, -r * 0.35), c + Vector2(-r * 0.25, r * 0.35), c + Vector2(r * 0.4, 0), col)
			"speaker":
				quad(c + Vector2(-r * 0.9, -r * 0.35), c + Vector2(-r * 0.4, -r * 0.35), c + Vector2(-r * 0.4, r * 0.35), c + Vector2(-r * 0.9, r * 0.35), col)
				tri(c + Vector2(-r * 0.4, -r * 0.35), c + Vector2(r * 0.15, -r * 0.8), c + Vector2(r * 0.15, r * 0.8), col)
				tri(c + Vector2(-r * 0.4, r * 0.35), c + Vector2(r * 0.15, -r * 0.8), c + Vector2(r * 0.15, r * 0.8), col)
				draw_arc(c + Vector2(r * 0.15, 0), r * 0.55, -PI * 0.35, PI * 0.35, 8, col, w)
				draw_arc(c + Vector2(r * 0.15, 0), r * 0.95, -PI * 0.35, PI * 0.35, 8, col, w)
			"note":
				draw_circle(c + Vector2(-r * 0.4, r * 0.55), r * 0.38, col)
				draw_line(c + Vector2(-r * 0.05, r * 0.5), c + Vector2(-r * 0.05, -r * 0.8), col, w * 1.3)
				tri(c + Vector2(-r * 0.05, -r * 0.8), c + Vector2(r * 0.7, -r * 0.4), c + Vector2(-r * 0.05, -r * 0.2), col)
			"bad_l":      # the student pilot's L
				text_l(c, r, col)
			"hangar":      # a hangar: a pitched roof over a wall with a door
				tri(c + Vector2(-r * 0.95, -r * 0.1), c + Vector2(0, -r * 0.9), c + Vector2(r * 0.95, -r * 0.1), col)
				draw_rect(Rect2(c.x - r * 0.75, c.y - r * 0.1, r * 1.5, r * 0.95), col)
				draw_rect(Rect2(c.x - r * 0.3, c.y + r * 0.2, r * 0.6, r * 0.65), Color(Style.INK, col.a * 0.55))
			"sun":      # a white sun (on the Daily tile)
				draw_arc(c, r * 0.42, 0.0, TAU, 20, col, w * 1.4)
				for k in 8:
					var a := k * PI / 4.0
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.72, c + Vector2(cos(a), sin(a)) * r * 1.0, col, w * 1.3)
			"airport":
				draw_rect(Rect2(c.x - r * 0.3, c.y - r * 0.95, r * 0.6, r * 1.9), col)
				for k in 3:
					draw_rect(Rect2(c.x - r * 0.06, c.y - r * 0.7 + k * r * 0.55, r * 0.12, r * 0.28), Color(Style.INK, col.a))
			"upgrades":
				tri(c + Vector2(-r * 0.8, r * 0.05), c + Vector2(r * 0.8, r * 0.05), c + Vector2(0, -r * 0.9), col)
				draw_rect(Rect2(c.x - r * 0.28, c.y + r * 0.05, r * 0.56, r * 0.85), col)
			"shop":      # a T-shirt: the shop sells looks
				_pts.resize(8)
				_pts[0] = c + Vector2(-r * 0.3, -r * 0.8)
				_pts[1] = c + Vector2(-r * 0.95, -r * 0.35)
				_pts[2] = c + Vector2(-r * 0.7, r * 0.05)
				_pts[3] = c + Vector2(-r * 0.5, -r * 0.1)
				_pts[4] = c + Vector2(-r * 0.5, r * 0.85)
				_pts[5] = c + Vector2(r * 0.5, r * 0.85)
				_pts[6] = c + Vector2(r * 0.5, -r * 0.1)
				_pts[7] = c + Vector2(r * 0.7, r * 0.05)
				draw_colored_polygon(_pts, col)
				tri(c + Vector2(r * 0.3, -r * 0.8), c + Vector2(r * 0.95, -r * 0.35), c + Vector2(r * 0.7, r * 0.05), col)
				tri(c + Vector2(-r * 0.3, -r * 0.8), c + Vector2(r * 0.3, -r * 0.8), c + Vector2(0, -r * 0.5), Color(Style.INK, col.a))
				_pts.resize(10)
			"daily":      # a sun: a new shift every day
				draw_circle(c, r * 0.45, Color(Style.ACCENT, col.a))
				for k in 8:
					var a := k * PI / 4.0
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.7, c + Vector2(cos(a), sin(a)) * r * 1.0, Color(Style.ACCENT, col.a), w * 1.3)
			"bad":
				draw_rect(Rect2(c.x - r * 0.8, c.y - r * 0.8, r * 1.6, r * 1.6), Color(Style.WARNING, col.a))
				line3(c + Vector2(-r * 0.3, -r * 0.5), c + Vector2(-r * 0.3, r * 0.5), c + Vector2(r * 0.45, r * 0.5), Color(1, 1, 1, col.a), w * 2.0)
			"radar":
				draw_arc(c, r * 0.9, 0.0, TAU, 24, col, w)
				draw_arc(c, r * 0.5, 0.0, TAU, 20, col, w)
				draw_line(c, c + Vector2(r * 0.7, -r * 0.7), col, w * 1.3)
			"approach":
				draw_line(c + Vector2(-r * 0.9, -r * 0.9), c + Vector2(-r * 0.15, r * 0.9), col, w * 1.3)
				draw_line(c + Vector2(r * 0.9, -r * 0.9), c + Vector2(r * 0.15, r * 0.9), col, w * 1.3)
				draw_line(c + Vector2(0, -r * 0.8), c + Vector2(0, r * 0.9), col, w * 0.9)
			"tower":
				quad(c + Vector2(-r * 0.35, r * 0.9), c + Vector2(-r * 0.2, -r * 0.2), c + Vector2(r * 0.2, -r * 0.2), c + Vector2(r * 0.35, r * 0.9), col)
				draw_rect(Rect2(c.x - r * 0.75, c.y - r * 0.75, r * 1.5, r * 0.55), col)
			"comms":
				draw_circle(c + Vector2(-r * 0.5, r * 0.5), r * 0.22, col)
				draw_arc(c + Vector2(-r * 0.5, r * 0.5), r * 0.7, -PI * 0.5, 0.0, 8, col, w * 1.1)
				draw_arc(c + Vector2(-r * 0.5, r * 0.5), r * 1.2, -PI * 0.5, 0.0, 10, col, w * 1.1)
			"holding":
				draw_arc(c, r * 0.7, PI * 0.2, PI * 1.9, 20, col, w * 1.4)
				tri(c + Vector2(r * 0.75, -r * 0.05), c + Vector2(r * 0.2, -r * 0.15), c + Vector2(r * 0.65, -r * 0.7), col)
			"rwlights":      # runway lights: two rows of lamps
				for q in 4:
					var qy := -r * 0.75 + q * r * 0.5
					draw_circle(c + Vector2(-r * 0.45, qy), r * 0.14, col)
					draw_circle(c + Vector2(r * 0.45, qy), r * 0.14, col)
			"applights":      # approach lights: lamps converging on the runway
				for q in 4:
					var qy2 := r * 0.8 - q * r * 0.5
					var qx := r * (0.15 + 0.2 * q)
					draw_circle(c + Vector2(-qx, qy2), r * 0.13, col)
					draw_circle(c + Vector2(qx, qy2), r * 0.13, col)
			"fuel":      # a fuel tank
				draw_rect(Rect2(c.x - r * 0.6, c.y - r * 0.45, r * 1.2, r * 1.1), col)
				draw_circle(c + Vector2(0, -r * 0.45), r * 0.6, col)
				draw_rect(Rect2(c.x - r * 0.6, c.y + r * 0.05, r * 1.2, r * 0.18), Color(Style.INK, col.a * 0.5))
			"exit":      # an exit taxiway branching off a runway
				draw_line(c + Vector2(-r * 0.4, r * 0.95), c + Vector2(-r * 0.4, -r * 0.95), col, w * 1.4)
				draw_line(c + Vector2(-r * 0.4, r * 0.3), c + Vector2(r * 0.7, -r * 0.7), col, w * 1.4)
			"turnoffs":
				draw_line(c + Vector2(0, r * 0.95), c + Vector2(0, -r * 0.2), col, w * 1.4)
				draw_line(c + Vector2(0, -r * 0.2), c + Vector2(-r * 0.7, -r * 0.9), col, w * 1.4)
				draw_line(c + Vector2(0, -r * 0.2), c + Vector2(r * 0.7, -r * 0.9), col, w * 1.4)
			"glider":
				draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), col, w * 1.4)
				draw_line(c, c + Vector2(0, r * 0.8), col, w * 1.4)
			"heli":
				draw_line(c + Vector2(-r, -r * 0.5), c + Vector2(r, -r * 0.5), col, w * 1.3)
				draw_circle(c + Vector2(0, r * 0.1), r * 0.5, col)
				draw_line(c + Vector2(0, r * 0.1), c + Vector2(0, r * 0.95), col, w)
			"jet":
				draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.9), col, w * 1.7)
				tri(c + Vector2(-r * 0.8, r * 0.5), c + Vector2(r * 0.8, r * 0.5), c + Vector2(0, -r * 0.2), col)
			"seaplane":
				glyph("plane", c + Vector2(0, -r * 0.15), r * 0.8, col)
				draw_line(c + Vector2(-r * 0.9, r * 0.8), c + Vector2(r * 0.9, r * 0.8), Color(0.45, 0.75, 1.0, col.a), w * 1.2)
			"emergency":
				tri(c + Vector2(-r, r * 0.85), c + Vector2(r, r * 0.85), c + Vector2(0, -r * 0.9), Color(Style.DANGER, col.a))
				draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.25), Color.WHITE, w * 1.2)
				draw_circle(c + Vector2(0, r * 0.55), w * 0.9, Color.WHITE)
			"vip":
				star(c, r, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, col.a), true)
			"student":
				glyph("bad", c, r, col)
			"storm":
				draw_circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.5, col)
				draw_circle(c + Vector2(r * 0.3, -r * 0.1), r * 0.6, col)
				quad(c + Vector2(r * 0.1, r * 0.1), c + Vector2(-r * 0.2, r * 0.1), c + Vector2(-r * 0.4, r * 0.95), c + Vector2(0.0, r * 0.35), Color(1.0, 0.85, 0.2, col.a))
			"fog":
				for k in 3:
					draw_line(c + Vector2(-r * 0.9 + k * r * 0.2, -r * 0.6 + k * r * 0.6), c + Vector2(r * 0.9 - (2 - k) * r * 0.2, -r * 0.6 + k * r * 0.6), col, w * 1.3)
			"cross":
				draw_line(c + Vector2(-r * 0.9, r * 0.5), c + Vector2(r * 0.8, -r * 0.6), col, w * 1.4)
				tri(c + Vector2(r * 0.95, -r * 0.7), c + Vector2(r * 0.2, -r * 0.7), c + Vector2(r * 0.7, 0.0), col)
			"wind":
				draw_line(c + Vector2(-r * 0.9, -r * 0.3), c + Vector2(r * 0.5, -r * 0.3), col, w * 1.2)
				draw_line(c + Vector2(-r * 0.9, r * 0.25), c + Vector2(r * 0.8, r * 0.25), col, w * 1.2)
				draw_arc(c + Vector2(r * 0.5, -r * 0.55), r * 0.25, PI * 0.5, PI * 2.0, 8, col, w * 1.2)
			"flame":
				draw_circle(c + Vector2(0, r * 0.2), r * 0.6, Color(1.0, 0.55, 0.15, col.a))
				tri(c + Vector2(-r * 0.5, r * 0.1), c + Vector2(r * 0.5, r * 0.1), c + Vector2(0, -r * 0.95), Color(1.0, 0.55, 0.15, col.a))
			_:
				draw_circle(c, r * 0.5, col)

	## An illustrated mini-map of airport `i` in a circle of radius `r` at `c`: the field (or water), its runways in their colours,
	## pads, lanes and mountains. (Static data from Airports; nothing is allocated except the four-point polygons it reuses.)
	func _minimap(c: Vector2, r: float, i: int, dim: bool = false) -> void:
		var d: Dictionary = Airports.def(i)
		var water: bool = d.get("water", false)
		var k := r / 6.2                       # world units -> pixels
		var a := 0.45 if dim else 1.0
		draw_circle(c + Vector2(0, 5.0), r + 4.0, Color(Style.INK, a))
		draw_circle(c, r, Color((d["ground"] as Color).darkened(0.1 if dim else 0.0), a))
		for dc in d["decor"]:
			var col: Color = dc["color"]
			if dc["shape"] == "disc":
				draw_circle(c + (dc["pos"] as Vector2) * k, minf(dc["r"] * k, r * 0.95), Color(col, a))
			else:
				var sz: Vector2 = dc["size"]
				var p: Vector2 = c + (dc["pos"] as Vector2) * k - sz * k * 0.5
				var rr := Rect2(p, sz * k).intersection(Rect2(c - Vector2(r, r) * 0.95, Vector2(r, r) * 1.9))
				if rr.size.x > 0.0 and rr.size.y > 0.0:
					draw_rect(rr, Color(col, a))
		for lane in d["lanes"]:
			var h := deg_to_rad(lane["heading"])
			_rot_rect(c + (lane["center"] as Vector2) * k, h, lane["width"] * k, minf(lane["length"] * k, r * 1.7), Color(0.38, 0.72, 0.9, a))
		for rw in d["runways"]:
			var h := deg_to_rad(rw["heading"])
			var cc: Vector2 = c + (rw["center"] as Vector2) * k
			var w: float = maxf(rw["width"] * k * 1.1, 6.0)
			var l: float = minf(rw["length"] * k, r * 1.8)
			_rot_rect(cc, h, w + 4.0, l + 4.0, Color(rw["color"], a))
			_rot_rect(cc, h, w, l, Color(0.243, 0.275, 0.345, a))
		for pad in d["pads"]:
			draw_circle(c + (pad["center"] as Vector2) * k, maxf(pad["radius"] * k, 6.0), Color(pad["color"], a))
		for hz in d["hazards"]:
			var hc: Vector2 = c + (hz["center"] as Vector2) * k
			var hr: float = hz["radius"] * k * 0.8
			tri(hc + Vector2(-hr, hr * 0.6), hc + Vector2(hr, hr * 0.6), hc + Vector2(0, -hr), Color(0.62, 0.6, 0.58, a))
		draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.5 * a), 3.0)

	func _rot_rect(c: Vector2, heading: float, w: float, l: float, col: Color) -> void:
		var dir := Vector2(sin(heading), -cos(heading))
		var side := Vector2(-dir.y, dir.x)
		quad(c - dir * l * 0.5 - side * w * 0.5, c - dir * l * 0.5 + side * w * 0.5, c + dir * l * 0.5 + side * w * 0.5, c + dir * l * 0.5 - side * w * 0.5, col)

	## A top-down vignette of airport `i` in a rounded square: its field (or water), runways in their colours, pads, lanes, mountains, the
	## apron, and the airport's landmark (a barn and silo; a lighthouse and pier; a lodge and pines). Dimmed when the airport is locked.
	func _vignette(r: Rect2, i: int, dim: bool = false, theme: int = -1) -> void:
		var d: Dictionary = Airports.def(i)
		var water: bool = d.get("water", false)
		var gcol: Color = d["ground"]
		var tint := Color.WHITE
		if theme >= 0:       # the shop's preview: the same picture in a skin's colours
			var th: Dictionary = Cosmetics.THEMES[theme]
			if th["ground"] != null and not water:
				gcol = th["ground"]
			tint = th["tint"]
		_sb_vig.bg_color = gcol.darkened(0.12) if not water else Color("5db8e0")
		_dsb(_sb_vig, r)
		var c := r.get_center()
		var k := r.size.x / 13.0
		for dc in d["decor"]:
			var col: Color = (dc["color"] as Color) * tint
			if dc["shape"] == "disc":
				draw_circle(c + (dc["pos"] as Vector2) * k, minf(dc["r"] * k, r.size.x * 0.46), col)
			else:
				var sz: Vector2 = dc["size"]
				var rr := Rect2(c + (dc["pos"] as Vector2) * k - sz * k * 0.5, sz * k).intersection(r.grow(-3.0))
				if rr.size.x > 0.0 and rr.size.y > 0.0:
					draw_rect(rr, col)
		for lane in d["lanes"]:
			_rot_rect(c + (lane["center"] as Vector2) * k, deg_to_rad(lane["heading"]), lane["width"] * k, minf(lane["length"] * k, r.size.x * 0.8), Color("62b8e2"))
		for rw in d["runways"]:
			var h := deg_to_rad(rw["heading"])
			var cc: Vector2 = c + (rw["center"] as Vector2) * k
			var w: float = maxf(rw["width"] * k * 1.1, 6.0)
			var l: float = minf(rw["length"] * k, r.size.y * 0.92)
			_rot_rect(cc, h, w + 4.0, l + 4.0, rw["color"])
			_rot_rect(cc, h, w, l, Color("6a7079"))
			_rot_rect(cc, h, 2.0, l * 0.84, Color(0.95, 0.93, 0.89, 0.85))
		for pad in d["pads"]:
			draw_circle(c + (pad["center"] as Vector2) * k, maxf(pad["radius"] * k, 6.0), pad["color"])
		for hz in d["hazards"]:
			var hc: Vector2 = c + (hz["center"] as Vector2) * k
			var hr: float = hz["radius"] * k * 0.8
			if r.grow(-4.0).has_point(hc):
				tri(hc + Vector2(-hr, hr * 0.6), hc + Vector2(hr, hr * 0.6), hc + Vector2(0, -hr), Color("a39d92"))
				tri(hc + Vector2(-hr * 0.3, -hr * 0.45), hc + Vector2(hr * 0.3, -hr * 0.45), hc + Vector2(0, -hr), Color.WHITE)
		var ap: Dictionary = d.get("apron", {})
		if not ap.is_empty():
			var ac: Vector2 = c + (ap["center"] as Vector2) * k
			var sc: float = ap["s"]
			draw_rect(Rect2(ac - Vector2(1.4, 1.6) * sc * k, Vector2(2.8, 3.2) * sc * k), Color("b6bbc2"))
			draw_rect(Rect2(ac + Vector2(-1.3, -1.45) * sc * k, Vector2(1.3, 0.95) * sc * k), Color("e2654a"))
			draw_rect(Rect2(ac + Vector2(0.0, 0.0) * sc * k + Vector2(-1.2, -0.1) * sc * k, Vector2(1.0, 0.7) * sc * k), Color("4fb8b2"))
		# the landmark: by airport style
		match Airports.style(i):
			"coastal":
				var lh := c + Vector2(r.size.x * 0.28, -r.size.y * 0.26)
				draw_circle(lh, r.size.x * 0.06, Color.WHITE)
				draw_circle(lh, r.size.x * 0.03, Color("e2483b"))
				draw_rect(Rect2(c + Vector2(r.size.x * 0.34, r.size.y * 0.0), Vector2(r.size.x * 0.1, r.size.y * 0.26)), Color("a8723f"))
			"alpine":
				var lo := c + Vector2(-r.size.x * 0.3, r.size.y * 0.22)
				draw_rect(Rect2(lo, Vector2(r.size.x * 0.18, r.size.y * 0.12)), Color("8a5a30"))
				draw_rect(Rect2(lo + Vector2(r.size.x * 0.12, -r.size.y * 0.04), Vector2(r.size.x * 0.03, r.size.y * 0.05)), Color("e8e0d0"))
				for q in 3:
					var pc := c + Vector2(-r.size.x * 0.36 + q * r.size.x * 0.05, r.size.y * 0.36 - q * r.size.y * 0.02)
					tri(pc + Vector2(-6, 10), pc + Vector2(6, 10), pc + Vector2(0, -10), Color("2f6b3c"))
			_:
				var bp := c + Vector2(-r.size.x * 0.34, r.size.y * 0.3)
				draw_rect(Rect2(bp, Vector2(r.size.x * 0.2, r.size.y * 0.13)), Color("b8352b"))
				draw_circle(bp + Vector2(r.size.x * 0.24, r.size.y * 0.04), r.size.x * 0.04, Color("f1ece0"))
		if dim:
			_dsb(_sb_vig_veil, r)
		if theme >= 0 and Cosmetics.THEMES[theme]["sun"] < 0.6:
			_dsb(_sb_vig_veil, r)         # (the night skin: the same picture, darker)

	## A card's icon: an animal pilot portrait, or a theme's two colours.
	func text_l(c: Vector2, r: float, col: Color) -> void:
		_ds(Style.display(), c + Vector2(-r * 0.45, r * 0.55), "L", HORIZONTAL_ALIGNMENT_CENTER, r * 0.9, int(r * 1.7), col)

	func _draw_icon(icon: int, c: Vector2, r: float) -> void:
		if icon < 100:
			Portraits.draw(self, c, r, icon)
		else:
			var t: Dictionary = Cosmetics.THEMES[icon - 100]
			var g: Color = t["ground"] if t["ground"] != null else Color(0.4, 0.65, 0.4)
			draw_circle(c, r + 3.0, Style.INK)
			draw_circle(c, r, g)
			draw_circle(c + Vector2(r * 0.35, -r * 0.2), r * 0.45, t["leaf"])
			draw_circle(c + Vector2(-r * 0.4, r * 0.35), r * 0.3, (t["bg"] as Color).lightened(0.2))

	# ---------- buttons and cards ----------

	## Is anything on the buttons still moving (so the art needs redrawing every frame)?
	func animating() -> bool:
		return (press_k >= 0 and press_t < Style.T_FAST) or (rel_k >= 0 and rel_t < Style.T_BASE)       # (a panel opening is the layer's transform and opacity: nothing is redrawn for it)

	func clear_buttons() -> void:
		btn_count = 0
		queue_redraw()

	func add_button(id: String, label: String, rect: Rect2, state: int = 0, sub: String = "", stars: int = -1, icon: int = -1, opts: Dictionary = {}) -> void:
		if btn_count >= MAX_BTN:
			return
		var k := btn_count
		btn_id[k] = id
		btn_text[k] = label
		btn_sub[k] = sub
		btn_rect[k] = rect
		btn_state[k] = state
		btn_stars[k] = stars
		btn_icon[k] = icon
		btn_kind[k] = int(opts.get("kind", 0))
		btn_glyph[k] = str(opts.get("glyph", ""))
		btn_pips[k] = int(opts.get("pips", -1))
		btn_cost[k] = int(opts.get("cost", -1))
		btn_badge[k] = int(opts.get("badge", 0))
		btn_lock[k] = int(opts.get("lock", 0))
		btn_tint[k] = opts.get("tint", Color(0, 0, 0, 0))
		btn_tint2[k] = opts.get("tint2", Color(0, 0, 0, 0))
		btn_map[k] = int(opts.get("map", -1))
		btn_count += 1
		btn_hit[k] = rect
		hits_dirty = true
		queue_redraw()

	## The hit area of a button: its rectangle, grown (about its centre, kept on the screen) to the 44-point tap size where it is smaller.
	func _slop(r: Rect2) -> Rect2:
		var tap := Style.tap_px()
		var h := r
		if h.size.x < tap:
			h.position.x -= (tap - h.size.x) * 0.5
			h.size.x = tap
		if h.size.y < tap:
			h.position.y -= (tap - h.size.y) * 0.5
			h.size.y = tap
		var vs := _bounds()
		if vs.x > 0.0 and h.size.x <= vs.x:
			h.position.x = clampf(h.position.x, 0.0, vs.x - h.size.x)
		if vs.y > 0.0 and h.size.y <= vs.y:
			h.position.y = clampf(h.position.y, 0.0, vs.y - h.size.y)
		return h

	var hits_dirty := false
	var tips_view := false            # the layer above every screen that draws the tip card and Day 1's dim, ghost finger and Skip (see Hud._tipart)
	var rows_view := false            # the results card's scrolling area of extra rows (see Hud._layout_result_rows): draws only those
	var is_scroll := false           # a list that scrolls (see Hud._scroll_for): its buttons are in the list's own coordinates

	func _bounds() -> Vector2:
		return size if is_scroll else get_viewport_rect().size

	## Work the hit areas out (when the layout is done, before the first tap or the audit): each button's rectangle grown to the 44-point
	## tap size; where two grown areas meet, each gives back its extra at the middle of the gap between the buttons; a button that gave
	## back too much grows again on its free side (up to the next button or the screen's edge).
	func refresh_hits() -> void:
		hits_dirty = false
		var vs := _bounds()
		for k in btn_count:
			btn_hit[k] = btn_rect[k] if btn_kind[k] == 11 else _slop(btn_rect[k])
		for k in btn_count:
			if btn_kind[k] == 11:
				continue
			for j in range(k):
				if btn_kind[j] == 11:
					continue
				_deconflict(k, j)
		var tap := Style.tap_px()
		for k in btn_count:
			if btn_kind[k] == 11:
				continue
			var h := btn_hit[k]
			if h.size.y < tap - 0.5:
				var need := tap - h.size.y
				var down := (vs.y - h.end.y) if vs.y > 0.0 else 0.0
				var up := h.position.y
				for j in btn_count:
					if j == k or btn_kind[j] == 11:
						continue
					var o := btn_hit[j]
					if o.end.x > h.position.x and o.position.x < h.end.x:
						if o.position.y >= h.end.y - 0.5:
							down = minf(down, o.position.y - h.end.y)
						elif o.end.y <= h.position.y + 0.5:
							up = minf(up, h.position.y - o.end.y)
				var dn := clampf(minf(need, down), 0.0, need)
				h.size.y += dn
				need -= dn
				var upd := clampf(minf(need, up), 0.0, need)
				h.position.y -= upd
				h.size.y += upd
			if h.size.x < tap - 0.5:
				var needx := tap - h.size.x
				var right := (vs.x - h.end.x) if vs.x > 0.0 else 0.0
				var left := h.position.x
				for j in btn_count:
					if j == k or btn_kind[j] == 11:
						continue
					var o2 := btn_hit[j]
					if o2.end.y > h.position.y and o2.position.y < h.end.y:
						if o2.position.x >= h.end.x - 0.5:
							right = minf(right, o2.position.x - h.end.x)
						elif o2.end.x <= h.position.x + 0.5:
							left = minf(left, h.position.x - o2.end.x)
				var rt := clampf(minf(needx, right), 0.0, needx)
				h.size.x += rt
				needx -= rt
				var lf := clampf(minf(needx, left), 0.0, needx)
				h.position.x -= lf
				h.size.x += lf
			btn_hit[k] = h

	func _deconflict(k: int, j: int) -> void:
		var a := btn_hit[k]
		var b := btn_hit[j]
		if not a.intersects(b) or btn_rect[k].intersects(btn_rect[j]):
			return
		var o := a.intersection(b)
		if o.size.x < o.size.y:           # side by side
			var left_k := btn_rect[k].get_center().x < btn_rect[j].get_center().x
			var gap_mid := (btn_rect[k].end.x + btn_rect[j].position.x) * 0.5 if left_k else (btn_rect[j].end.x + btn_rect[k].position.x) * 0.5
			if left_k:
				a.end.x = minf(a.end.x, gap_mid)
				b.position.x = maxf(b.position.x, gap_mid)
			else:
				b.end.x = minf(b.end.x, gap_mid)
				a.position.x = maxf(a.position.x, gap_mid)
		else:                              # one above the other
			var above_k := btn_rect[k].get_center().y < btn_rect[j].get_center().y
			var gap_mid_y := (btn_rect[k].end.y + btn_rect[j].position.y) * 0.5 if above_k else (btn_rect[j].end.y + btn_rect[k].position.y) * 0.5
			if above_k:
				a.end.y = minf(a.end.y, gap_mid_y)
				b.position.y = maxf(b.position.y, gap_mid_y)
			else:
				b.end.y = minf(b.end.y, gap_mid_y)
				a.position.y = maxf(a.position.y, gap_mid_y)
		btn_hit[k] = a
		btn_hit[j] = b

	## Index of the button under `pos`, or -1.
	func button_at(pos: Vector2) -> int:
		if hits_dirty:
			refresh_hits()
		for k in range(btn_count - 1, -1, -1):      # (a later button is drawn on top, so it gets the tap)
			if btn_hit[k].has_point(pos):
				return k
		return -1

	## A button squashes while pressed and bounces back. (They do not animate when a screen opens: the whole panel does, as a layer.)
	func _draw_buttons() -> void:
		for k in btn_count:
			if btn_kind[k] == 11:
				continue                 # (an invisible catcher: the sheet's scrim and card)
			var s := 1.0
			if press_k == k:
				s *= lerpf(1.0, 0.94, Style.ease_out_cubic(press_t / Style.T_FAST))
			elif rel_k == k and rel_t < Style.T_BASE:
				s *= lerpf(0.94, 1.0, Style.ease_out_back(rel_t / Style.T_BASE))
			if absf(s - 1.0) > 0.001:
				var c := btn_rect[k].get_center()
				_dst(c * (1.0 - s), 0.0, Vector2(s, s))
			_draw_button(k)
			_dst(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_button(k: int) -> void:
		var r := btn_rect[k]
		var st := btn_state[k]
		var kind := btn_kind[k]
		var ink := C_TEXT if st != 1 else C_QUIET
		var pressed := press_k == k and st != 1
		if pressed and kind != 2 and kind != 8:
			r.position.y += 4.0
		match kind:
			2:      # the primary button: orange, on a 7 px edge it drops onto when pressed; display text with its icon
				var face := Rect2(r.position.x, r.position.y, r.size.x, r.size.y - Style.LIP)
				if st == 1:
					_dsb(_sb_disabled, face)
				else:
					_dsb(_sb_lip, Rect2(face.position.x, face.position.y + Style.LIP, face.size.x, face.size.y))
					if pressed:
						face.position.y += Style.LIP - 2.0
					panel(_sb_primary, face, _sheen_o)
				r = face
				var gw := r.size.y * 0.34 if btn_glyph[k] != "" else 0.0
				var fs := Style.fit_size(btn_text[k], SZ_XL, 40, r.size.x - 90.0 - gw)
				var tw := text_width(btn_text[k], fs)
				var x0 := r.get_center().x - (tw + gw) * 0.5
				if gw > 0.0:
					glyph(btn_glyph[k], Vector2(x0 + gw * 0.3, r.get_center().y), r.size.y * 0.2, Color.WHITE)
				btext(btn_text[k], Vector2(x0 + gw, r.get_center().y + fs * 0.33), fs)
			8:      # a small orange button ("Fly here"): the same look, smaller
				var face2 := Rect2(r.position.x, r.position.y, r.size.x, r.size.y - 6.0)
				_dsb(_sb_lip, Rect2(face2.position.x, face2.position.y + 6.0, face2.size.x, face2.size.y))
				if pressed:
					face2.position.y += 4.0
				panel(_sb_primary, face2, _sheen_o)
				var fs2 := Style.fit_size(btn_text[k], 48, 48, face2.size.x - 40.0)
				btext(btn_text[k], Vector2(face2.position.x, face2.get_center().y + fs2 * 0.33), fs2, HORIZONTAL_ALIGNMENT_CENTER, face2.size.x)
			3:      # a colour tile (ink border, a lip under it) with a small label under it: the pause buttons
				var tint := btn_tint[k]
				if tint.a <= 0.0:
					tint = Style.PRIMARY
				if st == 1:
					tint = tint.darkened(0.5)
				var side := minf(r.size.x - 20.0, r.size.y - 64.0)
				var tile := Rect2(r.get_center().x - side * 0.5, r.position.y + 4.0, side, side)
				_dsb(_sb_tile_lip, Rect2(tile.position + Vector2(0.0, 10.0 if not pressed else 5.0), tile.size))
				_sb_tile.bg_color = tint
				panel(_sb_tile, tile, _sheen_m)
				var tc := tile.get_center()
				glyph(btn_glyph[k], tc, side * 0.27, Color.WHITE)
				text(btn_text[k], Vector2(r.position.x, r.end.y - 8.0), SZ_S, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			7:      # a small round cream icon button with its label under it (the menu's Upgrades / Hangar / Daily)
				var rad := minf(r.size.x, r.size.y - 36.0) * 0.5
				var cc := Vector2(r.get_center().x, r.position.y + rad + 2.0 + (4.0 if pressed else 0.0))
				draw_circle(cc + Vector2(0, 6.0), rad, Style.EDGE)
				draw_circle(cc, rad, Style.SURFACE_DARK)
				draw_circle(cc + Vector2(0, -rad * 0.25), rad * 0.7, Color(1, 1, 1, 0.45))
				glyph(btn_glyph[k], cc, rad * 0.5, Style.TEXT)
				text(btn_text[k], Vector2(r.position.x - 20.0, r.end.y - 14.0), 24, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0)
				var b7 := btn_badge[k]
				var bc7 := cc + Vector2(rad * 0.75, -rad * 0.75)
				if b7 == -2:
					draw_circle(bc7, 18.0, Style.SURFACE_DARK)
					draw_circle(bc7, 12.0, Style.DANGER)
				elif b7 != 0:
					draw_circle(bc7, 22.0, Style.SURFACE_DARK)
					draw_circle(bc7, 18.0, Style.SUCCESS if b7 < 0 else Style.WARNING)
					if b7 < 0:
						glyph("check", bc7, 10.0, Color.WHITE)
					else:
						text(str(b7), bc7 + Vector2(-18.0, 9.0), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 36.0)
			4:      # a small cream chip: glyph + a few words
				if btn_text[k] == "" and btn_glyph[k] != "":      # an icon-only button is a round cream chip
					_dsb(_sb_ghost, r)
					glyph(btn_glyph[k], r.get_center(), r.size.y * 0.3, ink)
					return
				panel(_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal), r, _sheen_s)
				var tw2 := text_width(btn_text[k], SZ_S)
				var total := tw2 + (text_width(btn_sub[k], SZ_S) + 16.0 if btn_sub[k] != "" else 0.0) + (r.size.y * 0.5 + 12.0 if btn_glyph[k] != "" else 0.0)
				var x0 := r.get_center().x - total * 0.5
				if btn_glyph[k] != "":
					glyph(btn_glyph[k], Vector2(x0 + r.size.y * 0.25, r.get_center().y), r.size.y * 0.24, ink)
					x0 += r.size.y * 0.5 + 12.0
				ptext(btn_text[k], Vector2(x0, r.get_center().y + SZ_S * 0.35), SZ_S, ink)
				if btn_sub[k] != "":
					ptext(btn_sub[k], Vector2(x0 + tw2 + 16.0, r.get_center().y + SZ_S * 0.35), SZ_S, C_GOLD_TXT)
			12:     # an improvement chip on the airport detail screen: icon, name, level pips, the next price
				panel(_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal), r, _sheen_s)
				var cx12 := r.get_center().x
				glyph(btn_glyph[k], Vector2(cx12, r.position.y + 36.0), 24.0, ink)
				var nfs12 := 24
				while nfs12 > 11 and text_width(btn_text[k], nfs12) > r.size.x - 10.0:
					nfs12 -= 1
				ptext(btn_text[k], Vector2(r.position.x + 6.0, r.position.y + 90.0), nfs12, ink, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 12.0)
				for q12 in Improvements.MAX_LEVEL:
					var pc12 := Vector2(cx12 + (q12 - 1) * 26.0, r.position.y + 112.0)
					draw_circle(pc12, 10.0, Style.INK)
					draw_circle(pc12, 7.5, C_GOLD if q12 < btn_pips[k] else Color(0.86, 0.78, 0.62))
				if btn_cost[k] > 0:
					var tw12 := text_width(str(btn_cost[k]), SZ_S)
					glyph("coin", Vector2(cx12 - tw12 * 0.5 - 4.0, r.position.y + 146.0), 13.0, Color(1, 1, 1, 1.0 if st != 1 else 0.5))
					ptext(str(btn_cost[k]), Vector2(cx12 - tw12 * 0.5 + 16.0, r.position.y + 156.0), SZ_S, ink)
				else:
					ptext("MAX", Vector2(r.position.x, r.position.y + 156.0), SZ_S, C_GOLD_TXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			10:     # the sheet's buy button: orange, with a fill that runs across it while it is held
				var face10 := Rect2(r.position.x, r.position.y, r.size.x, r.size.y - Style.LIP)
				if st == 1:
					_dsb(_sb_disabled, face10)
				else:
					_dsb(_sb_lip, Rect2(face10.position.x, face10.position.y + Style.LIP, face10.size.x, face10.size.y))
					if pressed:
						face10.position.y += Style.LIP - 2.0
					panel(_sb_primary, face10, _sheen_o)
					if pv_hold > 0.01:
						_sb_hold.set_corner_radius_all(Style.R_L)
						_dsb(_sb_hold, Rect2(face10.position.x, face10.position.y, maxf(face10.size.x * pv_hold, float(Style.R_L) * 2.0), face10.size.y))
				var fs10 := Style.fit_size(btn_text[k], SZ_XL, 40, face10.size.x - 90.0)
				var ink10 := Color.WHITE if st != 1 else C_QUIET
				if st != 1:
					btext(btn_text[k], Vector2(face10.position.x, face10.get_center().y + fs10 * 0.33), fs10, HORIZONTAL_ALIGNMENT_CENTER, face10.size.x)
				else:
					_ds(Style.display(), Vector2(face10.position.x, face10.get_center().y + fs10 * 0.33), btn_text[k], HORIZONTAL_ALIGNMENT_CENTER, face10.size.x, fs10, ink10)
			9:      # the airport under the title: name and stars on a cream chip, a tap opens the Airports screen
				panel(_sb_normal, r, _sheen_s)
				ptext(btn_text[k], Vector2(r.position.x + 32.0, r.get_center().y + 12.0), 34, ink)
				for i in 3:
					glyph("star" if i < btn_stars[k] else "star_off", Vector2(r.end.x - 128.0 + i * 44.0, r.get_center().y), 16.0)
			6:      # a quiet pill (the rewarded ads): it stays out of the way of the one big button
				_dsb(_sb_ghost, r)
				var lw := text_width(btn_text[k], Style.SZ_BUTTON)
				var sw := text_width(btn_sub[k], Style.SZ_BODY) if btn_sub[k] != "" else 0.0
				var lx := r.get_center().x - (lw + sw + (20.0 if sw > 0.0 else 0.0) + 64.0) * 0.5
				glyph(btn_glyph[k], Vector2(lx + 22.0, r.get_center().y), 20.0, ink)
				ptext(btn_text[k], Vector2(lx + 64.0, r.get_center().y + Style.SZ_BUTTON * 0.35), Style.SZ_BUTTON, ink)
				if sw > 0.0:
					ptext(btn_sub[k], Vector2(lx + 64.0 + lw + 20.0, r.get_center().y + Style.SZ_BODY * 0.35), Style.SZ_BODY, C_GOLD_TXT)
			1:      # a card
				var sb := _sb_gold if (st == 2 and btn_cost[k] == 0) else (_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal))
				if btn_map[k] >= 0:
					_draw_airport_card(k, r, st)
					return
				panel(sb, r)
				var left := r.position.x + 36.0
				var cy := r.get_center().y
				var iconed := btn_icon[k] >= 0 or btn_glyph[k] != ""
				if btn_icon[k] >= 0:
					_draw_icon(btn_icon[k], Vector2(left + 44.0, cy), minf(r.size.y * 0.3, 46.0))
				elif btn_glyph[k] != "":
					var tcol := btn_tint[k] if btn_tint[k].a > 0.0 else Style.PRIMARY
					if st == 1:
						tcol = tcol.darkened(0.45)
					var ts := Rect2(left - 2.0, cy - 48.0, 96.0, 96.0)
					_dsb(_sb_tile_lip, Rect2(ts.position + Vector2(0, 6.0), ts.size))
					_sb_tile.bg_color = tcol
					_dsb(_sb_tile, ts)
					glyph(btn_glyph[k], ts.get_center(), 26.0, Color.WHITE)
				var tx := left + (110.0 if iconed else 0.0)
				var right_w := 220.0 if (btn_cost[k] >= 0 or btn_pips[k] >= 0) else (190.0 if btn_stars[k] >= 0 or btn_lock[k] > 0 else 60.0)
				var tw3 := r.end.x - tx - right_w - 30.0
				var nfs := SZ_M if text_width(btn_text[k], SZ_M) < tw3 else 42
				ptext(btn_text[k], Vector2(tx, cy + (-4.0 if btn_sub[k] != "" else nfs * 0.34)), nfs, ink, HORIZONTAL_ALIGNMENT_LEFT, tw3)
				if btn_sub[k] != "":
					_ds(Style.body(), Vector2(tx, cy + 40.0), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, tw3, SZ_S, C_SOFT if st != 1 else C_QUIET)
				var rx := r.end.x - 36.0
				if btn_stars[k] >= 0 and btn_lock[k] <= 0:
					for i in 3:
						glyph("star" if i < btn_stars[k] else "star_off", Vector2(rx - 120.0 + i * 60.0, cy), 24.0)
				if btn_lock[k] > 0:
					glyph("lock", Vector2(rx - 250.0, cy), 26.0, C_SOFT)
					ptext("Level %d" % btn_lock[k], Vector2(rx - 214.0, cy + 11.0), SZ_S, C_GOLD_TXT, HORIZONTAL_ALIGNMENT_LEFT, 140.0)
					glyph("star", Vector2(rx - 38.0, cy), 20.0)
				if btn_pips[k] >= 0:
					for i in Upgrades.MAX_LEVEL:
						var pc := Vector2(rx - 146.0 + i * 30.0, cy - 36.0)
						draw_circle(pc, 12.0, Style.INK)
						draw_circle(pc, 9.5, C_GOLD if i < btn_pips[k] else Color(0.86, 0.78, 0.62))
				if btn_cost[k] > 0:
					var cc2 := Vector2(rx - 190.0, cy + 26.0)
					glyph("coin", cc2, 16.0, Color(1, 1, 1, 1.0 if st != 1 else 0.5))
					ptext(str(btn_cost[k]), cc2 + Vector2(26.0, 11.0), SZ_S, C_TEXT if st != 1 else C_QUIET)
				elif btn_cost[k] == 0:
					ptext("MAX", Vector2(rx - 190.0, cy + 38.0), SZ_S, C_GOLD_TXT)
			13:     # a daily goal on the goals sheet: a tier dot, the goal, its progress, its reward (done: a green card with a check)
				panel(_sb_gold if st == 2 else _sb_normal, r)
				var cy13 := r.get_center().y
				var tc13: Color = [Style.SUCCESS, Style.WARNING, Style.DANGER][clampi(btn_pips[k], 0, 2)]
				draw_circle(Vector2(r.position.x + 62.0, cy13), 34.0, Style.INK)
				draw_circle(Vector2(r.position.x + 62.0, cy13), 29.0, tc13)
				if st == 2:
					glyph("check", Vector2(r.position.x + 62.0, cy13), 17.0, Color.WHITE)
				var tw13 := r.size.x - 120.0 - 250.0
				var nl13 := Hud.wrap_lines(btn_text[k], Style.SZ_BUTTON, tw13)
				var sl13 := Hud.wrap_lines(btn_sub[k], Style.SZ_BODY, tw13)
				var ty13 := r.position.y + 26.0 + 44.0
				if nl13 > 1:
					_dms(Style.font_for(btn_text[k], Style.SZ_BUTTON), Vector2(r.position.x + 120.0, ty13), btn_text[k], HORIZONTAL_ALIGNMENT_LEFT, tw13, Style.SZ_BUTTON, nl13, ink, "button")
				else:
					ptext(btn_text[k], Vector2(r.position.x + 120.0, ty13), Style.SZ_BUTTON, ink, HORIZONTAL_ALIGNMENT_LEFT, tw13)
				var sy13 := ty13 + float(nl13 - 1) * 54.0 + 48.0
				if sl13 > 1:
					_dms(Style.body(), Vector2(r.position.x + 120.0, sy13), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, tw13, Style.SZ_BODY, sl13, C_SOFT)
				else:
					_ds(Style.body(), Vector2(r.position.x + 120.0, sy13), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, tw13, Style.SZ_BODY, C_SOFT)
				glyph("coin", Vector2(r.end.x - 218.0, cy13), 18.0)
				ptext("+%d" % btn_cost[k], Vector2(r.end.x - 188.0, cy13 + 12.0), SZ_M, C_GOLD_TXT if st != 2 else ink, HORIZONTAL_ALIGNMENT_LEFT, 160.0)
			16:     # a compact cosmetic card (two to a row): a picture or swatch, the name, and one line (the price, or where a locked item comes from)
				var locked16 := btn_lock[k] > 0 and st == 1
				panel(_sb_gold if st == 2 else (_sb_disabled if st == 1 else _sb_normal), r)
				var pc := Vector2(r.position.x + 62.0, r.get_center().y)
				if btn_icon[k] >= 0:
					_draw_icon(btn_icon[k], pc, 40.0)
				else:
					draw_circle(pc, 43.0, Style.INK)
					draw_circle(pc, 39.0, btn_tint2[k])
					draw_circle(pc + Vector2(0, -8.0), 25.0, btn_tint[k])
				var tw16 := r.size.x - 120.0 - 24.0
				var nfs16 := Style.SZ_BUTTON
				var two := Style.font_for(btn_text[k], nfs16).get_string_size(btn_text[k], HORIZONTAL_ALIGNMENT_LEFT, -1, nfs16).x > tw16
				if two:
					_dms(Style.font_for(btn_text[k], nfs16), Vector2(r.position.x + 120.0, r.position.y + 52.0), btn_text[k], HORIZONTAL_ALIGNMENT_LEFT, tw16, nfs16, 2, ink, "button")
				else:
					ptext(btn_text[k], Vector2(r.position.x + 120.0, r.position.y + 54.0), nfs16, ink, HORIZONTAL_ALIGNMENT_LEFT, tw16)
				var sy16 := r.position.y + (150.0 if two else 106.0)
				if locked16:       # where it comes from, on up to two lines
					glyph("lock", Vector2(r.position.x + 134.0, sy16 - 12.0), 13.0, C_SOFT)
					_dms(Style.body(), Vector2(r.position.x + 160.0, sy16), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, tw16 - 40.0, Style.SZ_BODY, 2, C_SOFT)
				else:
					_ds(Style.body(), Vector2(r.position.x + 120.0, sy16), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, tw16, Style.SZ_BODY, C_SOFT if st != 1 else C_QUIET)
			14:     # the menu's goals card: "Daily goals", the streak, and three dots for the three goals
				panel(_sb_normal, r, _sheen_s)
				glyph("sun", Vector2(r.position.x + 52.0, r.get_center().y), 26.0, ink)
				ptext(btn_text[k], Vector2(r.position.x + 98.0, r.get_center().y - 12.0), Style.SZ_BUTTON, ink, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 290.0)
				_ds(Style.body(), Vector2(r.position.x + 98.0, r.get_center().y + 40.0), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 290.0, SZ_S, C_SOFT)
				for i in 3:
					var dc := Vector2(r.end.x - 130.0 + i * 44.0, r.get_center().y)
					draw_circle(dc, 17.0, Style.INK)
					draw_circle(dc, 13.5, Style.SUCCESS if i < btn_stars[k] else Color(0.86, 0.78, 0.62))
					if i < btn_stars[k]:
						glyph("check", dc, 8.0, Color.WHITE)
				if btn_badge[k] == -2:
					var bc14 := Vector2(r.end.x - 6.0, r.position.y + 6.0)
					draw_circle(bc14, 18.0, Style.SURFACE_DARK)
					draw_circle(bc14, 12.0, Style.DANGER)
			15:     # the streak card: seven day dots (the 7th a gift), where the player is in the week, the freezes
				panel(_sb_normal, r)
				ptext(btn_text[k], Vector2(r.position.x + 36.0, r.position.y + 54.0), SZ_M, ink, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 72.0)
				_ds(Style.body(), Vector2(r.position.x + 36.0, r.position.y + 92.0), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 72.0, SZ_S, C_SOFT)
				var step := (r.size.x - 120.0) / 6.0
				for i in 7:
					var dc2 := Vector2(r.position.x + 60.0 + i * step, r.end.y - 52.0)
					draw_circle(dc2, 25.0, Style.INK)
					draw_circle(dc2, 21.0, C_GOLD if i < btn_pips[k] else Color(0.86, 0.78, 0.62))
					if i == 6:
						glyph("star" if i < btn_pips[k] else "star_off", dc2, 14.0)
					elif i < btn_pips[k]:
						glyph("check", dc2, 10.0, Color.WHITE)
			_:
				panel(_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal), r)
				var gw4 := r.size.y * 0.5 if btn_glyph[k] != "" else 0.0
				var fs4 := Style.fit_size(btn_text[k], SZ_M, 48, r.size.x - 50.0 - gw4)
				var tw4 := text_width(btn_text[k], fs4)
				var sx := r.get_center().x - (tw4 + gw4) * 0.5
				if btn_glyph[k] != "":
					glyph(btn_glyph[k], Vector2(sx + gw4 * 0.4, r.get_center().y), r.size.y * 0.24, ink)
				ptext(btn_text[k], Vector2(sx + gw4, r.get_center().y + fs4 * 0.34), fs4, ink)

	## The airport detail screen's card, in the lower third (the live airport is above it): the name in the display face, the best shift, the
	## three stars with what each needs, and for a locked airport the unlock requirement in place of the Fly here button.
	## A thin progress bar (mastery): a dark track, a fill (gold at the top rank) and a pip for each rank.
	func _mastery_bar(r: Rect2, frac: float, rank: int) -> void:
		draw_rect(r, Style.INK)
		var inner := r.grow(-2.0)
		draw_rect(inner, Color(0.86, 0.78, 0.62))
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(frac, 0.0, 1.0), inner.size.y)), C_GOLD if rank >= Mastery.MAX_RANK else Style.PRIMARY)

	## An airport's card on the Airports screen: a top-down vignette, the name in the display face, the best shift and three stars; the selected
	## card wears an orange ring (its "Fly here" button is its own button); a locked airport is dimmed under a dark "Unlock with N stars" pill.
	func _draw_airport_card(k: int, r: Rect2, st: int) -> void:
		var locked := btn_lock[k] > 0
		var sel := st == 2
		var sb := _sb_accent if sel else (_sb_disabled if locked else _sb_normal)
		panel(sb, r)
		var cy := r.get_center().y
		var vig := Rect2(r.position.x + 24.0, r.position.y + 22.0, r.size.y - 44.0, r.size.y - 44.0)
		_vignette(vig, btn_map[k], locked)
		var tx := vig.end.x + 28.0
		var avail := r.end.x - tx - (300.0 if sel else 40.0)
		var nfs := Style.fit_size(btn_text[k], 48, 48, avail)
		ptext(btn_text[k], Vector2(tx, r.position.y + 70.0), nfs, C_TEXT if not locked else C_QUIET, HORIZONTAL_ALIGNMENT_LEFT, avail)
		_ds(Style.body(), Vector2(tx, r.position.y + 122.0), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, avail, 26, C_SOFT if not locked else C_QUIET)
		if not locked:
			for i in 3:
				glyph("star" if i < btn_stars[k] else "star_off", Vector2(tx + 24.0 + i * 50.0, r.end.y - 52.0), 21.0)
			if btn_cost[k] > 0:
				_ds(Style.text(), Vector2(tx + 156.0, r.end.y - 40.0), "Best %d" % btn_cost[k], HORIZONTAL_ALIGNMENT_LEFT, 232.0, 26, C_SOFT, "caption")
			if btn_pips[k] >= 0:         # the mastery rank and how far to the next
				var mr := Rect2(r.end.x - 360.0, r.end.y - 58.0, 320.0, 16.0)
				_ds(Style.text(), Vector2(mr.position.x, mr.position.y - 12.0), "Rank %d \u00b7 %s" % [btn_pips[k], Mastery.rank_name(btn_pips[k])], HORIZONTAL_ALIGNMENT_LEFT, 320.0, 24, C_GOLD_TXT if btn_pips[k] >= Mastery.MAX_RANK else C_SOFT, "caption")
				_mastery_bar(mr, float(btn_badge[k]) / 100.0, btn_pips[k])
		else:
			var pill := Rect2(tx, r.end.y - 88.0, r.end.x - tx - 40.0, 64.0)         # (what unlocks it: under the name, where the stars are on an open card)
			_dsb(_sb_lockpill, pill)
			glyph("lock", Vector2(pill.position.x + 36.0, pill.get_center().y), 17.0, Color.WHITE)
			_ds(Style.text(), Vector2(pill.position.x + 68.0, pill.get_center().y + 9.0), "Level %d at %s" % [btn_lock[k], Airports.airport_name(maxi(btn_map[k] - 1, 0))], HORIZONTAL_ALIGNMENT_LEFT, pill.size.x - 68.0 - 64.0, 26, Color.WHITE)
			glyph("star", Vector2(pill.end.x - 36.0, pill.get_center().y), 18.0)

	# ---------- the HUD of a shift ----------

	## Two bars in a rounded square.
	func _draw_pause_button() -> void:
		var r := pause_rect
		_dsb(_sb_ghost, r)
		glyph("pause", r.get_center() + Vector2(0, -2), r.size.x * 0.28, Style.TEXT)

	func _draw_sliders() -> void:
		for i in 3:
			var r := slider_rect[i]
			var ty := r.get_center().y
			glyph(slider_glyph[i], Vector2(r.position.x - 70.0, ty), 34.0, C_TEXT)
			ptext(slider_name[i], Vector2(r.position.x, ty - 52.0), 26, C_SOFT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, "caption")         # (above the track's tap area, not on it)
			var track := Rect2(r.position.x, ty - 11.0, r.size.x, 22.0)
			_dsb(_sb_slider, track)
			var fx := maxf(r.size.x * slider_val[i], 22.0)
			_dsb(_sb_primary_flat(), Rect2(r.position.x, ty - 11.0, fx, 22.0))
			var kc := Vector2(r.position.x + r.size.x * slider_val[i], ty)
			draw_circle(kc + Style.SHADOW_OFFSET * 0.6, 30.0, Style.SHADOW_COLOR)
			draw_circle(kc, 30.0, Style.EDGE)
			draw_circle(kc, 25.0, Style.SURFACE_LIGHT)

	func _sb_primary_flat() -> StyleBoxFlat:
		return _sb_fill

	## The star bar: a rounded dark track with a gold fill, and a star at each threshold (gold when reached, cream until then).
	func _draw_star_bar() -> void:
		var w := minf(size.x - 380.0, 560.0)
		var x0 := size.x * 0.5 - w * 0.5
		var y := 224.0 + top
		var top := float(maxi(thresholds[2], 1)) * 1.04
		_dsb(_sb_track, Rect2(x0 - 6.0, y - 5.0, w + 12.0, 24.0))
		var f := clampf(bar_shown / top, 0.0, 1.0)
		if f > 0.0:
			_dsb(_sb_fill, Rect2(x0 - 2.0, y - 1.0, maxf(w * f + 4.0, 16.0), 16.0))
		for i in 3:
			var x := x0 + w * (0.07 if i == 0 else float(thresholds[i]) / top)     # (star 1 counts landings, so it sits near the start)
			var lit := star_on[i] != 0
			var c := Vector2(x, y + 7.0)
			var k := star_t[i] / 0.6 if star_t[i] >= 0.0 else 1.0
			if k < 1.0:
				var s := Style.ease_out_back(minf(k * 1.4, 1.0))
				_dst(c * (1.0 - s), 0.0, Vector2(s, s))
				glyph("star", c, 24.0)
				_dst(Vector2.ZERO, 0.0, Vector2.ONE)
				_sparks(c, k, 22.0, 60.0, 8, Style.ACCENT)
			else:
				glyph("star" if lit else "star_off", c, 24.0 if lit else 20.0)
			if i == 0 and not lit and thresholds[0] > 0:        # the landings still to go for the first star
				ptext("%d/%d" % [landed, thresholds[0]], Vector2(x - 80.0, y + 66.0), 31, C_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 160.0, "caption")

	## The wind card (top-right): a cream card with an arrow showing where the air is going and its direction number.
	func _draw_wind() -> void:
		var card := Rect2(size.x - 24.0 - right - 132.0, 20.0 + top, 132.0, 150.0)
		var flash := (wind_warn and int(Time.get_ticks_msec() / 250.0) % 2 == 0) or (wind_pulse >= 0.0 and sin(wind_pulse * PI) > 0.5)
		_dsb(_sb_flat_accent if flash else _sb_pill, card)
		var c := card.get_center() + Vector2(0, -22.0)
		var d := Vector2(sin(deg_to_rad(wind_shown)), -cos(deg_to_rad(wind_shown)))
		var n := Vector2(-d.y, d.x)
		var pop := 1.0 + (0.45 * sin(clampf(wind_pulse, 0.0, 1.0) * PI) if wind_pulse >= 0.0 else 0.0)
		draw_line(c - d * 28.0 * pop, c + d * 8.0 * pop, Style.TEXT, 9.0)
		tri(c + d * 36.0 * pop, c + d * 6.0 * pop + n * 18.0 * pop, c + d * 6.0 * pop - n * 18.0 * pop, Style.TEXT)
		ptext(wind_text, Vector2(card.position.x, card.end.y - 22.0), 28, C_GOLD_TXT if wind_warn else C_SOFT, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)

	## A status pill under the star bar: a glyph and a few characters.
	func _pill(c: Vector2, g: String, s: String, size_px: int, col: Color) -> void:
		var tw := text_width(s, size_px)
		var h := float(size_px) * 1.35
		var w := tw + h * 1.3
		_dsb(_sb_pill, Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h))
		glyph(g, Vector2(c.x - w * 0.5 + h * 0.62, c.y), h * 0.32, col if col != C_TEXT else Style.TEXT)
		ptext(s, Vector2(c.x - w * 0.5 + h * 1.12, c.y + size_px * 0.34), size_px, col if col != C_GOLD else C_GOLD_TXT)

	## A ring and a few short rays thrown outwards from `c` as `k` goes 0 -> 1.
	func _sparks(c: Vector2, k: float, r0: float, r1: float, rays: int, col: Color) -> void:
		var a := 1.0 - k
		draw_arc(c, lerpf(r0, r1, Style.ease_out_cubic(k)), 0.0, TAU, 28, Color(col.r, col.g, col.b, a * 0.9), 4.0)
		for j in rays:
			var d := Vector2(cos(j * TAU / rays + 0.3), sin(j * TAU / rays + 0.3))
			draw_line(c + d * lerpf(r0, r1, Style.ease_out_cubic(k)) * 0.9, c + d * lerpf(r0 * 1.3, r1 * 1.5, Style.ease_out_cubic(k)), Color(col.r, col.g, col.b, a), 5.0)

	func _draw_hud() -> void:
		_dsb(_sb_plate, Rect2(size.x * 0.5 - 215.0, 4.0 + top, 430.0, 206.0))       # the timer and coins sit on one soft pill
		_draw_pause_button()
		if mode_glyph != "":
			glyph(mode_glyph, Vector2(50.0 + left, 146.0 + top), 26.0, C_SOFT)       # (under the pause button, which has the safe area's top)
		_draw_star_bar()
		_draw_fines_counter()
		var y := 460.0 + top                 # (under the banner, which has 312 to 440 to itself)
		if chip_finale != "":
			_pill(Vector2(size.x * 0.5, y), "plane", chip_finale, SZ_M, C_RED if chip_finale_red else C_TEXT)
			y += 86.0
		if chip_weather != "":
			_pill(Vector2(size.x * 0.5, y), chip_weather_glyph, chip_weather, SZ_S, C_GOLD)
		if show_wind:
			_draw_wind()
		if coin_icon.x > 0.0:
			glyph("coin", coin_icon, 34.0)

	## The fines counter by the HUD (under the pause button, left of the star bar): a ticket and the fines so far. A fine is a quiet marker, never coins taken off the total.
	func fines_rect() -> Rect2:
		return Rect2(14.0 + left, 196.0 + top, 232.0, 92.0)

	func _draw_fines_counter() -> void:
		if tickets_shown <= 0 and fines_shown <= 0:
			return
		var r := fines_rect()
		var pop := 1.0 + (0.18 * sin(clampf(tk_punch, 0.0, 1.0) * PI) if tk_punch >= 0.0 else 0.0)
		if pop != 1.0:
			_dst(r.get_center() * (1.0 - pop), 0.0, Vector2(pop, pop))
		_dsb(_sb_plate, r)
		glyph("ticket", Vector2(r.position.x + 40.0, r.get_center().y), 22.0, Color(0.93, 0.78, 0.45))
		var tw := r.size.x - 84.0
		var tcap := "\u00d7%d" % tickets_shown            # (two short lines: the count, and what the fines come to; never more than five characters)
		var famt := "-%d" % fines_shown if fines_shown < 1000 else ("-%.1fk" % (float(fines_shown) / 1000.0) if fines_shown < 10000 else "-%dk" % mini(roundi(float(fines_shown) / 1000.0), 999))
		ptext(tcap, Vector2(r.position.x + 74.0, r.position.y + 38.0), Style.SZ_CAPTION, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, tw, "caption")
		ptext(famt, Vector2(r.position.x + 74.0, r.position.y + 76.0), Style.SZ_CAPTION, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, tw, "caption")
		if pop != 1.0:
			_dst(Vector2.ZERO, 0.0, Vector2.ONE)

	## The single banner and the tip: a pill with a glyph and one line (drawn here so the text sits on top of its pill).
	func _draw_pills() -> void:
		if not show_play or show_pause:
			return
		if banner_alpha > 0.01 and banner_text != "":
			var r := banner_rect
			_sb_banner.bg_color.a = banner_alpha
			_sb_banner.border_color = Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha)
			_dsb(_sb_banner, r)
			var x := r.position.x + 40.0
			if banner_glyph != "":
				glyph(banner_glyph, Vector2(x + 30.0, r.get_center().y), 30.0, Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha))
				x += 84.0
			var bfs := Style.fit_size(banner_text, SZ_M, Style.SZ_BODY, r.end.x - x - 40.0)
			var bcol := Color(Style.TEXT.r, Style.TEXT.g, Style.TEXT.b, banner_alpha)
			if banner_lines > 1:
				_dms(Style.font_for(banner_text, bfs), Vector2(x, r.position.y + 22.0 + float(bfs)), banner_text, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - x - 40.0, bfs, 2, bcol)
			else:
				ptext(banner_text, Vector2(x, r.get_center().y + bfs * 0.34), bfs, bcol)
	## The tip card (and Day 1's layer under it) is drawn by a layer of its own above every screen (Hud._tipart), so a tip can show anywhere.
	func _draw_tip_layer() -> void:
		_draw_tutorial_layer()
		if tip_alpha > 0.01 and tip_text != "":
			if tip_focus.x < 1.0e8:        # (a pulsing ring on the thing the tip is about)
				var pk := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
				draw_arc(tip_focus, tip_focus_r + 10.0 * pk, 0.0, TAU, 40, Color(Style.INK, 0.35 * tip_alpha), 11.0)
				draw_arc(tip_focus, tip_focus_r + 10.0 * pk, 0.0, TAU, 40, Color(C_GOLD, tip_alpha), 7.0)
			var r2 := tip_rect
			_sb_tip.bg_color.a = tip_alpha
			_sb_tip.border_color = Color(Style.SUCCESS, tip_alpha)
			_dsb(_sb_tip, r2)
			var x2 := r2.position.x + 40.0
			if tip_glyph != "":
				glyph(tip_glyph, Vector2(x2 + 28.0, r2.get_center().y), 28.0, Color(Style.TEXT, tip_alpha))
				x2 += 84.0
			if tip_lines > 1:
				_dms(Style.body(), Vector2(x2, r2.position.y + 24.0 + float(SZ_S)), tip_text, HORIZONTAL_ALIGNMENT_LEFT, r2.end.x - x2 - 28.0, SZ_S, 3, Color(Style.TEXT, tip_alpha))
			else:
				_ds(Style.body(), Vector2(x2, r2.get_center().y + SZ_S * 0.35), tip_text, HORIZONTAL_ALIGNMENT_LEFT, r2.end.x - x2 - 20.0, SZ_S, Color(Style.TEXT, tip_alpha))


	## Day 1: the dimmed game, the ghost finger drawing its path, and the Skip button.
	func _draw_tutorial_layer() -> void:
		if tut_dim > 0.01:
			draw_rect(Rect2(Vector2.ZERO, size), Color(Style.INK, 0.42 * tut_dim))
		if ghost_t >= 0.0 and ghost_pts.size() >= 2:
			var n := ghost_pts.size() - 1
			var f := clampf(ghost_t, 0.0, 1.0) * float(n)
			var seg := mini(int(f), n - 1)
			var pt := ghost_pts[seg].lerp(ghost_pts[seg + 1], f - float(seg))
			for k in range(1, seg + 1):
				draw_line(ghost_pts[k - 1], ghost_pts[k], Color(1.0, 0.96, 0.85, 0.85), 12.0)
			draw_line(ghost_pts[seg], pt, Color(1.0, 0.96, 0.85, 0.85), 12.0)
			draw_circle(pt + Vector2(5, 7), 40.0, Color(Style.INK, 0.28))
			draw_circle(pt, 38.0, Color(1.0, 1.0, 1.0, 0.92))
			draw_circle(pt, 30.0, Color(0.95, 0.8, 0.45, 0.95))
		if skip_rect.size.x > 0.0:
			_dsb(_sb_pill, skip_rect)
			ptext("Skip", Vector2(skip_rect.position.x, skip_rect.get_center().y + 14.0), SZ_S, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, skip_rect.size.x)

	# ---------- the results ----------

	func _ease_out_back(t: float) -> float:
		var c1 := 1.70158
		var c3 := c1 + 1.0
		return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

	func _draw_details() -> void:
		panel(_sb_sheet, details_rect, _sheen_l)
		for i in details_lines.size():
			var y := details_rect.position.y + 58.0 + i * 46.0
			var parts := details_lines[i].split("|")
			var last := i == details_lines.size() - 1
			_ds(Style.text(), Vector2(details_rect.position.x + 40.0, y), parts[0], HORIZONTAL_ALIGNMENT_LEFT, details_rect.size.x - 80.0, SZ_S, C_TEXT if last else C_SOFT)
			if parts.size() > 1:
				_ds(Style.text(), Vector2(details_rect.position.x + 40.0, y), parts[1], HORIZONTAL_ALIGNMENT_RIGHT, details_rect.size.x - 80.0, SZ_S, C_GOLD_TXT if last else C_TEXT)

	const RES_LIFT := 100.0               # the results screen sits this much higher than the 1080 x 1920 design, so a few rows fit in the card

	## What the shift earned besides the pay: goals, the streak day, the bonus chest, achievements, ranks: one row each, all alike (icon, text, +coins).
	## They are drawn on their own Art inside a scrolling area (Hud._layout_result_rows): row i is at ROW_TOP + i * ROW_STEP, in that area's coordinates.
	const ROW_TOP := 8.0
	const ROW_STEP := 112.0
	const ROW_H := 104.0

	static func row_rect(i: int, w: float) -> Rect2:
		return Rect2(w * 0.5 - 465.0, ROW_TOP + float(i) * ROW_STEP, 930.0, ROW_H)

	func _draw_rows_only() -> void:
		for i in res_rows.size():
			var rw: Dictionary = res_rows[i]
			var gr: Rect2 = Art.row_rect(i, size.x)
			_dsb(_sb_unlock, gr)
			glyph(str(rw["glyph"]), Vector2(gr.position.x + 52.0, gr.get_center().y), 22.0 if rw["glyph"] != "check" else 16.0, Style.SUCCESS_DARK if rw["glyph"] == "check" else Color.WHITE)
			var coins := int(rw["coins"])
			var gw := gr.size.x - 110.0 - (330.0 if coins > 0 else 40.0)
			var gtxt: String = str(rw.get("fit", rw["text"]))
			var gl: int = int(rw.get("lines", 1))
			if gl > 1:
				_dms(Style.text(), Vector2(gr.position.x + 96.0, gr.get_center().y - 10.0), gtxt, HORIZONTAL_ALIGNMENT_LEFT, gw, Style.SZ_BODY, 2, C_TEXT)
			else:
				ptext(gtxt, Vector2(gr.position.x + 96.0, gr.get_center().y + 14.0), Style.SZ_BODY, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, gw)
			if coins > 0:
				ptext("+%d" % coins, Vector2(gr.end.x - 330.0, gr.get_center().y + 14.0), Style.SZ_BODY, C_GOLD_TXT, HORIZONTAL_ALIGNMENT_RIGHT, 270.0)
				glyph("coin", Vector2(gr.end.x - 40.0, gr.get_center().y), 14.0)

	## The total shown on the results card at results time `t`: the earnings count up, then (with fines) it counts down to what was paid.
	func tally_at(t: float) -> int:
		var t_count := STAR_T0 + STAR_GAP * 3.0
		var f1 := Style.ease_out_cubic(clampf((t - t_count) / RES_UP, 0.0, 1.0))
		if res_fines_eff <= 0:
			return roundi(float(res_total) * f1)
		var shown := roundi(float(res_gross) * f1)
		var t_fine := t_count + RES_FINE_AT
		if t >= t_fine:
			var fk := clampf((t - t_fine) / RES_FINE_LEN, 0.0, 1.0)
			shown = roundi(lerpf(float(res_gross), float(res_total), fk * fk * (3.0 - 2.0 * fk)))
		return shown

	func _draw_results() -> void:
		var cx := size.x * 0.5
		if details_open:
			_draw_details()
			return
		var s2 := size.y / 1920.0                 # (positions below are for a 1080 x 1920 screen)
		# The title (over the field, cream on a warm extrusion) and where we were.
		var stat := res_layer != 2
		var dyn := res_layer != 1
		if stat:
			var tfs := Style.fit_size("SHIFT COMPLETE", 104, 50, 1000.0)
			Style.draw_ext(self, Vector2(cx - 520.0, 290.0 * s2 + top - RES_LIFT), "SHIFT COMPLETE", tfs, HORIZONTAL_ALIGNMENT_CENTER, 1040.0)
		if dyn and res_sub != "":
			if res_sub_two:       # (long: two lines)
				_dms(Style.text(), Vector2(cx - 520.0, 338.0 * s2 + top - RES_LIFT), res_sub, HORIZONTAL_ALIGNMENT_CENTER, 1040.0, SZ_S, 2, C_CREAM)
			else:
				text(res_sub, Vector2(cx - 520.0, 350.0 * s2 + top - RES_LIFT), SZ_S, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 1040.0)
		# The stars, one after another: each slams down from big with an impact ring, rays and a little shake. Three, big and tilted.
		for i in 3:
			var t0 := STAR_T0 + STAR_GAP * i
			var rot := (i - 1) * deg_to_rad(12.0)
			var rad := 150.0 if i == 1 else 118.0
			var c := Vector2(cx + (i - 1) * 285.0, (520.0 if i == 1 else 580.0) * s2 + top - RES_LIFT)
			if stat:
				star(c, rad, Color(Style.WORLD_TEXT), true, rot)
			if dyn and i < res_stars and res_t >= t0:
				var k := clampf((res_t - t0) / SLAM, 0.0, 1.0)
				var imp := res_t - t0 - SLAM
				var jit := Vector2.ZERO
				if imp >= 0.0 and imp < 0.22:
					jit = Vector2(sin(imp * 160.0), cos(imp * 190.0)) * 9.0 * (1.0 - imp / 0.22)
				star(c + jit, rad * lerpf(2.6, 1.0, Style.ease_out_cubic(k)), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.35 + 0.65 * k), true, rot)
				if imp >= 0.0 and imp < 0.5:
					_sparks(c, imp / 0.5, rad, rad * 3.0, 10, C_GOLD)
		# The card: NEW BEST, the total paid (rolling up once the stars are in), and three chips; under them what this shift also earned.
		var stk := res_stack()
		var card: Rect2 = stk["card"]
		if stat:
			panel(_sb_card, card, _sheen_l)
			var cw0 := (card.size.x - 90.0 - 36.0) / 3.0
			for j in 3:
				var cr0 := Rect2(card.position.x + 45.0 + j * (cw0 + 18.0), card.position.y + 270.0 * s2, cw0, 150.0)
				_dsb(_sb_chip, cr0)
				_ds(Style.text(), Vector2(cr0.position.x, cr0.position.y + 126.0), ["Landings", "Early clear", "Fines"][j], HORIZONTAL_ALIGNMENT_CENTER, cr0.size.x, SZ_S, C_SOFT, "caption")
		if not dyn:
			return
		var t_count := STAR_T0 + STAR_GAP * 3.0
		# The tally, in beats: the earnings count up, then (if there were fines) a ticket is stamped and the total counts down to what was really paid,
		# then the final total settles with a little pop.
		var t_fine := t_count + RES_FINE_AT
		var has_fines := res_fines_eff > 0
		var shown := tally_at(res_t)
		var settle_k := clampf((res_t - (t_fine + RES_FINE_LEN if has_fines else t_count + RES_UP)) / 0.3, 0.0, 1.0)
		var label := "+%d" % shown
		var bfs := Style.fit_size(label, 150, 80, 560.0)
		var tw := text_width(label, bfs)
		var ty := card.position.y + 215.0 * s2
		var pop := 1.0 + 0.08 * sin(settle_k * PI) if res_t > t_count + RES_UP else 1.0
		if pop != 1.0:
			_dst(Vector2(cx, ty - 40.0) * (1.0 - pop), 0.0, Vector2(pop, pop))
		glyph("coin", Vector2(cx - tw * 0.5 - 76.0, ty - 62.0), 54.0)
		Style.draw_ext(self, Vector2(cx - tw * 0.5, ty), label, bfs, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Style.ACCENT if not res_doubled else Style.SUCCESS.lightened(0.2), 5)
		if pop != 1.0:
			_dst(Vector2.ZERO, 0.0, Vector2.ONE)
		if res_doubled:
			ptext("x2", Vector2(cx + tw * 0.5 + 24.0, ty), SZ_M, Style.SUCCESS_DARK)
		var k2 := clampf((res_t - (t_count + 1.0)) / 0.4, 0.0, 1.0)
		if res_new_best:       # a red tag stuck on the card's top edge
			var tagr := Rect2(-140.0, -34.0, 280.0, 68.0)
			_dst(Vector2(cx, card.position.y), deg_to_rad(-3.0), Vector2(k2, k2))
			_dsb(_sb_tag, tagr)
			_ds(Style.text(), Vector2(-140.0, 14.0), "NEW BEST", HORIZONTAL_ALIGNMENT_CENTER, 280.0, 36, Color.WHITE)
			_dst(Vector2.ZERO, 0.0, Vector2.ONE)
		elif res_best > 0:
			ptext("best %d" % res_best, Vector2(cx - 300.0, card.position.y + 60.0), SZ_S, Color(C_QUIET.r, C_QUIET.g, C_QUIET.b, k2), HORIZONTAL_ALIGNMENT_CENTER, 600.0, "caption")
		var cw := (card.size.x - 90.0 - 36.0) / 3.0
		for j in 3:
			var cr := Rect2(card.position.x + 45.0 + j * (cw + 18.0), card.position.y + 270.0 * s2, cw, 150.0)
			var v := res_chips[j]
			var colr := C_TEXT if j == 0 else (Style.SUCCESS_DARK if j == 1 else Color("b8322a"))
			var sign := "+" if v >= 0 and j < 2 else ("" if j < 2 else "\u2212")
			var ctxt := "%s%s" % [sign, fmt_int(absi(v))]
			if j == 2 and has_fines and res_t < t_fine:
				continue                  # (the fines chip waits for its own beat)
			if j == 2 and has_fines:       # the ticket is stamped on the chip: it slams down from big and a ring flashes
				var sk := clampf((res_t - t_fine) / 0.22, 0.0, 1.0)
				var sc := lerpf(2.2, 1.0, Style.ease_out_cubic(sk))
				_dst(cr.get_center() * (1.0 - sc), 0.0, Vector2(sc, sc))
				glyph("ticket", Vector2(cr.end.x - 40.0, cr.position.y + 34.0), 22.0, Color(0.93, 0.78, 0.45, sk))
				_dst(Vector2.ZERO, 0.0, Vector2.ONE)
				if res_t - t_fine < 0.5:
					_sparks(Vector2(cr.end.x - 40.0, cr.position.y + 34.0), (res_t - t_fine) / 0.5, 22.0, 70.0, 8, Color(0.93, 0.78, 0.45))
			var cfs := Style.fit_size(ctxt, 54, 42, cr.size.x - 16.0)
			_ds(Style.display(), Vector2(cr.position.x, cr.position.y + 80.0), ctxt, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, cfs, colr)
		if stk.has("pill"):        # the fines took the net under the floor: the floor pays instead
			var pr: Rect2 = stk["pill"]
			_dsb(_sb_chip, pr)
			var cap_txt := "Fines capped. You still earned %s" % fmt_int(res_total)         # (the floor pays: the fines took the net down to it and no further)
			ptext(cap_txt, Vector2(pr.position.x, pr.get_center().y + 12.0), Style.fit_size(cap_txt, SZ_M, SZ_S, pr.size.x - 40.0), Style.SUCCESS_DARK, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
		# The nearest goal, always: "120 XP to level 5", "40 coins to Runway lights 3", or "Ready to buy!", over a bar that fills as the coins land
		if stk.has("goal"):
			var gl: Rect2 = stk["goal"]
			_dsb(_sb_unlock, gl)
			var gg: Dictionary = res_goal
			glyph(str(gg["glyph"]), Vector2(gl.position.x + 52.0, gl.position.y + 40.0), 22.0)
			var tail := str(gg["tail"])
			var gtw := text_width(tail, Style.SZ_BODY) + 8.0
			ptext(str(gg["text"]), Vector2(gl.position.x + 96.0, gl.position.y + 54.0), Style.SZ_BODY, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, gl.size.x - 100.0 - gtw - 40.0)
			ptext(tail, Vector2(gl.end.x - 28.0 - gtw, gl.position.y + 54.0), Style.SZ_BODY, C_GOLD_TXT if bool(gg["ready"]) else C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, gtw)
			var bar := Rect2(gl.position.x + 28.0, gl.end.y - 34.0, gl.size.x - 56.0, 18.0)
			var k := Style.ease_out_cubic(clampf((res_t - 1.4) / 0.9, 0.0, 1.0))
			var fr := lerpf(float(gg["frac0"]), float(gg["frac1"]), k)
			draw_rect(bar, Style.INK)
			draw_rect(bar.grow(-2.0), Color(0.86, 0.78, 0.62))
			draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4.0) * clampf(fr, 0.0, 1.0), bar.size.y - 4.0)), C_GOLD if bool(gg["ready"]) and k >= 1.0 else Style.PRIMARY)
		# A new airport opened with this shift.
		if stk.has("unlock"):
			var ur: Rect2 = stk["unlock"]
			_dsb(_sb_unlock, ur)
			_minimap(Vector2(ur.position.x + 90.0, ur.get_center().y), 50.0, Airports.index_of(res_unlock))
			ptext("%s unlocked!" % res_unlock, Vector2(ur.position.x + 170.0, ur.get_center().y - 8.0), 46, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, ur.size.x - 200.0)
			_ds(Style.body(), Vector2(ur.position.x + 170.0, ur.get_center().y + 46.0), Airports.tag(Airports.index_of(res_unlock)), HORIZONTAL_ALIGNMENT_LEFT, ur.size.x - 200.0, SZ_S, C_SOFT)

	## The results card laid out from the top down, so nothing sits on anything else: the card, then (what there is of it, in this order of
	## importance, as much as the room above the Next shift button allows) the new-airport row, the first goal, the pay-protected pill, the
	## second goal and the extra lines; the Details chip comes last. Everything is a rectangle here, not a position.
	## The Next shift button: above the ad pills (each as tall as a tap and as wide as the button, one under the other).
	func res_again() -> Rect2:
		var ph := maxf(100.0, Style.tap_px())
		var block := float(res_pills) * ph + float(maxi(res_pills - 1, 0)) * 14.0
		var bottom := size.y - Style.safe_bottom - 36.0 - (block + 24.0 if res_pills > 0 else 40.0)
		return Rect2(size.x * 0.5 - 450.0, bottom - 250.0, 900.0, 250.0)

	func res_stack() -> Dictionary:
		var s2 := size.y / 1920.0
		var cx := size.x * 0.5
		var tap := Style.tap_px()
		var out := {}
		var ctop := 700.0 * s2 + top - RES_LIFT
		var y := ctop + 270.0 * s2 + 150.0 + 16.0
		var limit := res_again().position.y - 20.0                # (the Next shift button's top, and a gap)
		var det_h := maxf(80.0, tap)
		var avail := limit - y - det_h - 12.0
		# in this order of importance, as much as the room allows: the new-airport row, the pay-protected pill, then the rows; what does not fit
		# is folded into the last row that fits ("3 more  +120")
		var yy := y
		var used := 0.0
		if not res_goal.is_empty() and used + 120.0 <= avail:
			out["goal"] = Rect2(cx - 465.0, yy, 930.0, 112.0)
			yy += 120.0
			used += 120.0
		if res_unlock != "" and used + 168.0 <= avail:
			out["unlock"] = Rect2(cx - 465.0, yy, 930.0, 160.0)
			yy += 168.0
			used += 168.0
		if res_protected > 0 and used + 108.0 <= avail:
			out["pill"] = Rect2(cx - 465.0 + 45.0, yy, 930.0 - 90.0, 100.0)
			yy += 108.0
			used += 108.0
		var n := res_rows.size()
		var want := ROW_TOP + float(n) * ROW_STEP if n > 0 else 0.0
		var room := maxf(avail - used, 0.0)
		var area_h := minf(want, room)             # (more rows than fit scroll inside the card)
		if area_h < 60.0:
			area_h = 0.0
		out["rows_area"] = Rect2(cx - 465.0, yy, 930.0, area_h)
		out["rows_total"] = want
		yy += area_h
		var details := Rect2(cx - 150.0, yy + 6.0, 300.0, det_h)
		out["details"] = details
		out["card"] = Rect2(cx - 465.0, ctop, 930.0, details.end.y + 18.0 - ctop)
		return out

	# ---------- The shop's preview sheet ----------

	static func fmt_int(n: int) -> String:
		var t := str(absi(n))
		var out := ""
		while t.length() > 3:
			out = "," + t.substr(t.length() - 3) + out
			t = t.substr(0, t.length() - 3)
		return ("-" if n < 0 else "") + t + out

	## The sheet: a scrim over the shop, a card with the item's name, its picture, the price and the balance before and after.
	func _draw_preview_base() -> void:
		var card: Rect2 = pv["card"]
		draw_rect(Rect2(Vector2.ZERO, size), Color(Style.INK, 0.58))
		panel(_sb_sheet, card, _sheen_l)
		ptext(pv["name"], Vector2(card.position.x, card.position.y + 150.0), SZ_M, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
		text_plain(pv["sub"], Vector2(card.position.x, card.position.y + 196.0), SZ_S, C_SOFT, card.size.x)
		var st: Rect2 = pv["stage"]
		var ok_pop := 1.0
		if pv_ok_t >= 0.0 and pv_ok_t < 0.35:
			ok_pop = 1.0 + 0.06 * sin(pv_ok_t / 0.35 * PI)
		if ok_pop != 1.0:
			_dst(st.get_center() * (1.0 - ok_pop), 0.0, Vector2(ok_pop, ok_pop))
		if pv["kind"] == "livery":
			_draw_livery_stage(st)
		elif pv["kind"] == "windsock" or pv["kind"] == "hangar" or pv["kind"] == "prop":
			_draw_detail_stage(st)
		else:
			_draw_theme_stage(st)
		_dst(Vector2.ZERO, 0.0, Vector2.ONE)
		# price and balance
		var y: float = pv["info_y"]
		var cx := card.get_center().x
		match pv["state"]:
			"buy", "need":
				var ps := fmt_int(pv["price"])
				var tw := text_width(ps, SZ_M)
				glyph("coin", Vector2(cx - tw * 0.5 - 44.0, y + 4.0), 30.0)
				ptext(ps, Vector2(cx - tw * 0.5, y + 24.0), SZ_M, C_TEXT)
				var line := "%s \u2192 %s" % [fmt_int(pv["balance"]), fmt_int(pv["balance"] - pv["price"])] if pv["state"] == "buy" else "Balance %s" % fmt_int(pv["balance"])
				ptext(line, Vector2(card.position.x, y + 84.0), 40, C_SOFT if pv["state"] == "buy" else C_RED, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
			"bought":
				ptext("Balance %s" % fmt_int(pv["balance"]), Vector2(card.position.x, y + 64.0), 40, C_SOFT, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
			"locked":
				glyph("lock", Vector2(cx, y + 10.0), 26.0, C_SOFT)
				_dms(Style.font_for(str(pv["source"]), 42), Vector2(card.position.x + 30.0, y + 76.0), str(pv["source"]), HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 60.0, 42, 2, C_TEXT)
			_:
				ptext("In use" if pv["state"] == "equipped" else "Yours", Vector2(card.position.x, y + 40.0), SZ_M, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)

	func text_plain(s: String, pos: Vector2, size_px: int, col: Color, width: float) -> void:
		_ds(Style.font_for(s, size_px), pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, size_px, col)

	## What bursts over the sheet when the purchase goes through: a ring, rays, a check.
	func _draw_preview_top() -> void:
		if pv_ok_t < 0.0 or pv_ok_t > 1.4:
			return
		var st: Rect2 = pv["stage"]
		var c := st.get_center()
		var k := clampf(pv_ok_t / 0.7, 0.0, 1.0)
		_sparks(c, k, 60.0, 360.0, 14, C_GOLD)
		var a := clampf(1.0 - (pv_ok_t - 0.7) / 0.7, 0.0, 1.0)
		var s := Style.ease_out_back(clampf(pv_ok_t / 0.3, 0.0, 1.0))
		draw_circle(c, 110.0 * s, Color(Style.SUCCESS, 0.92 * a))
		glyph("check", c, 62.0 * s, Color(1, 1, 1, a))

	## A windsock on its pole, or the hangar, in the item's colours.
	func _draw_detail_stage(st: Rect2) -> void:
		_sb_stage.bg_color = Color("a6cf74")
		_dsb(_sb_stage, st)
		var d: Dictionary = pv["detail"]
		var c := st.get_center()
		if pv["kind"] == "windsock":
			var pole := Rect2(c.x - 220.0, c.y - 220.0, 16.0, 420.0)
			draw_rect(pole, Color(0.8, 0.8, 0.82))
			var sway := sin(pv_t * 1.6) * 14.0
			for n in 3:
				var x0 := c.x - 204.0 + n * 150.0
				var h0 := 150.0 - n * 36.0
				var col: Color = d["a"] if n % 2 == 0 else d["b"]
				draw_colored_polygon(PackedVector2Array([Vector2(x0, c.y - 210.0 + n * 10.0 + sway * n * 0.1), Vector2(x0 + 150.0, c.y - 190.0 + n * 18.0 + sway * (n + 1) * 0.2), Vector2(x0 + 150.0, c.y - 190.0 + n * 18.0 + h0 * 0.9 - n * 10.0 + sway * (n + 1) * 0.2), Vector2(x0, c.y - 210.0 + n * 10.0 + h0 + sway * n * 0.1)]), col)
		else:
			var wall := Rect2(c.x - 280.0, c.y - 40.0, 560.0, 240.0)
			draw_rect(wall, Color("e8e1d2"))
			draw_rect(Rect2(wall.position.x - 20.0, wall.position.y - 70.0, wall.size.x + 40.0, 80.0), d["color"] if d["color"] != null else Color("e2654a"))
			draw_rect(Rect2(c.x - 120.0, c.y + 20.0, 240.0, 180.0), Color("3a2c2a"))

	func _draw_livery_stage(st: Rect2) -> void:
		_sb_stage.bg_color = Color("a6cf74")
		_dsb(_sb_stage, st)       # (a soft field green, like the menu's)
		var d: Dictionary = pv["livery"]
		var body: Color = d["body"] if d["body"] != null else Color.WHITE
		var stripe = d["stripe"]
		var rw: Color = pv["runway"]
		# the big one: slowly turning on the spot, rocking into a bank
		var yaw := sin(pv_t * 0.5) * 0.9 + 0.5
		var bank := sin(pv_t * 0.9) * 0.45
		_draw_plane(st.get_center() + Vector2(0.0, -30.0), 3.4, yaw, bank, body, stripe, rw)
		# the small one, as it flies in the shift: on a strip of its runway's colour, nose, wingtips and fin in that colour
		var w := 250.0
		var box := Rect2(st.end.x - w - 18.0, st.end.y - w - 18.0, w, w)
		_sb_stage.bg_color = Color(Style.SURFACE_DARK, 0.96)
		_dsb(_sb_stage, box)
		draw_rect(Rect2(box.get_center().x - 26.0, box.position.y + 14.0, 52.0, box.size.y - 66.0), Color(0.42, 0.44, 0.48))
		draw_rect(Rect2(box.get_center().x - 3.0, box.position.y + 26.0, 6.0, box.size.y - 90.0), Color(rw, 0.9))
		_draw_plane(box.get_center() + Vector2(0.0, -14.0), 0.9, 0.0, 0.0, body, stripe, rw)
		text_plain("In the game", Vector2(box.position.x, box.end.y - 14.0), 24, C_SOFT, box.size.x)

	## A plane seen from above, nose up: fuselage and stripe in the livery, nose cone, wingtips and fin in the runway's colour.
	## `yaw` turns it, `bank` squeezes the wings as if it rolled.
	func _draw_plane(c: Vector2, s: float, yaw: float, bank: float, body: Color, stripe, rw: Color) -> void:
		var bx := cos(bank)
		_dst(c, yaw, Vector2(s * bx, s))
		var wing := Color(0.94, 0.94, 0.92)
		for sx in [-1.0, 1.0]:
			quad(Vector2(sx * 8.0, -12.0), Vector2(sx * 62.0, 2.0), Vector2(sx * 62.0, 14.0), Vector2(sx * 8.0, 10.0), wing)
			quad(Vector2(sx * 50.0, -1.5), Vector2(sx * 62.0, 2.0), Vector2(sx * 62.0, 14.0), Vector2(sx * 50.0, 12.0), rw)
			quad(Vector2(sx * 8.0, 40.0), Vector2(sx * 26.0, 47.0), Vector2(sx * 26.0, 53.0), Vector2(sx * 8.0, 50.0), wing)
		draw_line(Vector2(0, -42.0), Vector2(0, 46.0), body, 20.0)
		draw_circle(Vector2(0, -42.0), 10.0, body)
		draw_circle(Vector2(0, 46.0), 10.0, body)
		if stripe != null:
			draw_line(Vector2(0, -30.0), Vector2(0, 36.0), stripe, 6.0)
		draw_circle(Vector2(0, -47.0), 7.0, rw)
		draw_rect(Rect2(-3.0, 34.0, 6.0, 22.0), rw)
		_dst(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_theme_stage(st: Rect2) -> void:
		var big: bool = pv["mode"] == 1
		var main_theme: int = pv["theme"] if big else pv["current_theme"]
		var other_theme: int = pv["current_theme"] if big else pv["theme"]
		_sb_stage.bg_color = Color(Style.SURFACE_DARK_2)
		_dsb(_sb_stage, st)
		var side := st.size.y - 24.0
		_vignette(Rect2(st.get_center().x - side * 0.5, st.position.y + 12.0, side, side), pv["airport"], false, main_theme)
		var w := 230.0
		var box := Rect2(st.end.x - w - 16.0, st.end.y - w - 16.0, w, w)
		_vignette(box, pv["airport"], false, other_theme)
		text_plain("Current" if big else "New", Vector2(box.position.x, box.position.y + 34.0), 28, Color.WHITE, box.size.x)

	## The menu's title, top-left over the live field: PATTERN over WORK in the display face, cream on a stacked warm extrusion, at a
	## 2 degree tilt, with a small tag above it and the selected airport under it. (A soft scrim at the top keeps it readable.)
	func _draw_lockup() -> void:
		var s2 := size.y / 1920.0
		_gp[0] = Vector2(0, 0)
		_gp[1] = Vector2(size.x, 0)
		_gp[2] = Vector2(size.x, size.y * 0.4)
		_gp[3] = Vector2(0, size.y * 0.4)
		_gc[0] = Color(Style.INK, 0.4)
		_gc[1] = _gc[0]
		_gc[2] = Color(Style.INK, 0.0)
		_gc[3] = _gc[2]
		draw_polygon(_gp, _gc)
		var x0 := 56.0 + left
		var y0 := 250.0 * s2 + top
		var muted := Color(Style.WORLD_TEXT, 0.7)         # (plain small print: nothing here can be tapped, so nothing is a shape)
		tracked("AIR TRAFFIC CONTROL", Vector2(x0 + 4.0, y0 - 6.0), 24, muted, 5.0)
		_dst(Vector2(x0, y0), deg_to_rad(2.0), Vector2.ONE)
		Style.draw_ext(self, Vector2(0.0, 150.0), "PATTERN", 150, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Style.WORLD_TEXT, 7)
		Style.draw_ext(self, Vector2(0.0, 300.0), "WORK", 150, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Style.WORLD_TEXT, 7)
		_dst(Vector2.ZERO, 0.0, Vector2.ONE)
		tracked("CLEAR PROP GAMES", Vector2(x0 + 4.0, y0 + 376.0), 24, muted, 5.0)

	## The intro: the studio mark (a propeller that spins up and settles) and wordmark pop in and out, then the game's
	## name lands with a little plane across it.
	func _draw_logo() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5 - 60.0
		var t := logo_t
		if t < 1.0:
			var k := Style.ease_out_back(t / 0.45)
			var a := clampf(minf(t / 0.2, (1.0 - t) / 0.2), 0.0, 1.0)
			_dst(Vector2(cx, cy) * (1.0 - k), 0.0, Vector2(k, k))
			Style.draw_mark(self, Vector2(cx, cy - 40.0), 110.0, (1.0 - Style.ease_out_cubic(t / 0.9)) * TAU * 2.0, a)
			Style.draw_wordmark(self, cx, cy + 150.0, SZ_M, a)
			_dst(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		var u := t - 1.0
		var a2 := clampf(1.0 - (t - 2.4) / 0.3, 0.0, 1.0)
		for w in 2:
			var word: String = ["PATTERN", "WORK"][w]
			var k2 := Style.ease_out_back((u - 0.12 * w) / 0.45)
			if k2 <= 0.01:
				continue
			var c := Vector2(cx, cy - 40.0 + w * 150.0)
			_dst(c * (1.0 - k2), 0.0, Vector2(k2, k2))
			Style.draw_ext(self, Vector2(cx - 500.0, c.y), word, 120, HORIZONTAL_ALIGNMENT_CENTER, 1000.0, Style.WORLD_TEXT if w == 0 else Style.ACCENT, 6, a2)
			_dst(Vector2.ZERO, 0.0, Vector2.ONE)
		var f := clampf((u - 0.5) / 1.0, 0.0, 1.0)
		if f > 0.0:
			var pc := Vector2(lerpf(-80.0, size.x + 80.0, Style.ease_out_cubic(f)), cy - 190.0 - 70.0 * sin(PI * f))
			draw_line(Vector2(maxf(pc.x - 260.0, 0.0), pc.y + 6.0), Vector2(pc.x - 40.0, pc.y + 6.0), Color(1, 1, 1, 0.45 * a2), 8.0)
			glyph("plane", pc, 46.0, Color(Style.ACCENT, a2))
			pc.y += 0.0

	func _draw_confetti() -> void:
		for i in CONFETTI:
			if cf_on[i] == 0:
				continue
			_dst(cf_pos[i], cf_rot[i], Vector2.ONE)
			draw_rect(Rect2(-cf_size[i] * 0.5, cf_size[i]), cf_col[i])
		_dst(Vector2.ZERO, 0.0, Vector2.ONE)

	## The new-airport reveal: a dimmed screen, a card that pops in, a padlock that springs open with a burst.
	func _draw_unlock() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5 - 120.0
		var a := clampf(unlock_t / 0.25, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(Style.SCRIM, 0.78 * a))
		var k := Style.ease_out_back(unlock_t / 0.45)
		_dst(Vector2(cx, cy) * (1.0 - k), 0.0, Vector2(k, k))
		var card := Rect2(cx - 430.0, cy - 340.0, 860.0, 680.0)
		panel(_sb_sheet, card, _sheen_l)
		_ds(Style.text(), Vector2(cx - 400.0, cy - 40.0), "NEW AIRPORT", HORIZONTAL_ALIGNMENT_CENTER, 800.0, SZ_S, C_GOLD_TXT)
		var ufs := Style.fit_size(unlock_name, SZ_XL, 40, 780.0)
		ptext(unlock_name, Vector2(cx - 420.0, cy + 90.0), ufs, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 840.0)
		_ds(Style.body(), Vector2(cx - 400.0, cy + 170.0), "ready for flights", HORIZONTAL_ALIGNMENT_CENTER, 800.0, SZ_S, Style.TEXT_SOFT)
		# The padlock: the shackle pops up and swings open at 0.55 s.
		var lc := Vector2(cx, cy - 190.0)
		var open := Style.ease_out_back(clampf((unlock_t - 0.55) / 0.35, 0.0, 1.0))
		var gold := Style.ACCENT
		draw_arc(lc + Vector2(-36.0 * open, -44.0 - 30.0 * open), 52.0, PI, TAU - 1.0 * open, 20, Color(Style.INK, 1.0), 30.0)
		draw_arc(lc + Vector2(-36.0 * open, -44.0 - 30.0 * open), 52.0, PI, TAU - 1.0 * open, 20, Color(0.85, 0.88, 0.95), 18.0)
		draw_rect(Rect2(lc.x - 78.0, lc.y - 44.0, 156.0, 124.0), Color(Style.INK, 1.0))
		draw_rect(Rect2(lc.x - 70.0, lc.y - 36.0, 140.0, 108.0), gold)
		draw_circle(lc + Vector2(0, 14.0), 14.0, Color(Style.ACCENT_DARK, 1.0))
		_dst(Vector2.ZERO, 0.0, Vector2.ONE)
		var sp := (unlock_t - 0.55) / 0.7
		if sp >= 0.0 and sp < 1.0:
			_sparks(lc + Vector2(0, -60.0), sp, 60.0, 280.0, 12, Style.ACCENT)

	func _span(what: String, since: int) -> int:
		var n := Time.get_ticks_usec()
		if n - since > 2000:
			Boot.add("interface art[%s]: " % name + what.strip_edges(), float(n - since) / 1000.0)
		return n

	func _draw() -> void:
		var t_start := Time.get_ticks_usec()
		if rec_on:                    # (the audit keeps the latest draw only: an animated screen draws every frame)
			rec_texts.clear()
			rec_glyphs.clear()
			rec_boxes.clear()
			rec_xf = Transform2D.IDENTITY
		_draw_all()
		last_draw_us = Time.get_ticks_usec() - t_start
		Boot.add("interface art redraw", float(last_draw_us) / 1000.0)

	func _draw_all() -> void:
		if rows_view:
			_draw_rows_only()
			return
		if tips_view:
			_draw_tip_layer()
			return
		if icon_id != "":              # (a layout element of a Control-built sheet that is just one picture: see DetailSheet.Icon)
			var ir := minf(size.x, size.y) * 0.5
			glyph(icon_id, size * 0.5, maxf(ir - 4.0, 4.0), icon_col)
			return
		if logo_t >= 0.0:
			_draw_logo()
			return
		var t0 := Time.get_ticks_usec()
		if lockup:
			_draw_lockup()
		if header_text != "":
			var hw := text_width(header_text, 46)
			var pr := Rect2(size.x - 36.0 - right - hw - 118.0, 20.0 + top, hw + 118.0, 84.0)
			_dsb(_sb_hdr, pr)
			glyph(header_glyph, Vector2(pr.position.x + 50.0, pr.get_center().y), 25.0)
			ptext(header_text, Vector2(pr.position.x + 92.0, pr.get_center().y + 16.0), 46, C_TEXT)
		if header2_text != "":
			var hw2 := text_width(header2_text, 46)
			var pr2 := Rect2(36.0 + left, 20.0 + top, hw2 + 118.0, 84.0)
			_dsb(_sb_hdr, pr2)
			glyph(header2_glyph, Vector2(pr2.position.x + 50.0, pr2.get_center().y), 25.0)
			ptext(header2_text, Vector2(pr2.position.x + 92.0, pr2.get_center().y + 16.0), 46, C_TEXT)
		t0 = _span("  lockup and header", t0)
		if (show_pause or warm) and pause_card.size.x > 0.0:
			panel(_sb_sheet, pause_card, _sheen_l)
		t0 = _span("  pause card", t0)
		if show_result:
			_draw_results()
		t0 = _span("  results card", t0)
		if unlock_t >= 0.0:
			_draw_unlock()
		if pv_on:
			_draw_preview_base()
		_draw_buttons()
		if pv_on:
			_draw_preview_top()
		t0 = _span("  buttons", t0)
		if show_play and not show_pause:
			_draw_hud()
		t0 = _span("  shift interface", t0)
		if (show_pause or warm) and slider_rect[0].size.x > 0.0:       # (only the pause layer has sliders; the shift's layer just steps aside)
			_draw_sliders()
		t0 = _span("  sliders", t0)
		_draw_pills()
		_draw_confetti()
		for i in fc_s.size():
			if fc_s[i] > 0.01:
				glyph("coin", fc_pos[i], 26.0 * fc_s[i])
		for i in tk_s.size():
			if tk_s[i] > 0.01:
				glyph("ticket", tk_pos[i], 30.0 * tk_s[i], Color(0.93, 0.78, 0.45))
		t0 = _span("  pills and confetti", t0)

var _art: Art                      # the one every screen draws with right now (the main one, or one of the three pre-built panels)
var _main_art: Art
var _tipart: Art                   # the tip card / Day 1 layer above every screen
var _panel_arts := {}              # "select" | "upgrades" | "shop" -> the Art that holds that panel, laid out in advance
var _panel_sig := {}               # ...and the data it was laid out with
var priming := false               # Main is laying a panel out in advance (hidden): no transition, no screen change
var _score: Label                    # the coin total (rolls up)
var _best: Label                     # the shift clock
var _wind_banner: Label              # the one banner (wind shifts, last arrivals, weather starting...)
var _event_banner: Label             # the weather chip's text
var _finale: Label                   # the "aircraft left" chip's number (kept for the tests: see finale_text())
var _tip: Label
var _tip_until := 0
var _menu: Control
var _pause: Control
var _menu_title: Label
var _select: Control
var _select_title: Label
var _ad: Control
var _ad_title: Label
var _ad_sub: Label
var _ad_bar: ColorRect
var _over: Control
var _over_head: Label
var _over_body: Label                # the breakdown behind "Details"
var _flash: ColorRect
var _splash: Control

## The in-game loading cover: the studio mark, a progress-style bar and nothing else (no text).
class SplashDraw extends Control:
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		Style.draw_mark(self, Vector2(cx, cy - 80.0), 110.0, t * 3.0)
		Style.draw_wordmark(self, cx, cy + 110.0, Style.SZ_M)
		var w := 420.0
		var r := Rect2(cx - w * 0.5, cy + 200.0, w, 20.0)
		draw_rect(r, Color(Style.INK, 0.8))
		var f := fposmod(t * 0.9, 1.4) / 1.4
		var x0 := r.position.x + (w + 140.0) * f - 140.0
		var x1 := minf(x0 + 140.0, r.end.x)
		x0 = maxf(x0, r.position.x)
		if x1 > x0:
			draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Style.ACCENT)
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
var _event_text := ""
var _finale_text := ""
var _finale_flash := false
var _coin_target := 0
var _coin_shown := 0.0
var _secs_left := 99999        # (negative = overtime, see set_overtime)
var _banner_q: Array = []      # waiting banners: [text, colour, glyph, seconds]
var _banner_left := 0.0
var _banner_total := 1.0
var _tip_q: Array = []
var _play_labels_on := false
var _wind_secs := -1
var _wind_inited := false
var _wind_posted := false
var _last_bal := 0
var mastery_ranks: Array = []        # per airport: mastery rank (the Airports screen's cards show it)
var mastery_pcts: Array = []         # ...and the progress to the next rank, 0..100
var ach_unseen := false              # the menu's Awards button wears a red dot while there are achievements not looked at yet
var goals_done := 0                  # the menu's goals card: goals finished today, the streak line, and a red dot while none is done
var goals_line := ""
var goal_note: Array = []            # the goals the shift just finished (the results card lists them)
var goal_strip: Dictionary = {}       # ...and the nearest goal (the results card's bar): {"text", "glyph", "frac0", "frac1", "tail", "ready"}
var goal_rows: Array = []             # ...and the other rows of the card (the streak day, the bonus chest, achievements, ranks): {"glyph", "text", "coins"}
var bad_streak := 0
var bad_done := false
var ramp_note := ""             # the results card says where the landed aircraft ended up ("Hangar full · 4 on the ramp")
var mode := ""                 # "", "daily" or "bad": a small badge on the HUD

func _ready() -> void:
	layer = 2
	Boot.mark("overlay built")
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0.1, 0.1, 0.0)
	add_child(_flash)
	_logo_bg = ColorRect.new()
	_logo_bg.color = Style.SCRIM
	_logo_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_bg.visible = false
	add_child(_logo_bg)
	_art = Art.new()
	_main_art = _art
	_art.name = "main"
	add_child(_art)
	_tipart = Art.new()
	_tipart.tips_view = true
	_tipart.name = "tips"
	_tipart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tipart)
	_score = _label(SZ_XL, HORIZONTAL_ALIGNMENT_CENTER)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.offset_left = -300
	_score.offset_right = 300
	_score.offset_top = 56
	_score.pivot_offset = Vector2(300, 80)
	_best = _label(SZ_M, HORIZONTAL_ALIGNMENT_CENTER)
	_best.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_best.offset_left = -300
	_best.offset_right = 300
	_best.offset_top = 6
	_wind_banner = _label(SZ_M, HORIZONTAL_ALIGNMENT_CENTER)
	_wind_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wind_banner.offset_left = -440
	_wind_banner.offset_right = 440
	_wind_banner.offset_top = 312
	_wind_banner.visible = false
	_wind_banner.modulate.a = 0.0         # (the banner is drawn by the art, on its pill; the label holds the text)
	_finale = _label(SZ_M, HORIZONTAL_ALIGNMENT_CENTER)
	_finale.visible = false
	_finale.modulate.a = 0.0          # (the chip is drawn by the art; this label only holds the text)
	_event_banner = _label(SZ_S, HORIZONTAL_ALIGNMENT_CENTER)
	_event_banner.visible = false
	_event_banner.modulate.a = 0.0
	_tip = _label(SZ_S, HORIZONTAL_ALIGNMENT_LEFT)
	_tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.offset_left = -400
	_tip.offset_right = 440
	_tip.offset_top = -270
	_tip.offset_bottom = -190
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip.visible = false
	_tip.modulate.a = 0.0                 # (the tip is drawn by the art, on its pill)
	for i in POPUP_POOL:
		var l := _label(SZ_M, HORIZONTAL_ALIGNMENT_CENTER)
		l.size = Vector2(560, 100)
		l.pivot_offset = Vector2(280, 50)
		l.visible = false
		_pop_labels.append(l)
	_pop_born.resize(POPUP_POOL)
	_cf_vel.resize(Art.CONFETTI)
	_cf_spin.resize(Art.CONFETTI)
	_fc_on.resize(FLY_POOL)
	_fc_on.fill(false)
	_fc_from.resize(FLY_POOL)
	_fc_t.resize(FLY_POOL)
	_pop_from.resize(POPUP_POOL)
	_build_pause()
	_build_menu()
	_build_over()
	_build_select()
	_build_ad()
	move_child(_art, _select.get_index() + 1)   # the art (buttons, stars, pills) is drawn above the screen shades
	move_child(_score, _art.get_index() + 1)    # (the coin total and the clock sit on top of their pills)
	move_child(_best, _art.get_index() + 2)
	_tr_nodes = [_art, _menu, _select, _over, _pause, _ad, _score, _best]
	_build_stamp()
	_set_play_labels(false)
	set_landed(0)
	Style.detect_safe(get_viewport().get_visible_rect().size)
	apply_safe()
	Boot.mark("hud built")

# ---------- Header numbers (they roll) ----------

var _star_lit: Array[bool] = [false, false, false]
var _slam_next := 0
var _confetti_done := false
var _cf_vel := PackedVector2Array()
var _cf_spin := PackedFloat32Array()
var _cf_rng := RandomNumberGenerator.new()
var _unlock_pending := ""
const UNLOCK_AT := 4.4        # results seconds: after the stars and the total (earnings, fines, final) have landed
var _hdr_shown := PackedFloat32Array([0.0, 0.0])
var _hdr_target := PackedFloat32Array([0.0, 0.0])
var _hdr_delay := PackedFloat32Array([0.0, 0.0])
var _hdr_on: Array[bool] = [false, false]

## The corner totals (slot 0 right: coins or stars; slot 1 left: coins on the menu). A total that changes on the same
## screen rolls to its new value; `from` starts it somewhere else (the results: the bank before this shift), after `delay`.
func _set_header(slot: int, glyph: String, value: int, from: int = -1, delay: float = 0.0) -> void:
	if slot == 0:
		_art.header_glyph = glyph
	else:
		_art.header2_glyph = glyph
	if from >= 0:
		_hdr_shown[slot] = float(from)
	elif not _hdr_on[slot]:
		_hdr_shown[slot] = float(value)
	_hdr_target[slot] = float(value)
	_hdr_delay[slot] = delay
	_hdr_on[slot] = true
	_apply_headers()

## The screen title of the list screens: left-aligned after the Back button and fitted to the room before the total in the corner (the total
## grows with the digits: 9,999,999 coins is wider than 0), so the two can never meet.
func _fit_select_title(total: int) -> void:
	var vp := get_viewport().get_visible_rect().size
	var pw := _main_art.text_width(str(total), 46) + 118.0
	var x0 := 110.0 + Style.safe_left
	var x1 := vp.x - Style.safe_right - 36.0 - pw - 16.0
	_select_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_select_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_select_title.offset_left = x0
	_select_title.offset_right = maxf(x1, x0 + 120.0)
	_select_title.offset_top = 40.0 + Style.safe_top
	_select_title.offset_bottom = _select_title.offset_top + 90.0
	_select_title.add_theme_font_size_override("font_size", Style.fit_size(_select_title.text, SZ_M, 42, maxf(x1 - x0, 120.0)))

func _apply_headers() -> void:
	var t0 := str(roundi(_hdr_shown[0]))
	var t1 := str(roundi(_hdr_shown[1]))
	if _hdr_on[0] and t0 != _art.header_text:
		_art.header_text = t0
		_art.queue_redraw()
	if _hdr_on[1] and t1 != _art.header2_text:
		_art.header2_text = t1
		_art.queue_redraw()

func _roll_headers(delta: float) -> void:
	for i in 2:
		if not _hdr_on[i] or _hdr_shown[i] == _hdr_target[i]:
			continue
		if _hdr_delay[i] > 0.0:
			_hdr_delay[i] -= delta
			continue
		var d := absf(_hdr_target[i] - _hdr_shown[i])
		_hdr_shown[i] = move_toward(_hdr_shown[i], _hdr_target[i], maxf(d * 4.0, 40.0) * delta)
	_apply_headers()

# ---------- Coins flying to the counter ----------

signal coin_arrived
signal star_reached(index: int)       # a star on the shift's bar just lit
signal star_slam(index: int)          # a results star just slammed in
signal unlock_shown
signal transition_started(dir: int)     # a screen slides (+1 forward, -1 back) or pops (0)
signal confetti_started

const FLY_POOL := 10
const FLY_TIME := 0.75
var _fc_on: Array[bool] = []
var _fc_from := PackedVector2Array()
var _fc_t := PackedFloat32Array()
var coins_arrived := 0

## `n` coins (at most a handful) leave `from` (a screen position) and fly to the coin total.
func fly_coins(from: Vector2, n: int) -> void:
	if DebugFlags.off("popup"):
		return
	var shown := 0
	for i in FLY_POOL:
		if shown >= mini(n, 5):
			break
		if _fc_on[i]:
			continue
		_fc_on[i] = true
		_fc_from[i] = from + Vector2((shown - 2) * 18.0, 0.0)
		_fc_t[i] = -0.07 * shown
		shown += 1

## A fine: a small ticket pops up at `from` (near the plane), then drops into the fines counter. The counter catches up when it lands.
const TK_POP := 0.32
const TK_FLY := 0.5
var _tk_on: Array[bool] = []
var _tk_from := PackedVector2Array()
var _tk_t := PackedFloat32Array()
var _tk_flying := 0
signal ticket_landed
signal fines_stamp                        # the results tally reaches the fines beat: the ticket is stamped
var _stamped := false

func fly_ticket(from: Vector2) -> void:
	if _tk_on.is_empty():
		_tk_on.resize(6)
		_tk_on.fill(false)
		_tk_from.resize(6)
		_tk_t.resize(6)
	for i in 6:
		if _tk_on[i]:
			continue
		_tk_on[i] = true
		_tk_from[i] = from
		_tk_t[i] = 0.0
		_tk_flying += 1
		return
	_art.tickets_shown = _art.tickets_target          # (a crowd of fines: the counter simply catches up)
	_art.fines_shown = _art.fines_total_target
	_art.queue_redraw()

func _clear_tickets() -> void:
	for i in _tk_on.size():
		_tk_on[i] = false
		_art.tk_s[i] = 0.0
	_tk_flying = 0
	_art.tickets_shown = 0
	_art.fines_shown = 0
	_art.tk_punch = -1.0

func _update_tickets(delta: float) -> void:
	var any := false
	var to: Vector2 = _art.fines_rect().get_center() + Vector2(-72.0, 0.0)
	for i in _tk_on.size():
		if not _tk_on[i]:
			_art.tk_s[i] = 0.0
			continue
		_tk_t[i] += delta
		var t := _tk_t[i]
		any = true
		if t < TK_POP:             # pops up near the plane
			var k := t / TK_POP
			_art.tk_pos[i] = _tk_from[i] + Vector2(0.0, -70.0 * Style.ease_out_cubic(k))
			_art.tk_s[i] = 1.35 * Style.ease_out_cubic(k)
		elif t < TK_POP + TK_FLY:  # ...and drops into the counter
			var k2 := (t - TK_POP) / TK_FLY
			var a: Vector2 = _tk_from[i] + Vector2(0.0, -70.0)
			var e := Style.ease_in_cubic(k2)
			_art.tk_pos[i] = a.lerp(to, e)
			_art.tk_s[i] = lerpf(1.35, 0.75, e)
		else:
			_tk_on[i] = false
			_art.tk_s[i] = 0.0
			_tk_flying = maxi(_tk_flying - 1, 0)
			_art.tickets_shown = mini(_art.tickets_shown + 1, _art.tickets_target)
			_art.fines_shown = _art.fines_total_target if _tk_flying == 0 else _art.fines_shown
			_art.tk_punch = 0.0
			ticket_landed.emit()
	if _art.tk_punch >= 0.0:
		_art.tk_punch += delta / 0.3
		any = true
		if _art.tk_punch > 1.0:
			_art.tk_punch = -1.0
	if _tk_flying == 0 and (_art.tickets_shown != _art.tickets_target or _art.fines_shown != _art.fines_total_target):
		_art.tickets_shown = _art.tickets_target
		_art.fines_shown = _art.fines_total_target
		any = true
	if any:
		_art.queue_redraw()

func flying_coins() -> int:
	var c := 0
	for i in FLY_POOL:
		if _fc_on[i]:
			c += 1
	return c

func _update_coins(delta: float) -> void:
	var to := _art.coin_icon if _art.coin_icon.x > 0.0 else Vector2(get_viewport().get_visible_rect().size.x * 0.5, 120.0)
	var any := false
	for i in FLY_POOL:
		if not _fc_on[i]:
			_art.fc_s[i] = 0.0
			continue
		_fc_t[i] += delta
		var t := _fc_t[i]
		if t < 0.0:
			_art.fc_s[i] = 0.0
			any = true
			continue
		var k := clampf(t / FLY_TIME, 0.0, 1.0)
		if k >= 1.0:
			_fc_on[i] = false
			_art.fc_s[i] = 0.0
			coins_arrived += 1
			_punch_ms = Time.get_ticks_msec()
			coin_arrived.emit()
			any = true
			continue
		var e := Style.ease_in_cubic(k) * 0.65 + k * 0.35
		var a: Vector2 = _fc_from[i]
		var ctrl := Vector2((a.x + to.x) * 0.5 + 60.0, minf(a.y, to.y) - 90.0)
		_art.fc_pos[i] = a.lerp(ctrl, e).lerp(ctrl.lerp(to, e), e)
		_art.fc_s[i] = 0.55 + 0.6 * sin(PI * minf(k * 1.6, 1.0)) * (1.0 - k * 0.5)
		any = true
	if any:
		_art.queue_redraw()

# ---------- Screen transitions ----------

const SLIDE := 140.0
## How far into the flow each screen is: going deeper slides in from the right, coming back from the left.
const DEPTH := {"menu": 0.0, "select": 1.0, "detail": 1.5, "upgrades": 1.0, "goals": 1.0, "achievements": 1.0, "list": 1.0, "play": 2.0, "results": 3.0, "pause": 2.5, "ad": 2.5}
const POP_KINDS := ["results", "pause", "ad"]
var _tr_t := 99.0
var transition_count := 0
var _tr_wait := 0              # frames to wait before the transition starts (one: the panel's first, invisible, draw)
var _tr_dir := 0
var _tr_kind := ""
var _tr_depth := 0.0
var _prewarming := false
var _tr_nodes: Array[Control] = []
var _logo_bg: ColorRect
var _logo_sent := false
signal logo_finished

const LOGO_END := 2.4          # the menu starts here; the intro's cover fades out over the next 0.3 s
const LOGO_FADE := 0.3

## A new screen is about to show: arm its transition (slide forward / back, or a scale pop for sheets). Redrawing the
## same screen (a shop tab, a purchase) does not replay it.
func _go(kind: String) -> void:
	if _tipart != null and _tipart.get_parent() == self:
		move_child(_tipart, get_child_count() - 1)       # (the tip layer stays above whatever screen is coming)
	if DebugFlags.stamp_enabled() and OS.has_feature("web"):
		call_deferred("_publish_buttons")
	if _prewarming or kind == _tr_kind:
		_tr_kind = kind
		return
	_hdr_on[0] = false
	_hdr_on[1] = false
	_scroll_cur = null
	var d: float = DEPTH.get(kind.get_slice(":", 0), 0.0)
	_tr_dir = 0 if kind in POP_KINDS else int(signf(d - _tr_depth))
	_tr_depth = d
	_tr_kind = kind
	transition_count += 1
	_tr_t = 0.0
	_tr_wait = 1                 # (the panel is drawn once, invisibly, before it moves)
	_art.press_k = -1
	_art.rel_k = -1
	_apply_transition()
	transition_started.emit(_tr_dir)

## ?perf on the web: where every button on screen is (CSS pixels, `window.__btn`), for the web checks to tap.
func _publish_buttons() -> void:
	var vp := get_viewport().get_visible_rect().size
	var sc := float(JavaScriptBridge.eval("window.innerWidth")) / vp.x
	var parts: Array[String] = []
	for k in _art.btn_count:
		var c: Vector2 = _art.btn_rect[k].get_center()
		parts.append("%s: [%.1f, %.1f]" % [JSON.stringify(_art.btn_id[k]), c.x * sc, c.y * sc])
	var pc: Vector2 = _art.pause_rect.get_center() * sc
	JavaScriptBridge.eval("window.__btn = {" + ", ".join(parts) + "}; window.__screen = %s; window.__pausePos = [%.1f, %.1f]" % [JSON.stringify(_tr_kind), pc.x, pc.y])

func transition_kind() -> String:
	return _tr_kind

func transition_dir() -> int:
	return _tr_dir

func transitioning() -> bool:
	return _tr_t < Style.T_PANEL or _tr_wait > 0

func _apply_transition() -> void:
	# Opening a screen: the layer scales up from 94% with a little overshoot (ease-out back) and fades in from nothing, in 180 ms.
	# Position, scale and opacity of the whole layer only: nothing inside is resized, re-laid out or redrawn for it.
	var k := clampf(_tr_t / Style.T_PANEL, 0.0, 1.0)
	var a := 0.0 if _tr_wait > 0 else clampf(_tr_t / (Style.T_PANEL * 0.8), 0.0, 1.0)
	if k >= 1.0 and _tr_wait <= 0:
		transform = Transform2D.IDENTITY
		a = 1.0
	else:
		var sc := lerpf(Style.PANEL_FROM, 1.0, Style.ease_out_back(k))
		var vp := get_viewport().get_visible_rect().size
		transform = Transform2D(0.0, Vector2(sc, sc), 0.0, vp * 0.5 * (1.0 - sc))
	for n in _tr_nodes:
		if n is Art and n.position == PARK:
			continue            # (a parked layer is left alone: touching it would draw it again)
		n.modulate.a = a

# ---------- Celebrations: star bar sparkle, results slam, confetti, the unlock reveal ----------

func _tick_celebrations(delta: float) -> void:
	var redraw := false
	for i in 3:
		if _art.star_t[i] >= 0.0:
			_art.star_t[i] += delta
			redraw = true
			if _art.star_t[i] > 0.7:
				_art.star_t[i] = -1.0
	if _art.show_result:
		while _slam_next < _art.res_stars and _art.res_t >= Art.STAR_T0 + Art.STAR_GAP * _slam_next + Art.SLAM:
			star_slam.emit(_slam_next)
			_slam_next += 1
		if not _stamped and _art.res_fines_eff > 0 and _art.res_t >= Art.STAR_T0 + Art.STAR_GAP * 3.0 + Art.RES_FINE_AT:
			_stamped = true
			fines_stamp.emit()
		if _art.res_stars >= 3 and not _confetti_done and _art.res_t >= Art.STAR_T0 + Art.STAR_GAP * 2.0 + Art.SLAM:
			_confetti_done = true
			_spawn_confetti()
			confetti_started.emit()
		if _unlock_pending != "" and _art.res_t >= UNLOCK_AT and _art.unlock_t < 0.0:
			_begin_unlock()
	if _art.unlock_t >= 0.0:
		_art.unlock_t += delta
		redraw = true
	if confetti_count() > 0:
		_tick_confetti(delta)
		redraw = true
	if redraw:
		_art.queue_redraw()

func _spawn_confetti() -> void:
	var vp := get_viewport().get_visible_rect().size
	var cols := [Style.ACCENT, Style.PRIMARY, Style.SUCCESS, Style.WARNING, Style.DANGER, Color.WHITE]
	_cf_rng.seed = 5
	for i in Art.CONFETTI:
		_art.cf_on[i] = 1
		_art.cf_pos[i] = Vector2(_cf_rng.randf_range(0.0, vp.x), _cf_rng.randf_range(-260.0, -20.0))
		_cf_vel[i] = Vector2(_cf_rng.randf_range(-140.0, 140.0), _cf_rng.randf_range(160.0, 420.0))
		_cf_spin[i] = _cf_rng.randf_range(-9.0, 9.0)
		_art.cf_rot[i] = _cf_rng.randf_range(0.0, TAU)
		_art.cf_col[i] = cols[i % cols.size()]
		_art.cf_size[i] = Vector2(_cf_rng.randf_range(14.0, 26.0), _cf_rng.randf_range(8.0, 14.0))

func _tick_confetti(delta: float) -> void:
	var h := get_viewport().get_visible_rect().size.y + 60.0
	for i in Art.CONFETTI:
		if _art.cf_on[i] == 0:
			continue
		_art.cf_pos[i] += _cf_vel[i] * delta
		_cf_vel[i].x += sin(_art.cf_pos[i].y * 0.02 + float(i)) * 260.0 * delta
		_art.cf_rot[i] += _cf_spin[i] * delta
		if _art.cf_pos[i].y > h:
			_art.cf_on[i] = 0

func confetti_count() -> int:
	var c := 0
	for i in Art.CONFETTI:
		c += _art.cf_on[i]
	return c

## Call after show_results: a new airport opened with this shift. Its reveal plays once the stars and the total are in.
func queue_unlock(airport_name: String) -> void:
	_unlock_pending = airport_name
	_art.res_unlock = airport_name
	_art.queue_redraw()

func _begin_unlock() -> void:
	var vp := get_viewport().get_visible_rect().size
	_art.unlock_name = _unlock_pending
	_unlock_pending = ""
	_art.unlock_t = 0.0
	_art.clear_buttons()
	_art.add_button("unlock_ok", "NICE!", Rect2(vp.x * 0.5 - 300.0, vp.y * 0.5 + 280.0, 600.0, 200.0), 0, "", -1, -1, {"kind": 2, "glyph": "check"})
	unlock_shown.emit()

func unlock_active() -> bool:
	return _art.unlock_t >= 0.0

func hide_unlock() -> void:
	_art.unlock_t = -1.0
	_art.unlock_name = ""
	_art.clear_buttons()
	_art.queue_redraw()

# ---------- Intro ----------

## The title intro: studio mark, then the game's logo (about 2.4 s, any tap skips). `logo_finished` fires when the menu should appear.
func show_logo() -> void:
	Boot.mark("logo started (frame %d)" % Engine.get_process_frames())
	_hide_all_screens()
	_art.clear_buttons()
	_logo_bg.visible = true
	_logo_bg.color.a = 1.0
	_logo_sent = false
	_logo_wall_ms = 0
	_art.logo_t = 0.0
	_art.queue_redraw()

func logo_active() -> bool:
	return _art.logo_t >= 0.0

func skip_logo() -> void:
	if _art.logo_t >= 0.0 and _art.logo_t < LOGO_END:
		_art.logo_t = LOGO_END

var _logo_wall_ms := 0
func _tick_logo(delta: float) -> void:
	if _art.logo_t < 0.0:
		return
	# The intro runs on the wall clock: the engine's frame delta is held to one physics tick (1/60 s) when frames are slower than that,
	# which on a slow phone made a 2.4 s intro last ten seconds.
	var now := Time.get_ticks_msec()
	var wall := minf((now - _logo_wall_ms) / 1000.0, 0.25) if _logo_wall_ms > 0 else 0.0
	_logo_wall_ms = now
	_art.logo_t += maxf(delta, wall)
	if _art.logo_t >= LOGO_END and not _logo_sent:
		_logo_sent = true
		Boot.mark("logo finished (%d fps, %d frames)" % [Engine.get_frames_per_second(), Engine.get_process_frames()])
		logo_finished.emit()
	_logo_bg.color.a = clampf(1.0 - (_art.logo_t - LOGO_END) / LOGO_FADE, 0.0, 1.0)
	if _art.logo_t >= LOGO_END + LOGO_FADE:
		_art.logo_t = -1.0
		_logo_bg.visible = false
	_art.queue_redraw()

## Fit the HUD to the device's safe area (notch / rounded corners / home indicator): the shift's top row, the pause
## button and the top-anchored labels move in; screens read Style.safe_* when they are laid out.
func apply_safe() -> void:
	var t := Style.safe_top
	for a in [_main_art] + _panel_arts.values():
		a.top = t
		a.left = Style.safe_left
		a.right = Style.safe_right
		a.pause_rect = Rect2(Style.GUTTER * 0.5 + Style.safe_left, 10.0 + t, 80.0, 80.0)
	if _panel_arts.has("results_bg"):
		_panel_arts["results_bg"].queue_redraw()      # (its layout follows the safe area)
	_score.offset_top = 56 + t
	_best.offset_top = 6 + t
	_wind_banner.offset_top = 312 + t
	_select_title.offset_top = 40 + t          # (the list screens fit their own title: see _fit_select_title)
	for vt in _version_tags:
		vt.offset_top = -52 - Style.safe_bottom
		vt.offset_bottom = -10 - Style.safe_bottom
		vt.offset_right = -14 - Style.safe_right
		vt.offset_left = -300 - Style.safe_right
	_tip.offset_top = -270 - Style.safe_bottom
	_tip.offset_bottom = -190 - Style.safe_bottom
	if _stamp != null:
		refresh_stamp()
	_art.queue_redraw()

## A finger is down on a button: it draws pushed in (and the activation follows at once).
## ---- lists that scroll ----
## A list that does not fit the screen (the shop, the achievements, the goals) is a KScroll (the game's one scroller) holding an Art of its own, as tall as the list; the
## header, tabs and Back button stay on the panel's Art. `_scroll_for` makes (or reuses) the one of a panel; the touch functions below look in it
## after the panel's own buttons, in the list's coordinates (the position of the finger, less the container's, plus how far it is scrolled).
var _scrolls := {}                 # panel kind -> {"host": KScroll, "art": Art}
var _scroll_cur = null              # the current panel's entry, or null
var _press_art: Art = null

## The lists take touches only while no sheet (the shop's preview) is up over them.
func _scrolls_enabled(on: bool) -> void:
	for e in _scrolls.values():
		(e["host"] as KScroll).enabled = on

func _scroll_for(kind: String, region: Rect2, content_h: float) -> Art:
	var pa := _panel_art(kind)
	var e = _scrolls.get(kind)
	if e == null:
		var host := KScroll.new()
		var sa := Art.new()
		sa.is_scroll = true
		sa.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sa.set_anchors_preset(Control.PRESET_TOP_LEFT)
		host.add_child(sa)
		pa.add_child(host)
		e = {"host": host, "art": sa}
		_scrolls[kind] = e
	var h: KScroll = e["host"]
	var a: Art = e["art"]
	h.position = region.position
	h.size = region.size
	h.jump_to(0.0)
	a.custom_minimum_size = Vector2(region.size.x, maxf(content_h, region.size.y))
	a.size = a.custom_minimum_size
	a.top = pa.top
	a.clear_buttons()
	a.btn_age = 99.0
	_scroll_cur = e
	return a

## The list's button under `pos` (screen coordinates), or [null, -1].
func _scroll_hit(pos: Vector2) -> Array:
	if _scroll_cur == null:
		return [null, -1]
	var h: KScroll = _scroll_cur["host"]
	if not h.is_visible_in_tree() or not h.get_global_rect().has_point(pos):
		return [null, -1]
	var a: Art = _scroll_cur["art"]
	var local := pos - h.get_global_rect().position + Vector2(0.0, float(h.scroll_vertical))
	return [a, a.button_at(local)]

func press(pos: Vector2) -> void:
	_art.press_k = _art.button_at(pos)
	_press_art = _art
	if _art.press_k < 0:
		var sh := _scroll_hit(pos)
		if sh[1] >= 0:
			_press_art = sh[0]
			_press_art.press_k = sh[1]
	_press_art.press_t = 0.0
	_press_art.rel_k = -1
	_press_art.queue_redraw()
	_art.queue_redraw()

func release() -> void:
	var pa: Art = _press_art if _press_art != null else _art
	if pa.press_k != -1:
		pa.rel_k = pa.press_k
		pa.rel_t = 0.0
		pa.press_k = -1
		pa.queue_redraw()
	_press_art = null

func pressed_id() -> String:
	var pa: Art = _press_art if _press_art != null else _art
	return pa.btn_id[pa.press_k] if pa.press_k >= 0 else ""

## A list card's button, for the tests and the audit: {"rect" (in the list), "state", "text", "index"} or {}.
func list_button(id: String) -> Dictionary:
	if _scroll_cur == null:
		return {}
	var a: Art = _scroll_cur["art"]
	var k: int = a.btn_id.find(id)
	if k < 0 or k >= a.btn_count:
		return {}
	return {"rect": a.btn_rect[k], "state": a.btn_state[k], "text": a.btn_text[k], "index": k, "art": a}

## Where a list card is on the screen now (the list's own offset and how far it is scrolled taken into account).
func list_screen_rect(id: String) -> Rect2:
	var b := list_button(id)
	if b.is_empty():
		return Rect2()
	var h: KScroll = _scroll_cur["host"]
	return Rect2(h.global_position + (b["rect"] as Rect2).position - Vector2(0.0, float(h.scroll_vertical)), (b["rect"] as Rect2).size)

func list_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if _scroll_cur != null:
		var a: Art = _scroll_cur["art"]
		for k in a.btn_count:
			out.append(a.btn_id[k])
	return out

func _label(size: int, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l: Label = ExtLabel.new() if size >= SZ_M else Label.new()       # display text is cream on a warm extrusion (see ExtLabel)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", Style.display() if size >= SZ_M else Style.text())
	l.add_theme_color_override("font_color", Style.WORLD_TEXT)
	l.add_theme_color_override("font_outline_color", Style.EXT_BOTTOM if size >= SZ_M else Style.INK)
	l.add_theme_constant_override("outline_size", 4 if size >= SZ_M else maxi(size / 8, 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("role", "heading" if size >= 54 else "body")
	if size < 54:
		l.add_theme_font_size_override("font_size", maxi(size, Style.SZ_BODY))
	(parent if parent != null else self).add_child(l)
	return l

func _centered(l: Label, top: float, bottom: float) -> void:
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = top
	l.offset_bottom = bottom
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _shade(parent: Control, a: float) -> ColorRect:
	var shade := ColorRect.new()
	shade.color = Color(C_DIM.r, C_DIM.g, C_DIM.b, a)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.offset_left = -SLIDE
	shade.offset_right = SLIDE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	return shade

## The labels of the shift HUD (coin total, clock) only show while a shift is on screen.
func _set_play_labels(on: bool) -> void:
	_play_labels_on = on
	_score.visible = on
	_best.visible = on
	if not on:
		_wind_banner.visible = false
		_tip.visible = false
		_art.banner_alpha = 0.0
		_tipart.tip_alpha = 0.0

# ---------- Pause ----------

## The pause menu: a heavy shade over everything, a title and the primary RESUME button; the volume sliders and the
## two small icon buttons are drawn by the art layer.
var _pause_title: Label

func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pause)
	_shade(_pause, 0.6)
	_pause_title = _label(SZ_XL, HORIZONTAL_ALIGNMENT_CENTER, _pause)
	_pause_title.text = "PAUSED"
	_centered(_pause_title, -600, -450)
	_version_tag(_pause)
	_pause.visible = false

## The reset sheet covers the pause menu: its title and shade step aside while it is up.
func set_pause_layer(on: bool) -> void:
	if _pause != null:
		_pause.visible = on

func show_pause(sound: float, music: float, ambience: float = 0.8) -> void:
	if not priming:
		_go("pause")
		_pause.visible = true
		_main_art.show_pause = true          # (the shift's interface steps aside; the sheet is its own layer, laid out in advance)
		_main_art.queue_redraw()
		_set_play_labels(false)
	var vp := get_viewport().get_visible_rect().size
	var pa := _panel_art("pause")
	var prev := _art
	_art = pa
	if _panel_sig.get("pause", "") != _sig([]):
		_art.show_pause = true
		# the stack, centred: RESUME, the card with the three sliders (each at least a tap apart), Restart and Menu, the privacy link
		var tap := Style.tap_px()
		var dy := maxf(130.0, tap + 16.0)
		var card_h := 80.0 + 2.0 * dy + 80.0 + 50.0
		var total := 170.0 + 230.0 + 40.0 + card_h + 30.0 + 260.0 + 40.0 + 96.0 + 30.0 + 96.0
		var yt := maxf(vp.y * 0.5 - total * 0.5, Style.safe_top + 24.0)
		_pause_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)       # (the title sits over the stack: a Label of its own, 150 tall)
		_pause_title.offset_left = -440.0
		_pause_title.offset_right = 440.0
		_pause_title.offset_top = yt
		_pause_title.offset_bottom = yt + 150.0
		var y0 := yt + 170.0
		var card_y := y0 + 230.0 + 40.0
		_art.slider_rect[1] = Rect2(vp.x * 0.5 - 250.0, card_y + 80.0, 620.0, 80.0)            # music on top, then effects, then ambience
		_art.slider_rect[0] = Rect2(vp.x * 0.5 - 250.0, card_y + 80.0 + dy, 620.0, 80.0)
		_art.slider_rect[2] = Rect2(vp.x * 0.5 - 250.0, card_y + 80.0 + 2.0 * dy, 620.0, 80.0)
		_art.pause_card = Rect2(vp.x * 0.5 - 440.0, card_y, 880.0, card_h)
		_art.clear_buttons()
		_art.add_button("resume", "RESUME", Rect2(vp.x * 0.5 - 420.0, y0, 840.0, 230.0), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
		var by := card_y + card_h + 30.0
		_art.add_button("restart", "Restart", Rect2(vp.x * 0.5 - 330.0, by, 220.0, 260.0), 0, "", -1, -1, {"kind": 3, "glyph": "restart", "tint": Style.PRIMARY})
		_art.add_button("quit", "Menu", Rect2(vp.x * 0.5 + 110.0, by, 220.0, 260.0), 0, "", -1, -1, {"kind": 3, "glyph": "home", "tint": Style.DANGER})
		var gy := by + 260.0 + 40.0                 # the settings buttons: two by two (Tips, Replay tutorial / Privacy policy, Reset progress)
		var gx := vp.x * 0.5 - 450.0
		_art.add_button("tips", "Tips", Rect2(gx, gy, 440.0, 96.0), 0, "", -1, -1, {"kind": 6, "glyph": "star"})
		_art.add_button("replay", "Replay tutorial", Rect2(gx + 460.0, gy, 440.0, 96.0), 0, "", -1, -1, {"kind": 6, "glyph": "restart"})
		_art.add_button("privacy", "Privacy policy", Rect2(gx, gy + 126.0, 440.0, 96.0), 0, "", -1, -1, {"kind": 6, "glyph": "lock"})
		_art.add_button("reset", "Reset progress", Rect2(gx + 460.0, gy + 126.0, 440.0, 96.0), 0, "", -1, -1, {"kind": 6, "glyph": "restart", "tint": Style.DANGER})
		_panel_sig["pause"] = _sig([])
		_art.queue_redraw()
	if not is_equal_approx(_art.slider_val[0], sound) or not is_equal_approx(_art.slider_val[1], music) or not is_equal_approx(_art.slider_val[2], ambience):
		_art.slider_val[0] = sound
		_art.slider_val[1] = music
		_art.slider_val[2] = ambience
		_art.queue_redraw()
	if priming:
		_art = prev
		return
	pa.position = Vector2.ZERO
	_apply_transition()          # (its opacity follows the screen's transition from the first frame)
	pa.btn_age = 99.0
	pa.press_k = -1
	pa.rel_k = -1

## Lay a results card out in advance (made-up numbers, parked): the first draw of an Art grows its command buffers and warms its
## styles, which is the part of opening the results that does not depend on the shift. Called while the menu is idle.
# ---------- The shop's preview sheet ----------
# Tapping a livery or a skin opens a sheet over the shop (the list stays behind it): the picture, the price, the balance before and
# after, and the one button. `p` is built by Main._preview_args(): kind, index, name, sub, state ("buy" | "need" | "bought" | "owned" |
# "equipped"), price, balance, need, mode (0 current / 1 new), airport, theme, current_theme, livery, runway.
var _preview_open := false

func _preview_art() -> Art:
	var pa := _panel_art("preview")
	var si: int = _panel_arts["shop"].get_index() if _panel_arts.has("shop") else 0
	if pa.get_index() < si:
		move_child(pa, si)                  # (above the shop's list)
	return pa

func show_preview(p: Dictionary) -> void:
	var pa := _preview_art()
	var fresh := not _preview_open
	_preview_open = true
	pa.pv_on = true
	_scrolls_enabled(false)
	var vp := get_viewport().get_visible_rect().size
	var top := Style.safe_top
	var card := Rect2(40.0, top + 110.0, vp.x - 80.0, vp.y - top - 110.0 - 50.0 - Style.safe_bottom)
	var stage := Rect2(card.position.x + 40.0, card.position.y + 240.0, card.size.x - 80.0, minf(card.size.y * 0.36, 760.0))
	p["card"] = card
	p["stage"] = stage
	var y := stage.end.y + 28.0
	var mode_h := maxf(76.0, Style.tap_px())
	if p["kind"] == "theme":
		y += mode_h + 20.0
	p["info_y"] = y + 40.0
	pa.pv = p
	if fresh:
		pa.pv_t = 0.0
		pa.pv_ok_t = -1.0
		pa.pv_hold = 0.0
		pa.modulate.a = 0.0
	if p["state"] == "bought" and pa.pv_ok_t < 0.0:
		pa.pv_ok_t = 0.0
	_art = pa
	pa.clear_buttons()
	pa.add_button("preview_scrim", "", Rect2(Vector2.ZERO, vp), 0, "", -1, -1, {"kind": 11})
	pa.add_button("preview_card", "", card, 0, "", -1, -1, {"kind": 11})
	pa.add_button("preview_close", "", Rect2(card.position.x + 14.0, card.position.y + 14.0, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
	if p["kind"] == "theme":
		var cw := 300.0
		for m in 2:
			pa.add_button("pv_mode:%d" % m, "Current" if m == 0 else "New", Rect2(card.get_center().x - cw - 10.0 + m * (cw + 20.0), stage.end.y + 20.0, cw, mode_h), 2 if p["mode"] == m else 0, "", -1, -1, {"kind": 4})
	var label := ""
	var bst := 2
	match p["state"]:
		"buy":
			label = "Buy for %s" % Art.fmt_int(p["price"])
		"need":
			label = "Need %s more" % Art.fmt_int(p["need"])
			bst = 1
		"locked":
			label = "Locked"
			bst = 1
		"bought", "owned":
			label = "Equip"
		"equipped":
			label = "Equipped"
			bst = 1
	pa.add_button("pv_buy", label, Rect2(card.position.x + 60.0, card.end.y - 60.0 - 220.0, card.size.x - 120.0, 220.0), bst, "", -1, -1, {"kind": 10})
	pa.queue_redraw()
	if DebugFlags.stamp_enabled() and OS.has_feature("web"):
		call_deferred("_publish_buttons")
	pa.position = Vector2.ZERO
	pa.btn_age = 99.0
	if fresh:
		pa.press_k = -1
		pa.rel_k = -1
	_art = pa

func hide_preview() -> void:
	if not _preview_open:
		return
	_preview_open = false
	var pa: Art = _panel_arts["preview"]
	pa.pv_on = false
	_scrolls_enabled(true)
	pa.position = PARK
	pa.btn_count = 0
	pa.press_k = -1
	pa.rel_k = -1
	if _panel_arts.has("shop"):
		_art = _panel_arts["shop"]
	if DebugFlags.stamp_enabled() and OS.has_feature("web"):
		call_deferred("_publish_buttons")

func preview_open() -> bool:
	return _preview_open

func set_preview_hold(f: float) -> void:
	if _preview_open:
		var pa: Art = _panel_arts["preview"]
		if absf(pa.pv_hold - f) > 0.001:
			pa.pv_hold = f
			pa.queue_redraw()

func preview_state() -> String:
	return str(_panel_arts["preview"].pv.get("state", "")) if _preview_open else ""

var _results_primed := false
## The part of the card that is the same every shift lives on its own layer under it, drawn once (here), never again.
func _results_bg() -> Art:
	var fresh := not _panel_arts.has("results_bg")
	var rb := _panel_art("results_bg")
	if fresh:
		rb.show_result = true
		rb.res_layer = 1
		rb.queue_redraw()
	if _panel_arts.has("results"):
		var ri: int = _panel_arts["results"].get_index()
		if rb.get_index() > ri:
			move_child(rb, ri)              # (under the layer with the numbers)
	return rb

func prime_results() -> void:
	if _results_primed:
		return
	_results_primed = true
	_preview_art()                # (the shop's preview sheet: its layer exists, above the list, before anyone taps a card)
	_results_bg()
	var ra := _panel_art("results")
	ra.res_layer = 2
	var prev := _art
	_art = ra
	ra.show_result = true
	ra.res_stars = 2
	ra.res_total = 123
	ra.res_best = 99
	ra.res_chips[0] = 140
	ra.res_chips[1] = 12
	ra.res_chips[2] = 29
	ra.res_sub = "%s \u00b7 12 landed" % Airports.airport_name()
	ra.res_t = 99.0
	set_results_ads(10, 10)
	ra.queue_redraw()
	_art = prev

func hide_pause() -> void:
	if _tr_kind == "pause":
		_tr_kind = "play"
		_tr_depth = 2.0
	_pause.visible = false
	_main_art.show_pause = false
	_use_main()
	if _art.show_play:
		_set_play_labels(true)
	_art.queue_redraw()

func pause_visible() -> bool:
	return _pause.visible

## Is this screen position on the pause button (a little generous for a finger)?
func pause_hit(pos: Vector2) -> bool:
	return _art.show_play and not _art.show_pause and _art._slop(_art.pause_rect.grow(6.0)).has_point(pos)

## Which volume slider (0 sound, 1 music) is at `pos`; -1 for none.
func slider_at(pos: Vector2) -> int:
	if not _art.show_pause:
		return -1
	for i in 3:
		if _art._slop(_art.slider_rect[i].grow_individual(40.0, 20.0, 40.0, 20.0)).has_point(pos):
			return i
	return -1

## Move slider `i` to the finger at screen x; returns the new 0..1 value.
func slider_set(i: int, x: float) -> float:
	var r := _art.slider_rect[i]
	var v := clampf((x - r.position.x) / r.size.x, 0.0, 1.0)
	_art.slider_val[i] = v
	_art.queue_redraw()
	return v

# ---------- Menu ----------

## "build 90bbdd5": small muted text in the bottom-right corner of the menu and the pause screen, so a tester can say which build they run.
func _version_tag(parent: Control) -> Label:
	var l := _label(Style.SZ_CAPTION, HORIZONTAL_ALIGNMENT_RIGHT, parent)
	l.name = "VersionTag"
	l.text = "build " + BuildInfo.COMMIT
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	l.offset_left = -300
	l.offset_right = -14
	l.offset_top = -52 - Style.safe_bottom
	l.offset_bottom = -10 - Style.safe_bottom
	l.modulate = Color(1, 1, 1, 0.5)
	l.set_meta("role", "caption")
	l.add_theme_font_size_override("font_size", Style.SZ_CAPTION)
	_version_tags.append(l)
	return l

var _version_tags: Array[Label] = []

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)
	_shade(_menu, 0.04)         # (the field shows through: the title has its own soft scrim at the top)
	_menu_title = _label(SZ_XL, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	_menu_title.text = "PATTERN WORK"
	_menu_title.visible = false         # (the lockup is drawn by the art; this label holds the name)
	_centered(_menu_title, -560, -420)
	_version_tag(_menu)
	_menu.visible = false

func _build_select() -> void:
	_select = Control.new()
	_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_select.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_select)
	_shade(_select, 0.62)
	_select_title = _label(SZ_M, HORIZONTAL_ALIGNMENT_CENTER, _select)
	_select_title.text = "AIRPORTS"
	_select_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_select_title.offset_left = -300
	_select_title.offset_right = 300
	_select_title.offset_top = 40
	_select.visible = false

## The fake "Ad playing" screen (no real ads yet).
func _build_ad() -> void:
	_ad = Control.new()
	_ad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ad)
	_shade(_ad, 0.96)
	_ad_title = _label(SZ_XL, HORIZONTAL_ALIGNMENT_CENTER, _ad)
	_ad_title.text = "AD"
	_centered(_ad_title, -200, -60)
	_ad_sub = _label(SZ_S, HORIZONTAL_ALIGNMENT_CENTER, _ad)
	_ad_sub.add_theme_color_override("font_color", C_SOFT)
	_centered(_ad_sub, -20, 60)
	_ad_bar = ColorRect.new()
	_ad_bar.color = Style.PRIMARY
	_ad_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_ad_bar.offset_left = -400
	_ad_bar.offset_right = 400
	_ad_bar.offset_top = 160
	_ad_bar.offset_bottom = 184
	_ad_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ad.add_child(_ad_bar)
	_ad.visible = false

## The fake ad: `title` says what it is for; the bar fills while it "plays".
func show_ad(title: String) -> void:
	_go("ad")
	_hide_all_screens()
	_art.clear_buttons()
	_ad_sub.text = title + "  (placeholder ad)"
	_ad_bar.offset_right = -400
	_ad.visible = true

func set_ad_progress(f: float) -> void:
	_ad_bar.offset_right = -400.0 + 800.0 * clampf(f, 0.0, 1.0)

func hide_ad() -> void:
	_ad.visible = false

## Back to the shift after the ad: the HUD of a running shift, nothing else.
func resume_play() -> void:
	if _tr_kind == "ad":
		_tr_kind = "play"
		_tr_depth = 2.0
	_ad.visible = false
	_over.visible = false
	_art.clear_buttons()
	_art.show_play = true
	_art.show_wind = true
	_art.show_result = false
	_set_play_labels(true)
	_art.queue_redraw()

func _hide_all_screens() -> void:
	_use_main()
	_menu.visible = false
	_over.visible = false
	_select.visible = false
	_pause.visible = false
	_art.show_pause = false
	_art.show_play = false
	_art.show_result = false
	_art.show_pause = false
	_art.show_wind = false
	_wind_inited = false
	_art.header_text = ""
	_art.header2_text = ""
	_art.lockup = false
	_art.dock_rect = Rect2()
	_art.res_unlock = ""
	_art.pause_card = Rect2()
	_set_play_labels(false)

# ---------- Results ----------

func _build_over() -> void:
	_over = Control.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	_shade(_over, 0.84)
	_over_head = _label(SZ_M, HORIZONTAL_ALIGNMENT_CENTER, _over)
	_over_head.visible = false
	_over_body = _label(SZ_S, HORIZONTAL_ALIGNMENT_CENTER, _over)
	_centered(_over_body, 60, 330)
	_over_body.visible = false
	_over_body.modulate.a = 0.0           # (the details are drawn by the art; this label holds the text)
	_over.visible = false

## The end-of-shift screen: stars and the total paid (revealed in order); the breakdown sits behind "Details".
func show_results(header: String, reason: String, shift: Shift, coins_earned: int, coins_total: int, best: int, new_best: bool, _animal: int = -1, _quote: String = "", doubled: bool = false) -> void:
	_go("results")
	_hide_all_screens()
	var rb := _results_bg()
	var ra := _panel_art("results")           # (its own layer: the card is not drawn together with the shift's interface)
	_art = ra
	ra.res_layer = 2
	rb.position = Vector2.ZERO
	_main_art.visible = false
	ra.position = Vector2.ZERO
	_apply_transition()          # (its opacity follows the screen's transition from the first frame)
	ra.btn_age = 99.0
	_over_head.text = header
	var total_line := "Total paid|+%d%s" % [coins_earned, " (doubled)" if doubled else ""]
	_over_body.text = (reason + "\n" + total_line + "\nBank|%d" % coins_total).replace("|", " ")
	_art.res_stars = shift.stars()
	_art.res_total = coins_earned
	var fines_eff := maxi(shift.gross() - shift.payout(), 0) * (2 if doubled else 1)       # (what the fines and overtime really took: the floor pays the rest)
	_art.res_fines_eff = fines_eff
	_art.res_gross = coins_earned + fines_eff
	_stamped = false
	_art.res_new_best = new_best
	_art.res_best = best
	_art.res_doubled = doubled
	_art.res_chips[0] = shift.earned + shift.bonus
	_art.res_chips[1] = shift.time_bonus
	_art.res_chips[2] = shift.fines + shift.overtime_penalty
	_art.res_protected = shift.kept() - shift.balance() if shift.is_protected() else 0
	var sub_extra := (" \u00b7 " + ramp_note) if ramp_note != "" else ((" \u00b7 cleared %d s early" % shift.early_seconds) if shift.early_seconds > 0 else "")
	_art.res_sub = "%s \u00b7 %d landed%s" % [Airports.airport_name(), shift.landed, sub_extra]
	_art.res_unlock = ""
	var rows: Array = []
	for g in goal_note:                  # (the goals first, then the rest: the streak day, the chest, achievements, ranks)
		rows.append({"glyph": "check", "text": str(g["text"]), "coins": int(g["reward"])})
	rows.append_array(goal_rows)
	for rw in rows:                      # (measured once here: a row's text fitted to two lines, not at every frame)
		var gw1 := 930.0 - 110.0 - (330.0 if int(rw["coins"]) > 0 else 40.0)
		rw["fit"] = Hud.fit_lines(str(rw["text"]), Style.SZ_BODY, gw1, 2)
		rw["lines"] = Hud.wrap_lines(rw["fit"], Style.SZ_BODY, gw1)
	_art.res_rows = rows
	_art.res_goal = goal_strip.duplicate()
	if not _art.res_goal.is_empty():
		_art.res_goal["text"] = Hud.fit_lines(str(_art.res_goal["text"]), Style.SZ_BODY, 930.0 - 100.0 - _art.text_width(str(_art.res_goal["tail"]), Style.SZ_BODY) - 48.0, 1)
	_art.res_sub_two = Hud.wrap_lines(_art.res_sub, Style.SZ_S, 1040.0) > 1
	if not _art.show_result or _art.res_t > 60.0:
		_art.res_t = 0.0
	_slam_next = 0
	_confetti_done = false
	_unlock_pending = ""
	_art.unlock_t = -1.0
	_art.cf_on.fill(0)
	_art.details_open = false
	_over_body.visible = false
	var lines := reason.split("\n")
	lines.append(total_line)
	_art.details_lines = lines
	_art.show_result = true
	_layout_result_rows()
	_set_header(0, "coin", coins_total, coins_total - coins_earned, 1.8)
	_art.queue_redraw()
	_over.visible = true

## ---- the results card's extra rows: a scrolling area inside the card ----
var _rows_host: KScroll = null
var _rows_art: Art = null

## Lay the extra rows out in the area the card leaves for them (more rows than fit scroll there, under the card's own edge).
func _layout_result_rows() -> void:
	var pa: Art = _art
	if not pa.show_result:
		return
	if _rows_host == null:
		_rows_host = KScroll.new()
		_rows_art = Art.new()
		_rows_art.rows_view = true
		_rows_art.is_scroll = true
		_rows_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows_art.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_rows_host.add_child(_rows_art)
		_scrolls["results_rows"] = {"host": _rows_host, "art": _rows_art}
	if _rows_host.get_parent() != pa:
		if _rows_host.get_parent() != null:
			_rows_host.get_parent().remove_child(_rows_host)
		pa.add_child(_rows_host)
	var stk: Dictionary = pa.res_stack()
	var area: Rect2 = stk["rows_area"]
	_rows_host.visible = area.size.y > 0.5 and not pa.res_rows.is_empty()
	_rows_host.position = area.position
	_rows_host.size = area.size
	_rows_art.res_rows = pa.res_rows
	var total := maxf(float(stk["rows_total"]) + 8.0, area.size.y)
	_rows_art.custom_minimum_size = Vector2(area.size.x, total)
	_rows_art.size = _rows_art.custom_minimum_size
	_rows_host.jump_to(0.0)
	_rows_art.queue_redraw()
	_rows_fade()

func _rows_fade() -> void:
	if _rows_host != null:
		_rows_host.modulate.a = clampf((_art.res_t - (Art.STAR_T0 + Art.STAR_GAP * 3.0 + Art.RES_FINE_AT + Art.RES_FINE_LEN + 0.2)) / 0.4, 0.0, 1.0)

## The extra row under `pos` (screen), or -1.
func result_row_at(pos: Vector2) -> int:
	if _rows_host == null or not _rows_host.visible or not _rows_host.is_visible_in_tree() or not _art.show_result:
		return -1
	var r := _rows_host.get_global_rect()
	if not r.has_point(pos):
		return -1
	var ly := pos.y - r.position.y + _rows_host.offset
	for i in _rows_art.res_rows.size():
		var rr := Art.row_rect(i, _rows_art.size.x)
		if ly >= rr.position.y and ly <= rr.end.y:
			return i
	return -1

func result_row(i: int) -> Dictionary:
	return _rows_art.res_rows[i] if _rows_art != null and i >= 0 and i < _rows_art.res_rows.size() else {}

func result_row_count() -> int:
	return _rows_art.res_rows.size() if _rows_art != null and _art.show_result else 0

func result_rows_host() -> KScroll:
	return _rows_host

## Results: the two rewarded offers (small, under the one clear PLAY AGAIN button), and the Details / Menu buttons.
## A zero amount leaves that offer out.
func set_results_ads(double_coins: int, refund: int) -> void:
	_art.clear_buttons()
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var s2 := vp.y / 1920.0
	_art.res_pills = (1 if double_coins > 0 else 0) + (1 if refund > 0 else 0)
	_layout_result_rows()
	_art.add_button("details", "Details", _art.res_stack()["details"], 0, "", -1, -1, {"kind": 4, "glyph": "chev_up" if _art.details_open else "chev_down"})
	var n := (1 if double_coins > 0 else 0) + (1 if refund > 0 else 0)
	_art.res_pills = n
	_art.add_button("again", "Next shift", _art.res_again(), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	var ph := maxf(100.0, Style.tap_px())
	var py := vp.y - Style.safe_bottom - 36.0 - float(n) * ph - float(maxi(n - 1, 0)) * 14.0
	if double_coins > 0:
		_art.add_button("ad_double", "Watch to double", Rect2(cx - 450.0, py, 900.0, ph), 0, "+%d" % double_coins, -1, -1, {"kind": 6, "glyph": "ad"})
		py += ph + 14.0
	if refund > 0:
		_art.add_button("ad_refund", "Refund fine", Rect2(cx - 450.0, py, 900.0, ph), 0, "+%d" % refund, -1, -1, {"kind": 6, "glyph": "ad"})
	_art.add_button("menu", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "home"})
	_art.queue_redraw()

## "Details": show / hide the full breakdown.
func toggle_details() -> void:
	_art.details_open = not _art.details_open
	if _panel_arts.has("results_bg") and _art == _panel_arts.get("results"):
		_panel_arts["results_bg"].position = PARK if _art.details_open else Vector2.ZERO
	_over_body.visible = _art.details_open
	var vp := get_viewport().get_visible_rect().size
	_art.details_rect = Rect2(vp.x * 0.5 - 470.0, vp.y * 0.5 - 90.0 - (90.0 + 46.0 * _art.details_lines.size()), 940.0, 90.0 + 46.0 * _art.details_lines.size()) if _art.details_open else Rect2()
	for k in _art.btn_count:
		if _art.btn_id[k] == "details":
			_art.btn_glyph[k] = "chev_up" if _art.details_open else "chev_down"
	_art.queue_redraw()

func results_details_open() -> bool:
	return _art.details_open

func set_results_text(text: String) -> void:
	_over_body.text = text

## Jump every animation to its end (the results reveal, the rolling coin total): used when the player taps to skip,
## and by the tests.
func skip_animations() -> void:
	_tr_t = 99.0
	_tr_wait = 0
	_apply_transition()
	_art.btn_age = 99.0
	_art.press_k = -1
	_art.rel_k = -1
	for i in 2:
		_hdr_shown[i] = _hdr_target[i]
	_apply_headers()
	for i in FLY_POOL:
		_fc_on[i] = false
	_art.star_t.fill(-1.0)
	_art.res_t = 99.0
	_coin_shown = float(_coin_target)
	_art.bar_shown = float(_art.balance)
	_score.text = str(_coin_target)
	_art.queue_redraw()

func results_revealed() -> bool:
	return _art.res_t >= Art.RES_DONE

# ---------- Lists ----------


# ---------- The panels, laid out in advance ----------
# Airports, Upgrades and the Hangar each have their own Art. Main lays them out while the menu is idle (`priming`: hidden, drawn once,
# invisibly), so tapping one just shows what is already drawn: the layer's transform and opacity are all that animate. If what the panel
# shows has changed since (coins, stars, a purchase), it is laid out again when it is opened.

## Where a panel waits: far off the screen (a hidden item is drawn again when it is shown; a parked one keeps what it drew).
const PARK := Vector2(-30000.0, 0.0)

func _panel_art(kind: String) -> Art:
	if not _panel_arts.has(kind):
		var a := Art.new()
		a.name = kind
		add_child(a)
		a.position = PARK
		move_child(a, _main_art.get_index() + 1)
		a.top = _main_art.top
		a.left = _main_art.left
		a.right = _main_art.right
		a.btn_age = 99.0
		_panel_arts[kind] = a
		_tr_nodes.append(a)
	return _panel_arts[kind]

func _use_main() -> void:
	_art = _main_art
	_main_art.visible = true
	for a in _panel_arts.values():
		a.position = PARK
	_preview_open = false
	if _panel_arts.has("preview"):
		_panel_arts["preview"].pv_on = false
		_scrolls_enabled(true)
		_panel_arts["preview"].btn_count = 0
	var ra: Art = _panel_arts.get("results")
	if ra != null:                 # (the next results card starts from nothing: no stars, no reveal, no unlock card)
		ra.show_result = false
		ra.res_unlock = ""
		ra.details_open = false
		ra.details_rect = Rect2()
		ra.unlock_t = -1.0
		ra.cf_on.fill(0)
		ra.btn_count = 0            # (not clear_buttons(): that would draw this parked layer again)

## Make `kind` the panel being drawn: `layout` fills its Art (only if `sig`, the data, is not what it was laid out with). Returns the Art.
func _use_panel(kind: String, sig: String, layout: Callable) -> void:
	var pa := _panel_art(kind)
	var prev := _art
	_art = pa
	if _panel_sig.get(kind, "") != sig:
		layout.call()
		_panel_sig[kind] = sig
	elif not priming:
		# (laid out already: only the header totals, which the screen change switched off, come back as they were drawn)
		_hdr_on[0] = pa.header_glyph != ""
		_hdr_on[1] = pa.header2_glyph != ""
		_hdr_shown[0] = float(pa.header_text.to_int())
		_hdr_shown[1] = float(pa.header2_text.to_int())
		_hdr_target = _hdr_shown.duplicate()
	if kind in ["select", "shop", "upgrades", "goals", "achievements", "detail"]:
		pa.header2_glyph = ""          # (these screens show one total, in the right corner: the menu's second one, at the left, is not theirs)
		pa.header2_text = ""
		_hdr_on[1] = false
	if priming:
		_art = prev                # (it stays parked off the screen: drawn once, out of sight)
		_scroll_cur = null
	else:
		_scroll_cur = _scrolls.get(kind)
		_main_art.visible = false
		pa.position = Vector2.ZERO
		_apply_transition()          # (its opacity follows the screen's transition from the first frame)
		pa.btn_age = 99.0
		pa.press_k = -1
		pa.rel_k = -1
		if _preview_open and kind == "shop":
			_art = _panel_arts["preview"]       # (the list behind the sheet was refreshed: the sheet still has the touches)

func panel_ready(kind: String) -> bool:
	return _panel_sig.has(kind)

func _sig(parts: Array) -> String:
	var out := PackedStringArray()
	for x in parts:
		out.append(str(x))
	return "|".join(out) + "|%d|%.1f|%.1f|%.1f|%d|%.2f" % [get_viewport().get_visible_rect().size.x, Style.safe_top, Style.safe_bottom, Style.safe_left, _loading_airport, Style.px_per_pt]

## An airport's detail screen: the live airport above (Main frames it in the top two thirds), this card below it, a back button, the
## "No engines" switch once the airport has three stars, and a big "Fly here" button (a locked airport shows what unlocks it instead).
func show_detail(info: Dictionary) -> void:
	if not priming:
		_go("detail")
		_hide_all_screens()
	_use_panel("detail", _sig([info]), func() -> void:
		var vp := get_viewport().get_visible_rect().size
		_art.clear_buttons()
		if not (bool(info.get("open", false)) and int(info.get("tab", 0)) == 1):         # (the Improve sheet covers the screen and has its own Back)
			_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
		# the card below the airfield is a Control tree of containers (DetailSheet), a child of this panel so it opens, parks and fades with it
		if _detail_sheet == null:
			_detail_sheet = DetailSheet.new()
			_detail_sheet.art_factory = func() -> Control: return Art.new()
			_detail_sheet.name = "DetailSheet"
			_detail_sheet.pressed.connect(func(id: String) -> void: sheet_pressed.emit(id))
			_detail_sheet.tapped.connect(func(id: String) -> void: sheet_tapped.emit(id))
			_art.add_child(_detail_sheet)
		_detail_sheet.build(info, vp, Style.safe_bottom, Style.safe_left, Style.safe_right)
		_art.queue_redraw())

## The airport detail sheet (containers), for the screen's tests and the overlap audit.
func detail_sheet() -> DetailSheet:
	return _detail_sheet

var _detail_sheet: DetailSheet = null
signal sheet_pressed(id: String)         # a finger went down on one of the detail sheet's buttons
signal sheet_tapped(id: String)          # ...and came up on it: that is a tap

## The airport select screen: one big card per airport, with just its name, stars and lock state.
func show_select(total_stars: int, open: PackedByteArray, stars: PackedInt32Array, _best_scores: PackedInt32Array, selected: int, no_engines: PackedByteArray = PackedByteArray()) -> void:
	if not priming:
		_go("select")
		_hide_all_screens()
		_select.visible = true
		_select_title.text = "AIRPORTS"
		_fit_select_title(total_stars)
	_use_panel("select", _sig([total_stars, open, stars, _best_scores, selected, no_engines, Tuning.no_engines_pay_mult, mastery_ranks, mastery_pcts]), func() -> void:
		_set_header(0, "star", total_stars)
		var vp := get_viewport().get_visible_rect().size
		_art.clear_buttons()
		_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
		for i in Airports.COUNT:
			var r := Rect2(40.0, 150.0 + Style.safe_top + i * 252.0, vp.x - 80.0, 236.0)
			if open[i] != 0:
				var best := _best_scores[i] if i < _best_scores.size() else 0
				_art.add_button("pick:%d" % i, Airports.airport_name(i), r, 2 if i == selected else 0, Airports.tag(i), stars[i], -1, {"kind": 1, "map": i, "cost": maxi(best, 0), "pips": int(mastery_ranks[i]) if i < mastery_ranks.size() else -1, "badge": int(mastery_pcts[i]) if i < mastery_pcts.size() else 0})
				pass             # (tapping a card opens its detail screen: Fly here and the No engines switch are there)
			else:
				_art.add_button("locked:%d" % i, Airports.airport_name(i), r, 1, Airports.tag(i), -1, -1, {"kind": 1, "map": i, "lock": Progression.GATE_LEVEL})
		_art.queue_redraw())

## The airport card whose scenery is still being built says so (its subtitle) until it is there; -1 clears it.
var _loading_airport := -1
func set_loading_airport(i: int) -> void:
	var was := _loading_airport
	_loading_airport = i
	for a in [was, i]:
		if a < 0:
			continue
		var k: int = _art.btn_id.find("pick:%d" % a)
		if k < 0:
			k = _art.btn_id.find("locked:%d" % a)
		if k >= 0:
			_art.btn_sub[k] = "Loading..." if a == i else Airports.tag(a)
			_art.queue_redraw()
	if i >= 0 and _select != null and not _select.visible:
		popup("Loading %s..." % Airports.airport_name(i), Color(1.0, 0.9, 0.6), get_viewport().get_visible_rect().size * Vector2(0.5, 0.45))

## A generic list screen: optional tab chips, then cards {id, title, sub, state, stars, icon, cost}, then Back.
## Where the content of a screen with a Back button starts (under the button's tap area, which is at least 44 points).
func _ytop() -> float:
	return Style.safe_top + maxf(130.0, 10.0 + Style.tap_px())

func show_list(title: String, coins: int, tabs: Array, cards: Array, compact: bool = false) -> void:
	if not priming:
		_go("list:" + title)
		_hide_all_screens()
		_select.visible = true
		_select_title.text = title
		_fit_select_title(coins)
	_use_panel("shop", _sig([title, coins, tabs, cards, compact]), func() -> void:
		_set_header(0, "coin", coins)
		var vp := get_viewport().get_visible_rect().size
		_art.clear_buttons()
		_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
		var y := _ytop()
		var tap := Style.tap_px()
		if not tabs.is_empty():
			var w := (vp.x - 80.0 - 20.0 * (tabs.size() - 1)) / tabs.size()
			var th := maxf(90.0, tap)
			for k in tabs.size():
				_art.add_button(tabs[k]["id"], tabs[k]["title"], Rect2(40.0 + k * (w + 20.0), y, w, th), 2 if tabs[k]["selected"] else 0)
			y += th + 30.0
		if compact:          # one column of cards (a picture, the name, one or two lines: a price, or where it comes from), in a list that scrolls
			var ch := maxf(190.0, tap)
			var region := Rect2(0.0, y, vp.x, vp.y - y - Style.safe_bottom - 16.0)
			var sa := _scroll_for("shop", region, 8.0 + cards.size() * (ch + 14.0) + 16.0)
			for n in cards.size():
				var c: Dictionary = cards[n]
				var rc := Rect2(40.0, 8.0 + n * (ch + 14.0), vp.x - 80.0, ch)
				var tint: Color = Color(0, 0, 0, 0)
				var sw: Array = c.get("swatch", [])
				sa.add_button(c["id"], c["title"], rc, c["state"], c["sub"], -1, c.get("icon", -1), {"kind": 16, "lock": 1 if c.get("locked", false) else 0, "tint": sw[0] if not sw.is_empty() else tint, "tint2": sw[1] if not sw.is_empty() else tint})
			sa.queue_redraw()
			_art.queue_redraw()
			return
		for c in cards:
			_art.add_button(c["id"], c["title"], Rect2(40.0, y, vp.x - 80.0, 160.0), c["state"], c["sub"], c.get("stars", -1), c.get("icon", -1), {"kind": 1, "cost": c.get("cost", -1), "glyph": c.get("glyph", "")})
			y += 176.0
		_art.queue_redraw())

## How many lines `s` takes at `size_px` in a box `w` wide (the card layouts and their drawing agree on it).
## `s` cut at a word, with an ellipsis, until it fits in `max_lines` lines of `w` units.
static func fit_lines(s: String, size_px: int, w: float, max_lines: int) -> String:
	if wrap_lines(s, size_px, w) <= max_lines:
		return s
	var words := s.split(" ")
	while words.size() > 1:
		words.remove_at(words.size() - 1)
		var t := " ".join(words) + "\u2026"
		if wrap_lines(t, size_px, w) <= max_lines:
			return t
	return s

static func wrap_lines(s: String, size_px: int, w: float) -> int:
	if s == "":
		return 1
	var f := Style.font_for(s, size_px)
	return maxi(1, roundi(f.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, w, size_px).y / maxf(f.get_height(size_px), 1.0)))

## The height of a goal / achievement row: its name and its second line, each as many lines as they need.
static func row_height(name: String, sub: String, card_w: float) -> float:
	var tw := card_w - 120.0 - 250.0
	return maxf(26.0 + Hud.wrap_lines(name, Style.SZ_BUTTON, tw) * 54.0 + 48.0 - 54.0 + 10.0 + Hud.wrap_lines(sub, Style.SZ_BODY, tw) * 46.0 + 20.0, Style.tap_px())

## The Tower (the upgrade shop): a card per upgrade with an icon, its name, one line of effect, level pips and the next price.
func show_upgrades(coins: int, levels: PackedInt32Array) -> void:
	if not priming:
		_go("upgrades")
		_hide_all_screens()
		_select.visible = true
		_select_title.text = "TOWER"
		_fit_select_title(coins)
	_use_panel("upgrades", _sig([coins, levels]), func() -> void:
		_set_header(0, "coin", coins)
		var vp := get_viewport().get_visible_rect().size
		_art.clear_buttons()
		_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
		for i in Upgrades.IDS.size():
			var id: String = Upgrades.IDS[i]
			var lvl := levels[i]
			var price := Upgrades.cost(id, lvl)
			var r := Rect2(40.0, 150.0 + Style.safe_top + i * 190.0, vp.x - 80.0, 170.0)
			var state := 0
			if price < 0:
				state = 2
			elif coins < price:
				state = 1
			else:
				state = 2
			_art.add_button("upg:" + id, Upgrades.upgrade_name(id), r, state, Upgrades.description(id), -1, -1, {"kind": 1, "glyph": Upgrades.glyph(id), "pips": lvl, "cost": maxi(price, 0), "tint": [Style.PRIMARY, Color("a06bff"), Style.WARNING, Style.DANGER, Style.SUCCESS, Color("ff8a3d")][i % 6]})
		_art.queue_redraw())

## The daily goals sheet: three goal cards (with a reroll chip each), the bonus chest and the streak.
func show_goals(v: Dictionary) -> void:
	if not priming:
		_go("goals")
		_hide_all_screens()
		_select.visible = true
		_select_title.text = "DAILY GOALS"
		_fit_select_title(int(v["coins"]))
	_use_panel("goals", _sig([v]), func() -> void:
		_set_header(0, "coin", int(v["coins"]))
		var vp := get_viewport().get_visible_rect().size
		_art.clear_buttons()
		_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
		var y := _ytop()
		var tap := Style.tap_px()
		var items: Array = v["items"]
		var gh := []
		var total := 8.0
		for it in items:
			var hh := Hud.row_height(it["text"], it["sub"], vp.x - 80.0)
			gh.append(hh)
			total += hh + 10.0 + (maxf(56.0, tap) + 10.0 if it["can_reroll"] else 0.0) + 10.0
		total += maxf(150.0, tap) + 30.0 + 250.0 + 16.0
		var sa := _scroll_for("goals", Rect2(0.0, y, vp.x, vp.y - y - Style.safe_bottom - 16.0), total)
		var ry := 8.0
		for i in items.size():
			var it2: Dictionary = items[i]
			sa.add_button("goal:%d" % i, it2["text"], Rect2(40.0, ry, vp.x - 80.0, gh[i]), 2 if it2["done"] else 0, it2["sub"], -1, -1, {"kind": 13, "pips": int(it2["tier"]), "cost": int(it2["reward"])})
			ry += gh[i] + 10.0
			if it2["can_reroll"]:
				sa.add_button("greroll:%d" % i, "Reroll", Rect2(vp.x - 40.0 - 240.0, ry, 240.0, maxf(56.0, tap)), 0, "", -1, -1, {"kind": 4})
				ry += maxf(56.0, tap) + 10.0
			ry += 10.0
		sa.add_button("chest", "Bonus chest: all three", Rect2(40.0, ry, vp.x - 80.0, Hud.row_height("Bonus chest: all three", "Finish every goal today", vp.x - 80.0)), 2 if v["chest_done"] else 0, "Finish every goal today", -1, -1, {"kind": 13, "pips": 1, "cost": int(v["chest"])})
		ry += Hud.row_height("Bonus chest: all three", "Finish every goal today", vp.x - 80.0) + 30.0
		sa.add_button("streak", v["streak_title"], Rect2(40.0, ry, vp.x - 80.0, 250.0), 0, v["streak_sub"], -1, -1, {"kind": 15, "pips": int(v["week_pos"])})
		sa.queue_redraw()
		_art.queue_redraw())

## The Achievements sheet: four group tabs, then a card per achievement (done ones in gold) with its progress and reward.
func show_achievements(v: Dictionary) -> void:
	if not priming:
		_go("achievements")
		_hide_all_screens()
		_select.visible = true
		_select_title.text = "ACHIEVEMENTS"
		_fit_select_title(int(v["coins"]))
	_use_panel("achievements", _sig([v]), func() -> void:
		_set_header(0, "coin", int(v["coins"]))
		var vp := get_viewport().get_visible_rect().size
		_art.clear_buttons()
		_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
		var y := _ytop()
		var tap := Style.tap_px()
		var tabs: Array = v["tabs"]
		var w := (vp.x - 80.0 - 14.0) / 2.0              # (the four group tabs sit two by two: "Collection" does not fit in a quarter)
		var th := maxf(90.0, tap)
		for k in tabs.size():
			_art.add_button("ach_tab:%d" % k, tabs[k], Rect2(40.0 + (k % 2) * (w + 14.0), y + (k / 2) * (th + 12.0), w, th), 2 if k == int(v["tab"]) else 0)
		y += ceilf(tabs.size() / 2.0) * (th + 12.0) + 14.0
		var items: Array = v["items"]
		var hs := []
		var total := 8.0
		for it in items:
			var hh := Hud.row_height(it["name"], it["sub"], vp.x - 80.0)
			hs.append(hh)
			total += hh + 14.0
		var sa := _scroll_for("achievements", Rect2(0.0, y, vp.x, vp.y - y - Style.safe_bottom - 16.0), total + 16.0)
		var ry := 8.0
		for n in items.size():
			var it2: Dictionary = items[n]
			sa.add_button("ach:" + it2["id"], it2["name"], Rect2(40.0, ry, vp.x - 80.0, hs[n]), 2 if it2["done"] else 0, it2["sub"], -1, -1, {"kind": 13, "pips": int(it2["size"]), "cost": int(it2["coins"])})
			ry += hs[n] + 14.0
		sa.queue_redraw()
		_art.queue_redraw())

## The centre of a button on the current screen (the tips point at it), or (INF, INF).
func button_center(id: String) -> Vector2:
	var k: int = _art.btn_id.find(id)
	if k < 0 or k >= _art.btn_count:
		var e = _scroll_cur
		return Vector2(INF, INF)
	return (_art.btn_rect[k] as Rect2).get_center()

## The id of the enabled button under `pos` ("" if none).
func button_at(pos: Vector2) -> String:
	var a: Art = _art
	var k := _art.button_at(pos)
	if k < 0:
		var sh := _scroll_hit(pos)
		if sh[1] < 0:
			return ""
		a = sh[0]
		k = sh[1]
	if a.btn_state[k] == 1 and not (a.btn_id[k].begins_with("theme:") or a.btn_id[k].begins_with("livery:") or a.btn_id[k].begins_with("windsock:") or a.btn_id[k].begins_with("hangar:") or a.btn_id[k].begins_with("locked:")):
		return ""             # (a shop card is dimmed when it is out of reach, but it still opens its preview: "Need 480 more"; so does a locked airport's card, view only)
	return a.btn_id[k]

## True if `pos` is on any button (even a disabled one): the tap belongs to the UI, not the game.
func ui_hit(pos: Vector2) -> bool:
	return _art.button_at(pos) >= 0 or _scroll_hit(pos)[1] >= 0

func hide_screens() -> void:
	_hide_all_screens()
	_ad.visible = false
	_art.clear_buttons()

## The menu: one primary PLAY button, the current airport under the title, and a row of round icon buttons.
func show_menu(airport_name: String, coins: int, stars: int, _best_coins: int, _tag: String = "", airport_stars: int = 0, bad_no_engines: bool = false) -> void:
	_go("menu")
	_hide_all_screens()
	_menu.visible = true
	_set_header(1, "coin", coins)
	_set_header(0, "star", stars)
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	_art.clear_buttons()
	var sb := Style.safe_bottom
	var tap := Style.tap_px()
	var row2 := Rect2(cx - 450.0, vp.y - 90.0 - sb - maxf(150.0, tap), 436.0, maxf(150.0, tap))         # (the build tag has the bottom 52)
	var ne_h := maxf(80.0, tap)                  # (the No engines switch over the Bad pilot day button: a tap-sized chip of its own)
	var play := Rect2(cx - 450.0, row2.position.y - ne_h - 28.0 - 250.0, 900.0, 250.0)
	_art.lockup = true
	_art.lockup_airport = airport_name
	_art.lockup_stars = airport_stars
	_art.add_button("play", "Start shift", play, 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	# The airport under the title is a button (it opens the Airports screen): it is drawn as one.
	var tag_y := 250.0 * vp.y / 1920.0 + Style.safe_top + 398.0
	_art.add_button("airports_tag", airport_name, Rect2(56.0 + Style.safe_left, tag_y, _art.text_width(airport_name, 34) + 250.0, 76.0), 0, "", airport_stars, -1, {"kind": 9})
	_art.add_button("goals", "Daily goals  %d/3" % goals_done, Rect2(56.0 + Style.safe_left, tag_y + 92.0, 760.0, 160.0), 0, goals_line, goals_done, -1, {"kind": 14, "badge": -2 if goals_done == 0 else 0})
	_art.add_button("airports", "Airports", row2, 0, "", -1, -1, {"kind": 0, "glyph": "airport"})
	_art.add_button("bad", "Bad pilot day", Rect2(row2.position.x + 464.0, row2.position.y, 436.0, 150.0), 0, "", -1, -1, {"kind": 0, "glyph": "bad"})
	_art.add_button("noeng_bad", "No engines \u00d7%s" % str(snappedf(Tuning.no_engines_pay_mult, 0.1)), Rect2(row2.position.x, row2.position.y - ne_h - 14.0, 900.0, ne_h), 2 if bad_no_engines else 0, "", -1, -1, {"kind": 4, "glyph": "glider"})
	var items := [["upgrades", "Tower", "upgrades", 0], ["shop", "Hangar", "hangar", 0], ["ach", "Awards", "star", -2 if ach_unseen else 0]]
	for k in items.size():
		_art.add_button(items[k][0], items[k][1], Rect2(vp.x - 30.0 - Style.safe_right - 190.0, 150.0 + Style.safe_top + k * 236.0, 190.0, 216.0), 0, "", -1, -1, {"kind": 7, "glyph": items[k][2], "badge": items[k][3]})
	_art.queue_redraw()

# ---------- The HUD of a shift ----------

func reset_for_run(_best_coins: int) -> void:
	_go("play")
	hide_screens()
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_flash.color.a = 0.0
	_art.show_play = true
	_art.show_wind = true
	_art.mode_glyph = mode
	_set_play_labels(true)
	_wind_banner.visible = false
	_banner_q.clear()
	_banner_left = 0.0
	_art.banner_alpha = 0.0
	_art.banner_text = ""
	_tip_q.clear()
	_tip.visible = false
	_tipart.tip_alpha = 0.0
	_wind_secs = -1
	_wind_posted = false
	_art.wind_warn = false
	_event_text = ""
	_event_banner.text = ""
	_art.chip_weather = ""
	_finale_text = ""
	_finale.text = ""
	_art.chip_finale = ""
	_secs_left = 99999
	_last_bal = 0
	_coin_target = 0
	_coin_shown = 0.0
	_art.bar_shown = 0.0
	_star_lit.fill(false)
	_art.star_on.fill(0)
	_art.landed = 0
	_art.star_t.fill(-1.0)
	_art.cf_on.fill(0)
	set_landed(0)
	set_timer(int(Tuning.par_eff()))
	_art.balance = 0
	_art.fines_total_target = 0
	_art.tickets_target = 0
	_clear_tickets()
	_score.text = "0"
	_score.add_theme_color_override("font_color", Color.WHITE)
	_layout_coin_icon()

func set_best(_best_coins: int) -> void:
	pass

var _landed := 0

## The shift clock: just m:ss (red in the last 15 s), or "+m:ss" in overtime.
func _refresh_status() -> void:
	if _secs_left < 0:      # overtime: counting up (the value is -(1 + whole seconds over))
		var over := -_secs_left - 1
		_best.text = "+%d:%02d" % [over / 60, over % 60]
		return
	_best.text = "%d:%02d" % [maxi(_secs_left, 0) / 60, maxi(_secs_left, 0) % 60]

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
		_best.add_theme_color_override("font_color", C_RED if secs_left <= 15 else Color.WHITE)

## Past par: the clock turns red and counts up (whole seconds over).
func set_overtime(over_secs: int) -> void:
	var code := -(1 + over_secs)
	if code != _secs_left:
		_secs_left = code
		_refresh_status()
		_best.add_theme_color_override("font_color", C_RED)

## The finale: "LAST ARRIVALS" is a banner (once); "CLEAR THE SKY  3 left" is a small pill with the number; "" clears it.
func set_finale(text: String, _color: Color, flash: bool) -> void:
	_finale_flash = flash
	if text == _finale_text:
		return
	_finale_text = text
	_finale.text = text
	_finale.visible = text != ""
	if text.begins_with("LAST ARRIVALS"):
		post_banner("LAST ARRIVALS", C_GOLD, "plane", 3.0)
		_art.chip_finale = ""
	elif text.begins_with("CLEAR THE SKY"):
		_art.chip_finale = text.get_slice("  ", 1).get_slice(" ", 0)
		_art.chip_finale_red = _secs_left < 0
	else:
		_art.chip_finale = ""
	_art.queue_redraw()

func finale_text() -> String:
	return _finale.text if _finale.visible else ""

## The wind widget: an arrow showing where the air is going and its direction number.
## The wind dial pulses once (a student has appeared: it must land into the wind).
func pulse_wind() -> void:
	_art.wind_pulse = 0.0
	_art.queue_redraw()

func set_wind(from_deg: float, toward_deg: float) -> void:
	if not _wind_inited:
		_art.wind_shown = toward_deg
		_wind_inited = true
	_art.wind_toward = toward_deg
	_art.wind_text = Wind.label(from_deg)
	_art.queue_redraw()

## An announced wind shift: the dial flashes and ONE banner says where it is going; `secs` < 0 clears it.
func set_wind_warning(next_deg: float, secs: int) -> void:
	_art.wind_warn = secs >= 0
	if secs < 0:
		_wind_secs = -1
		_wind_posted = false
		return
	if not _wind_posted:
		_wind_posted = true
		post_banner("Wind to %s" % Wind.label(next_deg), C_GOLD, "wind", 2.6)
	_wind_secs = secs

## A kept-for-compatibility switch: the old flashing "TRAFFIC!" text is gone (the warning rings say it).
func set_alert(_on: bool) -> void:
	pass

## The coin total (red when negative) rolls up to its new value; the star bar follows.
func set_shift(shift: Shift) -> void:
	var bal := shift.balance()
	var gross := shift.gross()                       # the coin counter only goes up during a shift: fines show on their own counter (the star bar still follows the net)
	_coin_target = gross
	_art.balance = bal
	_score.add_theme_color_override("font_color", Color.WHITE)
	_art.fines_total_target = shift.fines_total()
	_art.tickets_target = shift.tickets
	if _tk_flying == 0:
		_art.tickets_shown = shift.tickets
		_art.fines_shown = shift.fines_total()
	_art.landed = shift.landed
	for i in 3:
		_art.thresholds[i] = shift.thresholds[i]
		var lit := shift.star_reached(i)
		_art.star_on[i] = 1 if lit else 0
		if lit and not _star_lit[i] and _art.show_play:
			_art.star_t[i] = 0.0
			star_reached.emit(i)
		_star_lit[i] = lit
	_art.queue_redraw()
	if gross != _last_bal:
		_last_bal = gross
		_punch_ms = Time.get_ticks_msec()

func set_shift_fraction(_f: float) -> void:
	pass

## Where the coin icon goes: just left of the (centred) coin total.
func _layout_coin_icon() -> void:
	var font := _score.get_theme_font("font")
	var w := font.get_string_size(_score.text, HORIZONTAL_ALIGNMENT_LEFT, -1, SZ_XL).x
	var vp := get_viewport().get_visible_rect().size
	_art.coin_icon = Vector2(vp.x * 0.5 - w * 0.5 - 78.0, 56.0 + Style.safe_top + SZ_XL * 0.62)

## A floating word that rises from a screen position and fades. At most a few show at once: older ones fade fast.
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
	var pfs := SZ_M          # (the largest size on the ladder at which its longest line fits the label: no popup runs off the screen)
	for ln in text.split("\n"):
		pfs = mini(pfs, Style.fit_size(ln, SZ_M, Style.SZ_BODY, 540.0))
	l.add_theme_font_size_override("font_size", pfs)
	l.add_theme_color_override("font_color", color.lerp(Style.WORLD_TEXT, 0.55))       # cream with a hint of its meaning (gold, red, green)
	l.rotation = deg_to_rad(randf_range(-6.0, 6.0))                                     # score pops lean a few degrees, a different way each time
	var vp := get_viewport().get_visible_rect().size
	l.position = Vector2(clampf(at.x - 280.0, 0.0, maxf(vp.x - 560.0, 0.0)), clampf(at.y - 50.0, 20.0, maxf(vp.y - 160.0, 20.0)))
	_pop_from[best] = l.position
	_pop_born[best] = Time.get_ticks_msec()
	l.visible = true
	# Keep it to the newest few: the others fade out quickly instead of piling up.
	var shown := 0
	for i in POPUP_POOL:
		if _pop_born[i] != 0 and i != best:
			shown += 1
	if shown >= MAX_POPUPS_SHOWN:
		var oldest := -1
		for i in POPUP_POOL:
			if _pop_born[i] != 0 and i != best and (oldest < 0 or _pop_born[i] < _pop_born[oldest]):
				oldest = i
		if oldest >= 0:
			_pop_born[oldest] = mini(_pop_born[oldest], Time.get_ticks_msec() - int(Tuning.popup_time * 1000.0 * 0.75))

## The weather chip ("Fog 12s", "Storm in 4s"); "" hides it. The first time it appears it is also a banner.
func set_event_banner(text: String, warning: bool = false) -> void:
	if text == _event_text:
		return
	var was_empty := _event_text == ""
	_event_text = text
	_event_banner.text = text
	_event_banner.visible = text != ""
	var kind := _weather_glyph(text)
	_art.chip_weather = _short_weather(text)
	_art.chip_weather_glyph = kind
	if was_empty and text != "":
		if kind == "fog":
			post_banner("FOG ROLLING IN", C_SOFT, "fog", 3.0)
		else:
			post_banner(_short_weather(text).get_slice(" ", 0), C_GOLD if warning else C_SOFT, kind, 2.4)
	_art.queue_redraw()

func _weather_glyph(text: String) -> String:
	var t := text.to_lower()
	if t.contains("storm"):
		return "storm"
	if t.contains("fog"):
		return "fog"
	return "cross"

## "Storm cell in 4s" -> "Storm 4s"; "Fog: 12s" -> "Fog 12s"; "Orange runway closed: 9s" -> "Closed 9s".
func _short_weather(text: String) -> String:
	var secs := ""
	var i := text.length() - 1
	while i >= 0 and (text[i] == "s" or text[i].is_valid_int()):
		i -= 1
	secs = text.substr(i + 1)
	var kind := _weather_glyph(text)
	var name := "Storm" if kind == "storm" else ("Fog" if kind == "fog" else "Crosswind")
	return "%s %s" % [name, secs]

# ---------- One banner, one tip ----------

## Queue a banner: one shows at a time (a pill with a glyph and a few words) and gets out of the way.
func post_banner(text: String, color: Color, glyph: String, secs: float = 2.6) -> void:
	if text == _art.banner_text and _banner_left > 0.0:
		return
	for q in _banner_q:
		if q[0] == text:
			return
	if _banner_left > 0.0:
		_banner_q.append([text, color, glyph, secs])
		if _banner_q.size() > 3:
			_banner_q.pop_front()
		return
	_start_banner(text, color, glyph, secs)

func _start_banner(text: String, color: Color, glyph: String, secs: float) -> void:
	_art.banner_text = text
	_art.banner_color = color
	_art.banner_glyph = glyph
	_banner_left = secs
	_banner_total = secs
	_wind_banner.text = text
	_wind_banner.add_theme_color_override("font_color", color)
	_wind_banner.visible = true
	var vp := get_viewport().get_visible_rect().size
	var font := _wind_banner.get_theme_font("font")
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, SZ_M).x
	var chrome := 84.0 + 80.0 if glyph != "" else 80.0
	var avail := vp.x - 60.0 - Style.safe_left - Style.safe_right - chrome        # (the text's room on a screen this wide)
	var lines := 1
	var pw := tw
	if tw > avail:
		var fs := Style.fit_size(text, SZ_M, Style.SZ_BODY, avail)
		var fw := Style.font_for(text, fs).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if fw > avail:       # still too long at the smallest size: two lines of it
			lines = 2
			pw = avail
		else:
			pw = avail
	var ph := 90.0 if lines == 1 else 2.0 * 28.0 * 1.3 + 44.0
	_art.banner_lines = lines
	_art.banner_rect = Rect2(vp.x * 0.5 - (pw + chrome) * 0.5, 312.0 + Style.safe_top, pw + chrome, ph)
	_art.banner_alpha = 0.0

func banner_text() -> String:
	return _wind_banner.text if _wind_banner.visible else ""

## Day 1's layer: the dim (0..1), the ghost finger's screen path and how far along it is (-1 = none), and the Skip button.
func set_tutorial_layer(dim: float, pts: PackedVector2Array, ghost_t: float, skip: bool) -> void:
	_tipart.tut_dim = dim
	_tipart.ghost_pts = pts
	_tipart.ghost_t = ghost_t
	var vp := get_viewport().get_visible_rect().size
	_tipart.skip_rect = Rect2(vp.x - 24.0 - Style.safe_right - 190.0, vp.y - Style.safe_bottom - 150.0, 190.0, 100.0) if skip else Rect2()
	_tipart.queue_redraw()

func skip_hit(pos: Vector2) -> bool:
	return _tipart.skip_rect.size.x > 0.0 and _tipart.skip_rect.grow(14.0).has_point(pos)

## A tip: an icon and one short sentence, shown once. Only one at a time; the next waits its turn. With `anchor` (a screen position) the card sits next to the
## thing it is about and a ring pulses on it; `sticky` keeps it until a tap (or 12 s).
var _tip_sticky := false

func show_tip(text: String, glyph: String = "", anchor: Vector2 = Vector2(INF, INF), sticky: bool = false) -> void:
	if _tip.visible:
		_tip_q.append([text, glyph, anchor, sticky])
		if _tip_q.size() > 2:
			_tip_q.pop_front()
		return
	_start_tip(text, glyph, anchor, sticky)

func tip_active() -> bool:
	return _tip.visible

func tip_sticky() -> bool:
	return _tip.visible and _tip_sticky

## A tap anywhere puts the card away.
func dismiss_tip() -> void:
	if _tip.visible:
		_tip_until = Time.get_ticks_msec()

## The ring follows a thing that moves (a plane).
func set_tip_focus(pos: Vector2) -> void:
	if _tip.visible and _tipart.tip_focus.x < 1.0e8:
		_tipart.tip_focus = pos

func _start_tip(text: String, glyph: String, anchor: Vector2 = Vector2(INF, INF), sticky: bool = false) -> void:
	_tip.text = text
	_tip.visible = true
	_tip_sticky = sticky
	_tip_until = Time.get_ticks_msec() + (12000 if sticky else int(Tuning.tip_seconds * 1000.0))
	var vp := get_viewport().get_visible_rect().size
	_tipart.tip_glyph = glyph
	_tipart.tip_text = text
	var pw := minf(vp.x - 80.0, 860.0)
	var inner := pw - (84.0 if glyph != "" else 0.0) - 68.0
	var lines := clampi(Hud.wrap_lines(text, SZ_S, inner), 1, 3)
	_tipart.tip_lines = lines
	var ph := 100.0 if lines == 1 else 40.0 + float(lines) * 54.0
	var tw := _tip.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SZ_S).x
	if lines == 1:
		pw = minf(tw + (84.0 if glyph != "" else 0.0) + 90.0, pw)
	var top_lim := Style.safe_top + 340.0           # (under the star bar and its landing count)
	var bot_lim := vp.y - Style.safe_bottom - 24.0
	if anchor.x < 1.0e8:
		var below := anchor.y < vp.y * 0.55
		var y := anchor.y + 150.0 if below else anchor.y - 150.0 - ph
		y = clampf(y, top_lim, bot_lim - ph)
		_tipart.tip_rect = Rect2(clampf(anchor.x - pw * 0.5, 24.0, vp.x - 24.0 - pw), y, pw, ph)
		_tipart.tip_focus = anchor
	else:
		_tipart.tip_rect = Rect2(vp.x * 0.5 - pw * 0.5, vp.y - 280.0 - Style.safe_bottom - (ph - 100.0), pw, ph)
		_tipart.tip_focus = Vector2(INF, INF)
	_tipart.tip_alpha = 1.0

## A quick colour wash over the whole screen.
func flash(color: Color) -> void:
	_flash.color = Color(color.r, color.g, color.b, 0.0)
	_flash_ms = Time.get_ticks_msec()

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_inner(delta)
	Boot.add("interface (hud _process)", float(Time.get_ticks_usec() - t0) / 1000.0)

func _process_inner(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var wdiff := wrapf(_art.wind_toward - _art.wind_shown, -180.0, 180.0)
	if absf(wdiff) > 0.05:          # the wind arrow turns smoothly
		_art.wind_shown = fposmod(_art.wind_shown + wdiff * (1.0 - exp(-delta * 5.0)), 360.0)
		_art.queue_redraw()
	# The coin total rolls up (or down) to its target.
	if absf(_coin_shown - float(_coin_target)) > 0.01:
		_coin_shown = move_toward(_coin_shown, float(_coin_target), maxf(absf(float(_coin_target) - _coin_shown) * 6.0 * delta, 30.0 * delta))
		var t := str(roundi(_coin_shown))
		if t != _score.text:
			_score.text = t
			_layout_coin_icon()
			_art.queue_redraw()
	if absf(_art.bar_shown - float(_art.balance)) > 0.5:
		_art.bar_shown = move_toward(_art.bar_shown, float(_art.balance), maxf(absf(float(_art.balance) - _art.bar_shown) * 5.0 * delta, 20.0 * delta))
		_art.queue_redraw()
	var pk := (now - _punch_ms) / (Tuning.score_punch * 1000.0)
	_score.scale = Vector2.ONE * (1.0 + 0.3 * (1.0 - pk) * (1.0 - pk) if pk < 1.0 else 1.0)
	# The results reveal.
	if _art.show_result and _art.res_t < 6.0:
		_art.res_t += delta
		_rows_fade()
		_art.queue_redraw()
	# The one banner: fades in, holds, fades out, then the next one.
	if _banner_left > 0.0:
		_banner_left -= delta
		var lived := _banner_total - _banner_left
		var a := clampf(minf(lived / 0.25, _banner_left / 0.35), 0.0, 1.0)
		_art.banner_alpha = a
		_art.queue_redraw()
		if _banner_left <= 0.0:
			_art.banner_alpha = 0.0
			_art.banner_text = ""
			_wind_banner.visible = false
			if not _banner_q.is_empty():
				var q: Array = _banner_q.pop_front()
				_start_banner(q[0], q[1], q[2], q[3])
	if _finale_flash:
		_finale.modulate.a = 0.0
	var fa := (now - _flash_ms) / 450.0
	_flash.color.a = 0.45 * (1.0 - fa) if fa < 1.0 else 0.0
	for i in POPUP_POOL:
		if _pop_born[i] == 0:
			continue
		var pa := (now - _pop_born[i]) / (Tuning.popup_time * 1000.0)
		if pa >= 1.0:
			_pop_born[i] = 0
			_pop_labels[i].visible = false
			continue
		var l := _pop_labels[i]
		l.position = _pop_from[i] + Vector2(0, -150.0 * pa)
		l.modulate.a = 1.0 - maxf(pa - 0.5, 0.0) * 2.0
		l.scale = Vector2.ONE * lerpf(0.45, 1.0, Style.ease_out_back(pa / 0.18))
	if _tip.visible:
		var left := _tip_until - now
		if left <= 0:
			_tip.visible = false
			_tipart.tip_alpha = 0.0
			_tipart.tip_focus = Vector2(INF, INF)
			_tipart.queue_redraw()
			if not _tip_q.is_empty():
				var tq: Array = _tip_q.pop_front()
				_start_tip(tq[0], tq[1], tq[2] if tq.size() > 2 else Vector2(INF, INF), bool(tq[3]) if tq.size() > 3 else false)
		else:
			var ta := clampf(left / 600.0, 0.0, 1.0)
			_tipart.tip_alpha = ta
			_tipart.queue_redraw()          # (also animates the ring)
	# Screen transition, button motion, rolling header totals, coins in flight.
	if _tr_wait > 0:
		_tr_wait -= 1
		_apply_transition()
	elif _tr_t < Style.T_PANEL:
		_tr_t += delta
		_apply_transition()
	if _preview_open:
		var pva: Art = _panel_arts["preview"]
		pva.pv_t += delta
		if pva.pv_ok_t >= 0.0:
			pva.pv_ok_t += delta
		pva.modulate.a = minf(pva.pv_t / 0.16, 1.0)
		pva.queue_redraw()
	if _art.press_k >= 0:
		_art.press_t += delta
	if _art.rel_k >= 0 and _art.rel_t < 1.0:
		_art.rel_t += delta
	if _art.animating():
		_art.queue_redraw()
	_roll_headers(delta)
	_update_coins(delta)
	_update_tickets(delta)
	if _art.wind_pulse >= 0.0:
		_art.wind_pulse += delta / 1.1
		if _art.wind_pulse > 1.0:
			_art.wind_pulse = -1.0
		_art.queue_redraw()
	_tick_logo(delta)
	_tick_celebrations(delta)
	_update_perf(delta)

# ---------- ?perf ----------

## Small "commit . build time" tag bottom-left (BuildInfo.gd is rewritten by the workflow), with any
## active debug flags under it; plus the ?perf readout top-left.
var _stamp: Label

## The build stamp (commit and time, plus the active debug flags) is for debugging only: it shows with ?debug, ?tune
## or ?perf, small, in the bottom-left corner. Players never see it.
func _build_stamp() -> void:
	_stamp = _label(20, HORIZONTAL_ALIGNMENT_LEFT)
	_stamp.add_theme_font_size_override("font_size", Style.SZ_CAPTION)       # (developer overlays: small, never in a player's build)
	_stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stamp.offset_left = 12
	_stamp.modulate = Color(1, 1, 1, 0.45)
	_stamp.add_theme_font_override("font", Style.text())
	refresh_stamp()
	if DebugFlags.perf_enabled():
		_perf_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT)
		_perf_label.add_theme_font_size_override("font_size", Style.SZ_CAPTION)       # (developer overlays: small, never in a player's build)
		_perf_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_perf_label.offset_left = 14
		_perf_label.offset_top = 112       # (below the pause button)
		_perf_label.modulate = Color(0.6, 1, 0.6, 0.9)
		_perf_label.add_theme_font_override("font", Style.text())

func refresh_stamp() -> void:
	var on := DebugFlags.stamp_enabled()
	_stamp.visible = on
	if not on:
		return
	var flags := DebugFlags.summary()
	_stamp.text = "%s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME]
	if flags != "":
		_stamp.text += "\n" + flags
	_stamp.offset_top = (-40 if flags == "" else -66) - Style.safe_bottom

func note_hitch(raw: float, used: float, why: String, context: String) -> void:
	_hitch_count += 1
	var line := "#%d %.0f ms (simulated %.0f ms) %s | %s" % [_hitch_count, raw * 1000.0, used * 1000.0, why, context]
	_hitch_log.append(line)
	if _hitch_log.size() > 5:
		_hitch_log.pop_front()
	print("[hitch] " + line)   # (also in the browser console)

func set_perf_clock(sim: float, wall: float) -> void:
	_clock_text = "sim %.1f s / wall %.1f s" % [sim, wall]

var perf_extra := ""              # one more ?perf line (the overlay / art draw times), set by Main

func _update_perf(delta: float) -> void:
	if _perf_label == null:
		return
	_perf_worst = maxf(_perf_worst, delta * 1000.0)
	var now := Time.get_ticks_msec()
	if now - _perf_window_start > 3000:
		_perf_shown = _perf_worst
		_perf_worst = 0.0
		_perf_window_start = now
	_perf_label.text = "worst frame (3s): %.0f ms   %.0f fps\n%s\n%s\nhitches (over 50 ms):\n%s" % [_perf_shown, Engine.get_frames_per_second(), _clock_text, perf_extra, "\n".join(_hitch_log)]

# ---------- Start-up pre-warm ----------

## A splash (nearly opaque, so what is behind it is really drawn) while every label, popup and screen
## is shown once, building the font glyph caches.
func begin_prewarm() -> void:
	_prewarming = true
	prewarm_popups()
	_score.text = "0123456789"
	_set_play_labels(true)
	_best.text = "0123456789"
	_over_head.text = "0123456789"
	_over_body.text = "Landings earned +0123456789   Bonuses +0123456789   Fines -0123456789\nTotal paid +0123456789 coins  (bank 0123456789)"
	_art.thresholds[0] = 4
	_art.thresholds[1] = 200
	_art.thresholds[2] = 300
	_art.balance = 150
	_art.bar_shown = 150.0
	_art.show_play = true
	_art.show_result = true
	_art.warm = true
	_art.pause_card = Rect2(140.0, 700.0, 800.0, 470.0)
	_art.res_stars = 2
	_art.res_total = 123
	_art.res_t = 99.0
	_art.show_wind = true
	_art.wind_warn = true
	_art.chip_finale = "4"
	_art.chip_weather = "Storm 4s"
	post_banner("Wind to 270", C_GOLD, "wind", 3.0)
	_banner_left = 99.0
	_art.banner_alpha = 1.0
	_art.queue_redraw()
	_menu.visible = true
	_over.visible = true
	_over_body.visible = true
	_select.visible = true
	var open := PackedByteArray([1, 1, 0, 1, 0, 1])
	var st := PackedInt32Array([3, 2, 0, 1, 0, 3])
	Boot.mark("prewarm: hud flags")
	show_select(14, open, st, PackedInt32Array([12, 5, 0, 9, 0, 33]), 1)
	Boot.mark("prewarm: select panel laid out")
	_use_main()                  # (the main Art carries the results card, the pause sheet and the shift's interface: warm those)
	set_results_ads(10, 10)
	var pv := get_viewport().get_visible_rect().size
	_art.add_button("resume", "RESUME", Rect2(pv.x * 0.5 - 420.0, pv.y * 0.5 - 420.0, 840.0, 230.0), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	_art.add_button("restart", "Restart", Rect2(pv.x * 0.5 - 330.0, pv.y * 0.5 + 350.0, 220.0, 260.0), 0, "", -1, -1, {"kind": 3, "glyph": "restart", "tint": Style.PRIMARY})
	_art.add_button("quit", "Menu", Rect2(pv.x * 0.5 + 110.0, pv.y * 0.5 + 350.0, 220.0, 260.0), 0, "", -1, -1, {"kind": 3, "glyph": "home", "tint": Style.DANGER})
	_art.slider_rect[1] = Rect2(pv.x * 0.5 - 250.0, pv.y * 0.5 - 70.0, 620.0, 80.0)
	_art.slider_rect[0] = Rect2(pv.x * 0.5 - 250.0, pv.y * 0.5 + 60.0, 620.0, 80.0)
	_art.slider_rect[2] = Rect2(pv.x * 0.5 - 250.0, pv.y * 0.5 + 190.0, 620.0, 80.0)
	_select.visible = true
	_menu.visible = true
	_over.visible = true
	_ad_sub.text = "Reward: undo the conflict and keep flying  (placeholder ad)"
	_ad.visible = true
	_splash = Control.new()
	_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Every glyph of both faces at every size is drawn once so no letter is first seen mid-game. The rows sit BEHIND the
	# opaque cover (they are drawn, you never see them).
	var ascii := ""
	for cp in range(32, 127):
		ascii += char(cp)
	ascii += "\u2212\u00b7\u2014\u2013\u2019\u00d7\u2026"       # (the minus on the fines chip, the middle dot, dashes, an apostrophe, a times sign: not ASCII, and a first sight of one costs a frame)
	var row := 0
	# (the sizes the interface draws text at: a glyph is rasterised once per face and size, so each size gets its row)
	for face in 3:
		for sz in Style.PREWARM_SIZES:
			if face >= 1 and sz >= SZ_M:       # (the text face is for small text; digits and big text are the display face)
				continue
			var wl := Label.new()
			wl.text = ascii
			wl.add_theme_font_size_override("font_size", sz)
			wl.add_theme_font_override("font", Style.display() if face == 0 else (Style.text() if face == 1 else Style.body()))
			wl.add_theme_color_override("font_outline_color", Style.INK)
			wl.add_theme_constant_override("outline_size", maxi(sz / 8, 4))
			wl.position = Vector2(0.0, 60.0 + row * 150.0)
			wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_splash.add_child(wl)
			row += 1
	Boot.mark("prewarm: glyph rows")
	var bg := ColorRect.new()
	bg.color = Style.SURFACE_DARK.darkened(0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(bg)
	var sd := SplashDraw.new()
	sd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(sd)
	add_child(_splash)

func prewarm_tip() -> void:
	show_tip("Flashing aircraft: land them fast 0123456789", "emergency")
	_tipart.tip_alpha = 1.0

func prewarm_popups() -> void:
	var vp := get_viewport().get_visible_rect().size
	var words := ["+1", "+1  x2", "Diverted", "WRONG RUNWAY", "STAR!", "CONFLICT", "+25", "SHIFT COMPLETE"]
	for i in POPUP_POOL:
		popup(words[i], Color(1, 0.9, 0.3), Vector2(vp.x * 0.5, vp.y * (0.3 + 0.07 * i)))
	flash(Color(1, 0.1, 0.1))
	set_landed(0, true)

func end_prewarm() -> void:
	_prewarming = false
	_tr_kind = ""
	_tr_t = 99.0
	_apply_transition()
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_over.visible = false
	_menu.visible = false
	_ad.visible = false
	_select.visible = false
	_over_body.visible = false
	_art.show_play = false
	_art.show_result = false
	_art.warm = false
	_art.show_pause = false
	for si in 3:
		_art.slider_rect[si] = Rect2()      # (the pre-warm's sliders were for the warm-up only: the pause layer has the real ones)
	_art.clear_buttons()
	_art.show_wind = false
	_art.chip_finale = ""
	_art.chip_weather = ""
	_art.header_text = ""
	_art.header2_text = ""
	_hdr_on[0] = false
	_hdr_on[1] = false
	_art.cf_on.fill(0)
	_art.unlock_t = -1.0
	_art.res_t = 0.0
	_art.balance = 0
	_art.fines_total_target = 0
	_art.tickets_target = 0
	_clear_tickets()
	_art.bar_shown = 0.0
	_banner_left = 0.0
	_banner_q.clear()
	_art.banner_alpha = 0.0
	_art.banner_text = ""
	_wind_banner.visible = false
	_tip.visible = false
	_tip_q.clear()
	_tipart.tip_alpha = 0.0
	_finale.visible = false
	_finale.text = ""
	_finale_text = ""
	_event_banner.visible = false
	_event_text = ""
	_set_play_labels(false)
	_art.clear_buttons()
	_art.queue_redraw()
	_flash_ms = -10000
	if is_instance_valid(_splash):
		_splash.queue_free()
