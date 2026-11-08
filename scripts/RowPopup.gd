class_name RowPopup
extends Control
## The detail popup of one results row (an achievement, a goal, a rank ...): a small card centred over the results with a dimmed backdrop, styled like the other
## sheets. It closes on a tap outside the card or on the x. Nothing on the results card expands inline. Built from containers, so the longest text wraps inside.

signal closed

var card: PanelContainer
var close_chip: DetailSheet.Chip
var art_factory: Callable

## `info` = {"glyph", "text", "detail" (optional), "coins"}.
func build(info: Dictionary, vp: Vector2, safe_bottom: float) -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO
	size = vp
	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.04, 0.03, 0.74)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.size = vp
	scrim.gui_input.connect(_scrim_input)         # (a tap outside the card closes it)
	add_child(scrim)
	var w := minf(vp.x - 96.0, 900.0)
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := Style.box(Style.SURFACE_DARK, Style.EDGE, Style.R_L, 0, true)
	sb.content_margin_left = 36.0
	sb.content_margin_right = 36.0
	sb.content_margin_top = 28.0
	sb.content_margin_bottom = 36.0
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	card.size = Vector2(w, 100.0)
	var v := DetailSheet.vbox(18)
	card.add_child(v)
	var head := DetailSheet.hbox(12)
	var gi := DetailSheet.Icon.new()
	gi.setup(str(info.get("glyph", "star")), 64.0, art_factory)
	head.add_child(gi)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	close_chip = DetailSheet.Chip.new()
	close_chip.setup("row_close", 0, 0, maxf(96.0, Style.tap_px()), Vector2(26.0, 6.0))
	close_chip.custom_minimum_size.x = maxf(96.0, Style.tap_px())
	var xl := DetailSheet.label("×", Style.SZ_XL, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, false, Style.display())
	xl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_chip.add_child(xl)
	close_chip.up.connect(func(_id: String) -> void: closed.emit())
	head.add_child(close_chip)
	v.add_child(head)
	var inner := w - 72.0                      # (a wrapping label gets its width up front, so its height is right at once)
	var tl := DetailSheet.label(str(info["text"]), Style.SZ_M, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.display())
	tl.custom_minimum_size.x = inner
	v.add_child(tl)
	if str(info.get("detail", "")) != "":
		var dl := DetailSheet.label(str(info["detail"]), Style.SZ_BODY, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "body")
		dl.custom_minimum_size.x = inner
		v.add_child(dl)
	if int(info.get("coins", 0)) > 0:
		var rw := DetailSheet.hbox(12)
		var ci := DetailSheet.Icon.new()
		ci.setup("coin", 56.0, art_factory)
		rw.add_child(ci)
		rw.add_child(DetailSheet.label("+%d coins" % int(info["coins"]), Style.SZ_BODY, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_LEFT, false, Style.display(), "body"))
		v.add_child(rw)
	card.position = Vector2((vp.x - w) * 0.5, 0.0)
	settle()
	card.size = Vector2(w, card.get_combined_minimum_size().y)
	card.position = Vector2((vp.x - w) * 0.5, maxf((vp.y - card.size.y - safe_bottom) * 0.5, Style.safe_top + 16.0))
	settle()

func settle() -> void:
	for pass_k in 4:
		DetailSheet._sort_down(self)
		DetailSheet._sort(self)

func _scrim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		closed.emit()
