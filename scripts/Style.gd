class_name Style
extends RefCounted
## The visual identity in one place (the written version is docs/style.md): palette, type, radii, spacing, motion
## timings, shadows, safe areas. Nothing in here touches the autoloads, so any script can use it.

# ---- palette (Cozy Airfield) ----
const PRIMARY := Color("4c8fd6")         # blue: selection, info (runway 2)
const PRIMARY_DARK := Color("2f6aa8")
const ACCENT := Color("f2b233")          # coin gold: coins, stars, rewards
const ACCENT_DARK := Color("b87a14")
const SUCCESS := Color("35c98a")         # go / earned
const SUCCESS_DARK := Color("1a8a5a")
const WARNING := Color("f0803c")         # orange: streaks, the primary button, runway 1
const DANGER := Color("ea4a3c")          # fines, conflicts, overtime, last 15 s
const DANGER_DARK := Color("a8302a")
const ORANGE_TOP := Color("ff9d4f")      # the primary button: top of its gradient...
const ORANGE := Color("f0803c")          # ...its bottom...
const ORANGE_EDGE := Color("b85a1b")     # ...and the 7 px edge it sits on
# neutrals and surfaces: everything is cream (the names are kept: SURFACE_DARK is the cream's lower, darker end)
const INK := Color("3a2410")             # outlines, deepest dark (a warm brown, never black)
const SURFACE_DARK := Color("f6e8cf")    # cards and sheets: cream, bottom of the gradient
const SURFACE_DARK_2 := Color("ebd9b6")  # raised / selected surface
const SURFACE_LIGHT := Color("fff8ea")   # cream, top of the gradient
const SURFACE_LIGHT_2 := Color("f6e8cf")
const EDGE := Color("c9a46e")            # the solid 4 px bottom edge of every cream surface
const TEXT := Color("5a3a12")            # text on cream
const TEXT_SOFT := Color("7a5a2c")
const TEXT_QUIET := Color("a88c5e")
const TEXT_ON_LIGHT := Color("5a3a12")
const WORLD_TEXT := Color("fff4df")      # display text over the field: cream with a warm extrusion
const EXT_TOP := Color("c9641f")         # the stacked extrusion, from the letters down...
const EXT_BOTTOM := Color("803d11")
const LINE := Color(0.79, 0.64, 0.43, 0.9)
const SCRIM := Color("2b1b0a")           # the warm shade behind a screen or sheet

# ---- radii, spacing (px in the 1080 x 1920 viewport) ----
const R_S := 14
const R_M := 22                          # cards, chips
const R_L := 40                          # primary buttons, sheets
const R_PILL := 999                      # banners, pills: fully rounded
const SP_1 := 8
const SP_2 := 16
const SP_3 := 24
const SP_4 := 40
const SP_5 := 64
const GUTTER := 40                       # screen edge to content

# ---- shadows ----
const SHADOW_COLOR := Color(0.35, 0.22, 0.07, 0.3)
const SHADOW_SIZE := 16
const SHADOW_OFFSET := Vector2(0.0, 8.0)
const LIP := 7.0                         # the 7 px edge under the primary button (a press drops it onto the edge)

# ---- motion (seconds) ----
const T_FAST := 0.12                     # press / release
const T_BASE := 0.30                     # (button release bounce)
const T_PANEL := 0.18                    # a screen or panel opening: opacity and scale of its layer
const PANEL_FROM := 0.94                 # ...scaling up from this
const T_SLOW := 0.5                      # celebrations
const STAGGER := 0.05                    # between cards animating in
const OVERSHOOT := 1.70158               # ease-out-back constant for popups
# Easing: ease-out-cubic for things arriving, ease-in-cubic for things leaving, ease-out-back for popups and stars.

# ---- type ----
const SZ_XL := 110
const SZ_M := 56
const SZ_S := 30
const WGHT := 2003265652                 # the OpenType 'wght' axis tag
const LABEL_WEIGHT := 800.0              # Rubik ExtraBold: labels
const BODY_WEIGHT := 500.0               # Rubik Medium: one-line descriptions

static var _display: Font
static var _text: FontVariation
static var _body: FontVariation

## Bowlby One SC: the title, the timer, the score and the screen headers.
static func display() -> Font:
	if _display == null:
		_display = preload("res://assets/fonts/BowlbyOneSC.ttf")
	return _display

