class_name DetailSheet
extends Control
## An airport's detail screen below the live airfield, built from containers so nothing can sit on top of anything else:
##
##   Sheet (PanelContainer, the cream card)
##     Margin (the gutters and the safe area)
##       VBox
##         Scroll (takes whatever height is left; the content scrolls when it is taller)
##           VBox: name + tag, the Stars / Improve tabs, the mastery rank, the No engines switch, then the tab's content
##         Fly here (pinned under the scroll, always visible), or the "Unlock with N stars" pill of a locked airport
##
## Every size is a minimum, not a position: a Label wraps instead of running over its neighbour, a chip grows to fit its words and
## to the 44-point tap size, and the Scroll gives way. The buttons report taps through `pressed` (finger down) and `tapped` (finger
## up on the same button) with the same ids the drawn buttons use ("dtab:1", "noeng:3", "imp:3:fuel", "airport:3").

signal pressed(id: String)
signal tapped(id: String)

const GUTTER := 40.0
const MAX_W := 1044.0                    # the card on a wide (landscape) screen

## Makes a Hud.Art (the drawn glyphs live there); set by the Hud (this script must not name the Hud: it would be a cycle).
var art_factory: Callable

var scroll: ScrollContainer
var card: PanelContainer
var chips := {}                          # id -> Chip
var fly: Chip = null

## One tappable cream chip: a PanelContainer around its content, so it is as big as its content (and its minimum height).
class Chip extends PanelContainer:
	signal down(id: String)
	signal up(id: String)
	var id := ""
	var state := 0              # 0 normal, 1 dimmed (out of reach: it answers with the error sound only), 2 selected / on
	var kind := 0               # 0 cream chip, 1 primary (orange)
	var _held := false
	var _from := Vector2.ZERO
	var _sb := {}

	func setup(p_id: String, p_state: int, p_kind: int, min_h: float, pad: Vector2) -> void:
		id = p_id
		state = p_state
		kind = p_kind
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0.0, min_h)
		_sb = DetailSheet.chip_styles(kind, state, pad)
		add_theme_stylebox_override("panel", _sb["normal"])

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_held = true
				_from = ev.global_position
				add_theme_stylebox_override("panel", _sb["pressed"])
				down.emit(id)
			elif _held:
				_held = false
				add_theme_stylebox_override("panel", _sb["normal"])
				# (a drag that scrolled the sheet is not a tap)
				if ev.global_position.distance_to(_from) < 24.0 and get_global_rect().has_point(ev.global_position):
					up.emit(id)

	## Let go without a tap (the sheet is being rebuilt, or the finger left).
	func cancel() -> void:
		_held = false
		add_theme_stylebox_override("panel", _sb["normal"])

## The cream chip / orange primary looks, with the padding as content margins.
static func chip_styles(kind: int, state: int, pad: Vector2) -> Dictionary:
	var normal: StyleBoxFlat
	var pressed: StyleBoxFlat
	if kind == 1:
		normal = Style.box(Style.ORANGE, Style.ORANGE_EDGE, Style.R_L, 0, true)
		normal.border_width_bottom = int(Style.LIP)
		normal.border_color = Style.ORANGE_EDGE
		pressed = normal.duplicate()
		pressed.border_width_bottom = 2
		pressed.content_margin_top = pad.y + 5.0
	else:
		var fill := Color("e0d1b4") if state == 1 else Style.SURFACE_DARK
		normal = Style.box(fill, Style.ORANGE if state == 2 else Style.EDGE, Style.R_M, 5 if state == 2 else 0, state != 1)
		if state != 2:
			normal.border_width_bottom = 4
			normal.border_color = Style.EDGE
		pressed = normal.duplicate()
		pressed.border_width_bottom = 0
		pressed.content_margin_top = pad.y + 4.0
	for sb in [normal, pressed]:
		sb.content_margin_left = pad.x
		sb.content_margin_right = pad.x
		sb.content_margin_bottom = pad.y
		if sb == normal:
			sb.content_margin_top = pad.y
	return {"normal": normal, "pressed": pressed}

