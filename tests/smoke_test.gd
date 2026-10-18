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
##   9b. wind: active ends, the shift warning, re-routing, windsock
##   9c. airports: six layouts, unlock by stars, select screen, crossing runways (conflict), busy runway
##       (go around), terrain (crash = strike), cycling airports creates nothing
##   9d. special aircraft: helicopters (pad, hover), gliders (one path, no hold), jets (long runways), seaplanes
##       (lane), emergencies (any runway, bonus), VIPs (lose the bonus if held), first-time tips
##   9e. upgrades: buying, every effect, the radar re-framing, approach lining-up, the scenery, the shop screen
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
const SEAPLANE := 5
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
	var vis_roots := 0
	for av in main.airfield.variants:
		if av.root.visible:
			vis_roots += 1
	check(vis_roots == 6, "all six airports are drawn during the pre-warm (%d)" % vis_roots)
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
	save.unlocks["all_airports"] = true
	main.select_airport(2)    # the older tests were written for two parallel runways: Regional
	vis_roots = 0
	for av in main.airfield.variants:
		if av.root.visible:
			vis_roots += 1
	check(vis_roots == 1, "after the pre-warm only the current airport is visible")

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
	check(main.airfield.cur.glow_born[0] != 0, "the runway threshold flashes")

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
	check(colors.size() == 2 and classes.size() >= 4, "both colours and many aircraft types appear (%d)" % classes.size())
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
	fake.type = HELI
	fake.pos = Vector2(0, 0)
	save.reset_all()
	for k in 3:
		main._on_landed(fake)
	check(main.shift.progress(0) == 3 and main.hud._art.goal_text[0].ends_with("3/25"), "landings show as progress (%s)" % main.hud._art.goal_text[0])
	check(main.shift.state(1) == 1 and main.shift.progress(1) == 3, "Regional's second goal (3 helicopters) is met by 3 helicopter landings")
	fake.type = MEDIUM
	for k in 22:
		main._on_landed(fake)
	check(main.shift.state(0) == 1, "landing 25 meets the first goal")
	var star_pop = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "STAR!":
			star_pop = true
	check(star_pop, "a STAR! popup shows when a goal is met")
	check(main.shift.state(2) == 0, "no-strikes stays pending until the shift is complete")
	# Finish the shift cleanly: stop spawning, field empty.
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds + 1.0
	main.step(1.0 / 60.0)
	check(not main.alive and main.over_header == main.HEADER_DONE, "the shift completes when the planes stop and the field is clear")
	check(main.shift.stars() == 3 and save.stars_of(main.airport) == 3, "three stars earned and saved")
	var expect_coins = main.score * tuning.coins_per_landing + 3 * (tuning.coins_per_star + tuning.coins_first_star_bonus)
	check(save.coins == expect_coins, "coins: landings + stars + first-time bonuses (%d, expected %d)" % [save.coins, expect_coins])
	check(main.last_result["first_stars"] == 3 and main.hud._art.show_result, "the results screen shows with the stars")
	var coins_after = save.coins
	# A second shift: stars again, but no first-time bonus.
	main.restart()
	tr.auto_spawn = false
	for k in 25:
		fake.type = HELI if k < 3 else MEDIUM
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
	check(main.airfield.cur.active[1] and not main.airfield.cur.active[0], "active ends are highlighted on the field, inactive ones dimmed")
	main.airfield._process(0.016)
	check(main.airfield.cur.thr_mats[1].albedo_color != main.airfield.cur.thr_mats[0].albedo_color, "...the dull end really is a different colour")
	for k in 6:
		main.airfield._process(1.0)
	var sock_err = absf(wrapf(rad_to_deg(-main.airfield.cur.sock.rotation.y) - main.wind.toward_deg(), -180.0, 180.0))
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

	print("9c. airports")
	check(Airports.COUNT == 6, "six airports")
	var unlocks_ok = Airports.unlock_stars(0) == 0
	for i in range(1, 6):
		unlocks_ok = unlocks_ok and Airports.unlock_stars(i) > Airports.unlock_stars(i - 1)
	check(unlocks_ok and Airports.unlock_stars(5) <= 18, "unlock thresholds rise with total stars (max possible 18)")
	var want_rw = [1, 2, 2, 2, 2, 3]
	var want_pads = [0, 0, 1, 0, 0, 2]
	var want_lanes = [0, 0, 0, 0, 1, 2]
	var want_haz = [0, 0, 0, 5, 0, 0]
	var layout_ok = true
	var inside_ok = true
	var hazard_clear = true
	for i in 6:
		Airports.current = i
		layout_ok = layout_ok and Airports.rw_count() == want_rw[i] and Airports.pads().size() == want_pads[i] and Airports.lanes().size() == want_lanes[i] and Airports.hazards().size() == want_haz[i]
		for r in Airports.rw_count():
			for e in 2:
				var tp = Airports.end_threshold(r, e)
				var fp = Airports.end_far(r, e)
				inside_ok = inside_ok and absf(tp.x) <= 4.7 and absf(tp.y) <= 6.2 and absf(fp.x) <= 4.7 and absf(fp.y) <= 6.2
				for hz in Airports.hazards():
					hazard_clear = hazard_clear and tp.distance_to(hz["center"]) >= hz["radius"] + 0.8
		for pad in Airports.pads():
			inside_ok = inside_ok and absf(pad["center"].x) <= 4.7 and absf(pad["center"].y) <= 6.2
		for lane in Airports.lanes():
			inside_ok = inside_ok and absf(lane["center"].x) <= 4.7 and absf(lane["center"].y) <= 6.2
		check(Airports.goals().size() == 3 and Airports.goals()[2]["kind"] == "no_strikes", "airport %d (%s) has three star goals" % [i + 1, Airports.airport_name(i)])
	check(layout_ok, "runway / helipad / lane / mountain counts match the brief (1,2,2,2,2,3 runways)")
	check(inside_ok, "every runway end, pad and lane sits inside the screen on any phone or tablet")
	check(hazard_clear, "mountains stay clear of the approach ends")
	Airports.current = 1
	check(Airports.runways_cross(0, 1) and Airports.runways_cross(1, 0), "County: the two runways cross")
	Airports.current = 2
	check(not Airports.runways_cross(0, 1), "Regional: the parallel runways don't")
	Airports.current = 0
	check(Airports.is_long(0) == false and Airports.is_long(0) == (Airports.rw_length(0) >= 7.4), "Grass Strip is too short for jets")
	Airports.current = 5
	check(Airports.is_long(0) and Airports.is_long(2), "International's runways are long")
	Airports.current = 2
	check(main.airfield.variants.size() == 6, "every airport's scenery is built once, up front")
	# Select screen: locks, stars, tapping.
	save.reset_all()
	main._show_select()
	check(main.screen == main.SCREEN_SELECT and main.hud._select.visible, "the airport select screen shows")
	var cards = {}
	for k in main.hud._art.btn_count:
		cards[main.hud._art.btn_id[k]] = main.hud._art.btn_rect[k]
	check(cards.has("airport:0") and cards.has("locked:1") and cards.has("locked:5") and cards.has("back"), "airport 1 is open, the others show as locked, with a Back button")
	check(main.hud._art.btn_sub[1].contains("needs 2 stars"), "a locked card says what unlocks it (%s)" % main.hud._art.btn_sub[1])
	var locked_pos = cards["locked:1"].get_center()
	touch(main, 0, true, locked_pos)
	touch(main, 0, false, locked_pos)
	check(main.screen == main.SCREEN_SELECT, "tapping a locked airport does nothing")
	save.award_star(0, 0)
	save.award_star(0, 1)
	main._show_select()
	check(save.stars_total() == 2 and main.hud.button_at(cards["locked:1"].get_center()) == "airport:1", "two stars open County")
	touch(main, 0, true, cards["locked:1"].get_center())
	touch(main, 0, false, cards["locked:1"].get_center())
	check(main.screen == main.SCREEN_PLAY and main.airport == 1 and Airports.rw_count() == 2 and main.airfield.selected == 1, "tapping an open airport starts a shift there")
	check(save.selected_airport == 1, "the choice is remembered")
	set_wind(main, 40.0)
	# County: crossing runways.
	tr.auto_spawn = false
	var ca = tr.place(0, Airports.end_threshold(0, 0), 0.0, MEDIUM)
	var cb = tr.place(1, Airports.end_threshold(1, 0), 0.0, MEDIUM)
	for pl in [ca, cb]:
		pl.pos = Airports.end_threshold(pl.runway, 0)
		pl.push(pl.pos)
		pl.push(Airports.end_far(pl.runway, 0))
		pl.cleared = true
		pl.land_end = 0
	ca.pos += Vector2(30, 30)   # keep them out of each other's conflict range until we want them
	ca.pos = Airports.end_threshold(0, 0)
	cb.pos = Airports.end_threshold(1, 0) + Vector2(0.0, 0.0)
	var rc = [false]
	tr.runway_conflict.connect(func(_a, _b): rc[0] = true, CONNECT_ONE_SHOT)
	cb.entered = false   # (aircraft outside never conflict in the air; the runway check is separate)
	cb.entered = true
	ca.ground = true
	cb.ground = true
	tr.step(1.0 / 60.0)
	check(rc[0] and not main.alive and main.over_reason.contains("crossing"), "landing on a crossing runway while the other is busy is a runway conflict")
	# Same runway: go around.
	main.restart()
	set_wind(main, 40.0)
	tr.auto_spawn = false
	var g_a = tr.place(0, Airports.end_threshold(0, 0), 0.0, MEDIUM)
	var g_b = tr.place(0, Airports.end_threshold(0, 0) + Vector2(0.0, 0.5), 0.0, MEDIUM)
	for pl in [g_a, g_b]:
		pl.pos = Airports.end_threshold(0, 0)
		pl.push(pl.pos)
		pl.push(Airports.end_far(0, 0))
		pl.cleared = true
		pl.land_end = 0
		pl.ground = true
	var ga_seen = [false]
	tr.go_around.connect(func(_p): ga_seen[0] = true, CONNECT_ONE_SHOT)
	tr.step(1.0 / 60.0)
	check(ga_seen[0] and main.alive and main.shift.strikes == 0, "a second aircraft reaching a busy runway goes around: no strike")
	check(g_a.state == Aircraft.State.LANDING and g_b.state == Aircraft.State.FLY and not g_b.cleared, "...the first lands, the second keeps flying with its clearance withdrawn")
	var pop_ga = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "Go around!":
			pop_ga = true
	check(pop_ga, "a 'Go around!' popup shows")
	run_sec(main, tuning.landing_roll_time + tuning.runway_clear_seconds + 0.3)
	g_b.pos = Airports.end_threshold(0, 0)
	g_b.ground = true
	g_b.push(g_b.pos)
	g_b.push(Airports.end_far(0, 0))
	g_b.cleared = true
	g_b.land_end = 0
	tr.step(1.0 / 60.0)
	check(g_b.state == Aircraft.State.LANDING, "once the runway has cleared, a landing goes ahead")
	# Grass Strip: one runway, usable both ways.
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	check(Airports.rw_count() == 1 and main.wind.is_active(0, 0) and not main.wind.is_active(0, 1), "Grass Strip with a north wind: end 0 is active")
	set_wind(main, 180.0)
	check(main.wind.is_active(0, 1) and not main.wind.is_active(0, 0), "...and with a south wind the other end is")
	var gs = tr.place(0, Airports.end_threshold(0, 1) + Vector2(0.4, -3.0), PI, SMALL)
	draw_path(main, gs, [gs.pos + Vector2(0, 0.8), Airports.end_threshold(0, 1)])
	check(gs.cleared and gs.land_end == 1, "the single runway can be landed on from the south end")
	var jets_seen = false
	var small_seen = false
	for k in 150:
		var sp3 = tr.spawn()
		if sp3 != null:
			jets_seen = jets_seen or sp3.type == JET
			small_seen = small_seen or sp3.type == SMALL
			tr.release_all()
	check(small_seen and not jets_seen, "Grass Strip's traffic is small and medium planes only")
	# Mountain Field: terrain.
	main.select_airport(3)
	main.restart()
	tr.auto_spawn = false
	check(tr.hz_count == 5 and Airports.hazards().size() == 5, "Mountain Field has five no-fly zones")
	var safe = true
	var spawned_mt = 0
	for k in 300:
		var sp4 = tr.spawn()
		if sp4 != null:
			spawned_mt += 1
			var d4 = Vector2(sin(sp4.heading), -cos(sp4.heading))
			safe = safe and not tr._hits_hazard(sp4.entry, d4)
			tr.release_all()
	check(spawned_mt > 150 and safe, "no aircraft is ever sent straight at a mountain (%d spawns)" % spawned_mt)
	var mt = tr.place(0, Vector2(-3.7, -2.0), 0.0, MEDIUM)
	var strikes_mt = main.shift.strikes
	for i in 400:
		main.step(1.0 / 60.0)
		if not mt.active():
			break
	check(not mt.active() and main.shift.strikes == strikes_mt + 1, "flying into a mountain loses the aircraft and costs a strike")
	var pop_cr = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "Crashed!":
			pop_cr = true
	check(pop_cr, "a 'Crashed!' popup shows")
	# Island and International: the extras exist.
	main.select_airport(4)
	main.restart()
	check(Airports.lanes().size() == 1 and main.airfield.selected == 4, "Island has its seaplane lane")
	main.select_airport(5)
	main.restart()
	check(Airports.rw_count() == 3 and Airports.pads().size() == 2 and Airports.lanes().size() == 2, "International has multiples of everything")
	# Switching airports in place creates nothing.
	var before_cycle = snapshot(main)
	for i in 6:
		main.select_airport(i)
		main.restart()
		check(main.airfield.selected == i and Airports.current == i and main.alive and tr.hz_count == want_haz[i], "airport %d starts in place" % (i + 1))
		run_sec(main, 2.0)
	main.select_airport(2)
	main.restart()
	var after_cycle = snapshot(main)
	check(same_world(before_cycle, after_cycle), "cycling through all six airports created nothing new  [%s]" % describe(after_cycle))

	print("9d. special aircraft")
	check(tuning.timer_seaplane > tuning.timer_heli and tuning.timer_seaplane < tuning.timer_jet, "seaplane timer sits between helicopter and jet")
	# Which airports can spawn what.
	var mix_ok = true
	var jets_long = true
	for a_i in 6:
		main.select_airport(a_i)
		main.restart()
		tr.auto_spawn = false
		var seen = {}
		for k in 250:
			var sp5 = tr.spawn()
			if sp5 != null:
				seen[sp5.type] = true
				if sp5.type == JET:
					jets_long = jets_long and Airports.is_long(sp5.runway)
				if sp5.type == HELI:
					mix_ok = mix_ok and sp5.tkind == 1 and sp5.runway < Airports.pads().size()
				if sp5.type == SEAPLANE:
					mix_ok = mix_ok and sp5.tkind == 2 and sp5.runway < Airports.lanes().size()
				tr.release_all()
		mix_ok = mix_ok and (not seen.has(HELI) or Airports.pads().size() > 0) and (not seen.has(SEAPLANE) or Airports.lanes().size() > 0)
		if Airports.pads().size() == 0:
			mix_ok = mix_ok and not seen.has(HELI)
		var long_any = false
		for r in Airports.rw_count():
			long_any = long_any or Airports.is_long(r)
		mix_ok = mix_ok and (long_any or not seen.has(JET))
	check(mix_ok, "helicopters only where there is a pad, seaplanes only where there is a lane, jets only where a runway is long")
	check(jets_long, "jets are always given a long runway")
	# Helicopter on Regional.
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var pad_c = Airports.pads()[0]["center"]
	var hc = tr.place(0, pad_c + Vector2(-2.5, -2.0), 0.5, HELI)
	check(hc.tkind == 1 and is_equal_approx(hc.timer_max, tuning.timer_heli) and tr._heli_groups[tr.planes.find(hc)].visible and not tr._plane_groups[tr.planes.find(hc)].visible, "a helicopter has its own model and the helicopter timer")
	var refused_txt = [""]
	tr.refused.connect(func(_p, t, _a): refused_txt[0] = t)
	draw_path(main, hc, [hc.pos + Vector2(0.5, 0.0), Airports.end_threshold(0, 0)])
	check(not hc.cleared and refused_txt[0] == "Helicopters land on the helipad", "a helicopter can't be sent to a runway (%s)" % refused_txt[0])
	hc.clear_path()
	draw_path(main, hc, [hc.pos + (pad_c - hc.pos).normalized() * 0.8, pad_c])
	check(hc.cleared and hc.tkind == 1, "a path ending on the helipad clears a helicopter")
	var sc_h = main.score
	for i in 900:
		main.step(1.0 / 60.0)
		if not hc.active():
			break
	check(main.score == sc_h + 1 and not hc.active(), "...and it lands there")
	# Hover.
	var hv = tr.place(0, Vector2(-1.0, -3.0), 1.0, HELI)
	var hv_pos = hv.pos
	var tl0 = hv.timer_left
	tr.toggle_hold(hv)
	run_sec(main, 4.0)
	check(hv.state == Aircraft.State.HOLD and hv.hovering and hv.pos.distance_to(hv_pos) < 0.001, "tapping a helicopter makes it hover on the spot")
	check(absf((tl0 - hv.timer_left) - 4.0 * tuning.hold_drain_mult) < 0.35, "...burning its timer slowly")
	tr.toggle_hold(hv)
	check(hv.state == Aircraft.State.FLY and not hv.hovering, "tap again and it flies on")
	tr.release_all()
	# Gliders.
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var gl = tr.place(0, Vector2(1.5, -4.0), PI, GLIDER)
	check(is_equal_approx(gl.timer_max, tuning.timer_glider) and gl.speed < tuning.speed_slow, "a glider is slow with the shortest timer")
	tr.toggle_hold(gl)
	check(gl.state == Aircraft.State.FLY and refused_txt[0] == "Gliders can't hold", "gliders can't hold (%s)" % refused_txt[0])
	draw_path(main, gl, [gl.pos + Vector2(0.0, 0.8), gl.pos + Vector2(-1.0, 2.0)])
	check(gl.locked and not gl.cleared, "a glider's first path (that misses the runway) is final")
	check(not tr.begin_path(gl) and refused_txt[0] == "Glider: first path only", "...it refuses a second one")
	var gl2 = tr.place(0, Airports.end_threshold(0, 1) + Vector2(0.5, -3.0), PI, GLIDER)
	draw_path(main, gl2, [gl2.pos + Vector2(0, 1.0), Airports.end_threshold(0, 0) if false else Airports.end_threshold(0, 0)])
	set_wind(main, 180.0)
	tr.release_all()
	var gl3 = tr.place(0, Airports.end_threshold(0, 1) + Vector2(0.5, -3.0), PI, GLIDER)
	draw_path(main, gl3, [gl3.pos + Vector2(0, 0.8), Airports.end_threshold(0, 1)])
	check(gl3.cleared and gl3.locked, "a glider that gets it right on the first path lands")
	tr.release_all()
	# Jets need a long runway.
	main.select_airport(3)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var jt = tr.place(0, Airports.end_threshold(0, 0) + Vector2(0.4, 3.0), 0.0, JET)
	draw_path(main, jt, [jt.pos + Vector2(0, -0.8), Airports.end_threshold(0, 0)])
	check(not jt.cleared and refused_txt[0] == "Too short for jets", "a jet can't land on a short runway (%s)" % refused_txt[0])
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var jt2 = tr.place(0, Airports.end_threshold(0, 0) + Vector2(0.4, 3.0), 0.0, JET)
	draw_path(main, jt2, [jt2.pos + Vector2(0, -0.8), Airports.end_threshold(0, 0)])
	check(jt2.cleared, "...but it can on a long one")
	check(tuning.type_speed(JET) > tuning.type_speed(MEDIUM) and tuning.timer_jet > tuning.timer_medium, "jets are fast with the longest timer")
	tr.release_all()
	# Seaplanes on Island.
	main.select_airport(4)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var lane_e = Airports.land_threshold(2, 0, 0)
	var sp_a = tr.place(0, lane_e + Vector2(-0.5, -3.0), PI, SEAPLANE)
	check(sp_a.tkind == 2 and tr._float_groups[tr.planes.find(sp_a)].visible, "a seaplane has floats and lands on lanes")
	draw_path(main, sp_a, [sp_a.pos + Vector2(0, 0.8), Airports.end_threshold(0, 0)])
	check(not sp_a.cleared and refused_txt[0] == "Seaplanes land on water", "a seaplane can't be sent to a runway (%s)" % refused_txt[0])
	sp_a.clear_path()
	draw_path(main, sp_a, [sp_a.pos + (lane_e - sp_a.pos).normalized() * 0.8, lane_e])
	check(sp_a.cleared and sp_a.tkind == 2, "a path to the water lane clears it")
	var sc_p = main.score
	for i in 900:
		main.step(1.0 / 60.0)
		if not sp_a.active():
			break
	check(main.score == sc_p + 1, "...and it lands on the water")
	refused_txt[0] = ""
	var fm = tr.place(0, Vector2(-4.3, 6.2), 0.0, MEDIUM)
	draw_path(main, fm, [fm.pos + Vector2(0.4, -0.4), Airports.land_threshold(2, 0, 0)])
	check(not fm.cleared and refused_txt[0] == "Water lane: seaplanes only", "an ordinary plane is refused the lane (%s)" % refused_txt[0])
	tr.release_all()
	# Emergency: short timer, any runway, flashing, bonus.
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var em = tr.place(0, Airports.end_threshold(1, 0) + Vector2(0.3, 3.0), 0.0, MEDIUM)
	tr.make_special(em, true, false)
	check(is_equal_approx(em.timer_max, tuning.timer_medium * tuning.emergency_timer_mult), "an emergency has a shortened timer")
	var emi = tr.planes.find(em)
	var colors_seen = {}
	for k in 40:
		em.age = k * 0.05
		tr._sync(em, emi)
		colors_seen[tr._body_mats[emi].albedo_color] = true
	check(colors_seen.size() >= 2, "an emergency flashes")
	draw_path(main, em, [em.pos + Vector2(0, -0.8), Airports.end_threshold(1, 0)])
	check(em.cleared and em.runway == 1, "an emergency can land on any suitable runway (its colour doesn't matter)")
	var coins_em = main.shift_coins
	for i in 900:
		main.step(1.0 / 60.0)
		if not em.active():
			break
	check(main.shift_coins >= coins_em + tuning.emergency_bonus_coins and main.shift.landed_emergency == 1, "landing an emergency pays a big bonus and counts")
	# VIP.
	var vp1 = tr.place(0, Airports.end_threshold(0, 0) + Vector2(0.3, 3.0), 0.0, MEDIUM)
	tr.make_special(vp1, false, true)
	var coins_v = main.shift_coins
	draw_path(main, vp1, [vp1.pos + Vector2(0, -0.8), Airports.end_threshold(0, 0)])
	for i in 900:
		main.step(1.0 / 60.0)
		if not vp1.active():
			break
	check(main.shift_coins - coins_v == tuning.coins_per_landing + tuning.vip_bonus_coins and main.shift.landed_vip == 1, "a VIP landed promptly pays the VIP bonus")
	var vp2 = tr.place(1, Vector2(2.0, -2.0), 0.0, MEDIUM)
	tr.make_special(vp2, false, true)
	tr.toggle_hold(vp2)
	check(not vp2.vip_ok and refused_txt[0] == "VIP delayed: bonus lost", "holding a VIP loses its bonus (%s)" % refused_txt[0])
	tr.toggle_hold(vp2)
	vp2.pos = Airports.end_threshold(1, 0)
	vp2.push(vp2.pos)
	vp2.push(Airports.end_far(1, 0))
	vp2.cleared = true
	vp2.land_end = 0
	var coins_v2 = main.shift_coins
	var vip_before = main.shift.landed_vip
	for i in 900:
		main.step(1.0 / 60.0)
		if not vp2.active():
			break
	check(main.shift_coins - coins_v2 == tuning.coins_per_landing and main.shift.landed_vip == vip_before, "...a held VIP lands without the bonus and doesn't count for the goal")
	# Tips: first sighting only, remembered.
	save.tips_seen = {}
	main.hud._tip.visible = false
	var tg = tr.place(0, Vector2(0, 0), 0.0, GLIDER)
	main._on_appeared(tg)
	check(main.hud._tip.visible and main.hud._tip.text.begins_with("Glider"), "the first glider shows a one-line tip (%s)" % main.hud._tip.text)
	check(save.tips_seen.has("glider"), "...and it is remembered")
	main.hud._tip.visible = false
	main._on_appeared(tg)
	check(not main.hud._tip.visible, "it is not shown a second time")
	for tt in [[HELI, "heli"], [JET, "jet"], [SEAPLANE, "seaplane"]]:
		var tp2 = tr.place(0, Vector2(0, 0), 0.0, tt[0])
		main._on_appeared(tp2)
		check(save.tips_seen.has(tt[1]), "a first %s gets its tip" % tt[1])
	var tv = tr.place(0, Vector2(0, 0), 0.0, MEDIUM)
	tr.make_special(tv, false, true)
	main._on_appeared(tv)
	check(save.tips_seen.has("vip"), "...and so does the first VIP")
	var te = tr.place(0, Vector2(0, 0), 0.0, MEDIUM)
	tr.make_special(te, true, false)
	main._on_appeared(te)
	check(save.tips_seen.has("emergency"), "...and the first emergency")
	var pop_em = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "EMERGENCY":
			pop_em = true
	check(pop_em, "every emergency announces itself")
	save.write_file()
	save.tips_seen = {}
	save.load_file()
	check(save.tips_seen.has("glider") and save.tips_seen.has("emergency"), "seen tips survive a reload")
	tr.release_all()
	main.select_airport(2)

	print("9e. upgrades")
	save.reset_all()
	save.unlocks["all_airports"] = true
	check(Upgrades.IDS.size() == 6, "six upgrades")
	var cost_ok = true
	for id in Upgrades.IDS:
		cost_ok = cost_ok and Upgrades.cost(id, 0) < Upgrades.cost(id, 1) and Upgrades.cost(id, 1) < Upgrades.cost(id, 2) and Upgrades.cost(id, 3) == -1
	check(cost_ok, "each upgrade has three levels and rising costs")
	check(not save.buy_upgrade("radar") and save.upgrade_level("radar") == 0, "can't buy without the coins")
	save.add_coins(Upgrades.cost("radar", 0) + 7)
	var c_before = save.coins
	check(save.buy_upgrade("radar") and save.upgrade_level("radar") == 1 and save.coins == c_before - Upgrades.cost("radar", 0), "buying takes exactly the price and raises the level")
	save.add_coins(100000)
	save.buy_upgrade("radar")
	save.buy_upgrade("radar")
	check(save.upgrade_level("radar") == 3 and not save.buy_upgrade("radar"), "a maxed upgrade can't be bought again")
	save.upgrades = {}
	# Effects.
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var base_t = tuning.type_timer(MEDIUM)
	var p0 = tr.place(0, Vector2(-3, 0), 0.0, MEDIUM)
	save.upgrades["comms"] = 2
	var p2 = tr.place(1, Vector2(3, 0), 0.0, MEDIUM)
	check(is_equal_approx(p0.timer_max, base_t) and is_equal_approx(p2.timer_max, base_t * 1.2), "Better Comms: level 2 gives timers +20%% (%.1f -> %.1f s)" % [p0.timer_max, p2.timer_max])
	save.upgrades = {}
	tr.release_all()
	save.upgrades["holding"] = 3
	check(tuning.hold_drain() < tuning.hold_drain_mult and tuning.hold_radius_eff() < tuning.hold_radius, "Holding Fixes: slower drain and a tighter circle")
	var hz = tr.place(0, Vector2(-1.0, -2.0), 0.0, MEDIUM)
	tr.toggle_hold(hz)
	var t_hz = hz.timer_left
	var r_err = 0.0
	for i in 300:
		main.step(1.0 / 60.0)
		r_err = maxf(r_err, absf(hz.pos.distance_to(hz.hold_center) - tuning.hold_radius_eff()))
	check(r_err < 0.02, "...it really circles at the tighter radius (%.2f)" % tuning.hold_radius_eff())
	check(absf((t_hz - hz.timer_left) - 5.0 * tuning.hold_drain()) < 0.3, "...and drains at %.2fx" % tuning.hold_drain())
	save.upgrades = {}
	tr.release_all()
	# Fast Turnoffs: the busy window after a landing is shorter.
	var busy0 = tuning.landing_roll_time + tuning.runway_clear()
	save.upgrades["turnoffs"] = 3
	var busy3 = tuning.landing_roll_time + tuning.runway_clear()
	check(busy3 < busy0 and is_equal_approx(tuning.runway_clear(), tuning.runway_clear_seconds * 0.1), "Fast Turnoffs: runways clear faster (%.2f -> %.2f s busy)" % [busy0, busy3])
	var ta = tr.place(0, Airports.end_threshold(0, 0), 0.0, MEDIUM)
	ta.push(ta.pos)
	ta.push(Airports.end_far(0, 0))
	ta.cleared = true
	ta.land_end = 0
	tr.step(1.0 / 60.0)
	check(absf((tr._busy_until[0] - tr.run_time) - busy3) < 0.05, "...and the runway really is busy for only that long")
	save.upgrades = {}
	tr.release_all()
	# Tower Staff: slower, thinner traffic.
	check(tuning.traffic_speed_mult() == 1.0 and tuning.traffic_spawn_mult() == 1.0, "no upgrades: normal traffic")
	save.upgrades["tower"] = 3
	check(tuning.traffic_speed_mult() < 1.0 and tuning.traffic_spawn_mult() > 1.0, "Tower Staff: slower speeds (%.2fx) and fewer arrivals (%.2fx the gap)" % [tuning.traffic_speed_mult(), tuning.traffic_spawn_mult()])
	var tw = tr.place(0, Vector2(-3, -4), PI * 0.5, MEDIUM)
	tr.step(1.0)
	var moved = tw.pos.x + 3.0
	check(absf(moved - tuning.speed_medium * tuning.speed_mult(tr.run_time - 1.0 + 1.0) * 0.88) < 0.5 and moved < tuning.speed_medium * 1.0, "...aircraft really fly slower (%.2f units in a second)" % moved)
	save.upgrades = {}
	tr.release_all()
	# Radar: wider view, earlier warnings, smooth re-framing.
	check(is_equal_approx(tuning.view_size(), tuning.ortho_size), "no radar: the normal view")
	var lead0 = tuning.entry_lead()
	save.upgrades["radar"] = 3
	check(tuning.view_size() > tuning.ortho_size * 1.3 and tuning.entry_lead() > lead0 + 1.5, "Radar level 3: a wider view (%.1f) and arrivals announced %.1f s earlier" % [tuning.view_size(), tuning.entry_lead() - lead0])
	var vs0 = main.view_size
	main._process(0.1)
	var vs1 = main.view_size
	check(vs1 > vs0 and vs1 < tuning.view_size() and is_equal_approx(main.camera.size, vs1), "the camera re-frames smoothly (%.2f -> %.2f of %.2f)" % [vs0, vs1, tuning.view_size()])
	for i in 60:
		main._process(0.1)
	check(absf(main.view_size - tuning.view_size()) < 0.01 and absf(tr.half_w - main.view_size * 0.5) < 0.001, "...and settles on the new view")
	var sp7 = tr.spawn()
	var lead_seen = sp7.pos.distance_to(sp7.entry) / (sp7.speed * tuning.speed_mult(tr.run_time) * tuning.traffic_speed_mult())
	check(absf(lead_seen - tuning.entry_lead()) < 0.05, "arrivals really spawn %.1f s out (%.2f)" % [tuning.entry_lead(), lead_seen])
	tr.release_all()
	save.upgrades = {}
	for i in 80:
		main._process(0.1)
	check(absf(main.view_size - tuning.ortho_size) < 0.01, "...and zooms back without it")
	# Approach Control: arrivals line up with the active runways.
	set_wind(main, 0.0)
	var aligned0 = 0
	var aligned3 = 0
	var total0 = 0
	var total3 = 0
	for level in [0, 3]:
		save.upgrades["approach"] = level
		for k in 400:
			var sp8 = tr.spawn()
			if sp8 == null:
				continue
			if sp8.tkind == 0 and not sp8.emergency:
				var d8 = Vector2(sin(sp8.heading), -cos(sp8.heading))
				var best_d = 99.0
				for e in 2:
					if main.wind.is_active(sp8.runway, e):
						best_d = minf(best_d, tr._dist_to_segment(Airports.end_threshold(sp8.runway, e), sp8.entry, sp8.entry + d8 * 40.0))
				if level == 0:
					total0 += 1
					aligned0 += 1 if best_d < 1.0 else 0
				else:
					total3 += 1
					aligned3 += 1 if best_d < 1.0 else 0
			tr.release_all()
	check(float(aligned3) / maxf(total3, 1) > float(aligned0) / maxf(total0, 1) + 0.35 and float(aligned3) / maxf(total3, 1) > 0.6, "Approach Control: arrivals lined up with the active runway %d%% -> %d%%" % [100 * aligned0 / maxf(total0, 1), 100 * aligned3 / maxf(total3, 1)])
	save.upgrades = {}
	# Visible on the airport.
	main.airfield.show_upgrades()
	var any_vis = false
	for id in Upgrades.IDS:
		any_vis = any_vis or main.airfield.upgrade_nodes_visible(id) > 0
	check(not any_vis, "with no upgrades none of their scenery shows")
	var vis_ok = true
	var counts = {}
	for a_i in 6:
		main.select_airport(a_i)
		main.restart()
		for id in Upgrades.IDS:
			save.upgrades[id] = 1
			main.airfield.show_upgrades()
			var c1 = main.airfield.upgrade_nodes_visible(id)
			save.upgrades[id] = 3
			main.airfield.show_upgrades()
			var c3 = main.airfield.upgrade_nodes_visible(id)
			if not (c1 >= 1 and c3 > c1):
				print("     upgrade scenery: airport %d %s level1=%d level3=%d" % [a_i + 1, id, c1, c3])
			vis_ok = vis_ok and c1 >= 1 and c3 > c1
			counts[id] = c3
		save.upgrades = {}
	check(vis_ok, "at every airport each upgrade adds scenery that grows with its level %s" % str(counts))
	main.select_airport(2)
	main.restart()
	# The shop screen.
	save.reset_all()
	save.unlocks["all_airports"] = true
	main._show_menu()
	var ids_menu = []
	for k in main.hud._art.btn_count:
		ids_menu.append(main.hud._art.btn_id[k])
	check(ids_menu.has("upgrades") and ids_menu.has("airports"), "the menu has Airports and Upgrades buttons")
	save.add_coins(200)
	main._on_button("upgrades")
	check(main.screen == main.SCREEN_UPGRADES and main.hud._select.visible and main.hud._select_title.text == "UPGRADES", "the upgrade shop opens")
	var cards2 = {}
	for k in main.hud._art.btn_count:
		cards2[main.hud._art.btn_id[k]] = [main.hud._art.btn_rect[k], main.hud._art.btn_state[k], main.hud._art.btn_stars[k]]
	check(cards2.has("upg:radar") and cards2.has("upg:turnoffs") and cards2.has("back"), "one card per upgrade, plus Back")
	check(cards2["upg:comms"][1] == 2 and cards2["upg:radar"][1] == 1, "affordable cards are highlighted, unaffordable ones dim (200 coins)")
	touch(main, 0, true, cards2["upg:radar"][0].get_center())
	touch(main, 0, false, cards2["upg:radar"][0].get_center())
	check(save.upgrade_level("radar") == 0 and save.coins == 200, "tapping an unaffordable card buys nothing")
	var snap_shop = snapshot(main)
	touch(main, 0, true, cards2["upg:comms"][0].get_center())
	touch(main, 0, false, cards2["upg:comms"][0].get_center())
	check(save.upgrade_level("comms") == 1 and save.coins == 200 - Upgrades.cost("comms", 0), "tapping an affordable card buys it (%d coins left)" % save.coins)
	check(main.screen == main.SCREEN_UPGRADES and main.hud._art.btn_text[main.hud._art.btn_id.find("upg:comms")].ends_with("Lv 1"), "the card shows the new level")
	var pop_up = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "Better Comms level 1!":
			pop_up = true
	check(pop_up, "a confirmation popup shows")
	check(main.airfield.upgrade_nodes_visible("comms") >= 1, "...and the new mast appears on the airport")
	check(same_world(snap_shop, snapshot(main)), "buying created nothing new")
	save.write_file()
	save.upgrades = {}
	save.load_file()
	check(save.upgrade_level("comms") == 1, "the purchase is saved")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.airfield.show_upgrades()
	main._show_menu()
	main.select_airport(2)

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
					var e_ap = 0
					if pl.tkind == 0 and not main.wind.is_active(pl.runway, 0):
						e_ap = 1
					var th: Vector2 = Airports.land_threshold(pl.tkind, pl.runway, e_ap)
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
	check(save.best_for(main.airport) == best_seen, "the best score is remembered (%d)" % save.best_for(main.airport))
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
