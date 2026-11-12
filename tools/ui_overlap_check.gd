extends SceneTree
## The UI overlap audit. Opens every screen, panel, popup, tab and state of the game at six screen sizes and reports, in pairs:
##   - overlap     two visible things (text, buttons, labels, icons) whose screen rectangles overlap, unless one is nested in the
##                 other on purpose (a label inside its own button);
##   - clipped     text wider than its box, a wrapped run that lost its last line, text that leaves the button it belongs to;
##   - off-screen  anything partly outside the screen;
##   - safe-area   anything under the notch / Dynamic Island / home bar;
##   - tap-size    a button smaller than 44 points (Apple's minimum), or one another button sits on top of (a tap cannot reach it);
##   - (clipped, also) a label or drawn text that sticks out of the tile / row / card it sits on, even inside a scroll list (a row cut by the
##                 scroll's edge is allowed: only its width counts then), and, on the results screen, text under or beside the card
##   - small-text  text under the floor of its role (caption 11 pt, body 15 pt, button label 17 pt, on a 390-pt phone), or at a size the pre-warm does not rasterise.
## Every state is measured after it has settled: panel animations and tweens run to their end, then frames pass until nothing moves (`_settle`).
## Each problem gets a line; each screen at each size can be saved as a picture with the problems outlined in red.
##
##   godot --headless --path . --script tools/ui_overlap_check.gd                          (the check only: fast, no pictures)
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script tools/ui_overlap_check.gd -- shots=docs/ui_audit
##
## Arguments (after --):  shots=<dir>   save the pictures there        only=<text>   only states whose name contains it
##                        sizes=<a,b>   only those sizes ("390x844")    report=<file> write every problem as JSON there
##                        plant         self-test: a label across the PLAY button, one pushed out of an Improve row, one under the results card
##                                      (each with only="menu planted" / "planted tile" / "planted card"); the exit code must then be 1
##                        quiet         print only the totals          baseline=<file> compare with an earlier report: print what is new
## The exit code is 1 if there is any problem that is not in ALLOW (the allowlist below), 0 otherwise.

# ---- the sizes: logical points (what the phone reports), and the safe area in points ----
# name, width, height, top inset, bottom inset (the game hides the status bar; the insets are the notch / island and the home bar)
const SIZES := [
	{"name": "320x568", "w": 320, "h": 568, "top": 0.0, "bottom": 0.0, "dev": "iPhone SE (1st gen)"},
	{"name": "375x667", "w": 375, "h": 667, "top": 0.0, "bottom": 0.0, "dev": "iPhone SE (2nd, 3rd gen)"},
	{"name": "390x844", "w": 390, "h": 844, "top": 47.0, "bottom": 34.0, "dev": "iPhone 14"},
	{"name": "430x932", "w": 430, "h": 932, "top": 59.0, "bottom": 34.0, "dev": "iPhone 14 Pro Max (Dynamic Island)"},
	{"name": "768x1024", "w": 768, "h": 1024, "top": 24.0, "bottom": 20.0, "dev": "iPad"},
	{"name": "1280x720", "w": 1280, "h": 720, "top": 0.0, "bottom": 0.0, "dev": "landscape web"},
]

# ---- the allowlist: things that overlap on purpose. Every entry says why. ----
# Fields: screen (glob on the state name), size (glob, optional), type, a / b (substring of an element's text or id; b optional), why.
const ALLOW := [
	{"screen": "tutorial results*", "type": "overlap", "a": "", "b": "", "why": "Day 1's tip card sits over the results on purpose (it points at the stars and the first upgrade); a tap puts it away"},
	{"screen": "tutorial results*", "type": "clipped", "a": "", "b": "", "why": "the same card over the results"},
	{"screen": "settings tips page*", "type": "clipped", "a": "", "b": "", "why": "the list of tips scrolls inside its card: a row cut by the list's edge is the scroll"},
]

var out_dir := ""
var only := ""
var sizes_arg := ""
var report_path := ""
var baseline_path := ""
var quiet := false
var plant := false                    # self-test: put a label across the PLAY button, which the check must report (CI runs this and expects exit code 1)
var main: Node
var hud: Node
var save: Node
var vp := Vector2.ZERO
var ppp := 2.77                       # viewport units per point
var cur_size: Dictionary = {}
var cur_state := ""
var problems: Array = []              # every problem, across sizes: {size, screen, type, a, b, detail}
var allowed_count := 0
var state_count := 0
var shot_count := 0
## What the tool does not open, and why (printed with the totals, so nothing is skipped silently).
var unreachable: Array = [
	"privacy policy page: it opens the system browser (web/privacy.html), it is not an in-game screen",
	"TUNE panel and perf overlay: developer tools behind ?tune / ?perf in the page address, never shown to players",
	"confirmation dialogs: the game has none (the shop's hold-to-buy sheet is covered: 'preview ...' states)",
	"popups: where one appears depends on where the aircraft is; they are checked at the screen's left, middle and right edges",
]
var rendering := false
var screens_seen := {}
var scrolling := {}                   # "screen family" -> {size name -> true}: states whose content is taller than the room, so they scroll
var cur_boxes: Array = []             # the panels / cards / pills drawn in the state being checked

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			out_dir = a.substr(6)
		elif a.begins_with("only="):
			only = a.substr(5)
		elif a.begins_with("sizes="):
			sizes_arg = a.substr(6)
		elif a.begins_with("report="):
			report_path = a.substr(7)
		elif a.begins_with("baseline="):
			baseline_path = a.substr(9)
		elif a == "quiet":
			quiet = true
		elif a == "plant":
			plant = true
	rendering = DisplayServer.get_name() != "headless"
	if out_dir != "" and not rendering:
		print("no pictures: the display server is headless (use xvfb-run with --rendering-driver opengl3)")
		out_dir = ""
	save = root.get_node("Save")
	save.path = "user://ui_audit_save.json"
	root.get_node("Tuning").ad_stub_seconds = 0.0
	root.get_node("Tuning").ad_sdk_present = true             # (the rewarded pills are laid out and checked as they will be once an SDK is in)
	root.get_node("Tuning").intro_logo = false
	await _run()
	_finish()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

# ------------------------------------------------------------------------------------------------------------------
# the run: one game instance per size, every state at each
# ------------------------------------------------------------------------------------------------------------------

func _run() -> void:
	for sz in SIZES:
		if sizes_arg != "" and not (sz["name"] in sizes_arg.split(",")):
			continue
		cur_size = sz
		await _open_game(sz)
		print("== %s (%s): viewport %dx%d, %.2f units per point, tap target %d units, safe top %d bottom %d" % [sz["name"], sz["dev"], vp.x, vp.y, ppp, Style.tap_px(), Style.safe_top, Style.safe_bottom])
		await _all_states()
		main.queue_free()
		await _frames(2)

func _open_game(sz: Dictionary) -> void:
	# The viewport the phone gets: the 1080 x 1920 layout, stretched to fit and expanded on the long axis ("expand"). A headless window
	# cannot be resized, so the same viewport is set directly: a fixed content size that is exactly that.
	var asp := float(sz["w"]) / float(sz["h"])
	var want := Vector2(1080.0, 1080.0 / asp) if asp <= 1080.0 / 1920.0 else Vector2(1920.0 * asp, 1920.0)
	if rendering:
		root.size = Vector2i(int(sz["w"]), int(sz["h"]))
		DisplayServer.window_set_size(root.size)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(roundi(want.x), roundi(want.y))
	await _frames(3)
	save.reset_all()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	hud = main.hud
	var guard := 0
	while not main._warming and guard < 120:
		await process_frame
		guard += 1
	guard = 0
	while main._warming and guard < 6000:
		await process_frame
		guard += 1
	guard = 0
	while is_instance_valid(hud._splash) and guard < 600:
		await process_frame
		guard += 1
	main.goals_enabled = false
	main.progress_enabled = false
	for i in Airports.COUNT:                  # (every airfield built, so no "Loading ..." popup is on screen in a state)
		guard = 0
		if not main.airfield.is_built(i):
			main.request_airport(i)
		while not main.airfield.is_built(i) and guard < 900:
			await process_frame
			guard += 1
	vp = root.get_visible_rect().size
	ppp = vp.x / float(sz["w"])
	Style.px_per_pt = ppp
	Style.set_safe(float(sz["top"]) * ppp, float(sz["bottom"]) * ppp, 0.0, 0.0)
	hud.apply_safe()
	await _frames(240)               # (the loading popups fade out)

