extends SceneTree
## Every list that scrolls (the shop and its cosmetic tabs, the goals, the achievements, the airport detail sheet, the Improve sheet) at 390x844 and 320x568, with the
## web content scale (the 1080 x 1920 layout, stretched and expanded): a synthetic drag of N screen pixels must move the content N screen pixels (+-1), however the
## events' own `relative` is reported (a browser can report it in device pixels). Also: a drag under the 10 pt threshold stays a tap, no tap fires after a scroll,
## a fling coasts and ends inside the list, and a drag past an end stretches and comes back.
## The headless window cannot be resized, so the events are made in screen pixels of whatever the window's content scale is (screen px = viewport units x scale),
## and the drag is 120 points (the web build's units per point make that about 330 units on these phones, 1 unit being about 1 screen pixel of a phone at 3x).
## Run: godot --headless --path . --script tools/scroll_check.gd      Exit code 1 if anything is off.

const SIZES := [{"name": "390x844", "w": 390, "h": 844, "top": 47.0, "bottom": 34.0}, {"name": "320x568", "w": 320, "h": 568, "top": 0.0, "bottom": 0.0}]
const BIG := 9999999
var save: Node
var main: Node
var hud: Node
var fails := 0
var checks := 0
var lists_tested := {}
var scale_now := 1.0

func _initialize() -> void:
	Input.use_accumulated_input = false
	save = root.get_node("Save")
	save.path = "user://scroll_check_save.json"
	root.get_node("Tuning").ad_stub_seconds = 0.0
	root.get_node("Tuning").intro_logo = false
	await _run()
	print("scroll_check: %d checks, %d failed; lists tested: %s" % [checks, fails, str(lists_tested)])
	quit(1 if fails > 0 or lists_tested.size() < 4 else 0)

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	for sz in SIZES:
		var asp := float(sz["w"]) / float(sz["h"])
		var want := Vector2(1080.0, 1080.0 / asp) if asp <= 1080.0 / 1920.0 else Vector2(1920.0 * asp, 1920.0)
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
		for i in Airports.COUNT:
			guard = 0
			if not main.airfield.is_built(i):
				main.request_airport(i)
			while not main.airfield.is_built(i) and guard < 900:
				await process_frame
				guard += 1
		var vp := root.get_visible_rect().size
		Style.px_per_pt = vp.x / float(sz["w"])
		Style.set_safe(float(sz["top"]) * Style.px_per_pt, float(sz["bottom"]) * Style.px_per_pt, 0.0, 0.0)
		hud.apply_safe()
		await _frames(120)
		scale_now = root.get_final_transform().get_scale().x
		print("== %s: viewport %dx%d, %.3f screen px per unit, %.2f units per point" % [sz["name"], vp.x, vp.y, scale_now, Style.px_per_pt])
		await _states(str(sz["name"]))
		main.queue_free()
		await _frames(2)

func _rich() -> void:
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.coins = BIG
	for i in Airports.COUNT:
		for k in 3:
			save.stars[i * save.STARS_PER_AIRPORT + k] = 1
		save.best[i] = BIG
		save.mastery[i] = 99999
		save.mastery_paid[i] = 5
		save.ap_xp[i] = Progression.xp_at_level(i, Progression.MAX_LEVEL) + 99999
	save.sync_levels()

func _settle() -> void:
	for pass_k in 12:
		hud.skip_animations()
		for tw in get_processed_tweens():
			if tw.is_valid() and tw.is_running():
				tw.custom_step(60.0)
		await _frames(2)

func _states(sz: String) -> void:
	_rich()
	for tab in 3:
		main.shop_tab = tab
		main._show_shop()
		await _settle()
		await _list("%s shop tab %d" % [sz, tab], "shop")
	save.reset_all()
	save.day_override = 70000
	main.goals_enabled = true
	main._show_goals()
	await _settle()
	await _list(sz + " goals", "goals")
	main.goals_enabled = false
	_rich()
	main.ach_tab = 0
	main._show_achievements()
	await _settle()
	await _list(sz + " achievements", "achievements")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.open_detail(2)
	await _settle()
	await _sheet(sz + " airport detail")
	main.detail_tab = 1
	main._show_detail()
	await _settle()
	await _sheet(sz + " improve sheet")

## The scroller of a Hud list.
func _list(name: String, kind: String) -> void:
	var e = hud._scrolls.get(kind)
	if e == null or not (e["host"] as KScroll).is_visible_in_tree():
		ok(false, name + ": the list is not on screen")
		return
	await _drive(name, e["host"], kind)

func _sheet(name: String) -> void:
	var ds = hud.detail_sheet()
	if ds == null or ds.scroll == null or not ds.scroll.is_visible_in_tree():
		ok(false, name + ": the sheet is not on screen")
		return
	await _drive(name, ds.scroll, "sheet")

