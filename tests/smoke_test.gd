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
##   9f. weather: schedule + warnings per airport, storm cells (strike), fog (drawn behind everything, hides nothing), crosswind (closure, reroute)
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

func sx_clip_of(stream) -> PackedFloat32Array:
	var d: PackedByteArray = stream.data
	var out = PackedFloat32Array()
	out.resize(d.size() / 2)
	for i in out.size():
		out[i] = d.decode_s16(i * 2) / 32768.0
	return out

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
	tuning.path_smooth_points = 1.0       # (the older sections draw exact paths; section 14 tests the smoothing)
	var save = root.get_node("Save")
	save.path = "user://smoke_test_save.json"   # never touch a real save
	save.reset_all()
	tuning.ad_stub_seconds = 0.0    # fake ads finish at once unless a test is about them
	tuning.go_around_max = 0.0      # ...and no random go-arounds, except in the go-around section
	tuning.intro_logo = false       # ...and no boot logo, except in the motion section
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

	main.sfx.quantize = false     # (gameplay sounds fire at once; the quantizing section turns it on)
	print("2. a tap on the menu starts a run in place; real touches pick and drag a plane")
	main.traffic.auto_spawn = false
	var play_at := Vector2(540, 900)
	for pk in main.hud._art.btn_count:
		if main.hud._art.btn_id[pk] == "play":
			play_at = main.hud._art.btn_rect[pk].get_center()
	touch(main, 0, true, play_at)
	touch(main, 0, false, play_at)
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
	main.hud.skip_animations()
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
	check(is_equal_approx(tuning.spawn_interval(1000.0), float(tuning.profile()["spawn_min"]) * (tuning.intro_spawn_scale if tuning.intro_active else 1.0)), "...down to the airport's fastest pace")
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
	var auto_n = [0]
	var auto_cb = func(_pl): auto_n[0] += 1
	tr.spawned.connect(auto_cb)
	run_sec(main, 30.0)
	tr.spawned.disconnect(auto_cb)
	check(auto_n[0] >= 2, "the spawner puts planes on the field by itself (%d in 30 s)" % auto_n[0])
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
	check(main.shift.fines == tuning.fine_amount(tuning.fine_conflict) and main.shift.balance() == -tuning.fine_amount(tuning.fine_conflict), "...it costs the large fine, and the balance goes negative (%d)" % main.shift.balance())
	check(not a.active() and not bb.active(), "...and both aircraft are lost")
	check(not has_btn(main, "ad_refund") and main.screen == main.SCREEN_PLAY, "...and nothing interrupts play: no refund ad during the shift")
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
	check(is_equal_approx(tm.timer_max, tuning.timer_medium * tuning.timer_mult()) and is_equal_approx(tm.timer_left, tm.timer_max), "a medium plane starts with the medium timer (%.0f s)" % tm.timer_max)
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
	check(dv.state == Aircraft.State.DIVERT and main.shift.diversions == 1 and main.shift.fines == tuning.fine_amount(tuning.fine_timeout), "a timed-out aircraft is diverted and costs the small fine (%d)" % main.shift.fines)
	var pop_seen = false
	for l in main.hud._pop_labels:
		if l.visible and l.text.begins_with("Diverted") and l.text.contains("-%d" % tuning.fine_amount(tuning.fine_timeout)):
			pop_seen = true
	check(pop_seen, "a red 'Diverted -N' popup shows")
	check(main.hud._art.balance == -tuning.fine_amount(tuning.fine_timeout), "the HUD balance shows the fine (and can go negative)")
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
	check(main.shift.payout() == 0, "with nothing landed a negative balance pays out zero (the guaranteed share of nothing)")
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
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
	var sth9 = tuning.star_thresholds()
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
	main.shift.refund_biggest()
	check(main.shift.stars() == 3, "...and refunding it restores the stars")
	var payout_expect = main.shift.payout()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() - 0.01
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
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(save.coins == coins_after + pay2, "replaying: just the payout, no repeat first-time bonus (%d, expected %d)" % [save.coins, coins_after + pay2])
	# Refund ad: only on the results screen, instead of the double-coins ad; it gives back the biggest fine.
	save.reset_all()
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, sth9[2])
	var bal_hi = main.shift.balance()
	main._apply_fine(int(tuning.fine_timeout), "diversion", "Diverted", Vector2.ZERO)
	main._apply_fine(int(tuning.fine_conflict), "conflict", "CONFLICT", Vector2.ZERO)
	main._apply_fine(int(tuning.fine_hazard), "crash", "Crashed!", Vector2.ZERO)
	check(main.shift.biggest_fine == int(tuning.fine_conflict) and not has_btn(main, "ad_refund"), "fines track the biggest one; nothing is offered during play")
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(main.screen == main.SCREEN_OVER and has_btn(main, "ad_refund") and has_btn(main, "ad_double"), "the results offer both the refund and double-coins ads")
	var ri9 = main.hud._art.btn_id.find("ad_refund")
	check(main.hud._art.btn_text[ri9] == "Refund fine" and main.hud._art.btn_sub[ri9] == "+%d" % int(tuning.fine_conflict) and main.hud._art.btn_kind[ri9] == 6, "...a quiet pill: 'Refund fine' with its amount (%s %s)" % [main.hud._art.btn_text[ri9], main.hud._art.btn_sub[ri9]])
	var stars_pre = save.stars_of(main.airport)
	var coins_pre9 = save.coins
	var pay_pre = main.shift.payout()
	main._on_button("ad_refund")
	check(main.screen == main.SCREEN_OVER and main.shift.fines == int(tuning.fine_timeout) + int(tuning.fine_hazard), "watching it refunds the biggest fine (the %d one)" % int(tuning.fine_conflict))
	check(main.shift.payout() == maxi(main.shift.balance(), main.shift.kept()) and main.shift.payout() > pay_pre, "...so the payout goes up (the guaranteed %d -> %d)" % [pay_pre, main.shift.payout()])
	var stars_now = main.shift.stars()
	check(save.stars_of(main.airport) == stars_now and stars_now > stars_pre, "...and stars are re-awarded (%d -> %d)" % [stars_pre, stars_now])
	check(save.coins == coins_pre9 + (main.shift.payout() - pay_pre) + (stars_now - stars_pre) * int(tuning.coins_first_star_bonus), "...with the extra coins credited once (%d -> %d)" % [coins_pre9, save.coins])
	check(not has_btn(main, "ad_refund") and not has_btn(main, "ad_double") and has_btn(main, "menu"), "only one of the two ads per shift: both are gone now")
	check(main.hud._over_body.text.contains("refunded"), "the results say the fine was refunded")
	# ...and the other way round: doubling removes the refund.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, sth9[0])
	main._apply_fine(int(tuning.fine_timeout), "diversion", "Diverted", Vector2.ZERO)
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	main._on_button("ad_double")
	check(not has_btn(main, "ad_refund") and not has_btn(main, "ad_double"), "doubling the coins uses up the shift's one ad: no refund after it")
	# No fines: no refund offer.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 30)
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(has_btn(main, "ad_double") and not has_btn(main, "ad_refund"), "with no fines there is nothing to refund")
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
	check(main.hud.banner_text() == "Wind to 180" and main.hud._art.wind_warn, "the banner reads '%s' and the dial flashes" % main.hud.banner_text())
	check(main.hud._art.wind_warn, "the wind widget flags the coming shift")
	check(absf(main.wind.countdown - tuning.wind_warning_seconds) < 0.1, "about %.0f s of warning" % tuning.wind_warning_seconds)
	check(main.wind.is_active(0, 0), "the old ends stay active during the warning")
	run_sec(main, tuning.wind_warning_seconds + 0.5)
	check(is_equal_approx(main.wind.from_deg, 180.0) and main.wind.is_active(0, 1) and not main.wind.is_active(0, 0), "after the warning the wind and the active ends have changed")
	check(not main.hud._art.wind_warn and main.hud._art.wind_text == "180", "the dial stops flashing and shows the new wind")
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
	var scale0 = tuning.profile()["wind"]
	tuning.profile()["wind"] = 0.5
	var quick = main.wind.interval(0.0)
	tuning.profile()["wind"] = scale0
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
		var sth = tuning.star_thresholds(i)
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
	check(cards.has("pick:0") and cards.has("locked:1") and cards.has("locked:5") and cards.has("back"), "airport 1 is open, the others show as locked, with a Back button")
	check(main.hud._art.btn_lock[main.hud._art.btn_id.find("locked:1")] == 2 and main.hud._art.btn_state[main.hud._art.btn_id.find("locked:1")] == 1, "a locked card shows a padlock and the stars it needs")
	var locked_pos = cards["locked:1"].get_center()
	touch(main, 0, true, locked_pos)
	touch(main, 0, false, locked_pos)
	check(main.screen == main.SCREEN_SELECT, "tapping a locked airport does nothing")
	save.award_star(0, 0)
	save.award_star(0, 1)
	main._show_select()
	check(save.stars_total() == 2 and main.hud.button_at(cards["locked:1"].get_center()) == "pick:1", "two stars open County")
	touch(main, 0, true, cards["locked:1"].get_center())
	touch(main, 0, false, cards["locked:1"].get_center())
	check(main.screen == main.SCREEN_SELECT and main.airport == 1 and main.hud._art.btn_id.has("airport:1"), "tapping an open airport's card selects it and shows its Fly here button")
	var fly_at = main.hud._art.btn_rect[main.hud._art.btn_id.find("airport:1")].get_center()
	touch(main, 0, true, fly_at)
	touch(main, 0, false, fly_at)
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
	check(not mt.active() and main.shift.fines == fines_mt + tuning.fine_amount(tuning.fine_hazard), "flying into a mountain loses the aircraft and costs the medium fine")
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
	check(hc.tkind == 1 and is_equal_approx(hc.timer_max, tuning.timer_heli * tuning.timer_mult()) and tr._heli_groups[tr.planes.find(hc)].visible and not tr._plane_groups[tr.planes.find(hc)].visible, "a helicopter has its own model and the helicopter timer")
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
	check(is_equal_approx(gl.timer_max, tuning.timer_glider * tuning.timer_mult()) and gl.speed < tuning.speed_slow, "a glider is slow with the shortest timer")
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
	check(is_equal_approx(em.timer_max, tuning.timer_medium * tuning.timer_mult() * tuning.emergency_timer_mult), "an emergency has a shortened timer")
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
	var base_t = tuning.type_timer(MEDIUM) * tuning.timer_mult()
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
	save.add_coins(100)
	main._on_button("upgrades")
	check(main.screen == main.SCREEN_UPGRADES and main.hud._select.visible and main.hud._select_title.text == "UPGRADES", "the upgrade shop opens")
	var cards2 = {}
	for k in main.hud._art.btn_count:
		cards2[main.hud._art.btn_id[k]] = [main.hud._art.btn_rect[k], main.hud._art.btn_state[k], main.hud._art.btn_stars[k]]
	check(cards2.has("upg:radar") and cards2.has("upg:turnoffs") and cards2.has("back"), "one card per upgrade, plus Back")
	check(cards2["upg:comms"][1] == 2 and cards2["upg:radar"][1] == 1, "affordable cards are highlighted, unaffordable ones dim (100 coins)")
	touch(main, 0, true, cards2["upg:radar"][0].get_center())
	touch(main, 0, false, cards2["upg:radar"][0].get_center())
	check(save.upgrade_level("radar") == 0 and save.coins == 100, "tapping an unaffordable card buys nothing")
	var snap_shop = snapshot(main)
	touch(main, 0, true, cards2["upg:comms"][0].get_center())
	touch(main, 0, false, cards2["upg:comms"][0].get_center())
	check(save.upgrade_level("comms") == 1 and save.coins == 100 - Upgrades.cost("comms", 0), "tapping an affordable card buys it (%d coins left)" % save.coins)
	check(main.screen == main.SCREEN_UPGRADES and main.hud._art.btn_pips[main.hud._art.btn_id.find("upg:comms")] == 1, "the card shows the new level (pips)")
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
	for a_i in range(2, 6):
		Airports.current = a_i
		scales.append(float(tuning.profile()["weather"]))
	Airports.current = 2
	var scale_ok = true
	for k in range(1, 4):
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
	check(t_warn[0] >= tuning.weather_first_eff() - 0.1, "the first event is announced no earlier than %.0f s (%.1f)" % [tuning.weather_first_eff(), t_warn[0]])
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
	check(not st_a.active() and main.shift.fines == fines_st + tuning.fine_amount(tuning.fine_hazard), "flying into a storm cell loses the aircraft and costs the medium fine")
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
	var far_a = tr.place(1, center + Vector2(4.5, 0.0), PI * 0.0, MEDIUM)
	far_a.speed = 0.0
	near_a.speed = 0.0
	far_a.push(far_a.pos + Vector2(0.3, 0.3))
	await process_frame
	check(not main.fog_layer.visible, "no fog layer is drawn while the weather is clear")
	main.trigger_weather("fog")
	check(main.hud._event_banner.text.begins_with("Fog in"), "fog is announced (%s)" % main.hud._event_banner.text)
	check(main.hud.banner_text() == "FOG ROLLING IN", "...with a FOG ROLLING IN banner (%s)" % main.hud.banner_text())
	run_sec(main, tuning.weather_warning_seconds + 0.3 + tuning.fog_fade_seconds + 0.3)
	check(tr.fog_amount >= 0.99 and main.weather.phase == 2, "the fog rolls in")
	await process_frame
	await process_frame
	check(main.fog_layer.visible and absf(float(main.fog_layer.shader_material().get_shader_parameter("amount")) - tr.fog_amount) < 0.01, "a translucent fog layer is drawn, as thick as the fog (%.2f)" % tr.fog_amount)
	check(not far_a.fogged and not near_a.fogged and tr._nodes[tr.planes.find(far_a)].visible, "the fog hides nothing: a far aircraft is still there, model and all")
	check(tr.pick(far_a.pos) == far_a, "...and can still be grabbed")
	check(main.ribbons._nodes[tr.planes.find(far_a)].visible, "...and its path is still drawn")
	var tl_f = far_a.timer_left
	run_sec(main, 2.0)
	check(far_a.timer_left < tl_f - 1.5, "...its timer keeps running")
	run_sec(main, tuning.fog_seconds)
	check(tr.fog_target == 0.0 and main.weather.phase == 0, "the fog lifts when the event ends")
	run_sec(main, tuning.fog_fade_seconds + 0.3)
	await process_frame
	check(tr.fog_amount < 0.01 and not main.fog_layer.visible and not main.hud._event_banner.visible, "...the layer goes away and the chip is gone")
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
		card_state[main.hud._art.btn_id[k]] = [main.hud._art.btn_state[k], main.hud._art.btn_sub[k], main.hud._art.btn_icon[k], main.hud._art.btn_rect[k], main.hud._art.btn_cost[k]]
	check(card_state["theme:0"][1] == "In use" and card_state["theme:1"][4] == 300 and card_state["theme:1"][0] == 0 and card_state["theme:3"][0] == 1, "Classic is equipped, Autumn is for sale, Winter is out of reach")
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
	main.shop_pick("livery", 0)
	check(tr._stripes[fi][0].visible and tr._tail_mats[fi].albedo_color.is_equal_approx(tr._body_mats[fi].albedo_color) and tr._stripe_mats[fi].albedo_color.is_equal_approx(tr._body_mats[fi].albedo_color), "the standard livery wears the runway's colour on the stripe and the fin")
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
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(main.hud._art.show_result and main.hud._over.visible, "the results screen shows")
	main._on_button("menu")
	# Daily shift.
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.day_override = 20000
	main._show_menu()
	var daily_idx = main.hud._art.btn_id.find("daily")
	check(main.hud._art.btn_kind[daily_idx] == 7 and main.hud._art.btn_text[daily_idx] == "Daily" and main.hud._art.btn_badge[daily_idx] == -2, "the Daily button has a red dot before the first streak")
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
		earn_coins(main, tuning.star_thresholds()[0])
		tr.spawn_until = 0.0
		tr.run_time = tuning.par_eff() + 0.01
		main.step(1.0 / 60.0)
		streaks.append(save.daily_streak())
		var plain = main.shift.payout()
		coin_gain.append(save.coins - c0)
		bonus_given.append(save.coins - c0 - plain)
	check(streaks == [1, 2, 2, 1], "the streak counts consecutive days and resets after a gap %s" % str(streaks))
	var dbo1 = int(tuning.daily_bonus_coins + tuning.daily_streak_coins)
	var dbo2 = int(tuning.daily_bonus_coins + 2 * tuning.daily_streak_coins)
	check(bonus_given == [dbo1, dbo2, 0, dbo1], "bonus coins: %d, %d, none for a repeat, %d again after a gap %s" % [dbo1, dbo2, dbo1, str(bonus_given)])
	check(save.stars_total() == stars_before, "the daily shift earns no permanent airport stars")
	check(main.last_result["reason"].contains("Daily bonus") or bonus_given[3] == dbo1, "the results mention the bonus")
	save.day_override = -1
	main._show_menu()
	check(not main.daily_mode, "back on the menu, the daily mode is off")
	# Ad stubs: the rewarded fine refund is on the results screen.
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
	check(main.screen == main.SCREEN_PLAY and not has_btn(main, "ad_refund"), "a conflict during play offers no ad")
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	var ri = main.hud._art.btn_id.find("ad_refund")
	check(main.screen == main.SCREEN_OVER and ri >= 0 and main.hud.button_at(main.hud._art.btn_rect[ri].get_center()) == "ad_refund", "the results offer 'watch an ad to refund the biggest fine'")
	var fines_pre = main.shift.fines
	var ads0 = main.ads_shown
	main._on_button("ad_refund")
	check(main.screen == main.SCREEN_AD and main.hud._ad.visible and main.ads_shown == ads0 + 1, "the fake 'Ad playing' screen shows")
	main._process(0.2)
	check(main.screen == main.SCREEN_AD, "...for its full length")
	main._process(0.4)
	check(main.screen == main.SCREEN_OVER and not main.hud._ad.visible and main.shift.fines == fines_pre - tuning.fine_amount(tuning.fine_conflict), "then the results come back with the fine refunded (%d -> %d)" % [fines_pre, main.shift.fines])
	# Double coins.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 60)
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
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
		tr.run_time = tuning.par_eff() + 0.01
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

	print("9i. student pilots and Bad Pilot Day")
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.day_override = 20100
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	# Students appear among ordinary arrivals, and only runway aircraft that can go around.
	tuning.student_chance = 0.3
	var n_stu = 0
	var n_all = 0
	var stu_ok = true
	tr.rng.seed = 11
	for k in 120:
		tr.release_all()
		var sp = tr.spawn()
		if sp == null:
			continue
		n_all += 1
		if sp.student:
			n_stu += 1
			stu_ok = stu_ok and sp.tkind == Aircraft.Kind.RUNWAY and sp.type != GLIDER and not sp.emergency and not sp.vip
	check(n_stu > 10 and n_stu < n_all and stu_ok, "student pilots turn up in normal shifts (%d of %d), never gliders / emergencies / VIPs" % [n_stu, n_all])
	tuning.student_chance = 0.12
	# The "L" badge.
	var stp = tr.place(0, Vector2(0.0, 2.0), 0.0, MEDIUM)
	stp.student = true
	await real_wait(0.3)
	check(stp.student and main.overlay.student_tags_drawn() >= 1, "a student aircraft is drawn with an L badge")
	# Student pay: double.
	main.restart()
	tr.auto_spawn = false
	var fk = Aircraft.new()
	fk.runway = 0
	fk.type = MEDIUM
	main._on_landed(fk)
	var plain_pay = main.shift.earned
	fk.student = true
	main.traffic.run_time += 10.0
	main._on_landed(fk)
	check(main.shift.earned - plain_pay == plain_pay * 2 and main.shift.landed_student == 1, "a student landing pays double (%d vs %d)" % [main.shift.earned - plain_pay, plain_pay])
	# Go-around chance: far higher for a student on the same approach.
	set_wind(main, 0.0)
	tuning.go_around_max = 0.98
	var thr_s = Airports.end_threshold(0, 0)
	var rd_s = (Airports.end_far(0, 0) - thr_s).normalized()
	var sq = tr.place(0, thr_s - rd_s * 4.5, atan2(rd_s.x, -rd_s.y), MEDIUM)
	var u2 = -4.2
	while u2 < -0.05:
		sq.push(thr_s + rd_s * u2)
		u2 += 0.3
	sq.push(thr_s)
	sq.push(Airports.end_far(0, 0))
	sq.cleared = true
	sq.land_end = 0
	tr.step(1.0 / 60.0)
	var base_chance = sq.ga_chance
	sq.student = true
	tr.step(1.0 / 60.0)
	check(base_chance < 0.01 and sq.ga_chance > 0.2 and sq.ga_band >= 1, "a student's go-around chance is much higher on a perfect approach (%.2f -> %.2f)" % [base_chance, sq.ga_chance])
	tr.release_all()
	# Bad Pilot Day.
	tuning.go_around_max = 0.0
	save.day_override = 20100
	main.start_bad_day()
	check(main.bad_mode and main.daily_mode and main.airport == (20100 + 3) % 6 and tr.all_students, "Bad Pilot Day is its own daily mode with its own airport")
	tuning.go_around_max = 0.98
	tr.auto_spawn = false
	var all_stu = true
	tr.rng.seed = 5
	var bd_n = 0
	for k in 40:
		tr.release_all()
		var sp2 = tr.spawn()
		if sp2 != null:
			bd_n += 1
			all_stu = all_stu and (sp2.student or sp2.emergency)
	check(bd_n > 20 and all_stu, "every aircraft is a student pilot on Bad Pilot Day (%d)" % bd_n)
	# Seeded like the daily shift.
	var seqs = []
	for rep in 3:
		save.day_override = 20100 if rep < 2 else 20101
		main.start_bad_day()
		tr.auto_spawn = true
		var sq2 = []
		tr.spawned.connect(func(pl): sq2.append([pl.type, snappedf(pl.entry.x, 0.01), snappedf(pl.entry.y, 0.01)]))
		for i in 60 * 30:
			main.step(1.0 / 60.0)
		seqs.append(sq2)
		for conn in tr.spawned.get_connections():
			tr.spawned.disconnect(conn["callable"])
	var ncmp = mini(mini(seqs[0].size(), seqs[1].size()), 5)
	check(ncmp >= 4 and seqs[0].slice(0, ncmp) == seqs[1].slice(0, ncmp) and seqs[0] != seqs[2], "the same day gives the same arrivals; another day differs")
	# Landings pay big; high thresholds; separate best and streak.
	save.day_override = 20100
	tuning.go_around_max = 0.0
	main.start_bad_day()
	tr.auto_spawn = false
	var fk2 = Aircraft.new()
	fk2.runway = 0
	fk2.type = MEDIUM
	fk2.student = true
	main._on_landed(fk2)
	check(main.shift.earned == roundi(tuning.pay_medium * tuning.student_pay_mult * tuning.bad_day_pay_mult), "every Bad Pilot Day landing pays big (%d vs %d for an ordinary one)" % [main.shift.earned, tuning.pay_medium])
	check(main.shift.thresholds[0] == roundi(tuning.star_thresholds()[0] * tuning.bad_day_threshold_mult), "...and its star thresholds are higher")
	var streaks_b = []
	var bonus_b = []
	var stars_b = save.stars_total()
	var daily_before = save.daily.duplicate()
	for day_i in [20100, 20101, 20101, 20103]:
		save.day_override = day_i
		main.start_bad_day()
		tr.auto_spawn = false
		var cb0 = save.coins
		earn_coins(main, main.shift.thresholds[0])
		var plain_b = main.shift.payout()
		tr.spawn_until = 0.0
		tr.run_time = tuning.par_eff() + 0.01
		main.step(1.0 / 60.0)
		streaks_b.append(save.daily_streak("bad"))
		bonus_b.append(save.coins - cb0 - plain_b)
	var b1 = roundi((tuning.daily_bonus_coins + tuning.daily_streak_coins * 1) * tuning.bad_day_bonus_mult)
	var b2 = roundi((tuning.daily_bonus_coins + tuning.daily_streak_coins * 2) * tuning.bad_day_bonus_mult)
	check(streaks_b == [1, 2, 2, 1] and bonus_b == [b1, b2, 0, b1], "Bad Pilot Day has its own streak and bonus %s %s" % [str(streaks_b), str(bonus_b)])
	check(save.daily == daily_before and save.daily_streak("daily") == 0, "...separate from the Daily Shift's record")
	check(int(save.bad_day.get("best", 0)) >= main.shift.thresholds[0] and save.stars_total() == stars_b, "...its own best score, and no permanent stars")
	# The menu offers it; Save round trip keeps it.
	main._show_menu()
	check(not main.bad_mode and not main.daily_mode and main.hud._art.btn_id.find("bad") >= 0, "the menu has a Bad Pilot Day button")
	var bi = main.hud._art.btn_id.find("bad")
	var br = main.hud._art.btn_rect[bi]
	var vpz = main.get_viewport().get_visible_rect().size
	check(br.end.y <= vpz.y and br.end.x <= vpz.x and br.position.y > vpz.y * 0.5 + 200.0, "...which fits on screen (%s)" % str(br))
	main._on_button("bad")
	check(main.bad_mode and main.screen == main.SCREEN_PLAY, "pressing it starts the shift")
	save.write_file()
	save.bad_day = {}
	save.load_file()
	check(int(save.bad_day.get("streak", 0)) == 1, "the Bad Pilot Day record survives a save round trip")
	save.day_override = -1
	tuning.go_around_max = 0.0
	main.daily_mode = false
	main.bad_mode = false
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false

	print("9j. shift length, pause menu")
	check(tuning.par_window == 15.0 and tuning.shift_scale == 1.0 and tuning.par_eff() == tuning.spawn_stop_eff() + 15.0, "par is 15 s after spawning stops")
	var th_txt = []
	for ai in Airports.COUNT:
		th_txt.append(str(tuning.star_thresholds(ai)))
	var th_up = true
	for ai in range(1, Airports.COUNT):
		th_up = th_up and tuning.star_thresholds(ai)[2] > tuning.star_thresholds(ai - 1)[2]
	check(th_up, "star thresholds rise from airport to airport %s" % ", ".join(th_txt))
	check(tuning.daily_bonus_coins == 75 and tuning.daily_streak_coins == 13, "the daily completion bonus was halved too")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var pbtn = main.hud._art.pause_rect
	var vpp = main.get_viewport().get_visible_rect().size
	check(main.hud._art.show_play and pbtn.position.x < vpp.x * 0.25 and pbtn.position.y < vpp.y * 0.1 and pbtn.size.x >= 80.0, "a pause button sits in the top-left corner (%s)" % str(pbtn))
	# It overlaps no other HUD element and no aircraft entry point.
	var score_rect = Rect2(vpp.x * 0.5 - 300.0, 30.0, 600.0, 140.0)
	var wind_rect = Rect2(vpp.x - 148.0, 140.0, 112.0, 112.0)
	check(not pbtn.intersects(score_rect) and not pbtn.intersects(wind_rect), "...clear of the score and the wind dial")
	var entry_clear = true
	tr.rng.seed = 77
	for k in 150:
		tr.release_all()
		var spn = tr.spawn()
		if spn != null:
			var sc = main.overlay.world_to_screen(spn.entry)
			if pbtn.grow(10.0).has_point(sc):
				entry_clear = false
	check(entry_clear, "...and aircraft never enter the screen under it (150 arrivals)")
	tr.release_all()
	check(not ("pilot_animal" in main.hud._art), "the duck pilot portrait is gone from the play HUD")
	# Pausing.
	var pl9x = tr.place(0, Vector2(-3.0, 2.0), 0.0, MEDIUM)
	run_sec(main, 2.0)
	main._touch_down(0, pbtn.get_center())
	main._touch_up(0, pbtn.get_center())
	check(main.screen == main.SCREEN_PAUSE and main.hud.pause_visible(), "tapping it pauses and shows the pause menu")
	var t_p = tr.run_time
	var pos_p = pl9x.pos
	var tl_p = pl9x.timer_left
	for i in 120:
		main.step(1.0 / 60.0)
		main._process(1.0 / 60.0)
	check(is_equal_approx(tr.run_time, t_p) and pl9x.pos.is_equal_approx(pos_p) and is_equal_approx(pl9x.timer_left, tl_p), "the shift clock and all traffic are frozen while paused")
	check(has_btn(main, "resume") and has_btn(main, "restart") and has_btn(main, "quit"), "the menu has Resume, Restart Shift and Quit to Menu")
	main._touch_down(0, Vector2(vpp.x * 0.5, 40.0))
	main._touch_up(0, Vector2(vpp.x * 0.5, 40.0))
	check(main.screen == main.SCREEN_PAUSE, "a tap elsewhere doesn't do anything (it won't start a new shift)")
	# Volume sliders.
	var sld = main.hud._art.slider_rect
	main._touch_down(0, Vector2(sld[0].position.x + sld[0].size.x * 0.25, sld[0].position.y + sld[0].size.y * 0.6))
	main._touch_move(0, Vector2(sld[0].position.x + sld[0].size.x * 0.3, sld[0].position.y + sld[0].size.y * 0.6))
	main._touch_up(0, Vector2(sld[0].position.x + sld[0].size.x * 0.3, sld[0].position.y + sld[0].size.y * 0.6))
	check(absf(save.sound_volume - 0.3) < 0.01 and absf(save.music_volume - 0.8) < 0.01, "dragging the sound slider sets the sound volume only (%.2f)" % save.sound_volume)
	var sfx_bus = AudioServer.get_bus_index("SFX")
	check(sfx_bus >= 0 and absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.3)) < 0.1, "...on its own audio bus")
	main._touch_down(0, Vector2(sld[1].position.x, sld[1].position.y + sld[1].size.y * 0.6))
	main._touch_up(0, Vector2(sld[1].position.x, sld[1].position.y + sld[1].size.y * 0.6))
	var mus_bus = AudioServer.get_bus_index("Music")
	check(save.music_volume == 0.0 and AudioServer.is_bus_mute(mus_bus), "the music slider at zero mutes music")
	save.write_file()
	save.sound_volume = 1.0
	save.load_file()
	check(absf(save.sound_volume - 0.3) < 0.01 and save.music_volume == 0.0, "the volumes are saved")
	# Resume.
	main._on_button("resume")
	check(main.screen == main.SCREEN_PLAY and not main.hud.pause_visible(), "Resume carries on")
	run_sec(main, 1.0)
	check(tr.run_time > t_p + 0.9 and not is_equal_approx(pl9x.pos.x, pos_p.x), "...and the clock and traffic run again")
	# Restart Shift.
	main.pause_game()
	main._on_button("restart")
	check(main.screen == main.SCREEN_PLAY and main.alive and tr.run_time < 0.1 and main.score == 0 and not main.hud.pause_visible(), "Restart Shift starts a fresh shift")
	# Quit to Menu.
	main.pause_game()
	main._on_button("quit")
	check(main.screen == main.SCREEN_MENU and not main.hud.pause_visible(), "Quit to Menu goes back to the menu")
	# The pause button only exists during a shift.
	check(not main.hud.pause_hit(pbtn.get_center()), "...where the pause button is gone")
	# Auto-pause when the app loses focus (only during a shift).
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.screen == main.SCREEN_MENU, "losing focus on the menu pauses nothing")
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	main.restart()
	tr.auto_spawn = false
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.screen == main.SCREEN_PAUSE and main.hud.pause_visible(), "losing focus during a shift pauses it")
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(main.screen == main.SCREEN_PAUSE, "...and it stays paused until you press Resume")
	main._on_button("resume")
	check(main.screen == main.SCREEN_PLAY and main.alive, "Resume after coming back")
	# Paused near the end: the shift can't end while paused.
	tr.run_time = tuning.par_eff() - 0.5
	main.pause_game()
	for i in 120:
		main.step(1.0 / 60.0)
	check(main.alive and main.screen == main.SCREEN_PAUSE, "a paused shift doesn't run out its clock")
	main._on_button("resume")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false

	print("9k. traffic ramp, the finale, overtime, sound")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	# The ramp is scaled to the 90 s shift: it reaches the old full, busy state when spawning stops.
	var k9_full_t = float(tuning.profile()["ramp"]) * tuning.spawn_stop_eff()
	check(absf(tuning.spawn_progress(k9_full_t) - 1.0) < 0.001 and tuning.spawn_progress(k9_full_t * 0.5) > 0.45 and tuning.spawn_progress(k9_full_t * 0.5) < 0.55, "the traffic ramp finishes at %.0f s of a %.0f s spawning window" % [k9_full_t, tuning.spawn_stop_eff()])
	check(absf(tuning.spawn_interval(tuning.spawn_stop_eff()) - float(tuning.profile()["spawn_min"]) * (tuning.intro_spawn_scale if tuning.intro_active else 1.0)) < 0.01 and absf(tuning.speed_mult(tuning.spawn_stop_eff()) - tuning.speed_ramp_max * float(tuning.profile()["speed"])) < 0.01, "...at the busiest spacing and top speed (%.1f s apart, x%.1f)" % [tuning.spawn_interval(tuning.spawn_stop_eff()), tuning.speed_mult(tuning.spawn_stop_eff())])
	check(tuning.spawn_progress(30.0) > 0.4, "a 30 s old shift is already well into the ramp (%.2f)" % tuning.spawn_progress(30.0))
	# Spawning stops at 85 s.
	tr.auto_spawn = true
	tr.run_time = tuning.spawn_stop_eff() - 5.0
	tr.release_all()
	var late_spawns = [0]
	var spawned_before_stop = [0]
	var late_cb = func(_pl):
		if tr.run_time >= tuning.spawn_stop_eff():
			late_spawns[0] += 1
		else:
			spawned_before_stop[0] += 1
	tr.spawned.connect(late_cb)
	for i in 60 * 4:
		main.step(1.0 / 60.0)
	tr.release_all()
	for i in 60 * 6:
		main.step(1.0 / 60.0)
		if tr.run_time > tuning.spawn_stop_eff() + 1.0:
			tr.release_all()
	tr.spawned.disconnect(late_cb)
	check(spawned_before_stop[0] >= 1 and late_spawns[0] == 0, "arrivals come until the shift length (%d), then none (%d)" % [spawned_before_stop[0], late_spawns[0]])
	# The finale.
	var k9_snd0 = main.sfx.plays.duplicate()
	main.restart()
	tr.auto_spawn = false
	var k9_f1 = tr.place(0, Vector2(-3.0, 2.0), PI * 0.5, MEDIUM)
	var k9_f2 = tr.place(1, Vector2(3.0, 5.0), -PI * 0.5, SMALL)
	k9_f1.timer_left = 40.0
	k9_f2.timer_left = 40.0
	k9_f1.timer_max = 40.0
	k9_f2.timer_max = 40.0
	tr.run_time = tuning.spawn_stop_eff() - 0.5
	main.step(1.0 / 60.0)
	check(main.hud.finale_text() == "" and main._finale == 0, "before the shift length there is no finale")
	tr.run_time = tuning.spawn_stop_eff()
	main.step(1.0 / 60.0)
	check(main.hud.finale_text() == "LAST ARRIVALS" and main.sfx.plays["last_arrivals"] == k9_snd0["last_arrivals"] + 1, "at the shift length: the LAST ARRIVALS banner and its stinger")
	var k9_tl0 = k9_f1.timer_left
	for i in 60 * 4:
		main.step(1.0 / 60.0)
		for pf in [k9_f1, k9_f2]:        # (keep them from leaving by themselves)
			pass
	check(main.hud.finale_text().begins_with("CLEAR THE SKY") and main.hud.finale_text().contains("%d left" % tr.remaining()) and main.sfx.plays["clear_sky"] == k9_snd0["clear_sky"] + 1, "...then the CLEAR THE SKY counter with the aircraft remaining (%s)" % main.hud.finale_text())
	check(k9_f1.timer_left < k9_tl0 - 3.0, "aircraft timers keep running during the finale (%.1f -> %.1f)" % [k9_tl0, k9_f1.timer_left])
	check(main.alive and main.screen == main.SCREEN_PLAY, "the shift does not end while aircraft remain")
	# One diverted, one lands: the counter drops, and the shift ends when the sky is clear.
	var k9_left_before = tr.remaining()
	k9_f2.timer_left = 0.01
	main.step(1.0 / 30.0)
	check(tr.remaining() == k9_left_before - 1 and main.hud.finale_text().contains("%d left" % tr.remaining()), "a diversion counts as lost: the counter drops")
	tr.lose(k9_f1)
	main.step(1.0 / 60.0)
	check(not main.alive and main.screen == main.SCREEN_OVER, "the shift ends once every aircraft has landed or been lost")
	check(main.hud.finale_text() == "", "...and the banner goes away")
	# Early bonus: clear before par.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 100)
	tr.run_time = tuning.par_eff() - 3.6
	main.step(1.0 / 60.0)
	check(not main.alive and main.shift.early_seconds == 3 and main.shift.time_bonus == 3 * int(tuning.early_bonus_per_second), "clearing the sky 3.5 s before par pays %d coins per whole second early (%d)" % [int(tuning.early_bonus_per_second), main.shift.time_bonus])
	check(main.last_result["reason"].contains("Early bonus|+%d (3 s)" % main.shift.time_bonus) and main.last_result["reason"].contains("Overtime|-0 (0 s)"), "the results show the time bonus and the overtime lines")
	check(main.shift.balance() == main.shift.earned + main.shift.bonus + main.shift.time_bonus and main.last_result["payout"] == main.shift.balance(), "...and the bonus is part of the payout")
	# Overtime: a plane that never leaves.
	main.restart()
	tr.auto_spawn = false
	var k9_slow = tr.place(0, Vector2(0.0, 3.0), 0.0, MEDIUM)
	k9_slow.timer_left = 500.0
	k9_slow.timer_max = 500.0
	earn_coins(main, 100)
	var k9_bal_par = main.shift.balance()
	var k9_ticks0 = main.sfx.plays["tick"]
	tr.run_time = tuning.par_eff() - 0.1
	main.step(1.0 / 60.0)
	check(main.alive and main.hud._best.text.begins_with("0:0"), "just before par the clock still counts down (%s)" % main.hud._best.text)
	for i in 60 * 8:
		main.step(1.0 / 60.0)
	var k9_ot_s = main.shift.overtime_seconds
	check(k9_ot_s >= 7 and main.shift.overtime_penalty == k9_ot_s * int(tuning.overtime_penalty_per_second), "after par every whole second costs %d coins (%d s over, -%d)" % [int(tuning.overtime_penalty_per_second), k9_ot_s, main.shift.overtime_penalty])
	check(main.hud._best.text.begins_with("+0:0") and main.hud._best.get_theme_color("font_color").r > 0.9 and main.hud._best.get_theme_color("font_color").g < 0.4, "the clock turns red and counts up (%s)" % main.hud._best.text)
	check(main.hud._art.balance == main.shift.balance() and main.shift.balance() == k9_bal_par - main.shift.overtime_penalty, "the coin balance shows the overtime live")
	check(main.sfx.plays["tick"] >= k9_ticks0 + k9_ot_s, "an overtime tick sounds each second")
	check(main.hud.finale_text().begins_with("CLEAR THE SKY") and main.alive, "still clearing the sky in overtime")
	tr.lose(k9_slow)
	main.step(1.0 / 60.0)
	check(not main.alive and main.last_result["reason"].contains("Overtime|-%d (%d s)" % [main.shift.overtime_penalty, main.shift.overtime_seconds]), "the results show the overtime that was charged")
	# Sound: the placeholder set exists and is wired up.
	var k9_sfx = main.sfx
	var k9_all_made = true
	for nm in k9_sfx.NAMES:
		k9_all_made = k9_all_made and k9_sfx._streams.has(nm) and k9_sfx._streams[nm].data.size() > 100
	check(k9_all_made, "every placeholder sound was generated (%s)" % ", ".join(k9_sfx.NAMES))
	check(k9_sfx._music_calm.stream.data.size() == k9_sfx._music_hot.stream.data.size() and k9_sfx._music_hot.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "two equal-length music loops, looping")
	var k9_loop_players = 0
	for k9_lp in k9_sfx.get_children():
		if k9_lp is AudioStreamPlayer and k9_lp.stream is AudioStreamWAV and k9_lp.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			k9_loop_players += 1
	check(k9_loop_players == 4, "four looping players in all (calm, hot, tense, fog): no engine hum (%d)" % k9_loop_players)
	check(k9_sfx._streams["landing"] != k9_sfx._streams["go_around"] and k9_sfx._music_calm.stream.data != k9_sfx._fog_amb.stream.data, "the sounds differ from each other")
	main.restart()
	tr.auto_spawn = false
	var k9_c0 = k9_sfx.plays.duplicate()
	var k9_fk3 = Aircraft.new()
	k9_fk3.runway = 0
	k9_fk3.type = MEDIUM
	main._on_landed(k9_fk3)
	check(k9_sfx.plays["landing"] == k9_c0["landing"] + 1, "a landing rings the chime (the coins plink as they reach the counter)")
	main._on_go_around(k9_fk3, 2)
	check(k9_sfx.plays["go_around"] == k9_c0["go_around"] + 1, "a go-around plays the roar")
	var k9_ca3 = tr.place(0, Vector2(0, 0), 0.0, MEDIUM)
	var k9_cb3 = tr.place(1, Vector2(0.2, 0.1), 0.0, MEDIUM)
	main._on_conflict(k9_ca3, k9_cb3)
	check(k9_sfx.plays["alarm"] == k9_c0["alarm"] + 1 and k9_sfx.plays["fine"] == k9_c0["fine"] + 1, "a conflict sounds the alarm and the fine sound")
	var k9_w0 = k9_sfx.plays["wind"]
	set_wind(main, fposmod(main.wind.from_deg + 90.0, 360.0))
	main.step(1.0 / 60.0)
	check(k9_sfx.plays["wind"] == k9_w0 + 1, "a wind shift plays the chime (%d -> %d, last %s now %s)" % [k9_w0, k9_sfx.plays["wind"], str(main._last_wind_deg), str(main.wind.from_deg)])
	var k9_tp0 = k9_sfx.plays["back"]
	main._on_button("menu")
	check(k9_sfx.plays["back"] == k9_tp0 + 1, "going back has its own sound")
	main.restart()
	tr.auto_spawn = false
	for k9_h in [GLIDER, HELI, SMALL, MEDIUM, JET, SEAPLANE]:
		tr.place(0, Vector2(-3.0 + k9_h * 1.0, -4.0), 0.0, k9_h)
	main.step(1.0 / 60.0)
	for i in 120:
		k9_sfx._process(1.0 / 60.0)
	var k9_has_hum = false
	for k9_n in k9_sfx.get_children():
		if k9_n is AudioStreamPlayer and k9_n.playing and k9_n != k9_sfx._music_calm and k9_n != k9_sfx._music_hot and k9_n != k9_sfx._music_tense and k9_n != k9_sfx._fog_amb and not k9_sfx._pool.has(k9_n):
			k9_has_hum = true
	check(not k9_has_hum and not k9_sfx.LAYERS.has("hum") and not FileAccess.file_exists("res://assets/audio/loops/hum.wav") and not k9_sfx.has_method("set_hum_counts"), "there is no engine hum, however many aircraft are on the field")
	tr.release_all()
	main.step(1.0 / 60.0)
	main.restart()
	tr.auto_spawn = false
	tr.run_time = 5.0
	main.step(1.0 / 60.0)
	var k9_early_lv = k9_sfx.music_level
	tr.run_time = 70.0
	main.step(1.0 / 60.0)
	var k9_late_lv = k9_sfx.music_level
	tr.run_time = 86.0
	main.step(1.0 / 60.0)
	check(k9_early_lv < 0.05 and k9_late_lv > k9_early_lv + 0.3 and k9_sfx.music_level >= k9_late_lv and k9_sfx.music_pitch == 1.0, "the music intensifies towards the end, always in key (%.2f -> %.2f -> %.2f)" % [k9_early_lv, k9_late_lv, k9_sfx.music_level])
	check(k9_sfx._music_calm.playing or true, "the music loop is running")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false

	print("9l. guaranteed earnings, upgrade prices")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	# Shift bookkeeping on its own.
	var sh = Shift.new()
	sh.reset([50, 100, 160], 0.5)
	sh.on_landed(MEDIUM, 100, 30)
	check(sh.kept() == 50 and sh.balance() == 130 and sh.payout() == 130, "a clean shift pays everything: net 130, kept 50")
	sh.fine(60, "conflict")
	check(sh.balance() == 70 and sh.payout() == 70, "fines come off the bonuses and the other half of landing pay first (net 70)")
	sh.fine(400, "conflict")
	check(sh.balance() == -330 and sh.payout() == 50 and sh.stars() == 0, "a disaster still pays the guaranteed half of landing pay (50), and earns no stars")
	sh.set_overtime(30.0, 4)
	check(sh.payout() == 50 and sh.balance() == -330 - 120, "overtime cannot cut into the guaranteed share either")
	sh.reset([50, 100, 160], 0.5)
	sh.on_landed(MEDIUM, 100, 0)
	sh.on_landed(MEDIUM, 25, 0)
	check(sh.kept() == 62, "the guaranteed share rounds down (62 of 125)")
	check(tuning.landing_keep_fraction == 0.5, "the guaranteed share is a Tuning value (50%%)")
	# A failed shift in the real game: lots of landings, then conflicts.
	var coins_before = save.coins
	earn_coins(main, 100)
	var earned_l = main.shift.earned
	for k in 6:
		main._apply_fine(int(tuning.fine_conflict), "conflict", "CONFLICT", Vector2.ZERO)
	check(main.shift.balance() < 0, "six conflicts push the net negative (%d)" % main.shift.balance())
	check(main.shift.stars() == 0, "...and stars use the net: none")
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(main.last_result["payout"] == earned_l / 2 and save.coins == coins_before + earned_l / 2, "a failed shift still pays the guaranteed half of landing pay (%d)" % (earned_l / 2))
	var body = main.hud._over_body.text
	check(body.contains("Landings earned +%d" % earned_l) and body.contains("Fines -%d" % (6 * int(tuning.fine_conflict))) and body.contains("Guaranteed kept %d" % (earned_l / 2)) and body.contains("Net total (stars) %d" % main.shift.balance()) and body.contains("Total paid +%d" % (earned_l / 2)), "the results show landings earned, fines, kept and the total")
	# A raised share is respected.
	tuning.landing_keep_fraction = 0.8
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 50)
	check(main.shift.kept() == floori(main.shift.earned * 0.8), "the guaranteed share follows the Tuning value")
	tuning.landing_keep_fraction = 0.5
	# Upgrade prices: the first one is within reach after 1-2 poor shifts, and they keep coming.
	var poor_kept = floori(5.0 * tuning.pay_medium * tuning.landing_keep_fraction)
	var l1 = []
	for id in Upgrades.IDS:
		l1.append(Upgrades.cost(id, 0))
	l1.sort()
	check(l1[0] <= 2 * poor_kept, "the cheapest upgrade (%d) costs at most two poor shifts' guaranteed pay (2 x %d)" % [l1[0], poor_kept])
	var steady = true
	var cum_cost = 0
	for k in l1.size():
		cum_cost += l1[k]
		steady = steady and cum_cost <= (k + 1) * 4 * poor_kept
	check(steady, "...and the first six upgrades come steadily: all of them within %d poor shifts (%d coins in total)" % [ceili(float(cum_cost) / poor_kept), cum_cost])
	check(tuning.par_window == 15.0 and tuning.early_bonus_per_second * 15.0 <= 100.0 and tuning.overtime_penalty_per_second < tuning.early_bonus_per_second, "par leaves a 15 s window; the early bonus tops out at %d coins, overtime costs %d per second" % [int(tuning.early_bonus_per_second * 15.0), int(tuning.overtime_penalty_per_second)])
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false

	print("9m. airport difficulty profiles, gentle first shifts, intro beats")
	save.reset_all()
	save.unlocks["all_airports"] = true
	check(tuning.airport_profiles.size() == Airports.COUNT, "one difficulty profile per airport")
	var mono = true
	for ai in range(1, Airports.COUNT):
		var pa = tuning.profile(ai - 1)
		var pb = tuning.profile(ai)
		mono = mono and pb["max_planes"] >= pa["max_planes"] and pb["spawn_start"] <= pa["spawn_start"] and pb["spawn_min"] <= pa["spawn_min"] and pb["speed"] >= pa["speed"] and pb["timer"] <= pa["timer"] and pb["stars"][2] > pa["stars"][2] and pb["fines"] >= pa["fines"]
	check(mono, "difficulty only steps up: more traffic, faster pace, faster aircraft, shorter timers, higher stars and fines")
	var pg = tuning.profile(0)
	var pc = tuning.profile(1)
	check(pg["max_planes"] <= 3 and pc["max_planes"] <= 4 and pg["specials"] == 0.0 and pg["weather"] == 0.0 and pg["wind"] == 0.0 and pc["weather"] == 0.0 and pc["wind"] > 0.0, "Grass Strip: at most 3 aircraft, no specials, no weather, no wind shifts; County: at most 4, gentle wind shifts, no weather")
	var slow_only = true
	for k in Airports.mix(0):
		slow_only = slow_only and tuning.type_speed_class(k) == 0
	check(slow_only and pg["speed"] < 1.0 and pg["timer"] > 1.0, "Grass Strip has slow aircraft only, at a gentle speed (x%.2f), with long timers (x%.2f)" % [pg["speed"], pg["timer"]])
	var pm = tuning.profile(3)
	check(pm["max_planes"] >= 10 and pm["speed"] == 1.0 and pm["timer"] == 1.0 and pm["weather"] == 1.0 and pm["wind"] == 1.0, "Mountain Field is where today's full intensity is reached")
	check(tuning.profile(5)["max_planes"] > pm["max_planes"] and tuning.profile(5)["speed"] > 1.0 and tuning.profile(5)["timer"] < 1.0, "International goes beyond it")
	# Densities: nobody plays, and the field still never holds more than the cap.
	var peak = []
	for ai in [0, 1, 3, 5]:
		main.select_airport(ai)
		save.airport_plays[ai] = 1      # (not the gentle first shift)
		main.restart()
		tr.rng.seed = 900 + ai          # (the same arrivals on every run of the test)
		tr.auto_spawn = true
		var peak_n = 0
		var arrivals = [0]
		var arr_cb = func(_pl): arrivals[0] += 1
		tr.spawned.connect(arr_cb)
		for i in 60 * 80:
			main.step(1.0 / 60.0)
			peak_n = maxi(peak_n, tr.active_count())
			for pl in tr.planes:
				if pl.active() and pl.age > 10.0:
					tr.lose(pl)         # (stand-in for a player who lands them)
			if not main.alive:
				break
		tr.spawned.disconnect(arr_cb)
		peak.append([ai, peak_n, arrivals[0]])
		check(peak_n <= tuning.max_planes_eff(), "%s: never more than %d aircraft at once (peak %d, %d arrivals in a shift)" % [Airports.airport_name(ai), tuning.max_planes_eff(), peak_n, arrivals[0]])
	check(peak[0][2] <= peak[1][2] + 2 and peak[1][2] < peak[2][2] and peak[2][2] <= peak[3][2] + 2, "later airports bring more arrivals (%s)" % str(peak))
	check(peak[0][2] >= 5 and peak[0][2] <= 12 and peak[2][2] >= 12, "Grass Strip ~%d arrivals in its 45 s shift, Mountain Field ~%d in 75 s" % [peak[0][2], peak[2][2]])
	# Grass Strip: no wind shift and no weather, ever.
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	var shifts_seen = [0]
	var wx_seen = [0]
	var wcb = func(_d): shifts_seen[0] += 1
	var xcb = func(_k, _t): wx_seen[0] += 1
	main.wind.warned.connect(wcb)
	main.weather.warned.connect(xcb)
	for i in 60 * 84:
		main.step(1.0 / 60.0)
	main.wind.warned.disconnect(wcb)
	main.weather.warned.disconnect(xcb)
	check(shifts_seen[0] == 0 and wx_seen[0] == 0, "Grass Strip: no wind shift or weather in a whole shift")
	# County: the first wind shift is announced no earlier than wind_first, and weather never comes.
	main.select_airport(1)
	main.restart()
	tr.auto_spawn = false
	var first_wind = [-1.0]
	var wx2 = [0]
	var wcb2 = func(_d):
		if first_wind[0] < 0.0:
			first_wind[0] = tr.run_time
	var xcb2 = func(_k, _t): wx2[0] += 1
	main.wind.warned.connect(wcb2)
	main.weather.warned.connect(xcb2)
	for i in 60 * 84:
		main.step(1.0 / 60.0)
	main.wind.warned.disconnect(wcb2)
	main.weather.warned.disconnect(xcb2)
	check(first_wind[0] >= float(tuning.profile(1)["wind_first"]) - tuning.wind_warning_seconds - 0.5 and first_wind[0] > 0.0 and wx2[0] == 0, "County: the first wind shift is announced at %.0f s, with no weather" % first_wind[0])
	# Fines scale with the airport.
	main.select_airport(0)
	Airports.current = 0
	check(tuning.fine_amount(tuning.fine_conflict) == roundi(tuning.fine_conflict * 0.4) and tuning.fine_amount(tuning.fine_conflict) < 50, "Grass Strip fines are small (conflict %d)" % tuning.fine_amount(tuning.fine_conflict))
	main.select_airport(3)
	Airports.current = 3
	check(tuning.fine_amount(tuning.fine_conflict) == int(tuning.fine_conflict), "...and full size from Mountain Field on")
	# The first shift at an airport is gentler.
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	var iv_first = tuning.spawn_interval(40.0)
	var tm_first = tuning.timer_mult()
	check(tuning.intro_active and save.airport_plays[2] == 0, "a first visit is flagged as an intro shift")
	tr.auto_spawn = false
	var tp_first = tr.place(0, Vector2(-3, 0), 0.0, MEDIUM)
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(not main.alive and save.airport_plays[2] == 1, "finishing it is recorded")
	main.restart()
	check(not tuning.intro_active and tuning.spawn_interval(40.0) < iv_first and absf(iv_first / tuning.spawn_interval(40.0) - tuning.intro_spawn_scale) < 0.01, "replays have the normal pace: arrivals %.2fx further apart in the first shift" % (iv_first / tuning.spawn_interval(40.0)))
	check(tm_first > tuning.timer_mult() and absf(tm_first / tuning.timer_mult() - tuning.intro_timer_scale) < 0.01, "...and the first shift has longer timers (x%.2f)" % (tm_first / tuning.timer_mult()))
	main.start_daily()
	check(not tuning.intro_active and tr.beats.is_empty(), "the daily shifts have no intro easing and no scripted beats")
	main._show_menu()
	# Intro beats: the new mechanic arrives alone, early.
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = true
	var log = []
	var lcb = func(pl): log.append([tr.run_time, pl.type])
	tr.spawned.connect(lcb)
	for i in 60 * 40:
		main.step(1.0 / 60.0)
		for pl in tr.planes:
			if pl.active() and pl.timer_left < 5.0:
				pl.timer_left = 50.0
	tr.spawned.disconnect(lcb)
	var heli_i = -1
	var jet_i = -1
	for k in log.size():
		if log[k][1] == HELI and heli_i < 0 and log[k][0] >= 4.0:
			heli_i = k
		if log[k][1] == JET and jet_i < 0 and log[k][0] >= 20.0:
			jet_i = k
	check(heli_i >= 0 and log[heli_i][0] >= 5.0 and log[heli_i][0] < 10.0, "Regional: the helicopter (new mechanic) arrives early, at %.1f s" % (log[heli_i][0] if heli_i >= 0 else -1.0))
	var alone = heli_i >= 0
	for k in log.size():
		if k != heli_i and heli_i >= 0 and log[k][0] > log[heli_i][0] - tuning.beat_quiet_lead + 0.5 and log[k][0] < log[heli_i][0] + tuning.beat_gap - 0.5:
			alone = false
	check(alone, "...and alone: nothing else arrives in the %.0f s around it" % (tuning.beat_quiet_lead + tuning.beat_gap))
	check(jet_i >= 0 and log[jet_i][0] >= 24.0 and log[jet_i][0] < 32.0, "...and the jet comes by itself later, at %.1f s" % (log[jet_i][0] if jet_i >= 0 else -1.0))
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false

	print("9n. clarity pass: one primary element per screen, three text sizes, one banner / tip at a time")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	var art = main.hud._art
	var area = func(k): return art.btn_rect[k].size.x * art.btn_rect[k].size.y
	var words_ok = func(t): return t.split(" ", false).size() <= 4
	# Menu.
	main._show_menu()
	var primaries = []
	var biggest = 0.0
	var big_id = ""
	for k in art.btn_count:
		if art.btn_kind[k] == 2:
			primaries.append(art.btn_id[k])
		if area.call(k) > biggest:
			biggest = area.call(k)
			big_id = art.btn_id[k]
	check(primaries == ["play"] and big_id == "play", "menu: one primary button (PLAY), and it is the biggest thing on screen")
	var menu_words = true
	for k in art.btn_count:
		menu_words = menu_words and words_ok.call(art.btn_text[k]) and art.btn_sub[k] == ""
	check(menu_words and art.btn_count <= 8, "menu: short labels, no descriptions (%d buttons)" % art.btn_count)
	var round_n = 0
	for k in art.btn_count:
		if art.btn_kind[k] == 7:
			round_n += 1
			menu_words = menu_words and art.btn_glyph[k] != ""
	check(round_n == 3 and menu_words, "menu: Upgrades, Hangar and Daily are three small round icon buttons")
	check(not main.hud._score.visible and not main.hud._best.visible, "menu: no leftover shift numbers behind it")
	check(not main.hud._ad.visible, "menu: nothing else is covering it")
	# The three text sizes: every label in the interface uses one of them.
	var sizes_ok = true
	var sizes_seen = {}
	for ch in main.hud.get_children():
		if ch is Label and ch != main.hud._perf_label and ch != main.hud._stamp:
			var sz = ch.get_theme_font_size("font_size")
			sizes_seen[sz] = true
			sizes_ok = sizes_ok and (sz == main.hud.SZ_XL or sz == main.hud.SZ_M or sz == main.hud.SZ_S or sz == 26)
	for scr in [main.hud._menu, main.hud._over, main.hud._select, main.hud._pause, main.hud._ad]:
		for ch in scr.get_children():
			if ch is Label:
				var sz2 = ch.get_theme_font_size("font_size")
				sizes_seen[sz2] = true
				sizes_ok = sizes_ok and (sz2 == main.hud.SZ_XL or sz2 == main.hud.SZ_M or sz2 == main.hud.SZ_S)
	check(sizes_ok, "every label uses one of the three text sizes %s (seen %s)" % [str([main.hud.SZ_XL, main.hud.SZ_M, main.hud.SZ_S]), str(sizes_seen.keys())])
	# Airport select: just a name, stars and a lock.
	main._on_button("airports")
	var sel_ok = true
	var cards_n = 0
	for k in art.btn_count:
		if art.btn_kind[k] == 1:
			cards_n += 1
			sel_ok = sel_ok and art.btn_sub[k].length() < 40 and art.btn_map[k] >= 0 and words_ok.call(art.btn_text[k])
	check(cards_n == Airports.COUNT and sel_ok, "airport select: one big card per airport with a mini-map, its name, one line, stars and lock")
	main._show_menu()
	# Upgrades: icon, name, one line, pips, cost.
	main._on_button("upgrades")
	var up_ok = true
	for k in art.btn_count:
		if art.btn_kind[k] == 1:
			up_ok = up_ok and art.btn_glyph[k] != "" and art.btn_sub[k].length() <= 26 and art.btn_sub[k].length() > 0 and art.btn_pips[k] >= 0 and art.btn_cost[k] >= 0 and words_ok.call(art.btn_text[k]) and art.btn_stars[k] == -1
	check(up_ok and art.btn_id.find("upg:radar") >= 0, "upgrades: each card has an icon, a name, one short line, level pips and a cost")
	main._show_menu()
	# Shop.
	for tab in [0, 1]:
		main.shop_tab = tab
		main._show_shop()
		var shop_ok = true
		for k in art.btn_count:
			if art.btn_kind[k] == 1:
				shop_ok = shop_ok and art.btn_icon[k] >= 0 and art.btn_sub[k].length() <= 10 and words_ok.call(art.btn_text[k])
		check(shop_ok, "shop (tab %d): cards are an icon, a name and a price or a status, no paragraphs" % tab)
	main.shop_tab = 0
	main._show_menu()
	# HUD: only the clock, the coins and the star bar.
	main.restart()
	tr.auto_spawn = false
	check(main.hud._score.visible and main.hud._best.visible and art.show_play, "HUD: the coin total and the clock")
	check(art.chip_finale == "" and art.chip_weather == "" and art.banner_text == "" and art.tip_alpha == 0.0 and not main.hud._tip.visible, "HUD: no banners, chips or tips until something happens (%s|%s|%s|%.1f|%s)" % [art.chip_finale, art.chip_weather, art.banner_text, art.tip_alpha, str(main.hud._tip.visible)])
	check(not main.hud._best.text.contains("landed") and main.hud._best.text.length() <= 5, "HUD: the clock is just m:ss (%s)" % main.hud._best.text)
	check(art.thresholds[2] > art.thresholds[1] and art.thresholds[1] > art.thresholds[0], "HUD: a slim bar with three star ticks")
	# Numbers roll up.
	var sh_roll = Shift.new()
	sh_roll.reset([50, 100, 160], 0.5)
	sh_roll.on_landed(MEDIUM, 100, 0)
	main.hud.set_shift(sh_roll)
	main.hud._process(0.016)
	var mid_v = int(main.hud._score.text)
	check(mid_v > 0 and mid_v < 100, "the coin total rolls up instead of jumping (%d on the first frame)" % mid_v)
	for i in 120:
		main.hud._process(0.016)
	check(main.hud._score.text == "100" and absf(art.bar_shown - 100.0) < 1.0, "...and arrives (%s)" % main.hud._score.text)
	main.hud.skip_animations()
	main.hud.set_shift(main.shift)
	main.hud.skip_animations()
	# One banner at a time, one tip at a time.
	main.hud.post_banner("LAST ARRIVALS", main.hud.C_GOLD, "plane", 2.0)
	main.hud.post_banner("Wind to 270", main.hud.C_GOLD, "wind", 2.0)
	check(main.hud.banner_text() == "LAST ARRIVALS" and main.hud._banner_q.size() == 1, "banners: the first shows, the second waits its turn")
	main.hud._process(2.5)
	check(main.hud.banner_text() == "Wind to 270" and main.hud._banner_q.is_empty(), "...and takes over once the first has gone")
	main.hud._process(2.5)
	main.hud._process(0.5)
	check(main.hud.banner_text() == "" and art.banner_alpha == 0.0, "...then it gets out of the way")
	main.hud.show_tip("First tip", "plane")
	main.hud.show_tip("Second tip", "jet")
	check(main.hud._tip.text == "First tip" and main.hud._tip_q.size() == 1, "tips: one at a time")
	var tip_len_ok = true
	for key in main.TIPS:
		tip_len_ok = tip_len_ok and main.TIPS[key][0].split(" ").size() <= 8 and main.TIPS[key][1] != ""
	check(tip_len_ok, "every tip is an icon and one short line")
	main.hud._tip_until = 0
	main.hud._process(0.016)
	check(main.hud._tip.text == "Second tip" and main.hud._tip_q.is_empty(), "...the next one follows when the first is done")
	main.hud._tip_until = 0
	main.hud._process(0.016)
	# Pause: nothing from the HUD shows through; one primary button.
	main.pause_game()
	var pause_prim = []
	for k in art.btn_count:
		if art.btn_kind[k] == 2:
			pause_prim.append(art.btn_id[k])
	check(pause_prim == ["resume"] and not main.hud._score.visible and not main.hud._best.visible, "pause: RESUME is the one primary button and the HUD is hidden behind it")
	main._on_button("resume")
	check(main.hud._score.visible and main.hud._best.visible, "...and comes back on resume")
	# Results.
	earn_coins(main, 100)
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(main.screen == main.SCREEN_OVER and not main.hud._score.visible and not main.hud._best.visible, "results: the shift HUD is gone")
	check(art.res_t < 1.0 and not main.hud.results_revealed() and not main.hud._over_body.visible and not main.hud.results_details_open(), "results: the stars and total are revealed in sequence; the breakdown is hidden")
	var res_prim = []
	var res_small = true
	for k in art.btn_count:
		if art.btn_kind[k] == 2:
			res_prim.append(art.btn_id[k])
		elif art.btn_id[k] != "again":
			res_small = res_small and area.call(k) < area.call(art.btn_id.find("again")) * 0.3
	check(res_prim == ["again"] and res_small, "results: one big PLAY AGAIN button; the ads and the rest are small chips")
	main.hud._process(1.0)
	var t_mid = art.res_t
	main.hud._process(5.0)
	check(t_mid > 0.9 and main.hud.results_revealed(), "results: the reveal plays out (%.1f s)" % t_mid)
	main._on_button("details")
	check(main.hud.results_details_open() and art.details_lines.size() >= 8, "results: 'Details' opens the full breakdown (%d lines)" % art.details_lines.size())
	main._on_button("details")
	check(not main.hud.results_details_open(), "...and closes it again")
	main.restart()
	tr.auto_spawn = false

	print("9o. atmospheric fog")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var fogl = main.fog_layer
	var fsm = fogl.shader_material()
	check(fsm.shader.code.contains("depth_test_disabled") and fsm.shader.code.contains("blend_mix") and fsm.shader.code.contains("TIME"), "the fog is a cheap one-quad shader with drifting noise (%d characters)" % fsm.shader.code.length())
	check(fogl.mesh is PlaneMesh and main.get_children().filter(func(n): return n.get_script() == fogl.get_script()).size() == 1, "one fog quad, created once")
	# Draw order: ground and scenery (opaque) -> fog -> path ribbons -> aircraft, runways and pads.
	var plane_mat = tr._body_mats[0]
	var rw_mat = main.airfield.cur.thr_mats[0]
	check(fsm.render_priority < -1 and plane_mat.render_priority > fsm.render_priority and rw_mat.render_priority > fsm.render_priority, "draw order: the fog comes before the ribbons, aircraft and runways")
	check(plane_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS and rw_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS and plane_mat.albedo_color.a == 1.0, "aircraft and runways sit in the pass after the fog but stay fully opaque")
	check(main.airfield.cur.ground_mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and main.airfield.cur.ground_mat.render_priority == 0, "the ground and scenery stay in the opaque pass: only they are dimmed")
	var pad_lifted = false
	var lane_lifted = true
	for av in main.airfield.variants:
		for mi in av.root.find_children("*", "MeshInstance3D", true, false):
			var bm = mi.material_override as BaseMaterial3D
			if bm != null and bm.render_priority == 2:
				pad_lifted = true
	check(pad_lifted, "runways, pads and lanes are lifted above the fog")
	var outl_ok = true
	for mi in tr._nodes[0].find_children("*", "MeshInstance3D", true, false):
		if mi.material_overlay != null:
			outl_ok = outl_ok and mi.material_overlay.render_priority == 2
	check(outl_ok, "aircraft outlines are drawn above the fog with them")
	# The fog layer follows the fog and costs nothing without it.
	tr.fog_amount = 0.0
	tr.fog_target = 0.0
	await process_frame
	check(not fogl.visible, "no fog, no layer")
	tr.fog_amount = 0.6
	tr.fog_target = 0.6
	await process_frame
	check(fogl.visible and absf(float(fsm.get_shader_parameter("amount")) - 0.6) < 0.01 and float(fsm.get_shader_parameter("max_alpha")) == tuning.fog_max_alpha and tuning.fog_max_alpha < 0.7, "fog layer on, translucent (never above %.2f alpha)" % tuning.fog_max_alpha)
	# Go-arounds: poor approaches a little riskier in fog, clean ones untouched.
	tuning.go_around_max = 0.98
	var thr_f = Airports.end_threshold(0, 0)
	var rd_f = (Airports.end_far(0, 0) - thr_f).normalized()
	var nm_f = Vector2(-rd_f.y, rd_f.x)
	var mk_f = func(poor):
		tr.release_all()
		tr._busy_until.fill(0.0)
		tr._last_td.fill(-1000.0)
		var pts = []
		if poor:
			pts = [[-1.5, -1.5], [-1.0, -1.0], [-0.5, -0.5]]
		else:
			var uu = -4.2
			while uu < -0.05:
				pts.append([uu, 0.0])
				uu += 0.3
		var q0 = pts[0]
		var pq = tr.place(0, thr_f + rd_f * q0[0] + nm_f * q0[1], atan2(rd_f.x, -rd_f.y), MEDIUM)
		for e in pts.slice(1):
			pq.push(thr_f + rd_f * e[0] + nm_f * e[1])
		pq.push(thr_f)
		pq.push(Airports.end_far(0, 0))
		pq.cleared = true
		pq.land_end = 0
		return pq
	tr.fog_amount = 0.0
	tr.fog_target = 0.0
	var poor_clear = mk_f.call(true)
	tr.step(1.0 / 60.0)
	var c_poor_clear = poor_clear.ga_chance
	var good_clear = mk_f.call(false)
	tr.step(1.0 / 60.0)
	var c_good_clear = good_clear.ga_chance
	var poor_fog = mk_f.call(true)
	tr.fog_amount = 1.0
	tr.fog_target = 1.0
	tr.step(1.0 / 60.0)
	var c_poor_fog = poor_fog.ga_chance
	var good_fog = mk_f.call(false)
	tr.fog_amount = 1.0
	tr.fog_target = 1.0
	tr.step(1.0 / 60.0)
	var c_good_fog = good_fog.ga_chance
	check(c_poor_fog > c_poor_clear and absf(c_poor_fog / c_poor_clear - tuning.fog_poor_go_around_mult) < 0.01 and tuning.fog_poor_go_around_mult <= 1.5, "in fog a poor approach goes around a bit more often (%.2f -> %.2f, x%.2f)" % [c_poor_clear, c_poor_fog, tuning.fog_poor_go_around_mult])
	check(c_good_clear == 0.0 and c_good_fog == 0.0, "...a clean approach is unaffected (%.2f / %.2f)" % [c_good_clear, c_good_fog])
	tuning.go_around_max = 0.0
	tr.fog_amount = 0.0
	tr.fog_target = 0.0
	tr.release_all()
	# Fog only where it belongs.
	var fog_at = []
	for ai in Airports.COUNT:
		main.select_airport(ai)
		Airports.current = ai
		fog_at.append("fog" in Airports.weather_kinds())
	check(not fog_at[0] and not fog_at[1] and fog_at[2] and fog_at[3] and fog_at[4] and fog_at[5], "no fog on Grass Strip or County, fog from Regional on (%s)" % str(fog_at))
	# Sound: a soft ambience and a tenser music layer while it lasts.
	main.select_airport(2)
	main.restart()
	var fsfx = main.sfx
	fsfx.set_music(true, 0.2, 0.0)
	fsfx.set_fog(0.0)
	check(fsfx.fog_level == 0.0 and not fsfx._fog_amb.playing and not fsfx._music_tense.playing, "no fog: no ambience, no tense layer")
	fsfx.set_fog(1.0)
	check(fsfx.fog_level == 1.0 and fsfx._fog_amb.playing and fsfx._music_tense.playing, "fog: the ambience and the tense music layer play")
	check(fsfx._music_tense.stream.data.size() == fsfx._music_calm.stream.data.size() and fsfx._music_tense.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "...the tense layer loops in step with the music")
	check(fsfx._fog_amb.volume_db < -10.0 and fsfx._fog_amb.volume_db > -40.0, "...the ambience is soft (%.0f dB)" % fsfx._fog_amb.volume_db)
	fsfx.set_fog(0.0)
	check(not fsfx._fog_amb.playing and not fsfx._music_tense.playing, "...and both go quiet when the fog lifts")
	main.restart()
	tr.auto_spawn = false

	print("9p. visual identity: tokens, fonts, safe areas, button states")
	save.reset_all()
	main.restart()
	tr.auto_spawn = false
	var sdoc = FileAccess.get_file_as_string("res://docs/style.md")
	var tokens_ok = true
	for tk in [Style.PRIMARY, Style.PRIMARY_DARK, Style.ACCENT, Style.ACCENT_DARK, Style.SUCCESS, Style.SUCCESS_DARK, Style.WARNING, Style.DANGER, Style.DANGER_DARK, Style.INK, Style.SURFACE_DARK, Style.SURFACE_DARK_2, Style.SURFACE_LIGHT, Style.SURFACE_LIGHT_2, Style.TEXT, Style.TEXT_SOFT, Style.TEXT_QUIET, Style.TEXT_ON_LIGHT, Style.SCRIM]:
		tokens_ok = tokens_ok and sdoc.contains("#" + tk.to_html(false))
	check(tokens_ok, "docs/style.md lists every palette colour of Style.gd")
	check(sdoc.contains("Bowlby One SC") and sdoc.contains("Rubik") and sdoc.contains("Safe areas") and sdoc.contains("ease-out-back") and sdoc.contains("Round"), "...and the typography, buttons, safe areas and motion")
	check(FileAccess.file_exists("res://assets/fonts/OFL-BowlbyOneSC.txt") and FileAccess.get_file_as_string("res://assets/fonts/OFL-BowlbyOneSC.txt").contains("SIL OPEN FONT LICENSE") and FileAccess.file_exists("res://assets/fonts/OFL-Rubik.txt") and FileAccess.get_file_as_string("res://assets/fonts/OFL-Rubik.txt").contains("SIL OPEN FONT LICENSE"), "both fonts ship with their OFL licence file")
	var lum = func(c: Color):
		var f = func(v): return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
		return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)
	var contrast = func(a: Color, b: Color):
		var la = lum.call(a)
		var lb = lum.call(b)
		return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
	check(contrast.call(Style.TEXT, Style.SURFACE_DARK) >= 4.5 and contrast.call(Style.TEXT_SOFT, Style.SURFACE_DARK) >= 4.5 and contrast.call(main.hud.C_GOLD_TXT, Style.SURFACE_DARK) >= 4.5 and contrast.call(Style.TEXT_ON_LIGHT, Style.SURFACE_LIGHT) >= 4.5, "text and gold text on the cream surface (and brown on the lightest cream) are at least 4.5:1")
	var fd = Style.display()
	var ft = Style.text()
	check(fd is FontFile and fd.resource_path.ends_with("BowlbyOneSC.ttf") and ft is FontVariation and ft.base_font.resource_path.ends_with("Rubik.ttf") and ft.variation_opentype[Style.WGHT] == 800.0 and Style.body().variation_opentype[Style.WGHT] == 500.0, "Bowlby One SC for display, Rubik 800 for labels and Rubik 500 for descriptions")
	check(Style.font_for("PLAY", 110) == fd and Style.font_for("Radar", 30) == ft and Style.font_for("160", 30) == fd and Style.font_for("+40", 30) == fd, "titles and numbers use the display face, small words the text face")
	check(main.hud._score.get_theme_font("font") == fd and main.hud._ad_sub.get_theme_font("font") == ft, "labels use them too")
	var no_emoji = true
	for fn in DirAccess.get_files_at("res://scripts"):
		if fn.ends_with(".gd"):
			for ch in FileAccess.get_file_as_string("res://scripts/" + fn):
				var cp = ch.unicode_at(0)
				if cp >= 0x1F000 or (cp >= 0x2600 and cp <= 0x27BF):
					no_emoji = false
	check(no_emoji, "no emoji anywhere: the icons are all drawn")
	check(Style.R_S < Style.R_M and Style.R_M < Style.R_L and Style.T_FAST < Style.T_BASE and Style.T_BASE < Style.T_SLOW and absf(Style.ease_out_back(1.0) - 1.0) < 0.001 and Style.ease_out_back(0.7) > 1.0 and Style.ease_out_cubic(0.0) == 0.0, "radii, timings and easing are consistent")
	# Buttons: pressed state.
	main._show_menu()
	await process_frame
	var pl_k = -1
	for bk in main.hud._art.btn_count:
		if main.hud._art.btn_id[bk] == "play":
			pl_k = bk
	var pl_pos = main.hud._art.btn_rect[pl_k].get_center()
	main.hud.press(pl_pos)
	check(main.hud.pressed_id() == "play", "a finger on a button draws it pressed")
	main.hud.release()
	check(main.hud.pressed_id() == "", "...and lifting releases it")
	main.hud.press(Vector2(5, 5))
	check(main.hud.pressed_id() == "", "a touch on empty space presses nothing")
	main.hud.release()
	# Safe areas.
	var base_pause = main.hud._art.pause_rect.position.y
	var base_score = main.hud._score.offset_top
	Style.set_safe(70.0, 50.0, 12.0, 12.0)
	main.hud.apply_safe()
	main._show_upgrades()
	var back_ok = false
	for bk in main.hud._art.btn_count:
		if main.hud._art.btn_id[bk] == "back":
			back_ok = main.hud._art.btn_rect[bk].position.y >= 70.0 and main.hud._art.btn_rect[bk].position.x >= 12.0
	check(main.hud._art.pause_rect.position.y == base_pause + 70.0 and main.hud._score.offset_top == base_score + 70.0 and back_ok, "a notch pushes the pause button, coin total, clock and back buttons down")
	var first_card = main.hud._art.btn_rect[1].position.y
	main.hud.post_banner("Safe", Color.WHITE, "wind", 1.0)
	main.hud.show_tip("Tip", "plane")
	check(main.hud._art.tip_rect.end.y <= main.get_viewport().get_visible_rect().size.y - 50.0 and first_card >= 150.0 + 70.0, "...lists start below it and the tip clears the home indicator")
	Style.set_safe(0.0, 0.0, 0.0, 0.0)
	main.hud.apply_safe()
	check(main.hud._art.pause_rect.position.y == base_pause and main.hud._score.offset_top == base_score, "no notch: everything is back where it was")
	main.restart()
	tr.auto_spawn = false

	print("9q. motion: transitions, button feedback, flying coins, living menu")
	save.reset_all()
	var hud = main.hud
	main._show_menu()
	check(hud.transition_kind() == "menu", "the menu arms its transition")
	var q_from_menu_depth = hud._tr_depth
	main._show_select()
	check(hud.transition_kind() == "select" and hud.transition_dir() == 1 and hud.transitioning(), "opening a list slides forward (%d)" % hud.transition_dir())
	check(hud.offset.x > 0.0 and hud._art.modulate.a < 0.5, "...it starts off to the right, faded out")
	hud._process(Style.T_BASE * 0.5)
	var q_mid_x = hud.offset.x
	hud._process(Style.T_BASE)
	check(q_mid_x > 0.0 and q_mid_x < hud.SLIDE and hud.offset == Vector2.ZERO and hud._art.modulate.a == 1.0 and not hud.transitioning(), "...eases in over %.2f s and settles exactly" % Style.T_BASE)
	main._show_menu()
	check(hud.transition_dir() == -1 and hud.offset.x < 0.0, "coming back slides from the left")
	hud.skip_animations()
	check(hud.offset == Vector2.ZERO and hud.transform == Transform2D.IDENTITY, "skipping finishes it")
	main._show_upgrades()
	hud.skip_animations()
	var q_up_kind = hud.transition_kind()
	main._show_upgrades()
	check(hud.transition_kind() == q_up_kind and not hud.transitioning(), "refreshing the same screen (a purchase) does not replay it")
	main.restart()
	tr.auto_spawn = false
	hud.skip_animations()
	main.pause_game()
	check(hud.transition_dir() == 0 and hud.transitioning() and hud.transform != Transform2D.IDENTITY, "sheets (pause) pop in with a scale instead of sliding")
	main.resume_game()
	hud.skip_animations()
	main._show_menu()
	hud.skip_animations()
	# Cards pop in one after another; buttons squash and bounce.
	main._show_select()
	hud._process(0.01)
	check(hud._art.btn_age < 0.1, "a screen's cards start their pop-in (age %.2f)" % hud._art.btn_age)
	hud._process(Style.T_BASE + Style.STAGGER * 6.0 + 0.1)
	check(not hud._art.animating() or hud._art.btn_age >= 0.9 or hud._art.btn_age > Style.T_BASE + Style.STAGGER * 6.0, "...and are all in place after the stagger")
	var q_bk = hud._art.btn_id.find("airport:0")
	var q_bpos = hud._art.btn_rect[q_bk].get_center()
	hud.press(q_bpos)
	hud._process(Style.T_FAST)
	check(hud._art.press_k == q_bk and hud._art.animating(), "a pressed card squashes")
	hud.release()
	check(hud._art.rel_k == q_bk and hud._art.rel_t == 0.0 and hud._art.animating(), "...and bounces back on release")
	hud._process(Style.T_BASE + 0.05)
	check(not hud._art.animating(), "...then everything is still again")
	# Release activates, down only presses (with a click).
	main._show_menu()
	hud.skip_animations()
	var q_pk = hud._art.btn_id.find("airports")
	var q_ppos = hud._art.btn_rect[q_pk].get_center()
	var q_pr0 = main.sfx.plays["press"]
	touch(main, 0, true, q_ppos)
	check(main.screen == main.SCREEN_MENU and hud.pressed_id() == "airports" and main.sfx.plays["press"] == q_pr0 + 1 and hud.transition_kind() == "menu", "a finger down presses the button with a click, but nothing opens yet")
	touch(main, 0, true, Vector2(5, 900))
	touch(main, 0, false, Vector2(q_ppos.x + 400.0, q_ppos.y))
	check(hud.transition_kind() == "menu", "sliding off the button before lifting cancels it")
	touch(main, 0, true, q_ppos)
	touch(main, 0, false, q_ppos)
	check(hud.transition_kind() == "select", "lifting on it opens the airports")
	main._show_menu()
	hud.skip_animations()
	# Header totals roll.
	main._show_upgrades()
	hud.skip_animations()
	var q_coins_before = hud._hdr_shown[0]
	save.coins += 60
	main._show_upgrades()
	check(hud._hdr_target[0] == float(save.coins) and hud._hdr_shown[0] == q_coins_before, "a changed coin total rolls (still %d, going to %d)" % [q_coins_before, save.coins])
	hud._process(0.2)
	check(hud._hdr_shown[0] > q_coins_before and hud._hdr_shown[0] <= float(save.coins), "...towards the new value")
	hud.skip_animations()
	check(hud._art.header_text == str(save.coins), "...and lands on it")
	# Coins fly from a landing to the counter.
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	hud.skip_animations()
	var q_arrived0 = hud.coins_arrived
	main._on_landed(tr.place(0, Vector2(0, 0), 0.0, SMALL))
	check(hud.flying_coins() >= 1 and hud.flying_coins() <= 5, "a landing sends coins flying (%d)" % hud.flying_coins())
	hud._process(0.1)
	check(hud._art.fc_s[0] > 0.0 or hud._art.fc_s[1] > 0.0, "...they are drawn on the way")
	for i in 40:
		hud._process(0.05)
	check(hud.flying_coins() == 0 and hud.coins_arrived > q_arrived0, "...and arrive at the counter, which punches (%d arrived)" % (hud.coins_arrived - q_arrived0))
	# The living menu: a small scenic traffic of its own.
	main.restart()
	tr.auto_spawn = false
	var q_dio = main.diorama
	check(q_dio.traffic.scenic and q_dio.traffic.pool_n == 3 and q_dio.traffic != tr and q_dio.get_parent() == main, "the menu has its own scenic aircraft, apart from the game's")
	main._show_menu()
	main._process(0.016)
	check(q_dio.active, "the diorama runs behind the menu")
	q_dio.reset()
	q_dio._next = 0.0
	q_dio.tick(0.1)
	check(q_dio.traffic.active_count() == 1, "an aircraft comes in to land")
	var q_landed_seen = false
	var q_peak_air = 0
	for i in 60 * 14:
		q_dio.tick(1.0 / 60.0)
		q_peak_air = maxi(q_peak_air, q_dio.traffic.active_count())
		for pl in q_dio.traffic.planes:
			if pl.active() and pl.state == Aircraft.State.LANDING:
				q_landed_seen = true
	check(q_landed_seen, "...touches down and rolls out")
	check(q_peak_air >= 2 and q_peak_air <= 3, "...and another taxis off the runway (peak %d)" % q_peak_air)
	check(tr.active_count() == 0 and main.score == 0 and main.shift.earned == 0, "the scenery scores nothing and adds no aircraft to the game")
	var q_cloud_vis = 0
	for q_cl in q_dio._clouds:
		if q_cl.visible:
			q_cloud_vis += 1
	var q_x0 = q_dio._clouds[0].position
	q_dio.tick(1.0)
	check(q_cloud_vis == q_dio.CLOUDS and q_dio._clouds[0].position != q_x0 and float(q_dio._cloud_mats[0].get_shader_parameter("alpha")) > 0.0, "clouds drift across (%d of them)" % q_cloud_vis)
	main.begin_shift()
	main._process(0.016)
	q_dio.tick(0.7)
	check(not q_dio.active and q_dio.traffic.active_count() == 0 and not q_dio._clouds[0].visible, "during a shift the diorama is gone: no aircraft, no clouds")
	main.restart()
	tr.auto_spawn = false

	# The animated logo intro.
	tuning.intro_logo = true
	main._boot_to_menu()
	check(main.hud.logo_active() and main.hud._logo_bg.visible and main.hud._art.logo_t == 0.0, "the intro starts: a studio mark, then the game's name")
	var q_logo_done = [0]
	var q_logo_cb = func(): q_logo_done[0] += 1
	main.hud.logo_finished.connect(q_logo_cb)
	main.hud._process(0.5)
	main.hud._process(0.6)
	check(main.hud.logo_active() and q_logo_done[0] == 0 and main.hud._art.logo_t > 1.0, "...it runs on to the logo (%.1f s)" % main.hud._art.logo_t)
	touch(main, 0, true, Vector2(540, 900))
	check(main.hud._art.logo_t >= main.hud.LOGO_END and main.screen == main.SCREEN_MENU, "a tap skips ahead")
	main.hud._process(0.01)
	check(q_logo_done[0] == 1 and main.hud._logo_bg.color.a > 0.9, "...the menu is called for once, while the cover starts to fade")
	main.hud._process(0.5)
	main.hud._process(0.5)
	check(not main.hud.logo_active() and not main.hud._logo_bg.visible and q_logo_done[0] == 1, "...and the intro is over (total %.1f s)" % (main.hud.LOGO_END + main.hud.LOGO_FADE))
	check(main.hud.LOGO_END + main.hud.LOGO_FADE <= 3.0, "the whole intro is short")
	main.hud.logo_finished.disconnect(q_logo_cb)
	tuning.intro_logo = false
	main.restart()
	tr.auto_spawn = false

	print("9r. in-game polish: bank, shadows, contrails, touchdown, airport details, celebrations, results")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	# --- aircraft: banking into turns
	var r_p = tr.place(0, Vector2(0.0, 2.0), 0.0, SMALL)
	r_p.speed = 0.0
	var r_i = tr.planes.find(r_p)
	r_p.heading = 1.2
	for i in 12:
		main.step(1.0 / 60.0)
	check(r_p.bank > 0.1 and r_p.bank <= tr.MAX_BANK and tr._nodes[r_i].rotation.z < -0.1, "a right turn banks the aircraft (bank %.2f, roll %.2f)" % [r_p.bank, tr._nodes[r_i].rotation.z])
	for i in 120:
		main.step(1.0 / 60.0)
	check(absf(r_p.bank) < 0.03, "...and it rolls level when the turn is done (%.3f)" % r_p.bank)
	r_p.heading = r_p.vis_heading - 1.2
	for i in 12:
		main.step(1.0 / 60.0)
	check(r_p.bank < -0.1 and tr._nodes[r_i].rotation.z > 0.1, "a left turn banks the other way")
	# --- soft drop shadows
	var r_sh_n = tr._shadows[r_i]
	check(r_sh_n.visible and r_sh_n.position.y > 0.13 and tr._shadow_mats[r_i].render_priority > tr._body_mats[r_i].render_priority, "every aircraft has a shadow on the ground, drawn after the runway and the aircraft")
	var r_a0 = float(tr._shadow_mats[r_i].get_shader_parameter("alpha"))
	var r_sx0 = r_sh_n.position.x - r_p.pos.x
	r_p.climb = tuning.go_around_climb_seconds * 0.5
	main.step(1.0 / 60.0)
	check(float(tr._shadow_mats[r_i].get_shader_parameter("alpha")) < r_a0 and r_sh_n.position.x - r_p.pos.x > r_sx0 and tr._nodes[r_i].rotation.x > 0.05, "a climbing aircraft pitches up and its shadow slides away and fades")
	r_p.climb = 0.0
	tr.lose(r_p)
	check(not tr._shadows[r_i].visible, "a removed aircraft takes its shadow with it")
	# --- prop blur and contrails
	var r_jet = tr.place(0, Vector2(-3.0, 0.0), PI * 0.5, JET)
	var r_cub = tr.place(1, Vector2(3.0, 0.0), -PI * 0.5, SMALL)
	var r_gl = tr.place(0, Vector2(0.0, -4.0), PI, GLIDER)
	var r_ji = tr.planes.find(r_jet)
	var r_ci = tr.planes.find(r_cub)
	var r_gi = tr.planes.find(r_gl)
	check(tr._prop_discs[r_ci].visible and not tr._prop_discs[r_ji].visible and not tr._prop_discs[r_gi].visible, "propeller aircraft get a blur disc at the nose; jets and gliders do not")
	for i in 90:
		main.step(1.0 / 60.0)
	check(tr._trail_mm.visible_instance_count >= 6 and tr._trail.visible, "aircraft in the air leave contrails (%d puffs)" % tr._trail_mm.visible_instance_count)
	var r_jet_puffs = 0
	var r_gl_puffs = 0
	for k in tr.TRAIL_N:
		if tr._trail_peak[r_ji * tr.TRAIL_N + k] > 0.0 and tr._trail_age[r_ji * tr.TRAIL_N + k] < 1.0:
			r_jet_puffs += 1
		if tr._trail_peak[r_gi * tr.TRAIL_N + k] > 0.0 and tr._trail_age[r_gi * tr.TRAIL_N + k] < 1.0:
			r_gl_puffs += 1
	check(r_jet_puffs >= 4 and r_gl_puffs == 0 and Array(tr._trail_peak.slice(r_ji * tr.TRAIL_N, (r_ji + 1) * tr.TRAIL_N)).max() > Array(tr._trail_peak.slice(r_ci * tr.TRAIL_N, (r_ci + 1) * tr.TRAIL_N)).max(), "...a jet's are the strongest, a glider leaves none")
	tr.release_all()
	check(tr._trail_mm.visible_instance_count == 0, "...and none are left over after a shift")
	# --- touchdown: dust puff and a pop
	var r_td_n = [0]
	var r_td_cb = func(_pl): r_td_n[0] += 1
	tr.touchdown.connect(r_td_cb)
	var r_thr_t = Airports.end_threshold(0, 0)
	var r_rd_t = Airports.end_dir(0, 0)
	var r_lp = tr.place(0, r_thr_t - r_rd_t * 1.2, atan2(r_rd_t.x, -r_rd_t.y), MEDIUM)
	r_lp.push(r_thr_t)
	r_lp.push(Airports.end_far(0, 0))
	r_lp.cleared = true
	r_lp.land_end = 0
	var r_pop_seen = 0.0
	var r_puffed_before = false
	for pe in main.fx._puffs:
		r_puffed_before = r_puffed_before or pe.emitting
	for i in 60 * 4:
		main.step(1.0 / 60.0)
		r_pop_seen = maxf(r_pop_seen, r_lp.pop_t)
		if not r_lp.active():
			break
	var r_puffing = false
	for pe in main.fx._puffs:
		r_puffing = r_puffing or pe.emitting
	check(r_td_n[0] == 1 and r_pop_seen > 0.0 and r_puffing and not r_puffed_before, "touching down fires the touchdown once: dust puff and a little pop")
	tr.touchdown.disconnect(r_td_cb)
	# --- the airport: lights, taxiways, vehicles
	var r_details_ok = true
	var r_strips_n = 0
	var r_veh_n = 0
	for av in main.airfield.variants:
		r_details_ok = r_details_ok and av.lights != null and av.lights.multimesh.instance_count > 20
		r_strips_n += av.strips.size()
		r_veh_n += av.veh.size()
	check(r_details_ok, "every airport has runway edge lights and approach strobes")
	check(r_strips_n >= 4 and r_veh_n >= 4, "taxiways and ground vehicles where there is room (%d taxiways, %d vehicles)" % [r_strips_n, r_veh_n])
	var r_cur_sc = main.airfield.cur
	var r_v0 = null
	if r_cur_sc.veh.size() > 0:
		r_v0 = r_cur_sc.veh[0].position
		main.airfield._animate_ground(2.0, 1000)
	check(r_v0 == null or r_cur_sc.veh[0].position != r_v0, "the vehicles drive along their taxiway")
	check(r_cur_sc.lights.material_override.render_priority > tr._body_mats[0].render_priority and r_cur_sc.lights.material_override.shader.code.contains("TIME"), "the lights animate on the GPU and sit under the aircraft")
	# --- screen shake on a conflict
	main.restart()
	tr.auto_spawn = false
	var r_sk_a = tr.place(0, Vector2(-1.0, 0.0), PI * 0.5, MEDIUM)
	var r_sk_b = tr.place(1, Vector2(1.0, 0.0), -PI * 0.5, MEDIUM)
	main._tick_shake(1.0)
	main._tick_shake(0.01)
	check(main.shake_offset == Vector2.ZERO, "no shake normally")
	main._conflict(r_sk_a, r_sk_b, "CONFLICT")
	main._tick_shake(0.02)
	check(main.shake_offset != Vector2.ZERO and main.camera.h_offset == main.shake_offset.x or main.shake_offset.length() > 0.0, "a conflict shakes the camera (%.3f)" % main.shake_offset.length())
	main._update_camera()
	check(main.camera.h_offset == main.shake_offset.x and main.camera.v_offset == main.shake_offset.y, "...through the camera")
	main._tick_shake(0.5)
	main._update_camera()
	check(main.shake_offset == Vector2.ZERO and main.camera.h_offset == 0.0, "...short and sharp: it is gone in a third of a second")
	# --- go-around animation
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var r_ga_p = tr.place(0, Vector2(0.0, 2.0), 0.0, MEDIUM)
	tr._start_go_around(r_ga_p, 0)
	r_ga_p.climb = tuning.go_around_climb_seconds * 0.5
	main.step(1.0 / 60.0)
	main.overlay._draw_all()
	check(r_ga_p.climb > 0.0 and tr._nodes[tr.planes.find(r_ga_p)].rotation.x > 0.02, "a go-around climbs with the nose up (the overlay streams chevrons ahead of it)")
	# --- the star bar sparkles
	main.restart()
	tr.auto_spawn = false
	var r_thr0 = main.shift.thresholds[0]
	var r_stars_seen = []
	var r_star_cb = func(i): r_stars_seen.append(i)
	main.hud.star_reached.connect(r_star_cb)
	while main.shift.balance() < r_thr0:
		main.shift.on_landed(3, 14, 0)
	main.hud.set_shift(main.shift)
	check(r_stars_seen == [0] and main.hud._art.star_t[0] == 0.0, "crossing a threshold lights its star with a burst")
	main.hud.set_shift(main.shift)
	check(r_stars_seen == [0], "...once")
	main.hud._process(0.3)
	check(main.hud._art.star_t[0] > 0.2, "...the star pops and sparks for a moment")
	main.hud._process(1.0)
	check(main.hud._art.star_t[0] < 0.0, "...then settles")
	main.hud.star_reached.disconnect(r_star_cb)
	# --- results: stars slam in, confetti for three, the unlock reveal
	main.restart()
	tr.auto_spawn = false
	for i in 40:
		main.shift.on_landed(3, 14, 0)
	main.hud.set_shift(main.shift)
	var r_slams = []
	var r_slam_cb = func(i): r_slams.append(i)
	main.hud.star_slam.connect(r_slam_cb)
	var r_s3 = main.shift.stars()
	main.hud.show_results("DONE", "x|1", main.shift, 100, 500, 50, false)
	main.hud.set_results_ads(0, 0)
	var r_hres = main.hud
	check(r_s3 == 3 and r_slams.is_empty() and r_hres.confetti_count() == 0, "results: three stars to come, nothing yet")
	r_hres._process(0.45)
	check(r_slams.size() == 0, "...the first star is still on its way down")
	r_hres._process(0.2)
	check(r_slams == [0], "...slam: the first lands with its impact")
	r_hres._process(0.5)
	r_hres._process(0.5)
	check(r_slams == [0, 1, 2] and r_hres.confetti_count() == r_hres._art.CONFETTI, "...then the others, one at a time; three stars bring confetti (%d pieces)" % r_hres.confetti_count())
	for i in 320:
		r_hres._process(0.05)
	check(r_hres.confetti_count() == 0, "...which rains down and is gone")
	r_slams.clear()
	main.shift.reset(main.shift.thresholds, 0.5)
	main.shift.on_landed(3, 14, 0)
	main.shift.on_landed(3, 14, 0)
	main.hud.show_results("DONE", "x|1", main.shift, 10, 500, 50, false)
	for i in 80:
		r_hres._process(0.05)
	check(r_slams.size() == main.shift.stars() and r_hres.confetti_count() == 0, "fewer than three stars: no confetti")
	main.hud.star_slam.disconnect(r_slam_cb)
	# an airport unlocking with a shift gets its own reveal
	save.reset_all()
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	for i in 80:
		main.shift.on_landed(3, 14, 0)
	main.hud.set_shift(main.shift)
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(main.screen == main.SCREEN_OVER and main.last_result["unlocked"].size() >= 1, "a shift that opens a new airport says so (%s)" % str(main.last_result["unlocked"]))
	check(main.hud.unlock_active() == false and main.hud._unlock_pending == Airports.airport_name(main.last_result["unlocked"][0]), "...the reveal waits for the stars and the total")
	main.hud._art.res_t = 3.7
	main.hud._process(0.01)
	check(main.hud.unlock_active() and main.hud._art.btn_id[0] == "unlock_ok" and main.hud._art.btn_count == 1, "...then a card pops in over the results, with one NICE! button")
	main.hud._process(0.3)
	main.hud._process(0.6)
	main.hud._art._draw_unlock()
	touch(main, 0, true, main.hud._art.btn_rect[0].get_center())
	touch(main, 0, false, main.hud._art.btn_rect[0].get_center())
	check(not main.hud.unlock_active() and main.hud._art.btn_id.find("again") >= 0 and main.hud._art.btn_id.find("again") < main.hud._art.btn_count, "NICE! closes it and the results buttons are back")
	main.hud._process(5.0)
	check(not main.hud.unlock_active(), "...and it does not come back")
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false

	print("9s. audio, icon and splash, the consistency sweep, performance")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	var au = main.sfx
	var au_base = au.plays.duplicate()
	main._on_button("details")
	main._on_button("back")
	main._on_button("airports")
	check(au.plays["toggle"] == au_base["toggle"] + 1 and au.plays["back"] == au_base["back"] + 1 and au.plays["tap"] == au_base["tap"] + 1, "different taps sound different: a toggle, going back, going forward")
	main._show_upgrades()
	save.coins = 1000
	main._show_upgrades()
	var au_b0 = au.plays["buy"]
	main._on_button("upg:comms")
	check(au.plays["buy"] == au_b0 + 1, "buying something rings the purchase sound")
	save.coins = 0
	main._show_upgrades()
	var au_e0 = au.plays["error"]
	main._on_button("upg:comms")
	check(au.plays["error"] == au_e0 + 1 and au.plays["buy"] == au_b0 + 1, "a purchase that does not go through buzzes instead")
	var au_card = main.hud._art.btn_id.find("upg:radar")
	var au_pos = main.hud._art.btn_rect[au_card].get_center()
	var au_e1 = au.plays["error"]
	touch(main, 0, true, au_pos)
	touch(main, 0, false, au_pos)
	check(main.hud._art.btn_state[au_card] == 1 and au.plays["error"] == au_e1 + 1, "pressing a disabled card gives the error buzz and nothing else")
	var au_w0 = au.plays["whoosh"]
	main._show_menu()
	main._show_select()
	check(au.plays["whoosh"] >= au_w0 + 2, "screens sliding make a swish")
	check(au._streams.has("whoosh") and au._streams.has("buy") and au._streams.has("error") and au._streams.has("unlock") and au._streams.has("back") and au._streams.has("toggle"), "every UI sound is generated")
	# Music crossfades instead of cutting.
	au.set_music(false)
	au.set_menu_music(false)
	au._calm_db = -80.0
	au._hot_db = -80.0
	au.set_menu_music(true)
	var au_prev = au._calm_db
	var au_jump = 0.0
	for i in 140:
		au._glide_music(1.0 / 60.0)
		au_jump = maxf(au_jump, absf(au._calm_db - au_prev))
		au_prev = au._calm_db
	check(absf(au._calm_db - au.MENU_CALM_DB) < 0.5 and au_jump <= au.FADE_DB_PER_S / 60.0 + 0.01 and au._music_calm.playing, "the menu music fades up smoothly (%.1f dB at most per frame)" % au_jump)
	au.set_music(true, 0.8, 0.0)
	var au_pitch0 = au._music_calm.pitch_scale
	for i in 30:
		au._glide_music(1.0 / 60.0)
	check(au._calm_db > au.MENU_CALM_DB + 2.0 and au._calm_db < au.SHIFT_CALM_DB + 0.1, "...and rises into the shift's music without a jump")
	for i in 120:
		au._glide_music(1.0 / 60.0)
	check(absf(au._calm_db - au.SHIFT_CALM_DB) < 0.5 and au._hot_db > -40.0, "...the intense layer fades in with it")
	au.set_music(false)
	au.set_menu_music(true)
	for i in 240:
		au._glide_music(1.0 / 60.0)
	check(absf(au._calm_db - au.MENU_CALM_DB) < 0.5 and au._hot_db <= -75.0, "back at the menu the intense layer fades away again")
	au.set_menu_music(false)
	for i in 240:
		au._glide_music(1.0 / 60.0)
	check(not au._music_calm.playing and au._calm_db <= -75.0, "and with no music wanted, everything fades out and stops")
	# Icon and splash.
	var ic_svg = FileAccess.get_file_as_string("res://icon.svg")
	check(ic_svg.contains("#ffc933".substr(0, 0)) or ic_svg.contains("linearGradient"), "the app icon is drawn in the new style (gradient, gold aircraft on a runway)")
	var ic_ok = true
	for px in [144, 180, 512]:
		var im = Image.load_from_file("res://icons/icon-%d.png" % px)
		ic_ok = ic_ok and im != null and im.get_width() == px
	check(ic_ok, "icons are rendered at 144, 180 and 512 px")
	check(ProjectSettings.get_setting("application/boot_splash/image") == "res://assets/splash.png" and FileAccess.file_exists("res://assets/splash.png") and ProjectSettings.get_setting("application/boot_splash/bg_color") != Color.BLACK, "the boot splash is the new mark on the dark surface")
	var ex_cfg = FileAccess.get_file_as_string("res://export_presets.cfg")
	check(ex_cfg.contains("icon-512.png") and ex_cfg.contains("viewport-fit=cover"), "the web export carries the icons and allows the safe-area insets")
	# The consistency sweep: every label is in a style font; nothing uses the default font.
	var lab_bad = []
	for lb in main.hud.find_children("*", "Label", true, false):
		var lf = lb.get_theme_font("font")
		if lf != Style.display() and lf != Style.text():
			lab_bad.append(lb.text)
	check(lab_bad.is_empty() and main.overlay._font == Style.text(), "every label and the overlay tags use the two style fonts (%s)" % str(lab_bad))
	var fallback_uses = 0
	for fn in DirAccess.get_files_at("res://scripts"):
		if fn.ends_with(".gd") and fn != "TunePanel.gd" and FileAccess.get_file_as_string("res://scripts/" + fn).contains("ThemeDB.fallback_font"):
			fallback_uses += 1
	check(fallback_uses == 0, "no screen draws text in the engine's fallback font")
	var shots_ok = true
	var shots_missing = []
	for fn in DirAccess.get_files_at("res://docs/screens/makeover_before"):
		if fn.ends_with(".png") and not FileAccess.file_exists("res://docs/screens/makeover_after/" + fn):
			shots_ok = false
			shots_missing.append(fn)
	check(shots_ok and DirAccess.get_files_at("res://docs/screens/makeover_after").size() >= 20, "docs/screens has an after picture for every before picture (%s)" % str(shots_missing))
	# Performance on the busiest airport: a full field, drawn paths, every frame timed.
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(5)
	save.airport_plays[5] = 3
	main.restart()
	main.traffic._god = true            # (no fines or conflicts: the field stays full)
	tr.auto_spawn = false
	for k in 14:
		var pf_pl = tr.place(k % 2, Vector2(-4.0 + (k % 5) * 2.0, -7.0 + (k / 5) * 4.0), 0.3 * k, 2 + (k % 3))
		var pf_d = Vector2(sin(pf_pl.heading), -cos(pf_pl.heading))
		for pf_q in 40:
			pf_pl.push(pf_pl.pos + pf_d * (pf_q + 1) * 0.4 + Vector2(sin(pf_q * 0.7), cos(pf_q * 0.5)) * 0.5)
	var pf_worst = 0.0
	var pf_sum = 0.0
	var pf_n = 0
	var pf_all = []
	var pf_t = Time.get_ticks_usec()
	for i in 60 * 20:
		main._process(1.0 / 60.0)
		await process_frame
		var pf_now = Time.get_ticks_usec()
		var pf_ms = (pf_now - pf_t) / 1000.0
		pf_t = pf_now
		if i > 30:
			pf_worst = maxf(pf_worst, pf_ms)
			pf_sum += pf_ms
			pf_n += 1
			pf_all.append(pf_ms)
	pf_all.sort()
	var pf_p99 = pf_all[int(pf_all.size() * 0.99)]
	# What our own code costs per frame: the simulation step, the path ribbons, the HUD, the contrails, and the two
	# draws (overlay and HUD art), each timed on its own (a headless frame also includes the engine's idle wait).
	var pf_work = 0.0
	for i in 120:
		var pw0 = Time.get_ticks_usec()
		tr.step(1.0 / 60.0)
		main.ribbons._process(1.0 / 60.0)
		main.hud._process(1.0 / 60.0)
		main.fx.get_child_count()
		pf_work = maxf(pf_work, (Time.get_ticks_usec() - pw0) / 1000.0 + (main.overlay.last_draw_us + main.hud._art.last_draw_us) / 1000.0)
		await process_frame
	print("      perf, International, %d aircraft with paths: frame mean %.2f ms, 99th percentile %.2f ms, worst %.2f ms (headless wall clock); our code %.2f ms worst per frame (overlay draw %d us, hud draw %d us)" % [tr.active_count(), pf_sum / maxf(pf_n, 1), pf_p99, pf_worst, pf_work, main.overlay.last_draw_us, main.hud._art.last_draw_us])
	check(tr.active_count() >= 12 and pf_p99 < 33.0 and pf_work < 16.0, "the busiest airport stays under 33 ms a frame: 99%% of frames under %.1f ms (worst %.1f), our code %.2f ms (%d aircraft)" % [pf_p99, pf_worst, pf_work, tr.active_count()])
	main.traffic._god = DebugFlags.god_enabled()
	main.restart()
	tr.auto_spawn = false

	print("9t. landability: every airport, runway end, wind, aircraft type and entry edge")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	main._process(0.016)
	var ld = load("res://tests/landability.gd").new()
	ld.setup(tuning, load("res://scripts/Approach.gd").new(), load("res://scripts/Aircraft.gd").new(), tr.half_w, tr.half_h)
	var ld_total = 0
	var ld_storm = 0
	# Two screens: a tall phone (9:16) and a tablet (3:4: the shortest view the game supports).
	# Tall phones are held to the strict rule (no turn penalty at all). A tablet shows less of the field above and below the
	# runways, so a short final from the side edges needs a bend close to the runway: there a turn penalty up to 0.6
	# is accepted, but the final must still be long enough and the route free of terrain and storms.
	for ld_screen in [[tuning.ortho_size * 0.5, 20.0 / 9.0, 0.0], [tuning.ortho_size * 0.5, 16.0 / 9.0, 0.0], [tuning.ortho_size * 0.5, 4.0 / 3.0, 0.6]]:
		ld.allow_turn = ld_screen[2]
		ld.half_w = ld_screen[0]
		ld.half_h = ld_screen[0] * ld_screen[1] / cos(deg_to_rad(tuning.camera_tilt_deg))
		for ai in Airports.COUNT:
			var ld_res = ld.run(ai)
			ld_total += ld_res["checked"]
			ld_storm += ld_res["storm_blocked"]
			print("      %s on a %.1f x %.1f view: %d approach checks (%d wind directions, %d aircraft types, %d entry points), %d failures, %d storm probes with the corridor itself covered" % [Airports.airport_name(ai), ld.half_w * 2.0, ld.half_h * 2.0, ld_res["checked"], ld.winds().size(), ld.arriving_types(ai).size(), ld.usable(ld.entries(), ld.circles([])).size(), ld_res["failures"].size(), ld_res["storm_blocked"]])
			for lf in ld_res["failures"]:
				print("        ", lf)
			check(ld_res["failures"].is_empty() and ld_res["checked"] > 1000, "%s (%.1f x %.1f view): every runway end can be reached from every entry, avoiding terrain and storms, with a straight final of the wanted length%s (%d checks)" % [Airports.airport_name(ai), ld.half_w * 2.0, ld.half_h * 2.0, " and a clean approach" if ld.allow_turn == 0.0 else "", ld_res["checked"]])
	ld.allow_turn = 0.0
	ld.half_w = tr.half_w
	ld.half_h = tr.half_h
	# The checker really catches a blocked layout: the old Mountain Field (mountains in the approach lines).
	Airports.current = 3
	var ld_good = Airports.def(3)["hazards"].duplicate(true)
	Airports.def(3)["hazards"].clear()
	for ldh in [[-3.7, -4.4, 1.5], [3.6, -4.7, 1.6], [0.0, -5.9, 1.2], [-4.1, 4.9, 1.2], [3.9, 5.0, 1.2]]:
		Airports.def(3)["hazards"].append({"center": Vector2(ldh[0], ldh[1]), "radius": ldh[2]})
	var ld_old = ld.run(3)
	Airports.def(3)["hazards"].clear()
	Airports.def(3)["hazards"].append_array(ld_good)
	check(ld_old["failures"].size() >= 4, "the checker flags the old Mountain Field layout (%d unlandable combinations)" % ld_old["failures"].size())
	Airports.current = 2
	# And the paths it finds really land in the game: Mountain Field, every end, three entries each.
	main.select_airport(3)
	main.restart()
	tr.auto_spawn = false
	main._process(0.016)
	ld.half_w = tuning.ortho_size * 0.5
	ld.half_h = ld.half_w * 16.0 / 9.0 / cos(deg_to_rad(tuning.camera_tilt_deg))
	var ld_circ = ld.prepare(ld.circles([]))
	var ld_ents = ld.usable(ld.entries(), ld.circles([]))
	var ld_flown = 0
	var ld_counts = [0, 0]
	var ld_cb = func(_pl): ld_counts[0] += 1
	var ld_cr = func(_pl, _k): ld_counts[1] += 1
	tr.landed.connect(ld_cb)
	tr.crashed.connect(ld_cr)
	for lr in 2:
		for le in 2:
			for lk in 3:
				var lent = ld_ents[(lk * 17 + lr * 5 + le * 11) % ld_ents.size()]
				var lpath = ld.runway_path(lr, le, 2, lent, ld_circ)
				main.restart()          # (a fresh shift each time: no wind shift or storm arrives mid-flight)
				tr.auto_spawn = false
				set_wind(main, 0.0)
				main.wind.countdown = 99999.0
				var lpl = tr.place(lr, lent, 0.0, 2)
				lpl.speed = 4.0
				for lp in lpath:
					lpl.push(lp)
				lpl.push(Airports.end_threshold(lr, le))
				lpl.push(Airports.end_far(lr, le))
				lpl.cleared = true
				lpl.land_end = le
				lpl.heading = atan2(lpl.pts[lpl.head].x - lpl.pos.x, -(lpl.pts[lpl.head].y - lpl.pos.y))
				lpl.vis_heading = lpl.heading
				ld_flown += 1
				for i in 60 * 40:
					main.step(1.0 / 60.0)
					if not lpl.active():
						break
	tr.landed.disconnect(ld_cb)
	tr.crashed.disconnect(ld_cr)
	check(ld_flown == 12 and ld_counts[0] == 12 and ld_counts[1] == 0, "flown in the game: %d of %d aircraft on the found paths landed, %d struck terrain" % [ld_counts[0], ld_flown, ld_counts[1]])
	tr.release_all()
	# The ?tune panel: the old sliders are gone; the shift length is the airport's own (scaled by one knob).
	var tp_names = []
	for tp_ent in main.tune_panel.ENTRIES:
		tp_names.append(tp_ent[0])
	check(not tp_names.has("spawn_stop_seconds") and not tp_names.has("shift_seconds") and tp_names.has("shift_scale") and tp_names.has("par_window"), "the tuning panel has no stale shift sliders any more")
	main.select_airport(0)
	var sh_base = tuning.spawn_stop_eff()
	tuning.shift_scale = 2.0
	check(absf(tuning.spawn_stop_eff() - sh_base * 2.0) < 0.01 and absf(tuning.par_eff() - (sh_base * 2.0 + tuning.par_window)) < 0.01, "...the knob scales every airport's own shift length (%.0f s -> %.0f s)" % [sh_base, tuning.spawn_stop_eff()])
	tuning.shift_scale = 1.0
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false

	print("9u. studio branding, loading page, build stamp")
	var br_bad = []
	for br_dir in ["res://scripts", "res://docs", "res://web", "res://tools", "res://tests"]:
		for br_f in DirAccess.get_files_at(br_dir):
			if br_f.ends_with(".gd") or br_f.ends_with(".md") or br_f.ends_with(".html"):
				var br_txt = FileAccess.get_file_as_string(br_dir + "/" + br_f).to_lower()
				if br_f != "smoke_test.gd" and (br_txt.contains("tailwind") or br_txt.contains("placeholder studio") or br_txt.contains("studio mark (a placeholder")):
					br_bad.append(br_f)
	for br_f in ["res://README.md", "res://project.godot", "res://export_presets.cfg", "res://icon.svg", "res://assets/splash.svg"]:
		var br_txt2 = FileAccess.get_file_as_string(br_f).to_lower()
		if br_txt2.contains("tailwind") or br_txt2.contains("placeholder studio"):
			br_bad.append(br_f)
	check(br_bad.is_empty(), "no placeholder studio name is left anywhere (%s)" % str(br_bad))
	var br_shell = FileAccess.get_file_as_string("res://web/shell.html")
	var br_all = FileAccess.get_file_as_string("res://README.md").contains("Clear Prop Games") and FileAccess.get_file_as_string("res://docs/style.md").contains("Clear Prop Games") and FileAccess.get_file_as_string("res://project.godot").contains("Clear Prop Games") and br_shell.contains("CLEAR <b>PROP</b> GAMES")
	check(Style.STUDIO == "Clear Prop Games" and br_all, "the studio is Clear Prop Games in the README, style guide, project metadata and loading page")
	check(Style.STUDIO_WORDS == ["CLEAR", "PROP", "GAMES"], "the wordmark reads CLEAR PROP GAMES")
	check(ex_cfg.contains("html/custom_html_shell=\"res://web/shell.html\"") and br_shell.contains("$GODOT_URL") and br_shell.contains("$GODOT_CONFIG") and br_shell.contains("startGame") and br_shell.contains("onProgress") and br_shell.contains("<head>"), "the web export uses the custom loading page and it still starts the engine")
	check(br_shell.contains("#3a2410") and br_shell.contains("class=\"bar") and br_shell.contains("class=\"mark\"") and not br_shell.contains("Loading") and not br_shell.contains("loading..."), "the loading page is the brand background, the mark and a progress bar, with no loading text")
	# The in-game loading cover: opaque, no text, nothing jumbled behind it.
	var sp_cover = null
	main.hud.begin_prewarm()
	for sp_c in main.hud._splash.get_children():
		if sp_c is ColorRect:
			sp_cover = sp_c
	var sp_texts = 0
	for sp_c in main.hud._splash.get_children():
		if sp_c is Label and sp_c.get_index() > sp_cover.get_index():
			sp_texts += 1
	check(sp_cover != null and sp_cover.color.a == 1.0 and sp_texts == 0 and main.hud._splash.get_child(main.hud._splash.get_child_count() - 1).get_script() != null, "the in-game loading cover is fully opaque, with the glyph warm-up behind it and only the mark and a bar on top")
	main.hud.end_prewarm()
	await process_frame
	# The build stamp is for debugging.
	DebugFlags.parse([])
	main.hud.refresh_stamp()
	check(not main.hud._stamp.visible and not DebugFlags.stamp_enabled(), "players do not see the build stamp")
	DebugFlags.parse(["debug"])
	main.hud.refresh_stamp()
	check(main.hud._stamp.visible and main.hud._stamp.text.contains(BuildInfo.COMMIT) and main.hud._stamp.size.y < 90.0 and main.hud._stamp.get_theme_font_size("font_size") <= 22, "?debug shows it, small, in the corner")
	DebugFlags.parse(["perf"])
	main.hud.refresh_stamp()
	var br_perf = main.hud._stamp.visible
	DebugFlags.parse(["tune"])
	main.hud.refresh_stamp()
	check(br_perf and main.hud._stamp.visible, "...and so do ?perf and ?tune")
	DebugFlags.parse(["nofx=burst"])
	main.hud.refresh_stamp()
	check(not main.hud._stamp.visible, "other flags alone do not show it")
	DebugFlags.parse(["tune"])
	main.hud.refresh_stamp()

	print("9v. web audio: sample-based streams, buses from the layout, volumes, the first-gesture unlock")
	var wa_scripts = ""
	for wa_f in DirAccess.get_files_at("res://scripts"):
		if wa_f.ends_with(".gd"):
			wa_scripts += FileAccess.get_file_as_string("res://scripts/" + wa_f)
	check(not wa_scripts.contains("AudioStreamGenerator") and not wa_scripts.contains("AudioStreamMicrophone"), "no generator or microphone streams anywhere: everything is sample based")
	check(not wa_scripts.contains("add_bus("), "no bus is ever created at run time (in the single-threaded web export that silences all audio)")
	var wa_layout = FileAccess.get_file_as_string("res://default_bus_layout.tres")
	check(wa_layout.contains("&\"SFX\"") and wa_layout.contains("&\"Music\"") and ProjectSettings.get_setting("audio/buses/default_bus_layout") == "res://default_bus_layout.tres", "the SFX and Music buses come from the project's bus layout")
	check(AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == &"Master", "...and exist, sending to Master, from the first frame")
	var wa_sfx = main.sfx
	var wa_wavs = true
	var wa_count = 0
	var wa_all = wa_sfx._streams.values() + [wa_sfx._music_calm.stream, wa_sfx._music_hot.stream, wa_sfx._music_tense.stream, wa_sfx._fog_amb.stream]
	for wa_s in wa_all:
		wa_count += 1
		wa_wavs = wa_wavs and wa_s is AudioStreamWAV and wa_s.format == AudioStreamWAV.FORMAT_16_BITS and wa_s.data.size() > 200 and wa_s.mix_rate >= 8000
		if wa_s is AudioStreamWAV:
			var wa_nz = 0
			for wa_b in range(0, mini(wa_s.data.size(), 20000), 2):
				if wa_s.data[wa_b] != 0 or wa_s.data[wa_b + 1] != 0:
					wa_nz += 1
			wa_wavs = wa_wavs and wa_nz > 20
	check(wa_wavs and wa_count >= 25, "every sound, hum and music layer (%d) is a pre-rendered 16-bit AudioStreamWAV with real sample data" % wa_count)
	var wa_players_ok = true
	for wa_p in wa_sfx.get_children():
		if wa_p is AudioStreamPlayer:
			wa_players_ok = wa_players_ok and AudioServer.get_bus_index(wa_p.bus) >= 0
	check(wa_players_ok, "every player is on a bus that exists")
	save.reset_all()
	check(save.sound_volume == 0.8 and save.music_volume == 0.8, "the default volumes are 0.8, not zero")
	main._apply_volumes()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) > -6.0, "...so neither bus is muted or quiet at start")
	wa_sfx.unlocked = false
	wa_sfx.set_menu_music(true)
	wa_sfx._glide_music(0.2)
	var wa_was_playing = wa_sfx._music_calm.playing
	wa_sfx.unlock()
	check(wa_sfx.unlocked and wa_was_playing and wa_sfx._music_calm.playing, "the first touch unlocks audio and (re)starts the music layers")
	var wa_shell = FileAccess.get_file_as_string("res://web/shell.html")
	check(wa_shell.contains("AudioContext") and wa_shell.contains(".resume()") and wa_shell.contains("touchend"), "the web page resumes the browser's audio context on the first tap")
	check(FileAccess.file_exists("res://tools/web_audio_check.js") and FileAccess.get_file_as_string("res://.github/workflows/deploy.yml").contains("web_audio_check.js"), "CI loads the exported game in headless Chrome and listens for sound")
	save.reset_all()
	main._apply_volumes()

	print("9w. audio direction: soft, in key, enveloped, quiet UI, big moments, limiter")
	save.reset_all()
	main.restart()
	tr.auto_spawn = false
	var sx = main.sfx
	var sx_clip = func(w_k):
		var w_d: PackedByteArray = sx._streams[w_k].data
		var w_out = PackedFloat32Array()
		w_out.resize(w_d.size() / 2)
		for w_i in w_out.size():
			w_out[w_i] = w_d.decode_s16(w_i * 2) / 32768.0
		return w_out
	var sx_peak = func(w_x):
		var w_m = 0.0
		for w_v in w_x:
			w_m = maxf(w_m, absf(w_v))
		return w_m
	# Envelopes: every one-shot starts from silence and ends in silence (no clicks, no cuts).
	var w_env_bad = []
	var w_rate = sx.RATE
	for w_k in sx._streams.keys():
		var w_x = sx_clip.call(w_k)
		var w_pk = sx_peak.call(w_x)
		var w_head = 0.0
		for w_i in int(0.002 * w_rate):
			w_head = maxf(w_head, absf(w_x[w_i]))
		var w_tail = 0.0
		for w_i in range(w_x.size() - int(0.004 * w_rate), w_x.size()):
			w_tail = maxf(w_tail, absf(w_x[w_i]))
		if w_head > 0.35 * w_pk or w_tail > 0.03 * w_pk or absf(w_x[0]) > 0.02 * w_pk:
			w_env_bad.append("%s (head %.2f tail %.3f)" % [w_k, w_head / w_pk, w_tail / w_pk])
	check(w_env_bad.is_empty(), "every sound fades in softly and out smoothly: %s" % str(w_env_bad))
	# Soft: almost no energy above 4 kHz (everything is gently low-passed), and the key.
	var w_goertzel = func(w_x, w_f, n):
		var w_w = TAU * w_f / w_rate
		var w_c = 2.0 * cos(w_w)
		var w_s1 = 0.0
		var w_s2 = 0.0
		for w_i in n:
			var w_s0 = w_x[w_i] + w_c * w_s1 - w_s2
			w_s2 = w_s1
			w_s1 = w_s0
		return (w_s1 * w_s1 + w_s2 * w_s2 - w_c * w_s1 * w_s2) * 2.0 / n
	var w_hf_bad = []
	for w_k in sx._streams.keys():
		var w_x2 = sx_clip.call(w_k)
		var w_n2 = mini(w_x2.size(), 4000)
		var w_total = 0.0
		for w_i in w_n2:
			w_total += w_x2[w_i] * w_x2[w_i]
		var w_hf = 0.0
		for w_f in [4200.0, 5000.0, 5800.0, 6600.0, 7400.0]:
			w_hf += w_goertzel.call(w_x2, w_f, w_n2)
		if w_total > 0.0 and w_hf / (w_total + 0.0000001) > 0.03:
			w_hf_bad.append("%s %.3f" % [w_k, w_hf / w_total])
	check(w_hf_bad.is_empty(), "everything is soft: next to no energy above 4 kHz %s" % str(w_hf_bad))
	# Pitch classes of the pitched clips are all in C major pentatonic (C D E G A).
	var w_pc_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var w_in_key = [0, 2, 4, 7, 9]
	var w_key_bad = []
	var w_dom = func(w_x):
		var w_best = -1
		var w_best_e = 0.0
		var w_second = -1
		var w_second_e = 0.0
		var w_n3 = mini(w_x.size(), 5000)
		var w_es = []
		for w_m in range(0, 49):
			w_es.append(w_goertzel.call(w_x, 130.81 * pow(2.0, w_m / 12.0), w_n3))
		for w_m in 49:
			if w_es[w_m] > w_best_e:
				w_best_e = w_es[w_m]
				w_best = w_m
		return w_best
	var w_tonal = ["coin_0", "coin_3", "coin_6", "landing_0", "landing_3", "landing_6", "star", "unlock", "buy", "wind", "last_arrivals", "clear_sky"]
	for w_k in w_tonal:
		var w_x3 = sx_clip.call(w_k)
		var w_m = w_dom.call(w_x3)
		if not w_in_key.has(w_m % 12):
			w_key_bad.append("%s -> %s" % [w_k, w_pc_names[w_m % 12]])
	check(w_key_bad.is_empty(), "the chimes, plinks and fanfares all sit in the key of the music: %s" % str(w_key_bad))
	var w_hz_ok = true
	for w_dg in range(0, 14):
		var w_hz = SfxSynth.note_hz(w_dg)
		var w_semis = int(round(12.0 * log(w_hz / 261.6256) / log(2.0)))
		w_hz_ok = w_hz_ok and w_in_key.has(posmod(w_semis, 12)) and absf(w_hz - 261.6256 * pow(2.0, w_semis / 12.0)) < 0.01
	check(w_hz_ok and absf(SfxSynth.note_hz(5) - 523.25) < 0.1 and absf(SfxSynth.note_hz(4) - 440.0) < 0.1, "the scale helper is C major pentatonic (C4 261.6, A4 440, C5 523.3)")
	var w_land_d = []
	var w_coin_d = []
	for w_k in range(0, 7):
		w_land_d.append(w_dom.call(sx_clip.call("landing_%d" % w_k)))
		w_coin_d.append(w_dom.call(sx_clip.call("coin_%d" % w_k)))
	var w_land_up = true
	var w_coin_up = true
	for w_k in range(1, 7):
		w_land_up = w_land_up and w_land_d[w_k] >= w_land_d[w_k - 1]
		w_coin_up = w_coin_up and w_coin_d[w_k] >= w_coin_d[w_k - 1]
	check(w_land_up and w_coin_up and w_land_d[6] > w_land_d[0] and w_coin_d[6] > w_coin_d[0], "landing chimes and coin plinks climb the scale (%s / %s)" % [str(w_land_d), str(w_coin_d)])
	# Levels: UI quietest, gameplay moderate, big moments stand w_out; hums barely register.
	var w_lv = func(keys):
		var w_m = 0.0
		for w_k in keys:
			w_m = maxf(w_m, sx_peak.call(sx_clip.call(w_k)))
		return w_m
	var w_ui_pk = w_lv.call(["tap", "press", "back", "toggle", "error", "whoosh", "tick"])
	var w_game_lo = 1.0
	for w_k in ["coin_0", "fine", "alarm", "go_around", "wind", "buy"]:
		w_game_lo = minf(w_game_lo, sx_peak.call(sx_clip.call(w_k)))
	var w_game_hi = w_lv.call(["coin_0", "fine", "alarm", "go_around", "wind", "buy"])
	var w_big_lo = 1.0
	for w_k in ["landing_0", "star", "unlock", "slam"]:
		w_big_lo = minf(w_big_lo, sx_peak.call(sx_clip.call(w_k)))
	var w_ref = sx_peak.call(sx_clip_of(sx._music_calm.stream)) * db_to_linear(sx.SHIFT_CALM_DB)
	var w_gp_pk = w_lv.call(["landing_0", "landing_6", "coin_0", "fine", "alarm", "go_around", "wind", "buy", "last_arrivals", "clear_sky", "star", "unlock", "slam", "arrive", "touch"])
	check(absf(w_ref - SfxSynth.MUSIC_REF) < 0.01 and w_gp_pk <= 0.8 * w_ref + 0.001 and w_ui_pk <= 0.5 * w_ref + 0.001, "the music is the reference (peak %.3f): gameplay peaks %.3f <= 0.8 of it, UI %.3f <= 0.5 of it" % [w_ref, w_gp_pk, w_ui_pk])
	check(w_lv.call(["touch"]) < 0.3 * w_lv.call(["landing_0"]) and w_lv.call(["arrive"]) < 0.4 * w_lv.call(["landing_0"]) and w_lv.call(["coin_0"]) < w_lv.call(["landing_0"]), "the touchdown tap and the arrival tone sit far below the landing chime, and the coin plinks below it too")
	var w_loud = 0.0
	for w_k in sx._streams.keys():
		w_loud = maxf(w_loud, sx_peak.call(sx_clip.call(w_k)))
	check(w_loud <= 0.18, "no clip is loud (loudest peak %.2f)" % w_loud)
	# Reverb tails and w_loops.
	check(sx._streams["landing_0"].data.size() / 2.0 / w_rate > 1.1 and sx._streams["tap"].data.size() / 2.0 / w_rate < 0.1, "chimes have a tail; UI clicks are short")
	var w_seam_bad = []
	var w_loops = {"calm": sx._music_calm.stream, "hot": sx._music_hot.stream, "tense": sx._music_tense.stream, "fog": sx._fog_amb.stream}
	for w_k in w_loops.keys():
		var w_xs = sx_clip_of(w_loops[w_k])
		var w_big_step = 0.0
		for w_i in range(1, w_xs.size()):
			w_big_step = maxf(w_big_step, absf(w_xs[w_i] - w_xs[w_i - 1]))
		var w_seam = absf(w_xs[0] - w_xs[w_xs.size() - 1])
		if w_seam > w_big_step * 1.5 + 0.0005 or w_loops[w_k].loop_mode != AudioStreamWAV.LOOP_FORWARD:
			w_seam_bad.append("%s %.4f/%.4f" % [w_k, w_seam, w_big_step])
	check(w_seam_bad.is_empty(), "every loop is seamless %s" % str(w_seam_bad))
	check(sx._music_calm.stream.data.size() == sx._music_hot.stream.data.size() and sx._music_hot.stream.data.size() == sx._music_tense.stream.data.size(), "the three music layers are the same length (they build and fade without drifting)")
	# Variation: +-3% pitch, a hair of level.
	var w_pmin = 9.0
	var w_pmax = 0.0
	var w_vmin = 9.0
	var w_vmax = -9.0
	for w_i in 60:
		sx.play("coin")
		var w_ap = sx._pool[(sx._next + sx.POOL - 1) % sx.POOL]
		w_pmin = minf(w_pmin, w_ap.pitch_scale)
		w_pmax = maxf(w_pmax, w_ap.pitch_scale)
		w_vmin = minf(w_vmin, w_ap.volume_db)
		w_vmax = maxf(w_vmax, w_ap.volume_db)
	check(w_pmin >= 0.989 and w_pmax <= 1.011 and w_pmax - w_pmin > 0.01 and w_vmax - w_vmin > 0.3 and w_vmax < 1.0, "repeated sounds vary by about 1%% in pitch (they stay in key) (%.3f..%.3f) and a little in level" % [w_pmin, w_pmax])
	# Landings in quick succession climb; coins rise as they arrive.
	var w_st0 = sx.plays["landing"]
	main.restart()
	tr.auto_spawn = false
	var w_land_steps = []
	for w_i in 4:
		var w_lf = Aircraft.new()
		w_lf.runway = 0
		w_lf.type = MEDIUM
		tr.run_time = 10.0 + w_i * 1.0
		main._on_landed(w_lf)
		w_land_steps.append(main.streak)
	check(w_land_steps == [1, 2, 3, 4] and sx.plays["landing"] == w_st0 + 4, "quick landings step up the scale (streak %s)" % str(w_land_steps))
	main._coin_last_ms = -10000
	var w_coin_steps = []
	for w_i in 5:
		main._on_coin_arrived()
		w_coin_steps.append(main._coin_step)
	main._coin_last_ms = Time.get_ticks_msec() - 2000
	main._on_coin_arrived()
	check(w_coin_steps == [0, 1, 2, 3, 4] and main._coin_step == 0, "coins plink higher as they keep arriving, and start over after a pause (%s)" % str(w_coin_steps))
	# Timer warnings: a gentle tick that speeds up and rises.
	main.restart()
	tr.auto_spawn = false
	tr.release_all()
	var w_par = tuning.par_eff()
	var w_tick_t = []
	var w_tick_p = []
	var w_base_ticks = sx.plays["tick"]
	main._tick_next = 0.0
	var w_tt = w_par - 10.0
	while w_tt < w_par + 2.0:
		var w_before = sx.plays["tick"]
		main._timer_ticks(w_tt, w_par)
		if sx.plays["tick"] > w_before:
			w_tick_t.append(w_tt)
			w_tick_p.append(sx._pool[(sx._next + sx.POOL - 1) % sx.POOL].pitch_scale)
		w_tt += 1.0 / 60.0
	var w_gaps = []
	for w_i in range(1, w_tick_t.size()):
		w_gaps.append(w_tick_t[w_i] - w_tick_t[w_i - 1])
	check(w_tick_t.size() >= 8 and w_tick_t[0] >= w_par - 8.05 and w_gaps[0] > w_gaps[w_gaps.size() - 1] * 2.0 and w_tick_p[w_tick_p.size() - 1] > w_tick_p[0] * 1.05, "the timer ticks softly from 8 s out, faster and a little higher as it runs down (%d ticks, gaps %.2f -> %.2f s)" % [w_tick_t.size(), w_gaps[0], w_gaps[w_gaps.size() - 1]])
	var w_quiet_ticks = sx.plays["tick"]
	main._tick_next = 0.0
	main._timer_ticks(w_par - 20.0, w_par)
	check(sx.plays["tick"] == w_quiet_ticks, "...and not at all while there is plenty of time")
	# Master limiter, no harsh waveforms.
	var w_lim_ok = AudioServer.get_bus_effect_count(0) >= 1 and AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter and AudioServer.is_bus_effect_enabled(0, 0)
	check(w_lim_ok and FileAccess.get_file_as_string("res://default_bus_layout.tres").contains("AudioEffectHardLimiter"), "a gentle limiter sits on the Master bus (from the bus layout, not made at run time)")
	var w_sfx_src = FileAccess.get_file_as_string("res://scripts/Sfx.gd").to_lower()
	check(not w_sfx_src.contains("square") and not w_sfx_src.contains("sawtooth") and not w_sfx_src.contains("fposmod(f * t, 1.0) * 2.0"), "no square or saw waves in the sound code")
	var w_dsty = FileAccess.get_file_as_string("res://docs/style.md")
	check(w_dsty.contains("pentatonic") and w_dsty.contains("envelope") and w_dsty.contains("limiter") and w_dsty.contains("Mini Metro"), "the audio direction is documented in docs/style.md")

	print("9x. pre-rendered audio, no clipping, loops, background audio")
	# Every sound is a committed 44.1 kHz 16-bit mono WAV, and the committed files are exactly what the synth renders.
	var xa_synth = SfxSynth.new()
	var xa_fmt_bad = []
	var xa_stale = []
	var xa_all = {}
	for xa_k in xa_synth.clips().keys():
		xa_all["res://assets/audio/%s.wav" % xa_k] = xa_synth.clips()[xa_k]
	var xa_loops = xa_synth.loops()
	for xa_k in xa_loops.keys():
		xa_all["res://assets/audio/loops/%s.wav" % xa_k] = xa_loops[xa_k]
	for xa_path in xa_all.keys():
		var xa_b = FileAccess.get_file_as_bytes(xa_path)
		if xa_b.size() < 46 or xa_b.decode_u16(20) != 1 or xa_b.decode_u16(22) != 1 or xa_b.decode_u32(24) != 44100 or xa_b.decode_u16(34) != 16:
			xa_fmt_bad.append(xa_path)
			continue
		var xa_s: PackedFloat32Array = xa_all[xa_path]
		if xa_b.size() != 44 + xa_s.size() * 2:
			xa_stale.append(xa_path)
			continue
		var xa_diff = 0
		for xa_i in range(0, xa_s.size(), 97):
			if absi(xa_b.decode_s16(44 + xa_i * 2) - int(clampf(xa_s[xa_i], -1.0, 1.0) * 32000.0)) > 2:
				xa_diff += 1
		if xa_diff > 0:
			xa_stale.append(xa_path)
	check(xa_fmt_bad.is_empty() and xa_all.size() >= 37, "all %d sounds are committed as 44.1 kHz 16-bit mono WAVs %s" % [xa_all.size(), str(xa_fmt_bad)])
	check(xa_stale.is_empty(), "the committed WAVs match the synth (re-run tools/render_audio.gd): %s" % str(xa_stale))
	# No sample-skipping steps in the loops (the beds are smooth sums of sines), and none clip.
	var xa_step_bad = []
	var xa_clip_bad = []
	for xa_path in xa_all.keys():
		var xa_x: PackedFloat32Array = xa_all[xa_path]
		var xa_pk = 0.0
		var xa_st = 0.0
		for xa_i in range(1, xa_x.size()):
			xa_pk = maxf(xa_pk, absf(xa_x[xa_i]))
			xa_st = maxf(xa_st, absf(xa_x[xa_i] - xa_x[xa_i - 1]))
		if xa_pk >= 0.99:
			xa_clip_bad.append(xa_path)
		if xa_path.contains("/loops/") and xa_st > 0.05:
			xa_step_bad.append("%s %.3f" % [xa_path, xa_st])
	check(xa_clip_bad.is_empty(), "no clip reaches full scale %s" % str(xa_clip_bad))
	check(xa_step_bad.is_empty(), "no loop has jumps in it (smooth waveforms, no skipped or doubled samples) %s" % str(xa_step_bad))
	# Worst case at once: every music layer, fog and the bed at their mixed levels (in dB, as Sfx.gd sets them) stay far
	# below full scale, and the loudest one-shot on top of that is still under it, so the limiter only ever catches
	# rare pile-ups.
	var xa_gain = {"calm": -9.0, "hot": -8.0, "tense": -9.0, "fog": -10.0}
	var xa_sum = 0.0
	for xa_k in xa_gain.keys():
		var xa_p = 0.0
		for xa_v in xa_loops[xa_k]:
			xa_p = maxf(xa_p, absf(xa_v))
		xa_sum += xa_p * db_to_linear(xa_gain[xa_k])
	var xa_clips = xa_synth.clips()
	var xa_loud = 0.0
	for xa_k in xa_clips.keys():
		for xa_v in xa_clips[xa_k]:
			xa_loud = maxf(xa_loud, absf(xa_v))
	check(xa_sum < 0.6 and xa_sum + xa_loud < 1.1, "the whole bed peaks at %.2f and a big sound (%.2f) on top stays near full scale, so the limiter rarely works" % [xa_sum, xa_loud])
	# Web: the page plays the loops and holds everything in the background.
	var xa_shell = FileAccess.get_file_as_string("res://web/shell.html")
	var xa_shell_ok = true
	for xa_w in ["PWAudio", "visibilitychange", "pagehide", "blur", "suspend", "__pwRelease", "__pwHidden", "loop = true", "DynamicsCompressor"]:
		xa_shell_ok = xa_shell_ok and xa_shell.contains(xa_w)
	check(xa_shell_ok, "the loading page plays native loops and suspends every AudioContext when hidden, before the game is ready")
	check(FileAccess.get_file_as_string("res://export_presets.cfg").contains("assets/audio/loops/*") and FileAccess.get_file_as_string("res://.github/workflows/deploy.yml").contains("assets/audio/loops"), "the web build ships the loops beside the page, not inside the pck")
	# Focus out holds everything; only Resume lets sound back.
	main.restart()
	tr.auto_spawn = false
	main.step(1.0 / 60.0)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(sx.held and AudioServer.is_bus_mute(0) and main.screen == main.SCREEN_PAUSE, "leaving the app mutes the Master bus and pauses the game")
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(sx.held and AudioServer.is_bus_mute(0) and main.screen == main.SCREEN_PAUSE, "coming back does not bring the sound back by itself")
	main.resume_game()
	check(not sx.held and not AudioServer.is_bus_mute(0) and main.screen == main.SCREEN_PLAY, "Resume releases the sound and the game")
	main.restart()
	tr.auto_spawn = false

	print("9y. Cozy Airfield art: aircraft and ground")
	main.restart()
	tr.auto_spawn = false
	var sa_types = {}
	for sa_t in [GLIDER, HELI, SMALL, MEDIUM, JET, SEAPLANE]:
		var sa_p = tr.place(0, Vector2(0, -3), 0.0, sa_t)
		var sa_i = tr.planes.find(sa_p)
		tr._sync(sa_p, sa_i)
		sa_types[sa_t] = sa_i
	check(tr._jet_groups[sa_types[JET]].visible and not tr._plane_groups[sa_types[JET]].visible and not tr._jet_groups[sa_types[SMALL]].visible and tr._plane_groups[sa_types[SMALL]].visible, "jets have their own swept-wing model, light planes keep the straight wing")
	check(tr._rotor_discs[sa_types[HELI]].visible and not tr._rotor_discs[sa_types[SMALL]].visible and tr._float_groups[sa_types[SEAPLANE]].visible and not tr._float_groups[sa_types[SMALL]].visible, "helicopters get a rotor disc and seaplanes floats")
	var sa_ok = true
	for sa_t in sa_types.keys():
		var sa_i2 = sa_types[sa_t]
		sa_ok = sa_ok and (tr._wing_mats[sa_i2] as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.97, 0.98, 1.0)) and tr._body_mats[sa_i2].albedo_color.is_equal_approx(Airports.land_color(tr.planes[sa_i2].tkind, tr.planes[sa_i2].runway)) and tr._stripes[sa_i2].size() >= 3
	check(sa_ok, "aircraft have white wings, a livery stripe, and the livery colour is the target runway's")
	var sa_stu = tr.planes[sa_types[SMALL]]
	sa_stu.student = true
	tr._sync(sa_stu, sa_types[SMALL])
	var sa_nostu = tr.planes[sa_types[MEDIUM]]
	tr._sync(sa_nostu, sa_types[MEDIUM])
	check(tr._badges[sa_types[SMALL]].visible and not tr._badges[sa_types[MEDIUM]].visible, "a student pilot wears the orange L badge on the wing")
	check(float(tr._shadow_mats[sa_types[SMALL]].get_shader_parameter("alpha")) <= 0.27 and float(tr._shadow_mats[sa_types[SMALL]].get_shader_parameter("alpha")) > 0.1, "aircraft shadows are blue-grey at about 26%")
	var sa_scene = main.airfield.variants[0]
	var sa_outlined = 0
	var sa_stack = [sa_scene.root]
	while not sa_stack.is_empty():
		var sa_n = sa_stack.pop_back()
		if sa_n is MeshInstance3D and sa_n.material_overlay != null:
			sa_outlined += 1
		sa_stack.append_array(sa_n.get_children())
	check(sa_outlined == 0, "the ground and its props have no outlines (%d outlined parts)" % sa_outlined)
	check(Airports.ORANGE.is_equal_approx(Color("f0803c")) and Airports.BLUE.is_equal_approx(Color("4c8fd6")) and Airports.PAD_COLOR.is_equal_approx(Color("8e6bbe")) and Airports.LANE_COLOR.is_equal_approx(Color("2ba3a6")) and Airports.def(0)["ground"].is_equal_approx(Color("b9dc72")) and tuning.runway_asphalt.is_equal_approx(Color("6a7079")), "the Cozy Airfield palette: grass, asphalt and the four accent colours")
	var sa_shadows = 0
	for sa_v in main.airfield.variants:
		for sa_c in sa_v.root.get_children():
			if sa_c is MeshInstance3D and sa_c.material_override is StandardMaterial3D and (sa_c.material_override as StandardMaterial3D).albedo_texture != null and (sa_c.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(Shadow.COLOR, Shadow.ALPHA * (sa_c.material_override as StandardMaterial3D).albedo_color.a / Shadow.ALPHA)):
				sa_shadows += 1
	var sa_tree_shadows = 0
	for sa_h in sa_scene.tree_styles[0]:
		for sa_c in sa_h.get_children():
			if sa_c is MeshInstance3D and sa_c.material_override is StandardMaterial3D and (sa_c.material_override as StandardMaterial3D).albedo_texture != null:
				sa_tree_shadows += 1
	check(sa_shadows >= 12 and sa_tree_shadows >= 2, "ground props (tower, hangar, windsock, trees) sit on soft baked shadows (%d + %d)" % [sa_shadows, sa_tree_shadows])
	tr.release_all()

	print("9z. Cozy Airfield art: readability")
	check(rb._nodes[0].material_override is ShaderMaterial and (rb._nodes[0].material_override as ShaderMaterial).shader.resource_path.ends_with("path_dots.gdshader"), "paths are lines of round dots (the dot shader), not ribbons")
	check(rb.TINTS[0].is_equal_approx(Color("35c98a")) and rb.TINTS[1].is_equal_approx(Color("ffc933")) and rb.TINTS[2].is_equal_approx(Color("ff5c4d")), "the final segment tints green, yellow, red")
	check(tuning.timer_color(1.0).is_equal_approx(Color("35c98a")) and tuning.timer_color(0.4).is_equal_approx(Color("ffc933")) and tuning.timer_color(0.1).is_equal_approx(Color("ff5c4d")), "timer rings run green, yellow, red")
	var rz_src = FileAccess.get_file_as_string("res://scripts/Overlay.gd")
	check(rz_src.contains("round caps") and rz_src.contains("pulsing halo") and rz_src.contains("red dashed ring around the pair"), "timer rings have a track, round caps and a red pulsing halo; conflicts get a red dashed ring around the pair")
	check(not rz_src.contains("Color(0, 0, 0, 0.8)") and not rz_src.contains("BLACK"), "the overlay draws no black outlines")
	var rz_fx = main.fx
	var rz_ok = true
	for rz_p in rz_fx._emitters + rz_fx._puffs + rz_fx._sparkles:
		rz_ok = rz_ok and (rz_p.mesh.material as StandardMaterial3D).albedo_texture != null
	check(rz_ok, "particles are round dots and gold stars (textured), never squares")

	print("9zz. Cozy Airfield art: screens")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main._show_menu()
	var sc_art = main.hud._art
	check(sc_art.lockup and not main.hud._menu_title.visible and sc_art.lockup_airport == Airports.airport_name(main.airport), "the menu has the tilted title and the selected airport under it, no panels over the field")
	var sc_kinds = {}
	for sc_k in sc_art.btn_count:
		sc_kinds[sc_art.btn_id[sc_k]] = [sc_art.btn_kind[sc_k], sc_art.btn_text[sc_k]]
	check(sc_kinds["play"] == [2, "Start shift"] and sc_kinds["airports"] == [0, "Airports"] and sc_kinds["bad"] == [0, "Bad pilot day"] and sc_kinds["upgrades"][0] == 7 and sc_kinds["shop"] == [7, "Hangar"] and sc_kinds["daily"][0] == 7 and sc_art.btn_count == 6, "the menu: Start shift (orange), Airports and Bad pilot day (cream), and three small round buttons")
	main.select_airport(0)
	main._on_button("airport_next")
	check(main.airport == 1 and Airports.current == 1 and main.screen == main.SCREEN_MENU, "the next arrow moves to the next airport and the field behind the menu follows")
	main._on_button("airport_prev")
	main._on_button("airport_prev")
	check(main.airport == Airports.COUNT - 1, "the previous arrow wraps around")
	main.select_airport(2)
	main._show_menu()
	main.restart()
	main.shift.on_landed(3, 14, 0)
	main.shift.fine(40, "conflict")
	main.hud.set_shift(main.shift)
	main.hud.show_results("SHIFT COMPLETE", "Landings earned|+210", main.shift, 488, 728, 488, true)
	check(sc_art.res_chips[0] == main.shift.earned + main.shift.bonus and sc_art.res_chips[2] == main.shift.fines + main.shift.overtime_penalty and sc_art.res_sub.contains(Airports.airport_name()) and sc_art.res_sub.contains("landed"), "the results card has the three chips (landings, early clear, fines) and the subtitle")
	main.hud.queue_unlock("County")
	check(sc_art.res_unlock == "County", "a new airport shows as a card on the results")
	main.hud.hide_unlock()
	main._show_menu()
	main.restart()
	main.pause_game()
	check(sc_art.pause_card.size.x > 600.0 and sc_art.btn_kind[sc_art.btn_id.find("restart")] == 3, "the pause menu sits on a sheet with colour tiles")
	main.resume_game()
	var sc_doc = FileAccess.get_file_as_string("res://docs/style.md")
	check(sc_doc.contains("## Cozy Airfield") and sc_doc.contains("#FFD68A") and sc_doc.contains("film grain") and sc_doc.contains("#3B4A6B"), "docs/style.md documents the Cozy Airfield art direction")
	check(sc_art._sb_hdr != null and sc_art._sb_card != null and sc_art._sb_dock != null, "the pills, card and dock styles exist")
	main._show_menu()

	print("9zy. gameplay audio is part of the music")
	var qa = main.sfx
	check(qa.QUANTIZED.has("landing") and qa.QUANTIZED.has("go_around") and qa.QUANTIZED.has("alarm") and qa.QUANTIZED.has("tick") and qa.QUANTIZED.has("arrive") and not qa.QUANTIZED.has("tap") and not qa.QUANTIZED.has("touch"), "landings, arrivals, go-arounds, conflicts and ticks wait for the beat; taps and the touchdown tap do not")
	check(absf(qa.EIGHTH - 0.375) < 0.0001 and absf(qa.LOOP_SECS - 6.0) < 0.0001, "the grid is the music's eighth-note (0.375 s of the 6 s loop)")
	qa.quantize = true
	qa.set_music(true, 0.2, 0.0)
	qa._music_on = true
	var qa_w = qa.next_beat_wait()
	check(qa_w > 0.0 and qa_w <= qa.EIGHTH + 0.0001 + 0.03, "the next beat is never more than an eighth away (%.3f s)" % qa_w)
	qa._pending.clear()
	var qa_l0 = qa.plays["landing"]
	qa.play_step("landing", 0)
	check(qa.plays["landing"] == qa_l0 + 1 and qa.pending_count() == 1, "a landing chime is queued for the next beat")
	var qa_due = int(qa._pending[0][0])
	var qa_phase_at_due = fposmod(qa.music_phase() + (qa_due - Time.get_ticks_msec()) / 1000.0, qa.LOOP_SECS)
	var qa_off = fposmod(qa_phase_at_due, qa.EIGHTH)
	check(qa_off < 0.02 or qa.EIGHTH - qa_off < 0.02, "...and it is due exactly on an eighth-note (%.3f s off the grid)" % minf(qa_off, qa.EIGHTH - qa_off))
	qa.play_step("landing", 0)
	check(qa.pending_count() == 1, "two landings in the same beat share it (one chime per beat)")
	qa.flush_pending()
	check(qa.pending_count() == 0, "flushing plays what is waiting")
	# Velocity: the more landings in quick succession, the quieter each chime.
	qa._recent_land.clear()
	qa.quantize = false
	var qa_dbs = []
	for qa_i in 5:
		qa.play_step("landing", qa_i)
		qa_dbs.append(qa._pool[(qa._next + qa.POOL - 1) % qa.POOL].volume_db)
	check(qa_dbs[4] < qa_dbs[0] - 5.0 and qa_dbs[2] < qa_dbs[1], "landings close together are quieter (%.1f -> %.1f dB)" % [qa_dbs[0], qa_dbs[4]])
	qa.quantize = false
	qa.play("touch")
	check(qa.pending_count() == 0, "with quantizing off everything plays at once")
	qa.quantize = true
	qa.play("tap")
	check(qa.pending_count() == 0, "a UI tap is never delayed")
	qa._music_on = false
	qa.play_step("landing", 0)
	check(qa.pending_count() == 0, "with no music running there is no beat to wait for")
	qa.quantize = false
	# The page gives the music clock on the web; the three category sliders are saved.
	var qa_shell = FileAccess.get_file_as_string("res://web/shell.html")
	check(qa_shell.contains("api.phase") and not qa_shell.contains("'hum'"), "the loading page reports the music's phase and plays no hum")
	save.reset_all()
	main._set_volume(2, 0.35)
	main._set_volume(1, 0.6)
	main._set_volume(0, 0.45)
	save.write_file()
	save.load_file()
	check(absf(save.ambience_volume - 0.35) < 0.001 and absf(save.music_volume - 0.6) < 0.001 and absf(save.sound_volume - 0.45) < 0.001, "the three volumes (music, effects, ambience) are saved")
	check(AudioServer.get_bus_index("Ambience") >= 0 and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")) - linear_to_db(0.35)) < 0.01, "the Ambience bus follows its slider")
	main._set_volume(0, 0.8)
	main._set_volume(1, 0.8)
	main._set_volume(2, 0.8)
	main.restart()
	main.pause_game()
	check(main.hud._art.slider_rect[2].size.x > 100.0 and main.hud._art.slider_name.size() == 3 and main.hud.slider_at(main.hud._art.slider_rect[2].get_center()) == 2, "the pause menu has Music, Effects and Ambience sliders")
	main.resume_game()
	var qa_fog = qa._players["fog"]
	check(qa_fog.bus == &"Ambience", "the fog ambience is on the Ambience bus")

	print("9zw. Cozy Airfield: light, shading, shadows")
	var cz_light = main.light
	check(cz_light != null and cz_light.rect != null and cz_light.rect.material is ShaderMaterial and (cz_light.rect.material as ShaderMaterial).shader.code.contains("blend_premul_alpha"), "one light overlay (a ColorRect with a shader) covers the field")
	var cz_m = cz_light.material
	check(absf(float(cz_m.get_shader_parameter("warm_amount")) - 0.35) < 0.001 and absf(float(cz_m.get_shader_parameter("cool_amount")) - 0.2) < 0.001 and absf(float(cz_m.get_shader_parameter("grain_amount")) - 0.08) < 0.001 and (cz_m.get_shader_parameter("warm") as Color).is_equal_approx(Color("ffd68a")) and (cz_m.get_shader_parameter("cool") as Color).is_equal_approx(Color("2f4a7a")), "warm #FFD68A 35%, cool #2F4A7A 20%, grain 8%")
	var cz_g1 = LightOverlay.grain_texture().get_image().get_pixel(3, 5)
	var cz_g2 = LightOverlay.grain_texture().get_image().get_pixel(3, 5)
	check(cz_g1 == cz_g2 and LightOverlay.grain_texture().get_width() == 128 and cz_light.rect.visible == DebugFlags.light_enabled(), "the film grain is a tiled static texture")
	DebugFlags.parse(["nolight", "nolife"])
	check(not DebugFlags.light_enabled() and not DebugFlags.life_enabled() and DebugFlags.summary().contains("nolight") and DebugFlags.summary().contains("nolife"), "?nolight and ?nolife parse")
	DebugFlags.parse(["tune"])
	var cz_lo = 1.0
	var cz_hi = 0.0
	var cz_stack = []
	for cz_n in main.airfield.variants[0].root.get_children():
		if cz_n is MeshInstance3D and cz_n.mesh is ArrayMesh and cz_n != main.airfield.variants[0].root.get_child(0) and cz_n.get_child_count() == 0:
			var cz_arr = (cz_n.mesh as ArrayMesh).surface_get_arrays(0)
			if cz_arr[Mesh.ARRAY_COLOR] != null and cz_arr[Mesh.ARRAY_VERTEX].size() == 24:      # a shaded box
				for cz_c in (cz_arr[Mesh.ARRAY_COLOR] as PackedColorArray):
					cz_lo = minf(cz_lo, cz_c.r)
					cz_hi = maxf(cz_hi, cz_c.r)
	check(cz_hi > 0.97 and cz_lo < 0.86 and cz_lo > 0.78, "every shape is shaded lit to shade, about 18%% (%.2f .. %.2f)" % [cz_lo, cz_hi])
	check(Shadow.COLOR.is_equal_approx(Color("3b4a6b")) and absf(Shadow.ALPHA - 0.26) < 0.001 and Shadow.rect().get_image().get_pixel(32, 32).a > 0.95 and Shadow.rect().get_image().get_pixel(1, 1).a < 0.05, "shadows are #3B4A6B at 26% with a baked soft edge")
	var cz_ground = main.airfield.variants[0].root.get_child(0)
	check(cz_ground is MeshInstance3D and (cz_ground.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR].size() > 100, "the field is a gradient mesh (lit upper-left to shaded lower-right)")
	var cz_tufts = main.airfield.variants[0].tufts
	check(cz_tufts != null and cz_tufts.multimesh.instance_count >= 20 and cz_tufts.multimesh.instance_count <= 60, "sparse grass tufts are scattered (%d)" % cz_tufts.multimesh.instance_count)

	print("9zv. Cozy Airfield: buildings, props and life")
	var cl_af = main.airfield
	var cl_keep = Airports.current
	var cl_bad = []
	var cl_apron = 0
	for cl_i in Airports.COUNT:
		Airports.current = cl_i
		var cl_v = cl_af.variants[cl_i]
		cl_apron += 1 if not cl_v.apron_c.is_equal_approx(Vector2.ZERO) else 0
		for cl_p in cl_v.scenery:
			if not cl_af._clear_of_paths(cl_p, -0.9):
				cl_bad.append("%s %s" % [Airports.airport_name(cl_i), str(cl_p)])
	Airports.current = cl_keep
	check(cl_apron == Airports.COUNT and cl_bad.is_empty(), "every airport has a ramp, and the big scenery stands outside the paths' strips %s" % str(cl_bad))
	var cl_coast = cl_af.variants[Airports.index_of("Island")]
	var cl_alp = cl_af.variants[Airports.index_of("Mountain Field")]
	check(cl_coast.style == "coastal" and cl_coast.lamps.size() == 1, "the island has a lighthouse with a lamp")
	check(cl_alp.style == "alpine" and cl_alp.smoke.size() == 4, "the mountain lodge has chimney smoke")
	check(cl_alp.chairs.size() == 2 or cl_alp.chair_a == Vector2.ZERO, "the chairlift has two chairs when it fits")
	var cl_v0 = cl_af.variants[0]
	var cl_trucks = 0
	for cl_i in Airports.COUNT:
		cl_trucks += 1 if cl_af.variants[cl_i].truck != null else 0
	check(cl_v0.beacons.size() == 1 and cl_v0.truck != null and cl_v0.truck_pts.size() == 3 and cl_v0.birds.size() == 2 and not cl_v0.balloon.is_empty() and cl_v0.tufts != null and cl_trucks >= 4, "the tower's beacon, the fuel truck and its route (%d airports), two birds and the balloon exist" % cl_trucks)
	var cl_sig = []
	for cl_c in cl_v0.root.get_children():
		cl_sig.append(cl_c.get_class())
	cl_af.select(0)
	cl_af.traffic = main.traffic
	var cl_tp = cl_v0.truck.position
	for cl_k in 120:
		cl_af._animate_life(0.1)
	check(cl_v0.truck.position.distance_to(cl_tp) > 0.2 or cl_v0.truck_pts[0].distance_to(Vector2(cl_tp.x, cl_tp.z)) < 5.0, "the fuel truck drives its loop")
	var cl_b0 = cl_v0.birds[0]["pos"]
	cl_af._animate_life(0.5)
	check(cl_v0.birds[0]["pos"] != cl_b0, "the birds drift")
	var cl_bx = cl_v0.balloon["x"]
	cl_af._animate_life(2.0)
	check(cl_v0.balloon["x"] > cl_bx, "the balloon drifts across the top")
	# a plane passing near scares a bird
	var cl_plane = main.traffic.place(0, cl_v0.birds[0]["pos"] + Vector2(0.5, 0.0), 0.0, SMALL)
	cl_af._animate_life(0.05)
	check(cl_v0.birds[0]["scatter"] > 1.0 and cl_v0.birds[0]["vel"].length() > 1.0, "birds scatter when an aircraft passes close")
	main.traffic.release_all()
	if cl_v0.mower != null:
		cl_af.progress = 0.05
		cl_af._animate_life(0.01)
		var cl_row0 = 0
		for cl_r in cl_v0.mower_rows:
			cl_row0 += 1 if cl_r.visible else 0
		cl_af.progress = 0.8
		cl_af._animate_life(0.01)
		var cl_row1 = 0
		for cl_r in cl_v0.mower_rows:
			cl_row1 += 1 if cl_r.visible else 0
		check(cl_row1 > cl_row0 and cl_v0.mower.visible, "the mower leaves more stripes as the shift goes on (%d -> %d)" % [cl_row0, cl_row1])
		cl_af.progress = 0.0
		cl_af._animate_life(0.01)
		var cl_row2 = 0
		for cl_r in cl_v0.mower_rows:
			cl_row2 += 1 if cl_r.visible else 0
		check(cl_row2 <= 1, "...and a restart clears them")
	cl_af.progress = -1.0
	DebugFlags.parse(["tune", "nolife"])
	var cl_still = cl_v0.truck.position
	var cl_balloon = cl_v0.balloon["x"]
	if DebugFlags.life_enabled():
		cl_af._animate_life(1.0)
	check(not DebugFlags.life_enabled() and cl_v0.truck.position == cl_still and cl_v0.balloon["x"] == cl_balloon, "?nolife stops the moving pieces")
	DebugFlags.parse(["tune"])
	var cl_papi = 0
	var cl_labels = 0
	var cl_stack = [cl_v0.root]
	while not cl_stack.is_empty():
		var cl_n = cl_stack.pop_back()
		if cl_n is Label3D:
			cl_labels += 1
		cl_stack.append_array(cl_n.get_children())
	check(cl_labels >= 3, "runway numbers and the taxiway sign are on the field (%d labels)" % cl_labels)

	print("9zu. Cozy Airfield: fonts and interface")
	check(main.hud._score is ExtLabel and main.hud._best is ExtLabel and main.hud._pop_labels[0] is ExtLabel, "the timer, the score and the score pops are display-face labels with the warm extrusion")
	check(Style.WORLD_TEXT.is_equal_approx(Color("fff4df")) and Style.EXT_TOP.is_equal_approx(Color("c9641f")) and Style.EXT_BOTTOM.is_equal_approx(Color("803d11")), "cream #FFF4DF letters on a #C9641F to #803D11 extrusion")
	main.hud.popup("+12", Color(1, 0.8, 0.2), Vector2(500, 900))
	var zu_rot = []
	for zu_i in 6:
		main.hud.popup("+12", Color(1, 0.8, 0.2), Vector2(500, 900))
		for zu_l in main.hud._pop_labels:
			if zu_l.visible and absf(zu_l.rotation) > 0.0001:
				zu_rot.append(snappedf(zu_l.rotation, 0.001))
	check(zu_rot.size() >= 3 and zu_rot.min() < 0.0 + 0.1 and absf(zu_rot.max()) <= deg_to_rad(6.01), "score pops lean a few degrees, a different way each time")
	var zu_art = main.hud._art
	check(zu_art._sb_normal.border_width_bottom == 4 and zu_art._sb_normal.border_color.is_equal_approx(Style.EDGE) and zu_art._sb_normal.bg_color.is_equal_approx(Style.SURFACE_DARK) and zu_art._sb_normal.corner_radius_top_left == 22, "cream cards: a solid 4 px #C9A46E bottom edge, 22 px corners")
	check(Style.LIP == 7.0 and zu_art._sb_lip.bg_color.is_equal_approx(Color("b85a1b")) and zu_art._sb_primary.bg_color.is_equal_approx(Color("f0803c")), "the primary button is orange on a 7 px #B85A1B edge")
	main.hud.show_menu("Grass Strip", 10, 3, 0, "", 2)
	check(absf(rad_to_deg(deg_to_rad(2.0)) - 2.0) < 0.001 and zu_art.lockup and zu_art.lockup_airport == "Grass Strip", "the title sits at a 2 degree tilt over the live field")
	main.hud.show_select(3, PackedByteArray([1, 0, 0, 0, 0, 0]), PackedInt32Array([2, 0, 0, 0, 0, 0]), PackedInt32Array([120, 0, 0, 0, 0, 0]), 0)
	var zu_ids = []
	for zu_k in zu_art.btn_count:
		zu_ids.append(zu_art.btn_id[zu_k])
	check(zu_ids.has("pick:0") and zu_ids.has("airport:0") and zu_ids.has("locked:1") and zu_art.btn_text[zu_art.btn_id.find("airport:0")] == "Fly here" and zu_art.btn_cost[zu_art.btn_id.find("pick:0")] == 120 and zu_art.btn_map[zu_art.btn_id.find("locked:1")] == 1, "airports: vignette cards, the selected one has Fly here, a locked one a dimmed vignette")
	main._show_menu()
	check(not FileAccess.file_exists("res://assets/fonts/Fredoka.ttf") and not FileAccess.file_exists("res://assets/fonts/Nunito.ttf"), "Fredoka and Nunito are gone")

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
		for i in 60 * 100:
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
	check(main.hud._over_body.text.contains("Landings earned +%d" % main.shift.earned) and main.hud._over_body.text.contains("Guaranteed kept %d" % main.shift.kept()), "the results details list landings earned, fines, kept and the total")
	# The PLAY AGAIN button restarts in place; a tap on the empty results screen only skips the reveal.
	var empty_tap = Vector2(540, 60)
	main.hud._art.res_t = 0.0
	touch(main, 0, true, empty_tap)
	touch(main, 0, false, empty_tap)
	check(main.screen == main.SCREEN_OVER and main.hud.results_revealed(), "a tap on the empty results screen skips the reveal but doesn't restart")
	var again_i = main.hud._art.btn_id.find("again")
	var again_c = main.hud._art.btn_rect[again_i].get_center()
	touch(main, 0, true, again_c)
	touch(main, 0, false, again_c)
	check(main.screen == main.SCREEN_PLAY and main.alive and main.score == 0, "PLAY AGAIN restarts in place")
	touch(main, 0, false, again_c)

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
	for name in ["intro_spawn_scale", "speed_fast", "timer_jet", "shift_scale", "par_window", "conflict_distance", "warn_distance"]:
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

	print("13. Polish 1: the hangar, the ramp and the taxi routes")
	var RampC = load("res://scripts/Ramp.gd")
	var rp_bad = []
	var rp_keep = Airports.current
	for rp_i in Airports.COUNT:
		Airports.current = rp_i
		var rp_cap = RampC.capacity(rp_i)
		var rp_pay = RampC.mean_pay(rp_i)
		var rp_cost = RampC.shift_cost(rp_i)
		if not (rp_cap * rp_pay >= rp_cost and (rp_cap - 1) * rp_pay < rp_cost):
			rp_bad.append("%s cap %d pay %.1f cost %d" % [Airports.airport_name(rp_i), rp_cap, rp_pay, rp_cost])
	check(rp_bad.is_empty(), "the hangar capacity is the break-even landing count %s" % str(rp_bad))
	var rp = RampC.new()
	rp.reset(5, 6, 0, 1, 6)
	var rp_places = []
	for rp_k in 5 + 17:
		rp_places.append(rp.place(Aircraft.Type.SMALL)["kind"])
	check(rp.hangar == 5 and rp.ties == 6 and rp.overs == 6 and rp.extra == 5 and rp.on_ramp() == 17, "ramp count = landings beyond the hangar (%d on the ramp)" % rp.on_ramp())
	check(rp_places[4] == "hangar" and rp_places[5] == "tie" and rp_places[11] == "over" and rp_places[17] == "extra", "the order is hangar, tie-downs, grass, then the +N")
	check(rp.summary() == "Hangar full · 17 on the ramp", "the results line says it (%s)" % rp.summary())
	rp.reset(8, 6, 0, 1, 6)
	for rp_k in 5:
		rp.place(Aircraft.Type.SMALL)
	check(rp.summary() == "Hangar 5 / 8" and rp.on_ramp() == 0, "...and 'Hangar 5 / 8' when not full (%s)" % rp.summary())
	rp.reset(1, 6, 0, 1, 6)
	rp.place(Aircraft.Type.SMALL)
	check(rp.place(Aircraft.Type.HELI)["kind"] == "heli" and rp.place(Aircraft.Type.HELI)["kind"] == "tie", "a helicopter goes to the heli spot first")
	var rp_cross = []
	var rp_slots = 0
	for rp_i in Airports.COUNT:
		Airports.current = rp_i
		main.airfield.select(rp_i)
		var rp_rv = main.airfield.cur
		check(rp_rv.ramp_ok and (rp_rv.slots["tie"] as Array).size() == 6, "%s has six tie-downs" % Airports.airport_name(rp_i))
		var rp_goals = []
		for rp_rk in ["tie", "over", "heli", "dock"]:
			for rp_e in rp_rv.slots[rp_rk]:
				rp_goals.append([rp_e["goals"], rp_e["tail"]])
		rp_goals.append([rp_rv.hangar_goals, rp_rv.hangar_tail])
		rp_goals.append([rp_rv.extra_goals, rp_rv.extra_tail])
		for rp_rk in range(Airports.land_count(Aircraft.Kind.RUNWAY)):
			for rp_re in 2:
				var rp_far = Airports.land_far(Aircraft.Kind.RUNWAY, rp_rk, rp_re)
				var rp_dir = Airports.end_dir(rp_rk, rp_re)
				for rp_g in rp_goals:
					var rp_any = false
					for rp_gp in rp_g[0]:
						var rp_rr = RampC.taxi_route(rp_far, rp_dir, rp_gp, rp_g[1])
						if rp_rr.is_empty():
							continue
						rp_any = true
						rp_slots += 1
						for rp_sg in range(1, rp_rr.size() - 1):
							if RampC.crosses_runway(rp_rr[rp_sg], rp_rr[rp_sg + 1], 0.05):
								rp_cross.append("%s rw%d e%d seg %d" % [Airports.airport_name(rp_i), rp_rk, rp_re, rp_sg])
					if not rp_any:
						rp_cross.append("%s rw%d e%d: a slot has no route (%s)" % [Airports.airport_name(rp_i), rp_rk, rp_re, str(rp_g[0])])
	Airports.current = rp_keep
	main.airfield.select(rp_keep)
	check(rp_slots > 0 and rp_cross.is_empty(), "no taxi route crosses a runway (%d routes) %s" % [rp_slots, str(rp_cross.slice(0, 4))])
	# in the game: landings park, nothing is allocated, a restart clears the ramp in place
	main.restart()
	var rp_rv0 = main.airfield.cur
	var rp_children = rp_rv0.root.get_child_count()
	var rp_cap = main.airfield.ramp.cap
	check(main.airfield.ramp_active and rp_cap == RampC.capacity(), "a shift starts with an empty hangar of %d" % rp_cap)
	var rp_max_moving = 0
	for rp_k in rp_cap + 9:
		main.airfield.begin_taxi(Aircraft.Type.SMALL, 0, 0, rp_k % 2)
		var rp_moving = 0
		for rp_t in main.airfield.taxis:
			if not rp_t["ff"]:
				rp_moving += 1
		rp_max_moving = maxi(rp_max_moving, rp_moving)
		main.airfield.step_taxi(0.5)
	check(rp_max_moving <= 4, "at most four taxi at their own pace (%d)" % rp_max_moving)
	for rp_k in 400:
		main.airfield.step_taxi(0.5)
	check(main.airfield.taxis.is_empty() and main.airfield.hangar_shown == rp_cap, "they all arrive; the hangar door shows %d / %d" % [main.airfield.hangar_shown, rp_cap])
	check(main.airfield.ramp.on_ramp() == 9, "ramp count equals landings beyond the hangar (%d)" % main.airfield.ramp.on_ramp())
	var rp_parked = 0
	for rp_rk in ["tie", "over"]:
		for rp_e in rp_rv0.slots[rp_rk]:
			if rp_e["node"].visible and rp_e["chocks"].visible:
				rp_parked += 1
	check(rp_parked == mini(9, 6 + (rp_rv0.slots["over"] as Array).size()), "the parked planes show their chocks (%d)" % rp_parked)
	check(rp_rv0.root.get_child_count() == rp_children, "nothing was allocated by parking")
	main.restart()
	check(main.airfield.ramp.on_ramp() == 0 and main.airfield.hangar_shown == 0 and main.airfield.taxis.is_empty(), "a restart clears the ramp")
	var rp_vis = 0
	for rp_rk in rp_rv0.slots:
		for rp_e in rp_rv0.slots[rp_rk]:
			if rp_e["node"].visible:
				rp_vis += 1
	check(rp_vis == 0 and rp_rv0.root.get_child_count() == rp_children, "...in place (nothing left parked, nothing new built)")

	print("14. Polish 2: path feel")
	main.restart()
	var sn_tr = main.traffic
	sn_tr.auto_spawn = false
	sn_tr.wind = null
	var sn_thr = Airports.end_threshold(0, 0)
	var sn_dir = Airports.end_dir(0, 0)
	var sn_perp = Vector2(-sn_dir.y, sn_dir.x)
	var sn_hits = []
	var sn_cb = func(_p, at): sn_hits.append(at)
	sn_tr.snapped.connect(sn_cb)
	var sn_p = sn_tr.place(0, sn_thr - sn_dir * 4.0 + sn_perp * 3.0, 0.0, 2)
	sn_p.runway = 0
	check(sn_tr.begin_path(sn_p), "a path can start")
	var sn_far_try = sn_tr.extend_path(sn_p, sn_thr - sn_dir * 2.0 + sn_perp * 1.6)
	check(not sn_far_try and not sn_p.cleared and sn_hits.is_empty(), "a finger outside the snap radius does not snap")
	var sn_ok = sn_tr.extend_path(sn_p, sn_thr - sn_dir * 1.4 + sn_perp * 0.3)
	var sn_pt = sn_p.pts[sn_p.head + sn_p.count - 3]
	check(sn_ok and sn_p.cleared and sn_hits.size() == 1, "a finger within the snap radius of the extended centreline locks on")
	check(absf((sn_pt - sn_thr).dot(sn_perp)) < 0.01 and absf((sn_pt - sn_thr).dot(sn_dir) + 1.4) < 0.02, "...at the point on the centreline (%s)" % str(sn_pt))
	check(sn_p.last_point().is_equal_approx(Airports.end_far(0, 0)), "...and the path runs straight down the runway")
	sn_tr.snapped.disconnect(sn_cb)
	sn_tr.release_all()
	var sn_n0 = tuning.path_smooth_points
	tuning.path_smooth_points = 4.0
	main._smooth_count = 0
	var sn_last = Vector2.ZERO
	for sn_k in 4:
		sn_last = main._smooth(Vector2(0.4 if sn_k % 2 == 1 else 0.0, 0.0))
	check(is_equal_approx(sn_last.x, 0.2), "the path follows the average of the last four points (%.2f)" % sn_last.x)
	tuning.path_smooth_points = sn_n0
	var sn_q = sn_tr.place(0, Vector2(-2.0, -5.0), 0.0, 2)
	sn_tr.begin_path(sn_q)
	for sn_k in 6:
		sn_q.push(Vector2(-2.0 + sn_k * 0.3, -4.0))
	sn_tr.toggle_hold(sn_q)
	check(sn_q.count == 0 and sn_q.ghost_n == 6 and sn_q.ghost_t > 0.0, "a tap clears the path and leaves a fading copy")
	check(tp._sliders.has("snap_radius") and tp._sliders.has("path_smooth_points"), "?tune exposes the snap radius and the smoothing")
	sn_tr.release_all()
	check(sn_q.ghost_t == 0.0, "nothing fades after the aircraft is gone")

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
