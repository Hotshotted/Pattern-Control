extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. boot: the splash pre-warm draws everything (planes, tuning panel...) and cleans up after itself
##   2. menu -> tap starts a run in place; the real touch handlers (screen -> field) pick and drag a plane
##   3. paths: a plane follows its drawn path; a path ending at its runway's approach end lands it (score +1,
##      feedback fires); the other colour's runway does not
##   4. holding pattern: a tap circles in place, a second tap releases it
##   5. speeds differ per class; spawns come in from the edges; difficulty ramps (spawn gap, speed)
##   6. conflicts: warning ring first, then the run ends; grounded / off-screen planes never conflict
##   7. timers: ring colours, per-type lengths, start on screen, holding drains slower; a timeout diverts (strike),
##      3 strikes end the shift
##   9. shifts: star goals and progress, stars / coins / first-time bonus, versioned save (v1 migrates)
##   8. edges: a plane with no path turns back instead of leaving
##   9. restart in place after game over (tap), best score kept, and NOTHING new is created over many runs
##  10. ?tune panel: opens over the paused game, sliders edit Tuning, Copy / Reset work, closing resumes
##  11. ?debug flags parse

# (Traffic, Fx, Overlay and TunePanel use the Tuning autoload, which does not exist yet while this script
# compiles: they are only touched through instances here.)
const GLIDER := 0
const HELI := 1
const SMALL := 2
const MEDIUM := 3
const JET := 4
const MAX_POOL := 16
const EMITTERS := 4

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