## Rubik 800: labels.
static func text() -> Font:
	if _text == null:
		_text = FontVariation.new()
		_text.base_font = preload("res://assets/fonts/Rubik.ttf")
		_text.variation_opentype = {WGHT: LABEL_WEIGHT}
	return _text

## Rubik 500: descriptions.
static func body() -> Font:
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = preload("res://assets/fonts/Rubik.ttf")
		_body.variation_opentype = {WGHT: BODY_WEIGHT}
	return _body

## Display text over the field: cream letters on a stacked warm extrusion (#C9641F down to #803D11) and a soft shadow.
## `pos` is the baseline start, as for draw_string.
static func draw_ext(ci: CanvasItem, pos: Vector2, s: String, size_px: int, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, col: Color = WORLD_TEXT, depth: int = 5, alpha: float = 1.0) -> void:
	var f := display()
	var step := maxf(size_px / 28.0, 1.5)
	ci.draw_string(f, pos + Vector2(0, step * depth + 3.0), s, align, width, size_px, Color(0.2, 0.1, 0.02, 0.22 * alpha))       # the soft shadow
	for i in range(depth, 0, -1):
		var k := float(i - 1) / maxf(depth - 1, 1)
		var c := EXT_TOP.lerp(EXT_BOTTOM, k)
		ci.draw_string(f, pos + Vector2(0, step * i), s, align, width, size_px, Color(c, alpha))
	ci.draw_string(f, pos, s, align, width, size_px, Color(col, col.a * alpha))

## Text that has to fit a width is drawn at the largest size of a fixed ladder that fits (never at an arbitrary pixel size): every
## size on it is rasterised by the start-up pre-warm, so fitting a string never rasterises a glyph for the first time mid-game.
const FIT := [150, 130, 110, 104, 96, 84, 74, 64, 56, 48, 42, 36, 32, 28, 24]

## Every size the interface draws text at (the pre-warm rows): the ladder plus the fixed ones.
const PREWARM_SIZES := [22, 24, 26, 28, 30, 32, 34, 36, 40, 42, 46, 48, 54, 56, 64, 74, 80, 84, 96, 104, 110, 120, 130, 150]

## The size to draw `s` at: `start` if it fits `max_w`, else the largest ladder size below it that does (never under `min_px`).
static func fit_size(s: String, start: int, min_px: int, max_w: float) -> int:
	var f := font_for(s, start)
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, start).x <= max_w:
		return start
	var last := start
	for sz in FIT:
		if sz >= start:
			continue
		if sz < min_px:
			break
		last = sz
		if font_for(s, sz).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= max_w:
			return sz
	return last

## The font for a string at a size: the display face for big text and for numbers, the text face for the rest.
static func font_for(s: String, size_px: int) -> Font:
	if size_px >= SZ_M:
		return display()
	if s.length() > 0:
		var c := s.unicode_at(0)
		if (c >= 48 and c <= 57) or c == 43 or c == 45 or c == 120:     # 0-9, +, -, x
			return display()
	return text()

# ---- safe areas (notch, rounded corners, home indicator), in viewport pixels ----
static var safe_top := 0.0
static var safe_bottom := 0.0
static var safe_left := 0.0
static var safe_right := 0.0

static func set_safe(top: float, bottom: float, left: float = 0.0, right: float = 0.0) -> void:
	safe_top = maxf(top, 0.0)
	safe_bottom = maxf(bottom, 0.0)
	safe_left = maxf(left, 0.0)
	safe_right = maxf(right, 0.0)

## Read the device's safe area (native) and fit it to the viewport; the web build asks the page for its env() insets.
static func detect_safe(viewport: Vector2) -> void:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0 or viewport.x <= 0.0:
		return
	var k := viewport.x / float(win.x)       # window pixels -> viewport units (the stretch keeps the width)
	if OS.has_feature("web"):
		var js = JavaScriptBridge.eval("(function(){var d=document.createElement('div');d.style.cssText='position:fixed;left:0;top:0;width:0;height:0;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[parseFloat(s.paddingTop)||0,parseFloat(s.paddingBottom)||0,parseFloat(s.paddingLeft)||0,parseFloat(s.paddingRight)||0,window.innerWidth||1];document.body.removeChild(d);return r.join(',');})()")
		if js is String:
			var p: PackedStringArray = (js as String).split(",")
			if p.size() == 5 and float(p[4]) > 0.0:
				var kc := viewport.x / float(p[4])      # css px -> viewport units
				set_safe(float(p[0]) * kc, float(p[1]) * kc, float(p[2]) * kc, float(p[3]) * kc)
		return
	var sa := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	if sa.size.x > 0 and sa.size.y > 0 and scr.x > 0 and (sa.size.x < scr.x or sa.size.y < scr.y):
		set_safe(float(sa.position.y) * k, float(scr.y - sa.end.y) * k, float(sa.position.x) * k, float(scr.x - sa.end.x) * k)

