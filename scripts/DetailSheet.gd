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
var holds := {}                          # id of a hold-to-buy button -> its HoldFill

## One tappable cream chip: a PanelContainer around its content, so it is as big as its content (and its minimum height).
class Chip extends PanelContainer:
	signal down(id: String)
	signal up(id: String)
	signal cancelled(id: String)
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
		mouse_filter = Control.MOUSE_FILTER_PASS         # (a drag that starts on a chip still scrolls the list under it)
		custom_minimum_size = Vector2(0.0, min_h)
		_sb = DetailSheet.chip_styles(kind, state, pad)
		add_theme_stylebox_override("panel", _sb["normal"])

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion and _held and ev.global_position.distance_to(_from) >= 24.0:
			cancel()          # (it became a scroll: not a tap, and a hold-to-buy stops)
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
		cancelled.emit(id)
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

## The level pips of an improvement (one per level, filled up to the level reached).
class Pips extends Control:
	var level := 0
	var max_level := Improvements.MAX_LEVEL

	func setup(p_level: int, p_max: int) -> void:
		level = p_level
		max_level = p_max
		custom_minimum_size = Vector2(float(max_level) * 26.0, 24.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _init() -> void:
		custom_minimum_size = Vector2(float(max_level) * 26.0, 24.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for q in max_level:
			var c := Vector2(13.0 + q * 26.0, size.y * 0.5)
			draw_circle(c, 10.0, Style.INK)
			draw_circle(c, 7.5, Style.ACCENT if q < level else Color(0.86, 0.78, 0.62))

## The fill that runs across a hold-to-buy button while it is held.
class HoldFill extends Control:
	var hold := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		if hold > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(hold, 0.0, 1.0), size.y)), Color(1.0, 1.0, 1.0, 0.38))

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
	var keep_scroll := scroll.scroll_vertical if (scroll != null and is_instance_valid(scroll)) else 0
	var improve: bool = bool(info["open"]) and int(info.get("tab", 0)) == 1
	var y0 := 0.0 if improve else vp.y * float(info.get("split", 0.667))       # (the Improve sheet is the whole screen: a list needs the height)
	position = Vector2(0.0, y0)
	size = Vector2(vp.x, vp.y - y0)
	holds.clear()
	var tap := Style.tap_px()
	var locked: bool = not bool(info["open"])
	var i: int = info["i"]
	var w := minf(vp.x - 36.0 - safe_left - safe_right, MAX_W)

	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP          # (the sheet swallows taps: they never reach the field behind it)
	var sb := Style.box(Style.SURFACE_DARK, Style.EDGE, Style.R_L, 0, true)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	if improve:
		sb.corner_radius_top_left = 0
		sb.corner_radius_top_right = 0
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	card.position = Vector2((vp.x + safe_left - safe_right - w) * 0.5, 0.0)
	card.size = Vector2(w if not improve else vp.x, size.y + 40.0)                    # (it runs 40 under the screen's edge: no rounded bottom corners show)
	if improve:
		card.position = Vector2.ZERO
		w = vp.x - safe_left - safe_right

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(GUTTER))
	margin.add_theme_constant_override("margin_right", int(GUTTER))
	margin.add_theme_constant_override("margin_top", int(28.0 + (Style.safe_top if improve else 0.0)))
	if improve:
		margin.add_theme_constant_override("margin_left", int(GUTTER + safe_left))
		margin.add_theme_constant_override("margin_right", int(GUTTER + safe_right))
	margin.add_theme_constant_override("margin_bottom", int(24.0 + 40.0 + safe_bottom))
	card.add_child(margin)
	var col := vbox(16)
	margin.add_child(col)
	if improve:
		_improve_header(col, info, tap)

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
	if not improve:
		var names := vbox(2)
		_fill(names)
		names.custom_minimum_size.x = 8.0
		body.add_child(names)
		var nm: String = info["name"]
		var nfs := Style.fit_size(nm, 64, Style.SZ_BODY, inner_w)
		names.add_child(label(nm, nfs, Style.TEXT if not locked else Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.display()))
		var tag_txt: String = info["tag"] + ((" \u00b7 Best %d" % int(info["best"])) if (not locked and int(info["best"]) > 0) else "")
		names.add_child(label(tag_txt, 28, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.body()))
	if not locked and not improve:
		var tabs := hbox(10)
		body.add_child(tabs)
		tabs.add_child(_chip("dtab:0", "Stars", "star", 2 if tab == 0 else 0, tap))
		tabs.add_child(_chip("dtab:1", "Improve", "upgrades", 2 if tab == 1 else 0, tap))

	# ---- the tab's content ----
	if tab == 0 and not locked:
		_glance(body, info, tap)
	elif locked:
		var stars_row := hbox(8)
		body.add_child(stars_row)
		for k in 3:
			var cellv := vbox(6)
			_fill(cellv)
			stars_row.add_child(cellv)
			var ic := Icon.new()
			ic.setup("star_off", 64.0, art_factory)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cellv.add_child(ic)
			var htxt := ("Land %d" % int(info["land"][0])) if k == 0 else ("Net %d" % int(info["coins"][k]))
			cellv.add_child(label(htxt, 32, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.display()))
	if improve:
		for im in info["imps"]:
			body.add_child(_imp_row(i, im, str(info.get("imp_sel", "")) == str(im["id"]), int(info["bank"]), tap))

	if not locked and not improve:
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
		var ul := label(str(info.get("lock_text", "Unlock with %d %s" % [n, "star" if n == 1 else "stars"])), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, true, Style.display())
		_fill(ul)
		pr.add_child(ul)
		var si := Icon.new()
		si.setup("star", 48.0, art_factory)
		pr.add_child(si)
		pill.custom_minimum_size.y = maxf(100.0, tap)
		col.add_child(pill)
	elif improve:
		col.add_child(_primary("imp_done", "Done", maxf(130.0, tap)))
	else:
		fly = _primary("airport:%d" % i, "Fly here", maxf(130.0, tap))
		col.add_child(fly)
	settle()
	if improve and keep_scroll > 0:
		scroll.scroll_vertical = keep_scroll