# ------------------------------------------------------------------------------------------------------------------
# collecting what is on screen
# ------------------------------------------------------------------------------------------------------------------

func _all_arts() -> Array:
	var out: Array = hud._panel_arts.values() + [hud._main_art, hud._tipart]
	if hud.get("_scrolls") != null:
		for e in hud._scrolls.values():
			out.append(e["art"])
	return out

func _arts() -> Array:
	var out := []
	for a in [hud._main_art, hud._tipart] + hud._panel_arts.values():
		if is_instance_valid(a) and a.is_visible_in_tree() and a.position.x > -5000.0:
			out.append(a)
	if main != null and (main.get("_reset_ui") != null or main.get("_row_popup") != null or main.get("_tips_page") != null):
		return []            # the reset sheet is a modal of its own (scrim over the pause menu): what is under it is not on screen
	# a sheet over a list (the shop's preview) hides the list: its scrim takes every tap, so what is under it is not on screen
	for a in out:
		if a.pv_on:
			return [a]
	return out

func _effective_alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n != null and n is CanvasItem:
		a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	return a

func _label_rect(l: Label) -> Rect2:
	## The rectangle the ink of a Label really covers (not the Label's own, often much wider, box): its text width, from the top of the
	## capitals on the first line to the bottom of the last one.
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var g := l.get_global_rect()
	var lines := maxi(l.get_line_count(), 1)
	var lh := f.get_height(fs) + float(l.get_theme_constant("line_spacing"))
	var th := float(lines) * lh
	var tw := 0.0
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		tw = minf(f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, g.size.x)
		if lines > 1:
			tw = g.size.x
	else:
		tw = f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := g.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = g.position.x + (g.size.x - tw) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = g.end.x - tw
	var y := g.position.y
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y = g.position.y + (g.size.y - th) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y = g.end.y - th
	var asc := f.get_ascent(fs)
	var top := y + asc - 0.74 * float(fs)
	var desc := 0.22 if (l.text.contains("g") or l.text.contains("j") or l.text.contains("p") or l.text.contains("q") or l.text.contains("y") or l.text.contains(",")) else 0.04
	var bot := y + float(lines - 1) * lh + asc + float(fs) * desc
	return Rect2(x, top, tw, maxf(bot - top, 4.0))

## Everything visible, as a flat list of elements:
##   {"k": "text" | "glyph" | "button" | "label" | "icon", "id", "text", "rect", "inter": bool, "size": int, "over": bool, "limit": float}
func _collect() -> Array:
	var els: Array = []
	cur_boxes = []
	for art in _arts():
		for bx in art.rec_boxes:
			var br: Rect2 = bx
			if br.size.x >= 24.0 and br.size.y >= 24.0 and br.size.x * br.size.y < 0.6 * vp.x * vp.y:
				cur_boxes.append(br)
		# (an older checkout, which the baseline run reads, has no hit areas: its buttons are tapped where they are drawn)
		var has_hits: bool = art.has_method("refresh_hits")
		if has_hits and art.hits_dirty:
			art.refresh_hits()
		for k in art.btn_count:
			if art.btn_kind[k] == 11:
				continue                       # (an invisible catcher: a sheet's scrim)
			els.append({"k": "button", "id": art.btn_id[k], "text": art.btn_text[k], "rect": art.btn_rect[k], "hit": art.btn_hit[k] if has_hits else art.btn_rect[k], "inter": true, "state": art.btn_state[k], "src": "art"})
		if art.show_play and art.pause_rect.size.x > 0.0:
			els.append({"k": "button", "id": "pause", "text": "", "rect": art.pause_rect, "hit": art._slop(art.pause_rect.grow(6.0)) if has_hits else art.pause_rect.grow(6.0), "inter": true, "state": 0, "src": "art"})
		if art.show_pause and art == hud._art and art.slider_rect[0].size.x > 0.0:
			for i in 3:
				var sh: Rect2 = art.slider_rect[i].grow_individual(40.0, 20.0, 40.0, 20.0)
				els.append({"k": "button", "id": "slider:%d" % i, "text": art.slider_name[i], "rect": art.slider_rect[i], "hit": art._slop(sh) if has_hits else sh, "inter": true, "state": 0, "src": "art"})
		for t in art.rec_texts:
			els.append({"k": "text", "id": "", "text": t["text"], "rect": t["rect"], "inter": false, "size": t["size"], "over": t["over"], "limit": t["limit"], "natural": t["natural"], "src": "art", "layer": str(art.name), "role": t.get("role", "")})
		for g in art.rec_glyphs:
			els.append({"k": "glyph", "id": g["id"], "text": "", "rect": g["rect"], "inter": false, "src": "art", "layer": str(art.name)})
	var modal_up: bool = main != null and (main.get("_reset_ui") != null or main.get("_row_popup") != null or main.get("_tips_page") != null)
	if hud.get("_scrolls") != null and not modal_up and not (hud._panel_arts.has("preview") and hud._panel_arts["preview"].pv_on):
		for e in hud._scrolls.values():
			_collect_scroll(e, els)
	_walk(hud, els)
	_dedupe(els)
	return els

## Which states scroll at this size: a list whose content is taller than its box, or the detail sheet's content taller than its scroll area.
func _note_scrolls(name: String) -> void:
	var tall := false
	for e in (hud._scrolls.values() if hud.get("_scrolls") != null else []):
		if e["host"].is_visible_in_tree() and e["host"].global_position.x > -5000.0 and e["art"].custom_minimum_size.y > e["host"].size.y + 1.0:
			tall = true
	var ds = hud.detail_sheet()
	if ds != null and ds.scroll != null and ds.scroll.is_visible_in_tree() and ds.scroll.global_position.x > -5000.0:
		if ds.scroll.max_scroll() > 1.0:
			tall = true
	if tall:
		var fam := name.split(" ")[0]
		if fam == "shop" or fam == "preview":
			fam = "shop"
		if not scrolling.has(fam):
			scrolling[fam] = {}
		scrolling[fam][cur_size["name"]] = int(scrolling[fam].get(cur_size["name"], 0)) + 1

## A list that scrolls: its buttons, text and icons, in screen coordinates and cut to the visible part of its container.
func _collect_scroll(e: Dictionary, els: Array) -> void:
	var host: KScroll = e["host"]
	var sa = e["art"]
	if not host.is_visible_in_tree() or host.global_position.x < -5000.0:
		return
	var xf: Transform2D = sa.get_global_transform()
	var clip := host.get_global_rect()
	if sa.hits_dirty:
		sa.refresh_hits()
	for k in sa.btn_count:
		var full: Rect2 = xf * sa.btn_rect[k]
		var vis := full.intersection(clip)
		if vis.size.x <= 0.0 or vis.size.y <= 0.0:
			continue
		els.append({"k": "button", "id": sa.btn_id[k], "text": sa.btn_text[k], "rect": vis, "full": full, "hit": xf * sa.btn_hit[k], "inter": true, "state": sa.btn_state[k], "src": "art"})
	for t in sa.rec_texts:
		var tr: Rect2 = xf * (t["rect"] as Rect2)
		var tv := tr.intersection(clip)
		if tv.size.x <= 0.0 or tv.size.y <= 0.0:
			continue
		els.append({"k": "text", "id": "", "text": t["text"], "rect": tv, "full": tr, "inter": false, "size": t["size"], "over": t["over"] and tr.position.y >= clip.position.y and tr.end.y <= clip.end.y, "limit": t["limit"], "natural": t["natural"], "src": "art", "layer": "scroll", "role": t.get("role", "")})
	for g in sa.rec_glyphs:
		var gr: Rect2 = xf * (g["rect"] as Rect2)
		var gv := gr.intersection(clip)
		if gv.size.x > 0.0 and gv.size.y > 0.0:
			els.append({"k": "glyph", "id": g["id"], "text": "", "rect": gv, "inter": false, "src": "art", "layer": "scroll"})
	for bx in sa.rec_boxes:
		var br: Rect2 = (xf * (bx as Rect2)).intersection(clip)          # (only the part of a card that shows: a row below the list's edge is not on the screen)
		if br.size.x >= 24.0 and br.size.y >= 24.0:
			cur_boxes.append(br)

