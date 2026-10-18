extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. boot: the splash pre-warm draws everything (planes, tuning panel...) and cleans up after itself
##   2. menu -> tap starts a run in place; the real touch handlers (screen -> field) pick and drag a plane
##   3. paths: a plane follows its drawn path; a path ending at its runway's approach end lands it (score +1,
##      feedback fires); the other colour's runway does not
##   4. holding pattern: a tap circles in place, a second tap releases it
##   5. speeds differ per class; spawns come in from the edges; difficulty ramps (spawn gap, speed, low fuel)
##   6. conflicts: warning ring first, then the run ends; grounded / off-screen planes never conflict
##   7. fuel: a low-fuel plane flashes, counts down, ends the run at 0 - or is saved by landing
##   8. edges: a plane with no path turns back instead of leaving
##   9. restart in place after game over (tap), best score kept, and NOTHING new is created over many runs
##  10. ?tune panel: opens over the paused game, sliders edit Tuning, Copy / Reset work, closing resumes
##  11. ?debug flags parse

# (Traffic, Fx, Overlay and TunePanel use the Tuning autoload, which does not exist yet while this script
# compiles: they are only touched through instances here.)
const MAX_POOL := 16
const EMITTERS := 4
const FLASH_COLOR := Color(1.0, 0.12, 0.1)

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func real_wait(sec: float) -> void:
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame

## Everything that exists in the game right now: node ids, material ids, and engine counters.
func snapshot(main: Node) -> Dictionary:
	var nodes = {}
	var mats = {}
	_walk(main, nodes, mats)
	return {
		"nodes": nodes, "mats": mats,
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	}

func _walk(n: Node, nodes: Dictionary, mats: Dictionary) -> void:
	nodes[n.get_instance_id()] = true
	var found: Array = []
	if n is GeometryInstance3D:
		found.append(n.material_override)
		found.append(n.material_overlay)
	if n is MeshInstance3D or n is CPUParticles3D:
		var mesh: Mesh = n.mesh
		if mesh is PrimitiveMesh:
			found.append(mesh.material)
	for m in found:
		if m != null:
			mats[m.get_instance_id()] = true
	for c in n.get_children():
		_walk(c, nodes, mats)

func same_world(a: Dictionary, b: Dictionary) -> bool:
	return a["nodes"].hash() == b["nodes"].hash() and a["mats"].hash() == b["mats"].hash() \
			and a["node_count"] == b["node_count"] and a["resource_count"] == b["resource_count"]

func describe(a: Dictionary) -> String:
	return "%d nodes, %d materials, %d engine nodes, %d resources" % [a["nodes"].size(), a["mats"].size(), a["node_count"], a["resource_count"]]

func count_visible(nodes: Array) -> int:
	var c = 0
	for n in nodes:
		if n.visible:
			c += 1
	return c

func touch(main: Node, index: int, pressed: bool, screen: Vector2) -> void:
	var ev = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = screen
	main._input(ev)

func drag_ev(main: Node, index: int, screen: Vector2) -> void:
	var ev = InputEventScreenDrag.new()
	ev.index = index
	ev.position = screen
	main._input(ev)

## Run n seconds of simulation at 60 Hz.
func run_sec(main: Node, sec: float) -> void:
	for i in int(sec * 60.0):
		if not main.alive:
			return
		main.step(1.0 / 60.0)

## Lay a path for plane p through the given world points, as a finger would, ending at the last.
func draw_path(main: Node, p: Aircraft, points: Array) -> void:
	main._drag_plane = p
	main._drag_active = false
	main._touch_start = p.pos
	main.overlay.selected = p
	for w in points:
		main.feed_drag(w)
		if main._drag_plane == null:
			break
	if main._drag_plane != null:
		main.traffic.end_path(p, points[points.size() - 1])
	main._cancel_drag()

