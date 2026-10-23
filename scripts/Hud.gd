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
	const SLAM := 0.2
	# ---- the HUD of a running shift ----
	var show_play := false
	var balance := 0                 # the shift's coin total (the target; `bar_shown` rolls towards it)
	var bar_shown := 0.0
	var thresholds := PackedInt32Array([0, 0, 0])   # coins for 1, 2, 3 stars
	var wind_toward := 0.0
	var wind_text := "000"
	var wind_warn := false
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
	var tip_alpha := 0.0
	var tip_glyph := ""
	var tip_text := ""
	var tip_rect := Rect2()
	var details_lines := PackedStringArray()
	# ---- the pause menu ----
	var show_pause := false
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
	var res_unlock := ""             # results: a new airport opened (shown as a card)
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
	const MAX_BTN := 14
	var btn_rect: Array[Rect2] = []
	var btn_id := PackedStringArray()
	var btn_text := PackedStringArray()
	var btn_sub := PackedStringArray()
	var btn_state := PackedInt32Array()
	var btn_stars := PackedInt32Array()      # -1: none, 0..3: stars earned (drawn on cards)
	var btn_icon := PackedInt32Array()       # -1: none, 0..5: an animal pilot portrait, 100+: a theme's colour swatch
	var btn_kind := PackedInt32Array()
	var btn_glyph := PackedStringArray()
	var btn_pips := PackedInt32Array()       # -1: none, else upgrade level (three pips)
	var btn_cost := PackedInt32Array()       # -1: none, 0: "MAX", else a price (coin icon + number)
	var btn_badge := PackedInt32Array()      # round buttons: 0 none, >0 a streak number, -1 a tick (done today)
	var btn_lock := PackedInt32Array()       # cards: >0 a locked card showing a padlock and this many stars needed
	var btn_tint := PackedColorArray()       # colour tiles / card icons: the tile colour (alpha 0 = default)
	var btn_map := PackedInt32Array()        # cards: -1 none, else an airport index: its mini-map is drawn as the icon
	var btn_count := 0

	func _init() -> void:
		for i in MAX_BTN:
			btn_rect.append(Rect2())
		for a in [btn_id, btn_text, btn_sub, btn_glyph]:
			a.resize(MAX_BTN)
		for a in [btn_state, btn_stars, btn_icon, btn_kind, btn_pips, btn_cost, btn_badge, btn_lock, btn_map]:
			a.resize(MAX_BTN)
		btn_tint.resize(MAX_BTN)
		_pts.resize(10)
		fc_pos.resize(10)
		cf_pos.resize(CONFETTI)
		cf_rot.resize(CONFETTI)
		cf_col.resize(CONFETTI)
		cf_size.resize(CONFETTI)
		cf_on.resize(CONFETTI)
		fc_s.resize(10)
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
		_sb_pill = _cream(Style.R_PILL, 4, Style.SURFACE_DARK)
		_sb_sheet = _cream(Style.R_L, 6, Style.SURFACE_DARK)
		_sb_banner = Style.box(Style.SURFACE_DARK, Style.WARNING, Style.R_PILL, 4)
		_sb_tip = Style.box(Style.SURFACE_DARK, Style.SUCCESS, Style.R_PILL, 4)
		_sb_tile = Style.box(Style.PRIMARY, Style.INK, 34, 6, false)
		_sb_tile_lip = Style.box(Style.INK, Style.INK, 34, 0, false)
		_sb_dock = _cream(56, 6, Style.SURFACE_DARK)
		_sb_hdr = _cream(Style.R_PILL, 4, Style.SURFACE_DARK)
		_sb_chip = Style.box(Style.SURFACE_DARK_2, Style.SURFACE_DARK_2, 40, 0, false)
		_sb_card = _cream(52, 8, Style.SURFACE_DARK)
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

	## A panel with its soft highlight: a rounded cap at the top fading down into the face (the style's gradient).
	func panel(sb: StyleBoxFlat, r: Rect2, sheen_sb: StyleBoxFlat = null) -> void:
		draw_style_box(sb, r)
		var sh := sheen_sb if sheen_sb != null else _sheen_m
		var inset := float(sb.border_width_left) + 2.0
		var rad := float(sh.corner_radius_top_left)
		var h := maxf(r.size.y * 0.5 - inset, rad + 2.0)
		var x0 := r.position.x + inset
		var x1 := r.end.x - inset
		var y0 := r.position.y + inset
		draw_style_box(sh, Rect2(x0, y0, x1 - x0, rad))
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

	# ---------- text ----------

	func text(s: String, pos: Vector2, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
		var f := Style.font_for(s, size_px)
		draw_string_outline(f, pos, s, align, width, size_px, maxi(size_px / 8, 4), Color(Style.INK, col.a))
		draw_string(f, pos, s, align, width, size_px, col)

	## Text on a cream surface: brown, no outline.
	func ptext(s: String, pos: Vector2, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
		draw_string(Style.font_for(s, size_px), pos, s, align, width, size_px, col)

	## Text on the primary button: white with a slight dark shadow.
	func btext(s: String, pos: Vector2, size_px: int, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
		var f := Style.display()
		draw_string(f, pos + Vector2(0, 4), s, align, width, size_px, Color(Style.ORANGE_EDGE.r * 0.6, Style.ORANGE_EDGE.g * 0.5, 0.05, 0.5))
		draw_string(f, pos, s, align, width, size_px, Color.WHITE)

	func text_width(s: String, size_px: int) -> float:
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
	func _vignette(r: Rect2, i: int, dim: bool = false) -> void:
		var d: Dictionary = Airports.def(i)
		var water: bool = d.get("water", false)
		var gcol: Color = d["ground"]
		_sb_vig.bg_color = gcol.darkened(0.12) if not water else Color("5db8e0")
		draw_style_box(_sb_vig, r)
		var c := r.get_center()
		var k := r.size.x / 13.0
		for dc in d["decor"]:
			var col: Color = dc["color"]
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
			draw_style_box(_sb_vig_veil, r)

	## A card's icon: an animal pilot portrait, or a theme's two colours.
	func text_l(c: Vector2, r: float, col: Color) -> void:
		draw_string(Style.display(), c + Vector2(-r * 0.45, r * 0.55), "L", HORIZONTAL_ALIGNMENT_CENTER, r * 0.9, int(r * 1.7), col)

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
		return (btn_count > 0 and btn_age < 0.9) or (press_k >= 0 and press_t < Style.T_FAST) or (rel_k >= 0 and rel_t < Style.T_BASE)

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
		btn_map[k] = int(opts.get("map", -1))
		btn_count += 1
		queue_redraw()

	## Index of the button under `pos`, or -1.
	func button_at(pos: Vector2) -> int:
		for k in range(btn_count - 1, -1, -1):      # (a later button is drawn on top, so it gets the tap)
			if btn_rect[k].has_point(pos):
				return k
		return -1

	## Every button pops in (staggered, overshooting) when its screen appears, squashes while pressed and bounces back.
	func _draw_buttons() -> void:
		for k in btn_count:
			var s := 1.0
			var t := (btn_age - minf(float(k), 6.0) * Style.STAGGER) / Style.T_BASE
			if t < 1.0:
				s = Style.ease_out_back(maxf(t, 0.0))
				if s <= 0.01:
					continue
			if press_k == k:
				s *= lerpf(1.0, 0.94, Style.ease_out_cubic(press_t / Style.T_FAST))
			elif rel_k == k and rel_t < Style.T_BASE:
				s *= lerpf(0.94, 1.0, Style.ease_out_back(rel_t / Style.T_BASE))
			if absf(s - 1.0) > 0.001:
				var c := btn_rect[k].get_center()
				draw_set_transform(c * (1.0 - s), 0.0, Vector2(s, s))
			_draw_button(k)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
					draw_style_box(_sb_disabled, face)
				else:
					draw_style_box(_sb_lip, Rect2(face.position.x, face.position.y + Style.LIP, face.size.x, face.size.y))
					if pressed:
						face.position.y += Style.LIP - 2.0
					panel(_sb_primary, face, _sheen_o)
				r = face
				var gw := r.size.y * 0.34 if btn_glyph[k] != "" else 0.0
				var fs := SZ_XL
				while text_width(btn_text[k], fs) + gw > r.size.x - 90.0 and fs > 40:
					fs -= 6
				var tw := text_width(btn_text[k], fs)
				var x0 := r.get_center().x - (tw + gw) * 0.5
				if gw > 0.0:
					glyph(btn_glyph[k], Vector2(x0 + gw * 0.3, r.get_center().y), r.size.y * 0.2, Color.WHITE)
				btext(btn_text[k], Vector2(x0 + gw, r.get_center().y + fs * 0.33), fs)
			8:      # a small orange button ("Fly here"): the same look, smaller
				var face2 := Rect2(r.position.x, r.position.y, r.size.x, r.size.y - 6.0)
				draw_style_box(_sb_lip, Rect2(face2.position.x, face2.position.y + 6.0, face2.size.x, face2.size.y))
				if pressed:
					face2.position.y += 4.0
				panel(_sb_primary, face2, _sheen_o)
				var fs2 := 40
				while text_width(btn_text[k], fs2) > face2.size.x - 40.0 and fs2 > 24:
					fs2 -= 4
				btext(btn_text[k], Vector2(face2.position.x, face2.get_center().y + fs2 * 0.33), fs2, HORIZONTAL_ALIGNMENT_CENTER, face2.size.x)
			3:      # a colour tile (ink border, a lip under it) with a small label under it: the pause buttons
				var tint := btn_tint[k]
				if tint.a <= 0.0:
					tint = Style.PRIMARY
				if st == 1:
					tint = tint.darkened(0.5)
				var side := minf(r.size.x - 20.0, r.size.y - 64.0)
				var tile := Rect2(r.get_center().x - side * 0.5, r.position.y + 4.0, side, side)
				draw_style_box(_sb_tile_lip, Rect2(tile.position + Vector2(0.0, 10.0 if not pressed else 5.0), tile.size))
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
				text(btn_text[k], Vector2(r.position.x - 20.0, r.end.y - 4.0), 24, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0)
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
					draw_style_box(_sb_ghost, r)
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
			6:      # a quiet pill (the rewarded ads): it stays out of the way of the one big button
				draw_style_box(_sb_ghost, r)
				var lw := text_width(btn_text[k], SZ_S)
				var sw := text_width(btn_sub[k], SZ_S) if btn_sub[k] != "" else 0.0
				var lx := r.get_center().x - (lw + sw + (14.0 if sw > 0.0 else 0.0) + 56.0) * 0.5
				glyph(btn_glyph[k], Vector2(lx + 18.0, r.get_center().y), 16.0, ink)
				ptext(btn_text[k], Vector2(lx + 56.0, r.get_center().y + SZ_S * 0.35), SZ_S, ink)
				if sw > 0.0:
					ptext(btn_sub[k], Vector2(lx + 56.0 + lw + 14.0, r.get_center().y + SZ_S * 0.35), SZ_S, C_GOLD_TXT)
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
					draw_style_box(_sb_tile_lip, Rect2(ts.position + Vector2(0, 6.0), ts.size))
					_sb_tile.bg_color = tcol
					draw_style_box(_sb_tile, ts)
					glyph(btn_glyph[k], ts.get_center(), 26.0, Color.WHITE)
				var tx := left + (110.0 if iconed else 0.0)
				var right_w := 220.0 if (btn_cost[k] >= 0 or btn_pips[k] >= 0) else (190.0 if btn_stars[k] >= 0 or btn_lock[k] > 0 else 60.0)
				var tw3 := r.end.x - tx - right_w - 30.0
				var nfs := SZ_M if text_width(btn_text[k], SZ_M) < tw3 else 42
				ptext(btn_text[k], Vector2(tx, cy + (-4.0 if btn_sub[k] != "" else nfs * 0.34)), nfs, ink, HORIZONTAL_ALIGNMENT_LEFT, tw3)
				if btn_sub[k] != "":
					draw_string(Style.body(), Vector2(tx, cy + 40.0), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, tw3, SZ_S, C_SOFT if st != 1 else C_QUIET)
				var rx := r.end.x - 36.0
				if btn_stars[k] >= 0 and btn_lock[k] <= 0:
					for i in 3:
						glyph("star" if i < btn_stars[k] else "star_off", Vector2(rx - 120.0 + i * 60.0, cy), 24.0)
				if btn_lock[k] > 0:
					glyph("lock", Vector2(rx - 250.0, cy), 26.0, C_SOFT)
					ptext("Needs %d" % btn_lock[k], Vector2(rx - 214.0, cy + 11.0), SZ_S, C_GOLD_TXT, HORIZONTAL_ALIGNMENT_LEFT, 140.0)
					glyph("star", Vector2(rx - 38.0, cy), 20.0)
				if btn_pips[k] >= 0:
					for i in 3:
						var pc := Vector2(rx - 130.0 + i * 36.0, cy - 36.0)
						draw_circle(pc, 14.0, Style.INK)
						draw_circle(pc, 11.0, C_GOLD if i < btn_pips[k] else Color(0.86, 0.78, 0.62))
				if btn_cost[k] > 0:
					var cc2 := Vector2(rx - 190.0, cy + 26.0)
					glyph("coin", cc2, 16.0, Color(1, 1, 1, 1.0 if st != 1 else 0.5))
					ptext(str(btn_cost[k]), cc2 + Vector2(26.0, 11.0), SZ_S, C_TEXT if st != 1 else C_QUIET)
				elif btn_cost[k] == 0:
					ptext("MAX", Vector2(rx - 190.0, cy + 38.0), SZ_S, C_GOLD_TXT)
			_:
				panel(_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal), r)
				var gw4 := r.size.y * 0.5 if btn_glyph[k] != "" else 0.0
				var fs4 := SZ_M
				while text_width(btn_text[k], fs4) + gw4 > r.size.x - 50.0 and fs4 > 30:
					fs4 -= 4
				var tw4 := text_width(btn_text[k], fs4)
				var sx := r.get_center().x - (tw4 + gw4) * 0.5
				if btn_glyph[k] != "":
					glyph(btn_glyph[k], Vector2(sx + gw4 * 0.4, r.get_center().y), r.size.y * 0.24, ink)
				ptext(btn_text[k], Vector2(sx + gw4, r.get_center().y + fs4 * 0.34), fs4, ink)

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
		var nfs := 46
		while text_width(btn_text[k], nfs) > avail and nfs > 28:
			nfs -= 3
		ptext(btn_text[k], Vector2(tx, r.position.y + 78.0), nfs, C_TEXT if not locked else C_QUIET, HORIZONTAL_ALIGNMENT_LEFT, avail)
		draw_string(Style.body(), Vector2(tx, r.position.y + 118.0), btn_sub[k], HORIZONTAL_ALIGNMENT_LEFT, avail, 26, C_SOFT if not locked else C_QUIET)
		if not locked:
			for i in 3:
				glyph("star" if i < btn_stars[k] else "star_off", Vector2(tx + 24.0 + i * 58.0, r.end.y - 52.0), 21.0)
			if btn_cost[k] > 0:
				draw_string(Style.text(), Vector2(tx + 200.0, r.end.y - 42.0), "Best %d" % btn_cost[k], HORIZONTAL_ALIGNMENT_LEFT, 200.0, 26, C_SOFT)
		else:
			var pill := Rect2(vig.position.x + 6.0, vig.get_center().y - 30.0, vig.size.x - 12.0, 60.0)
			draw_style_box(_sb_lockpill, pill)
			glyph("lock", Vector2(pill.position.x + 30.0, pill.get_center().y), 15.0, Color.WHITE)
			draw_string(Style.text(), Vector2(pill.position.x + 52.0, pill.get_center().y + 9.0), "Unlock with %d" % btn_lock[k], HORIZONTAL_ALIGNMENT_LEFT, pill.size.x - 56.0, 22, Color.WHITE)
			glyph("star", Vector2(r.end.x - 60.0, cy), 22.0)

	# ---------- the HUD of a shift ----------

	## Two bars in a rounded square.
	func _draw_pause_button() -> void:
		var r := pause_rect
		draw_style_box(_sb_ghost, r)
		glyph("pause", r.get_center() + Vector2(0, -2), r.size.x * 0.28, Style.TEXT)

	func _draw_sliders() -> void:
		for i in 3:
			var r := slider_rect[i]
			var ty := r.get_center().y
			glyph(slider_glyph[i], Vector2(r.position.x - 70.0, ty), 34.0, C_TEXT)
			ptext(slider_name[i], Vector2(r.position.x, ty - 32.0), 26, C_SOFT)
			var track := Rect2(r.position.x, ty - 11.0, r.size.x, 22.0)
			draw_style_box(_sb_slider, track)
			var fx := maxf(r.size.x * slider_val[i], 22.0)
			draw_style_box(_sb_primary_flat(), Rect2(r.position.x, ty - 11.0, fx, 22.0))
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
		draw_style_box(_sb_track, Rect2(x0 - 6.0, y - 5.0, w + 12.0, 24.0))
		var f := clampf(bar_shown / top, 0.0, 1.0)
		if f > 0.0:
			draw_style_box(_sb_fill, Rect2(x0 - 2.0, y - 1.0, maxf(w * f + 4.0, 16.0), 16.0))
		for i in 3:
			var x := x0 + w * float(thresholds[i]) / top
			var lit := balance >= thresholds[i]
			var c := Vector2(x, y + 7.0)
			var k := star_t[i] / 0.6 if star_t[i] >= 0.0 else 1.0
			if k < 1.0:
				var s := Style.ease_out_back(minf(k * 1.4, 1.0))
				draw_set_transform(c * (1.0 - s), 0.0, Vector2(s, s))
				glyph("star", c, 24.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				_sparks(c, k, 22.0, 60.0, 8, Style.ACCENT)
			else:
				glyph("star" if lit else "star_off", c, 24.0 if lit else 20.0)

	## The wind card (top-right): a cream card with an arrow showing where the air is going and its direction number.
	func _draw_wind() -> void:
		var card := Rect2(size.x - 24.0 - right - 132.0, 20.0 + top, 132.0, 150.0)
		var flash := wind_warn and int(Time.get_ticks_msec() / 250.0) % 2 == 0
		draw_style_box(_sb_accent if flash else _sb_normal, card)
		var c := card.get_center() + Vector2(0, -22.0)
		var d := Vector2(sin(deg_to_rad(wind_toward)), -cos(deg_to_rad(wind_toward)))
		var n := Vector2(-d.y, d.x)
		draw_line(c - d * 28.0, c + d * 8.0, Style.TEXT, 9.0)
		tri(c + d * 36.0, c + d * 6.0 + n * 18.0, c + d * 6.0 - n * 18.0, Style.TEXT)
		ptext(wind_text, Vector2(card.position.x, card.end.y - 22.0), 28, C_GOLD_TXT if wind_warn else C_SOFT, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)

	## A status pill under the star bar: a glyph and a few characters.
	func _pill(c: Vector2, g: String, s: String, size_px: int, col: Color) -> void:
		var tw := text_width(s, size_px)
		var h := float(size_px) * 1.35
		var w := tw + h * 1.3
		draw_style_box(_sb_pill, Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h))
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
		draw_style_box(_sb_plate, Rect2(size.x * 0.5 - 215.0, 4.0 + top, 430.0, 206.0))       # the timer and coins sit on one soft pill
		_draw_pause_button()
		if mode_glyph != "":
			glyph(mode_glyph, Vector2(50.0, 146.0), 26.0, C_SOFT)
		_draw_star_bar()
		var y := 300.0 + top
		if chip_finale != "":
			_pill(Vector2(size.x * 0.5, y), "plane", chip_finale, SZ_M, C_RED if chip_finale_red else C_TEXT)
			y += 86.0
		if chip_weather != "":
			_pill(Vector2(size.x * 0.5, y), chip_weather_glyph, chip_weather, SZ_S, C_GOLD)
		if show_wind:
			_draw_wind()
		if coin_icon.x > 0.0:
			glyph("coin", coin_icon, 34.0)

	## The single banner and the tip: a pill with a glyph and one line (drawn here so the text sits on top of its pill).
	func _draw_pills() -> void:
		if not show_play or show_pause:
			return
		if banner_alpha > 0.01 and banner_text != "":
			var r := banner_rect
			_sb_banner.bg_color.a = banner_alpha
			_sb_banner.border_color = Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha)
			draw_style_box(_sb_banner, r)
			var x := r.position.x + 40.0
			if banner_glyph != "":
				glyph(banner_glyph, Vector2(x + 30.0, r.get_center().y), 30.0, Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha))
				x += 84.0
			var bfs := SZ_M
			while text_width(banner_text, bfs) > r.end.x - x - 40.0 and bfs > 28:
				bfs -= 4
			ptext(banner_text, Vector2(x, r.get_center().y + bfs * 0.34), bfs, Color(Style.TEXT.r, Style.TEXT.g, Style.TEXT.b, banner_alpha))
		if tip_alpha > 0.01 and tip_text != "":
			var r2 := tip_rect
			_sb_tip.bg_color.a = tip_alpha
			_sb_tip.border_color = Color(Style.SUCCESS, tip_alpha)
			draw_style_box(_sb_tip, r2)
			var x2 := r2.position.x + 40.0
			if tip_glyph != "":
				glyph(tip_glyph, Vector2(x2 + 28.0, r2.get_center().y), 28.0, Color(Style.TEXT, tip_alpha))
				x2 += 84.0
			draw_string(Style.body(), Vector2(x2, r2.get_center().y + SZ_S * 0.35), tip_text, HORIZONTAL_ALIGNMENT_LEFT, r2.end.x - x2 - 20.0, SZ_S, Color(Style.TEXT, tip_alpha))

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
			draw_string(Style.text(), Vector2(details_rect.position.x + 40.0, y), parts[0], HORIZONTAL_ALIGNMENT_LEFT, details_rect.size.x - 80.0, SZ_S, C_TEXT if last else C_SOFT)
			if parts.size() > 1:
				draw_string(Style.text(), Vector2(details_rect.position.x + 40.0, y), parts[1], HORIZONTAL_ALIGNMENT_RIGHT, details_rect.size.x - 80.0, SZ_S, C_GOLD_TXT if last else C_TEXT)

	func _draw_results() -> void:
		var cx := size.x * 0.5
		if details_open:
			_draw_details()
			return
		var s2 := size.y / 1920.0                 # (positions below are for a 1080 x 1920 screen)
		# The title (over the field, cream on a warm extrusion) and where we were.
		var tfs := 104
		while text_width("SHIFT COMPLETE", tfs) > 1000.0 and tfs > 50:
			tfs -= 4
		Style.draw_ext(self, Vector2(cx - 520.0, 290.0 * s2 + top), "SHIFT COMPLETE", tfs, HORIZONTAL_ALIGNMENT_CENTER, 1040.0)
		if res_sub != "":
			text(res_sub, Vector2(cx - 520.0, 350.0 * s2 + top), SZ_S, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 1040.0)
		# The stars, one after another: each slams down from big with an impact ring, rays and a little shake. Three, big and tilted.
		for i in 3:
			var t0 := STAR_T0 + STAR_GAP * i
			var rot := (i - 1) * deg_to_rad(12.0)
			var rad := 150.0 if i == 1 else 118.0
			var c := Vector2(cx + (i - 1) * 285.0, (520.0 if i == 1 else 580.0) * s2 + top)
			star(c, rad, Color(Style.WORLD_TEXT), true, rot)
			if i < res_stars and res_t >= t0:
				var k := clampf((res_t - t0) / SLAM, 0.0, 1.0)
				var imp := res_t - t0 - SLAM
				var jit := Vector2.ZERO
				if imp >= 0.0 and imp < 0.22:
					jit = Vector2(sin(imp * 160.0), cos(imp * 190.0)) * 9.0 * (1.0 - imp / 0.22)
				star(c + jit, rad * lerpf(2.6, 1.0, Style.ease_out_cubic(k)), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.35 + 0.65 * k), true, rot)
				if imp >= 0.0 and imp < 0.5:
					_sparks(c, imp / 0.5, rad, rad * 3.0, 10, C_GOLD)
		# The card: NEW BEST, the total paid (rolling up once the stars are in), and three chips.
		var card := Rect2(cx - 465.0, 750.0 * s2 + top, 930.0, 590.0 * s2)
		panel(_sb_card, card, _sheen_l)
		var t_count := STAR_T0 + STAR_GAP * 3.0
		var f := clampf((res_t - t_count) / 1.0, 0.0, 1.0)
		var shown := roundi(res_total * (1.0 - pow(1.0 - f, 3.0)))
		var label := "+%d" % shown
		var bfs := 150
		while text_width(label, bfs) > 560.0 and bfs > 80:
			bfs -= 10
		var tw := text_width(label, bfs)
		var ty := card.position.y + 230.0 * s2
		glyph("coin", Vector2(cx - tw * 0.5 - 76.0, ty - 62.0), 54.0)
		Style.draw_ext(self, Vector2(cx - tw * 0.5, ty), label, bfs, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Style.ACCENT if not res_doubled else Style.SUCCESS.lightened(0.2), 5)
		if res_doubled:
			ptext("x2", Vector2(cx + tw * 0.5 + 24.0, ty), SZ_M, Style.SUCCESS_DARK)
		var k2 := clampf((res_t - (t_count + 1.0)) / 0.4, 0.0, 1.0)
		if res_new_best:       # a red tag stuck on the card's top edge
			var tagr := Rect2(-140.0, -34.0, 280.0, 68.0)
			draw_set_transform(Vector2(cx, card.position.y), deg_to_rad(-3.0), Vector2(k2, k2))
			draw_style_box(_sb_tag, tagr)
			draw_string(Style.text(), Vector2(-140.0, 14.0), "NEW BEST", HORIZONTAL_ALIGNMENT_CENTER, 280.0, 36, Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif res_best > 0:
			ptext("best %d" % res_best, Vector2(cx - 300.0, card.position.y + 60.0), SZ_S, Color(C_QUIET.r, C_QUIET.g, C_QUIET.b, k2), HORIZONTAL_ALIGNMENT_CENTER, 600.0)
		var cw := (card.size.x - 90.0 - 36.0) / 3.0
		for j in 3:
			var cr := Rect2(card.position.x + 45.0 + j * (cw + 18.0), card.position.y + 290.0 * s2, cw, 150.0)
			draw_style_box(_sb_chip, cr)
			var v := res_chips[j]
			var colr := C_TEXT if j == 0 else (Style.SUCCESS_DARK if j == 1 else Color("b8322a"))
			var sign := "+" if v >= 0 and j < 2 else ("" if j < 2 else "\u2212")
			draw_string(Style.display(), Vector2(cr.position.x, cr.position.y + 80.0), "%s%d" % [sign, absi(v)], HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 54, colr)
			draw_string(Style.text(), Vector2(cr.position.x, cr.position.y + 126.0), ["Landings", "Early clear", "Fines"][j], HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, SZ_S, C_SOFT)
		# A new airport opened with this shift.
		if res_unlock != "":
			var ur := Rect2(cx - 465.0, 1370.0 * s2 + top, 930.0, 130.0)
			draw_style_box(_sb_unlock, ur)
			_minimap(Vector2(ur.position.x + 90.0, ur.get_center().y), 50.0, Airports.index_of(res_unlock))
			ptext("%s unlocked!" % res_unlock, Vector2(ur.position.x + 170.0, ur.get_center().y - 4.0), 40, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, ur.size.x - 200.0)
			draw_string(Style.body(), Vector2(ur.position.x + 170.0, ur.get_center().y + 40.0), Airports.tag(Airports.index_of(res_unlock)), HORIZONTAL_ALIGNMENT_LEFT, ur.size.x - 200.0, SZ_S, C_SOFT)

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
		var tag_w := 520.0
		draw_style_box(_sb_pill, Rect2(x0, y0 - 40.0, tag_w, 64.0))
		draw_string(Style.text(), Vector2(x0, y0 + 2.0), "AIR TRAFFIC CONTROL", HORIZONTAL_ALIGNMENT_CENTER, tag_w, 28, Style.TEXT)
		draw_set_transform(Vector2(x0, y0), deg_to_rad(2.0), Vector2.ONE)
		Style.draw_ext(self, Vector2(0.0, 150.0), "PATTERN", 150, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Style.WORLD_TEXT, 7)
		Style.draw_ext(self, Vector2(0.0, 300.0), "WORK", 150, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Style.WORLD_TEXT, 7)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if lockup_airport != "":
			var nw := text_width(lockup_airport, 34)
			var pr := Rect2(x0, y0 + 360.0, nw + 250.0, 76.0)
			draw_style_box(_sb_pill, pr)
			ptext(lockup_airport, Vector2(pr.position.x + 32.0, pr.get_center().y + 12.0), 34, C_TEXT)
			for i in 3:
				glyph("star" if i < lockup_stars else "star_off", Vector2(pr.end.x - 128.0 + i * 44.0, pr.get_center().y), 16.0)

	## The intro: the studio mark (a propeller that spins up and settles) and wordmark pop in and out, then the game's
	## name lands with a little plane across it.
	func _draw_logo() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5 - 60.0
		var t := logo_t
		if t < 1.0:
			var k := Style.ease_out_back(t / 0.45)
			var a := clampf(minf(t / 0.2, (1.0 - t) / 0.2), 0.0, 1.0)
			draw_set_transform(Vector2(cx, cy) * (1.0 - k), 0.0, Vector2(k, k))
			Style.draw_mark(self, Vector2(cx, cy - 40.0), 110.0, (1.0 - Style.ease_out_cubic(t / 0.9)) * TAU * 2.0, a)
			Style.draw_wordmark(self, cx, cy + 150.0, SZ_M, a)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		var u := t - 1.0
		var a2 := clampf(1.0 - (t - 2.4) / 0.3, 0.0, 1.0)
		for w in 2:
			var word: String = ["PATTERN", "WORK"][w]
			var k2 := Style.ease_out_back((u - 0.12 * w) / 0.45)
			if k2 <= 0.01:
				continue
			var c := Vector2(cx, cy - 40.0 + w * 150.0)
			draw_set_transform(c * (1.0 - k2), 0.0, Vector2(k2, k2))
			Style.draw_ext(self, Vector2(cx - 500.0, c.y), word, 120, HORIZONTAL_ALIGNMENT_CENTER, 1000.0, Style.WORLD_TEXT if w == 0 else Style.ACCENT, 6, a2)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
			draw_set_transform(cf_pos[i], cf_rot[i], Vector2.ONE)
			draw_rect(Rect2(-cf_size[i] * 0.5, cf_size[i]), cf_col[i])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## The new-airport reveal: a dimmed screen, a card that pops in, a padlock that springs open with a burst.
	func _draw_unlock() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5 - 120.0
		var a := clampf(unlock_t / 0.25, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(Style.SCRIM, 0.78 * a))
		var k := Style.ease_out_back(unlock_t / 0.45)
		draw_set_transform(Vector2(cx, cy) * (1.0 - k), 0.0, Vector2(k, k))
		var card := Rect2(cx - 430.0, cy - 340.0, 860.0, 680.0)
		panel(_sb_sheet, card, _sheen_l)
		draw_string(Style.text(), Vector2(cx - 400.0, cy - 40.0), "NEW AIRPORT", HORIZONTAL_ALIGNMENT_CENTER, 800.0, SZ_S, C_GOLD_TXT)
		var ufs := SZ_XL
		while text_width(unlock_name, ufs) > 780.0 and ufs > 40:
			ufs -= 6
		ptext(unlock_name, Vector2(cx - 420.0, cy + 90.0), ufs, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 840.0)
		draw_string(Style.body(), Vector2(cx - 400.0, cy + 170.0), "ready for flights", HORIZONTAL_ALIGNMENT_CENTER, 800.0, SZ_S, Style.TEXT_SOFT)
		# The padlock: the shackle pops up and swings open at 0.55 s.
		var lc := Vector2(cx, cy - 190.0)
		var open := Style.ease_out_back(clampf((unlock_t - 0.55) / 0.35, 0.0, 1.0))
		var gold := Style.ACCENT
		draw_arc(lc + Vector2(-36.0 * open, -44.0 - 30.0 * open), 52.0, PI, TAU - 1.0 * open, 20, Color(Style.INK, 1.0), 30.0)
		draw_arc(lc + Vector2(-36.0 * open, -44.0 - 30.0 * open), 52.0, PI, TAU - 1.0 * open, 20, Color(0.85, 0.88, 0.95), 18.0)
		draw_rect(Rect2(lc.x - 78.0, lc.y - 44.0, 156.0, 124.0), Color(Style.INK, 1.0))
		draw_rect(Rect2(lc.x - 70.0, lc.y - 36.0, 140.0, 108.0), gold)
		draw_circle(lc + Vector2(0, 14.0), 14.0, Color(Style.ACCENT_DARK, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var sp := (unlock_t - 0.55) / 0.7
		if sp >= 0.0 and sp < 1.0:
			_sparks(lc + Vector2(0, -60.0), sp, 60.0, 280.0, 12, Style.ACCENT)

	func _draw() -> void:
		var t_start := Time.get_ticks_usec()
		_draw_all()
		last_draw_us = Time.get_ticks_usec() - t_start

	func _draw_all() -> void:
		if logo_t >= 0.0:
			_draw_logo()
			return
		if lockup:
			_draw_lockup()
		if header_text != "":
			var hw := text_width(header_text, 46)
			var pr := Rect2(size.x - 36.0 - right - hw - 118.0, 20.0 + top, hw + 118.0, 84.0)
			draw_style_box(_sb_hdr, pr)
			glyph(header_glyph, Vector2(pr.position.x + 50.0, pr.get_center().y), 25.0)
			ptext(header_text, Vector2(pr.position.x + 92.0, pr.get_center().y + 16.0), 46, C_TEXT)
		if header2_text != "":
			var hw2 := text_width(header2_text, 46)
			var pr2 := Rect2(36.0 + left, 20.0 + top, hw2 + 118.0, 84.0)
			draw_style_box(_sb_hdr, pr2)
			glyph(header2_glyph, Vector2(pr2.position.x + 50.0, pr2.get_center().y), 25.0)
			ptext(header2_text, Vector2(pr2.position.x + 92.0, pr2.get_center().y + 16.0), 46, C_TEXT)
		if show_pause and pause_card.size.x > 0.0:
			panel(_sb_sheet, pause_card, _sheen_l)
		if show_result:
			_draw_results()
		if unlock_t >= 0.0:
			_draw_unlock()
		_draw_buttons()
		if show_play and not show_pause:
			_draw_hud()
		elif show_play and show_pause:
			pass
		if show_pause:
			_draw_sliders()
		_draw_pills()
		_draw_confetti()
		for i in fc_s.size():
			if fc_s[i] > 0.01:
				glyph("coin", fc_pos[i], 26.0 * fc_s[i])

var _art: Art
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
var _wind_posted := false
var _last_bal := 0
var daily_streak := 0
var daily_done := false
var bad_streak := 0
var bad_done := false
var mode := ""                 # "", "daily" or "bad": a small badge on the HUD

func _ready() -> void:
	layer = 2
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
	add_child(_art)
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
	_wind_banner.offset_top = 470
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

# ---------- Header numbers (they roll) ----------

var _star_lit: Array[bool] = [false, false, false]
var _slam_next := 0
var _confetti_done := false
var _cf_vel := PackedVector2Array()
var _cf_spin := PackedFloat32Array()
var _cf_rng := RandomNumberGenerator.new()
var _unlock_pending := ""
const UNLOCK_AT := 3.6        # results seconds: after the stars and the total have landed
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
const DEPTH := {"menu": 0.0, "select": 1.0, "upgrades": 1.0, "list": 1.0, "play": 2.0, "results": 3.0, "pause": 2.5, "ad": 2.5}
const POP_KINDS := ["results", "pause", "ad"]
var _tr_t := 99.0
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
	if _prewarming or kind == _tr_kind:
		_tr_kind = kind
		return
	_hdr_on[0] = false
	_hdr_on[1] = false
	var d: float = DEPTH.get(kind.get_slice(":", 0), 0.0)
	_tr_dir = 0 if kind in POP_KINDS else int(signf(d - _tr_depth))
	_tr_depth = d
	_tr_kind = kind
	_tr_t = 0.0
	_art.btn_age = 0.0
	_art.press_k = -1
	_art.rel_k = -1
	_apply_transition()
	transition_started.emit(_tr_dir)

func transition_kind() -> String:
	return _tr_kind

func transition_dir() -> int:
	return _tr_dir

func transitioning() -> bool:
	return _tr_t < Style.T_BASE

func _apply_transition() -> void:
	var k := clampf(_tr_t / Style.T_BASE, 0.0, 1.0)
	var e := Style.ease_out_cubic(k)
	var a := clampf(_tr_t / (Style.T_BASE * 0.7), 0.0, 1.0)
	if k >= 1.0:
		transform = Transform2D.IDENTITY
		a = 1.0
	elif _tr_dir != 0:
		transform = Transform2D(0.0, Vector2.ONE, 0.0, Vector2(_tr_dir * SLIDE * (1.0 - e), 0.0))
	else:
		var sc := lerpf(0.9, 1.0, Style.ease_out_back(k))
		var vp := get_viewport().get_visible_rect().size
		transform = Transform2D(0.0, Vector2(sc, sc), 0.0, vp * 0.5 * (1.0 - sc))
	for n in _tr_nodes:
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
	_hide_all_screens()
	_art.clear_buttons()
	_logo_bg.visible = true
	_logo_bg.color.a = 1.0
	_logo_sent = false
	_art.logo_t = 0.0
	_art.queue_redraw()

func logo_active() -> bool:
	return _art.logo_t >= 0.0

func skip_logo() -> void:
	if _art.logo_t >= 0.0 and _art.logo_t < LOGO_END:
		_art.logo_t = LOGO_END

func _tick_logo(delta: float) -> void:
	if _art.logo_t < 0.0:
		return
	_art.logo_t += delta
	if _art.logo_t >= LOGO_END and not _logo_sent:
		_logo_sent = true
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
	_art.top = t
	_art.left = Style.safe_left
	_art.right = Style.safe_right
	_art.pause_rect = Rect2(Style.GUTTER * 0.5 + Style.safe_left, 10.0 + t, 80.0, 80.0)
	_score.offset_top = 56 + t
	_best.offset_top = 6 + t
	_wind_banner.offset_top = 470 + t
	_select_title.offset_top = 40 + t
	_tip.offset_top = -270 - Style.safe_bottom
	_tip.offset_bottom = -190 - Style.safe_bottom
	if _stamp != null:
		refresh_stamp()
	_art.queue_redraw()

## A finger is down on a button: it draws pushed in (and the activation follows at once).
func press(pos: Vector2) -> void:
	_art.press_k = _art.button_at(pos)
	_art.press_t = 0.0
	_art.rel_k = -1
	_art.queue_redraw()

func release() -> void:
	if _art.press_k != -1:
		_art.rel_k = _art.press_k
		_art.rel_t = 0.0
		_art.press_k = -1
		_art.queue_redraw()

func pressed_id() -> String:
	return _art.btn_id[_art.press_k] if _art.press_k >= 0 else ""

func _label(size: int, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l: Label = ExtLabel.new() if size >= SZ_M else Label.new()       # display text is cream on a warm extrusion (see ExtLabel)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", Style.display() if size >= SZ_M else Style.text())
	l.add_theme_color_override("font_color", Style.WORLD_TEXT)
	l.add_theme_color_override("font_outline_color", Style.EXT_BOTTOM if size >= SZ_M else Style.INK)
	l.add_theme_constant_override("outline_size", 4 if size >= SZ_M else maxi(size / 8, 4))
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
		_art.tip_alpha = 0.0

# ---------- Pause ----------

## The pause menu: a heavy shade over everything, a title and the primary RESUME button; the volume sliders and the
## two small icon buttons are drawn by the art layer.
func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pause)
	_shade(_pause, 0.6)
	var title := _label(SZ_XL, HORIZONTAL_ALIGNMENT_CENTER, _pause)
	title.text = "PAUSED"
	_centered(title, -600, -450)
	_pause.visible = false

func show_pause(sound: float, music: float, ambience: float = 0.8) -> void:
	_go("pause")
	var vp := get_viewport().get_visible_rect().size
	_pause.visible = true
	_art.show_pause = true
	_set_play_labels(false)
	_art.slider_rect[1] = Rect2(vp.x * 0.5 - 250.0, vp.y * 0.5 - 70.0, 620.0, 80.0)       # music on top, then effects, then ambience
	_art.slider_rect[0] = Rect2(vp.x * 0.5 - 250.0, vp.y * 0.5 + 60.0, 620.0, 80.0)
	_art.slider_rect[2] = Rect2(vp.x * 0.5 - 250.0, vp.y * 0.5 + 190.0, 620.0, 80.0)
	_art.pause_card = Rect2(vp.x * 0.5 - 440.0, vp.y * 0.5 - 150.0, 880.0, 470.0)
	_art.slider_val[0] = sound
	_art.slider_val[1] = music
	_art.slider_val[2] = ambience
	_art.clear_buttons()
	_art.add_button("resume", "RESUME", Rect2(vp.x * 0.5 - 420.0, vp.y * 0.5 - 420.0, 840.0, 230.0), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	_art.add_button("restart", "Restart", Rect2(vp.x * 0.5 - 330.0, vp.y * 0.5 + 350.0, 220.0, 260.0), 0, "", -1, -1, {"kind": 3, "glyph": "restart", "tint": Style.PRIMARY})
	_art.add_button("quit", "Menu", Rect2(vp.x * 0.5 + 110.0, vp.y * 0.5 + 350.0, 220.0, 260.0), 0, "", -1, -1, {"kind": 3, "glyph": "home", "tint": Style.DANGER})
	_art.queue_redraw()

func hide_pause() -> void:
	if _tr_kind == "pause":
		_tr_kind = "play"
		_tr_depth = 2.0
	_pause.visible = false
	_art.show_pause = false
	_art.clear_buttons()
	if _art.show_play:
		_set_play_labels(true)
	_art.queue_redraw()

func pause_visible() -> bool:
	return _pause.visible

## Is this screen position on the pause button (a little generous for a finger)?
func pause_hit(pos: Vector2) -> bool:
	return _art.show_play and not _art.show_pause and _art.pause_rect.grow(6.0).has_point(pos)

## Which volume slider (0 sound, 1 music) is at `pos`; -1 for none.
func slider_at(pos: Vector2) -> int:
	if not _art.show_pause:
		return -1
	for i in 3:
		if _art.slider_rect[i].grow_individual(40.0, 20.0, 40.0, 20.0).has_point(pos):
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
	_menu.visible = false
	_over.visible = false
	_select.visible = false
	_pause.visible = false
	_art.show_pause = false
	_art.show_play = false
	_art.show_result = false
	_art.show_wind = false
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
	_over_head.text = header
	var total_line := "Total paid|+%d%s" % [coins_earned, " (doubled)" if doubled else ""]
	_over_body.text = (reason + "\n" + total_line + "\nBank|%d" % coins_total).replace("|", " ")
	_art.res_stars = shift.stars()
	_art.res_total = coins_earned
	_art.res_new_best = new_best
	_art.res_best = best
	_art.res_doubled = doubled
	_art.res_chips[0] = shift.earned + shift.bonus
	_art.res_chips[1] = shift.time_bonus
	_art.res_chips[2] = shift.fines + shift.overtime_penalty
	_art.res_sub = "%s \u00b7 %d landed%s" % [Airports.airport_name(), shift.landed, (" \u00b7 cleared %d s early" % shift.early_seconds) if shift.early_seconds > 0 else ""]
	_art.res_unlock = ""
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
	_set_header(0, "coin", coins_total, coins_total - coins_earned, 1.8)
	_art.queue_redraw()
	_over.visible = true

## Results: the two rewarded offers (small, under the one clear PLAY AGAIN button), and the Details / Menu buttons.
## A zero amount leaves that offer out.
func set_results_ads(double_coins: int, refund: int) -> void:
	_art.clear_buttons()
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var s2 := vp.y / 1920.0
	_art.add_button("details", "Details", Rect2(cx - 150.0, 750.0 * s2 + 590.0 * s2 - 100.0 + Style.safe_top, 300.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "chev_up" if _art.details_open else "chev_down"})
	_art.add_button("again", "Next shift", Rect2(cx - 450.0, vp.y - 380.0 - Style.safe_bottom, 900.0, 250.0), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	var n := (1 if double_coins > 0 else 0) + (1 if refund > 0 else 0)
	var pw := 560.0 if n == 1 else 440.0
	var x := cx - (n * pw + (n - 1) * 20.0) * 0.5
	if double_coins > 0:
		_art.add_button("ad_double", "Watch to double", Rect2(x, vp.y - 112.0 - Style.safe_bottom, pw, 76.0), 0, "+%d" % double_coins, -1, -1, {"kind": 6, "glyph": "ad"})
		x += pw + 20.0
	if refund > 0:
		_art.add_button("ad_refund", "Refund fine", Rect2(x, vp.y - 112.0 - Style.safe_bottom, pw, 76.0), 0, "+%d" % refund, -1, -1, {"kind": 6, "glyph": "ad"})
	_art.add_button("menu", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "home"})
	_art.queue_redraw()

## "Details": show / hide the full breakdown.
func toggle_details() -> void:
	_art.details_open = not _art.details_open
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
	return _art.res_t >= 4.0

# ---------- Lists ----------

## The airport select screen: one big card per airport, with just its name, stars and lock state.
func show_select(total_stars: int, open: PackedByteArray, stars: PackedInt32Array, _best_scores: PackedInt32Array, selected: int) -> void:
	_go("select")
	_hide_all_screens()
	_select.visible = true
	_select_title.text = "AIRPORTS"
	_set_header(0, "star", total_stars)
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
	for i in Airports.COUNT:
		var r := Rect2(40.0, 150.0 + Style.safe_top + i * 252.0, vp.x - 80.0, 236.0)
		if open[i] != 0:
			var best := _best_scores[i] if i < _best_scores.size() else 0
			_art.add_button("pick:%d" % i, Airports.airport_name(i), r, 2 if i == selected else 0, Airports.tag(i), stars[i], -1, {"kind": 1, "map": i, "cost": maxi(best, 0)})
			if i == selected:
				_art.add_button("airport:%d" % i, "Fly here", Rect2(r.end.x - 270.0, r.get_center().y - 52.0, 240.0, 104.0), 0, "", -1, -1, {"kind": 8})
		else:
			_art.add_button("locked:%d" % i, Airports.airport_name(i), r, 1, Airports.tag(i), -1, -1, {"kind": 1, "map": i, "lock": Airports.unlock_stars(i)})
	_art.queue_redraw()

## A generic list screen: optional tab chips, then cards {id, title, sub, state, stars, icon, cost}, then Back.
func show_list(title: String, coins: int, tabs: Array, cards: Array) -> void:
	_go("list:" + title)
	_hide_all_screens()
	_select.visible = true
	_select_title.text = title
	_set_header(0, "coin", coins)
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	_art.add_button("back", "", Rect2(10.0 + Style.safe_left, 10.0 + Style.safe_top, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
	var y := 130.0 + Style.safe_top
	if not tabs.is_empty():
		var w := (vp.x - 80.0 - 20.0 * (tabs.size() - 1)) / tabs.size()
		for k in tabs.size():
			_art.add_button(tabs[k]["id"], tabs[k]["title"], Rect2(40.0 + k * (w + 20.0), y, w, 90.0), 2 if tabs[k]["selected"] else 0)
		y += 120.0
	for c in cards:
		_art.add_button(c["id"], c["title"], Rect2(40.0, y, vp.x - 80.0, 160.0), c["state"], c["sub"], c.get("stars", -1), c.get("icon", -1), {"kind": 1, "cost": c.get("cost", -1), "glyph": c.get("glyph", "")})
		y += 176.0
	_art.queue_redraw()

## The upgrade shop: a card per upgrade with an icon, its name, one line of effect, level pips and the next price.
func show_upgrades(coins: int, levels: PackedInt32Array) -> void:
	_go("upgrades")
	_hide_all_screens()
	_select.visible = true
	_select_title.text = "UPGRADES"
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

func hide_screens() -> void:
	_hide_all_screens()
	_ad.visible = false
	_art.clear_buttons()

## The menu: one primary PLAY button, the current airport under the title, and a row of round icon buttons.
func show_menu(airport_name: String, coins: int, stars: int, _best_coins: int, _tag: String = "", airport_stars: int = 0) -> void:
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
	var row2 := Rect2(cx - 450.0, vp.y - 40.0 - sb - 150.0, 436.0, 150.0)
	var play := Rect2(cx - 450.0, row2.position.y - 30.0 - 250.0, 900.0, 250.0)
	_art.lockup = true
	_art.lockup_airport = airport_name
	_art.lockup_stars = airport_stars
	_art.add_button("play", "Start shift", play, 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	_art.add_button("airports", "Airports", row2, 0, "", -1, -1, {"kind": 0, "glyph": "airport"})
	_art.add_button("bad", "Bad pilot day", Rect2(row2.position.x + 464.0, row2.position.y, 436.0, 150.0), 0, "", -1, -1, {"kind": 0, "glyph": "bad"})
	var items := [["upgrades", "Upgrades", "upgrades", 0], ["shop", "Hangar", "hangar", 0], ["daily", "Daily", "sun", -1 if daily_done else (daily_streak if daily_streak > 0 else -2)]]
	for k in items.size():
		_art.add_button(items[k][0], items[k][1], Rect2(vp.x - 36.0 - Style.safe_right - 130.0, 150.0 + Style.safe_top + k * 176.0, 130.0, 160.0), 0, "", -1, -1, {"kind": 7, "glyph": items[k][2], "badge": items[k][3]})
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
	_art.tip_alpha = 0.0
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
	_art.star_t.fill(-1.0)
	_art.cf_on.fill(0)
	set_landed(0)
	set_timer(int(Tuning.par_eff()))
	_art.balance = 0
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
func set_wind(from_deg: float, toward_deg: float) -> void:
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
	_coin_target = bal
	_art.balance = bal
	_score.add_theme_color_override("font_color", C_RED if bal < 0 else Color.WHITE)
	for i in 3:
		_art.thresholds[i] = shift.thresholds[i]
		var lit := bal >= shift.thresholds[i]
		if lit and not _star_lit[i] and _art.show_play:
			_art.star_t[i] = 0.0
			star_reached.emit(i)
		_star_lit[i] = lit
	_art.queue_redraw()
	if bal != _last_bal:
		_last_bal = bal
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
	_art.banner_rect = Rect2(vp.x * 0.5 - (tw + 84.0 + 80.0) * 0.5, 470.0 + Style.safe_top, tw + 84.0 + 80.0, 90.0)
	_art.banner_alpha = 0.0

func banner_text() -> String:
	return _wind_banner.text if _wind_banner.visible else ""

## A tip: an icon and one short line, shown once. Only one at a time; the next waits its turn.
func show_tip(text: String, glyph: String = "") -> void:
	if _tip.visible:
		_tip_q.append([text, glyph])
		if _tip_q.size() > 2:
			_tip_q.pop_front()
		return
	_start_tip(text, glyph)

func _start_tip(text: String, glyph: String) -> void:
	_tip.text = text
	_tip.visible = true
	_tip_until = Time.get_ticks_msec() + int(Tuning.tip_seconds * 1000.0)
	var vp := get_viewport().get_visible_rect().size
	_art.tip_glyph = glyph
	_art.tip_text = text
	var tfont := _tip.get_theme_font("font")
	var tw := tfont.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SZ_S).x
	var pw := minf(tw + (84.0 if glyph != "" else 0.0) + 90.0, vp.x - 60.0)
	_art.tip_rect = Rect2(vp.x * 0.5 - pw * 0.5, vp.y - 280.0 - Style.safe_bottom, pw, 100.0)
	_art.tip_alpha = 1.0

## A quick colour wash over the whole screen.
func flash(color: Color) -> void:
	_flash.color = Color(color.r, color.g, color.b, 0.0)
	_flash_ms = Time.get_ticks_msec()

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
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
			_art.tip_alpha = 0.0
			_art.queue_redraw()
			if not _tip_q.is_empty():
				var tq: Array = _tip_q.pop_front()
				_start_tip(tq[0], tq[1])
		else:
			var ta := clampf(left / 600.0, 0.0, 1.0)
			_art.tip_alpha = ta
			_art.queue_redraw()
	# Screen transition, button motion, rolling header totals, coins in flight.
	if _tr_t < Style.T_BASE:
		_tr_t += delta
		_apply_transition()
	if _art.btn_age < 2.0:
		_art.btn_age += delta
	if _art.press_k >= 0:
		_art.press_t += delta
	if _art.rel_k >= 0 and _art.rel_t < 1.0:
		_art.rel_t += delta
	if _art.animating():
		_art.queue_redraw()
	_roll_headers(delta)
	_update_coins(delta)
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
	_stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stamp.offset_left = 12
	_stamp.modulate = Color(1, 1, 1, 0.45)
	_stamp.add_theme_font_override("font", Style.text())
	refresh_stamp()
	if DebugFlags.perf_enabled():
		_perf_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT)
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
	_art.thresholds[0] = 100
	_art.thresholds[1] = 200
	_art.thresholds[2] = 300
	_art.balance = 150
	_art.bar_shown = 150.0
	_art.show_play = true
	_art.show_result = true
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
	show_select(14, open, st, PackedInt32Array([12, 5, 0, 9, 0, 33]), 1)
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
	var row := 0
	for face in 2:
		for sz in [SZ_S, SZ_M, SZ_XL]:
			var wl := Label.new()
			wl.text = ascii
			wl.add_theme_font_size_override("font_size", sz)
			wl.add_theme_font_override("font", Style.display() if face == 0 else Style.text())
			wl.add_theme_color_override("font_outline_color", Style.INK)
			wl.add_theme_constant_override("outline_size", maxi(sz / 8, 4))
			wl.position = Vector2(0.0, 60.0 + row * 150.0)
			wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_splash.add_child(wl)
			row += 1
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
	_art.tip_alpha = 1.0

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
	_art.bar_shown = 0.0
	_banner_left = 0.0
	_banner_q.clear()
	_art.banner_alpha = 0.0
	_art.banner_text = ""
	_wind_banner.visible = false
	_tip.visible = false
	_tip_q.clear()
	_art.tip_alpha = 0.0
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