# ---- style boxes ----

## A rounded panel: fill, a light inner border, and a soft drop shadow.
static func box(fill: Color, border: Color, radius: int, border_w: int = 3, shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = SHADOW_COLOR
		sb.shadow_size = SHADOW_SIZE
		sb.shadow_offset = SHADOW_OFFSET
	return sb

## The soft highlight across the top of a panel (a flat stand-in for a gradient): rounded on top only.
static func sheen(radius: int, alpha: float = 0.10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, alpha)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.anti_aliasing = true
	return sb

# ---- the studio mark: Clear Prop Games ----
const STUDIO := "Clear Prop Games"
const STUDIO_WORDS := ["CLEAR", "PROP", "GAMES"]
static var _blade := PackedVector2Array([Vector2(-0.10, -0.16), Vector2(-0.25, -0.5), Vector2(-0.13, -0.82), Vector2(0.0, -0.88), Vector2(0.13, -0.82), Vector2(0.25, -0.5), Vector2(0.10, -0.16)])
static var _bp := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

## A propeller in a round badge: three gold blades with a dark outline round a white hub. `r` is the badge radius.
static func draw_mark(ci: CanvasItem, c: Vector2, r: float, angle: float, a: float = 1.0) -> void:
	ci.draw_circle(c + SHADOW_OFFSET * (r / 80.0), r, Color(SHADOW_COLOR, SHADOW_COLOR.a * a))
	ci.draw_circle(c, r, Color(INK, a))
	ci.draw_circle(c, r - r * 0.06, Color(SURFACE_DARK_2, a))
	ci.draw_arc(c, r * 0.94, 0.0, TAU, 56, Color(PRIMARY, a), maxf(r * 0.06, 2.0))
	for pass_k in 2:
		var grow := 1.14 if pass_k == 0 else 1.0
		var col := Color(INK, a) if pass_k == 0 else Color(ACCENT, a)
		for k in 3:
			var rot := angle + k * TAU / 3.0
			for i in _blade.size():
				var q := _blade[i] * grow * r * 0.9
				if pass_k == 0:
					q.y += r * 0.02 * (1.0 if _blade[i].y < -0.5 else 0.0) * -1.0
				_bp[i] = c + q.rotated(rot)
			ci.draw_colored_polygon(_bp, col)
	for k in 3:
		var rot2 := angle + k * TAU / 3.0
		ci.draw_line(c + Vector2(-0.03, -0.3).rotated(rot2) * r * 0.9, c + Vector2(-0.07, -0.66).rotated(rot2) * r * 0.9, Color(1, 1, 1, 0.55 * a), maxf(r * 0.05, 2.0))
	ci.draw_circle(c, r * 0.2, Color(INK, a))
	ci.draw_circle(c, r * 0.14, Color(TEXT, a))

## "CLEAR PROP GAMES" in the display face, the middle word in gold, centred on `cx`, baseline `y`.
static func draw_wordmark(ci: CanvasItem, cx: float, y: float, size_px: int, a: float = 1.0) -> void:
	var f := display()
	var gap := size_px * 0.32
	var total := -gap
	var widths: Array[float] = []
	for w in STUDIO_WORDS:
		var ww := f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		widths.append(ww)
		total += ww + gap
	var x := cx - total * 0.5
	for k in 3:
		var col := Color(ACCENT if k == 1 else TEXT, a)
		ci.draw_string_outline(f, Vector2(x, y), STUDIO_WORDS[k], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, maxi(size_px / 8, 4), Color(INK, a))
		ci.draw_string(f, Vector2(x, y), STUDIO_WORDS[k], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
		x += widths[k] + gap

static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

static func ease_in_cubic(t: float) -> float:
	return pow(clampf(t, 0.0, 1.0), 3.0)

static func ease_out_back(t: float) -> float:
	var c3 := OVERSHOOT + 1.0
	var u := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + c3 * u * u * u + OVERSHOOT * u * u