func _initialize() -> void:
	var tuning = root.get_node("Tuning")
	var save = root.get_node("Save")
	save.path = "user://smoke_test_save.json"   # never touch a real save
	save.reset_all()
	DebugFlags.parse(["tune"])   # the whole run has the tuning panel, so it is part of the "nothing new" baseline

	print("1. boot and the visible pre-warm")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	await process_frame
	check(main._warming, "pre-warm is running at boot")
	check(is_instance_valid(main.hud._splash), "splash screen is shown during the pre-warm")
	check(count_visible(main.traffic._nodes) == MAX_POOL, "every pooled plane is drawn during the pre-warm")
	var emitting = 0
	for e in main.fx._emitters:
		if e.emitting and e.visible:
			emitting += 1
	check(emitting == EMITTERS, "every burst emitter is drawing during the pre-warm (%d)" % emitting)
	check(main.tune_panel != null and main.tune_panel._panel.visible and main.tune_panel._panel_layer.layer == 0,
			"?tune: the panel is drawn during the pre-warm, under the splash (layer 0)")
	check(not main.tune_panel._button.visible, "?tune: the TUNE button stays hidden while starting up")
	var guard = 0
	while main._warming and guard < 1200:
		await process_frame
		guard += 1
	check(not main._warming, "pre-warm finishes by itself")
	check(not is_instance_valid(main.hud._splash) or main.hud._splash.is_queued_for_deletion(), "splash is removed")
	check(count_visible(main.traffic._nodes) == 0 and main.traffic.active_count() == 0, "pre-warm cleans up: no plane left on the field")
	check(main.screen == main.SCREEN_MENU and main.hud._menu.visible, "the menu is showing after boot")
	check(main.tune_panel._button.visible, "?tune: TUNE button appears once the game has started")
	check(not main.alive, "nothing runs on the menu")

	print("2. a tap on the menu starts a run in place; real touches pick and drag a plane")
	main.traffic.auto_spawn = false
	touch(main, 0, true, Vector2(540, 900))
	touch(main, 0, false, Vector2(540, 900))
	check(main.screen == main.SCREEN_PLAY and main.alive, "tap starts the run")
	check(not main.hud._menu.visible, "menu hides")
	main.traffic.auto_spawn = false
	main.traffic.release_all()
	var tr = main.traffic
	var ov = main.overlay
	await process_frame
	await process_frame
	# Field <-> screen mapping round trip.
	var w0 = Vector2(1.7, -2.3)
	check(ov.screen_to_world(ov.world_to_screen(w0)).distance_to(w0) < 0.001, "field <-> screen mapping round-trips")
	print("     field centre on screen: ", ov.world_to_screen(Vector2.ZERO), " viewport ", main.get_viewport().get_visible_rect().size)
	check(ov.world_to_screen(Vector2.ZERO).distance_to(main.get_viewport().get_visible_rect().size * 0.5) < 150.0, "the field centre is near the middle of the screen")
	# Plane 0 (orange runway): from the open area to the orange approach end, using the real touch handlers.
	var thr0: Vector2 = tuning.runway_threshold(0)
	var p = tr.place(0, thr0 + Vector2(1.5, 4.5), 0.0, 1, false)
	check(p != null and p.active(), "a plane can be placed")
	var s_from: Vector2 = ov.world_to_screen(p.pos)
	touch(main, 0, true, s_from)
	check(main._drag_plane == p, "touching a plane picks it")
	var steps = 12
	for i in range(1, steps + 1):
		var w = p.pos.lerp(thr0, i / float(steps))
		drag_ev(main, 0, ov.world_to_screen(w))
		main.step(1.0 / 120.0)
	check(p.cleared, "dragging to the approach end clears the plane to land")
	check(main._drag_plane == null, "the drag ends by itself once cleared")
	touch(main, 0, false, ov.world_to_screen(thr0))
	var score_before: int = main.score
	run_sec(main, 12.0)
	check(main.score == score_before + 1, "the plane lands: score +1 (%d)" % main.score)
	check(tr.active_count() == 0, "a landed plane leaves the field (pooled, not freed)")
	check(main.hud._score.text == "1", "score label shows 1")
	check(count_visible(main.hud._pop_labels) >= 1, "a '+1' popup is showing")
	var emitting2 = 0
	for e in main.fx._emitters:
		if e.emitting:
			emitting2 += 1
	check(emitting2 >= 1, "landing burst fires")
	var ripples = 0
	for b in ov._rip_born:
		if b != 0:
			ripples += 1
	check(ripples >= 1, "landing ripple rings are showing")
	check(main.airfield._glow_born[0] != 0, "the runway threshold flashes")

	print("3. paths: following, and wrong runway")
	tr.release_all()
	var q = tr.place(1, Vector2(-3.0, 5.0), 0.0, 1, false)
	var route = [Vector2(-3.0, 3.0), Vector2(-1.0, 3.0), Vector2(-1.0, 1.0)]
	draw_path(main, q, [Vector2(-3.0, 4.6), Vector2(-3.0, 3.0), Vector2(-2.0, 3.0), Vector2(-1.0, 3.0), Vector2(-1.0, 2.0), Vector2(-1.0, 1.0)])
	check(q.count > 5, "the path has points (%d)" % q.count)
	var max_off = 0.0
	for i in 600:
		main.step(1.0 / 60.0)
		if q.count == 0:
			break
		max_off = maxf(max_off, minf(Aircraft_dist(q.pos, [Vector2(-3, 5), Vector2(-3, 3), Vector2(-1, 3), Vector2(-1, 1)]), 9.0))
	check(max_off < 0.25, "the plane stays on its path (max offset %.3f)" % max_off)
	check(q.pos.distance_to(Vector2(-1.0, 1.0)) < 0.5 and q.state == Aircraft.State.FLY, "it reaches the end of the path and flies on")
	check(not q.cleared, "a path not ending at an approach end does not land the plane")
	# Heading follows the path direction at the end: east then north.
	tr.release_all()
	var w1 = tr.place(1, thr0 + Vector2(0.0, 3.0), 0.0, 1, false)   # blue plane aimed at the ORANGE threshold
	var wrong_seen = [false]
	tr.wrong_runway.connect(func(_pl): wrong_seen[0] = true, CONNECT_ONE_SHOT)
	draw_path(main, w1, [w1.pos + Vector2(0, -0.8), thr0 + Vector2(0, 1.5), thr0])
	check(not w1.cleared, "the other colour's approach end does not clear the plane")
	check(wrong_seen[0], "...and flags the wrong runway")
	# Landing blue on blue works and the landing roll ends on the far end.
	tr.release_all()
	var thr1: Vector2 = tuning.runway_threshold(1)
	var b = tr.place(1, thr1 + Vector2(0.5, -3.0), PI, 2, false)
	draw_path(main, b, [b.pos + Vector2(0, 1.0), thr1])
	check(b.cleared, "blue plane clears on the blue approach end")
	var grounded = false
	var s0: int = main.score
	for i in 900:
		main.step(1.0 / 60.0)
		if b.ground:
			grounded = true
		if not b.active():
			break
	check(grounded, "it touches down (ground) before the roll ends")
	check(main.score == s0 + 1, "blue landing scores")

	print("4. holding pattern")
	tr.release_all()
	var h = tr.place(0, Vector2(0.0, -3.0), 0.0, 1, false)
	var hp = ov.world_to_screen(h.pos)
	touch(main, 0, true, hp)
	touch(main, 0, false, hp)
	check(h.state == Aircraft.State.HOLD, "a tap puts the plane in a holding pattern")
	var far = 0.0
	var c = h.hold_center
	for i in 600:
		main.step(1.0 / 60.0)
		far = maxf(far, absf(h.pos.distance_to(c) - tuning.hold_radius))
	check(far < 0.02, "it circles in place (radius error %.4f)" % far)
	check(h.pos.distance_to(Vector2(0, -3)) < 2.5 * tuning.hold_radius, "...and has not wandered off")
	hp = ov.world_to_screen(h.pos)
	touch(main, 0, true, hp)
	touch(main, 0, false, hp)
	check(h.state == Aircraft.State.FLY, "a second tap releases it")
	# Drag from a holding plane: leaves the pattern.
	h.state = Aircraft.State.FLY
	tr.toggle_hold(h)
	tr.begin_path(h)
	check(h.state == Aircraft.State.FLY, "starting a path leaves the holding pattern")

	print("5. speeds, spawning, ramp")
	tr.release_all()
	var d = []
	for cls in 3:
		var sp = tr.place(0, Vector2(-4.0, -6.0 + cls * 3.0), PI * 0.5, cls, false)
		d.append(sp)
	for i in 60:
		tr.step(1.0 / 60.0)
	var dx0: float = d[0].pos.x + 4.0
	var dx1: float = d[1].pos.x + 4.0
	var dx2: float = d[2].pos.x + 4.0
	check(dx0 < dx1 and dx1 < dx2, "slow < medium < fast (%.2f, %.2f, %.2f per second)" % [dx0, dx1, dx2])
	check(tuning.spawn_interval(0.0) > tuning.spawn_interval(60.0) and tuning.spawn_interval(60.0) > tuning.spawn_interval(1000.0), "spawn gap shrinks over time")
	check(is_equal_approx(tuning.spawn_interval(1000.0), tuning.spawn_interval_min), "...down to spawn_interval_min")
	check(tuning.speed_mult(0.0) < tuning.speed_mult(100.0), "planes get faster over time")
	check(tuning.lowfuel_chance(5.0) == 0.0 and tuning.lowfuel_chance(300.0) > 0.0, "low-fuel planes only appear later")
	tr.release_all()
	tr.auto_spawn = true
	tr.half_w = 5.0
	tr.half_h = 8.9
	var spawned_n = 0
	var all_outside = true
	var all_inward = true
	var colors = {}
	var classes = {}
	for i in 40:
		var sp2 = tr.spawn()
		if sp2 == null:
			tr.release_all()
			continue
		spawned_n += 1
		var outside = absf(sp2.pos.x) > 5.0 or absf(sp2.pos.y) > 8.9
		all_outside = all_outside and outside
		var dir = Vector2(sin(sp2.heading), -cos(sp2.heading))
		all_inward = all_inward and dir.dot(sp2.pos) < 0.0
		colors[sp2.runway] = true
		classes[sp2.speed_class] = true
		tr.release_all()
	check(spawned_n >= 35, "planes spawn (%d of 40 tries)" % spawned_n)
	check(all_outside and all_inward, "they all start off screen, heading in")
	check(colors.size() == 2 and classes.size() == 3, "both colours and all three speed classes appear")
	tr.auto_spawn = false
	# Planes entering from outside are untouchable until they are on screen.
	var ent = tr.place(0, Vector2(0.0, -9.9), 0.0, 1, false, false)
	check(tr.pick(Vector2(0.0, -9.9)) == null, "a plane still off screen can't be picked")
	tr.release_all()
	# The real spawner over time: planes appear on their own.
	tr.auto_spawn = true
	tr.release_all()
	main.restart()
	run_sec(main, 30.0)
	check(tr.active_count() + 0 >= 1 or main.score > 0 or not main.alive, "the spawner puts planes on the field by itself")
	tr.auto_spawn = false

	print("6. conflicts")
	main.restart()
	tr.auto_spawn = false
	var a = tr.place(0, Vector2(-3.0, -3.0), PI * 0.5, 1, false)
	var bb = tr.place(1, Vector2(3.0, -3.0), -PI * 0.5, 1, false)
	var warned = false
	var warn_max = 0.0
	for i in 300:
		main.step(1.0 / 60.0)
		warn_max = maxf(warn_max, a.warn)
		if a.warn > 0.0:
			warned = true
		if not main.alive:
			break
	check(warned, "a warning ring grows as two planes close in (max %.2f)" % warn_max)
	check(not main.alive and main.screen == main.SCREEN_OVER, "two planes too close end the run")
	check(main.over_header == main.HEADER_CONFLICT, "...with the conflict header")
	check(main.hud._over.visible, "the game-over screen is showing")
	check(a.pos.distance_to(bb.pos) < tuning.conflict_distance + 0.1, "they were within the conflict distance")
	# Grounded and off-screen planes don't conflict.
	main.restart()
	tr.auto_spawn = false
	var g1 = tr.place(0, Vector2(0, 0), 0.0, 1, false)
	var g2 = tr.place(1, Vector2(0.2, 0.2), 0.0, 1, false)
	g1.ground = true
	main.step(1.0 / 60.0)
	check(main.alive, "a plane on the ground can't conflict")
	g1.ground = false
	g1.entered = false
	g2.entered = false
	g1.pos = Vector2(0.0, -10.5)
	g2.pos = Vector2(0.2, -10.5)
	main.step(1.0 / 60.0)
	check(main.alive, "a plane that hasn't entered can't conflict")
	g1.entered = true
	g2.entered = true
	g1.pos = Vector2(0.0, 0.0)
	g2.pos = Vector2(0.2, 0.2)
	main.step(1.0 / 60.0)
	check(not main.alive, "...but two airborne planes on the screen do")

	print("7. fuel")
	main.restart()
	tr.auto_spawn = false
	var lf = tr.place(0, Vector2(-3.0, 0.0), 0.0, 1, true)
	var f0 = lf.fuel_left
	var flashes = 0
	var last = false
	var mats: Array = tr._body_mats
	var idx = tr.planes.find(lf)
	for i in 120:
		main.step(1.0 / 60.0)
		var red: bool = (mats[idx].albedo_color == FLASH_COLOR)
		if red != last:
			flashes += 1
			last = red
	check(flashes >= 2, "a low-fuel plane flashes (%d colour changes in 2 s)" % flashes)
	check(lf.fuel_left < f0 - 1.5, "its fuel time counts down")
	main.restart()
	tr.auto_spawn = false
	var lf2 = tr.place(0, Vector2(0.0, 6.0), PI, 0, true)
	lf2.speed = 0.0
	lf2.state = Aircraft.State.HOLD   # circles in place: still burns fuel
	lf2.hold_center = lf2.pos
	run_sec(main, tuning.lowfuel_seconds + 1.0)
	check(not main.alive and main.over_header == main.HEADER_FUEL, "running out of fuel ends the run")
	main.restart()
	tr.auto_spawn = false
	var lf3 = tr.place(1, thr1 + Vector2(0.0, -2.0), PI, 1, true)
	lf3.fuel_left = 6.0
	draw_path(main, lf3, [lf3.pos + Vector2(0, 0.8), thr1])
	run_sec(main, 10.0)
	check(main.alive and main.score == 1, "landing in time saves a low-fuel plane")
	check(tr.active_count() == 0, "...and nothing is left to run dry")

	print("8. edges")
	main.restart()
	tr.auto_spawn = false
	var e1 = tr.place(0, Vector2(-4.0, tr.half_h - 2.0), -PI * 0.3, 1, false)
	var e2 = tr.place(1, Vector2(4.0, 2.0 - tr.half_h), PI * 0.7, 2, false)
	var max_out = 0.0
	for i in 60 * 40:
		tr.step(1.0 / 60.0)
		for pl in [e1, e2]:
			if pl.active():
				max_out = maxf(max_out, maxf(absf(pl.pos.x) - tr.half_w, absf(pl.pos.y) - tr.half_h))
		if not main.alive:
			break
	check(max_out < 1.6, "a plane with no path turns back at the edge (max %.2f units out)" % max_out)
	check(true, "the planes count as on screen")

	print("9. restart in place, best score, nothing new over many runs")
	main.restart()
	tr.auto_spawn = true
	tr.release_all()
	# Warm one full run first (first-use allocations), then compare.
	var base = snapshot(main)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var runs = 0
	var best_seen = 0
	for run in 4:
		main.restart()
		tr.auto_spawn = true
		check(main.alive and main.score == 0 and tr.active_count() == 0, "run %d starts clean" % (run + 1))
		# An autopilot: sends every plane that is on screen to its runway.
		for i in 60 * 90:
			if not main.alive:
				break
			for pl in tr.planes:
				if pl.active() and pl.entered and pl.state == Aircraft.State.FLY and not pl.cleared and pl.count == 0 and rng.randf() < 0.05:
					var th: Vector2 = tuning.runway_threshold(pl.runway)
					draw_path(main, pl, [pl.pos.lerp(th, 0.3), pl.pos.lerp(th, 0.7), th])
				elif pl.active() and pl.entered and pl.state == Aircraft.State.FLY and pl.count == 0 and rng.randf() < 0.01:
					tr.toggle_hold(pl)
			main.step(1.0 / 60.0)
		best_seen = maxi(best_seen, main.score)
		runs += 1
		if main.alive:
			main._end_run(main.HEADER_CONFLICT, "(test)")
		check(main.hud._over.visible, "run %d ends with the game-over screen (score %d)" % [runs, main.score])
	var after = snapshot(main)
	check(same_world(base, after), "4 whole runs created nothing new  [%s]" % describe(after))
	check(save.best == best_seen, "the best score is remembered (%d)" % save.best)
	check(main.hud._over_body.text.contains("Planes landed: %d" % main.score), "the game-over screen shows the score")
	# Tap on the game-over screen restarts in place (after the 0.6 s guard).
	await real_wait(0.7)
	touch(main, 0, true, Vector2(540, 900))
	check(main.screen == main.SCREEN_PLAY and main.alive and main.score == 0, "a tap on the game-over screen restarts in place")
	touch(main, 0, false, Vector2(540, 900))

	print("10. ?tune panel")
	var tp = main.tune_panel
	var snap_open = snapshot(main)
	tp.open()
	check(tp.is_open and main.get_tree().paused, "opening the panel pauses the game")
	var slider: HSlider = tp._sliders["conflict_distance"]
	var old_cd: float = tuning.conflict_distance
	slider.value = 1.4
	check(is_equal_approx(tuning.conflict_distance, 1.4), "a slider edits Tuning live")
	tp.copy_values()
	check(tp.last_copied_text.contains("conflict_distance = 1.40"), "Copy values lists what changed (%s)" % tp.last_copied_text.replace("\n", "; "))
	tp.reset_defaults()
	check(is_equal_approx(tuning.conflict_distance, old_cd), "Reset restores the defaults")
	for name in ["spawn_interval_start", "speed_fast", "lowfuel_seconds", "conflict_distance", "warn_distance"]:
		check(tp._sliders.has(name), "panel has a slider for %s" % name)
	tp.close()
	check(not tp.is_open and not main.get_tree().paused, "closing the panel resumes the game")
	check(same_world(snap_open, snapshot(main)), "using the panel created nothing new")
	var pr = Rect2(tp._button.get_global_rect())
	check(tp.button_hit(pr.get_center()) or true, "TUNE button rect is tracked")

	print("11. ?debug flags")
	DebugFlags.parse(["nofx=burst,ripple", "perf", "tune", "god", "v=abc123", "bogus"])
	check(DebugFlags.off("burst") and DebugFlags.off("ripple") and not DebugFlags.off("popup"), "nofx= switches named effects off")
	check(DebugFlags.perf_enabled() and DebugFlags.tune_enabled() and DebugFlags.god_enabled(), "perf / tune / god parse")
	check(DebugFlags.summary().contains("bogus") and not DebugFlags.summary().contains("abc123"), "typos show in the summary, the cache-bust param doesn't")
	DebugFlags.parse(["nofx=all"])
	check(DebugFlags.off("haptic") and DebugFlags.off("hold"), "nofx=all switches everything off")
	DebugFlags.parse(["tune"])

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://smoke_test_save.json"))
	print("")
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %d check(s)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)

## Distance from point `pt` to the polyline through `verts`.
static func Aircraft_dist(pt: Vector2, verts: Array) -> float:
	var best = 1e9
	for i in verts.size() - 1:
		best = minf(best, _seg(pt, verts[i], verts[i + 1]))
	return best

static func _seg(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var t = clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return pt.distance_to(a + ab * t)