## The airport at a glance (everything on one scroll, nothing to dig for): the level and its bar, the next unlock, the first goal (until something is
## bought here), the three star objectives, the mastery rank, today's goals and the No engines switch.
func _glance(body: VBoxContainer, info: Dictionary, tap: float) -> void:
	var lv: Dictionary = info["level"]
	# ---- the level, and how far to the next ----
	var lrow := hbox(16)
	body.add_child(lrow)
	var big := label("Level %d" % int(lv["level"]), Style.SZ_M, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, Style.display())
	lrow.add_child(big)
	var lcol := vbox(4)
	_fill(lcol)
	lcol.custom_minimum_size.x = 8.0
	lcol.alignment = BoxContainer.ALIGNMENT_CENTER
	lrow.add_child(lcol)
	var ltxt := "%d XP to level %d" % [int(lv["left"]), int(lv["level"]) + 1] if int(lv["need"]) > 0 else "Top level"
	lcol.add_child(label(ltxt, Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, true, Style.text(), "caption"))
	var lbar := Bar.new()
	lbar.frac = float(lv["frac"])
	lbar.top = int(lv["need"]) <= 0
	lcol.add_child(lbar)
	# ---- the next unlock ----
	var nx: Dictionary = info["next"]
	if not nx.is_empty():
		body.add_child(_card("upgrades", "Level %d: %s" % [int(nx["level"]), str(nx["title"])], str(nx["detail"])))
	# ---- the first goal ----
	if info.has("first_goal"):
		var fg: Dictionary = info["first_goal"]
		var c := _card("coin", "First goal: %s for %d" % [str(fg["name"]), int(fg["price"])], "You have %d: %s" % [int(fg["have"]), "enough, buy it on the Improve tab" if int(fg["have"]) >= int(fg["price"]) else "%d to go" % (int(fg["price"]) - int(fg["have"]))], true)
		body.add_child(c)
	# ---- the three star objectives ----
	var names: Array = info["star_names"]
	for k in 3:
		var have: bool = k < int(info["stars"])
		var req := "Land %d and finish the shift" % int(info["land"][0]) if k == 0 else "Net %d after fines" % int(info["coins"][k])
		body.add_child(_card("star" if have else "star_off", str(names[k]), "%s  \u00b7  +%d XP each shift" % [req, int(Progression.XP_STAR[k])]))
	body.add_child(label("Hangar %d, profit after %d landings" % [int(info["hangar"]), int(info["land"][0])], Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.text(), "caption"))
	_extras(body, info, tap)
	# ---- the weekly event ----
	if info.has("event"):
		var ev: Dictionary = info["event"]
		var prog := "%d points" % int(ev["points"]) + ("  \u00b7  next reward at %d" % int(ev["next"]) if int(ev["next"]) > 0 else "  \u00b7  every reward earned")
		body.add_child(_card("flame", "This week: %s" % str(ev["name"]), "%s  \u00b7  %s" % [str(ev["text"]), prog]))
	# ---- today's goals at this airport ----
	if info.has("daily"):
		for g in info["daily"]:
			body.add_child(_card("check" if bool(g["done"]) else "daily", str(g["text"]), "%s  \u00b7  +%d coins" % ["Done" if bool(g["done"]) else "Today", int(g["reward"])]))