## The part of `r` that shows: cut by every ancestor that clips (a ScrollContainer). An empty rectangle: scrolled out of view.
func _visible_part(c: Control, r: Rect2) -> Rect2:
	var n: Node = c.get_parent()
	while n != null and n is Control:
		if (n as Control).clip_contents:
			r = r.intersection((n as Control).get_global_rect())
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				return Rect2()
		n = n.get_parent()
	return r

## The tile a label sits on: the global rectangle of its nearest ancestor that is a chip (a row, a button) or a panel; empty when it has none.
func _tile_ctl(l: Control) -> Control:
	var n: Node = l.get_parent()
	while n != null and n is Control:
		if n is PanelContainer or (n.has_signal("down") and n.get("id") != null):
			return n as Control
		n = n.get_parent()
	return null

func _tile_rect(l: Control) -> Rect2:
	var t := _tile_ctl(l)
	return t.get_global_rect() if t != null else Rect2()

## The tile is cut by a scroll's edge (a row half scrolled out of view): its edge says nothing about the text in it.
func _tile_cut(l: Control) -> bool:
	var t := _tile_ctl(l)
	if t == null:
		return false
	var g := t.get_global_rect()
	return _visible_part(t, g).size.is_equal_approx(g.size) == false

func _add_leaf(els: Array, ctl: Control, id: String) -> void:
	var r := _visible_part(ctl, ctl.get_global_rect())
	if r.size.x > 0.0 and r.size.y > 0.0:
		els.append({"k": "icon", "id": id, "text": "", "rect": r, "inter": false, "src": "ctl", "node": ctl})

func _walk(n: Node, els: Array) -> void:
	for c in n.get_children():
		if c is Control and not c.has_method("rec_text"):
			var ctl := c as Control
			if ctl.is_visible_in_tree() and _effective_alpha(ctl) > 0.05 and ctl.size.x > 0.0 and ctl.size.y > 0.0 and ctl.global_position.x > -5000.0:
				if ctl is Label:
					var l := ctl as Label
					if l.text != "":
						var r := _visible_part(l, _label_rect(l))
						if r.size.x <= 0.0 or r.size.y <= 0.0:
							continue
						var fs := l.get_theme_font_size("font_size")
						var over := false
						if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
							var nat := l.get_theme_font("font").get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
							over = nat > l.size.x + 1.0 and l.size.x > 0.0 and l.clip_text
						else:
							over = l.get_visible_line_count() < l.get_line_count() or l.get_minimum_size().y > l.size.y + 1.0 and false
						els.append({"k": "label", "id": l.name, "text": l.text, "rect": r, "full": _label_rect(l), "tile": _tile_rect(l), "tile_cut": _tile_cut(l), "inter": false, "size": fs, "over": over, "limit": l.size.x, "natural": r.size.x, "src": "ctl", "node": l, "role": str(l.get_meta("role", "body"))})
				elif ctl.has_signal("down") and ctl.get("id") != null:       # a DetailSheet.Chip
					var cr := _visible_part(ctl, ctl.get_global_rect())
					if cr.size.x > 0.0 and cr.size.y > 0.0:
						els.append({"k": "button", "id": str(ctl.get("id")), "text": "", "rect": cr, "full": ctl.get_global_rect(), "inter": true, "state": int(ctl.get("state")), "src": "ctl", "node": ctl})
				elif ctl.get_script() != null and ctl.has_method("setup") and ctl.get("art") != null:        # DetailSheet.Icon
					_add_leaf(els, ctl, "icon")
				elif ctl.get_script() != null and ctl.get("frac") != null:                                  # DetailSheet.Bar
					_add_leaf(els, ctl, "bar")
				elif ctl.get_script() != null and ctl.get("level") != null:                                 # DetailSheet.Pips
					_add_leaf(els, ctl, "pips")
		_walk(c, els)

## The same string drawn twice a few pixels apart is one run (a shadow, an outline).
func _dedupe(els: Array) -> void:
	var drop := {}
	for i in els.size():
		if els[i]["k"] != "text" or drop.has(i):
			continue
		for j in range(i + 1, els.size()):
			if els[j]["k"] != "text" or drop.has(j):
				continue
			if els[i]["text"] == els[j]["text"] and els[i]["size"] == els[j]["size"] and (els[i]["rect"].position - els[j]["rect"].position).length() <= 8.0:
				drop[j] = true
	var keep: Array = []
	for i in els.size():
		if not drop.has(i):
			keep.append(els[i])
	els.clear()
	els.append_array(keep)

# ------------------------------------------------------------------------------------------------------------------
# the checks
# ------------------------------------------------------------------------------------------------------------------

func _name_of(e: Dictionary) -> String:
	var s: String = e["text"] if e["text"] != "" else (e["id"] if e["id"] != "" else e["k"])
	if e["k"] == "button" and e["id"] != "" and e["text"] != "":
		s = "%s [%s]" % [e["text"], e["id"]]
	elif e["k"] == "glyph":
		s = "icon %s" % e["id"]
	elif e["k"] == "icon":
		s = "icon (%s)" % e["id"]
	return "%s '%s' %s%s" % [e["k"], s.replace("\n", " "), _rs(e["rect"]), (" @" + str(e["layer"])) if e.has("layer") else ""]

func _rs(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]

