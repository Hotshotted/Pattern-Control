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
const SZ_XL := 110
const SZ_M := 56
const SZ_S := 30
const C_TEXT := Color(1.0, 1.0, 1.0)
const C_SOFT := Color(0.74, 0.82, 0.93)
const C_QUIET := Color(0.56, 0.63, 0.75)
const C_GOLD := Color(1.0, 0.84, 0.15)
const C_GREEN := Color(0.2, 0.7, 0.45)
const C_RED := Color(1.0, 0.36, 0.3)
const C_PANEL := Color(0.09, 0.13, 0.21, 0.94)
const C_LINE := Color(0.62, 0.72, 0.9, 0.9)
const C_DIM := Color(0.04, 0.06, 0.1)

## The drawn parts of the HUD: icons, buttons and cards, the star bar, the results and the little pills.
class Art extends Control:
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
	var pause_rect := Rect2(10.0, 10.0, 80.0, 80.0)   # the pause button, top-left (the wind dial is on the right)
	var slider_rect: Array[Rect2] = [Rect2(), Rect2()]
	var slider_val := PackedFloat32Array([0.8, 0.8])
	var slider_glyph := PackedStringArray(["speaker", "note"])
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
	var _pts := PackedVector2Array()
	var _p3 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _p4 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _p5 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _font: Font
	var _sb_normal: StyleBoxFlat
	var _sb_disabled: StyleBoxFlat
	var _sb_accent: StyleBoxFlat
	var _sb_primary: StyleBoxFlat
	var _sb_gold: StyleBoxFlat
	var _sb_pill: StyleBoxFlat
	var _sb_banner: StyleBoxFlat
	var _sb_tip: StyleBoxFlat
	var _sb_sheet: StyleBoxFlat

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
	var btn_count := 0

	func _init() -> void:
		for i in MAX_BTN:
			btn_rect.append(Rect2())
		for a in [btn_id, btn_text, btn_sub, btn_glyph]:
			a.resize(MAX_BTN)
		for a in [btn_state, btn_stars, btn_icon, btn_kind, btn_pips, btn_cost, btn_badge, btn_lock]:
			a.resize(MAX_BTN)
		_pts.resize(10)
		_font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sb_normal = _box(C_PANEL, C_LINE, 22)
		_sb_disabled = _box(Color(0.06, 0.07, 0.1, 0.9), Color(0.3, 0.33, 0.4, 0.9), 22)
		_sb_accent = _box(Color(0.12, 0.45, 0.32, 0.97), Color(0.75, 1.0, 0.85, 0.95), 22)
		_sb_primary = _box(Color(0.14, 0.62, 0.4, 1.0), Color(0.88, 1.0, 0.93, 1.0), 38, 7)
		_sb_gold = _box(Color(0.3, 0.24, 0.06, 0.96), C_GOLD, 22)
		_sb_pill = _box(Color(0.03, 0.05, 0.09, 0.78), Color(0.8, 0.88, 1.0, 0.55), 40, 3)
		_sb_sheet = _box(Color(0.05, 0.07, 0.12, 0.98), C_LINE, 30, 3)
		_sb_banner = _box(Color(0.03, 0.05, 0.09, 0.82), Color.WHITE, 40, 3)
		_sb_tip = _box(Color(0.03, 0.05, 0.09, 0.85), Color(0.7, 0.95, 0.85), 40, 3)

	func _box(fill: Color, border: Color, radius: int, width: int = 4) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(radius)
		return sb

	# ---------- text ----------

	func text(s: String, pos: Vector2, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
		draw_string_outline(_font, pos, s, align, width, size_px, maxi(size_px / 8, 4), Color(0, 0, 0, col.a))
		draw_string(_font, pos, s, align, width, size_px, col)

	func text_width(s: String, size_px: int) -> float:
		return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

	# ---------- shapes ----------

	func star(c: Vector2, r: float, fill: Color, outline: bool = true) -> void:
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			var rr := (r if k % 2 == 0 else r * 0.45) + (4.0 if outline else 0.0)
			_pts[k] = c + Vector2(cos(a), sin(a)) * rr
		if outline:
			draw_colored_polygon(_pts, Color(0, 0, 0, fill.a))
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0
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
			"coin":
				draw_circle(c, r, Color(0, 0, 0, col.a))
				draw_circle(c, r - 3.0, Color(1.0, 0.82, 0.2, col.a))
				draw_arc(c, r * 0.62, 0.0, TAU, 20, Color(0.78, 0.52, 0.05, col.a), w * 0.8)
			"star":
				star(c, r, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, col.a), true)
			"star_off":
				star(c, r, Color(0.28, 0.3, 0.38, col.a), true)
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
			"chev_up":
				line3(c + Vector2(-r * 0.7, r * 0.3), c + Vector2(0, -r * 0.4), c + Vector2(r * 0.7, r * 0.3), col, w * 1.4)
			"home":
				tri(c + Vector2(-r * 0.9, -r * 0.05), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.9, -r * 0.05), col)
				draw_rect(Rect2(c.x - r * 0.6, c.y - r * 0.05, r * 1.2, r * 0.85), col)
				draw_rect(Rect2(c.x - r * 0.17, c.y + r * 0.3, r * 0.34, r * 0.5), Color(0.08, 0.1, 0.16, col.a))
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
			"airport":
				draw_rect(Rect2(c.x - r * 0.3, c.y - r * 0.95, r * 0.6, r * 1.9), col)
				for k in 3:
					draw_rect(Rect2(c.x - r * 0.06, c.y - r * 0.7 + k * r * 0.55, r * 0.12, r * 0.28), Color(0.08, 0.1, 0.16, col.a))
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
				tri(c + Vector2(-r * 0.3, -r * 0.8), c + Vector2(r * 0.3, -r * 0.8), c + Vector2(0, -r * 0.5), Color(0.08, 0.1, 0.16, col.a))
				_pts.resize(10)
			"daily":      # a sun: a new shift every day
				draw_circle(c, r * 0.45, Color(1.0, 0.82, 0.25, col.a))
				for k in 8:
					var a := k * PI / 4.0
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.7, c + Vector2(cos(a), sin(a)) * r * 1.0, Color(1.0, 0.82, 0.25, col.a), w * 1.3)
			"bad":
				draw_rect(Rect2(c.x - r * 0.8, c.y - r * 0.8, r * 1.6, r * 1.6), Color(1.0, 0.62, 0.15, col.a))
				text("L", c + Vector2(-r * 0.8, r * 0.58), int(r * 1.7), Color(1, 1, 1, col.a), HORIZONTAL_ALIGNMENT_CENTER, r * 1.6)
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
				tri(c + Vector2(-r, r * 0.85), c + Vector2(r, r * 0.85), c + Vector2(0, -r * 0.9), Color(1.0, 0.35, 0.3, col.a))
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

	# ---------- buttons and cards ----------

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
			var kind := btn_kind[k]
			var ink := C_TEXT if st != 1 else Color(0.5, 0.53, 0.6)
			match kind:
				2:      # the primary button: big, green, XL text with its icon right beside it
					draw_style_box(_sb_primary, r)
					var tw := text_width(btn_text[k], SZ_XL)
					var gw := r.size.y * 0.34 if btn_glyph[k] != "" else 0.0
					var x0 := r.get_center().x - (tw + gw) * 0.5
					if gw > 0.0:
						glyph(btn_glyph[k], Vector2(x0 + gw * 0.3, r.get_center().y), r.size.y * 0.2, ink)
					text(btn_text[k], Vector2(x0 + gw, r.get_center().y + SZ_XL * 0.33), SZ_XL, ink)
				3:      # a round icon button with a small label under it
					var c := r.get_center() - Vector2(0, 16.0)
					var rad := minf(r.size.x, r.size.y) * 0.5 - 18.0
					draw_circle(c, rad + 4.0, C_LINE if st != 1 else Color(0.3, 0.33, 0.4))
					draw_circle(c, rad, C_PANEL if st != 2 else Color(0.14, 0.5, 0.35))
					glyph(btn_glyph[k], c, rad * 0.5, ink)
					text(btn_text[k], Vector2(r.position.x, r.end.y - 4.0), SZ_S, C_SOFT if st != 1 else C_QUIET, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
					var b := btn_badge[k]
					if b != 0:
						var bc := c + Vector2(rad * 0.75, -rad * 0.75)
						draw_circle(bc, 22.0, Color.BLACK)
						draw_circle(bc, 19.0, Color(0.2, 0.75, 0.45) if b < 0 else Color(1.0, 0.55, 0.15))
						if b < 0:
							glyph("check", bc, 11.0, Color.WHITE)
						else:
							text(str(b), bc + Vector2(-20.0, 10.0), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
				4:      # a small chip: glyph + a few words
					draw_style_box(_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal), r)
					var tw2 := text_width(btn_text[k], SZ_S)
					if btn_text[k] == "" and btn_glyph[k] != "":
						glyph(btn_glyph[k], r.get_center(), r.size.y * 0.3, ink)
						continue
					var total := tw2 + (text_width(btn_sub[k], SZ_S) + 16.0 if btn_sub[k] != "" else 0.0) + (r.size.y * 0.5 + 12.0 if btn_glyph[k] != "" else 0.0)
					var x0 := r.get_center().x - total * 0.5
					if btn_glyph[k] != "":
						glyph(btn_glyph[k], Vector2(x0 + r.size.y * 0.25, r.get_center().y), r.size.y * 0.24, ink)
						x0 += r.size.y * 0.5 + 12.0
					text(btn_text[k], Vector2(x0, r.get_center().y + SZ_S * 0.35), SZ_S, ink)
					if btn_sub[k] != "":
						text(btn_sub[k], Vector2(x0 + tw2 + 16.0, r.get_center().y + SZ_S * 0.35), SZ_S, C_GOLD)
				1:      # a card
					var sb := _sb_gold if (st == 2 and btn_cost[k] == 0) else (_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal))
					draw_style_box(sb, r)
					var left := r.position.x + 36.0
					var cy := r.get_center().y
					var iconed := btn_icon[k] >= 0 or btn_glyph[k] != ""
					if btn_icon[k] >= 0:
						_draw_icon(btn_icon[k], Vector2(left + 44.0, cy), minf(r.size.y * 0.3, 46.0))
					elif btn_glyph[k] != "":
						draw_circle(Vector2(left + 44.0, cy), 44.0, Color(0.03, 0.05, 0.09, 0.8))
						glyph(btn_glyph[k], Vector2(left + 44.0, cy), 24.0, ink if st != 1 else C_QUIET)
					var tx := left + (110.0 if iconed else 0.0)
					var right_w := 220.0 if (btn_cost[k] >= 0 or btn_pips[k] >= 0) else (190.0 if btn_stars[k] >= 0 or btn_lock[k] > 0 else 60.0)
					var tw3 := r.end.x - tx - right_w - 30.0
					text(btn_text[k], Vector2(tx, cy + (-2.0 if btn_sub[k] != "" else SZ_M * 0.34)), SZ_M, ink, HORIZONTAL_ALIGNMENT_LEFT, tw3)
					if btn_sub[k] != "":
						text(btn_sub[k], Vector2(tx, cy + 40.0), SZ_S, C_SOFT if st != 1 else C_QUIET, HORIZONTAL_ALIGNMENT_LEFT, tw3)
					var rx := r.end.x - 36.0
					if btn_stars[k] >= 0 and btn_lock[k] <= 0:
						for i in 3:
							glyph("star" if i < btn_stars[k] else "star_off", Vector2(rx - 120.0 + i * 60.0, cy), 24.0)
					if btn_lock[k] > 0:
						glyph("lock", Vector2(rx - 110.0, cy), 24.0, C_QUIET)
						glyph("star", Vector2(rx - 38.0, cy), 18.0, Color(1, 1, 1, 0.55))
						text(str(btn_lock[k]), Vector2(rx - 66.0, cy + 10.0), SZ_S, C_QUIET, HORIZONTAL_ALIGNMENT_RIGHT, 28.0)
					if btn_pips[k] >= 0:
						for i in 3:
							var pc := Vector2(rx - 130.0 + i * 36.0, cy - 36.0)
							draw_circle(pc, 14.0, Color.BLACK)
							draw_circle(pc, 11.0, C_GOLD if i < btn_pips[k] else Color(0.25, 0.28, 0.36))
					if btn_cost[k] > 0:
						var cc := Vector2(rx - 190.0, cy + 26.0)
						glyph("coin", cc, 16.0, Color(1, 1, 1, 1.0 if st != 1 else 0.5))
						text(str(btn_cost[k]), cc + Vector2(26.0, 11.0), SZ_S, C_TEXT if st != 1 else C_QUIET)
					elif btn_cost[k] == 0:
						text("MAX", Vector2(rx - 190.0, cy + 38.0), SZ_S, C_GOLD)
				_:
					draw_style_box(_sb_accent if st == 2 else (_sb_disabled if st == 1 else _sb_normal), r)
					var gw := r.size.y * 0.5 if btn_glyph[k] != "" else 0.0
					var tw4 := text_width(btn_text[k], SZ_M)
					var sx := r.get_center().x - (tw4 + gw) * 0.5
					if btn_glyph[k] != "":
						glyph(btn_glyph[k], Vector2(sx + gw * 0.4, r.get_center().y), r.size.y * 0.24, ink)
					text(btn_text[k], Vector2(sx + gw, r.get_center().y + SZ_M * 0.34), SZ_M, ink)

	# ---------- the HUD of a shift ----------

	## Two bars in a rounded square.
	func _draw_pause_button() -> void:
		var r := pause_rect
		draw_style_box(_sb_pill, r)
		glyph("pause", r.get_center(), r.size.x * 0.3, Color.WHITE)

	func _draw_sliders() -> void:
		for i in 2:
			var r := slider_rect[i]
			var ty := r.get_center().y
			glyph(slider_glyph[i], Vector2(r.position.x - 70.0, ty), 34.0, C_TEXT)
			draw_line(Vector2(r.position.x, ty), Vector2(r.end.x, ty), Color(0, 0, 0, 0.85), 22.0)
			draw_line(Vector2(r.position.x, ty), Vector2(r.position.x + r.size.x * slider_val[i], ty), C_GOLD, 12.0)
			draw_circle(Vector2(r.position.x + r.size.x * slider_val[i], ty), 28.0, Color.BLACK)
			draw_circle(Vector2(r.position.x + r.size.x * slider_val[i], ty), 22.0, Color.WHITE)

	## The slim star bar: it fills as the balance grows, with a tick (a small star) at each threshold.
	func _draw_star_bar() -> void:
		var w := minf(size.x - 380.0, 560.0)
		var x0 := size.x * 0.5 - w * 0.5
		var y := 224.0
		var top := float(maxi(thresholds[2], 1)) * 1.04
		draw_rect(Rect2(x0, y, w, 12.0), Color(0, 0, 0, 0.6))
		var f := clampf(bar_shown / top, 0.0, 1.0)
		draw_rect(Rect2(x0, y, w * f, 12.0), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.95))
		for i in 3:
			var x := x0 + w * float(thresholds[i]) / top
			var lit := balance >= thresholds[i]
			glyph("star" if lit else "star_off", Vector2(x, y + 6.0), 20.0 if lit else 16.0)

	func _draw_wind() -> void:
		var c := Vector2(size.x - 78.0, 96.0)
		draw_circle(c, 52.0, Color(0.03, 0.05, 0.08, 0.55))
		var ring := C_GOLD if wind_warn and int(Time.get_ticks_msec() / 250.0) % 2 == 0 else Color(0.85, 0.9, 1.0, 0.8)
		draw_arc(c, 52.0, 0.0, TAU, 40, ring, 4.0)
		var d := Vector2(sin(deg_to_rad(wind_toward)), -cos(deg_to_rad(wind_toward)))
		var n := Vector2(-d.y, d.x)
		draw_line(c - d * 32.0, c + d * 8.0, Color.BLACK, 11.0)
		draw_line(c - d * 32.0, c + d * 8.0, Color.WHITE, 6.0)
		tri(c + d * 38.0, c + d * 6.0 + n * 18.0, c + d * 6.0 - n * 18.0, Color.WHITE)
		text(wind_text, Vector2(c.x - 50.0, c.y + 92.0), SZ_S, C_GOLD if wind_warn else C_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 100.0)

	## A status pill under the star bar: a glyph and a few characters.
	func _pill(c: Vector2, g: String, s: String, size_px: int, col: Color) -> void:
		var tw := text_width(s, size_px)
		var h := float(size_px) * 1.35
		var w := tw + h * 1.3
		draw_style_box(_sb_pill, Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h))
		glyph(g, Vector2(c.x - w * 0.5 + h * 0.62, c.y), h * 0.32, col)
		text(s, Vector2(c.x - w * 0.5 + h * 1.12, c.y + size_px * 0.34), size_px, col)

	func _draw_hud() -> void:
		_draw_pause_button()
		if mode_glyph != "":
			glyph(mode_glyph, Vector2(50.0, 146.0), 26.0, C_SOFT)
		_draw_star_bar()
		var y := 300.0
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
			_sb_banner.bg_color.a = 0.82 * banner_alpha
			_sb_banner.border_color = Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha)
			draw_style_box(_sb_banner, r)
			var x := r.position.x + 40.0
			if banner_glyph != "":
				glyph(banner_glyph, Vector2(x + 30.0, r.get_center().y), 30.0, Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha))
				x += 84.0
			text(banner_text, Vector2(x, r.get_center().y + SZ_M * 0.34), SZ_M, Color(banner_color.r, banner_color.g, banner_color.b, banner_alpha))
		if tip_alpha > 0.01 and tip_text != "":
			var r2 := tip_rect
			_sb_tip.bg_color.a = 0.85 * tip_alpha
			_sb_tip.border_color = Color(0.7, 0.95, 0.85, tip_alpha)
			draw_style_box(_sb_tip, r2)
			var x2 := r2.position.x + 40.0
			if tip_glyph != "":
				glyph(tip_glyph, Vector2(x2 + 28.0, r2.get_center().y), 28.0, Color(1, 1, 1, tip_alpha))
				x2 += 84.0
			text(tip_text, Vector2(x2, r2.get_center().y + SZ_S * 0.35), SZ_S, Color(0.92, 1.0, 0.96, tip_alpha), HORIZONTAL_ALIGNMENT_LEFT, r2.end.x - x2 - 20.0)

	# ---------- the results ----------

	func _ease_out_back(t: float) -> float:
		var c1 := 1.70158
		var c3 := c1 + 1.0
		return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

	func _draw_details() -> void:
		draw_style_box(_sb_sheet, details_rect)
		for i in details_lines.size():
			var y := details_rect.position.y + 58.0 + i * 46.0
			var parts := details_lines[i].split("|")
			var last := i == details_lines.size() - 1
			text(parts[0], Vector2(details_rect.position.x + 40.0, y), SZ_S, C_TEXT if last else C_SOFT, HORIZONTAL_ALIGNMENT_LEFT, details_rect.size.x - 80.0)
			if parts.size() > 1:
				text(parts[1], Vector2(details_rect.position.x + 40.0, y), SZ_S, C_GOLD if last else C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, details_rect.size.x - 80.0)

	func _draw_results() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		if details_open:
			_draw_details()
			return
		# The stars, one after another, each popping in.
		for i in 3:
			var t0 := 0.35 + 0.5 * i
			var k := clampf((res_t - t0) / 0.4, 0.0, 1.0)
			var c := Vector2(cx + (i - 1) * 230.0, cy - 470.0 - (50.0 if i == 1 else 0.0))
			star(c, 110.0, Color(0.22, 0.25, 0.32), true)
			if i < res_stars and k > 0.0:
				star(c, 110.0 * _ease_out_back(k), C_GOLD, true)
		# The total paid, rolling up once the stars are in.
		var t_count := 0.35 + 0.5 * 3.0
		var f := clampf((res_t - t_count) / 1.0, 0.0, 1.0)
		var shown := roundi(res_total * (1.0 - pow(1.0 - f, 3.0)))
		var label := "+%d" % shown
		var tw := text_width(label, SZ_XL)
		var ty := cy - 150.0
		glyph("coin", Vector2(cx - tw * 0.5 - 56.0, ty - SZ_XL * 0.32), 40.0)
		text(label, Vector2(cx - tw * 0.5, ty), SZ_XL, C_GOLD if not res_doubled else Color(0.6, 1.0, 0.7))
		if res_doubled:
			text("x2", Vector2(cx + tw * 0.5 + 24.0, ty), SZ_M, Color(0.6, 1.0, 0.7))
		# One quiet line: a new best, or the best so far.
		var k2 := clampf((res_t - (t_count + 1.0)) / 0.4, 0.0, 1.0)
		if res_new_best:
			text("NEW BEST", Vector2(cx - 300.0, ty + 78.0), SZ_M, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, k2), HORIZONTAL_ALIGNMENT_CENTER, 600.0)
		elif res_best > 0:
			text("best %d" % res_best, Vector2(cx - 300.0, ty + 70.0), SZ_S, Color(C_QUIET.r, C_QUIET.g, C_QUIET.b, k2), HORIZONTAL_ALIGNMENT_CENTER, 600.0)
	func _draw() -> void:
		if header_text != "":
			var hw := text_width(header_text, SZ_M)
			glyph(header_glyph, Vector2(size.x - 40.0 - hw - 40.0, 62.0), 26.0)
			text(header_text, Vector2(size.x - 40.0 - hw, 78.0), SZ_M, C_TEXT)
		if header2_text != "":
			glyph(header2_glyph, Vector2(64.0, 62.0), 26.0)
			text(header2_text, Vector2(104.0, 78.0), SZ_M, C_TEXT)
		_draw_buttons()
		if show_play and not show_pause:
			_draw_hud()
		elif show_play and show_pause:
			pass
		if show_pause:
			_draw_sliders()
		if show_result:
			_draw_results()
		_draw_pills()

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
	_pop_from.resize(POPUP_POOL)
	_build_pause()
	_build_menu()
	_build_over()
	_build_select()
	_build_ad()
	move_child(_art, _select.get_index() + 1)   # the art (buttons, stars, pills) is drawn above the screen shades
	_build_stamp()
	_set_play_labels(false)
	set_landed(0)