## A read-only card: a picture, a line and a smaller line under it.
func _card(glyph: String, title: String, sub: String, accent: bool = false) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Style.box(Style.SURFACE_DARK, Style.ORANGE if accent else Style.EDGE, Style.R_M, 5 if accent else 0, not accent)
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size.y = 64.0 * Style.px_per_pt
	var r := hbox(16)
	pc.add_child(r)
	var ic := Icon.new()
	ic.setup(glyph, 64.0, art_factory, Style.TEXT)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var v := vbox(2)
	_fill(v)
	v.custom_minimum_size.x = 8.0
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_child(v)
	v.add_child(label(title, Style.SZ_BODY, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "body"))
	v.add_child(label(sub, Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "caption"))
	return pc

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
	for pass_k in 4:
		_sort_down(self)         # (a parent hands its width to its children...)
		_sort(self)              # (...and the children's wrapped heights go back up)

static func _sort_down(n: Node) -> void:
	if n is Container:
		n.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in n.get_children():
		_sort_down(c)

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

## The Improve sheet's top: a clear Back, the title and the coins in the bank.
func _improve_header(col: VBoxContainer, info: Dictionary, tap: float) -> void:
	var hb := hbox(14)
	col.add_child(hb)
	var back := _chip("dtab:0", "Back", "back", 0, maxf(tap, 64.0 * Style.px_per_pt))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hb.add_child(back)
	var tv := vbox(0)
	_fill(tv)
	tv.custom_minimum_size.x = 8.0
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(tv)
	tv.add_child(label("Improve", Style.SZ_M, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.display()))
	tv.add_child(label(str(info["name"]), Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "caption"))
	var bank := hbox(8)
	bank.alignment = BoxContainer.ALIGNMENT_END
	var ci := Icon.new()
	ci.setup("coin", 44.0, art_factory)
	bank.add_child(ci)
	bank.add_child(label(str(int(info["bank"])), Style.SZ_BODY, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_RIGHT, false, Style.display()))
	hb.add_child(bank)

