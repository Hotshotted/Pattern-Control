class_name ResetConfirm
extends Control
## "Reset progress" in the settings (the pause menu): a dimmed sheet with a plain warning and a button that has to be HELD (Tuning.reset_hold_seconds) before
## everything is erased. Letting go early, or Cancel, changes nothing. Built from containers (like Tally), so nothing overlaps on a small phone.

signal confirmed
signal cancelled

const WARNING := "This erases EVERYTHING: coins, levels, stars, purchases, goals, streak, mastery, achievements and the tutorial tips. It cannot be undone."

var card: PanelContainer
var hold_chip: DetailSheet.Chip
var cancel_chip: DetailSheet.Chip
var _sb_hold: StyleBoxFlat
var _label: Label
var hold_seconds := 2.0
var held_t := 0.0
var progress := 0.0
var _done := false
var art_factory: Callable

func build(vp: Vector2, safe_bottom: float) -> void:
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
	add_child(scrim)
	var w := minf(vp.x - 72.0, 960.0)
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := Style.box(Style.SURFACE_DARK, Style.DANGER, Style.R_L, 6, true)
	sb.content_margin_left = 40.0
	sb.content_margin_right = 40.0
	sb.content_margin_top = 36.0
	sb.content_margin_bottom = 36.0
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	card.size = Vector2(w, 100.0)
	var v := DetailSheet.vbox(20)
	card.add_child(v)
	v.add_child(DetailSheet.label("Reset progress?", Style.SZ_M, Style.DANGER, HORIZONTAL_ALIGNMENT_CENTER, true, Style.display()))
	v.add_child(DetailSheet.label(WARNING, Style.SZ_BODY, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.text(), "body"))
	v.add_child(DetailSheet.label("Press and HOLD the red button to erase. Let go to keep your game.", Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.text(), "caption"))
	hold_chip = DetailSheet.Chip.new()
	hold_chip.setup("reset_hold", 0, 0, maxf(130.0, Style.tap_px()), Vector2(24.0, 10.0))
	hold_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sbh := Style.box(Style.DANGER, Style.DANGER.darkened(0.3), Style.R_L, 0, true)
	sbh.content_margin_left = 24.0
	sbh.content_margin_right = 24.0
	sbh.content_margin_top = 10.0
	sbh.content_margin_bottom = 10.0
	hold_chip.add_theme_stylebox_override("panel", sbh)
	_sb_hold = sbh
	var l := DetailSheet.label("Hold to erase everything", Style.SZ_M, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true, Style.display())
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label = l
	hold_chip.add_child(l)
	v.add_child(hold_chip)
	cancel_chip = DetailSheet.Chip.new()
	cancel_chip.setup("reset_cancel", 0, 0, maxf(110.0, Style.tap_px()), Vector2(24.0, 8.0))
	cancel_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cl := DetailSheet.label("Keep my game", Style.SZ_BODY, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.display())
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_chip.add_child(cl)
	cancel_chip.up.connect(func(_id: String) -> void: cancelled.emit())
	v.add_child(cancel_chip)
	card.position = Vector2((vp.x - w) * 0.5, 0.0)
	settle()
	card.size = Vector2(w, card.get_combined_minimum_size().y)
	card.position = Vector2((vp.x - w) * 0.5, maxf((vp.y - card.size.y - safe_bottom) * 0.5, Style.safe_top + 16.0))
	settle()
	_show_progress()

func settle() -> void:
	for pass_k in 4:
		DetailSheet._sort_down(self)
		DetailSheet._sort(self)

## The red button fills with warm gold as it is held, and says how far.
func _show_progress() -> void:
	if _sb_hold == null:
		return
	_sb_hold.bg_color = Style.DANGER.lerp(Color(0.95, 0.62, 0.2), progress)
	_label.text = "Hold to erase everything" if progress <= 0.001 else "Erasing... %d%%" % roundi(progress * 100.0)

func _process(delta: float) -> void:
	if _done or hold_chip == null:
		return
	if hold_chip._held:
		held_t += delta
	else:
		held_t = 0.0
	progress = clampf(held_t / maxf(hold_seconds, 0.05), 0.0, 1.0)
	_show_progress()
	if progress >= 1.0:
		_done = true
		confirmed.emit()
