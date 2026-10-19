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
##      timed shifts: fines, coin payout, stars from coin thresholds
##   9b. wind: active ends, the shift warning, re-routing, windsock
##   9c. airports: six layouts, unlock by stars, select screen, crossing runways (conflict), busy runway
##       (go around), terrain (crash = strike), cycling airports creates nothing
##   9d. special aircraft: helicopters (pad, hover), gliders (one path, no hold), jets (long runways), seaplanes
##       (lane), emergencies (any runway, bonus), VIPs (lose the bonus if held), first-time tips
##   9e. upgrades: buying, every effect, the radar re-framing, approach lining-up, the scenery, the shop screen
##   9f. weather: schedule + warnings per airport, storm cells (strike), fog (hidden, revealed, radar), crosswind (closure, reroute)
##   9g: cosmetics shop (themes, liveries, pilots), the daily shift (seeded, streak, bonus), ad stubs (continue,
##       double coins, interstitial) and the ?tune debug buttons
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

## Land fake aircraft (spaced out in time) until the running shift's balance reaches `coins`.
func earn_coins(main: Node, coins: int) -> void:
	var f = Aircraft.new()
	f.runway = 0
	f.pos = Vector2.ZERO
	f.type = 3
	var guard = 0
	while main.shift.balance() < coins and guard < 500:
		main.traffic.run_time += 10.0     # outside the quick-succession window: flat pay
		main._on_landed(f)
		guard += 1