## One improvement as a row: icon, full name, level pips, a one-line effect and (on the right) a big cost button you hold to buy.
## Tapping the row selects it: it then shows what the next level changes.
func _imp_row(i: int, im: Dictionary, selected: bool, bank: int, tap: float) -> Chip:
	var price: int = im["price"]
	var maxed := price < 0
	var locked: bool = bool(im.get("locked", false))
	var can := not maxed and not locked and bank >= price
	var c := Chip.new()
	c.setup("imp:%d:%s" % [i, im["id"]], 2 if selected else 0, 0, maxf(64.0 * Style.px_per_pt, tap), Vector2(18.0, 12.0))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ink := Style.TEXT
	var row := hbox(16)
	c.add_child(row)
	var ic := Icon.new()
	ic.setup(im["id"], 84.0, art_factory, ink)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tv := vbox(2)
	_fill(tv)
	tv.custom_minimum_size.x = 8.0
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(tv)
	tv.add_child(label(im["name"], Style.SZ_BUTTON, ink, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "button"))
	var pr := hbox(10)
	var pips := Pips.new()
	pips.setup(int(im["level"]), int(im["max"]))
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(pips)
	pr.add_child(label("Level %d of %d" % [int(im["level"]), int(im["max"])], Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, false, Style.text(), "caption"))
	tv.add_child(pr)
	if selected and not maxed:             # the preview: what it does now, what the next level adds
		var now_txt: String = ("Now: " + str(im["now"])) if str(im["now"]) != "" else "Now: not built yet"
		tv.add_child(label(now_txt, Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "caption"))
		tv.add_child(label("Level %d: %s" % [int(im["level"]) + 1, str(im["next"])], Style.SZ_CAPTION, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "caption"))
	elif locked:
		tv.add_child(label("%s  \u00b7  needs airport level %d" % [str(im["next"]), int(im["gate"])], Style.SZ_CAPTION, Style.TEXT_QUIET, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "caption"))
	else:
		tv.add_child(label(str(im["next"]) if not maxed else "Fully built: " + str(im["now"]), Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "caption"))
	if maxed:
		var mx := label("MAX", Style.SZ_BUTTON, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_RIGHT, false, Style.display())
		mx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mx)
	elif locked:
		row.add_child(_lock_badge(int(im["gate"])))
	else:
		row.add_child(_buy_button("impbuy:%d:%s" % [i, im["id"]], price, can, tap))
	_wire(c)
	return c

## Where a locked row's cost button would be: a lock and the airport level that opens it.
func _lock_badge(gate: int) -> Control:
	var v := hbox(8)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.custom_minimum_size.x = 250.0
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var li := Icon.new()
	li.setup("lock", 44.0, art_factory, Style.TEXT_QUIET)
	v.add_child(li)
	v.add_child(label("Level %d" % gate, Style.SZ_BUTTON, Style.TEXT_QUIET, HORIZONTAL_ALIGNMENT_RIGHT, false, Style.text(), "button"))
	return v

## The cost button of a row: the price over a fill that runs across it while held (Tuning.buy_hold_seconds), orange when it can be bought.
func _buy_button(id: String, price: int, can: bool, tap: float) -> Chip:
	var b := Chip.new()
	b.setup(id, 0 if can else 1, 1 if can else 0, maxf(64.0 * Style.px_per_pt - 24.0, tap), Vector2(14.0, 8.0))
	b.custom_minimum_size.x = 250.0
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := HoldFill.new()
	b.add_child(fill)
	holds[id] = fill
	var inner := hbox(8)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ci := Icon.new()
	ci.setup("coin", 40.0, art_factory)
	inner.add_child(ci)
	var l := label(str(price), Style.SZ_BUTTON, Color.WHITE if can else Style.TEXT_QUIET, HORIZONTAL_ALIGNMENT_LEFT, false, Style.display())
	inner.add_child(l)
	b.add_child(inner)
	_wire(b)
	return b

## Fade away for `secs` and come back: a purchase's building grows on the field behind the full-height sheet.
func peek(secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_interval(maxf(secs - 0.4, 0.1))
	tw.tween_property(self, "modulate:a", 1.0, 0.22)

## The fill of a hold-to-buy button (0..1).
func set_hold(id: String, frac: float) -> void:
	var f = holds.get(id)
	if f != null and is_instance_valid(f):
		f.hold = frac
		f.queue_redraw()