## A small picture (one of the Art glyphs) as a layout element with a minimum size.
class Icon extends Control:
	var art: Control

	func setup(id: String, px: float, factory: Callable, col: Color = Color.WHITE) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		art = factory.call()
		art.icon_id = id
		art.icon_col = col
		add_child(art)

## The mastery bar: a dark track, a fill and nothing else (a minimum height; as wide as its box).
class Bar extends Control:
	var frac := 0.0
	var top := false

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 16.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Style.INK)
		var inner := r.grow(-2.0)
		draw_rect(inner, Color(0.86, 0.78, 0.62))
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(frac, 0.0, 1.0), inner.size.y)), Style.ACCENT if top else Style.PRIMARY)

## The three level pips of an improvement.
class Pips extends Control:
	var level := 0

	func _init() -> void:
		custom_minimum_size = Vector2(3.0 * 26.0, 24.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for q in Improvements.MAX_LEVEL:
			var c := Vector2(size.x * 0.5 + (q - 1) * 26.0, size.y * 0.5)
			draw_circle(c, 10.0, Style.INK)
			draw_circle(c, 7.5, Style.ACCENT if q < level else Color(0.86, 0.78, 0.62))

# ---------------------------------------------------------------------------------------------------------------------

static func label(text: String, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = true, font: Font = null, role: String = "") -> Label:
	var l := Label.new()
	if role == "":
		role = "heading" if size_px >= 54 else "body"
	size_px = maxi(size_px, Style.min_size(role))          # (text is never under the floor of its role: Style, docs/style.md)
	l.set_meta("role", role)
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_font_override("font", font if font != null else Style.font_for(text, size_px))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 8.0          # (so it can be narrower than its text: it wraps, it never pushes its neighbour)
	return l

static func hbox(sep: int = 16) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func vbox(sep: int = 16) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func _fill(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## Rebuild the whole sheet for `info` (the dictionary Main._show_detail makes) on a viewport of `vp` units.
func build(info: Dictionary, vp: Vector2, safe_bottom: float, safe_left: float = 0.0, safe_right: float = 0.0) -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
	chips.clear()
	fly = null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var y0 := vp.y * 0.667
	position = Vector2(0.0, y0)
	size = Vector2(vp.x, vp.y - y0)
	var tap := Style.tap_px()
	var locked: bool = not bool(info["open"])
	var i: int = info["i"]
	var w := minf(vp.x - 36.0 - safe_left - safe_right, MAX_W)

	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP          # (the sheet swallows taps: they never reach the field behind it)
	var sb := Style.box(Style.SURFACE_DARK, Style.EDGE, Style.R_L, 0, true)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	card.position = Vector2((vp.x + safe_left - safe_right - w) * 0.5, 0.0)
	card.size = Vector2(w, size.y + 40.0)                    # (it runs 40 under the screen's edge: no rounded bottom corners show)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(GUTTER))
	margin.add_theme_constant_override("margin_right", int(GUTTER))
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", int(24.0 + 40.0 + safe_bottom))
	card.add_child(margin)
	var col := vbox(16)
	margin.add_child(col)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = 16
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(scroll)
	var body := vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# ---- name and tag (left), the tabs (right) ----
	var inner_w := w - 2.0 * GUTTER
	var tab := int(info.get("tab", 0))
	var names := vbox(2)
	_fill(names)
	names.custom_minimum_size.x = 8.0
	body.add_child(names)
	var nm: String = info["name"]
	var nfs := Style.fit_size(nm, 64, Style.SZ_BODY, inner_w)
	names.add_child(label(nm, nfs, Style.TEXT if not locked else Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.display()))
	var tag_txt: String = info["tag"] + ((" \u00b7 Best %d" % int(info["best"])) if (not locked and int(info["best"]) > 0) else "")
	names.add_child(label(tag_txt, 28, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.body()))
	if not locked:
		var tabs := hbox(10)
		body.add_child(tabs)
		tabs.add_child(_chip("dtab:0", "Stars", "star", 2 if tab == 0 else 0, tap))
		tabs.add_child(_chip("dtab:1", "Improve", "upgrades", 2 if tab == 1 else 0, tap))

	# ---- the tab's content ----
	if tab == 0 or locked:
		var stars_row := hbox(8)
		body.add_child(stars_row)
		for k in 3:
			var cellv := vbox(6)
			_fill(cellv)
			stars_row.add_child(cellv)
			var have: bool = k < int(info["stars"]) and not locked
			var ic := Icon.new()
			ic.setup("star" if have else "star_off", 64.0, art_factory)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cellv.add_child(ic)
			var htxt := ("Land %d" % int(info["land"][0])) if k == 0 else ("Net %d" % int(info["coins"][k]))
			cellv.add_child(label(htxt, 32, Style.TEXT if not locked else Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.display()))
			if k == 0:
				cellv.add_child(label("and finish the shift", 24, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.text(), "caption"))
			else:
				var cr := hbox(6)
				cr.alignment = BoxContainer.ALIGNMENT_CENTER
				var ci := Icon.new()
				ci.setup("coin", 28.0, art_factory)
				cr.add_child(ci)
				cr.add_child(label("after fines", 24, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, false, Style.text(), "caption"))
				cellv.add_child(cr)
	if not locked and tab == 0:
		body.add_child(label("Hangar %d, profit after %d landings" % [int(info["hangar"]), int(info["land"][0])], 28, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.text()))
	if not locked and tab == 1:
		var imps: Array = info["imps"]
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(grid)
		for im in imps:
			var price: int = im["price"]
			var st := 2 if price < 0 else (1 if int(info["bank"]) < price else 0)
			grid.add_child(_imp_chip("imp:%d:%s" % [i, im["id"]], im, price, st, tap))

	if not locked:
		_extras(body, info, tap)

	# ---- the pinned bottom: Fly here, or what unlocks a locked airport ----
	if locked:
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var psb := Style.box(Style.SURFACE_DARK_2, Style.INK, Style.R_L, 0, false)
		psb.bg_color = Color(Style.INK, 0.86)
		psb.content_margin_left = 40.0
		psb.content_margin_right = 40.0
		psb.content_margin_top = 18.0
		psb.content_margin_bottom = 18.0
		pill.add_theme_stylebox_override("panel", psb)
		var pr := hbox(18)
		pill.add_child(pr)
		var li := Icon.new()
		li.setup("lock", 48.0, art_factory)
		pr.add_child(li)
		var n := int(info["lock"])
		var ul := label("Unlock with %d %s" % [n, "star" if n == 1 else "stars"], 40, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, true, Style.display())
		_fill(ul)
		pr.add_child(ul)
		var si := Icon.new()
		si.setup("star", 48.0, art_factory)
		pr.add_child(si)
		pill.custom_minimum_size.y = maxf(100.0, tap)
		col.add_child(pill)
	else:
		fly = _primary("airport:%d" % i, "Fly here", maxf(130.0, tap))
		col.add_child(fly)
	settle()

## Under the tab's content: the mastery rank (and how far to the next one, over a bar) and the No engines switch.
func _extras(body: VBoxContainer, info: Dictionary, tap: float) -> void:
	var i: int = info["i"]
	# ---- mastery: the rank and how far to the next one, over a bar ----
	if info.has("rank"):
		var rank := int(info["rank"])
		var mrow := vbox(6)
		body.add_child(mrow)
		var mline := hbox(16)
		mrow.add_child(mline)
		var rl := label("Rank %d  \u00b7  %s" % [rank, Mastery.rank_name(rank)], 28, Style.ACCENT_DARK if rank >= Mastery.MAX_RANK else Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text())
		_fill(rl)
		mline.add_child(rl)
		var mtxt := "%d landings  \u00b7  top rank" % int(info["landings"]) if int(info["need"]) <= 0 else "%d / %d to rank %d" % [int(info["into"]), int(info["need"]), rank + 1]
		var ml := label(mtxt, 24, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, true, Style.text(), "caption")
		_fill(ml)
		mline.add_child(ml)
		var bar := Bar.new()
		bar.frac = float(info["frac"])
		bar.top = rank >= Mastery.MAX_RANK
		mrow.add_child(bar)
	# ---- No engines ----
	if bool(info["no_engines_ok"]):
		body.add_child(_chip("noeng:%d" % i, "No engines \u00d7%s" % str(snappedf(float(info["no_engines_mult"]), 0.1)), "glider", 2 if bool(info["no_engines"]) else 0, tap))



## Lay everything out now rather than at the end of the frame (the tests and the audit read rectangles straight after building).
func settle() -> void:
	for pass_k in 3:
		_sort(self)

static func _sort(n: Node) -> void:
	for c in n.get_children():
		_sort(c)
	if n is Container:
		n.notification(Container.NOTIFICATION_SORT_CHILDREN)

func _wire(c: Chip) -> void:
	chips[c.id] = c
	c.down.connect(func(id: String) -> void: pressed.emit(id))
	c.up.connect(func(id: String) -> void: tapped.emit(id))

## A cream chip: a glyph and a few words, at least `tap` tall.
func _chip(id: String, text: String, glyph: String, state: int, tap: float) -> Chip:
	var c := Chip.new()
	c.setup(id, state, 0, tap, Vector2(24.0, 10.0))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(row)
	var ic := Icon.new()
	ic.setup(glyph, 44.0, art_factory, Style.TEXT if state != 1 else Style.TEXT_QUIET)
	row.add_child(ic)
	var l := label(text, Style.SZ_S, Style.TEXT if state != 1 else Style.TEXT_QUIET, HORIZONTAL_ALIGNMENT_LEFT, false, Style.text(), "button")
	row.add_child(l)
	_wire(c)
	return c

func _primary(id: String, text: String, min_h: float) -> Chip:
	var c := Chip.new()
	c.setup(id, 0, 1, min_h, Vector2(24.0, 10.0))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := label(text, Style.SZ_XL, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false, Style.display())
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fs := Style.fit_size(text, Style.SZ_XL, 40, 900.0)
	l.add_theme_font_size_override("font_size", fs)
	c.add_child(l)
	_wire(c)
	return c

## An improvement: icon, name, level pips and the next price (or MAX).
func _imp_chip(id: String, im: Dictionary, price: int, state: int, tap: float) -> Chip:
	var c := Chip.new()
	c.setup(id, state, 0, maxf(176.0, tap), Vector2(10.0, 12.0))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ink := Style.TEXT if state != 1 else Style.TEXT_QUIET
	var v := vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var ic := Icon.new()
	ic.setup(im["id"], 48.0, art_factory, ink)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(label(im["name"], 26, ink, HORIZONTAL_ALIGNMENT_CENTER, true, Style.text(), "button"))
	var pips := Pips.new()
	pips.level = int(im["level"])
	v.add_child(pips)
	if price > 0:
		var cr := hbox(6)
		cr.alignment = BoxContainer.ALIGNMENT_CENTER
		var ci := Icon.new()
		ci.setup("coin", 30.0, art_factory, Color(1, 1, 1, 1.0 if state != 1 else 0.5))
		cr.add_child(ci)
		cr.add_child(label(str(price), Style.SZ_S, ink, HORIZONTAL_ALIGNMENT_LEFT, false, Style.display()))
		v.add_child(cr)
	else:
		v.add_child(label("MAX", Style.SZ_S, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_CENTER, false, Style.text()))
	_wire(c)
	return c