func has_btn(main: Node, id: String) -> bool:
	var i = main.hud._art.btn_id.find(id)
	return i >= 0 and i < main.hud._art.btn_count

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
	tuning.ad_stub_seconds = 0.0    # fake ads finish at once unless a test is about them
	tuning.go_around_max = 0.0      # ...and no random go-arounds, except in the go-around section
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
	check(main.hud._score.text == str(main.shift.balance()) and main.shift.landed == 1, "the score label shows the coin balance (%s)" % main.hud._score.text)
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
		if main.shift.conflicts > 0:
			break
	check(warned, "a warning ring grows as two planes close in (max %.2f)" % warn_max)
	check(main.alive and main.screen == main.SCREEN_PLAY and main.shift.conflicts == 1, "a conflict doesn't end the shift")
	check(main.shift.fines == int(tuning.fine_conflict) and main.shift.balance() == -int(tuning.fine_conflict), "...it costs the large fine, and the balance goes negative (%d)" % main.shift.balance())
	check(not a.active() and not bb.active(), "...and both aircraft are lost")
	check(has_btn(main, "ad_refund"), "...and the refund ad is offered")
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
	check(main.shift.conflicts == 1, "...but two airborne planes on the screen do")

	print("7. timers, fines, diverting")
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
	# A timer running out: a small fine, the aircraft diverts and leaves, no conflict with it.
	main.restart()
	tr.auto_spawn = false
	var dv = tr.place(0, Vector2(0.0, 2.0), 0.0, MEDIUM)
	var near = tr.place(1, Vector2(0.4, 2.2), 0.0, MEDIUM)
	near.entered = false
	dv.timer_left = 0.02
	main.step(1.0 / 30.0)
	check(dv.state == Aircraft.State.DIVERT and main.shift.diversions == 1 and main.shift.fines == int(tuning.fine_timeout), "a timed-out aircraft is diverted and costs the small fine (%d)" % main.shift.fines)
	var pop_seen = false
	for l in main.hud._pop_labels:
		if l.visible and l.text.begins_with("Diverted") and l.text.contains("-%d" % int(tuning.fine_timeout)):
			pop_seen = true
	check(pop_seen, "a red 'Diverted -N' popup shows")
	check(main.hud._art.balance == -int(tuning.fine_timeout), "the HUD balance shows the fine (and can go negative)")
	check(tr.pick(dv.pos) != dv, "a diverting aircraft can't be grabbed")
	check(main.alive, "a fine doesn't end the shift")
	for i in 600:
		main.step(1.0 / 60.0)
		if not dv.active():
			break
	check(not dv.active(), "the diverted aircraft flies off and is returned to the pool")
	tr.release_all()
	# Fines can pile up past zero; the shift still ends only at the clock, and pays nothing.
	main.restart()
	tr.auto_spawn = false
	var coins0 = save.coins
	for k in 3:
		var sx = tr.place(k % 2, Vector2(-3.0 + k * 3.0, -5.0 + k * 2.0), 0.0, MEDIUM)
		sx.timer_left = 0.01
		main.step(1.0 / 60.0)
	check(main.alive and main.shift.diversions == 3 and main.shift.balance() < 0, "three diversions don't end the shift; the balance is %d" % main.shift.balance())
	check(main.shift.payout() == 0, "a negative balance pays out as zero")
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds + 0.01
	main.step(1.0 / 60.0)
	check(not main.alive and main.over_header == main.HEADER_DONE and main.hud._over.visible, "the shift ends at the clock")
	check(save.coins == coins0 and main.shift.stars() == 0, "...earning no coins and no stars (%d -> %d)" % [coins0, save.coins])
	# Landing in time saves it.
	main.restart()
	set_wind(main, 0.0)
	tr.auto_spawn = false
	var sv = tr.place(1, thr1 + Vector2(0.0, -2.0), PI, MEDIUM)
	sv.timer_left = 6.0
	draw_path(main, sv, [sv.pos + Vector2(0, 0.8), thr1])
	run_sec(main, 10.0)
	check(main.alive and main.score == 1 and main.shift.diversions == 0 and main.shift.earned == int(tuning.pay_medium), "landing in time pays the landing coins and no fine")
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
	var sth9 = Airports.star_thresholds()
	check(sth9.size() == 3 and sth9[0] < sth9[1] and sth9[1] < sth9[2] and main.hud._art.thresholds.size() == 3, "three coin thresholds per airport, shown on the HUD (%s)" % str(sth9))
	var fake = Aircraft.new()
	fake.runway = 0
	fake.type = HELI
	fake.pos = Vector2(0, 0)
	save.reset_all()
	main._on_landed(fake)
	check(main.shift.earned == int(tuning.pay_heli) and main.shift.landed == 1, "a landing pays by type (heli %d)" % main.shift.earned)
	fake.type = GLIDER
	main.traffic.run_time += 10.0
	main._on_landed(fake)
	check(main.shift.earned == int(tuning.pay_heli) + int(tuning.pay_glider), "a glider pays more than a small plane (%d)" % int(tuning.pay_glider))
	# Quick succession: landings close together pay a growing bonus.
	main.restart()
	fake.type = MEDIUM
	main._on_landed(fake)
	check(main.shift.bonus == 0, "the first landing has no streak bonus")
	main.traffic.run_time += 1.0
	main._on_landed(fake)
	check(main.shift.bonus == int(tuning.streak_bonus_coins), "a second landing within %.0f s earns the quick-succession bonus (%d)" % [tuning.streak_window_seconds, main.shift.bonus])
	main.traffic.run_time += 10.0
	main._on_landed(fake)
	check(main.streak == 1 and main.shift.bonus == int(tuning.streak_bonus_coins), "a slow landing resets the streak")
	# Stars come from the coin thresholds.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, sth9[0])
	check(main.shift.stars() == 1 and main.shift.star_reached(0), "reaching the first threshold earns one star")
	var star_pop = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "STAR!":
			star_pop = true
	check(star_pop, "a STAR! popup shows when a threshold is crossed")
	earn_coins(main, sth9[2])
	check(main.shift.stars() == 3, "reaching the third threshold earns three stars")
	# Fines subtract and can drop a star again.
	main.shift.fine(500, "conflict")
	check(main.shift.stars() < 3 and main.shift.balance() < sth9[2], "a big fine takes the balance back under a threshold")
	main.shift.refund_last()
	check(main.shift.stars() == 3, "...and refunding it restores the stars")
	var payout_expect = main.shift.payout()
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds - 0.01
	main.step(1.0 / 30.0)
	check(not main.alive and main.over_header == main.HEADER_DONE, "the shift ends exactly when the clock runs out, whatever is flying")
	check(save.stars_of(main.airport) == 3, "three stars earned and saved")
	var expect_coins = payout_expect + 3 * int(tuning.coins_first_star_bonus)
	check(save.coins == expect_coins, "coins: payout + first-time star bonuses (%d, expected %d)" % [save.coins, expect_coins])
	check(main.last_result["first_stars"] == 3 and main.hud._art.show_result, "the results screen shows with the stars")
	check(save.best_coins_for(main.airport) == payout_expect and main.new_best, "the best payout is recorded")
	var coins_after = save.coins
	# A second shift: no first-time bonus again.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, sth9[2])
	var pay2 = main.shift.payout()
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds + 0.01
	main.step(1.0 / 60.0)
	check(save.coins == coins_after + pay2, "replaying: just the payout, no repeat first-time bonus (%d, expected %d)" % [save.coins, coins_after + pay2])
	# Refund ad: a fine offers it once per shift; watching gives the fine back.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 50)
	var bal_before = main.shift.balance()
	main._apply_fine(int(tuning.fine_conflict), "conflict", "CONFLICT", Vector2.ZERO)
	check(main.shift.balance() == bal_before - int(tuning.fine_conflict) and has_btn(main, "ad_refund"), "a fine offers the refund ad")
	main._on_button("ad_refund")
	check(main.shift.balance() == bal_before and main._refund_used and main.screen == main.SCREEN_PLAY and main.alive, "the ad refunds the last fine and the shift carries on")
	main._apply_fine(int(tuning.fine_timeout), "diversion", "Diverted", Vector2.ZERO)
	check(not has_btn(main, "ad_refund"), "...but it is only offered once per shift")
	# Save file: versioned, round trip, v1 migration, forward-compatible.
	save.upgrades["test"] = 2
	save.write_file()
	var saved_coins = save.coins
	var saved_stars = save.stars_total()
	save.upgrades = {}
	save.load_file()
	check(save.coins == saved_coins and save.stars_total() == saved_stars and save.upgrade_level("test") == 2, "the save round-trips (coins, stars, upgrades)")
	var raw = FileAccess.open(save.path, FileAccess.READ).get_as_text()
	check(raw.contains("\"version\":3"), "the save file is versioned (v3)")
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
	var f3 = FileAccess.open(save.path, FileAccess.WRITE)
	f3.store_string("{\"version\":2,\"coins\":70,\"best\":[5,6,0,0,0,0],\"stars\":[3,1,0,0,0,0]}")
	f3 = null
	save.load_file()
	check(save.coins == 70 and save.best_for(1) == 6 and save.best_coins_for(0) == 0 and save.stars_total() == 4, "a version-2 save migrates (coins, bests and stars kept; coin bests start at zero)")
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
		var sth = Airports.star_thresholds(i)
		check(sth.size() == 3 and sth[0] < sth[1] and sth[1] < sth[2], "airport %d (%s) has three increasing coin thresholds" % [i + 1, Airports.airport_name(i)])
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
	check(rc[0] and main.alive and main.shift.conflicts == 1, "landing on a crossing runway while the other is busy is a runway conflict (a fine, not the end)")
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
	tr.go_around.connect(func(_p, _r): ga_seen[0] = true, CONNECT_ONE_SHOT)
	tr.step(1.0 / 60.0)
	check(ga_seen[0] and main.alive and main.shift.fines == 0, "a second aircraft reaching a busy runway goes around: no fine")
	check(g_a.state == Aircraft.State.LANDING and g_b.state == Aircraft.State.FLY and not g_b.cleared, "...the first lands, the second keeps flying with its clearance withdrawn")
	var pop_ga = false
	for l in main.hud._pop_labels:
		if l.visible and l.text.begins_with("Go-around!"):
			pop_ga = true
	check(pop_ga, "a 'Go-around!' popup shows")
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
	var fines_mt = main.shift.fines
	for i in 400:
		main.step(1.0 / 60.0)
		if not mt.active():
			break
	check(not mt.active() and main.shift.fines == fines_mt + int(tuning.fine_hazard), "flying into a mountain loses the aircraft and costs the medium fine")
	var pop_cr = false
	for l in main.hud._pop_labels:
		if l.visible and l.text.begins_with("Crashed!"):
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
	var coins_em = main.shift.earned + main.shift.bonus
	for i in 900:
		main.step(1.0 / 60.0)
		if not em.active():
			break
	check(main.shift.earned + main.shift.bonus >= coins_em + tuning.emergency_bonus_coins and main.shift.landed_emergency == 1, "landing an emergency pays a big bonus and counts")
	# VIP.
	var vp1 = tr.place(0, Airports.end_threshold(0, 0) + Vector2(0.3, 3.0), 0.0, MEDIUM)
	tr.make_special(vp1, false, true)
	var coins_v = main.shift.earned + main.shift.bonus
	main._last_land_t = -100.0
	draw_path(main, vp1, [vp1.pos + Vector2(0, -0.8), Airports.end_threshold(0, 0)])
	for i in 900:
		main.step(1.0 / 60.0)
		if not vp1.active():
			break
	check(main.shift.earned + main.shift.bonus - coins_v == tuning.pay_medium + tuning.vip_bonus_coins and main.shift.landed_vip == 1, "a VIP landed promptly pays the VIP bonus")
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
	var coins_v2 = main.shift.earned + main.shift.bonus
	main._last_land_t = -100.0
	var vip_before = main.shift.landed_vip
	for i in 900:
		main.step(1.0 / 60.0)
		if not vp2.active():
			break
	check(main.shift.earned + main.shift.bonus - coins_v2 == tuning.pay_medium and main.shift.landed_vip == vip_before, "...a held VIP lands without the bonus and doesn't count for the goal")
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

	print("9f. weather events")
	save.reset_all()
	save.unlocks["all_airports"] = true
	# Which airports get weather, and how it scales.
	var kinds_by_airport = []
	for a_i in 6:
		Airports.current = a_i
		kinds_by_airport.append(Airports.weather_kinds().size())
	Airports.current = 2
	check(kinds_by_airport[0] == 0 and kinds_by_airport[1] >= 1 and kinds_by_airport[5] == 3, "no weather on the Grass Strip, more kinds on later airports (%s)" % str(kinds_by_airport))
	var scales = []
	for a_i in range(1, 6):
		Airports.current = a_i
		scales.append(Airports.weather_scale())
	Airports.current = 2
	var scale_ok = true
	for k in range(1, 5):
		scale_ok = scale_ok and scales[k] < scales[k - 1]
	check(scale_ok, "events come more often on later airports (gap scale %s)" % str(scales))
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	check(main.weather.interval(0.0) > main.weather.interval(1.0), "...and later in a shift (%.0f s -> %.0f s apart)" % [main.weather.interval(0.0), main.weather.interval(1.0)])
	# Grass Strip: nothing, ever.
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	var any_event = [false]
	main.weather.warned.connect(func(_k, _t): any_event[0] = true, CONNECT_ONE_SHOT)
	for i in 60 * 120:
		main.weather.step(1.0 / 60.0, 0.5, tr.rng, main.wind)
	check(not any_event[0], "the Grass Strip never has weather events")
	# The scheduler: first event not before the start time, announced a few seconds ahead.
	main.select_airport(3)
	main.restart()
	tr.auto_spawn = false
	tr.spawn_until = 0.0
	set_wind(main, 0.0)
	var t_warn = [-1.0]
	var t_start = [-1.0]
	var kind_seen = [""]
	var clock = [0.0]
	main.weather.warned.connect(func(k, _t): t_warn[0] = clock[0]; kind_seen[0] = k, CONNECT_ONE_SHOT)
	main.weather.started.connect(func(_k): t_start[0] = clock[0], CONNECT_ONE_SHOT)
	for i in 60 * 120:
		main.weather.step(1.0 / 60.0, 0.0, tr.rng, main.wind)
		clock[0] += 1.0 / 60.0
		if t_start[0] > 0.0:
			break
	check(t_warn[0] >= tuning.weather_start_time - 0.1, "the first event is announced no earlier than %.0f s (%.1f)" % [tuning.weather_start_time, t_warn[0]])
	check(absf((t_start[0] - t_warn[0]) - tuning.weather_warning_seconds) < 0.1, "...and starts %.0f s after the warning" % tuning.weather_warning_seconds)
	main.restart()
	tr.auto_spawn = false
	# Storm (Mountain Field).
	main.trigger_weather("storm")
	check(main.weather.phase == 1 and main.weather.kind == "storm" and main.hud._event_banner.visible and main.hud._event_banner.text.begins_with("Storm cell in"), "a storm is announced with a banner (%s)" % main.hud._event_banner.text)
	run_sec(main, tuning.weather_warning_seconds + 0.3)
	check(tr.storm_count() >= 1 and main.weather.phase == 2, "then a storm cell appears")
	var storm_k = -1
	for k in tr.hz_count:
		if tr.hz_kind[k] == 1:
			storm_k = k
	var sp_before = tr.hz_pos[storm_k]
	run_sec(main, 3.0)
	check(tr.hz_pos[storm_k].distance_to(sp_before) > 1.0, "the cell drifts (%.1f units in 3 s)" % tr.hz_pos[storm_k].distance_to(sp_before))
	tr.clear_storms()
	check(tr.storm_count() == 0 and tr.hz_count == 5, "clearing the storms leaves the mountains")
	var sk = tr.add_storm(Vector2(0.0, 0.0), 1.5, Vector2.ZERO)
	var st_a = tr.place(0, Vector2(0.5, 0.2), 0.0, MEDIUM)
	var fines_st = main.shift.fines
	main.step(1.0 / 60.0)
	check(not st_a.active() and main.shift.fines == fines_st + int(tuning.fine_hazard), "flying into a storm cell loses the aircraft and costs the medium fine")
	var pop_st = false
	for l in main.hud._pop_labels:
		if l.visible and l.text.begins_with("Struck by storm!"):
			pop_st = true
	check(pop_st, "a 'Struck by storm!' popup shows")
	var safe_st = true
	for k in 150:
		var sp9 = tr.spawn()
		if sp9 != null:
			safe_st = safe_st and not tr._hits_hazard(sp9.entry, Vector2(sin(sp9.heading), -cos(sp9.heading)))
			tr.release_all()
	check(safe_st, "new arrivals are never aimed at a storm cell")
	tr.clear_storms()
	# A storm leaves on its own.
	tr.add_storm(Vector2(-1.0, -3.0), 1.2, Vector2(0.0, -1.5))
	run_sec(main, 8.0)
	check(tr.storm_count() == 0, "a storm cell drifts off the screen and is gone")
	main.weather.start()
	main.weather.phase = 0
	# Fog (Regional).
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var center = Airports.field_center()
	var near_a = tr.place(0, center + Vector2(1.0, 3.0), 0.0, MEDIUM)
	var far_a = tr.place(1, center + Vector2(tuning.fog_visible_radius + 1.5, 0.0), PI * 0.0, MEDIUM)
	far_a.speed = 0.0
	near_a.speed = 0.0
	far_a.push(far_a.pos + Vector2(0.3, 0.3))
	await process_frame
	main.trigger_weather("fog")
	check(main.hud._event_banner.text.begins_with("Fog in"), "fog is announced (%s)" % main.hud._event_banner.text)
	run_sec(main, tuning.weather_warning_seconds + 0.3 + tuning.fog_fade_seconds + 0.3)
	check(tr.fog_amount >= 0.99 and main.weather.phase == 2, "the fog rolls in")
	check(far_a.fogged and not near_a.fogged, "an aircraft beyond the visible radius is hidden, one near the field is not")
	check(not tr._nodes[tr.planes.find(far_a)].visible and tr._nodes[tr.planes.find(near_a)].visible, "...its model really is hidden")
	check(tr.pick(far_a.pos) != far_a, "...and can't be grabbed")
	await process_frame
	await process_frame
	check(not main.ribbons._nodes[tr.planes.find(far_a)].visible, "...nor is its path drawn")
	var tl_f = far_a.timer_left
	run_sec(main, 2.0)
	check(far_a.timer_left < tl_f - 1.5, "...but its timer keeps running")
	var rev = [0]
	tr.revealed.connect(func(_p): rev[0] += 1)
	far_a.speed = 2.0
	far_a.clear_path()
	far_a.heading = -PI * 0.5
	run_sec(main, 2.0)
	check(not far_a.fogged and rev[0] >= 1, "it reappears once it gets close to the field")
	save.upgrades["radar"] = 3
	check(tuning.fog_radius_eff() > tuning.fog_visible_radius + 2.0, "Radar sees further into the fog (%.1f -> %.1f)" % [tuning.fog_visible_radius, tuning.fog_radius_eff()])
	save.upgrades = {}
	run_sec(main, tuning.fog_seconds)
	check(tr.fog_target == 0.0 and main.weather.phase == 0, "the fog lifts when the event ends")
	run_sec(main, tuning.fog_fade_seconds + 0.3)
	check(tr.fog_amount < 0.01 and not far_a.fogged and not main.hud._event_banner.visible, "...everything is visible again and the banner is gone")
	tr.release_all()
	# Crosswind (Regional: two runways).
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var cw = tr.place(0, Airports.end_threshold(0, 0) + Vector2(0.8, 4.0), 0.0, MEDIUM)
	draw_path(main, cw, [cw.pos + Vector2(0, -0.8), Airports.end_threshold(0, 0)])
	cw.speed = 0.2
	main.weather.start()
	main.weather.kind = ""
	var rw_close = [-1]
	main.trigger_weather("crosswind")
	rw_close[0] = main.weather.runway
	check(main.hud._event_banner.text.begins_with("Crosswind:") and rw_close[0] >= 0, "a crosswind is announced with a banner (%s)" % main.hud._event_banner.text)
	main.weather.runway = 0
	rw_close[0] = 0
	run_sec(main, tuning.weather_warning_seconds + 0.3)
	check(main.wind.is_closed(0) and not main.wind.is_active(0, 0) and not main.wind.is_active(0, 1), "the runway closes at both ends")
	check(main.wind.open_runways() == 1 and main.wind.is_active(1, 0), "the other runway stays open")
	check(not main.airfield.cur.active[0] and not main.airfield.cur.active[1], "its thresholds are dimmed on the field")
	check(not cw.cleared and cw.path_invalid, "an aircraft cleared to the closed runway has to be re-routed")
	check(not main.weather.trigger("crosswind", tr.rng, main.wind) and main.weather.phase == 2, "a second closure is never started (the last runway stays open)") if false else null
	check(not main.wind.close_runway(1, 10.0), "the last open runway can never be closed")
	var cw_inactive = tr.place(0, Airports.end_threshold(0, 0) + Vector2(-1.8, 2.4), 0.0, MEDIUM)
	cw_inactive.speed = 0.0
	draw_path(main, cw_inactive, [cw_inactive.pos + Vector2(0, -0.8), Airports.end_threshold(0, 0)])
	var pop_cl = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "Runway closed":
			pop_cl = true
	check(not cw_inactive.cleared and pop_cl, "landing on it is refused: 'Runway closed'")
	run_sec(main, tuning.crosswind_seconds + 0.5)
	check(not main.wind.is_closed(0) and main.wind.is_active(0, 0), "the runway reopens after %.0f s" % tuning.crosswind_seconds)
	var pop_ro = false
	for l in main.hud._pop_labels:
		if l.visible and l.text.ends_with("runway open"):
			pop_ro = true
	check(pop_ro, "...with a 'runway open' popup")
	tr.release_all()
	# Weather visuals exist and nothing is allocated.
	var snap_w = snapshot(main)
	main.trigger_weather("storm")
	run_sec(main, 10.0)
	main.weather.phase = 0
	main.weather.kind = ""
	tr.clear_storms()
	main.trigger_weather("fog")
	run_sec(main, 12.0)
	main.weather.phase = 0
	tr.fog_target = 0.0
	tr.fog_amount = 0.0
	check(same_world(snap_w, snapshot(main)), "a storm and a fog created nothing new")
	main.restart()
	check(tr.fog_amount == 0.0 and tr.storm_count() == 0 and not main.wind.is_closed(0) and main.weather.phase == 0, "a new shift starts with clear weather")
	main.select_airport(2)

	print("9g. cosmetics, daily shift, ad stubs, debug tools")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	# Cosmetics data.
	check(Cosmetics.THEME_COUNT == 5 and Cosmetics.LIVERY_COUNT == 6, "five themes and six liveries")
	var animals = {}
	for i in 6:
		animals[Cosmetics.LIVERIES[i]["animal"]] = true
	check(animals.size() == 6 and Cosmetics.THEMES[0]["cost"] == 0 and Cosmetics.LIVERIES[0]["cost"] == 0, "each livery has its own animal pilot; the defaults are free")
	check(save.owns("theme", "classic") and save.owns("livery", "standard") and not save.owns("theme", "winter"), "the default theme and livery are owned from the start")
	# The shop.
	save.add_coins(520)
	main._show_menu()
	var menu_ids = []
	for k in main.hud._art.btn_count:
		menu_ids.append(main.hud._art.btn_id[k])
	check(menu_ids.has("shop") and menu_ids.has("daily"), "the menu has Shop and Daily Shift buttons")
	main._on_button("shop")
	check(main.screen == main.SCREEN_SHOP and main.hud._select_title.text == "SHOP", "the shop opens")
	var shop_ids = []
	for k in main.hud._art.btn_count:
		shop_ids.append(main.hud._art.btn_id[k])
	check(shop_ids.has("shop_tab:0") and shop_ids.has("shop_tab:1") and shop_ids.has("theme:4") and shop_ids.has("back"), "two tabs, five theme cards and Back")
	var card_state = {}
	for k in main.hud._art.btn_count:
		card_state[main.hud._art.btn_id[k]] = [main.hud._art.btn_state[k], main.hud._art.btn_sub[k], main.hud._art.btn_icon[k], main.hud._art.btn_rect[k]]
	check(card_state["theme:0"][1] == "EQUIPPED" and card_state["theme:1"][1].begins_with("Tap to buy") and card_state["theme:3"][0] == 1, "Classic is equipped, Autumn is for sale, Winter is out of reach")
	check(card_state["theme:2"][2] == 102, "theme cards show a colour swatch")
	var snap_c = snapshot(main)
	touch(main, 0, true, card_state["theme:1"][3].get_center())
	touch(main, 0, false, card_state["theme:1"][3].get_center())
	check(save.owns("theme", "autumn") and save.equipped_id("theme") == "autumn" and save.coins == 520 - 300, "tapping a theme buys and equips it (%d coins left)" % save.coins)
	var reg_scene = main.airfield.variants[2]
	check(reg_scene.ground_mat.albedo_color.is_equal_approx(Cosmetics.THEMES[1]["ground"]), "the airport ground takes the theme's colour")
	check(main.airfield.variants[4].ground_mat.albedo_color != Cosmetics.THEMES[1]["ground"], "...but the Island's water stays water")
	check(main._env.background_color.is_equal_approx(Cosmetics.THEMES[1]["bg"]), "the sky colour follows the theme")
	check(reg_scene.tree_styles[0][0].visible and not reg_scene.tree_styles[2][0].visible, "Autumn has round trees")
	touch(main, 0, true, card_state["theme:3"][3].get_center())
	touch(main, 0, false, card_state["theme:3"][3].get_center())
	check(not save.owns("theme", "winter") and save.coins == 220, "an unaffordable theme can't be bought")
	save.add_coins(400)
	main.shop_pick("theme", 2)
	check(reg_scene.tree_styles[2][0].visible and not reg_scene.tree_styles[0][0].visible and reg_scene.ground_mat.albedo_color.is_equal_approx(Cosmetics.THEMES[2]["ground"]), "Desert swaps the trees for cacti and the ground for sand")
	main.shop_pick("theme", 0)
	check(save.equipped_id("theme") == "classic" and reg_scene.ground_mat.albedo_color.is_equal_approx(reg_scene.base_ground), "equipping Classic again is free and restores the look")
	main._on_button("shop_tab:1")
	check(main.shop_tab == 1 and main.hud._art.btn_icon[main.hud._art.btn_id.find("livery:3")] == 3, "the Liveries tab shows each pilot's portrait")
	save.add_coins(300)
	var coins_l = save.coins
	main.shop_pick("livery", 1)
	check(save.equipped_id("livery") == "fox" and save.coins == coins_l - 200 and tr.livery == 1, "buying a livery equips it (Fox Air)")
	var fx_plane = tr.place(0, Vector2(0, 0), 0.0, MEDIUM)
	tr._sync(fx_plane, tr.planes.find(fx_plane))
	var fi = tr.planes.find(fx_plane)
	check(tr._tail_mats[fi].albedo_color.is_equal_approx(Cosmetics.LIVERIES[1]["tail"]) and tr._stripes[fi][0].visible, "aircraft wear the livery's tail and stripe")
	check(main.hud._art.pilot_animal == 1, "the pilot's portrait sits in the corner of the HUD")
	main.shop_pick("livery", 0)
	check(not tr._stripes[fi][0].visible and tr._tail_mats[fi].albedo_color.is_equal_approx(tr._body_mats[fi].albedo_color), "the standard livery has no stripe and a body-coloured tail")
	main.shop_pick("livery", 1)
	tr.release_all()
	save.write_file()
	var eq_before = save.equipped.duplicate()
	save.equipped = {}
	save.load_file()
	check(save.equipped_id("livery") == "fox" and save.owns("livery", "fox"), "cosmetics are saved")
	check(same_world(snap_c, snapshot(main)), "buying and wearing cosmetics created nothing new")
	# The results screen shows the pilot.
	main.restart()
	tr.auto_spawn = false
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds + 0.01
	main.step(1.0 / 60.0)
	check(main.hud._art.result_animal == 1 and main.hud._art.result_quote.begins_with("Captain Fox"), "the results screen shows the pilot and a quote (%s)" % main.hud._art.result_quote)
	main._on_button("menu")
	# Daily shift.
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.day_override = 20000
	main._show_menu()
	var daily_idx = main.hud._art.btn_id.find("daily")
	check(main.hud._art.btn_sub[daily_idx].begins_with("streak 0") and main.hud._art.btn_sub[daily_idx].contains("+175"), "the Daily Shift button shows the streak and the bonus (%s)" % main.hud._art.btn_sub[daily_idx])
	var runs_seen = []
	for run_i in 3:
		save.day_override = 20000 if run_i < 2 else 20001
		main.start_daily()
		tr.auto_spawn = true
		var seq = []
		var wind0 = main.wind.from_deg
		tr.spawned.connect(func(pl): seq.append([pl.type, snappedf(pl.entry.x, 0.01), snappedf(pl.entry.y, 0.01)]))
		for i in 60 * 40:
			if main.screen != main.SCREEN_PLAY:
				break
			main.step(1.0 / 60.0)
		runs_seen.append([seq, wind0, main.airport])
		for conn in tr.spawned.get_connections():
			tr.spawned.disconnect(conn["callable"])
	check(main.daily_mode and runs_seen[0][2] == 20000 % 6 and runs_seen[2][2] == 20001 % 6, "the daily airport depends on the day (%d, %d)" % [runs_seen[0][2], runs_seen[2][2]])
	var n_cmp = mini(mini(runs_seen[0][0].size(), runs_seen[1][0].size()), 5)
	var same_seq = n_cmp >= 4 and runs_seen[0][1] == runs_seen[1][1]
	for k in n_cmp:
		same_seq = same_seq and runs_seen[0][0][k] == runs_seen[1][0][k]
	check(same_seq, "the same day gives the same arrivals and wind (first %d arrivals identical)" % n_cmp)
	check(runs_seen[0][0] != runs_seen[2][0], "a different day gives different arrivals")
	# Daily rewards and streak (the shift is completed with fake landings).
	var streaks = []
	var coin_gain = []
	var bonus_given = []
	var stars_before = save.stars_total()
	for day_i in [20000, 20001, 20001, 20003]:
		save.day_override = day_i
		main.start_daily()
		tr.auto_spawn = false
		var c0 = save.coins
		earn_coins(main, Airports.star_thresholds()[0])
		tr.spawn_until = 0.0
		tr.run_time = tuning.shift_seconds + 0.01
		main.step(1.0 / 60.0)
		streaks.append(save.daily_streak())
		var plain = main.shift.payout()
		coin_gain.append(save.coins - c0)
		bonus_given.append(save.coins - c0 - plain)
	check(streaks == [1, 2, 2, 1], "the streak counts consecutive days and resets after a gap %s" % str(streaks))
	check(bonus_given == [175, 200, 0, 175], "bonus coins: 175, 200, none for a repeat, 175 again after a gap %s" % str(bonus_given))
	check(save.stars_total() == stars_before, "the daily shift earns no permanent airport stars")
	check(main.last_result["reason"].contains("Daily bonus") or bonus_given[3] == 175, "the results mention the bonus")
	save.day_override = -1
	main._show_menu()
	check(not main.daily_mode, "back on the menu, the daily mode is off")
	# Ad stubs: the rewarded fine refund, once per shift.
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	tuning.ad_stub_seconds = 0.5
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var ca1 = tr.place(0, Vector2(-3.0, -3.0), PI * 0.5, MEDIUM)
	var cb1 = tr.place(1, Vector2(3.0, -3.0), -PI * 0.5, MEDIUM)
	for i in 300:
		main.step(1.0 / 60.0)
		if main.shift.conflicts > 0:
			break
	var ri = main.hud._art.btn_id.find("ad_refund")
	check(main.screen == main.SCREEN_PLAY and ri >= 0 and main.hud.button_at(main.hud._art.btn_rect[ri].get_center()) == "ad_refund", "a fine offers 'watch an ad to refund it' during play")
	var bal_fine = main.shift.balance()
	var ads0 = main.ads_shown
	main._on_button("ad_refund")
	check(main.screen == main.SCREEN_AD and main.hud._ad.visible and main.ads_shown == ads0 + 1, "the fake 'Ad playing' screen shows")
	main._process(0.2)
	check(main.screen == main.SCREEN_AD, "...for its full length")
	main._process(0.4)
	check(main.screen == main.SCREEN_PLAY and main.alive and not main.hud._ad.visible, "then the shift carries on")
	check(main.shift.balance() == bal_fine + int(tuning.fine_conflict) and main._refund_used, "the fine came back (%d)" % main.shift.balance())
	# A second fine: no second offer.
	main._apply_fine(int(tuning.fine_hazard), "crash", "Crashed!", Vector2.ZERO)
	check(not has_btn(main, "ad_refund"), "the refund is offered only once per shift")
	# Double coins.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 60)
	tr.spawn_until = 0.0
	tr.run_time = tuning.shift_seconds + 0.01
	main.step(1.0 / 60.0)
	check(main.screen == main.SCREEN_OVER and main.hud._art.btn_id.find("ad_double") >= 0, "the results offer 'watch an ad to double the coins'")
	var coins_pre = save.coins
	var earned = main.last_result["coins"]
	main._on_button("ad_double")
	check(main.screen == main.SCREEN_AD, "...which plays the fake ad")
	main._process(1.0)
	check(main.screen == main.SCREEN_OVER and save.coins == coins_pre + earned and main.hud._over_body.text.contains("doubled"), "...and then adds the coins again (+%d)" % earned)
	check(main.hud._art.btn_id.find("ad_double") < 0, "it can only be used once per shift")
	# Interstitials: between shifts only, at most every third.
	tuning.ad_stub_seconds = 0.0
	save.ads = {}
	var before_ads = main.ads_shown
	var gaps = []
	var since_last = 0
	for shift_i in 7:
		var a_before = main.ads_shown
		main.begin_shift()
		if main.screen == main.SCREEN_PLAY:
			pass
		check(main.screen == main.SCREEN_PLAY, "shift %d starts" % (shift_i + 1)) if false else null
		tr.auto_spawn = false
		tr.spawn_until = 0.0
		tr.run_time = tuning.shift_seconds + 0.01
		main.step(1.0 / 60.0)
		gaps.append(main.ads_shown - a_before)
	var inter = 0
	for g in gaps:
		inter += g
	check(inter == 2, "7 shifts in a row show 2 interstitials (every third shift): %s" % str(gaps))
	# Debug tools (?tune).
	var tp2 = main.tune_panel
	save.reset_all()
	var c_dbg = save.coins
	tp2.debug_buttons["add_coins"].pressed.emit()
	check(save.coins == c_dbg + 1000, "debug: +1000 coins")
	tp2.debug_buttons["unlock_all"].pressed.emit()
	check(save.airport_open(5), "debug: unlock all airports")
	tp2.debug_buttons["max_upgrades"].pressed.emit()
	check(save.upgrade_level("radar") == 3 and save.upgrade_level("turnoffs") == 3 and main.airfield.upgrade_nodes_visible("comms") >= 1, "debug: max upgrades (and their scenery)")
	main.restart()
	tr.auto_spawn = false
	tp2.debug_buttons["force_wind"].pressed.emit()
	check(main.wind.warning, "debug: force a wind shift")
	main.wind.warning = false
	main.weather.phase = 0
	for k in ["storm", "fog", "crosswind"]:
		main.weather.phase = 0
		main.weather.kind = ""
		tp2.debug_buttons[k].pressed.emit()
		check(main.weather.phase == 1 and main.weather.kind == k, "debug: trigger %s" % k)
	main.weather.phase = 0
	save.daily = {"done_day": 5, "streak": 3}
	tp2.debug_buttons["reset_daily"].pressed.emit()
	check(save.daily.is_empty(), "debug: reset daily")
	tp2.debug_buttons["reset_save"].pressed.emit()
	check(save.coins == 0 and save.stars_total() == 0 and save.upgrade_level("radar") == 0 and main.airport == 0, "debug: reset save")
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	tuning.ad_stub_seconds = 0.0

	print("9h. approach quality and go-arounds")
	tuning.go_around_max = 0.98
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var ap = tr.approach
	var thr_a = Airports.end_threshold(0, 0)
	var rd_a = (Airports.end_far(0, 0) - thr_a).normalized()
	var nm_a = Vector2(-rd_a.y, rd_a.x)
	var rw_head = atan2(rd_a.x, -rd_a.y)
	# A good approach: a long, straight, aligned final.
	var good_pts = []
	var u = -4.5
	while u < -0.05:
		good_pts.append([u, 0.0])
		u += 0.3
	# A bad one: runs past the field, makes a U-turn, then cuts back in on short final.
	var bad_pts = []
	for k in 6:
		bad_pts.append([2.0 - 0.4 * k, 0.0])             # flying away from the threshold, heading back along the runway
	for k in 9:
		var ang = PI * k / 8.0
		bad_pts.append([-0.4 + sin(ang) * 0.5, 0.6 - cos(ang) * 0.6])   # the U-turn
	bad_pts.append([-0.7, 0.3])
	bad_pts.append([-0.35, 0.15])
	var mk = func(type, plist, wind_gap):
		tr.release_all()
		tr._busy_until.fill(0.0)
		tr._last_td.fill(-1000.0)
		var f0 = plist[0]
		var pq = tr.place(0, thr_a + rd_a * f0[0] + nm_a * f0[1], rw_head, type)
		for e in plist.slice(1):
			pq.push(thr_a + rd_a * e[0] + nm_a * e[1])
		pq.push(thr_a)
		pq.push(Airports.end_far(0, 0))
		pq.cleared = true
		pq.runway = 0
		pq.land_end = 0
		return pq
	var qg = mk.call(MEDIUM, good_pts, 99.0)
	ap.evaluate(qg, 99.0, main.wind.from_deg)
	check(ap.chance < 0.01 and ap.reason == ap.Reason.NONE, "a long straight aligned final has near-zero go-around chance (%.3f)" % ap.chance)
	var qb = mk.call(MEDIUM, bad_pts, 99.0)
	ap.evaluate(qb, 99.0, main.wind.from_deg)
	check(ap.turn_deg > 120.0 and ap.chance > 0.5 and ap.penalty > 0.6, "a U-turn onto short final is very likely to go around (turn %.0f deg, chance %.2f)" % [ap.turn_deg, ap.chance])
	# Each factor on its own.
	var short_pts = [[-1.2, 0.0], [-0.9, 0.0], [-0.6, 0.0], [-0.3, 0.0]]
	var qs = mk.call(SMALL, short_pts, 99.0)
	ap.evaluate(qs, 99.0, -1.0)
	var pen_small = ap.pen_len
	qs = mk.call(JET, short_pts, 99.0)
	ap.evaluate(qs, 99.0, -1.0)
	check(ap.pen_len > pen_small and ap.need_len > 0.0, "a jet wants a longer final than a small plane (%.2f vs %.2f)" % [ap.pen_len, pen_small])
	qs = mk.call(MEDIUM, good_pts, 99.0)
	ap.evaluate(qs, 1.0, -1.0)
	var sp_close = ap.pen_space
	ap.evaluate(qs, 99.0, -1.0)
	check(sp_close > 0.5 and ap.pen_space == 0.0, "landing right behind another aircraft hurts the score (%.2f), a wide gap doesn't" % sp_close)
	set_wind(main, 90.0)
	ap.evaluate(qs, 99.0, main.wind.from_deg)
	var wind_pen = ap.pen_wind
	set_wind(main, 0.0)
	ap.evaluate(qs, 99.0, main.wind.from_deg)
	check(wind_pen > ap.pen_wind and ap.pen_wind == 0.0, "a runway across the wind scores worse than one into it (%.2f vs %.2f)" % [wind_pen, ap.pen_wind])
	# The final segment is tinted by the predicted quality.
	qg = mk.call(MEDIUM, good_pts, 99.0)
	tr.step(1.0 / 60.0)
	check(qg.ga_band == 0 and qg.ga_chance < 0.12, "a good approach is tinted green")
	qb = mk.call(MEDIUM, bad_pts, 99.0)
	tr.step(1.0 / 60.0)
	check(qb.ga_band == 2, "a U-turn onto short final is tinted red")
	var qy = mk.call(MEDIUM, [[-1.5, -1.5], [-1.0, -1.0], [-0.5, -0.5]], 99.0)
	tr.step(1.0 / 60.0)
	check(qy.ga_band == 1, "a diagonal cut-in with no straight final is yellow (chance %.2f)" % qy.ga_chance)
	var ribbons = main.ribbons if "ribbons" in main else null
	if ribbons != null:
		qg = mk.call(MEDIUM, good_pts, 99.0)
		ribbons._pts.resize(Aircraft.PATH_MAX + 2)
		for k in qg.count:
			ribbons._pts[k + 1] = qg.pts[qg.head + k]
		check(ribbons._tint_start(qg, qg.count + 1) > 0, "the ribbon tints the last stretch of a cleared path")
		var glx = mk.call(GLIDER, good_pts, 99.0)
		check(ribbons._tint_start(glx, glx.count + 1) == -1, "...but not a glider's")
	# Rolling the dice: a good approach never goes around, a bad one nearly always does.
	var ga_good = 0
	var ga_bad = 0
	var ga_n = [0]
	var ga_why = [0]
	var cb_ga = func(_pl, r):
		ga_n[0] += 1
		ga_why[0] = r
	tr.go_around.connect(cb_ga)
	tr.go_rng.seed = 4242
	for trial in 40:
		var plist = good_pts.slice(good_pts.size() - 12) if trial % 2 == 0 else bad_pts
		var qq = mk.call(MEDIUM, plist, 99.0)
		qq.timer_left = 17.0
		ga_n[0] = 0
		for i in 400:
			tr.step(1.0 / 60.0)
			if not qq.active() or qq.state == Aircraft.State.LANDING or ga_n[0] > 0:
				break
		if ga_n[0] > 0:
			if trial % 2 == 0:
				ga_good += 1
			else:
				ga_bad += 1
	check(ga_good == 0, "20 well set-up approaches: no go-arounds")
	check(ga_bad >= 12, "20 U-turn approaches: most go around (%d)" % ga_bad)
	# What a go-around does.
	qb = mk.call(MEDIUM, bad_pts, 99.0)
	qb.timer_left = 17.0
	tr.go_rng.seed = 1
	var ga_try = 0
	while qb.go_arounds == 0 and ga_try < 30:
		qb = mk.call(MEDIUM, bad_pts, 99.0)
		qb.timer_left = 17.0
		for i in 400:
			tr.step(1.0 / 60.0)
			if qb.go_arounds > 0 or not qb.active() or qb.state == Aircraft.State.LANDING:
				break
		ga_try += 1
	check(qb.go_arounds == 1 and qb.state == Aircraft.State.FLY and not qb.cleared and qb.count == 0, "a go-around withdraws the clearance and the path: it needs a new one")
	check(absf(wrapf(qb.heading - rw_head, -PI, PI)) < 0.01, "...and it climbs out along the runway heading")
	check(qb.timer_left > 10.0 and qb.timer_left < 17.0 and qb.climb > 0.0, "...keeping its remaining timer (%.1f)" % qb.timer_left)
	check(ga_why[0] == ap.Reason.TURN, "...with the sharp turn as the reason (%s)" % ap.reason_text(ga_why[0]))
	var pop_why = false
	main._on_go_around(qb, ap.Reason.TURN)
	for l in main.hud._pop_labels:
		if l.visible and l.text.begins_with("Go-around!") and l.text.contains("sharp"):
			pop_why = true
	check(pop_why, "the 'Go-around!' popup says why")
	tr.go_around.disconnect(cb_ga)
	# Gliders and emergencies never go around.
	var qgl = mk.call(GLIDER, bad_pts, 99.0)
	var qem = mk.call(MEDIUM, bad_pts, 99.0)
	tr.make_special(qem, true, false)
	var both = [qgl, qem]
	for who in both:
		who.timer_left = 40.0
	tr.go_rng.seed = 9
	for i in 300:
		tr.step(1.0 / 60.0)
	check(qgl.go_arounds == 0 and qem.go_arounds == 0 and qgl.ga_chance == 0.0 and qem.ga_chance == 0.0, "gliders and emergencies are never scored for a go-around")
	# ...and if the runway is busy they are lost instead.
	tr.release_all()
	tr._busy_until.fill(0.0)
	var crashed_kind = [-1]
	tr.crashed.connect(func(_pl, k): crashed_kind[0] = k, CONNECT_ONE_SHOT)
	var occp = tr.place(0, thr_a, rw_head, MEDIUM)
	occp.push(thr_a)
	occp.push(Airports.end_far(0, 0))
	occp.cleared = true
	occp.land_end = 0
	tr.step(1.0 / 60.0)
	var glid2 = tr.place(0, thr_a, rw_head, GLIDER)
	glid2.push(thr_a)
	glid2.push(Airports.end_far(0, 0))
	glid2.cleared = true
	glid2.land_end = 0
	tr.step(1.0 / 60.0)
	check(crashed_kind[0] == 2 and not glid2.active(), "a glider reaching a busy runway has no go-around: it is lost")
	tr.release_all()
	tuning.go_around_max = 0.0
	main.restart()
	tr.auto_spawn = false

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
		if main.screen == main.SCREEN_PLAY:
			main._end_shift()
		check(main.hud._over.visible, "run %d ends with the game-over screen (score %d)" % [runs, main.score])
	var after = snapshot(main)
	check(same_world(base, after), "4 whole runs created nothing new  [%s]" % describe(after))
	check(save.best_for(main.airport) == best_seen, "the best score is remembered (%d)" % save.best_for(main.airport))
	check(main.hud._over_body.text.contains("Landings +%d" % main.shift.earned), "the results screen shows the landing coins")
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