func _inter_area(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return maxf(i.size.x, 0.0) * maxf(i.size.y, 0.0) if i.size.x > 0.0 and i.size.y > 0.0 else 0.0

## The smallest interactive element holding the centre of `e` (its owner: what it is a label of), or -1.
func _owner(els: Array, idx: int) -> int:
	var e: Dictionary = els[idx]
	var c: Vector2 = (e["rect"] as Rect2).get_center()
	var best := -1
	var best_area := INF
	for j in els.size():
		if j == idx or not els[j]["inter"]:
			continue
		var r: Rect2 = els[j]["rect"]
		if r.has_point(c):
			var a := r.size.x * r.size.y
			if a < best_area:
				best_area = a
				best = j
	return best

func _analyze(els: Array) -> Array:
	var found: Array = []
	var n := els.size()
	var owner: Array = []
	for i in n:
		owner.append(_owner(els, i) if not els[i]["inter"] else -1)
	var screen := Rect2(Vector2.ZERO, vp)
	var top_band := Rect2(0.0, 0.0, vp.x, Style.safe_top)
	var bot_band := Rect2(0.0, vp.y - Style.safe_bottom, vp.x, Style.safe_bottom)
	var tap := Style.tap_px()
	for i in n:
		var e: Dictionary = els[i]
		var r: Rect2 = e["rect"]
		# off-screen, safe area
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > vp.x + 0.5 or r.end.y > vp.y + 0.5:
			found.append({"type": "off-screen", "a": e, "b": null, "detail": "extends %s" % _rs(r.intersection(screen)) if false else "outside the %dx%d screen by %s" % [vp.x, vp.y, _outside(r)]})
		elif (e["k"] == "text" or e["k"] == "label" or e["inter"]) and (_inter_area(r, top_band) > 1.0 or _inter_area(r, bot_band) > 1.0):
			found.append({"type": "safe-area", "a": e, "b": null, "detail": "under the %s" % ("notch / Dynamic Island" if _inter_area(r, top_band) > 1.0 else "home indicator")})
		# clipped text
		if e["k"] == "text" or e["k"] == "label":
			if e["over"]:
				found.append({"type": "clipped", "a": e, "b": null, "detail": "text %d wide in a %d wide box" % [roundi(e["natural"]), roundi(e["limit"])] if e["k"] == "text" and e["limit"] > 0.0 and e["natural"] > e["limit"] else "wrapped text lost its last line"})
			var o: int = owner[i]
			if o >= 0:
				var ob: Rect2 = els[o]["rect"]
				if r.position.x < ob.position.x - 2.0 or r.end.x > ob.end.x + 2.0 or r.position.y < ob.position.y - 2.0 or r.end.y > ob.end.y + 2.0:
					found.append({"type": "clipped", "a": e, "b": els[o], "detail": "text leaves the button it belongs to"})
			if e["src"] == "art":              # text that leaves the panel, card or pill it is drawn on (a row cut by a scroll's edge is fine: only its width counts then)
				var best := Rect2()
				var best_a := INF
				var fr0: Rect2 = e.get("full", r)
				var c: Vector2 = fr0.get_center()
				for bx in cur_boxes:
					var b: Rect2 = bx
					if b.has_point(c) and b.size.x * b.size.y < best_a and b.size.x * b.size.y > 1.0:
						best = b
						best_a = b.size.x * b.size.y
				if best_a < INF and (fr0.size.x < best.size.x * 1.5):
					var cut: bool = not (e["rect"] as Rect2).is_equal_approx(fr0)        # (partly scrolled out of view)
					var g3 := best.grow(3.0)
					var x_ok: bool = fr0.position.x >= g3.position.x and fr0.end.x <= g3.end.x
					var y_ok: bool = cut or (fr0.position.y >= g3.position.y and fr0.end.y <= g3.end.y)
					if not (x_ok and y_ok):
						found.append({"type": "clipped", "a": e, "b": null, "detail": "text leaves the panel it is on %s" % _rs(best)})
			if e["k"] == "label" and (e["tile"] as Rect2).size.x > 0.0:      # a label that sticks out of the tile (row, button, card) it sits on
				var tl: Rect2 = e["tile"]
				var fl: Rect2 = e["full"]
				var tg := tl.grow(2.0)
				var tile_cut: bool = e["tile_cut"]
				if fl.position.x < tg.position.x or fl.end.x > tg.end.x or ((fl.position.y < tg.position.y or fl.end.y > tg.end.y) and not tile_cut):
					found.append({"type": "clipped", "a": e, "b": null, "detail": "text leaves the tile it is in %s" % _rs(tl)})
			if e["k"] == "label" and e.has("node"):
				var lb: Label = e["node"]
				if lb.autowrap_mode != TextServer.AUTOWRAP_OFF:
					var lf := lb.get_theme_font("font")
					var lfs := lb.get_theme_font_size("font_size")
					var longest := 0.0
					for wd in lb.text.split(" "):
						longest = maxf(longest, lf.get_string_size(wd, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x)
					if longest > lb.size.x + 1.0:
						found.append({"type": "clipped", "a": e, "b": null, "detail": "a word (%d wide) is broken across lines in a %d wide label" % [roundi(longest), roundi(lb.size.x)]})
			var role := _role_of(e, els, owner[i])
			var need: int = int(ROLE_MIN_PT[role] * PT + 0.999) if ROLE_MIN_PT.has(role) else 0
			if need > 0 and int(e["size"]) < need:
				found.append({"type": "small-text", "a": e, "b": null, "detail": "%s text at %d units = %.1f pt on a 390-pt phone (minimum %d pt for a %s)" % [role, int(e["size"]), float(e["size"]) / PT, ROLE_MIN_PT[role], role]})
			if not (int(e["size"]) in Style.PREWARM_SIZES):
				found.append({"type": "small-text", "a": e, "b": null, "detail": "size %d is not one the start-up pre-warm rasterises (Style.PREWARM_SIZES): its first use would hitch" % int(e["size"])})
		# tap size
		if e["inter"]:
			var fr: Rect2 = e.get("hit", e.get("full", r))
			var m := minf(fr.size.x, fr.size.y)
			if m < tap - 0.5 and e["state"] != 1:
				found.append({"type": "tap-size", "a": e, "b": null, "detail": "%.0f x %.0f pt (minimum 44 x 44)" % [fr.size.x / ppp, fr.size.y / ppp]})
	# pairs
	for i in n:
		var a: Dictionary = els[i]
		for j in range(i + 1, n):
			var b: Dictionary = els[j]
			if _nested_in_tree(a, b):
				continue                       # (a button on a row that is itself a button, a label in the row: one is inside the other in the node tree, on purpose)
			if a["inter"] and b["inter"]:
				var har := _inter_area(a.get("hit", a["rect"]), b.get("hit", b["rect"]))
				if har > 6.0:
					found.append({"type": "covered", "a": a, "b": b, "detail": "tap areas overlap by %d px: a tap on the shared part reaches only one" % roundi(har)})
				continue
			var ar := _inter_area(a["rect"], b["rect"])
			if ar <= 6.0:
				continue
			# nested on purpose: a label / icon / text inside its own button (all of it: one that sticks out of the button is not nested)
			if a["inter"] and owner[j] == i and (a["rect"] as Rect2).grow(2.0).encloses(b["rect"]):
				continue
			if b["inter"] and owner[i] == j and (b["rect"] as Rect2).grow(2.0).encloses(a["rect"]):
				continue
			if a["inter"] or b["inter"]:
				# a text or icon over a button that is not its own
				var oa: int = owner[i] if not a["inter"] else -1
				var ob2: int = owner[j] if not b["inter"] else -1
				found.append({"type": "overlap", "a": a, "b": b, "detail": "%d px overlap" % roundi(ar)})
				continue
			# two non-interactive things: text over text, text over an icon, icon over icon
			if a["k"] == "glyph" and b["k"] == "glyph":
				continue                       # (glyphs are layered on purpose: coins in a pile, a badge on a circle)
			found.append({"type": "overlap", "a": a, "b": b, "detail": "%d px overlap" % roundi(ar)})
	_results_outside_card(els, found)
	return found

## The results screen: whatever is written between the top of the card and the Next shift button belongs inside the card. (Rows drawn under it
## sat on the dimmed field, faint and hard to read, and no rule noticed: they were over no button and no box.)
func _results_outside_card(els: Array, found: Array) -> void:
	if not cur_state.begins_with("results") or cur_state.contains("details"):
		return
	var ra = hud._panel_arts.get("results")
	if ra == null or not ra.show_result:
		return
	var stk: Dictionary = ra.res_stack()
	var card: Rect2 = stk["card"]
	var next_top: float = ra.res_again().position.y
	for e in els:
		if e["k"] != "text" and e["k"] != "label":
			continue
		var r: Rect2 = e["rect"]
		var c := r.get_center()
		if c.y > card.position.y and c.y < next_top and (r.position.x < card.position.x - 3.0 or r.end.x > card.end.x + 3.0 or r.end.y > card.end.y + 3.0):
			found.append({"type": "clipped", "a": e, "b": null, "detail": "text on the results screen outside the card %s" % _rs(card)})
		elif c.y >= card.end.y and c.y < next_top:
			found.append({"type": "clipped", "a": e, "b": null, "detail": "text on the results screen under the card %s" % _rs(card)})

## One is a descendant of the other in the sheet's node tree and its rectangle lies inside the other's: a part of it, not something on top of it.
func _nested_in_tree(a: Dictionary, b: Dictionary) -> bool:
	if not a.has("node") or not b.has("node"):
		return false
	var na: Node = a["node"]
	var nb: Node = b["node"]
	if na.is_ancestor_of(nb):
		return (a["rect"] as Rect2).grow(2.0).encloses(b["rect"])
	if nb.is_ancestor_of(na):
		return (b["rect"] as Rect2).grow(2.0).encloses(a["rect"])
	return false

func _outside(r: Rect2) -> String:
	var parts := PackedStringArray()
	if r.position.x < -0.5:
		parts.append("left %d" % roundi(-r.position.x))
	if r.position.y < -0.5:
		parts.append("top %d" % roundi(-r.position.y))
	if r.end.x > vp.x + 0.5:
		parts.append("right %d" % roundi(r.end.x - vp.x))
	if r.end.y > vp.y + 0.5:
		parts.append("bottom %d" % roundi(r.end.y - vp.y))
	return ", ".join(parts)

## The role of a text: set where it is drawn (caption), a button's own label, a heading (big, as designed), or body.
func _role_of(e: Dictionary, els: Array, owner_idx: int) -> String:
	var r: String = str(e.get("role", ""))
	if r != "":
		return r
	if int(e["size"]) >= 54:
		return "heading"
	if owner_idx >= 0 and str(els[owner_idx]["text"]) == str(e["text"]):
		return "button"
	return "body"

func _allowed(state: String, p: Dictionary) -> String:
	for al in ALLOW:
		if state.match(al["screen"]) and al["type"] == p["type"]:
			if al.has("size") and not str(cur_size["name"]).match(al["size"]):
				continue
			var an := _name_of(p["a"])
			var bn := _name_of(p["b"]) if p["b"] != null else ""
			var a_any: bool = str(al["a"]) == ""
			var b_any: bool = not al.has("b") or str(al["b"]) == ""
			if (a_any or an.contains(al["a"])) and (b_any or bn.contains(al["b"])):
				return al["why"]
			if p["b"] != null and (a_any or bn.contains(al["a"])) and (b_any or an.contains(al["b"])):
				return al["why"]
	return ""

# ------------------------------------------------------------------------------------------------------------------
# capturing a state
# ------------------------------------------------------------------------------------------------------------------

## Call after the state is set up. Waits for it to settle, records, analyses, saves the picture.
## Wait until the screen has stopped moving before it is measured: every panel animation and every tween is run to its end, then frames
## pass until no control has moved for two frames in a row (a sheet that grows, a row that settles, a counter that rolls up).
func _settle() -> void:
	var last := ""
	var same := 0
	for pass_k in 40:
		hud.skip_animations()
		for tw in get_processed_tweens():
			if tw.is_valid() and tw.is_running():
				tw.custom_step(60.0)
		await _frames(2)
		var sig := _layout_sig(hud)
		if sig == last:
			same += 1
			if same >= 2:
				return
		else:
			same = 0
			last = sig

## A fingerprint of where every visible control is: it changes while anything is still moving or growing.
func _layout_sig(n: Node) -> String:
	var acc := PackedStringArray()
	_sig_walk(n, acc)
	return "|".join(acc)

func _sig_walk(n: Node, acc: PackedStringArray) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var ctl := c as Control
			acc.append("%d,%d,%d,%d,%.2f" % [roundi(ctl.global_position.x), roundi(ctl.global_position.y), roundi(ctl.size.x), roundi(ctl.size.y), ctl.modulate.a])
		_sig_walk(c, acc)

func _check(name: String) -> void:
	if only != "" and not name.contains(only):
		return
	cur_state = name
	state_count += 1
	await _settle()
	for art in _all_arts():
		art.rec_texts.clear()
		art.rec_glyphs.clear()
		art.rec_on = true
		art.queue_redraw()
	await _frames(3)
	var els := _collect()
	for art in _all_arts():
		art.rec_on = false
	_note_scrolls(name)
	var found := _analyze(els)
	var live: Array = []
	for p in found:
		var why := _allowed(name, p)
		if why != "":
			allowed_count += 1
			continue
		p["size"] = cur_size["name"]
		p["screen"] = name
		live.append(p)
		problems.append(p)
	screens_seen[name] = true
	if not quiet:
		print("  %-44s %3d elements  %s" % [name, els.size(), ("%d problem(s)" % live.size()) if live.size() > 0 else "ok"])
		for p in live:
			print("      %-10s %s%s -- %s" % [p["type"], _name_of(p["a"]), (("  vs  " + _name_of(p["b"])) if p["b"] != null else ""), p["detail"]])
	if out_dir != "":
		await _shot(name, live)

func _shot(name: String, live: Array) -> void:
	await _frames(2)
	var img := root.get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / vp.x
	for p in live:
		for key in ["a", "b"]:
			if p[key] != null:
				_outline(img, (p[key]["rect"] as Rect2), k)
	var longest := 640
	var sc := minf(1.0, float(longest) / float(maxi(img.get_width(), img.get_height())))
	if sc < 1.0:
		img.resize(int(img.get_width() * sc), int(img.get_height() * sc), Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var dir := "%s/%s" % [out_dir, cur_size["name"]]
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_jpg("%s/%s.jpg" % [dir, name.replace(" ", "_").replace("/", "-")], 0.6)
	shot_count += 1

func _outline(img: Image, r: Rect2, k: float) -> void:
	# (outlines are drawn on the full-size picture, before it is scaled down: 4 px thick)
	var x0 := clampi(int(r.position.x * k), 0, img.get_width() - 1)
	var y0 := clampi(int(r.position.y * k), 0, img.get_height() - 1)
	var x1 := clampi(int(r.end.x * k), 0, img.get_width() - 1)
	var y1 := clampi(int(r.end.y * k), 0, img.get_height() - 1)
	var t := maxi(int(4.0 * k * 1.6), 3)
	var red := Color(1.0, 0.0, 0.0, 1.0)
	img.fill_rect(Rect2i(x0, y0, maxi(x1 - x0, 1), t), red)
	img.fill_rect(Rect2i(x0, maxi(y1 - t, y0), maxi(x1 - x0, 1), t), red)
	img.fill_rect(Rect2i(x0, y0, t, maxi(y1 - y0, 1)), red)
	img.fill_rect(Rect2i(maxi(x1 - t, x0), y0, t, maxi(y1 - y0, 1)), red)

# ------------------------------------------------------------------------------------------------------------------
# the states
# ------------------------------------------------------------------------------------------------------------------

const BIG := 9999999
const PT := 1080.0 / 390.0          # units per point on the 390-point-wide design phone
## Text floors by role, in points on a 390-point-wide phone (docs/style.md, "Text sizes"). Headings are as designed.
const ROLE_MIN_PT := {"caption": 11.0, "body": 15.0, "button": 17.0}

func _all_states() -> void:
	await _states_menu()
	await _states_airports()
	await _states_detail()
	await _states_shop()
	await _states_sheets()
	await _states_play()
	await _states_results()
	await _states_misc()

## A save that has everything at its largest: every airport open with three stars, mastered, the best numbers a screen can show.
func _rich_save() -> void:
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.coins = BIG
	for i in Airports.COUNT:
		for k in 3:
			save.stars[i * save.STARS_PER_AIRPORT + k] = 1
		save.best[i] = BIG
		save.best_coins[i] = BIG
		save.mastery[i] = 99999
		save.mastery_paid[i] = 5
		save.ap_xp[i] = Progression.xp_at_level(i, Progression.MAX_LEVEL) + 99999
	save.sync_levels()
	save.stats["ach_seen"] = 0

func _frames_ui(n: int = 4) -> void:
	await _frames(n)
	hud.skip_animations()

func _states_menu() -> void:
	save.reset_all()
	main._show_menu()
	await _check("menu fresh")
	if plant:
		var pk: int = hud._art.btn_id.find("play")
		var pr: Rect2 = hud._art.btn_rect[pk]
		var pl := Label.new()
		pl.text = "PLANTED OVERLAP"
		pl.add_theme_font_size_override("font_size", 56)
		hud.add_child(pl)
		pl.position = Vector2(pr.position.x + 40.0, pr.position.y - 30.0)
		await _check("menu planted overlap")
		pl.queue_free()
	_rich_save()
	save.day_override = 70000
	main.goals_enabled = true
	main._show_menu()
	await _check("menu rich (9,999,999 coins)")
	save.no_engines_bad = true
	main._show_menu()
	await _check("menu bad pilot day, no engines")
	main.goals_enabled = false
	save.no_engines_bad = false

func _states_airports() -> void:
	save.reset_all()
	main._show_select()
	await _check("airports all locked")
	save.stars[0] = 3
	save.award_star(0, 0)
	save.award_star(0, 1)
	main._show_select()
	await _check("airports two stars")
	main.hud.set_loading_airport(1)
	await _check("airports loading card")
	main.hud.set_loading_airport(-1)
	_rich_save()
	main._show_select()
	await _check("airports mastered 9,999,999")

func _states_detail() -> void:
	for i in Airports.COUNT:
		var nm := "detail %d %s" % [i, Airports.airport_name(i).to_lower()]
		save.reset_all()
		main.open_detail(i)
		await _frames_ui()
		await _check(nm + " locked")
		save.unlocks["all_airports"] = true
		main.open_detail(i)
		await _frames_ui()
		await _check(nm + " open")
		main.detail_tab = 1
		main._show_detail()
		await _check(nm + " open improve")
		if plant:                          # self-test: a label pushed out of its row must be reported (CI expects exit code 1)
			var rows: Array = hud.detail_sheet().chips.keys().filter(func(k): return str(k).begins_with("imp:"))
			var row = hud.detail_sheet().chips[rows[0]]
			var rr: Rect2 = row.get_global_rect()
			var pl2 := Label.new()
			pl2.text = "PLANTED NAME"
			pl2.add_theme_font_size_override("font_size", 56)
			pl2.top_level = true
			row.add_child(pl2)
			pl2.global_position = Vector2(rr.end.x - 120.0, rr.position.y + 20.0)
			await _check(nm + " planted tile")
			main._show_detail()
		# the Improve sheet in its other states: a row selected (the preview), money in the bank (orange buttons), and a maxed row
		save.coins = BIG
		main.imp_selected = "hangar"
		main._show_detail()
		await _check(nm + " improve rich, hangar selected")
		save.improvements = {str(i): {"hangar": Improvements.max_level("hangar"), "rwlights": 1, "applights": 2, "fuel": 0, "exit": 0}}
		main.imp_selected = "rwlights"
		main._show_detail()
		await _check(nm + " improve rich, hangar maxed, runway lights selected")
		save.coins = 7
		main.imp_selected = "fuel"
		main._show_detail()
		await _check(nm + " improve poor, fuel selected")
		main.imp_selected = ""
		save.improvements = {}
		save.coins = 0
		for k in 3:
			save.stars[i * save.STARS_PER_AIRPORT + k] = 1
		save.mastery[i] = 40
		main.open_detail(i)
		await _frames_ui()
		await _check(nm + " starred")
		save.mastery[i] = 99999
		save.ap_xp[i] = Progression.xp_at_level(i, Progression.MAX_LEVEL)
		save.sync_levels()
		save.coins = BIG
		save.no_engines_at[i] = 1
		save.improvements = {str(i): {"hangar": 10, "rwlights": 3, "applights": 5, "fuel": 8, "exit": 0}}
		main.open_detail(i)
		await _frames_ui()
		await _check(nm + " mastered, no engines on")
		main.detail_tab = 1
		main._show_detail()
		await _check(nm + " mastered improve")
		save.reset_all()
		save.unlocks["all_airports"] = false
	main._show_menu()

func _states_shop() -> void:
	_rich_save()
	save.coins = BIG
	for tab in 3:
		main.shop_tab = tab
		main._show_shop()
		await _check("shop tab %d" % tab)
	save.reset_all()
	save.coins = 130
	for tab in 3:
		main.shop_tab = tab
		main._show_shop()
		await _check("shop tab %d poor" % tab)
	main._show_upgrades()
	await _check("tower upgrades poor")
	save.coins = BIG
	main._show_upgrades()
	await _check("tower upgrades rich")
	for lv in ["theme", "livery", "windsock", "hangar"]:
		var n: int = Cosmetics.items(lv).size()
		save.reset_all()
		save.coins = 10000
		main.shop_tab = 0 if lv == "theme" else (1 if lv == "livery" else 2)
		main._show_shop()
		for i in n:
			var d: Dictionary = Cosmetics.items(lv)[i]
			main.open_preview(lv, i)
			await _check("preview %s %d %s" % [lv, i, str(d["id"])])
		save.coins = 3
		main.open_preview(lv, n - 1)
		await _check("preview %s need coins" % lv)
		main.close_preview()
	save.reset_all()
	main._show_menu()

func _states_sheets() -> void:
	save.reset_all()
	save.day_override = 70000
	main.goals_enabled = true
	main._show_goals()
	await _check("goals")
	for i in 3:
		(save.goals["list"][i] as Dictionary)["done"] = (i == 0)
	save.goals["chest"] = true
	main._show_goals()
	await _check("goals one done, chest taken")
	main.goals_enabled = false
	_rich_save()
	for t in Achievements.GROUP_NAMES.size():
		main.ach_tab = t
		main._show_achievements()
		await _check("achievements %s" % str(Achievements.GROUP_NAMES[t]).to_lower())
	save.reset_all()
	main.ach_tab = 0

func _clear_popups() -> void:
	hud._pop_born.fill(0)
	for l in hud._pop_labels:
		l.visible = false
		l.size = Vector2(560, 100)
	hud._tip.visible = false
	for a in [hud._main_art] + hud._panel_arts.values():
		a.tip_alpha = 0.0
		a.tip_text = ""
		a.banner_alpha = 0.0
		a.banner_text = ""

## Toast lines as the game words them, the longest few (they are the ones that can overflow).
func _longest_rows() -> Array:
	var rows: Array = []
	for ln in _longest_toasts().slice(0, 4):
		rows.append({"glyph": "star", "text": str(ln).get_slice("  +", 0), "coins": 90})
	return rows

func _longest_toasts() -> Array:
	var lines: Array = []
	for ap in Airports.COUNT:
		for rank in range(1, Mastery.MAX_RANK + 1):
			var line := "%s: rank %d, %s  +%d" % [Airports.airport_name(ap), rank, Mastery.rank_name(rank), Mastery.coins_for(ap, rank, Goals.AVG_PAY[clampi(ap, 0, 5)])]
			var cid := Mastery.cosmetic_for(ap, rank)
			if cid != "":
				line += "  \u00b7  new: " + main._cosmetic_name(cid)
			lines.append(line)
	for a in Achievements.LIST:
		var line2 := "Achievement: %s  +%d" % [a["name"], int(a["coins"])]
		if a.get("cos", "") != "":
			line2 += "  \u00b7  new: " + main._cosmetic_name(a["cos"])
		lines.append(line2)
	lines.sort_custom(func(x, y): return x.length() > y.length())
	return lines.slice(0, 4)

func _states_play() -> void:
	save.reset_all()
	main.restart()
	main.traffic.auto_spawn = false
	main.set_process(false)
	await _frames_ui()
	_clear_popups()
	await _check("shift start")
	# a student on the field: the end it may use glows green, the other shows the red wind icon; then a drag onto an end it may not use (red path, reason tag)
	var st_tr = main.traffic
	var st_p = st_tr.place(0, Vector2(0.0, -6.0), 0.0, 2)
	st_p.runway = 0
	st_p.student = true
	st_p.entered = true
	main.wind.from_deg = Airports.end_heading_deg(0, 0)
	main.wind.refresh()
	main.hud.pulse_wind()
	await _frames_ui(4)
	_clear_popups()
	await _check("shift student, green and red runway ends")
	st_tr.demote_students = false
	main.wind.from_deg = fposmod(Airports.end_heading_deg(0, 0) + 50.0, 360.0)
	main.wind.refresh()
	var st_thr0 = Airports.end_threshold(0, 0)
	st_tr.begin_path(st_p)
	st_p.push(st_thr0 - Airports.end_dir(0, 0) * 3.0)
	st_tr.extend_path(st_p, st_thr0, st_thr0)
	await _frames_ui(4)
	_clear_popups()
	await _check("shift student, path refused (red, Land into the wind)")
	st_tr.end_path(st_p, st_thr0)
	st_tr.demote_students = true
	st_tr.release_all()
	main.wind.from_deg = 0.0
	main.wind.refresh()
	main._apply_fine(root.get_node("Tuning").fine_amount(root.get_node("Tuning").fine_conflict), "conflict", "Too close!", Vector2(0, 0))
	main._apply_fine(root.get_node("Tuning").fine_amount(root.get_node("Tuning").fine_conflict), "conflict", "Too close!", Vector2(1, 0))
	for tk_i in 40:
		main.hud._process(0.05)
	_clear_popups()
	await _check("shift fines counter")
	main.shift.fines = 99999
	main.shift.tickets = 12
	main.hud.set_shift(main.shift)
	for tk_i in 40:
		main.hud._process(0.05)
	_clear_popups()
	await _check("shift fines counter, the widest")
	main.shift.fines = 0
	main.shift.tickets = 0
	main.hud.set_shift(main.shift)
	main.hud._process(0.05)
	main.pause_game()
	await _check("pause")
	main.open_reset_confirm()
	await _frames_ui()
	await _check("pause reset warning")
	main.close_reset_confirm()
	await _frames_ui()
	save.tips_seen = {}
	main.open_tips_page()
	await _frames_ui()
	await _check("settings tips page, empty")
	main.close_tips_page()
	for tid in Tips.LIST:
		save.tips_seen[tid] = true
	main.open_tips_page()
	await _frames_ui()
	await _check("settings tips page, every tip seen")
	main.close_tips_page()
	save.tips_seen = {}
	await _frames_ui()
	main.resume_game()
	main.hud.set_timer(5)
	main.hud.set_finale("4 aircraft left", Color.WHITE, false)
	await _check("shift last arrivals")
	main.hud.set_finale("", Color.WHITE, false)
	main.hud.set_overtime(95)
	await _check("shift overtime")
	main.set_process(true)
	main.restart()
	main.traffic.auto_spawn = false
	main.set_process(false)
	main.shift.earned = BIG
	main.hud.set_shift(main.shift)
	main.hud.set_landed(9999, false)
	await _frames_ui()
	_clear_popups()
	await _check("shift 9,999,999 coins")
	main.hud.set_event_banner("Storm in 20 s", true)
	await _check("shift weather chip")
	main.hud.set_event_banner("")
	main.hud.set_wind_warning(270.0, 8)
	await _check("shift wind warning")
	main.hud.post_banner("No engines: no go-arounds, \u00d72.0 pay", Color(1.0, 0.8, 0.3), "glider", 3.4)
	await _check("shift no engines banner")
	for t in _longest_toasts():
		main.hud.post_banner(t, Color(1.0, 0.85, 0.3), "star", 3.2)
		await _check("shift toast %s" % t.substr(0, 28))
	main.hud.post_banner("LAST ARRIVALS", main.hud.C_GOLD, "plane", 2.0)
	await _check("shift banner")
	_clear_popups()
	for key in Tips.LIST:
		main.hud.dismiss_tip()
		await _frames_ui(3)
		main.hud.show_tip(Tips.text(key), Tips.icon(key), Vector2(INF, INF), true)
		await _check("shift tip %s" % key)
	_clear_popups()
	main.hud.popup("Go-around!\nNot into the wind", Color(1, 0.85, 0.3), Vector2(60.0, 900.0))
	main.hud.popup("Hangar fee +9999", Color(0.75, 0.95, 1.0), Vector2(vp.x - 60.0, 1000.0))
	main.hud.popup("Goal done!  +9999", Color(1.0, 0.85, 0.3), Vector2(vp.x * 0.5, 1100.0))
	main.hud.popup("WRONG RUNWAY", Color(1, 0.4, 0.35), Vector2(vp.x * 0.5, 1300.0))
	await _check("shift popups")
	_clear_popups()
	main.set_process(true)
	# Day 1, the scripted first shift: the dim and the ghost finger, then its cards
	main.onboarding_gates = true
	save.reset_all()
	main.select_airport(0)
	main.start_tutorial()
	main.set_process(false)
	for d1_i in 70:
		main.step(1.0 / 60.0)
	await _frames_ui(4)
	_clear_popups()
	await _check("tutorial 1, draw a path (dim, ghost finger, card, Skip)")
	var d1_thr = Airports.end_threshold(0, main._tut._into_wind_end())
	main.traffic.begin_path(main._tut.a)
	var d1_from = main._tut.a.pos
	for d1_k in range(1, 40):
		if main.traffic.extend_path(main._tut.a, d1_from.lerp(d1_thr, float(d1_k) / 39.0), d1_from.lerp(d1_thr, float(d1_k) / 39.0)):
			break
	main.hud.dismiss_tip()
	for d1_i in 40:
		main.step(1.0 / 60.0)
	main._tut.step = 1
	main.shift.landed = 1
	main._tut.tick(0.1)
	await _frames_ui(4)
	await _check("tutorial 2, landed planes park in the hangar")
	main.hud.dismiss_tip()
	main._tut.step = 3
	main._tut.b = main._tut._spawn(0, 1.0, 2.0, 4.6)
	main._tut.c = main._tut._spawn(0, 1.0, 1.4, 6.0)
	main._tut.t = 3.0
	main._tut.tick(0.1)
	await _frames_ui(4)
	await _check("tutorial 3, keep planes apart")
	main.hud.dismiss_tip()
	main.skip_tutorial()
	main.set_process(true)
	main.onboarding_gates = false
	save.reset_all()
	# Bad Pilot Day (a challenge mode with its own chip), and the No engines modifier on a shift
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.start_bad_day()
	main.set_process(false)
	main.traffic.auto_spawn = false
	await _frames_ui()
	_clear_popups()
	await _check("shift bad pilot day")
	main.set_process(true)
	save.no_engines_bad = true
	main.start_bad_day()
	main.set_process(false)
	main.traffic.auto_spawn = false
	await _frames_ui()
	await _check("shift bad pilot day no engines")
	main.set_process(true)
	save.no_engines_bad = false
	main._show_menu()

func _states_results() -> void:
	for variant in ["win", "fail", "record", "unlock", "rankup", "long"]:
		save.reset_all()
		save.unlocks["all_airports"] = variant != "unlock"
		main.restart()
		main.traffic.auto_spawn = false
		main.set_process(false)
		match variant:
			"win":
				main.shift.earned = BIG
				main.shift.landed = 99
			"fail":
				main.shift.earned = 12
				main.shift.fines = 400
				main.shift.biggest_fine = 250
				main.shift.landed = 2
			"record":
				main.shift.earned = 880
				main.shift.landed = 31
			"unlock":
				main.shift.earned = 880
				main.shift.landed = 40
			"rankup":
				main.shift.earned = 1200
				main.shift.landed = 55
			"long":
				main.shift.earned = 3400
				main.shift.landed = 88
		main._end_shift()
		if variant == "win" or variant == "rankup" or variant == "long":
			main.goal_results = [{"text": "Land 25 aircraft at Mountain Field", "reward": 40}, {"text": "A shift with no fines at all", "reward": 60}, {"text": "Fly with no engines", "reward": 90}]
			if variant == "long":              # the longest content: wordy goals, a long streak line, two ranks, three achievements, a long subtitle
				main.goal_results = [{"text": "Land 40 aircraft at International Airport without a single go-around", "reward": 1250}, {"text": "A shift with no fines at all, in a crosswind, at dusk", "reward": 600}]
			main.hud.goal_note = main.goal_results
			main.goal_streak_text = "Streak: day 7 done  \u00b7  a free cosmetic"
			main.goal_streak_row = {"glyph": "flame", "text": "Day 7 of the streak  \u00b7  new: A free cosmetic", "coins": 150}
			main.goal_chest = 9999
			main.toast_results.assign(_longest_rows() if variant == "rankup" or variant == "long" else [{"glyph": "star", "text": "Achievement: Clean sheet", "coins": 60}])
			main._show_results(false)
			if variant == "long":
				hud._panel_arts["results"].res_sub = "%s \u00b7 99 landed \u00b7 Hangar full \u00b7 14 on the ramp" % Airports.airport_name(5)
				hud._panel_arts["results"].res_sub_two = true
				hud._panel_arts["results"].queue_redraw()
		await _frames_ui(30)
		await _check("results %s" % variant)
		if variant == "win":          # Day 1's results tips: the stars, then the first upgrade
			save.stats["tutorial"] = 1
			save.tips_seen.erase("t_stars")
			save.tips_seen.erase("t_upgrade")
			save.tips_seen.erase("t_hold")
			main.try_tip("t_stars", Vector2(vp.x * 0.5, vp.y * 0.30))
			main.try_tip("t_upgrade", Vector2(vp.x * 0.5, vp.y * 0.58))
			await _frames_ui(4)
			await _check("tutorial results, hit the score to earn stars")
			main.hud.dismiss_tip()
			for tq_i in 4:
				main.hud._process(0.05)
			await _frames_ui(4)
			await _check("tutorial results, the first upgrade is ready")
			main.hud.dismiss_tip()
			main.hud._process(0.05)
			save.stats["tutorial"] = 2
		if plant and variant == "win":          # self-test: text written under the card, on the dimmed field, must be reported
			var pra = hud._panel_arts["results"]
			var pcard: Rect2 = pra.res_stack()["card"]
			var pl3 := Label.new()
			pl3.text = "Day 1 of the streak +15"
			pl3.add_theme_font_size_override("font_size", 56)
			pra.add_child(pl3)
			pl3.position = Vector2(pcard.position.x + 60.0, pcard.end.y + 20.0)
			await _check("results planted card")
			pl3.queue_free()
		if variant == "long":
			# more rows than fit: the card's row area scrolls (checked at the top, and scrolled to the end), then the popups: the longest achievement text
			var rh = main.hud.result_rows_host()
			if rh != null and rh.visible:
				rh.jump_to(rh.max_scroll())
				await _frames_ui(3)
				await _check("results long rows scrolled")
				rh.jump_to(0.0)
			var longest := {}
			for a in Achievements.LIST:
				var txt := "Achievement: %s" % a["name"]
				if a.get("cos", "") != "":
					txt += "  \u00b7  new: " + main._cosmetic_name(a["cos"])
				if longest.is_empty() or txt.length() + str(a["text"]).length() > str(longest["text"]).length() + str(longest["detail"]).length():
					longest = {"glyph": "star", "text": txt, "coins": int(a["coins"]), "detail": "%s (%s)" % [a["text"], str(Achievements.SIZE_NAMES[int(a["s"])]).to_lower()]}
			main.open_row_popup_info(longest)
			await _frames_ui(6)
			await _check("results row popup, the longest achievement")
			main.close_row_popup()
			await _frames_ui(2)
			var wordy := {"glyph": "check", "text": "Land 40 aircraft at International Airport without a single go-around, in a crosswind, at dusk, with the wind shifting", "coins": 1250, "detail": "A daily goal, done today"}
			main.open_row_popup_info(wordy)
			await _frames_ui(6)
			await _check("results row popup, a wordy goal")
			main.close_row_popup()
			await _frames_ui(2)
		main.hud.toggle_details()
		await _check("results %s details" % variant)
		main.hud.toggle_details()
		if main.hud.unlock_active():
			await _check("results %s unlock card" % variant)
			main.hud.hide_unlock()
		main.set_process(true)
	save.reset_all()

func _states_misc() -> void:
	save.reset_all()
	_check_splash()
	for title in ["Reward: double your coins", "Reward: refund your biggest fine", "Between shifts: a short break"]:
		main.hud.show_ad(title)
		main.hud.set_ad_progress(0.4)
		await _check("ad screen %s" % title.substr(0, 14))
		main.hud.hide_ad()
	main._offline = {"total": 1234567, "hours": 8.0, "per": {0: 1200, 1: 34000, 2: 50000, 3: 123, 4: 99999, 5: 999999}}
	main._maybe_tally()
	await _check("tally welcome back (six airports)")
	main._collect_tally()
	save.reset_all()
	main.hud.show_logo()
	main.hud.set_process(false)             # (the intro's clock stands still: the plane that crosses the screen is in the same place every run)
	main.hud._art.logo_t = 2.0
	main.hud._art.queue_redraw()
	await _check("studio logo")
	main.hud.set_process(true)
	main.hud._art.logo_t = -1.0
	main.hud._logo_bg.visible = false
	main._show_menu()
	await _check("menu again")

## The boot splash (the studio mark and a progress bar over the start-up pre-warm) is drawn by a class of its own, centred and at fixed
## sizes: check by measuring that its wordmark and bar fit the screen, with room to spare.
func _check_splash() -> void:
	state_count += 1
	var f := Style.display()
	var gap := Style.SZ_M * 0.32
	var total := -gap
	for w in Style.STUDIO_WORDS:
		total += f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, Style.SZ_M).x + gap
	var inside := total <= vp.x - 80.0 and 420.0 <= vp.x - 80.0
	if not quiet:
		print("  %-44s wordmark %d wide on a %d wide screen  %s" % ["boot splash (measured)", total, vp.x, "ok" if inside else "TOO WIDE"])
	if not inside:
		problems.append({"size": cur_size["name"], "screen": "boot splash", "type": "clipped", "a": {"k": "text", "id": "", "text": "CLEAR PROP GAMES", "rect": Rect2((vp.x - total) * 0.5, vp.y * 0.5 - 40.0, total, 60.0), "inter": false}, "b": null, "detail": "wordmark wider than the screen"})

# ------------------------------------------------------------------------------------------------------------------

func _finish() -> void:
	var by_type := {}
	for p in problems:
		by_type[p["type"]] = int(by_type.get(p["type"], 0)) + 1
	print("")
	print("ui_overlap_check: %d states x sizes checked, %d pictures, %d problem(s) %s, %d allowed by the allowlist" % [state_count, shot_count, problems.size(), str(by_type), allowed_count])
	print("screens that scroll (content taller than the room), by size: ", scrolling)
	print("not opened by the tool:")
	for u in unreachable:
		print("  - ", u)
	if report_path != "":
		var rows := []
		for p in problems:
			rows.append({"size": p["size"], "screen": p["screen"], "type": p["type"], "a": _name_of(p["a"]), "b": _name_of(p["b"]) if p["b"] != null else "", "detail": p["detail"]})
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"problems": rows, "states": state_count, "allowed": allowed_count, "unreachable": unreachable, "scrolling": scrolling}, "\t"))
		f.close()
	quit(1 if problems.size() > 0 else 0)