func _label(size: int, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(size / 8, 4))
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

func _shade(parent: Control, a: float) -> void:
	var shade := ColorRect.new()
	shade.color = Color(C_DIM.r, C_DIM.g, C_DIM.b, a)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)

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
	_shade(_pause, 0.9)
	var title := _label(SZ_XL, HORIZONTAL_ALIGNMENT_CENTER, _pause)
	title.text = "PAUSED"
	_centered(title, -600, -450)
	_pause.visible = false

func show_pause(sound: float, music: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	_pause.visible = true
	_art.show_pause = true
	_set_play_labels(false)
	_art.slider_rect[0] = Rect2(vp.x * 0.5 - 250.0, vp.y * 0.5 - 60.0, 620.0, 80.0)
	_art.slider_rect[1] = Rect2(vp.x * 0.5 - 250.0, vp.y * 0.5 + 80.0, 620.0, 80.0)
	_art.slider_val[0] = sound
	_art.slider_val[1] = music
	_art.clear_buttons()
	_art.add_button("resume", "RESUME", Rect2(vp.x * 0.5 - 420.0, vp.y * 0.5 - 420.0, 840.0, 230.0), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	_art.add_button("restart", "Restart", Rect2(vp.x * 0.5 - 330.0, vp.y * 0.5 + 280.0, 220.0, 230.0), 0, "", -1, -1, {"kind": 3, "glyph": "restart"})
	_art.add_button("quit", "Menu", Rect2(vp.x * 0.5 + 110.0, vp.y * 0.5 + 280.0, 220.0, 230.0), 0, "", -1, -1, {"kind": 3, "glyph": "home"})
	_art.queue_redraw()

func hide_pause() -> void:
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
	for i in 2:
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
	_shade(_menu, 0.72)
	_menu_title = _label(SZ_XL, HORIZONTAL_ALIGNMENT_CENTER, _menu)
	_menu_title.text = "PATTERN WORK"
	_centered(_menu_title, -560, -420)
	_menu.visible = false

func _build_select() -> void:
	_select = Control.new()
	_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_select.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_select)
	_shade(_select, 0.9)
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
	_ad_bar.color = Color(0.4, 0.85, 1.0)
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
	_hide_all_screens()
	_over_head.text = header
	var total_line := "Total paid|+%d%s" % [coins_earned, " (doubled)" if doubled else ""]
	_over_body.text = (reason + "\n" + total_line + "\nBank|%d" % coins_total).replace("|", " ")
	_art.res_stars = shift.stars()
	_art.res_total = coins_earned
	_art.res_new_best = new_best
	_art.res_best = best
	_art.res_doubled = doubled
	if not _art.show_result or _art.res_t > 60.0:
		_art.res_t = 0.0
	_art.details_open = false
	_over_body.visible = false
	var lines := reason.split("\n")
	lines.append(total_line)
	_art.details_lines = lines
	_art.show_result = true
	_art.header_glyph = "coin"
	_art.header_text = str(coins_total)
	_art.queue_redraw()
	_over.visible = true

## Results: the two rewarded offers (small, under the one clear PLAY AGAIN button), and the Details / Menu buttons.
## A zero amount leaves that offer out.
func set_results_ads(double_coins: int, refund: int) -> void:
	_art.clear_buttons()
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	_art.add_button("details", "Details", Rect2(cx - 150.0, cy - 30.0, 300.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "chev_up" if _art.details_open else "chev_down"})
	_art.add_button("again", "PLAY AGAIN", Rect2(cx - 420.0, cy + 330.0, 840.0, 230.0), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	var n := (1 if double_coins > 0 else 0) + (1 if refund > 0 else 0)
	var x := cx - (n * 400.0 + (n - 1) * 20.0) * 0.5
	if double_coins > 0:
		_art.add_button("ad_double", "x2 coins", Rect2(x, cy + 600.0, 400.0, 84.0), 0, "+%d" % double_coins, -1, -1, {"kind": 4, "glyph": "ad"})
		x += 420.0
	if refund > 0:
		_art.add_button("ad_refund", "Refund fine", Rect2(x, cy + 600.0, 400.0, 84.0), 0, "+%d" % refund, -1, -1, {"kind": 4, "glyph": "ad"})
	_art.add_button("menu", "", Rect2(10.0, 10.0, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "home"})
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
	_hide_all_screens()
	_select.visible = true
	_select_title.text = "AIRPORTS"
	_art.header_glyph = "star"
	_art.header_text = str(total_stars)
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	_art.add_button("back", "", Rect2(10.0, 10.0, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
	for i in Airports.COUNT:
		var r := Rect2(40.0, 150.0 + i * 190.0, vp.x - 80.0, 170.0)
		if open[i] != 0:
			_art.add_button("airport:%d" % i, Airports.airport_name(i), r, 2 if i == selected else 0, "", stars[i], -1, {"kind": 1, "glyph": "airport"})
		else:
			_art.add_button("locked:%d" % i, Airports.airport_name(i), r, 1, "", -1, -1, {"kind": 1, "glyph": "airport", "lock": Airports.unlock_stars(i)})
	_art.queue_redraw()

## A generic list screen: optional tab chips, then cards {id, title, sub, state, stars, icon, cost}, then Back.
func show_list(title: String, coins: int, tabs: Array, cards: Array) -> void:
	_hide_all_screens()
	_select.visible = true
	_select_title.text = title
	_art.header_glyph = "coin"
	_art.header_text = str(coins)
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	_art.add_button("back", "", Rect2(10.0, 10.0, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
	var y := 130.0
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
	_hide_all_screens()
	_select.visible = true
	_select_title.text = "UPGRADES"
	_art.header_glyph = "coin"
	_art.header_text = str(coins)
	var vp := get_viewport().get_visible_rect().size
	_art.clear_buttons()
	_art.add_button("back", "", Rect2(10.0, 10.0, 80.0, 80.0), 0, "", -1, -1, {"kind": 4, "glyph": "back"})
	for i in Upgrades.IDS.size():
		var id: String = Upgrades.IDS[i]
		var lvl := levels[i]
		var price := Upgrades.cost(id, lvl)
		var r := Rect2(40.0, 150.0 + i * 190.0, vp.x - 80.0, 170.0)
		var state := 0
		if price < 0:
			state = 2
		elif coins < price:
			state = 1
		else:
			state = 2
		_art.add_button("upg:" + id, Upgrades.upgrade_name(id), r, state, Upgrades.description(id), -1, -1, {"kind": 1, "glyph": Upgrades.glyph(id), "pips": lvl, "cost": maxi(price, 0)})
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
	_hide_all_screens()
	_menu.visible = true
	_art.header2_glyph = "coin"
	_art.header2_text = str(coins)
	_art.header_glyph = "star"
	_art.header_text = str(stars)
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	_art.clear_buttons()
	_art.add_button("airports", airport_name, Rect2(cx - 380.0, cy - 340.0, 760.0, 150.0), 0, "", airport_stars, -1, {"kind": 1, "glyph": "airport"})
	_art.add_button("play", "PLAY", Rect2(cx - 420.0, cy - 110.0, 840.0, 280.0), 2, "", -1, -1, {"kind": 2, "glyph": "play"})
	var items := [["upgrades", "Upgrades", "upgrades", 0], ["shop", "Shop", "shop", 0],
			["daily", "Daily", "daily", -1 if daily_done else daily_streak], ["bad", "Bad day", "bad", -1 if bad_done else bad_streak]]
	for k in items.size():
		var x := cx + (k - 1.5) * 250.0
		_art.add_button(items[k][0], items[k][1], Rect2(x - 110.0, cy + 330.0, 220.0, 240.0), 0, "", -1, -1, {"kind": 3, "glyph": items[k][2], "badge": items[k][3]})
	_art.queue_redraw()

# ---------- The HUD of a shift ----------

func reset_for_run(_best_coins: int) -> void:
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
	set_landed(0)
	set_timer(int(Tuning.shift_seconds))
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
	_art.coin_icon = Vector2(vp.x * 0.5 - w * 0.5 - 78.0, 56.0 + SZ_XL * 0.62)

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
	l.add_theme_color_override("font_color", color)
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
	_art.banner_rect = Rect2(vp.x * 0.5 - (tw + 84.0 + 80.0) * 0.5, 470.0, tw + 84.0 + 80.0, 90.0)
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
	_art.tip_rect = Rect2(vp.x * 0.5 - pw * 0.5, vp.y - 280.0, pw, 100.0)
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
		l.scale = Vector2.ONE * (1.0 + 0.3 * (1.0 - pa) * (1.0 - pa))
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
	_update_perf(delta)

# ---------- ?perf ----------

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
	l.modulate = Color(1, 1, 1, 0.4)
	if DebugFlags.perf_enabled():
		_perf_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT)
		_perf_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_perf_label.offset_left = 14
		_perf_label.offset_top = 112       # (below the pause button)
		_perf_label.modulate = Color(0.6, 1, 0.6, 0.9)

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
