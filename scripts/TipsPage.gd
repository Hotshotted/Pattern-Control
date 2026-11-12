class_name TipsPage
extends Control
## Settings > Tips: every tip seen so far, to read again (the topic, then the sentence). A dimmed sheet with a scrolling list; the x or a tap outside closes it.

signal closed

var card: PanelContainer
var scroll: KScroll
var close_chip: DetailSheet.Chip

func build(seen: Dictionary, vp: Vector2, safe_bottom: float) -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO
	size = vp
	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.04, 0.03, 0.78)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.size = vp
	scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			closed.emit())
	add_child(scrim)
	var w := minf(vp.x - 72.0, 960.0)
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := Style.box(Style.SURFACE_DARK, Style.EDGE, Style.R_L, 0, true)
	sb.content_margin_left = 36.0
	sb.content_margin_right = 36.0
	sb.content_margin_top = 28.0
	sb.content_margin_bottom = 32.0
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	card.size = Vector2(w, 100.0)
	var v := DetailSheet.vbox(16)
	card.add_child(v)
	var head := DetailSheet.hbox(12)
	var title := DetailSheet.label("Tips", Style.SZ_M, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, Style.display())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	close_chip = DetailSheet.Chip.new()
	close_chip.setup("tips_close", 0, 0, maxf(96.0, Style.tap_px()), Vector2(26.0, 6.0))
	close_chip.custom_minimum_size.x = maxf(96.0, Style.tap_px())
	var xl := DetailSheet.label("×", Style.SZ_XL, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, false, Style.display())
	xl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_chip.add_child(xl)
	close_chip.up.connect(func(_id: String) -> void: closed.emit())
	head.add_child(close_chip)
	v.add_child(head)
	scroll = KScroll.new()
	var list := DetailSheet.vbox(14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := w - 72.0
	var ids := Tips.seen_ids(seen)
	if ids.is_empty():
		var none := DetailSheet.label("No tips yet. They appear the first time something happens.", Style.SZ_BODY, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "body")
		none.custom_minimum_size.x = inner
		list.add_child(none)
	for id in ids:
		var topic := DetailSheet.label(str(Tips.LIST[id]["what"]), Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_LEFT, false, Style.text(), "caption")
		list.add_child(topic)
		var sentence := DetailSheet.label(Tips.text(id), Style.SZ_BODY, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "body")
		sentence.custom_minimum_size.x = inner
		list.add_child(sentence)
	scroll.add_child(list)
	scroll.custom_minimum_size = Vector2(inner, 60.0)
	v.add_child(scroll)
	card.position = Vector2((vp.x - w) * 0.5, 0.0)
	settle()
	scroll.custom_minimum_size = Vector2(inner, minf(list.get_combined_minimum_size().y + 8.0, vp.y * 0.55))       # (measured once the labels have their widths)
	settle()
	card.size = Vector2(w, card.get_combined_minimum_size().y)
	card.position = Vector2((vp.x - w) * 0.5, maxf((vp.y - card.size.y - safe_bottom) * 0.5, Style.safe_top + 16.0))
	settle()

func settle() -> void:
	for pass_k in 4:
		DetailSheet._sort_down(self)
		DetailSheet._sort(self)