func _touch(pressed: bool, pos_units: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = pressed
	t.position = root.get_final_transform() * pos_units               # (screen pixels: the window's transform brings it back to the viewport)
	Input.parse_input_event(t)

func _dragev(pos_units: Vector2, rel_units: Vector2, rel_mult: float) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = root.get_final_transform() * pos_units
	d.relative = root.get_final_transform().basis_xform(rel_units) * rel_mult
	Input.parse_input_event(d)

## A drag of `dy` units (negative: the finger goes up) in `steps` events; returns nothing, the finger stays down.
func _move(from: Vector2, dy: float, steps: int, rel_mult: float) -> void:
	var prev := from
	for k in range(1, steps + 1):
		var p := from + Vector2(0.0, dy * float(k) / float(steps))
		_dragev(p, p - prev, rel_mult)
		prev = p

## The scroller of a family now (a rebuilt sheet makes a new one).
func _resolve(fam: String) -> KScroll:
	if fam == "sheet":
		return hud.detail_sheet().scroll
	return hud._scrolls[fam]["host"]

## Where the content fits (or nearly) at this size, make it taller so the same host and routing are still driven.
func _inflate(name: String, sc: KScroll) -> void:
	if sc.max_scroll() < KScroll.threshold() * 8.0:
		print("  (%s: the content scrolls only %.0f units here: made 1400 units taller for the drag)" % [name, sc.max_scroll()])
		var c := sc.content()
		c.custom_minimum_size.y = maxf(c.get_combined_minimum_size().y, 0.0) + 1400.0
		sc.queue_sort()
		await _frames(3)

func _drive(name: String, sc0: KScroll, fam: String) -> void:
	var sc := sc0
	lists_tested[fam] = true
	var mx := sc.max_scroll()
	var thr := KScroll.threshold()
	await _inflate(name, sc)
	mx = sc.max_scroll()
	var r := sc.get_global_rect()
	var n_units := minf(120.0 * Style.px_per_pt, mx * 0.9)       # (120 points, or less where the list is short)
	var x := r.position.x + r.size.x * 0.5
	var y0 := r.position.y + r.size.y * 0.75
	for rel_mult in [1.0, 3.0, 0.0]:     # the events' `relative`: right, three times too big (a device-pixel report), absent
		sc.jump_to(0.0)
		await _frames(1)
		var start := sc.offset
		_touch(true, Vector2(x, y0))
		_move(Vector2(x, y0), -n_units, 12, rel_mult)
		var moved := sc.offset - start
		ok(absf(moved - n_units) <= 1.0, "%s: a drag of %.1f units (%.1f screen px) moved the content %.1f units (relative x%.0f)" % [name, n_units, n_units * scale_now, moved, rel_mult])
		# the same finger turns back: the content follows it back, again 1:1
		_move(Vector2(x, y0 - n_units), n_units * 0.5, 6, rel_mult)
		var back := sc.offset - start
		ok(absf(back - n_units * 0.5) <= 1.0, "%s: after turning back the content is %.1f units from the start, should be %.1f (relative x%.0f)" % [name, back, n_units * 0.5, rel_mult])
		_touch(false, Vector2(x, y0 - n_units * 0.5))
		await _frames(2)
		ok(KScroll.touch_scrolled, name + ": a touch that scrolled must not fire a tap")
		var still := sc.offset
		await _frames(20)
		ok(absf(sc.offset - still) <= 1.0, "%s: a slow release must not drift (%.1f -> %.1f)" % [name, still, sc.offset])
	# under the threshold it is not a scroll
	sc.jump_to(0.0)
	await _frames(1)
	_touch(true, Vector2(x, y0))
	_move(Vector2(x, y0), -(thr * 0.6), 4, 1.0)
	ok(absf(sc.offset) <= 0.5, "%s: a move under 10 points scrolled the list (%.1f)" % [name, sc.offset])
	_touch(false, Vector2(x, y0 - thr * 0.6))
	await _frames(2)
	ok(not KScroll.touch_scrolled, name + ": a move under 10 points is still a tap")
	if hud.preview_state() != "":
		main.close_preview()
	await _frames(3)
	sc = _resolve(fam)           # (a tap can rebuild the sheet: the scroller is a new one)
	await _inflate(name, sc)
	mx = sc.max_scroll()
	r = sc.get_global_rect()
	x = r.position.x + r.size.x * 0.5
	y0 = r.position.y + r.size.y * 0.75
	sc.enabled = true
	# the threshold: just over it, the content is exactly where the finger is (it catches up, there is no lag)
	_touch(true, Vector2(x, y0))
	_move(Vector2(x, y0), -(thr * 1.2), 3, 1.0)
	ok(absf(sc.offset - thr * 1.2) <= 1.0, "%s: just over the threshold the content should be %.1f from the start, is %.1f" % [name, thr * 1.2, sc.offset])
	_touch(false, Vector2(x, y0 - thr * 1.2))
	await _frames(2)
	# a drag past the end stretches (softly) and comes back
	sc.jump_to(0.0)
	await _frames(1)
	_touch(true, Vector2(x, y0))
	_move(Vector2(x, y0), 300.0, 6, 1.0)
	ok(sc.offset < 0.0 and sc.offset > -300.0 * 0.6, "%s: past the top the content stretches softly (%.1f for a 300 unit pull)" % [name, sc.offset])
	_touch(false, Vector2(x, y0 + 300.0))
	for k in 240:
		OS.delay_msec(8)
		await process_frame
	ok(absf(sc.offset) <= 1.0, "%s: past the top it springs back to the top (%.1f)" % [name, sc.offset])
	# a fling coasts and ends inside the list
	sc.jump_to(0.0)
	await _frames(1)
	_touch(true, Vector2(x, y0))
	var py := y0
	var stepy := minf(60.0, mx * 0.7 / 8.0)
	for k in 8:
		py -= stepy
		_dragev(Vector2(x, py), Vector2(0.0, -stepy), 1.0)
		OS.delay_msec(14)
		await process_frame
	var before := sc.offset
	_touch(false, Vector2(x, py))
	for k in 400:
		OS.delay_msec(8)
		await process_frame
	ok(sc.offset >= before - 1.0 and sc.offset <= mx + 1.0, "%s: a fling coasts on (%.0f -> %.0f of %.0f) and stays inside the list" % [name, before, sc.offset, mx])
	# a tap on a card after a scroll fires nothing: press on the list, scroll, let go over where the press was
	sc.jump_to(0.0)
	await _frames(1)