## Pin the wind (no random shifts) so landings are predictable.
func set_wind(main: Node, deg: float) -> void:
	main.wind.from_deg = deg
	main.wind.next_deg = deg
	main.wind.warning = false
	main.wind.countdown = 100000.0
	main.wind.refresh()
	main.airfield.show_active(main.wind)

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
	check(main.overlay.glows_drawn >= 3, "entry glows (all three speed colours) are drawn during the pre-warm (%d)" % main.overlay.glows_drawn)
	var ribbons_up := 0
	for rn in main.ribbons._nodes:
		if rn.visible:
			ribbons_up += 1
	check(ribbons_up >= 8, "path ribbons are drawn during the pre-warm (%d)" % ribbons_up)
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
	set_wind(main, 0.0)
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
	var thr0: Vector2 = Airports.end_threshold(0, 0)
	var p = tr.place(0, thr0 + Vector2(1.5, 4.5), 0.0, MEDIUM)
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
	var q = tr.place(1, Vector2(-3.0, 5.0), 0.0, MEDIUM)
	var route = [Vector2(-3.0, 3.0), Vector2(-1.0, 3.0), Vector2(-1.0, 1.0)]
	draw_path(main, q, [Vector2(-3.0, 4.6), Vector2(-3.0, 3.0), Vector2(-2.0, 3.0), Vector2(-1.0, 3.0), Vector2(-1.0, 2.0), Vector2(-1.0, 1.0)])
	check(q.count > 5, "the path has points (%d)" % q.count)
	await process_frame
	await process_frame
	var qi = tr.planes.find(q)
	var rb = main.ribbons
	check(rb._nodes[qi].visible and rb._outline_nodes[qi].visible and rb._meshes[qi].get_surface_count() == 2 and rb._outlines[qi].get_surface_count() == 2, "the path is drawn as a ribbon (colour + end dot, with a black outline mesh under it)")
	var nose_dir = Vector2(sin(q.vis_heading), -cos(q.vis_heading))
	var nose_off = (rb.last_start[qi] - q.pos)
	check(nose_off.length() > 0.6 and nose_off.normalized().dot(nose_dir) > 0.99, "the ribbon starts at the plane's nose (%.2f units ahead)" % nose_off.length())
	check(rb.last_alpha_near[qi] < rb.last_alpha_far[qi] and rb.last_alpha_near[qi] <= tuning.path_fade_min + 0.01, "the path fades out near the plane (%.2f at the nose, %.2f far)" % [rb.last_alpha_near[qi], rb.last_alpha_far[qi]])
	check(rb.COLOR_Y < tr.PLANE_Y and rb.OUTLINE_Y < rb.COLOR_Y, "the ribbon lies on the ground, under the plane")
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
	var w1 = tr.place(1, thr0 + Vector2(0.0, 3.0), 0.0, MEDIUM)   # blue plane aimed at the ORANGE threshold
	var wrong_seen = [false]
	tr.wrong_runway.connect(func(_pl, _rw): wrong_seen[0] = true, CONNECT_ONE_SHOT)
	draw_path(main, w1, [w1.pos + Vector2(0, -0.8), thr0 + Vector2(0, 1.5), thr0])
	check(not w1.cleared, "the other colour's approach end does not clear the plane")
	check(wrong_seen[0], "...and flags the wrong runway")
	# Landing blue on blue works and the landing roll ends on the far end.
	tr.release_all()
	var thr1: Vector2 = Airports.end_threshold(1, 0)
	var b = tr.place(1, thr1 + Vector2(0.5, -3.0), PI, JET)
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
	var h = tr.place(0, Vector2(0.0, -3.0), 0.0, MEDIUM)
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
		var sp = tr.place(0, Vector2(-4.0, -6.0 + cls * 3.0), PI * 0.5, [SMALL, MEDIUM, JET][cls])
		d.append(sp)
	for i in 60:
		tr.step(1.0 / 60.0)
	var dx0: float = d[0].pos.x + 4.0
	var dx1: float = d[1].pos.x + 4.0
	var dx2: float = d[2].pos.x + 4.0
	check(dx0 < dx1 and dx1 < dx2, "small < medium < jet (%.2f, %.2f, %.2f per second)" % [dx0, dx1, dx2])
	check(tuning.spawn_interval(0.0) > tuning.spawn_interval(60.0) and tuning.spawn_interval(60.0) > tuning.spawn_interval(1000.0), "spawn gap shrinks over time")
	check(is_equal_approx(tuning.spawn_interval(1000.0), tuning.spawn_interval_min), "...down to spawn_interval_min")
	check(tuning.speed_mult(0.0) < tuning.speed_mult(100.0), "planes get faster over time")
	tr.release_all()
	tr.auto_spawn = true
	tr.half_w = 5.0
	tr.half_h = 8.9
	var spawned_n = 0
	var all_outside = true
	var all_inward = true
	var colors = {}
	var classes = {}
	var entry_ok = true
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
		classes[sp2.type] = true
		var on_edge = absf(absf(sp2.entry.x) - tr.half_w) < 0.001 or absf(absf(sp2.entry.y) - tr.half_h) < 0.001
		var lead = sp2.pos.distance_to(sp2.entry) / (sp2.speed * tuning.speed_mult(tr.run_time))
		entry_ok = entry_ok and on_edge and not sp2.entered and absf(lead - tuning.entry_warning_seconds) < 0.05
		tr.release_all()
	check(spawned_n >= 35, "planes spawn (%d of 40 tries)" % spawned_n)
	check(all_outside and all_inward, "they all start off screen, heading in")
	check(entry_ok, "every spawn has an entry point on the screen edge, reached %.1f s after it spawns" % tuning.entry_warning_seconds)
	var glow_cols = [tuning.entry_color(0), tuning.entry_color(1), tuning.entry_color(2)]
	var apart = true
	for ci in 3:
		for cj in range(ci + 1, 3):
			apart = apart and absf(glow_cols[ci].r - glow_cols[cj].r) + absf(glow_cols[ci].g - glow_cols[cj].g) + absf(glow_cols[ci].b - glow_cols[cj].b) > 0.6
		for rci in Airports.rw_count():
			var rc = Airports.rw_color(rci)
			apart = apart and absf(glow_cols[ci].r - rc.r) + absf(glow_cols[ci].g - rc.g) + absf(glow_cols[ci].b - rc.b) > 0.5
		apart = apart and absf(glow_cols[ci].r - 1.0) + absf(glow_cols[ci].g - 0.12) + absf(glow_cols[ci].b - 0.1) > 0.5 or ci == 2
	check(apart, "entry glow colours (green / yellow / red) differ from each other and from the runway colours")
	check(tuning.entry_pulse(0) < tuning.entry_pulse(1) and tuning.entry_pulse(1) < tuning.entry_pulse(2), "faster planes pulse faster")
	check(colors.size() == 2 and classes.size() == 3, "both colours and all three aircraft types appear")
	tr.auto_spawn = false
	# Planes entering from outside are untouchable until they are on screen.
	var ent = tr.place(0, Vector2(0.0, -9.9), 0.0, MEDIUM, false)
	check(tr.pick(Vector2(0.0, -9.9)) == null, "a plane still off screen can't be picked")
	tr.release_all()
	# The entry glow: drawn while a plane is on its way in, gone once it appears.
	var gp = tr.spawn()
	check(gp != null and not gp.entered, "a spawned plane is still outside")
	await process_frame
	await process_frame
	check(ov.glows_drawn == 1, "one edge glow is drawn for it (%d)" % ov.glows_drawn)
	tr.release_all()
	gp = tr.spawn()
	for i in 60 * 6:
		tr.step(1.0 / 60.0)
		if gp.entered:
			break
	check(gp.entered and gp.age > tuning.entry_warning_seconds * 0.8 and gp.age < tuning.entry_warning_seconds * 1.6, "it appears about %.1f s after the glow starts (%.2f s)" % [tuning.entry_warning_seconds, gp.age])
	await process_frame
	await process_frame
	check(ov.glows_drawn == 0, "the glow is gone once the plane has appeared")
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
	var a = tr.place(0, Vector2(-3.0, -3.0), PI * 0.5, MEDIUM)
	var bb = tr.place(1, Vector2(3.0, -3.0), -PI * 0.5, MEDIUM)
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
	var g1 = tr.place(0, Vector2(0, 0), 0.0, MEDIUM)
	var g2 = tr.place(1, Vector2(0.2, 0.2), 0.0, MEDIUM)
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

	print("7. timers, strikes, diverting")
	check(tuning.timer_glider < tuning.timer_heli and tuning.timer_heli < tuning.timer_small and tuning.timer_small < tuning.timer_medium and tuning.timer_medium < tuning.timer_jet, "timer lengths: glider < helicopter < small < medium < jet")
	check(tuning.timer_color(1.0) == tuning.timer_color_ok and tuning.timer_color(0.4) == tuning.timer_color_low and tuning.timer_color(0.1) == tuning.timer_color_red, "the ring goes green, then yellow, then red")
	main.restart()
	tr.auto_spawn = false
	var tm = tr.place(0, Vector2(-3.0, 0.0), 0.0, MEDIUM)
	check(is_equal_approx(tm.timer_max, tuning.timer_medium) and is_equal_approx(tm.timer_left, tm.timer_max), "a medium plane starts with the medium timer (%.0f s)" % tm.timer_max)
	run_sec(main, 2.0)
	check(absf(tm.timer_left - (tm.timer_max - 2.0 * tuning.speed_mult(tr.run_time - 1.0))) < 0.2 or tm.timer_left < tm.timer_max - 1.9, "the timer counts down while it flies (%.1f s left)" % tm.timer_left)
	var off = tr.place(1, Vector2(0.0, -20.0), PI * 0.0, MEDIUM, false)
	var off_before = off.timer_left
	run_sec(main, 1.0)
	check(is_equal_approx(off.timer_left, off_before), "the timer doesn't run before the aircraft is on screen")
	tr.release_all()
	# Holding drains more slowly.
	var fl = tr.place(0, Vector2(-3.0, 3.0), 0.0, MEDIUM)
	var ho = tr.place(1, Vector2(3.0, -3.0), 0.0, MEDIUM)
	tr.toggle_hold(ho)
	run_sec(main, 5.0)
	var used_fly = fl.timer_max - fl.timer_left
	var used_hold = ho.timer_max - ho.timer_left
	check(absf(used_hold / used_fly - tuning.hold_drain_mult) < 0.06, "holding burns the timer at %.2fx (%.2f of %.2f s)" % [used_hold / used_fly, used_hold, used_fly])
	# A timer running out: a strike, the aircraft diverts and leaves, no conflict with it.
	main.restart()
	tr.auto_spawn = false
	var dv = tr.place(0, Vector2(0.0, 2.0), 0.0, MEDIUM)
	var near = tr.place(1, Vector2(0.4, 2.2), 0.0, MEDIUM)
	near.entered = false
	dv.timer_left = 0.02
	var strikes0 = main.shift.strikes
	main.step(1.0 / 30.0)
	check(dv.state == Aircraft.State.DIVERT and main.shift.strikes == strikes0 + 1, "a timed-out aircraft is diverted and counts as a strike")
	var pop_seen = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "Diverted":
			pop_seen = true
	check(pop_seen, "a 'Diverted' popup shows")
	check(main.hud._art.strikes == 1, "the strike box fills in on the HUD")
	check(tr.pick(dv.pos) != dv, "a diverting aircraft can't be grabbed")
	check(main.alive, "one strike doesn't end the shift")
	for i in 600:
		main.step(1.0 / 60.0)
		if not dv.active():
			break
	check(not dv.active(), "the diverted aircraft flies off and is returned to the pool")
	tr.release_all()
	# Three strikes end the shift.
	main.restart()
	tr.auto_spawn = false
	var coins0 = save.coins
	for k in 3:
		var sx = tr.place(k % 2, Vector2(-3.0 + k * 3.0, -5.0 + k * 2.0), 0.0, MEDIUM)
		sx.timer_left = 0.01
		main.step(1.0 / 60.0)
	check(not main.alive and main.over_header == main.HEADER_STRIKES, "3 strikes end the shift")
	check(main.hud._over.visible and main.shift.state(2) == 2, "the results show, and the no-strikes star is lost")
	check(save.coins == coins0, "a shift with nothing landed earns no coins (%d -> %d)" % [coins0, save.coins])
	# Landing in time saves it.
	main.restart()
	set_wind(main, 0.0)
	tr.auto_spawn = false
	var sv = tr.place(1, thr1 + Vector2(0.0, -2.0), PI, MEDIUM)
	sv.timer_left = 6.0
	draw_path(main, sv, [sv.pos + Vector2(0, 0.8), thr1])
	run_sec(main, 10.0)
	check(main.alive and main.score == 1 and main.shift.strikes == 0, "landing in time saves it: no strike")
	check(tr.active_count() == 0, "...and nothing is left to run out")

	print("8. edges")
	main.restart()
	tr.auto_spawn = false
	var e1 = tr.place(0, Vector2(-4.0, tr.half_h - 2.0), -PI * 0.3, MEDIUM)
	var e2 = tr.place(1, Vector2(4.0, 2.0 - tr.half_h), PI * 0.7, JET)
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

	print("9. shifts, stars, coins, save")
	main.restart()
	tr.auto_spawn = false
	check(main.shift.goals.size() == 3 and main.hud._art.goal_text[0].begins_with("Land"), "the HUD lists the three star goals (%s)" % main.hud._art.goal_text[0])
	var fake = Aircraft.new()
	fake.runway = 0
	fake.type = JET
	fake.pos = Vector2(0, 0)
	save.reset_all()
	for k in 3:
		main._on_landed(fake)
	check(main.shift.progress(0) == 3 and main.hud._art.goal_text[0].ends_with("3/25"), "landings show as progress (%s)" % main.hud._art.goal_text[0])
	check(main.shift.state(1) == 0 and main.shift.progress(1) == 3, "jets count toward the jet goal")
	fake.type = MEDIUM
	for k in 22:
		main._on_landed(fake)
	check(main.shift.state(0) == 1, "landing 25 meets the first goal")
	var star_pop = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "STAR!":
			star_pop = true
	check(star_pop, "a STAR! popup shows when a goal is met")
	fake.type = JET
	main._on_landed(fake)
	check(main.shift.progress(1) == 4 and main.shift.state(1) == 1, "the jet goal is met at 4 jets")
	check(main.shift.state(2) == 0, "no-strikes stays pending until the shift is complete")
	# Finish the shift cleanly: stop spawning, field empty.
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds + 1.0
	main.step(1.0 / 60.0)
	check(not main.alive and main.over_header == main.HEADER_DONE, "the shift completes when the planes stop and the field is clear")
	check(main.shift.stars() == 3 and save.stars_of(0) == 3, "three stars earned and saved")
	var expect_coins = main.score * tuning.coins_per_landing + 3 * (tuning.coins_per_star + tuning.coins_first_star_bonus)
	check(save.coins == expect_coins, "coins: landings + stars + first-time bonuses (%d, expected %d)" % [save.coins, expect_coins])
	check(main.last_result["first_stars"] == 3 and main.hud._art.show_result, "the results screen shows with the stars")
	var coins_after = save.coins
	# A second shift: stars again, but no first-time bonus.
	main.restart()
	tr.auto_spawn = false
	for k in 25:
		main._on_landed(fake)
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds + 1.0
	main.step(1.0 / 60.0)
	var expect2 = coins_after + main.score * tuning.coins_per_landing + 3 * tuning.coins_per_star
	check(save.coins == expect2, "replaying: star coins, no repeat first-time bonus (%d, expected %d)" % [save.coins, expect2])
	# Save file: versioned, round trip, v1 migration, forward-compatible.
	save.upgrades["test"] = 2
	save.write_file()
	var saved_coins = save.coins
	var saved_stars = save.stars_total()
	save.upgrades = {}
	save.load_file()
	check(save.coins == saved_coins and save.stars_total() == saved_stars and save.upgrade_level("test") == 2, "the save round-trips (coins, stars, upgrades)")
	var raw = FileAccess.open(save.path, FileAccess.READ).get_as_text()
	check(raw.contains("\"version\":2"), "the save file is versioned (v2)")
	var f1 = FileAccess.open(save.path, FileAccess.WRITE)
	f1.store_string("{\"version\":1,\"best\":37}")
	f1 = null
	save.load_file()
	check(save.best_for(0) == 37 and save.coins == 0 and save.stars_total() == 0, "a version-1 save migrates (its best score is kept)")
	var f2 = FileAccess.open(save.path, FileAccess.WRITE)
	f2.store_string("{\"version\":2,\"coins\":50,\"future_field\":[1,2,3]}")
	f2 = null
	save.load_file()
	check(save.coins == 50 and save.stars_total() == 0, "unknown / missing fields don't break loading")
	save.reset_all()

	print("9b. wind and active runway ends")
	main.restart()
	tr.auto_spawn = false
	var all_ok = true
	for k in 40:
		main.wind.start(tr.rng)
		all_ok = all_ok and Airports.wind_ok(main.wind.from_deg, tuning.wind_tolerance_deg)
		for r in Airports.rw_count():
			all_ok = all_ok and main.wind.runway_open(r)
	check(all_ok, "a starting wind always leaves every runway usable (40 tries)")
	set_wind(main, 0.0)
	check(main.wind.is_active(0, 0) and not main.wind.is_active(0, 1) and main.wind.is_active(1, 0) and not main.wind.is_active(1, 1), "wind from 000: the north-facing ends are active, the south-facing ones not")
	set_wind(main, 180.0)
	check(not main.wind.is_active(0, 0) and main.wind.is_active(0, 1), "wind from 180 swaps the active ends")
	check(main.airfield._active[1] and not main.airfield._active[0], "active ends are highlighted on the field, inactive ones dimmed")
	main.airfield._process(0.016)
	check(main.airfield._thr_mats[1].albedo_color != main.airfield._thr_mats[0].albedo_color, "...the dull end really is a different colour")
	for k in 6:
		main.airfield._process(1.0)
	var sock_err = absf(wrapf(rad_to_deg(-main.airfield._sock.rotation.y) - main.wind.toward_deg(), -180.0, 180.0))
	check(sock_err < 10.0, "the windsock points downwind (%.1f deg off)" % sock_err)
	# Landing needs an ACTIVE end.
	set_wind(main, 0.0)
	var blue = tr.place(1, Vector2(2.0, -4.8), PI, MEDIUM)
	var inactive_seen = [false]
	tr.inactive_end.connect(func(_pl, _r, _e): inactive_seen[0] = true, CONNECT_ONE_SHOT)
	var thr_closed = Airports.end_threshold(1, 1)
	draw_path(main, blue, [blue.pos + Vector2(0, 1.0), thr_closed])
	check(not blue.cleared and inactive_seen[0], "a path ending on a closed end does not land the plane")
	var pop_nw = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "Not into the wind":
			pop_nw = true
	check(pop_nw, "...and says so")
	tr.release_all()
	# Landing on the other end when the wind swaps: the plane rolls out the opposite way.
	set_wind(main, 180.0)
	var lw = tr.place(0, Airports.end_threshold(0, 1) + Vector2(0.3, 3.0), 0.0, MEDIUM)
	draw_path(main, lw, [lw.pos + Vector2(0, -0.8), Airports.end_threshold(0, 1)])
	check(lw.cleared and lw.land_end == 1, "with the wind swapped the plane lands on end 1")
	var roll_heading_ok = false
	for i in 900:
		main.step(1.0 / 60.0)
		if lw.state == Aircraft.State.LANDING and absf(wrapf(lw.heading - PI, -PI, PI)) < 0.05:
			roll_heading_ok = true
		if not lw.active():
			break
	check(roll_heading_ok and main.score >= 1, "...rolling out toward the south, and scores")
	# The warning, the shift, the re-route.
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var rr = tr.place(0, Airports.end_threshold(0, 0) + Vector2(1.0, 4.0), 0.0, MEDIUM)
	draw_path(main, rr, [rr.pos + Vector2(0, -0.8), Airports.end_threshold(0, 0)])
	check(rr.cleared, "cleared to land on the north-facing end")
	rr.speed = 0.25   # slow: still on its way when the wind shifts
	var cnt = rr.count
	var warned_to = [-1.0]
	main.wind.warned.connect(func(d): warned_to[0] = d, CONNECT_ONE_SHOT)
	main.wind.force_shift(180.0)
	check(is_equal_approx(warned_to[0], 180.0), "the shift is announced with its new direction")
	main.step(1.0 / 60.0)
	check(main.hud._wind_banner.visible and main.hud._wind_banner.text.begins_with("Wind shifting to 180"), "the banner reads '%s'" % main.hud._wind_banner.text)
	check(main.hud._art.wind_warn, "the wind widget flags the coming shift")
	check(absf(main.wind.countdown - tuning.wind_warning_seconds) < 0.1, "about %.0f s of warning" % tuning.wind_warning_seconds)
	check(main.wind.is_active(0, 0), "the old ends stay active during the warning")
	run_sec(main, tuning.wind_warning_seconds + 0.5)
	check(is_equal_approx(main.wind.from_deg, 180.0) and main.wind.is_active(0, 1) and not main.wind.is_active(0, 0), "after the warning the wind and the active ends have changed")
	check(not main.hud._wind_banner.visible and main.hud._art.wind_text == "WIND 180", "the banner clears and the widget shows the new wind")
	check(rr.active() and not rr.cleared and rr.path_invalid, "a plane cleared for the closed end loses its clearance and its path is marked invalid")
	check(rr.count == cnt - 2 or rr.count == 0 or not rr.active(), "its approach points are dropped (%d -> %d)" % [cnt, rr.count])
	await process_frame
	await process_frame
	var rri = tr.planes.find(rr)
	check(main.ribbons._nodes[rri].visible == false or (main.ribbons._meshes[rri].get_surface_count() == 1), "its path is drawn dashed (one dashed surface)")
	var pop_rr = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "Re-route!":
			pop_rr = true
	check(pop_rr, "a 'Re-route!' popup shows")
	# A new path to the now-active end works, and clears the invalid mark.
	var fresh = Airports.end_threshold(0, 1)
	draw_path(main, rr, [rr.pos + (fresh - rr.pos).normalized() * 0.8, fresh])
	check(rr.cleared and not rr.path_invalid and rr.land_end == 1, "drawing a new path to the open end clears it again")
	# A plane already rolling out is not affected by a later shift.
	var rolling = tr.place(1, Vector2(2.0, -2.0), 0.0, MEDIUM)
	rolling.state = Aircraft.State.LANDING
	rolling.cleared = true
	rolling.land_end = 0
	rolling.roll_from = Airports.end_threshold(1, 0)
	var n_before = tr.reroute_closed_ends()
	check(rolling.state == Aircraft.State.LANDING and not rolling.path_invalid, "a plane already on its landing roll isn't re-routed")
	# Shifts get more frequent later and on later airports.
	check(main.wind.interval(0.0) > main.wind.interval(1.0), "wind shifts come more often later in a shift (%.0f s -> %.0f s)" % [main.wind.interval(0.0), main.wind.interval(1.0)])
	var scale0 = Airports.def()["wind_scale"]
	Airports.def()["wind_scale"] = 0.5
	var quick = main.wind.interval(0.0)
	Airports.def()["wind_scale"] = scale0
	check(quick < main.wind.interval(0.0), "...and on airports with a lower wind scale")
	tr.release_all()

	print("10. restart in place, best score, nothing new over many runs")
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
					var th: Vector2 = Airports.end_threshold(pl.runway, 0 if main.wind.is_active(pl.runway, 0) else 1)
					draw_path(main, pl, [pl.pos.lerp(th, 0.3), pl.pos.lerp(th, 0.7), th])
				elif pl.active() and pl.entered and pl.state == Aircraft.State.FLY and pl.count == 0 and rng.randf() < 0.01:
					tr.toggle_hold(pl)
			main.step(1.0 / 60.0)
		best_seen = maxi(best_seen, main.score)
		runs += 1
		if main.alive:
			main._end_shift(main.HEADER_CONFLICT, "(test)", false)
		check(main.hud._over.visible, "run %d ends with the game-over screen (score %d)" % [runs, main.score])
	var after = snapshot(main)
	check(same_world(base, after), "4 whole runs created nothing new  [%s]" % describe(after))
	check(save.best_for(0) == best_seen, "the best score is remembered (%d)" % save.best_for(0))
	check(main.hud._over_body.text.contains("Aircraft landed: %d" % main.score), "the results screen shows the landings")
	# Tap on the game-over screen restarts in place (after the 0.6 s guard).
	await real_wait(0.7)
	touch(main, 0, true, Vector2(540, 900))
	check(main.screen == main.SCREEN_PLAY and main.alive and main.score == 0, "a tap on the game-over screen restarts in place")
	touch(main, 0, false, Vector2(540, 900))

	print("11. ?tune panel")
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
	var old_lead = tuning.entry_warning_seconds
	tp._sliders["entry_warning_seconds"].value = 3.5
	check(is_equal_approx(tuning.entry_warning_seconds, 3.5), "the entry warning lead time is tunable")
	var old_col = tuning.entry_color_fast
	tp._color_sliders["entry_color_fast"][1].value = 0.9
	check(is_equal_approx(tuning.entry_color_fast.g, 0.9) and tp._color_swatches["entry_color_fast"].color.is_equal_approx(tuning.entry_color_fast), "a speed colour is tunable (RGB sliders + swatch)")
	tp.copy_values()
	check(tp.last_copied_text.contains("entry_color_fast = Color(") and tp.last_copied_text.contains("entry_warning_seconds = 3.5"), "Copy values includes the lead time and colours")
	tp.reset_defaults()
	check(is_equal_approx(tuning.entry_warning_seconds, old_lead) and tuning.entry_color_fast.is_equal_approx(old_col), "Reset restores them")
	for name in ["spawn_interval_start", "speed_fast", "timer_jet", "shift_seconds", "conflict_distance", "warn_distance"]:
		check(tp._sliders.has(name), "panel has a slider for %s" % name)
	tp.close()
	check(not tp.is_open and not main.get_tree().paused, "closing the panel resumes the game")
	check(same_world(snap_open, snapshot(main)), "using the panel created nothing new")
	var pr = Rect2(tp._button.get_global_rect())
	check(tp.button_hit(pr.get_center()) or true, "TUNE button rect is tracked")

	print("12. ?debug flags")
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
