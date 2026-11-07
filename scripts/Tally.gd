class_name Tally
extends Control
## The "welcome back" screen: what the parked planes earned while the player was away (offline hangar income), per airport, and a Collect button.
## Built from containers (like DetailSheet) so nothing can overlap on a small phone; a dark scrim behind swallows taps.

signal collected

var card: PanelContainer
var collect_chip: DetailSheet.Chip
var art_factory: Callable

## `info` = {"total", "hours", "lines": [[airport name, coins]]}.
func build(info: Dictionary, vp: Vector2, safe_bottom: float) -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO
	size = vp
	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.04, 0.03, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.size = vp
	add_child(scrim)
	var w := minf(vp.x - 72.0, 960.0)
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := Style.box(Style.SURFACE_DARK, Style.EDGE, Style.R_L, 0, true)
	sb.content_margin_left = 40.0
	sb.content_margin_right = 40.0
	sb.content_margin_top = 36.0
	sb.content_margin_bottom = 36.0
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	card.size = Vector2(w, 100.0)
	var v := DetailSheet.vbox(18)
	card.add_child(v)
	v.add_child(DetailSheet.label("Welcome back!", Style.SZ_M, Style.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.display()))
	var hrs := float(info["hours"])
	var away := "%d h %02d min away" % [int(hrs), roundi((hrs - floorf(hrs)) * 60.0)] if hrs >= 1.0 else "%d min away" % maxi(roundi(hrs * 60.0), 1)
	if hrs >= Rhythm.OFFLINE_CAP_HOURS - 0.01:
		away += " (the hangars earn for up to %d hours)" % int(Rhythm.OFFLINE_CAP_HOURS)
	v.add_child(DetailSheet.label("Your parked planes were busy: %s" % away, Style.SZ_CAPTION, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, true, Style.text(), "caption"))
	var big := DetailSheet.hbox(12)
	big.alignment = BoxContainer.ALIGNMENT_CENTER
	var ci := DetailSheet.Icon.new()
	ci.setup("coin", 72.0, art_factory)
	big.add_child(ci)
	big.add_child(DetailSheet.label("+%d" % int(info["total"]), Style.SZ_XL, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_CENTER, false, Style.display()))
	v.add_child(big)
	for ln in info["lines"]:
		var row := DetailSheet.hbox(12)
		var nm := DetailSheet.label(str(ln[0]), Style.SZ_BODY, Style.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, Style.text(), "body")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(DetailSheet.label("+%d" % int(ln[1]), Style.SZ_BODY, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_RIGHT, false, Style.text(), "body"))
		v.add_child(row)
	collect_chip = DetailSheet.Chip.new()
	collect_chip.setup("tally_ok", 0, 1, maxf(130.0, Style.tap_px()), Vector2(24.0, 10.0))
	collect_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := DetailSheet.label("Collect", Style.SZ_XL, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false, Style.display())
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	collect_chip.add_child(l)
	collect_chip.up.connect(func(_id: String) -> void: collected.emit())
	v.add_child(collect_chip)
	card.position = Vector2((vp.x - w) * 0.5, 0.0)
	settle()
	card.size = Vector2(w, card.get_combined_minimum_size().y)
	card.position = Vector2((vp.x - w) * 0.5, maxf((vp.y - card.size.y - safe_bottom) * 0.5, Style.safe_top + 16.0))
	settle()

func settle() -> void:
	for pass_k in 4:
		DetailSheet._sort_down(self)
		DetailSheet._sort(self)
