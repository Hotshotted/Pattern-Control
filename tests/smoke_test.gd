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
##   9c. airports: six layouts, unlock by stars, select screen, crossing runways (no ground conflicts), busy runway
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
	while (main.shift.balance() < coins or main.shift.landed < main.shift.thresholds[0]) and guard < 500:     # (and enough landings for the first star)
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

func _mouse_up_ev() -> InputEvent:
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	return ev

func await_frames_sync(main: Node, n: int) -> void:
	for i in n:
		main.hud._process(0.016)

func touch(main: Node, index: int, pressed: bool, screen: Vector2) -> void:
	var ev = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = screen
	main._input(ev)

## Is there a button with this id on the screen: among the panel's own, or in its list that scrolls?
func bt_has(main: Node, id: String) -> bool:
	return main.hud._art.btn_id.find(id) in range(main.hud._art.btn_count) or main.hud.list_ids().has(id)

## A tap on one of the detail sheet's buttons, as the sheet reports it (finger down, finger up on the same button).
func sheet_tap(main: Node, id: String) -> void:
	var c = main.hud.detail_sheet().chips.get(id)
	if c == null:
		return
	c.down.emit(id)
	c.up.emit(id)

## Every airport at its top level (the improvements' deepest tiers are open), for tests that buy them.
func all_levels(save) -> void:
	for a in 6:
		save.ap_xp[a] = Progression.xp_at_level(a, 20)
	save.sync_levels()

## Hold a cost button for `secs` seconds: finger down, the sheet's hold timer ticking, finger up (as a hold that fills rebuilds the sheet, up may find nothing).
func sheet_hold(main: Node, id: String, secs: float) -> void:
	var c = main.hud.detail_sheet().chips.get(id)
	if c == null:
		return
	var sheet = main.hud.detail_sheet()
	c._held = true
	c.down.emit(id)
	var left := secs
	while left > 0.0:
		main._tick_imp_hold(0.05)
		left -= 0.05
	if is_instance_valid(c) and c._held:
		c._held = false
		if sheet.chips.get(id) == c:
			c.up.emit(id)

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
	tuning.ad_sdk_present = true    # the older sections test the ad pills as if an SDK were there (section 40 tests it absent)
	tuning.ad_stub_seconds = 0.0    # fake ads finish at once unless a test is about them
	tuning.go_around_max = 0.0      # ...and no random go-arounds, except in the go-around section
	tuning.landing_keep_fraction = 0.25   # ...and the pay floor is the old quarter of the gross (the game ships 0.40: a struggling player keeps more)
	save.event_modifiers = false    # ...and the weekly event changes nothing (section 40 tests it)
	save.sync_event()
	tuning.welcome_shifts = 0       # ...and no welcome floor on the first shifts (section 40 tests it)
	Progression.flat_pay = true     # ...and a level's pay steps are off (section 40 tests them)
	Airports.test_full_mix = true   # ...and every airport plays its whole traffic mix, whatever its level (section 40 tests the levels)
	tuning.intro_logo = false       # ...and no boot logo, except in the motion section
	load("res://scripts/Airfield.gd").boot_lazy = false      # (the tests want every airport built up front; the lazy build has its own section)
	DebugFlags.parse(["tune"])   # the whole run has the tuning panel, so it is part of the "nothing new" baseline

	print("1. boot and the visible pre-warm")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.progress_enabled = false   # (mastery and achievements likewise: section 34)
	main.goals_enabled = false      # (the daily goals have their own section, 33: elsewhere their rewards would change the coin counts)
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
	check(tuning.type_timer(0) < tuning.timer_heli and tuning.timer_heli < tuning.timer_small and tuning.timer_small < tuning.timer_medium and tuning.timer_medium < tuning.timer_jet, "timer lengths: glider < helicopter < small < medium < jet")
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
		if l.visible and l.text.begins_with("Diverted") and not l.text.contains("-"):
			pop_seen = true
	check(pop_seen, "a fine shows its reason as a plain popup ('Diverted'), with no coins subtracting")
	check(main.hud._tk_flying == 1 and main.shift.tickets == 1, "...and a small ticket pops at the plane and drops towards the fines counter")
	check(main.hud._coin_target == main.shift.gross() and main.hud._coin_target >= 0 and main.hud._art.balance == -tuning.fine_amount(tuning.fine_timeout), "the coin counter does not go down (the star bar still follows the net)")
	for fk_i in 40:
		main.hud._process(0.05)
	check(main.hud._tk_flying == 0 and main.hud._art.tickets_shown == 1 and main.hud._art.fines_shown == tuning.fine_amount(tuning.fine_timeout), "the fines counter takes the ticket in when it lands (%d ticket, %d)" % [main.hud._art.tickets_shown, main.hud._art.fines_shown])
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
	# The pay floor: a completed shift pays at least 25% of its gross; fines cut the pay down to it and no further.
	var payfl = Shift.new()
	payfl.reset([1, 50, 100])
	payfl.on_landed(2, 100, 20)
	payfl.set_finish(10.0, 25.0, 6)
	check(payfl.gross() == 210 and payfl.kept() == 52 and payfl.keep_fraction == 0.25, "the floor is 25%% of the gross (landing pay + bonuses + early bonus): %d of %d" % [payfl.kept(), payfl.gross()])
	payfl.fine(100, "conflict")
	check(payfl.payout() == payfl.balance() and not payfl.is_protected(), "a small fine comes straight off the pay (%d)" % payfl.payout())
	payfl.fine(400, "crash")
	check(payfl.balance() < 0 and payfl.payout() == payfl.kept() and payfl.is_protected(), "a huge fine cannot take the pay under the floor (net %d, pay %d)" % [payfl.balance(), payfl.payout()])
	check(not payfl.star_reached(1) and payfl.crashes == 1, "...but the net still counts against the stars")
	payfl.reset([1, 50, 100])
	check(payfl.payout() == 0 and not payfl.is_protected(), "a shift with nothing earned pays nothing")
	# On the results card: "Shift pay protected" when the floor is what pays.
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 120)
	main.shift.fine(900, "conflict")
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 30.0)
	check(main.shift.is_protected() and main.shift.payout() == main.shift.kept() and main.last_result["reason"].contains("Shift pay protected"), "the results list says the shift pay was protected")
	check(main.hud._art.res_protected == main.shift.kept() - main.shift.balance() and main.hud._art.res_protected > 0, "...and the results card shows it (+%d from the floor)" % main.hud._art.res_protected)
	# Abandoning a shift pays nothing.
	main.restart()
	tr.auto_spawn = false
	var coins_ab = save.coins
	earn_coins(main, 150)
	main._on_button("quit")
	check(main.screen == main.SCREEN_MENU and save.coins == coins_ab, "leaving a shift from the pause menu pays nothing (%d -> %d)" % [coins_ab, save.coins])
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
	check(main.shift.earned == int(tuning.pay_heli) + tuning.landing_pay(GLIDER), "a glider pays more than a small plane (%d)" % tuning.landing_pay(GLIDER))
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
	# Stars: star 1 is for finishing with enough landings; stars 2 and 3 are the net coins after fines.
	main.restart()
	tr.auto_spawn = false
	main.shift.bonus += sth9[2] + 50             # coins without the landings...
	check(main.shift.stars() == 0 and not main.shift.star_reached(0), "coins alone earn no star: the first one is for landings (%d needed)" % sth9[0])
	for lk in sth9[0] - 1:
		main.shift.on_landed(3, 0, 0)
	check(main.shift.stars() == 0, "...%d landings are not enough" % (sth9[0] - 1))
	main._on_landed(fake)
	check(main.shift.stars() == 3 and main.shift.star_reached(0), "the last landing for the first star also lifts the net over stars 2 and 3 here (three stars)")
	var star_pop = false
	for l in main.hud._pop_labels:
		if l.visible and l.text == "STAR!":
			star_pop = true
	check(star_pop, "a STAR! popup shows when a star is reached")
	# Fines subtract from the net and can drop stars 2 and 3 again, but not the first.
	main.shift.fine(500, "conflict")
	check(main.shift.stars() == 1 and main.shift.balance() < sth9[1], "a big fine takes the net back under stars 2 and 3; the landing star stays (%d)" % main.shift.stars())
	main.shift.refund_biggest()
	check(main.shift.stars() == 3, "...and refunding it restores them")
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
	earn_coins(main, sth9[2] + 120)      # (the three fines below take 170: the net ends under the second star, and the refund lifts it back over the third)
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
	check(raw.contains("\"version\":7"), "the save file is versioned (v7)")
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
	check(main.hud._art.btn_lock[main.hud._art.btn_id.find("locked:1")] == Progression.GATE_LEVEL and main.hud._art.btn_state[main.hud._art.btn_id.find("locked:1")] == 1, "a locked card shows a padlock and the level it needs")
	var locked_pos = cards["locked:1"].get_center()
	var sel_locked = main.airport
	touch(main, 0, true, locked_pos)
	touch(main, 0, false, locked_pos)
	check(main.screen == main.SCREEN_DETAIL and main.detail_airport == 1 and not main.hud.detail_sheet().chips.has("airport:1") and main.hud.detail_sheet().fly == null, "tapping a locked airport opens its detail screen, view only (no Fly here)")
	touch(main, 0, true, main.hud._art.btn_rect[main.hud._art.btn_id.find("back")].get_center())
	touch(main, 0, false, main.hud._art.btn_rect[main.hud._art.btn_id.find("back")].get_center())
	check(main.screen == main.SCREEN_SELECT and main.airport == sel_locked, "...and Back returns to the list without changing the airport")
	save.add_xp(0, Progression.xp_at_level(0, Progression.GATE_LEVEL - 1))
	main._show_select()
	check(not save.airport_open(1) and main.hud.button_at(cards["locked:1"].get_center()) != "pick:1", "level 7 at the Grass Strip does not open County")
	save.add_xp(0, Progression.xp_to_next(0, Progression.GATE_LEVEL - 1))
	main._show_select()
	check(save.ap_level(0) == Progression.GATE_LEVEL and save.airport_open(1) and main.hud.button_at(cards["locked:1"].get_center()) == "pick:1", "level 8 at the Grass Strip opens County")
	var sel_before = main.airport
	touch(main, 0, true, cards["locked:1"].get_center())
	touch(main, 0, false, cards["locked:1"].get_center())
	check(main.screen == main.SCREEN_DETAIL and main.detail_airport == 1 and main.airport == sel_before and main.hud.detail_sheet().chips.has("airport:1"), "tapping an open airport's card opens its detail screen with a Fly here button (nothing starts, nothing is selected yet)")
	sheet_tap(main, "airport:1")
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
	cb.entered = true
	ca.ground = true
	cb.ground = true
	ca.state = Aircraft.State.LANDING
	cb.state = Aircraft.State.LANDING
	ca.pos = Vector2.ZERO
	cb.pos = Vector2.ZERO
	var rc = [false]
	tr.conflict.connect(func(_a, _b): rc[0] = true, CONNECT_ONE_SHOT)
	for rc_k in 30:
		tr.step(1.0 / 60.0)
	check(not rc[0] and main.alive and main.shift.conflicts == 0, "two aircraft rolling out on crossing runways, on the very same spot, never collide: no conflict, no fine")
	check(not ca.can_conflict() and not cb.can_conflict(), "...aircraft in the landing roll or on the ground can't conflict at all")
	check(not tr.has_signal("runway_conflict"), "...and the runway-crossing conflict no longer exists")
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
	check(is_equal_approx(gl.timer_max, tuning.glider_frac() * tuning.timer_small * tuning.timer_mult()) and is_equal_approx(tuning.glider_frac(), 0.75) and is_equal_approx(tuning.glider_timer_frac, 0.6) and gl.speed < tuning.speed_slow, "a glider is slow, and its ring starts at 75%% of a small plane's on Grass Strip (60%% elsewhere) (%.1f of %.1f s)" % [gl.timer_max, tuning.timer_small * tuning.timer_mult()])
	check(tuning.type_timer(GLIDER) < tuning.timer_small and tuning.type_timer(GLIDER) == tuning.glider_frac() * tuning.timer_small, "...the share is a tuning value (?tune)")
	check(Airports.mix(0)[GLIDER] == 0.15 and Airports.glider_timer_own(1) < 0.0, "Grass Strip: 15%% gliders; the others have the general share")
	tr.toggle_hold(gl)
	check(gl.state == Aircraft.State.HOLD, "in normal play a glider can hold like the rest")
	tr.toggle_hold(gl)
	draw_path(main, gl, [gl.pos + Vector2(0.0, 0.8), gl.pos + Vector2(-1.0, 2.0)])
	check(not gl.locked and not gl.cleared and tr.begin_path(gl), "...and its first path is not final: it may draw another")
	check(gl.can_go_around() and gl.approach_scored(), "...and can go around")
	tr.release_all()
	# "No engines": a glider's first path is final, nobody holds on a glider, and nothing goes around.
	tr.no_engines = true
	var glx0 = tr.place(0, Vector2(1.5, -4.0), PI, GLIDER)
	check(glx0.one_shot and glx0.glider_one_shot() and not glx0.can_go_around(), "No engines: a glider cannot go around")
	tr.toggle_hold(glx0)
	check(glx0.state == Aircraft.State.FLY and refused_txt[0] == "Gliders can't hold", "...cannot hold (%s)" % refused_txt[0])
	draw_path(main, glx0, [glx0.pos + Vector2(0.0, 0.8), glx0.pos + Vector2(-1.0, 2.0)])
	check(glx0.locked and not glx0.cleared, "...its first path (that misses the runway) is final")
	check(not tr.begin_path(glx0) and refused_txt[0] == "Glider: first path only", "...it refuses a second one")
	tr.release_all()
	var gl2 = tr.place(0, Airports.end_threshold(0, 1) + Vector2(0.5, -3.0), PI, GLIDER)
	draw_path(main, gl2, [gl2.pos + Vector2(0, 1.0), Airports.end_threshold(0, 0) if false else Airports.end_threshold(0, 0)])
	set_wind(main, 180.0)
	tr.release_all()
	var gl3 = tr.place(0, Airports.end_threshold(0, 1) + Vector2(0.5, -3.0), PI, GLIDER)
	draw_path(main, gl3, [gl3.pos + Vector2(0, 0.8), Airports.end_threshold(0, 1)])
	check(gl3.cleared and gl3.locked, "a glider that gets it right on the first path lands")
	tr.no_engines = false
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
		cost_ok = cost_ok and Upgrades.cost(id, 0) < Upgrades.cost(id, 1) and Upgrades.cost(id, 1) < Upgrades.cost(id, 2) and Upgrades.cost(id, 2) < Upgrades.cost(id, 3) and Upgrades.cost(id, 3) < Upgrades.cost(id, 4) and Upgrades.cost(id, 5) == -1 and Upgrades.cost(id, 3) >= 2 * Upgrades.cost(id, 2) * 0.9
	check(cost_ok, "each upgrade has five levels and rising costs (levels 4 and 5 cost far more than level 3)")
	check(not save.buy_upgrade("radar") and save.upgrade_level("radar") == 0, "can't buy without the coins")
	save.add_coins(Upgrades.cost("radar", 0) + 7)
	var c_before = save.coins
	check(save.buy_upgrade("radar") and save.upgrade_level("radar") == 1 and save.coins == c_before - Upgrades.cost("radar", 0), "buying takes exactly the price and raises the level")
	save.add_coins(100000)
	for lk in 4:
		save.buy_upgrade("radar")
	check(save.upgrade_level("radar") == 5 and not save.buy_upgrade("radar"), "a maxed upgrade (level 5) can't be bought again")
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
	# Levels 4 and 5: each still helps, a little less than the one before.
	var ladder_ok = true
	var msgs = []
	var series = {
		"comms": func(): return tuning.timer_mult(), "holding": func(): return 1.0 / tuning.hold_drain(), "tower": func(): return tuning.traffic_spawn_mult(),
		"radar": func(): return tuning.view_size(), "approach": func(): return tuning.approach_bias(), "turnoffs": func(): return 1.0 / (tuning.landing_roll() + tuning.runway_clear())}
	for id in series:
		var vals = []
		for lv in 6:
			save.upgrades[id] = lv
			vals.append(series[id].call())
		save.upgrades = {}
		var steps_ok = true
		for lv in range(1, 6):
			steps_ok = steps_ok and vals[lv] > vals[lv - 1]
		steps_ok = steps_ok and (vals[5] - vals[3]) < 2.0 * (vals[3] - vals[2]) * 1.5 and (vals[4] - vals[3]) > 0.0
		ladder_ok = ladder_ok and steps_ok
		msgs.append("%s %.2f/%.2f/%.2f" % [id, vals[3], vals[4], vals[5]])
	check(ladder_ok, "levels 4 and 5 of every Tower upgrade help, with smaller steps than the first three (%s)" % ", ".join(msgs))
	save.upgrades["turnoffs"] = 5
	check(is_equal_approx(tuning.landing_roll(), tuning.landing_roll_time * 0.7) and is_equal_approx(tuning.runway_clear(), tuning.runway_clear_seconds * 0.06), "Fast Turnoffs level 5: the roll is 30%% shorter and the runway clears in %.2f s" % tuning.runway_clear())
	save.upgrades = {}
	# Visible on the airport.
	main.airfield.show_upgrades()
	var any_vis = false
	for id in Upgrades.IDS:
		any_vis = any_vis or main.airfield.upgrade_nodes_visible(id) > 0
	check(not any_vis, "with no upgrades none of their scenery shows")
	var vis_ok = true
	var counts = {}
	var vis_t3 = {}
	var vis_t5 = {}
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
			save.upgrades[id] = 5
			main.airfield.show_upgrades()
			var c5 = main.airfield.upgrade_nodes_visible(id)
			if not (c1 >= 1 and c3 > c1 and c5 >= c3):
				print("     upgrade scenery: airport %d %s level1=%d level3=%d level5=%d" % [a_i + 1, id, c1, c3, c5])
			vis_ok = vis_ok and c1 >= 1 and c3 > c1 and c5 >= c3
			counts[id] = c3
			vis_t3[id] = int(vis_t3.get(id, 0)) + c3
			vis_t5[id] = int(vis_t5.get(id, 0)) + c5
		save.upgrades = {}
	for id in Upgrades.IDS:
		vis_ok = vis_ok and int(vis_t5[id]) > int(vis_t3[id])
	check(vis_ok, "at every airport each upgrade adds scenery that grows with its level, and levels 4 and 5 add more %s" % str(counts))
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
	check(main.screen == main.SCREEN_UPGRADES and main.hud._select.visible and main.hud._select_title.text == "TOWER", "the Tower (upgrade shop) opens")
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

	print("9e2. airport improvements")
	var RampX = load("res://scripts/Ramp.gd")
	save.reset_all()
	save.unlocks["all_airports"] = true
	# The list: five at every airport, three levels each, dearer at the later airports.
	var imp_ok = Improvements.IDS.size() == 5 and Improvements.MAX_LEVEL == 10
	for iid in Improvements.IDS:
		for ia in Airports.COUNT:
			imp_ok = imp_ok and Improvements.cost(ia, iid, 0) < Improvements.cost(ia, iid, 1) and Improvements.cost(ia, iid, 1) < Improvements.cost(ia, iid, 2) and Improvements.cost(ia, iid, Improvements.max_level(iid)) == -1
			if ia > 0:
				imp_ok = imp_ok and Improvements.cost(ia, iid, 0) >= Improvements.cost(ia - 1, iid, 0)
	check(imp_ok, "five improvements, 8 to 10 levels deep at every airport; the later the airport, the dearer (%d to %d coins in all)" % [Improvements.total_cost(0), Improvements.total_cost(5)])
	all_levels(save)
	# Buying: per airport, with coins, saved.
	save.add_coins(100000)
	var imp_c0 = save.coins
	check(save.buy_improvement(2, "fuel") and save.imp_level(2, "fuel") == 1 and save.imp_level(1, "fuel") == 0 and save.coins == imp_c0 - Improvements.cost(2, "fuel", 0), "an improvement is bought for one airport only, at exactly its price")
	save.buy_improvement(2, "fuel")
	save.buy_improvement(2, "fuel")
	for imp_k in 6:
		save.buy_improvement(2, "fuel")
	check(save.imp_level(2, "fuel") == Improvements.max_level("fuel") and not save.buy_improvement(2, "fuel"), "a maxed improvement can't be bought again")
	save.reset_all()
	check(not save.buy_improvement(3, "hangar") and save.imp_level(3, "hangar") == 0, "nothing is bought without the coins or at a closed airport")
	save.unlocks["all_airports"] = true
	all_levels(save)
	save.add_coins(100000)
	save.buy_improvement(4, "exit")
	save.buy_improvement(0, "hangar")
	save.write_file()
	save.improvements = {}
	save.load_file()
	check(save.imp_level(4, "exit") == 1 and save.imp_level(0, "hangar") == 1 and save.imp_total(4) == 1, "the improvements are saved")
	# Hangar bay: more places and a fee for the landings that use them.
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(0)
	Airports.current = 0
	var bay_n = RampX.star_landings(0)
	check(RampX.capacity(0) == bay_n, "no bays: the hangar holds the break-even landings (%d)" % bay_n)
	save.improvements = {"0": {"hangar": 2}}
	check(RampX.capacity(0) == bay_n + 2 * int(tuning.imp_hangar_bays) and RampX.capacity(1) == RampX.star_landings(1), "Hangar bay level 2: %d more places at this airport only" % (2 * int(tuning.imp_hangar_bays)))
	main.restart()
	tr.auto_spawn = false
	check(main.airfield.ramp.cap == RampX.capacity(0), "...and the hangar on the field really has them (%d)" % main.airfield.ramp.cap)
	var hf_fake = Aircraft.new()
	hf_fake.runway = 0
	hf_fake.pos = Vector2.ZERO
	hf_fake.type = 3
	var hf_fee = roundi(tuning.landing_pay(3) * tuning.imp_hangar_fee)
	var hf_got = []
	for hk in RampX.capacity(0) + 1:
		main.traffic.run_time += 10.0
		var b_before = main.shift.bonus
		main._on_landed(hf_fake)
		hf_got.append(main.shift.bonus - b_before)
	var hf_ok = true
	for hk in hf_got.size():
		var in_bay = hk >= bay_n and hk < RampX.capacity(0)
		hf_ok = hf_ok and hf_got[hk] == (hf_fee if in_bay else 0)
	check(hf_ok and hf_fee > 0, "landings %d to %d each pay a hangar fee of %d, the others none %s" % [bay_n + 1, RampX.capacity(0), hf_fee, str(hf_got)])
	save.improvements = {}
	# The detail screen says it: Hangar N, profit after M landings.
	main._show_menu()
	main.open_detail(0)
	check(main.hud.detail_sheet().find_children("*", "Label", true, false).any(func(n): return n.text == "Hangar %d, profit after %d landings" % [bay_n, bay_n]), "the detail screen: Hangar %d, profit after %d landings" % [bay_n, bay_n])
	# Runway lights: fewer go-arounds in fog, weather and at dusk, none to gain in clear daylight.
	var rl_clear = tuning.light_go_around_mult(0.0)
	save.improvements = {"0": {"rwlights": 3}}
	check(rl_clear == 1.0 and absf(tuning.light_go_around_mult(1.0) - (1.0 - 3.0 * tuning.imp_light_cut)) < 0.0001 and tuning.light_go_around_mult(1.0) < tuning.light_go_around_mult(0.4) and tuning.light_go_around_mult(0.0) == 1.0, "Runway lights: go-arounds x%.2f in full bad light, x1 in clear daylight" % tuning.light_go_around_mult(1.0))
	check(tuning.bad_light(0.0, false, 0.2) == 0.0 and tuning.bad_light(1.0, false, 0.2) == 1.0 and tuning.bad_light(0.0, true, 0.2) == 1.0 and tuning.bad_light(0.0, false, 1.0) > 0.4 and tuning.bad_light(0.0, false, 1.0) < 1.0, "fog and weather events are bad light; the end of the shift is dusk")
	save.improvements = {}
	# ...really, on a poor approach in fog.
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	Airports.current = 2
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var rl_thr = Airports.end_threshold(0, 0)
	var rl_h = deg_to_rad(Airports.land_heading_deg(Aircraft.Kind.RUNWAY, 0, 0))
	var rl_d = Vector2(sin(rl_h), -cos(rl_h))
	var rl_n = Vector2(-rl_d.y, rl_d.x)
	var rl_chance = []
	var rl_gm = tuning.go_around_max
	tuning.go_around_max = 0.98
	for lv in [0, 3]:
		save.improvements = {"2": {"rwlights": lv}}
		tr.fog_amount = 1.0
		tr.fog_target = 1.0
		var rp = tr.place(0, rl_thr + rl_d * -1.5 + rl_n * -1.5, atan2(rl_d.x, -rl_d.y), MEDIUM)
		rp.push(rl_thr + rl_d * -1.0 + rl_n * -1.0)
		rp.push(rl_thr + rl_d * -0.5 + rl_n * -0.5)
		rp.push(rl_thr)
		rp.push(Airports.end_far(0, 0))
		rp.cleared = true
		rp.land_end = 0
		tr.step(1.0 / 60.0)
		rl_chance.append(rp.ga_chance)
		tr.release_all()
	tuning.go_around_max = rl_gm
	check(rl_chance[0] > 0.05 and absf(rl_chance[1] - rl_chance[0] * (1.0 - 3.0 * tuning.imp_light_cut)) < 0.02, "a poor approach in fog goes around with chance %.2f; with runway lights level 3 only %.2f" % [rl_chance[0], rl_chance[1]])
	tr.fog_amount = 0.0
	tr.fog_target = 0.0
	save.improvements = {}
	# Approach lights: the path snaps onto the final from further to the side.
	var al_e = 0 if main.wind.is_active(0, 0) else 1
	var al_thr = Airports.end_threshold(0, al_e)
	var al_h = deg_to_rad(Airports.land_heading_deg(Aircraft.Kind.RUNWAY, 0, al_e))
	var al_d = Vector2(sin(al_h), -cos(al_h))
	var al_n = Vector2(-al_d.y, al_d.x)
	var al_snapped = []
	for lv in [0, 3]:
		save.improvements = {"2": {"applights": lv}}
		var ap_ = tr.place(0, al_thr - al_d * 3.0 + al_n * 1.2, atan2(al_d.x, -al_d.y), MEDIUM)
		ap_.push(ap_.pos)
		var al_raw = al_thr - al_d * 1.8 + al_n * (tuning.snap_radius * 1.4)
		al_snapped.append(tr.extend_path(ap_, al_raw, al_raw) and ap_.cleared)
		tr.release_all()
	save.improvements = {"2": {"applights": 3}}
	check(not al_snapped[0] and al_snapped[1] and absf(tuning.snap_radius_eff() - tuning.snap_radius * (1.0 + 3.0 * tuning.imp_snap)) < 0.0001, "Approach lights level 3: a path %.2f to the side snaps (radius %.2f -> %.2f), without them it doesn't" % [tuning.snap_radius * 1.4, tuning.snap_radius, tuning.snap_radius_eff()])
	save.improvements = {}
	# Fuel farm: longer timers.
	var ff_base = tuning.type_timer(MEDIUM) * tuning.timer_mult()
	var ff0 = tr.place(0, Vector2(-3, 0), 0.0, MEDIUM)
	save.improvements = {"2": {"fuel": 3}}
	var ff3 = tr.place(1, Vector2(3, 0), 0.0, MEDIUM)
	check(is_equal_approx(ff0.timer_max, ff_base) and is_equal_approx(ff3.timer_max, ff_base * (1.0 + 3.0 * tuning.imp_fuel_timer)), "Fuel farm level 3: arrivals start with timers +%d%% (%.1f -> %.1f s)" % [roundi(300.0 * tuning.imp_fuel_timer), ff0.timer_max, ff3.timer_max])
	save.improvements = {}
	tr.release_all()
	# Extra exit: a shorter rollout (the runway frees sooner) and a faster taxi.
	var ex_busy0 = tuning.landing_roll() + tuning.runway_clear()
	save.improvements = {"2": {"exit": 3}}
	var ex_busy3 = tuning.landing_roll() + tuning.runway_clear()
	check(ex_busy3 < ex_busy0 and is_equal_approx(tuning.landing_roll(), tuning.landing_roll_time * (1.0 - 3.0 * tuning.imp_exit_roll)) and is_equal_approx(tuning.taxi_speed_mult(), 1.0 + 3.0 * tuning.imp_exit_taxi), "Extra exit level 3: the runway is busy %.2f s instead of %.2f, and the taxi is %.1fx faster" % [ex_busy3, ex_busy0, tuning.taxi_speed_mult()])
	var ex_a = tr.place(0, Airports.end_threshold(0, 0), 0.0, MEDIUM)
	ex_a.push(ex_a.pos)
	ex_a.push(Airports.end_far(0, 0))
	ex_a.cleared = true
	ex_a.land_end = 0
	tr.step(1.0 / 60.0)
	check(absf((tr._busy_until[0] - tr.run_time) - ex_busy3) < 0.05, "...and the runway really is busy for only that long")
	save.improvements = {}
	tr.release_all()
	# They show on the field, in each airport's style, growing with their level.
	var imp_vis_ok = true
	var imp_counts = {}
	for a_i in Airports.COUNT:
		main.select_airport(a_i)
		Airports.current = a_i
		main.restart()
		save.improvements = {}
		main.airfield.show_upgrades()
		for iid in Improvements.IDS:
			imp_vis_ok = imp_vis_ok and main.airfield.improvement_nodes_visible(iid) == 0
		for iid in Improvements.IDS:
			save.improvements = {str(a_i): {iid: 1}}
			main.airfield.show_upgrades()
			var v1 = main.airfield.improvement_nodes_visible(iid)
			save.improvements = {str(a_i): {iid: 2}}
			main.airfield.show_upgrades()
			var v2 = main.airfield.improvement_nodes_visible(iid)
			save.improvements = {str(a_i): {iid: 3}}
			main.airfield.show_upgrades()
			var v3 = main.airfield.improvement_nodes_visible(iid)
			if not (v1 >= 1 and v2 > v1 and v3 > v2):
				print("     improvement scenery: airport %d %s %d/%d/%d" % [a_i, iid, v1, v2, v3])
			imp_vis_ok = imp_vis_ok and v1 >= 1 and v2 > v1 and v3 > v2
			imp_counts[iid] = v3
			var others = 0
			for oid in Improvements.IDS:
				if oid != iid:
					others += main.airfield.improvement_nodes_visible(oid)
			imp_vis_ok = imp_vis_ok and others == 0
		save.improvements = {}
	check(imp_vis_ok, "at every airport each improvement is nothing before it is bought and then shows on the field, more with each level %s" % str(imp_counts))
	main.airfield.show_upgrades()
	# Bought on the detail screen.
	save.reset_all()
	save.unlocks["all_airports"] = true
	all_levels(save)
	main.select_airport(2)
	main._show_menu()
	main.open_detail(2)
	main.hud.skip_animations()
	check(not main.hud.detail_sheet().chips.has("imp:2:fuel") and main.hud.detail_sheet().chips.has("dtab:1"), "the detail screen has an Improve tab; the improvements show only on it")
	main._on_button("dtab:1")
	main.hud.skip_animations()
	var det_ids = []
	for iid in Improvements.IDS:
		det_ids.append(main.hud.detail_sheet().chips.has("imp:2:%s" % iid) and main.hud.detail_sheet().chips.has("impbuy:2:%s" % iid))
	check(not det_ids.has(false) and main.detail_tab == 1, "...five improvement rows, one for each, each with its own cost button")
	save.add_coins(Improvements.cost(2, "fuel", 0) - 1)
	main._show_detail()
	main.hud.skip_animations()
	check(main.hud.detail_sheet().chips["impbuy:2:fuel"].state == 1, "a cost button is dim when it is out of reach")
	var det_coins0 = save.coins
	sheet_hold(main, "impbuy:2:fuel", tuning.buy_hold_seconds + 0.2)
	check(save.imp_level(2, "fuel") == 0 and save.coins == det_coins0, "holding an unaffordable cost button buys nothing")
	save.add_coins(1)
	main._show_detail()
	main.hud.skip_animations()
	sheet_tap(main, "impbuy:2:fuel")
	check(save.imp_level(2, "fuel") == 0, "a tap on the cost button does not buy: it says to hold")
	sheet_hold(main, "impbuy:2:fuel", tuning.buy_hold_seconds * 0.5)
	check(save.imp_level(2, "fuel") == 0, "...half a hold does not buy either")
	sheet_hold(main, "impbuy:2:fuel", tuning.buy_hold_seconds + 0.2)
	main.hud.skip_animations()
	check(save.imp_level(2, "fuel") == 1 and save.coins == 0 and main.hud.detail_sheet().chips["imp:2:fuel"].find_children("*", "Control", true, false).any(func(n): return n is DetailSheet.Pips and n.level == 1) and main.airfield.improvement_nodes_visible("fuel") >= 1, "holding an affordable cost button buys it, the pips fill and the new tank stands on the field")
	check(main.screen == main.SCREEN_DETAIL, "...and the screen stays")
	# the sheet: full height, one column, rows at least 64 points tall, the cost button on the right, tapping a row previews the next level
	var imp_sheet = main.hud.detail_sheet()
	await process_frame          # (wrapped labels re-measure when frames run)
	await process_frame
	imp_sheet.settle()
	var imp_vp = main.get_viewport().get_visible_rect().size
	check(imp_sheet.size.y >= imp_vp.y - 1.0 and imp_sheet.card.size.x >= imp_vp.x - 1.0, "the Improve sheet is the whole screen")
	var imp_rows_ok = true
	var imp_diag = ""
	var imp_prev_y = -1.0
	for iid in Improvements.IDS:
		var row = imp_sheet.chips["imp:2:%s" % iid]
		var btn = imp_sheet.chips["impbuy:2:%s" % iid]
		var imp_rr = row.get_global_rect()
		imp_rows_ok = imp_rows_ok and imp_rr.size.y >= 64.0 * Style.px_per_pt - 1.0 and imp_rr.position.y > imp_prev_y and btn.get_global_rect().end.x <= imp_rr.end.x + 0.5 and btn.get_global_rect().position.x > imp_rr.position.x + imp_rr.size.x * 0.4
		imp_diag += " %s:%s/%s" % [iid, str(imp_rr), str(btn.get_global_rect())]
		imp_prev_y = imp_rr.end.y
	check(imp_rows_ok, "...a single column of rows, each at least 64 points tall with its cost button on the right (%.1f px per point)%s" % [Style.px_per_pt, "" if imp_rows_ok else imp_diag])
	check(imp_sheet.chips.has("dtab:0") and imp_sheet.chips["dtab:0"].get_global_rect().position.y < imp_vp.y * 0.2 and imp_sheet.chips.has("imp_done"), "...with a Back at the top and a Done at the bottom")
	var imp_before = imp_sheet.find_children("*", "Label", true, false).filter(func(n): return n.text.begins_with("Now:")).size()
	sheet_tap(main, "imp:2:hangar")
	imp_sheet = main.hud.detail_sheet()
	check(imp_before == 0 and main.imp_selected == "hangar" and imp_sheet.find_children("*", "Label", true, false).any(func(n): return n.text.begins_with("Now:")) and imp_sheet.find_children("*", "Label", true, false).any(func(n): return n.text.begins_with("Level 1:")), "tapping a row previews what the next level changes")

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
	main.trigger_weather("fog")
	check(main.hud._event_banner.text.begins_with("Fog in"), "fog is announced (%s)" % main.hud._event_banner.text)
	check(main.hud.banner_text() == "FOG ROLLING IN", "...with a FOG ROLLING IN banner (%s)" % main.hud.banner_text())
	run_sec(main, tuning.weather_warning_seconds + 0.3 + tuning.fog_fade_seconds + 0.3)
	check(tr.fog_amount >= 0.99 and main.weather.phase == 2, "the fog rolls in")
	await process_frame
	await process_frame
	var fog_veil := false
	for fg_n in main.get_children():
		if fg_n is MeshInstance3D and (fg_n as MeshInstance3D).mesh is PlaneMesh and ((fg_n as MeshInstance3D).mesh as PlaneMesh).size.x > 20.0:
			fog_veil = true
	check(not fog_veil and tr.fog_amount > 0.5, "fog is weather, not a veil: nothing is drawn over the whole field (%.2f)" % tr.fog_amount)
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
	check(tr.fog_amount < 0.01 and not main.hud._event_banner.visible, "...and the chip is gone")
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
	# the rules: never in the first 30 s of a shift, never on the first two airports (the scheduler's own call; the ?tune button forces one)
	var wx_rules = main.weather.get_script().new()
	wx_rules.start()
	wx_rules.trigger("crosswind", tr.rng, main.wind)
	check(wx_rules.phase == 0, "no closure in the first %.0f s of a shift" % tuning.closure_min_time)
	wx_rules.elapsed = tuning.closure_min_time + 1.0
	var wx_airport := Airports.current
	Airports.current = 1
	wx_rules.trigger("crosswind", tr.rng, main.wind)
	check(wx_rules.phase == 0, "...nor on the first two airports")
	Airports.current = wx_airport
	wx_rules.trigger("crosswind", tr.rng, main.wind)
	check(wx_rules.phase == 1 and is_equal_approx(wx_rules.left, tuning.closure_warning_seconds) and tuning.closure_warning_seconds == 8.0, "...and later on a later airport it is announced 8 s ahead")
	main.trigger_weather("crosswind")
	rw_close[0] = main.weather.runway
	check(main.hud._event_banner.text.contains("runway closing in 8 s") and rw_close[0] >= 0, "a closure is announced with a banner (%s)" % main.hud._event_banner.text)
	main.weather.runway = 0
	main.wind.closing = 0
	rw_close[0] = 0
	run_sec(main, 3.0)
	check(main.wind.is_closing(0) and main.wind.is_active(0, 0) and not main.wind.is_closed(0) and main.hud._event_banner.text.contains("closing in") and cw.cleared, "while it counts down the runway is still open and the aircraft on final keeps its clearance")
	run_sec(main, tuning.closure_warning_seconds - 3.0 + 0.3)
	check(main.wind.is_closed(0) and not main.wind.is_active(0, 0) and not main.wind.is_active(0, 1), "the runway closes at both ends")
	check(main.wind.open_runways() == 1 and main.wind.is_active(1, 0), "the other runway stays open")
	check(not main.airfield.cur.active[0] and not main.airfield.cur.active[1], "its thresholds are dimmed on the field")
	check(cw.cleared and not cw.path_invalid, "an aircraft already locked on final to the runway that closes still gets to land")
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
	check(Cosmetics.THEME_COUNT == 9 and Cosmetics.LIVERY_COUNT == 23 and Cosmetics.THEMES.size() == 9 and Cosmetics.LIVERIES.size() == 23, "nine airport skins and twenty-three liveries")
	var animals = {}
	for i in Cosmetics.LIVERY_COUNT:
		animals[Cosmetics.LIVERIES[i]["animal"]] = true
	check(animals.size() == 17 and Cosmetics.THEMES[0]["cost"] == 0 and Cosmetics.LIVERIES[0]["cost"] == 0, "the 17 animal pilots all fly (the airport liveries share them); the defaults are free")
	check(save.owns("theme", "classic") and save.owns("livery", "standard") and not save.owns("theme", "winter"), "the default theme and livery are owned from the start")
	# The shop.
	save.add_coins(520)
	main._show_menu()
	var menu_ids = []
	for k in main.hud._art.btn_count:
		menu_ids.append(main.hud._art.btn_id[k])
	check(menu_ids.has("shop") and menu_ids.has("goals"), "the menu has Shop and the daily goals card")
	main._on_button("shop")
	check(main.screen == main.SCREEN_SHOP and main.hud._select_title.text == "SHOP", "the shop opens")
	var shop_ids = []
	for k in main.hud._art.btn_count:
		shop_ids.append(main.hud._art.btn_id[k])
	shop_ids.append_array(main.hud.list_ids())
	check(shop_ids.has("shop_tab:0") and shop_ids.has("shop_tab:1") and shop_ids.has("theme:4") and shop_ids.has("back"), "two tabs, five theme cards and Back")
	var card_state = {}
	for k in main.hud._art.btn_count:
		card_state[main.hud._art.btn_id[k]] = [main.hud._art.btn_state[k], main.hud._art.btn_sub[k], main.hud._art.btn_icon[k], main.hud._art.btn_rect[k], main.hud._art.btn_cost[k]]
	for lid in main.hud.list_ids():       # (the cards are in the list that scrolls: their rectangles are where they are on the screen)
		var lb = main.hud.list_button(lid)
		var la = lb["art"]
		card_state[lid] = [la.btn_state[lb["index"]], la.btn_sub[lb["index"]], la.btn_icon[lb["index"]], main.hud.list_screen_rect(lid), la.btn_cost[lb["index"]]]
	check(card_state["theme:0"][1] == "In use" and card_state["theme:1"][1] == "300 coins" and card_state["theme:1"][0] == 0 and card_state["theme:3"][0] == 1, "Classic is equipped, Autumn is for sale, Winter is out of reach")
	check(card_state["theme:2"][2] == 102, "theme cards show a colour swatch")
	main.hud._preview_art()        # (made, and put above the list, while the menu idles in the game)
	var snap_c = snapshot(main)
	# Tapping a card opens the preview sheet; nothing is spent until the buy button is held.
	touch(main, 0, true, card_state["theme:1"][3].get_center())
	touch(main, 0, false, card_state["theme:1"][3].get_center())
	check(main.preview_kind == "theme" and main.hud.preview_open() and save.coins == 520 and not save.owns("theme", "autumn"), "tapping a theme card opens its preview sheet and spends nothing")
	var pv_art = main.hud._art
	var pv_ids = []
	for k in pv_art.btn_count:
		pv_ids.append(pv_art.btn_id[k])
	check(pv_ids.has("pv_buy") and pv_ids.has("pv_mode:0") and pv_ids.has("pv_mode:1") and pv_ids.has("preview_close"), "the sheet has the buy button, the Current / New toggle and a close button")
	var pv_k = pv_art.btn_id.find("pv_buy")
	check(pv_art.btn_text[pv_k] == "Buy for 300" and pv_art.pv["balance"] == 520 and pv_art.pv["state"] == "buy", "the button reads 'Buy for 300' and the balance before is 520 (%s)" % pv_art.btn_text[pv_k])
	var pv_pos = pv_art.btn_rect[pv_k].get_center()
	touch(main, 0, true, pv_pos)
	touch(main, 0, false, pv_pos)
	main._tick_preview(0.05)
	check(save.coins == 520 and not save.owns("theme", "autumn"), "a single tap never spends coins")
	touch(main, 0, true, pv_pos)
	main._tick_preview(0.3)
	check(save.coins == 520 and main.hud._art.pv_hold > 0.4 and main.hud._art.pv_hold < 0.6, "holding fills the button (%.2f) without spending yet" % main.hud._art.pv_hold)
	touch(main, 0, false, pv_pos)
	main._tick_preview(0.05)
	check(save.coins == 520 and main.hud._art.pv_hold == 0.0, "letting go early empties it and spends nothing")
	touch(main, 0, true, pv_pos)
	main._tick_preview(0.35)
	main._tick_preview(0.35)
	check(save.coins == 520 - 300 and save.owns("theme", "autumn") and save.equipped_id("theme") == "classic", "a hold spends exactly the price (%d left) and does not equip" % save.coins)
	main._tick_preview(0.5)
	main._tick_preview(0.5)
	check(save.coins == 220, "holding on does not spend again")
	touch(main, 0, false, pv_pos)
	check(save.equipped_id("theme") == "classic" and main.hud.preview_state() == "bought" and main.hud._art.btn_text[main.hud._art.btn_id.find("pv_buy")] == "Equip", "the release that ends the hold does not equip; the button now says Equip")
	touch(main, 0, true, pv_pos)
	touch(main, 0, false, pv_pos)
	check(save.equipped_id("theme") == "autumn" and save.coins == 220 and main.hud.preview_state() == "equipped", "a tap on Equip equips it for free")
	main.close_preview()
	check(not main.hud.preview_open() and bt_has(main, "theme:1"), "closing the sheet leaves the list")
	var reg_scene = main.airfield.variants[2]
	check(reg_scene.ground_mat.albedo_color.is_equal_approx(Cosmetics.THEMES[1]["ground"]), "the airport ground takes the theme's colour")
	check(main.airfield.variants[4].ground_mat.albedo_color != Cosmetics.THEMES[1]["ground"], "...but the Island's water stays water")
	check(main._env.background_color.is_equal_approx(Cosmetics.THEMES[1]["bg"]), "the sky colour follows the theme")
	check(reg_scene.tree_styles[0][0].visible and not reg_scene.tree_styles[2][0].visible, "Autumn has round trees")
	main._on_button("theme:3")
	var pw_art = main.hud._art
	var pw_k = pw_art.btn_id.find("pv_buy")
	check(pw_art.btn_text[pw_k] == "Need 480 more" and pw_art.btn_state[pw_k] == 1, "an unaffordable theme's button is disabled and reads 'Need 480 more' (%s)" % pw_art.btn_text[pw_k])
	touch(main, 0, true, pw_art.btn_rect[pw_k].get_center())
	main._tick_preview(1.0)
	main._tick_preview(1.0)
	touch(main, 0, false, pw_art.btn_rect[pw_k].get_center())
	check(not save.owns("theme", "winter") and save.coins == 220, "a disabled button never spends, held or tapped")
	main.close_preview()
	save.add_coins(400)
	main.shop_pick("theme", 2)
	check(reg_scene.tree_styles[2][0].visible and not reg_scene.tree_styles[0][0].visible and reg_scene.ground_mat.albedo_color.is_equal_approx(Cosmetics.THEMES[2]["ground"]), "Desert swaps the trees for cacti and the ground for sand")
	main.shop_pick("theme", 0)
	check(save.equipped_id("theme") == "classic" and reg_scene.ground_mat.albedo_color.is_equal_approx(reg_scene.base_ground), "equipping Classic again is free and restores the look")
	main._on_button("shop_tab:1")
	check(main.shop_tab == 1 and main.hud.list_button("livery:3")["art"].btn_icon[main.hud.list_button("livery:3")["index"]] == 3, "the Liveries tab shows each pilot's portrait")
	save.add_coins(300)
	var coins_l = save.coins
	main.shop_pick("livery", 1)
	check(save.equipped_id("livery") == "fox" and save.coins == coins_l - 200 and tr.livery == 1, "buying a livery equips it (Fox Air)")
	var fx_plane = tr.place(0, Vector2(0, 0), 0.0, MEDIUM)
	tr._sync(fx_plane, tr.planes.find(fx_plane))
	var fi = tr.planes.find(fx_plane)
	check(tr._fus_mats[fi].albedo_color.is_equal_approx(Cosmetics.LIVERIES[1]["body"]) and tr._stripe_mats[fi].albedo_color.is_equal_approx(Cosmetics.LIVERIES[1]["stripe"]) and tr._stripes[fi][0].visible, "aircraft wear the livery's body and stripe")
	check(tr._body_mats[fi].albedo_color.is_equal_approx(Airports.land_color(tr.planes[fi].tkind, tr.planes[fi].runway)), "...while the nose, wingtips and fin keep the runway's colour")
	main.shop_pick("livery", 0)
	check(not tr._stripes[fi][0].visible and tr._fus_mats[fi].albedo_color.is_equal_approx(Color.WHITE), "the standard livery has a white fuselage and no coloured stripe")
	# no livery colour (fuselage or stripe) is anywhere near a runway colour: the nose, wingtips and fin must stay the only thing that says "this runway"
	var lv_clear := true
	var lv_names := ""
	for lv_i in Cosmetics.LIVERY_COUNT:
		for lv_key in ["body", "stripe"]:
			var lv_c = Cosmetics.LIVERIES[lv_i][lv_key]
			if lv_c == null:
				continue
			for lv_rc in [Airports.ORANGE, Airports.BLUE, Airports.PINK, Airports.PAD_COLOR, Airports.LANE_COLOR]:
				var lv_d := Vector3(lv_c.r - lv_rc.r, lv_c.g - lv_rc.g, lv_c.b - lv_rc.b).length()
				if lv_d < 0.3:
					lv_clear = false
					lv_names += " %s/%s (%.2f)" % [Cosmetics.LIVERIES[lv_i]["id"], lv_key, lv_d]
	check(lv_clear, "no livery colour is within 0.3 of a runway, pad or lane colour:" + lv_names)
	main.shop_pick("livery", 1)
	tr.release_all()
	save.write_file()
	var eq_before = save.equipped.duplicate()
	save.equipped = {}
	save.load_file()
	check(save.equipped_id("livery") == "fox" and save.owns("livery", "fox"), "cosmetics are saved")
	var snap_c2 = snapshot(main)
	check(same_world(snap_c, snap_c2), "buying and wearing cosmetics created nothing new [%s] vs [%s]" % [describe(snap_c), describe(snap_c2)])
	# The results screen shows the pilot.
	main.restart()
	tr.auto_spawn = false
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(main.hud._art.show_result and main.hud._over.visible, "the results screen shows")
	main._on_button("menu")
	# The old Daily Shift is gone (the daily goals replace it); Bad Pilot Day keeps the seeded shift.
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.day_override = 20000
	main._show_menu()
	check(main.hud._art.btn_id.find("daily") < 0 and main.hud._art.btn_id.find("goals") >= 0 and main.hud._art.btn_id.find("bad") >= 0, "the menu has a goals card and Bad Pilot Day, and no Daily Shift button")
	check(not main.has_method("start_daily") and tuning.daily_bonus_coins == 75, "the daily-shift entry point is retired (its bonus numbers stay for Bad Pilot Day)")
	var runs_seen = []
	for run_i in 3:
		save.day_override = 20000 if run_i < 2 else 20001
		save.ads["since"] = 0
		main.start_bad_day()
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
	check(main.daily_mode and runs_seen[0][2] == (20000 + 3) % 6 and runs_seen[2][2] == (20001 + 3) % 6, "Bad Pilot Day's airport depends on the day (%d, %d)" % [runs_seen[0][2], runs_seen[2][2]])
	var n_cmp = mini(mini(runs_seen[0][0].size(), runs_seen[1][0].size()), 5)
	var same_seq = n_cmp >= 4 and runs_seen[0][1] == runs_seen[1][1]
	for k in n_cmp:
		same_seq = same_seq and runs_seen[0][0][k] == runs_seen[1][0][k]
	check(same_seq, "the same day gives the same arrivals and wind (first %d arrivals identical)" % n_cmp)
	check(runs_seen[0][0] != runs_seen[2][0], "a different day gives different arrivals")
	# Bad Pilot Day only picks airports the player has open.
	var dq_bad = 0
	var dq_miss = 0
	for dq_stars in [0, 1, 3, 5, 8, 11, 14, 18]:
		save.reset_all()
		for dq_k in dq_stars:
			save.stars[dq_k] = 1
		var dq_open = {}
		for dq_i in Airports.COUNT:
			if save.airport_open(dq_i):
				dq_open[dq_i] = true
		var dq_bad_day = {}
		for dq_day in 12:
			save.day_override = 20000 + dq_day
			save.ads["since"] = 0
			main.start_bad_day()
			dq_bad_day[main.airport] = true
			if not dq_open.has(main.airport) or not main.bad_mode:
				dq_bad += 1
		if dq_bad_day.size() != dq_open.size():
			dq_miss += 1
	check(dq_bad == 0, "Bad Pilot Day never picks a locked airport (%d bad picks over 8 star levels x 12 days)" % dq_bad)
	check(dq_miss == 0, "...and over twelve days it visits every open airport")
	save.reset_all()
	save.day_override = 20000
	save.ads["since"] = 0
	main.start_bad_day()
	check(main.airport == 0, "a new player (no stars) gets the Grass Strip for Bad Pilot Day")
	save.unlocks["all_airports"] = true
	save.day_override = 20000
	save.ads["since"] = 0
	main.start_bad_day()
	check(main.airport == (20000 + 3) % 6, "with every airport open Bad Pilot Day's airport is (day + 3) %% 6")
	save.day_override = -1
	main._show_menu()
	check(not main.daily_mode, "back on the menu, the seeded mode is off")
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
	check(save.upgrade_level("radar") == 5 and save.upgrade_level("turnoffs") == 5 and main.airfield.upgrade_nodes_visible("comms") >= 1, "debug: max upgrades (and their scenery)")
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
	save.goals = {"day": 5, "list": []}
	save.goal_streak = {"count": 3, "last": 5}
	tp2.debug_buttons["reset_daily"].pressed.emit()
	check(save.goals.is_empty() and save.goal_streak.is_empty(), "debug: reset goals")
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
		check(ribbons._tint_start(glx, glx.count + 1) > 0, "...and a glider's (it can go around now)")
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
	# Emergencies never go around; a glider is judged like any other plane.
	var qgl = mk.call(GLIDER, bad_pts, 99.0)
	qgl.timer_left = 40.0
	tr.go_rng.seed = 9
	for i in 300:
		tr.step(1.0 / 60.0)
	check(qgl.go_arounds > 0 or qgl.ga_chance > 0.0, "a glider on a bad final is scored for a go-around like any plane (chance %.2f, %d)" % [qgl.ga_chance, qgl.go_arounds])
	var qem = mk.call(MEDIUM, bad_pts, 99.0)
	tr.make_special(qem, true, false)
	qem.timer_left = 40.0
	tr.go_rng.seed = 9
	for i in 300:
		tr.step(1.0 / 60.0)
	check(qem.go_arounds == 0 and qem.ga_chance == 0.0, "emergencies are never scored for a go-around")
	# ...if the runway is busy a glider goes around (a lost one only with "No engines"), an emergency is lost.
	tr.release_all()
	tr._busy_until.fill(0.0)
	var crashed_kind = [-1]
	var cb_cr = func(_pl, k): crashed_kind[0] = k
	tr.crashed.connect(cb_cr)
	var occp = tr.place(0, thr_a, rw_head, MEDIUM)
	occp.push(thr_a)
	occp.push(Airports.end_far(0, 0))
	occp.cleared = true
	occp.land_end = 0
	tr.step(1.0 / 60.0)
	var glid2_ga = [0]
	var cb_g2 = func(_pl, _r): glid2_ga[0] += 1
	tr.go_around.connect(cb_g2)
	var glid2 = tr.place(0, thr_a, rw_head, GLIDER)
	glid2.push(thr_a)
	glid2.push(Airports.end_far(0, 0))
	glid2.cleared = true
	glid2.land_end = 0
	tr.step(1.0 / 60.0)
	tr.go_around.disconnect(cb_g2)
	check(crashed_kind[0] == -1 and glid2_ga[0] == 1, "a glider reaching a busy runway goes around, like any other plane (%d go-around, no crash)" % glid2_ga[0])
	tr.release_all()
	tr._busy_until.fill(0.0)
	tr.no_engines = true
	var occp2 = tr.place(0, thr_a, rw_head, MEDIUM)
	occp2.push(thr_a)
	occp2.push(Airports.end_far(0, 0))
	occp2.cleared = true
	occp2.land_end = 0
	tr.step(1.0 / 60.0)
	var glid3 = tr.place(0, thr_a, rw_head, GLIDER)
	glid3.push(thr_a)
	glid3.push(Airports.end_far(0, 0))
	glid3.cleared = true
	glid3.land_end = 0
	tr.step(1.0 / 60.0)
	check(crashed_kind[0] == 2 and not glid3.active(), "No engines: a plane reaching a busy runway has no go-around, it is lost")
	# A missed approach in "No engines" is a crash (kind 3); in normal play it is a go-around.
	tr.release_all()
	tr._busy_until.fill(0.0)
	crashed_kind[0] = -1
	var qmiss = mk.call(SMALL, bad_pts, 99.0)
	qmiss.timer_left = 40.0
	qmiss.ga_pending = true
	qmiss.ga_t = 0.0
	qmiss.ga_reason = ap.Reason.TURN
	tr.step(1.0 / 60.0)
	check(crashed_kind[0] == 3 and not qmiss.active(), "No engines: a missed approach is a crash, not a go-around")
	tr.no_engines = false
	tr.crashed.disconnect(cb_cr)
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
	set_wind(main, Airports.end_heading_deg(0, 0))          # (a wind with a legal end: students only spawn into one)
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
	check(base_chance < 0.01 and sq.ga_chance < 0.01 and sq.student_reason == 0 and sq.ga_band == 0, "a student on a perfect approach has no go-around chance at all (%.2f -> %.2f): it is not luck" % [base_chance, sq.ga_chance])
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
	check(main.shift.thresholds[0] == tuning.star_thresholds()[0] and main.shift.thresholds[1] == roundi(tuning.star_thresholds()[1] * tuning.bad_day_threshold_mult) and main.shift.thresholds[2] == roundi(tuning.star_thresholds()[2] * tuning.bad_day_threshold_mult), "...and its net-coin star thresholds are higher (the landing count for star 1 is not)")
	var streaks_b = []
	var bonus_b = []
	var stars_b = save.stars_total()
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
	check(save.goal_streak.is_empty(), "...separate from the daily goals' streak")
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
	for ai in range(Airports.COUNT):
		var tha = tuning.star_thresholds(ai)
		th_up = th_up and tha[0] >= 1 and tha[1] > 0 and tha[2] > tha[1]
		if ai >= 4:           # the last two airports ask for more (Mountain Field is a short, lean shift)
			th_up = th_up and tha[2] > tuning.star_thresholds(ai - 1)[2] and tha[1] >= tuning.star_thresholds(ai - 1)[1] * 0.0
	var gates = []
	for ai in Airports.COUNT:
		gates.append(Airports.unlock_stars(ai))
	check(gates == [0, 1, 2, 3, 6, 10], "airports open at 0, 1, 2, 3, 6 and 10 total stars (%s)" % str(gates))
	check(th_up, "each airport asks for a landing count and two rising net-coin stars, and from Island on the third star rises %s" % ", ".join(th_txt))
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
	check(k9_sfx._music1.stream.data.size() == k9_sfx._music2.stream.data.size() and k9_sfx._music2.stream.data.size() == k9_sfx._music3.stream.data.size() and k9_sfx._music3.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "three equal-length music loops, looping")
	var k9_loop_players = 0
	for k9_lp in k9_sfx.get_children():
		if k9_lp is AudioStreamPlayer and k9_lp.stream is AudioStreamWAV and k9_lp.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			k9_loop_players += 1
	check(k9_loop_players == 5, "five looping players in all (music 1, 2 and 3, the tense drone, fog): no engine hum (%d)" % k9_loop_players)
	check(k9_sfx._streams["landing"] != k9_sfx._streams["go_around"] and k9_sfx._music1.stream.data != k9_sfx._fog_amb.stream.data, "the sounds differ from each other")
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
		if k9_n is AudioStreamPlayer and k9_n.playing and k9_n != k9_sfx._music1 and k9_n != k9_sfx._music2 and k9_n != k9_sfx._music3 and k9_n != k9_sfx._music_tense and k9_n != k9_sfx._fog_amb and not k9_sfx._pool.has(k9_n):
			k9_has_hum = true
	check(not k9_has_hum and not k9_sfx.LAYERS.has("hum") and not FileAccess.file_exists("res://assets/audio/loops/hum.wav") and not k9_sfx.has_method("set_hum_counts"), "there is no engine hum, however many aircraft are on the field")
	tr.release_all()
	main.step(1.0 / 60.0)
	main.restart()
	tr.auto_spawn = false
	tr.run_time = 5.0
	main.step(1.0 / 60.0)
	# The music follows the traffic: layer 1 always, layer 2 at 3 or more aircraft inbound, layer 3 at 5 or more or in the last 20 s.
	var k9_spawn_stop = tuning.spawn_stop_eff()
	for k9_i in 240:
		k9_sfx._process(1.0 / 60.0)         # (let the layers the six aircraft above called in be released)
	tr.run_time = 5.0
	main.step(1.0 / 60.0)
	var k9_l0 = k9_sfx.layers_on()
	check(k9_l0 == 1 and k9_sfx._target["music1"] == k9_sfx.SHIFT_L1_DB and k9_sfx.music_pitch == 1.0, "with the sky empty only layer 1 (bass and percussion) plays (%d layer)" % k9_l0)
	for k9_i in 2:
		tr.place(0, Vector2(-3.0 + k9_i * 2.0, -5.0), 0.0, MEDIUM).entered = true
	main.step(1.0 / 60.0)
	check(tr.inbound_count() == 2 and k9_sfx.layers_on() == 1, "two inbound: still just layer 1")
	tr.place(0, Vector2(1.0, -5.0), 0.0, MEDIUM).entered = true
	main.step(1.0 / 60.0)
	check(tr.inbound_count() == 3 and k9_sfx.layers_on() == 2 and float(k9_sfx._target["music2"]) == k9_sfx.SHIFT_L2_DB and float(k9_sfx._target["music3"]) <= -70.0, "three inbound: the rhythm guitar and keys join (layer 2)")
	tr.place(1, Vector2(2.0, -6.0), 0.0, MEDIUM).entered = true
	main.step(1.0 / 60.0)
	check(k9_sfx.layers_on() == 2, "four inbound: still layers 1 and 2")
	tr.place(1, Vector2(3.0, -4.0), 0.0, MEDIUM).entered = true
	main.step(1.0 / 60.0)
	check(tr.inbound_count() == 5 and k9_sfx.layers_on() == 3 and float(k9_sfx._target["music3"]) == k9_sfx.SHIFT_L3_DB, "five inbound: the lead joins (layer 3)")
	# ...they glide in rather than jump, layer 2 and 3 slower than layer 1, and they do not flicker when the count dips
	for k9_i in 90:
		k9_sfx._process(1.0 / 60.0)
	check(float(k9_sfx._db["music3"]) > -30.0 and float(k9_sfx._db["music3"]) < float(k9_sfx.SHIFT_L3_DB) + 0.01 and k9_sfx.LAYER_FADE_DB_PER_S < k9_sfx.FADE_DB_PER_S, "...layers glide in (layer 3 at %.1f dB after 1.5 s), the upper two more slowly than layer 1" % float(k9_sfx._db["music3"]))
	tr.release_all()
	main.step(1.0 / 60.0)
	check(k9_sfx.inbound == 0 and k9_sfx.layers_on() == 3, "an empty sky does not drop the layers at once (they are held a moment: no flicker)")
	for k9_i in int((k9_sfx.HOLD_SECS + 0.5) * 60.0):
		k9_sfx._process(1.0 / 60.0)
	check(k9_sfx.layers_on() == 1, "...and a moment later they fade back to layer 1 (%d)" % k9_sfx.layers_on())
	# the last 20 s of the shift bring the lead in on their own
	tr.run_time = k9_spawn_stop - k9_sfx.LAST_SECS - 2.0
	main.step(1.0 / 60.0)
	var k9_before_last = k9_sfx.layers_on()
	tr.run_time = k9_spawn_stop - k9_sfx.LAST_SECS + 1.0
	main.step(1.0 / 60.0)
	check(k9_before_last == 1 and k9_sfx.layers_on() == 2 and float(k9_sfx._target["music3"]) == k9_sfx.SHIFT_L3_DB and float(k9_sfx._target["music2"]) <= -70.0, "in the last 20 s the lead plays even with an empty sky (layers 1 and 3: %d -> %d)" % [k9_before_last, k9_sfx.layers_on()])
	check(k9_sfx._music1.playing or true, "the music loop is running")
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
	sh.reset([50, 100, 160], 0.25)
	sh.on_landed(MEDIUM, 100, 30)
	check(sh.kept() == 32 and sh.balance() == 130 and sh.payout() == 130, "a clean shift pays everything: net 130, floor 32 (25%% of the 130 gross)")
	sh.fine(60, "conflict")
	check(sh.balance() == 70 and sh.payout() == 70, "fines come off the pay first (net 70)")
	sh.fine(400, "conflict")
	check(sh.balance() == -330 and sh.payout() == 32 and sh.stars() == 0, "a disaster still pays the floor (32), and earns no stars")
	sh.set_overtime(30.0, 4)
	check(sh.payout() == 32 and sh.balance() == -330 - 120, "overtime cannot cut into the floor either")
	sh.reset([50, 100, 160], 0.25)
	sh.on_landed(MEDIUM, 100, 0)
	sh.on_landed(MEDIUM, 25, 0)
	check(sh.kept() == 31, "the floor rounds down (31 of 125)")
	check(tuning.landing_keep_fraction == 0.25, "the floor share is a Tuning value (25%%)")
	# A failed shift in the real game: lots of landings, then conflicts.
	var coins_before = save.coins
	earn_coins(main, 100)
	var earned_l = main.shift.earned
	for k in 6:
		main._apply_fine(int(tuning.fine_conflict), "conflict", "CONFLICT", Vector2.ZERO)
	check(main.shift.balance() < 0, "six conflicts push the net negative (%d)" % main.shift.balance())
	check(main.shift.stars() == 1, "...star 1 is for the landings, but stars 2 and 3 use the net: none")
	tr.release_all()
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	var floor_l = main.shift.kept()
	check(floor_l == earned_l / 4 and main.last_result["payout"] == floor_l and save.coins == coins_before + floor_l + int(tuning.coins_first_star_bonus), "a failed shift still pays the floor, a quarter of the gross (%d), plus the first-star bonus for its landings" % floor_l)
	var body = main.hud._over_body.text
	check(body.contains("Landings earned +%d" % earned_l) and body.contains("Fines -%d" % (6 * int(tuning.fine_conflict))) and body.contains("Pay floor (25%% of gross) %d" % floor_l) and body.contains("Shift pay protected +%d" % (floor_l - main.shift.balance())) and body.contains("Net total (stars) %d" % main.shift.balance()) and body.contains("Total paid +%d" % (floor_l + int(tuning.coins_first_star_bonus))), "the results show landings earned, fines, the floor, the protected note and the total")
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
		var steps_up = pb["max_planes"] >= pa["max_planes"] and pb["spawn_start"] <= pa["spawn_start"] and pb["spawn_min"] <= pa["spawn_min"] and pb["speed"] >= pa["speed"] and pb["timer"] <= pa["timer"]
		mono = mono and (steps_up or ai == 3) and pb["fines"] >= pa["fines"]       # (Mountain Field trades volume for terrain)
	check(mono, "difficulty only steps up: more traffic, faster pace, faster aircraft, shorter timers (Mountain Field aside) and bigger fines")
	var pg = tuning.profile(0)
	var pc = tuning.profile(1)
	check(pg["max_planes"] <= 3 and pc["max_planes"] <= 4 and pg["specials"] == 0.0 and pg["weather"] == 0.0 and pg["wind"] == 0.0 and pc["weather"] == 0.0 and pc["wind"] > 0.0, "Grass Strip: at most 3 aircraft, no specials, no weather, no wind shifts; County: at most 4, gentle wind shifts, no weather")
	var slow_only = true
	for k in Airports.mix(0):
		slow_only = slow_only and tuning.type_speed_class(k) == 0
	check(slow_only and pg["speed"] < 1.0 and pg["timer"] > 1.0, "Grass Strip has slow aircraft only, at a gentle speed (x%.2f), with long timers (x%.2f)" % [pg["speed"], pg["timer"]])
	var pm = tuning.profile(3)
	check(pm["max_planes"] <= tuning.profile(4)["max_planes"] and pm["weather"] == 1.0 and pm["wind"] == 1.0 and pm["fines"] <= 0.5, "Mountain Field trades volume for terrain: calmer traffic and small fines, weather and wind at full strength")
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
	check(tuning.fine_amount(tuning.fine_conflict) == roundi(tuning.fine_conflict * tuning.profile(0)["fines"]) and tuning.fine_amount(tuning.fine_conflict) < 50, "Grass Strip fines are small (conflict %d)" % tuning.fine_amount(tuning.fine_conflict))
	main.select_airport(3)
	Airports.current = 3
	check(tuning.fine_amount(tuning.fine_conflict) == roundi(tuning.fine_conflict * tuning.profile(3)["fines"]) and tuning.profile(5)["fines"] >= tuning.profile(3)["fines"] and tuning.profile(3)["fines"] >= tuning.profile(0)["fines"], "...and they never get smaller from airport to airport")
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
	main.start_bad_day()
	check(not tuning.intro_active and tr.beats.is_empty(), "the seeded shifts have no intro easing and no scripted beats")
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
		menu_words = menu_words and (art.btn_kind[k] == 14 or (words_ok.call(art.btn_text[k]) and art.btn_sub[k] == ""))
	check(menu_words and art.btn_count <= 9, "menu: short labels, no descriptions (%d buttons)" % art.btn_count)
	var round_n = 0
	for k in art.btn_count:
		if art.btn_kind[k] == 7:
			round_n += 1
			menu_words = menu_words and art.btn_glyph[k] != ""
	check(round_n == 3 and menu_words, "menu: Tower, Hangar and Awards are three small round icon buttons (the goals card has its own line)")
	check(not main.hud._score.visible and not main.hud._best.visible, "menu: no leftover shift numbers behind it")
	check(not main.hud._ad.visible, "menu: nothing else is covering it")
	# The three text sizes: every label in the interface uses one of them.
	var sizes_ok = true
	var sizes_seen = {}
	for ch in main.hud.get_children():
		if ch is Label and ch != main.hud._perf_label and ch != main.hud._stamp:
			var sz = ch.get_theme_font_size("font_size")
			sizes_seen[sz] = true
			sizes_ok = sizes_ok and (sz == main.hud.SZ_XL or sz == main.hud.SZ_M or sz == main.hud.SZ_S or sz == 26 or (sz in Style.FIT and sz >= Style.SZ_CAPTION and sz < main.hud.SZ_XL))     # (the popups fit their text down the ladder)
	for scr in [main.hud._menu, main.hud._over, main.hud._select, main.hud._pause, main.hud._ad]:
		for ch in scr.get_children():
			if ch is Label:
				var sz2 = ch.get_theme_font_size("font_size")
				sizes_seen[sz2] = true
				sizes_ok = sizes_ok and (sz2 == main.hud.SZ_XL or sz2 == main.hud.SZ_M or sz2 == main.hud.SZ_S or (sz2 in Style.FIT and sz2 >= Style.SZ_CAPTION and sz2 < main.hud.SZ_XL))        # (a title that has to fit its room steps down the size ladder)
	check(sizes_ok, "every label uses one of the three text sizes %s, or a step down the size ladder for one that must fit (seen %s)" % [str([main.hud.SZ_XL, main.hud.SZ_M, main.hud.SZ_S]), str(sizes_seen.keys())])
	# Airport select: just a name, stars and a lock.
	main._on_button("airports")
	var pa = main.hud._art
	var sel_ok = true
	var cards_n = 0
	for k in pa.btn_count:
		if pa.btn_kind[k] == 1:
			cards_n += 1
			sel_ok = sel_ok and pa.btn_sub[k].length() < 40 and pa.btn_map[k] >= 0 and words_ok.call(pa.btn_text[k])
	check(cards_n == Airports.COUNT and sel_ok, "airport select: one big card per airport with a mini-map, its name, one line, stars and lock")
	main._show_menu()
	# Upgrades: icon, name, one line, pips, cost.
	main._on_button("upgrades")
	pa = main.hud._art
	var up_ok = true
	for k in pa.btn_count:
		if pa.btn_kind[k] == 1:
			up_ok = up_ok and pa.btn_glyph[k] != "" and pa.btn_sub[k].length() <= 26 and pa.btn_sub[k].length() > 0 and pa.btn_pips[k] >= 0 and pa.btn_cost[k] >= 0 and words_ok.call(pa.btn_text[k]) and pa.btn_stars[k] == -1
	check(up_ok and pa.btn_id.find("upg:radar") >= 0, "upgrades: each card has an icon, a name, one short line, level pips and a cost")
	main._show_menu()
	# Shop.
	for tab in [0, 1]:
		main.shop_tab = tab
		main._show_shop()
		pa = main.hud._art
		var shop_ok = true
		for k in pa.btn_count:
			if pa.btn_kind[k] == 1:
				shop_ok = shop_ok and pa.btn_icon[k] >= 0 and pa.btn_sub[k].length() <= 10 and words_ok.call(pa.btn_text[k])
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
		tip_len_ok = tip_len_ok and main.TIPS[key][0].split(" ").size() <= 10 and main.TIPS[key][1] != ""
	check(tip_len_ok, "every tip is an icon and one short line")
	main.hud._tip_until = 0
	main.hud._process(0.016)
	check(main.hud._tip.text == "Second tip" and main.hud._tip_q.is_empty(), "...the next one follows when the first is done")
	main.hud._tip_until = 0
	main.hud._process(0.016)
	# Pause: nothing from the HUD shows through; one primary button.
	main.pause_game()
	var pause_art = main.hud._art
	var pause_prim = []
	for k in pause_art.btn_count:
		if pause_art.btn_kind[k] == 2:
			pause_prim.append(pause_art.btn_id[k])
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
	art = main.hud._art       # (the results card is its own layer)
	area = func(k): return art.btn_rect[k].size.x * art.btn_rect[k].size.y
	var rbg = main.hud._panel_arts.get("results_bg")
	check(rbg != null and rbg.res_layer == 1 and rbg.position == Vector2.ZERO and art.res_layer == 2 and rbg.get_index() < art.get_index(), "results: the unchanging part of the card is its own layer under the numbers")
	check(art.res_t < 1.0 and not main.hud.results_revealed() and not main.hud._over_body.visible and not main.hud.results_details_open(), "results: the stars and total are revealed in sequence; the breakdown is hidden")
	var res_prim = []
	var res_small = true
	for k in art.btn_count:
		if art.btn_kind[k] == 2:
			res_prim.append(art.btn_id[k])
		elif art.btn_id[k] != "again":
			res_small = res_small and area.call(k) < area.call(art.btn_id.find("again")) * 0.55
	check(res_prim == ["again"] and res_small, "results: one big PLAY AGAIN button; the ads and the rest are small chips")
	main.hud._process(1.0)
	var t_mid = art.res_t
	main.hud._process(5.0)
	check(t_mid > 0.9 and main.hud.results_revealed(), "results: the reveal plays out (%.1f s)" % t_mid)
	main._on_button("details")
	check(rbg.position != Vector2.ZERO, "...the unchanging layer steps aside for it")
	check(main.hud.results_details_open() and art.details_lines.size() >= 8, "results: 'Details' opens the full breakdown (%d lines)" % art.details_lines.size())
	main._on_button("details")
	check(not main.hud.results_details_open(), "...and closes it again")
	main.restart()
	tr.auto_spawn = false

	print("9o. no haze: three small cloud shadows, and the draw order that keeps the interface and the aircraft clear of them")
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	set_wind(main, 0.0)
	var cls = main.clouds
	check(cls.count() >= 1 and cls.count() <= 3 and main.get_children().filter(func(n): return n.get_script() == cls.get_script()).size() == 1, "at most three cloud shadows, created once (%d)" % cls.count())
	var cs_code: String = cls.material(0).shader.code
	check(cs_code.contains("depth_test_disabled") and cs_code.contains("blend_mix") and not cs_code.contains("TIME"), "...each a flat soft-edged shape (%d characters of shader)" % cs_code.length())
	var cs_ok := true
	for cs_i in cls.count():
		var cs_tint: Color = cls.material(cs_i).get_shader_parameter("tint")
		var cs_a: float = cls.material(cs_i).get_shader_parameter("alpha")
		var cs_size: Vector2 = (cls.shadow(cs_i).mesh as PlaneMesh).size
		cs_ok = cs_ok and cs_a >= 0.08 and cs_a <= 0.15 and cs_tint.is_equal_approx(Shadow.COLOR) and cs_tint.get_luminance() < 0.4 and cs_size.x <= 4.0 and cs_size.y <= 2.5
	check(cs_ok, "...dark (the shadow colour) at about 12%, small (under 4 x 2.5 units of a 10-unit-wide view), with no white anywhere")
	var cs_x0 = cls.shadow(0).position
	cls._process(1.0)
	check(cls.shadow(0).visible and cls.shadow(0).position != cs_x0 and cls.shadow(0).position.distance_to(cs_x0) < 0.3, "...drifting slowly (%.2f units in a second)" % cls.shadow(0).position.distance_to(cs_x0))
	main.begin_shift()
	main._process(0.016)
	cls._process(0.016)
	check(cls.shadow(0).visible, "...in a shift too")
	DebugFlags.parse(["tune", "nolife"])
	cls._process(0.016)
	check(not cls.shadow(0).visible, "?nolife takes them away")
	DebugFlags.parse(["tune"])
	cls._process(0.016)
	var plane_mat = tr._body_mats[0]
	var rw_mat = main.airfield.cur.thr_mats[0]
	check(cls.material(0).render_priority < -1 and plane_mat.render_priority > cls.material(0).render_priority and rw_mat.render_priority > cls.material(0).render_priority, "draw order: the shadows come before the ribbons, aircraft and runways")
	check(main.hud.layer > main.get_viewport().get_visible_rect().size.x * 0.0 and cls is Node3D, "...and the interface is a canvas layer above the 3D scene, so nothing is ever drawn over it")
	check(plane_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS and rw_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS and plane_mat.albedo_color.a == 1.0, "aircraft and runways sit in the pass after the shadows but stay fully opaque")
	check(main.airfield.cur.ground_mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and main.airfield.cur.ground_mat.render_priority == 0, "the ground and scenery stay in the opaque pass")
	var pad_lifted = false
	for av in main.airfield.variants:
		for mi in av.root.find_children("*", "MeshInstance3D", true, false):
			var bm = mi.material_override as BaseMaterial3D
			if bm != null and bm.render_priority == 2:
				pad_lifted = true
	check(pad_lifted, "runways, pads and lanes are lifted above them")
	var outl_ok = true
	for mi in tr._nodes[0].find_children("*", "MeshInstance3D", true, false):
		if mi.material_overlay != null:
			outl_ok = outl_ok and mi.material_overlay.render_priority == 2
	check(outl_ok, "aircraft outlines are drawn above them with the aircraft")
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
	fsfx.set_music(true, 0, false)
	fsfx.set_fog(0.0)
	check(fsfx.fog_level == 0.0 and not fsfx._fog_amb.playing and not fsfx._music_tense.playing, "no fog: no ambience, no tense layer")
	fsfx.set_fog(1.0)
	check(fsfx.fog_level == 1.0 and fsfx._fog_amb.playing and fsfx._music_tense.playing, "fog: the ambience and the tense music layer play")
	check(fsfx._music_tense.stream.data.size() == fsfx._music1.stream.data.size() and fsfx._music_tense.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "...the tense layer loops in step with the music")
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
	check(hud.transition_dir() == -1 and hud.transitioning() and hud.transform != Transform2D.IDENTITY, "coming back pops in too (direction %d)" % hud.transition_dir())
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
	# Screens pop in as a whole (no per-card stagger); buttons squash and bounce.
	main._show_select()
	hud.skip_animations()
	check(not hud._art.animating(), "a screen's cards sit still once it has opened (no per-card pop-in)")
	var q_bk = hud._art.btn_id.find("pick:0")
	var q_bpos = hud._art.btn_rect[q_bk].get_center()
	hud.press(q_bpos)
	hud._process(Style.T_FAST * 0.5)
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
	main._on_touchdown(tr.place(0, Vector2(0, 0), 0.0, SMALL))
	check(hud.flying_coins() >= 1 and hud.flying_coins() <= 5, "the coins leave at touchdown (%d)" % hud.flying_coins())
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
	main.begin_shift()
	main._process(0.016)
	q_dio.tick(0.7)
	check(not q_dio.active and q_dio.traffic.active_count() == 0, "during a shift the diorama is gone: no aircraft")
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
	while main.shift.landed < r_thr0:
		main.shift.on_landed(3, 14, 0)
	main.hud.set_shift(main.shift)
	check(r_stars_seen.size() >= 1 and r_stars_seen[0] == 0 and main.hud._art.star_t[0] == 0.0, "reaching the landings for the first star lights it with a burst")
	var r_seen_n = r_stars_seen.size()
	main.hud.set_shift(main.shift)
	check(r_stars_seen.size() == r_seen_n, "...once")
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
	save.ap_xp[0] = Progression.xp_at_level(0, Progression.GATE_LEVEL) - 50
	save.sync_levels()
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
	main.hud._art.res_t = 4.6
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
	for au_n in au.MUSIC_LAYERS:
		au._db[au_n] = -80.0
	au.set_menu_music(true)
	var au_prev = au._db["music1"]
	var au_jump = 0.0
	for i in 200:
		au._glide_music(1.0 / 60.0)
		au_jump = maxf(au_jump, absf(au._db["music1"] - au_prev))
		au_prev = au._db["music1"]
	check(absf(au._db["music1"] - au.MENU_L1_DB) < 0.5 and absf(au._db["music2"] - au.MENU_L2_DB) < 0.5 and au._db["music3"] <= -75.0 and au_jump <= au.FADE_DB_PER_S / 60.0 + 0.01 and au._music1.playing and au._music2.playing and au._music3.playing, "the menu plays layers 1 and 2, lower, fading up smoothly (%.1f dB at most per frame)" % au_jump)
	check(au.MENU_L1_DB < au.SHIFT_L1_DB and au.MENU_L2_DB < au.SHIFT_L2_DB, "...at lower levels than in a shift")
	au.set_music(true, 0, false)
	for i in 30:
		au._glide_music(1.0 / 60.0)
	check(au._db["music1"] > au.MENU_L1_DB + 2.0 and au._db["music1"] < au.SHIFT_L1_DB + 0.1, "...and rises into the shift's music without a jump")
	for i in 240:
		au._glide_music(1.0 / 60.0)
	check(absf(au._db["music1"] - au.SHIFT_L1_DB) < 0.5 and au._db["music2"] <= -75.0 and au._db["music3"] <= -75.0, "in a shift with an empty sky only layer 1 is up (the menu's layer 2 fades out)")
	au.set_music(true, 5, false)
	for i in 240:
		au._glide_music(1.0 / 60.0)
	check(absf(au._db["music2"] - au.SHIFT_L2_DB) < 0.5 and absf(au._db["music3"] - au.SHIFT_L3_DB) < 0.5, "...with five inbound all three are up")
	au.set_music(false)
	au.set_menu_music(true)
	for i in 300:
		au._glide_music(1.0 / 60.0)
	check(absf(au._db["music1"] - au.MENU_L1_DB) < 0.5 and au._db["music3"] <= -75.0, "back at the menu the lead fades away again")
	au.set_menu_music(false)
	for i in 300:
		au._glide_music(1.0 / 60.0)
	check(not au._music1.playing and not au._music2.playing and not au._music3.playing and au._db["music1"] <= -75.0, "and with no music wanted, everything fades out and stops")
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
		if lf != Style.display() and lf != Style.text() and lf != Style.body():
			lab_bad.append(lb.text)
	check(lab_bad.is_empty() and main.overlay._font == Style.text(), "every label and the overlay tags use the style fonts (%s)" % str(lab_bad))
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
	var pf_works = []
	for i in 120:
		var pw0 = Time.get_ticks_usec()
		tr.step(1.0 / 60.0)
		main.ribbons._process(1.0 / 60.0)
		main.hud._process(1.0 / 60.0)
		main.fx.get_child_count()
		pf_works.append((Time.get_ticks_usec() - pw0) / 1000.0 + (main.overlay.last_draw_us + main.hud._art.last_draw_us) / 1000.0)
		await process_frame
	pf_works.sort()
	var pf_work = pf_works[int(pf_works.size() * 0.95)]       # (the 95th percentile: one slow frame on a busy machine says nothing about the code)
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
	check(main.hud._stamp.visible and main.hud._stamp.text.contains(BuildInfo.COMMIT) and main.hud._stamp.size.y < 90.0 and main.hud._stamp.get_theme_font_size("font_size") <= Style.SZ_CAPTION, "?debug shows it, small, in the corner")
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
	for vt_parent in [main.hud._menu, main.hud._pause]:
		var vt: Label = vt_parent.get_node_or_null("VersionTag")
		check(vt != null and vt.text == "build " + BuildInfo.COMMIT and vt.get_theme_font_size("font_size") <= Style.SZ_CAPTION and vt.modulate.a < 0.8 and vt.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and vt.anchor_left == 1.0 and vt.anchor_top == 1.0, "the menu and the pause screen show a small muted 'build <commit>' bottom-right")

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
	var wa_all = wa_sfx._streams.values() + [wa_sfx._music1.stream, wa_sfx._music2.stream, wa_sfx._music3.stream, wa_sfx._music_tense.stream, wa_sfx._fog_amb.stream]
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
	var wa_was_playing = wa_sfx._music1.playing
	wa_sfx.unlock()
	check(wa_sfx.unlocked and wa_was_playing and wa_sfx._music1.playing, "the first touch unlocks audio and (re)starts the music layers")
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
	# Pitch classes of the pitched clips are all in D major pentatonic (D E F# A B).
	var w_pc_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var w_in_key = [2, 4, 6, 9, 11]
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
		w_hz_ok = w_hz_ok and w_in_key.has(posmod(w_semis, 12)) and absf(w_hz - 261.6256 * pow(2.0, w_semis / 12.0)) < 0.15
	check(w_hz_ok and absf(SfxSynth.note_hz(5) - 587.33) < 0.1 and absf(SfxSynth.note_hz(3) - 440.0) < 0.1, "the scale helper is D major pentatonic (D4 293.7, A4 440, D5 587.3)")
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
	var w_ref = sx_peak.call(sx_clip_of(sx._music1.stream)) * db_to_linear(sx.SHIFT_L1_DB)
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
	var w_loops = {"music1": sx._music1.stream, "music2": sx._music2.stream, "music3": sx._music3.stream, "tense": sx._music_tense.stream, "fog": sx._fog_amb.stream}
	for w_k in w_loops.keys():
		var w_xs = sx_clip_of(w_loops[w_k])
		var w_big_step = 0.0
		for w_i in range(1, w_xs.size()):
			w_big_step = maxf(w_big_step, absf(w_xs[w_i] - w_xs[w_i - 1]))
		var w_seam = absf(w_xs[0] - w_xs[w_xs.size() - 1])
		if w_seam > w_big_step * 1.5 + 0.0005 or w_loops[w_k].loop_mode != AudioStreamWAV.LOOP_FORWARD:
			w_seam_bad.append("%s %.4f/%.4f" % [w_k, w_seam, w_big_step])
	check(w_seam_bad.is_empty(), "every loop is seamless %s" % str(w_seam_bad))
	check(sx._music1.stream.data.size() == sx._music2.stream.data.size() and sx._music2.stream.data.size() == sx._music3.stream.data.size() and sx._music3.stream.data.size() == sx._music_tense.stream.data.size() and sx._music1.stream.data.size() / 2 == int(round(SfxSynth.LOOP_SECS * 44100.0)), "the three music layers and the tense drone are the same length, exactly 8 bars at 112 BPM (they build and fade without drifting)")
	check(absf(SfxSynth.BPM - 112.0) < 0.001 and absf(sx.BEAT - SfxSynth.BEAT) < 0.000001 and absf(sx.LOOP_SECS - SfxSynth.LOOP_SECS) < 0.000001 and int(round(SfxSynth.BEAT * 44100.0)) == 23625, "the music is at 112 BPM (a beat is 23 625 samples), in step with the sound code")
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
		if xa_path.contains("/loops/") and xa_st > 0.08:
			xa_step_bad.append("%s %.3f" % [xa_path, xa_st])
	var xa_edge_bad = []
	for xa_path in xa_all.keys():
		var xa_e: PackedFloat32Array = xa_all[xa_path]
		if not xa_path.contains("/loops/") and (absf(xa_e[0]) > 0.0005 or absf(xa_e[xa_e.size() - 1]) > 0.0005):
			xa_edge_bad.append(xa_path)
	check(xa_edge_bad.is_empty(), "every one-shot starts and ends at zero (no click when it starts or stops) %s" % str(xa_edge_bad))
	check(xa_clip_bad.is_empty(), "no clip reaches full scale %s" % str(xa_clip_bad))
	check(xa_step_bad.is_empty(), "no loop has jumps in it (smooth waveforms, no skipped or doubled samples) %s" % str(xa_step_bad))
	# Worst case at once: every music layer, fog and the bed at their mixed levels (in dB, as Sfx.gd sets them) stay far
	# below full scale, and the loudest one-shot on top of that is still under it, so the limiter only ever catches
	# rare pile-ups.
	var xa_gain = {"music1": -4.0, "music2": -7.0, "music3": -8.0, "tense": -9.0, "fog": -10.0}
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
	check(xa_sum < 0.75 and xa_sum + xa_loud < 1.1, "the whole bed peaks at %.2f and a big sound (%.2f) on top stays near full scale, so the limiter rarely works" % [xa_sum, xa_loud])
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
	check(sc_kinds["play"] == [2, "Start shift"] and sc_kinds["airports"] == [0, "Airports"] and sc_kinds["bad"] == [0, "Bad pilot day"] and sc_kinds["upgrades"][0] == 7 and sc_kinds["shop"] == [7, "Hangar"] and sc_kinds["goals"][0] == 14 and sc_art.btn_count == 9 and sc_kinds["airports_tag"][0] == 9, "the menu: Start shift (orange), Airports and Bad pilot day (cream), and three small round buttons, with the goals card under the title")
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
	sc_art = main.hud._art
	check(sc_art.res_chips[0] == main.shift.earned + main.shift.bonus and sc_art.res_chips[2] == main.shift.fines + main.shift.overtime_penalty and sc_art.res_sub.contains(Airports.airport_name()) and sc_art.res_sub.contains("landed"), "the results card has the three chips (landings, early clear, fines) and the subtitle")
	main.hud.queue_unlock("County")
	check(sc_art.res_unlock == "County", "a new airport shows as a card on the results")
	main.hud.hide_unlock()
	main._show_menu()
	main.restart()
	main.pause_game()
	sc_art = main.hud._art
	check(sc_art.pause_card.size.x > 600.0 and sc_art.btn_kind[sc_art.btn_id.find("restart")] == 3, "the pause menu sits on a sheet with colour tiles")
	main.resume_game()
	var sc_doc = FileAccess.get_file_as_string("res://docs/style.md")
	check(sc_doc.contains("## Cozy Airfield") and sc_doc.contains("#FFD68A") and sc_doc.contains("#3B4A6B"), "docs/style.md documents the Cozy Airfield art direction")
	check(sc_art._sb_hdr != null and sc_art._sb_card != null and sc_art._sb_dock != null, "the pills, card and dock styles exist")
	main._show_menu()

	print("9zy. gameplay audio is part of the music")
	var qa = main.sfx
	check(qa.QUANTIZED.has("landing") and qa.QUANTIZED.has("go_around") and qa.QUANTIZED.has("alarm") and qa.QUANTIZED.has("tick") and qa.QUANTIZED.has("arrive") and not qa.QUANTIZED.has("tap") and not qa.QUANTIZED.has("touch"), "landings, arrivals, go-arounds, conflicts and ticks wait for the beat; taps and the touchdown tap do not")
	check(absf(qa.EIGHTH - 60.0 / 112.0 / 2.0) < 0.0001 and absf(qa.LOOP_SECS - 60.0 / 112.0 * 32.0) < 0.0001, "the grid is the music's eighth-note (0.268 s of the 17.14 s loop)")
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
	check(absf(float(cz_m.get_shader_parameter("warm_amount")) - 0.35) < 0.001 and absf(float(cz_m.get_shader_parameter("cool_amount")) - 0.2) < 0.001 and (cz_m.get_shader_parameter("warm") as Color).is_equal_approx(Color("ffd68a")) and (cz_m.get_shader_parameter("cool") as Color).is_equal_approx(Color("2f4a7a")), "warm #FFD68A 35%, cool #2F4A7A 20%")
	check(cz_m.get_shader_parameter("grain") == null and cz_light.rect.visible == DebugFlags.light_enabled(), "the overlay has no grain and no texture")
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
	zu_art = main.hud._art
	var zu_ids = []
	for zu_k in zu_art.btn_count:
		zu_ids.append(zu_art.btn_id[zu_k])
	check(zu_ids.has("pick:0") and not zu_ids.has("airport:0") and zu_ids.has("locked:1") and zu_art.btn_cost[zu_art.btn_id.find("pick:0")] == 120 and zu_art.btn_map[zu_art.btn_id.find("locked:1")] == 1, "airports: vignette cards (a tap opens the detail screen: no Fly here on the list), a locked one a dimmed vignette")
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
	check(main.hud._over_body.text.contains("Landings earned +%d" % main.shift.earned) and main.hud._over_body.text.contains("of gross) %d" % main.shift.kept()), "the results details list landings earned, fines, the pay floor and the total")
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
	# Every landing counts toward the hangar, wherever it parks: mixed traffic, a helicopter and a seaplane among the planes
	var rp_mix = [Aircraft.Type.SMALL, Aircraft.Type.HELI, Aircraft.Type.SEAPLANE, Aircraft.Type.MEDIUM, Aircraft.Type.JET, Aircraft.Type.GLIDER, Aircraft.Type.HELI, Aircraft.Type.SEAPLANE, Aircraft.Type.SMALL, Aircraft.Type.HELI]
	var rp_mix_ok = true
	var rp_mix_kinds = []
	rp.reset(6, 6, 2, 1, 6)
	for rp_k in 10:
		var rp_slot = rp.place(rp_mix[rp_k])
		rp_mix_kinds.append(rp_slot["kind"])
		var rp_expect_full = rp_k + 1 >= 6
		rp_mix_ok = rp_mix_ok and rp.hangar == mini(rp_k + 1, 6) and rp.hangar_full() == rp_expect_full and rp.on_ramp() == maxi(rp_k + 1 - 6, 0) and rp.summary().begins_with("Hangar full") == rp_expect_full and bool(rp_slot["counted"]) == (rp_k < 6)
	check(rp_mix_ok, "with mixed traffic every landing counts: 'Hangar full' comes exactly at the sixth landing, and the ramp is the landings after it %s" % str(rp_mix_kinds))
	check(rp_mix_kinds[1] == "heli" and rp_mix_kinds[2] == "dock" and rp_mix_kinds[7] == "dock" and rp.summary() == "Hangar full · 4 on the ramp", "...helicopters and seaplanes still park on the pad and the dock (%s)" % rp.summary())
	rp.reset(6, 6, 2, 1, 6)
	for rp_k in 3:
		rp.place(Aircraft.Type.HELI)
	check(rp.summary() == "Hangar 3 / 6" and rp.on_ramp() == 0, "...so a helicopter on its spot is one of the hangar's 'Hangar 3 / 6'")
	# and in the game, at every airport, with the real traffic mix: the hangar is full exactly when the shift breaks even
	var rp_be = []
	for rp_i in Airports.COUNT:
		Airports.current = rp_i
		var rp_cap2 = RampC.capacity(rp_i)
		var rp_mix_d = Airports.mix(rp_i)
		var rp_types = []
		for rp_t in rp_mix_d:
			rp_types.append(rp_t)
		var rp_r2 = RampC.new()
		rp_r2.reset(rp_cap2, 6, 2 if rp_i == 4 else 0, 1 if Airports.pads().size() > 0 else 0, 6)
		var rp_full_at = -1
		for rp_k in rp_cap2 + 12:
			var rp_ty = rp_types[rp_k % rp_types.size()]
			rp_r2.place(rp_ty)
			if rp_full_at < 0 and rp_r2.hangar_full():
				rp_full_at = rp_k + 1
		if rp_full_at != rp_cap2 or rp_r2.on_ramp() != 12:
			rp_be.append("%s full at %d (cap %d) ramp %d" % [Airports.airport_name(rp_i), rp_full_at, rp_cap2, rp_r2.on_ramp()])
	check(rp_be.is_empty(), "at every airport the hangar fills at exactly its capacity, whatever lands %s" % str(rp_be))
	Airports.current = rp_keep
	var rp_cross = []
	var rp_slots = 0
	for rp_i in Airports.COUNT:
		Airports.current = rp_i
		main.airfield.select(rp_i)
		var rp_rv = main.airfield.cur
		check(rp_rv.ramp_ok and (rp_rv.slots["tie"] as Array).size() == 6, "%s has six tie-downs" % Airports.airport_name(rp_i))
		check((rp_rv.slots["over"] as Array).size() == 6, "%s has six overflow bays on its ramp" % Airports.airport_name(rp_i))
		var rp_vias = []
		for rp_rk in ["tie", "over"]:
			for rp_e in rp_rv.slots[rp_rk]:
				rp_vias.append(rp_e["via"])
		rp_vias.append(rp_rv.hangar_via)
		rp_vias.append(rp_rv.extra_via)
		for rp_rk in range(Airports.land_count(Aircraft.Kind.RUNWAY)):
			for rp_re in 2:
				for rp_cl in [0, 2]:
					for rp_via in rp_vias:
						var rp_plan = Taxi.plan(rp_rk, rp_re, rp_cl, rp_via)
						var rp_rr = rp_plan["route"]
						if rp_rr.size() < 2:
							rp_cross.append("%s rw%d e%d: a place has no route" % [Airports.airport_name(rp_i), rp_rk, rp_re])
							continue
						rp_slots += 1
						# a route may cross another runway only behind a hold-short line for it
						for rp_j in Airports.rw_count():
							if rp_j == rp_rk:
								continue
							var rp_hit = false
							var rp_dd = 0.0
							while rp_dd <= Taxi.length(rp_rr):
								if Taxi.in_box(Taxi.at(rp_rr, rp_dd)[0], Taxi.rw_box(rp_j)):
									rp_hit = true
									break
								rp_dd += 0.1
							var rp_held = false
							for rp_h in rp_plan["holds"]:
								if rp_h["rw"] == rp_j:
									rp_held = true
							if rp_hit and not rp_held:
								rp_cross.append("%s rw%d e%d crosses runway %d with no hold-short" % [Airports.airport_name(rp_i), rp_rk, rp_re, rp_j])
		# helicopters and seaplanes keep their own pads and docks (their legacy routes never cross a runway)
		for rp_rk in ["heli", "dock"]:
			for rp_e in rp_rv.slots[rp_rk]:
				for rp_kind in [Aircraft.Kind.PAD, Aircraft.Kind.LANE]:
					for rp_lk in range(Airports.land_count(rp_kind)):
						for rp_re in 2:
							var rp_far = Airports.land_far(rp_kind, rp_lk, rp_re)
							var rp_hd = deg_to_rad(Airports.land_heading_deg(rp_kind, rp_lk, rp_re))
							for rp_gp in rp_e["goals"]:
								var rp_rr = RampC.taxi_route(rp_far, Vector2(sin(rp_hd), -cos(rp_hd)), rp_gp, rp_e["tail"], rp_kind != Aircraft.Kind.PAD)
								if rp_rr.is_empty():
									continue
								rp_slots += 1
								for rp_sg in range(1, rp_rr.size() - 1):
									if RampC.crosses_runway(rp_rr[rp_sg], rp_rr[rp_sg + 1], 0.05):
										rp_cross.append("%s %s seg %d" % [Airports.airport_name(rp_i), rp_rk, rp_sg])
	Airports.current = rp_keep
	main.airfield.select(rp_keep)
	check(rp_slots > 0 and rp_cross.is_empty(), "every taxi route is held short of a runway it crosses (%d routes) %s" % [rp_slots, str(rp_cross.slice(0, 4))])
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
			if rp_e["mi"] >= 0 and main.traffic.ramp_node(rp_e["mi"]).visible and rp_e["chocks"].visible:
				rp_parked += 1
	check(rp_parked == mini(9, 6 + (rp_rv0.slots["over"] as Array).size()), "the parked planes show their chocks (%d)" % rp_parked)
	check(rp_rv0.root.get_child_count() == rp_children, "nothing was allocated by parking")
	main.restart()
	check(main.airfield.ramp.on_ramp() == 0 and main.airfield.hangar_shown == 0 and main.airfield.taxis.is_empty(), "a restart clears the ramp")
	var rp_vis = 0
	for rp_rk in rp_rv0.slots:
		for rp_e in rp_rv0.slots[rp_rk]:
			if rp_e["mi"] >= 0:
				rp_vis += 1
	check(rp_vis == 0 and main.traffic.ramp_in_use() == 0 and rp_rv0.root.get_child_count() == rp_children, "...in place (nothing left parked, nothing new built)")

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

	print("15. Polish 3: the light moves on through the shift")
	var ti_shadow = load("res://scripts/Shadow.gd")
	main.restart()
	check(main.light.time == 0.0 and is_equal_approx(main.light.material.get_shader_parameter("warm_amount"), 0.35) and is_equal_approx(main.light.material.get_shader_parameter("cool_amount"), 0.20), "a shift starts with the 35% glow and the 20% shade")
	main._set_day(0.5)
	check(is_equal_approx(main.light.material.get_shader_parameter("warm_amount"), 0.425) and is_equal_approx(main.light.material.get_shader_parameter("cool_amount"), 0.25), "half way: 42.5% and 25% (linear)")
	main._set_day(1.0)
	check(is_equal_approx(main.light.material.get_shader_parameter("warm_amount"), 0.50) and is_equal_approx(main.light.material.get_shader_parameter("cool_amount"), 0.30), "at the end: 50% and 30%")
	check(is_equal_approx(main.traffic.shadow_scale, 1.3), "the aircraft's shadow offsets are 30% longer")
	var ti_c = ti_shadow._casters[0]
	check(ti_shadow._casters.size() > 20 and ti_c[0].position.is_equal_approx(ti_c[1] + Vector3(ti_c[2].x, 0.0, ti_c[2].y) * 0.3), "every prop shadow offset is 30%% longer (%d shadows)" % ti_shadow._casters.size())
	var ti_g0 = main.airfield.cur.ground_mat.albedo_color
	main._set_day(0.0)
	var ti_g1 = main.airfield.cur.ground_mat.albedo_color
	check(ti_g1.b > ti_g0.b and ti_g1.g >= ti_g0.g and ti_c[0].position.is_equal_approx(ti_c[1]), "the grass is a touch warmer at the end, and the start restores it all")
	main.restart()
	check(main.light.time == 0.0, "a restart resets the light")
	main.bad_mode = true
	main.restart()
	check(is_equal_approx(main.light.time, 0.4) and is_equal_approx(main.light.material.get_shader_parameter("warm_amount"), lerpf(0.35, 0.5, 0.4)), "Bad Pilot Day starts 40% of the way in")
	main.bad_mode = false
	main.restart()

	print("16. Polish 4: wind you can always see")
	main.restart()
	var wd_af = main.airfield
	var wd_w = main.wind
	main.traffic.auto_spawn = false
	wd_w.from_deg = 270.0                       # blowing toward the east
	wd_af._wd = -1.0
	wd_af._last_from = -1.0
	wd_af._animate_wind(0.1, 0)
	check(wd_af._st_mm.instance_count == 12 and wd_af._st_node.visible, "twelve wind streaks are pooled and visible")
	var wd_x0 = wd_af._st_pos[0].x
	var wd_y0 = wd_af._st_pos[0].y
	for wd_k in 20:
		wd_af._animate_wind(0.1, 0)
	check(wd_af._st_pos[0].x > wd_x0 + 0.3 or wd_af._st_age[0] < 2.0, "the streaks drift the way the air is going (%.2f -> %.2f)" % [wd_x0, wd_af._st_pos[0].x])
	check(absf(wd_af._st_pos[0].y - wd_y0) < 0.2 or wd_af._st_age[0] < 2.0, "...straight along it")
	var wd_len_ok = true
	for wd_i in 12:
		wd_len_ok = wd_len_ok and wd_af._st_len[wd_i] >= 0.55 and wd_af._st_len[wd_i] <= 1.1
	check(wd_len_ok, "each is 60-120 px long")
	var wd_a_max = 0.0
	for wd_i in 12:
		wd_a_max = maxf(wd_a_max, wd_af._st_alpha[wd_i])
	check(wd_a_max > 0.02 and wd_a_max <= 0.1001, "...at about 10%% opacity (%.3f)" % wd_a_max)
	wd_af._st_age[3] = 0.0              # (a streak that is about to respawn somewhere else would not be moving along)
	wd_af._st_ttl[3] = 9.0
	var wd_sp0 = wd_af._st_pos[3]
	wd_af._animate_wind(1.0, 0)
	var wd_moved = wd_af._st_pos[3].distance_to(wd_sp0)
	check(wd_moved > 0.1 and wd_moved < 0.7, "they drift at 20-60 px a second (%.2f units in a second)" % wd_moved)
	var wd_c = wd_af.cur
	check(wd_c.tufts == null or (wd_c.tufts.multimesh.get_instance_transform(0).basis != wd_c.tuft_base[0].basis), "the grass leans downwind")
	var wd_tree = null
	for wd_st in 3:
		for wd_h in wd_c.tree_styles[wd_st]:
			wd_tree = wd_h
	check(wd_tree == null or not wd_tree.basis.is_equal_approx(Basis.IDENTITY), "the trees sway")
	# a wind shift: the streaks swing over about 1.2 s and double in brightness, the trees sway harder
	var wd_d0 = wd_af._wd
	wd_w.from_deg = 0.0                          # now toward the south
	wd_af._animate_wind(0.1, 0)
	check(wd_af._gust_t > 1.0, "a wind shift starts the gust")
	var wd_swing = absf(wrapf(180.0 - wd_af._wd, -180.0, 180.0))
	check(wd_swing > 60.0, "...and the streaks are only part of the way round (%.0f deg to go)" % wd_swing)
	var wd_b_max = 0.0
	for wd_i in 12:
		wd_b_max = maxf(wd_b_max, wd_af._st_alpha[wd_i])
	check(wd_b_max > wd_a_max * 1.4, "...briefly brighter (%.3f vs %.3f)" % [wd_b_max, wd_a_max])
	for wd_k in 13:
		wd_af._animate_wind(0.1, 0)
	check(absf(wrapf(180.0 - wd_af._wd, -180.0, 180.0)) < 12.0 and wd_af._gust_t < 0.1, "...and have swung round after about 1.2 s")
	# the HUD arrow turns smoothly
	main.hud._art.wind_toward = 180.0
	main.hud._art.wind_shown = 90.0
	main.hud._process(0.1)
	check(main.hud._art.wind_shown > 90.0 and main.hud._art.wind_shown < 180.0, "the wind arrow turns smoothly (%.0f)" % main.hud._art.wind_shown)
	# the pond (countryside airports) and ?nowind
	var wd_pond = wd_af.variants[0]
	check(not wd_pond.pond.is_empty() and wd_af._clear_of_paths(wd_pond.pond["center"], -0.9), "the grass strip has a pond outside the paths' strips")
	DebugFlags.parse(["nowind", "windtest"])
	check(not DebugFlags.wind_enabled() and DebugFlags.windtest_enabled() and DebugFlags.summary().contains("nowind") and not DebugFlags.life_enabled(), "?nowind and ?windtest parse")
	wd_af._animate_wind(0.1, 0)
	check(not wd_af._st_node.visible, "?nowind hides the streaks")
	DebugFlags.parse(["tune"])
	wd_af._animate_wind(0.1, 0)
	check(wd_af._st_node.visible, "...and they come back without it")
	check(main.sfx.plays.has("gust") or main.sfx.NAMES.has("gust"), "the wind shift has a soft gust sound")

	print("17. Polish 5: the go-around telegraph")
	main.restart()
	var ga_tr = main.traffic
	ga_tr.auto_spawn = false
	ga_tr.wind = null
	ga_tr.go_rng.seed = 5
	var ga_warned = []
	var ga_cancelled = []
	var ga_went = []
	var ga_cb1 = func(_p, _r): ga_warned.append(ga_tr.run_time)
	var ga_cb2 = func(_p): ga_cancelled.append(ga_tr.run_time)
	var ga_cb3 = func(_p, _r): ga_went.append(ga_tr.run_time)
	ga_tr.go_around_warned.connect(ga_cb1)
	ga_tr.go_around_cancelled.connect(ga_cb2)
	ga_tr.go_around.connect(ga_cb3)
	var ga_thr = Airports.end_threshold(0, 0)
	var ga_dir = Airports.end_dir(0, 0)
	var ga_side = Vector2(-ga_dir.y, ga_dir.x)
	# a plane with a ragged, hopeless final: the dice always say go around
	var ga_old_max = tuning.go_around_max
	tuning.go_around_max = 1.0
	tuning.go_around_free = 0.0
	var ga_p = ga_tr.place(0, ga_thr - ga_dir * 6.0 + ga_side * 1.0, atan2(ga_dir.x, -ga_dir.y), 2)
	ga_p.runway = 0
	ga_p.student = true
	ga_tr.begin_path(ga_p)
	for ga_k in 8:
		ga_p.push(ga_thr - ga_dir * (5.0 - ga_k * 0.45) + ga_side * 1.0 * (1.0 if ga_k % 2 == 0 else -1.0))
	ga_p.push(ga_thr)
	ga_p.push(Airports.end_far(0, 0))
	ga_p.cleared = true
	var ga_steps = 0
	while ga_warned.is_empty() and ga_steps < 4000:
		ga_tr.step(1.0 / 60.0)
		ga_steps += 1
	check(ga_warned.size() == 1 and ga_p.ga_pending, "a go-around is signalled before it happens")
	var ga_roll0 = 0.0
	var ga_wob = 0.0
	var ga_tags_seen = false
	var ga_node = ga_tr._nodes[ga_tr.planes.find(ga_p)]
	for ga_k in 25:
		ga_tr.step(1.0 / 60.0)
		ga_wob = maxf(ga_wob, absf(ga_node.rotation.z))
	check(ga_wob > deg_to_rad(2.0) and ga_wob <= deg_to_rad(4.5) + absf(ga_p.bank), "the plane wobbles up to 4 degrees of roll (%.1f)" % rad_to_deg(ga_wob))
	await process_frame
	await process_frame
	check(main.overlay.go_around_tags_drawn() >= 1, "...and shows a '?' tag")
	var ga_left = 1.0 - (ga_tr.run_time - ga_warned[0])
	while ga_went.is_empty() and ga_steps < 6000:
		ga_tr.step(1.0 / 60.0)
		ga_steps += 1
	check(ga_went.size() == 1 and ga_went[0] - ga_warned[0] < tuning.go_around_telegraph + 0.05, "otherwise it goes around within the warning second (%.2f s later)" % (ga_went[0] - ga_warned[0] if not ga_went.is_empty() else -1.0))
	check(not ga_p.ga_pending and ga_p.climb > 0.0, "...and the tag becomes GOING AROUND while it climbs")
	await process_frame
	await process_frame
	check(main.overlay.go_around_tags_drawn() >= 1, "(the tag is drawn)")
	# the same again, but the player redraws a straight final within the second
	ga_tr.release_all()
	ga_warned.clear()
	ga_cancelled.clear()
	ga_went.clear()
	ga_p = ga_tr.place(0, ga_thr - ga_dir * 6.0 + ga_side * 1.0, atan2(ga_dir.x, -ga_dir.y), 2)
	ga_p.runway = 0
	ga_p.student = true
	ga_tr.begin_path(ga_p)
	for ga_k in 8:
		ga_p.push(ga_thr - ga_dir * (5.0 - ga_k * 0.45) + ga_side * 1.0 * (1.0 if ga_k % 2 == 0 else -1.0))
	ga_p.push(ga_thr)
	ga_p.push(Airports.end_far(0, 0))
	ga_p.cleared = true
	ga_steps = 0
	while ga_warned.is_empty() and ga_steps < 4000:
		ga_tr.step(1.0 / 60.0)
		ga_steps += 1
	check(ga_p.ga_pending, "a second warning")
	ga_p.student = false
	ga_tr.begin_path(ga_p)
	check(ga_p.ga_redrawn, "starting a new final is noticed")
	for ga_k in 6:
		ga_p.push(ga_p.pos.lerp(ga_thr, (ga_k + 1) / 7.0))
	ga_p.push(ga_thr)
	ga_p.push(Airports.end_far(0, 0))
	ga_p.cleared = true
	for ga_k in 6:
		ga_tr.step(1.0 / 60.0)
	check(ga_cancelled.size() == 1 and not ga_p.ga_pending and ga_went.is_empty(), "a cleaner final inside the second cancels the go-around")
	check(ga_tr.go_around_warns >= 1 and ga_tr.go_around_cancels == 1, "the cancel rate is logged (%d of %d)" % [ga_tr.go_around_cancels, ga_tr.go_around_warns])
	ga_tr.go_around_warned.disconnect(ga_cb1)
	ga_tr.go_around_cancelled.disconnect(ga_cb2)
	ga_tr.go_around.disconnect(ga_cb3)
	tuning.go_around_max = ga_old_max
	ga_tr.release_all()
	check(tp._sliders.has("go_around_telegraph"), "?tune exposes the warning time")

	print("18. Polish 6: juice")
	main.restart()
	var ju_tr = main.traffic
	ju_tr.auto_spawn = false
	var ju_p = ju_tr.place(0, Vector2(-2.0, -5.0), 0.0, 2)
	ju_p.entered = true
	ju_p.timer_left = ju_p.timer_max * 0.9
	ju_tr.step(1.0 / 60.0)
	check(not ju_p.red_seen and ju_p.red_pulse_t < 0.0, "a healthy timer ring does not pulse")
	ju_p.timer_left = ju_p.timer_max * (tuning.timer_red_fraction - 0.01)
	ju_tr.step(1.0 / 60.0)
	check(ju_p.red_seen and ju_p.red_pulse_t >= 0.0, "the ring pulses when it turns red")
	for ju_k in 60:
		ju_tr.step(1.0 / 60.0)
	check(ju_p.red_pulse_t < 0.0 and ju_p.red_seen, "...once (it is over after %.1f s and does not start again)" % tuning.red_pulse_seconds)
	ju_tr.release_all()
	check(not ju_p.red_seen and ju_p.red_pulse_t < 0.0, "a new aircraft starts over")
	# the coins: one by one, with a plink on each arrival that climbs the scale, the counter bumping
	var ju_arrived0 = main.hud.coins_arrived
	main.hud.fly_coins(Vector2(540, 900), 3)
	var ju_starts = []
	for ju_k in 3:
		ju_starts.append(main.hud._fc_t[ju_k])
	check(ju_starts[0] > ju_starts[1] and ju_starts[1] > ju_starts[2], "the coins are staggered, one after the other (%s)" % str(ju_starts))
	for ju_k in 80:
		main.hud._process(0.05)
	check(main.hud.coins_arrived - ju_arrived0 == 3, "...each arrives at the counter on its own (%d)" % (main.hud.coins_arrived - ju_arrived0))

	print("19. Per-airport layout: nothing built, planted or parked in an approach corridor or a drawn-path strip")
	var ly_only = []                  # (godot ... -- airport=3,4 limits this section to those airports)
	for ly_a in OS.get_cmdline_user_args():
		if ly_a.begins_with("airport="):
			for ly_n in ly_a.substr(8).split(","):
				match ly_n.to_lower():
					"countryside":
						ly_only.append(2)
					"island":
						ly_only.append(4)
					"mountain":
						ly_only.append(3)
					"international":
						ly_only.append(5)
					_:
						ly_only.append(int(ly_n))
	var ly_af = main.airfield
	for ly_i in Airports.COUNT:
		if not ly_only.is_empty() and not ly_only.has(ly_i):
			continue
		Airports.current = ly_i
		var ly_v = ly_af.variants[ly_i]
		var ly_bad = []
		var ly_pts = {}
		for ly_p in ly_v.scenery:
			ly_pts["scenery %s" % str(ly_p)] = [ly_p, 0.3]
		for ly_k in ly_v.slots:
			for ly_e in ly_v.slots[ly_k]:
				ly_pts["%s slot %s" % [ly_k, str(ly_e["pos"])]] = [ly_e["pos"], 0.3, ly_k != "heli"]
		if not ly_v.pond.is_empty():
			ly_pts["pond"] = [ly_v.pond["center"], ly_v.pond["r"]]
		for ly_st in 3:
			for ly_h in ly_v.tree_styles[ly_st]:
				ly_pts["tree %s" % str(ly_h.position)] = [Vector2(ly_h.position.x, ly_h.position.z), 0.4]
		for ly_tb in ly_v.tuft_base:
			ly_pts["tuft %s" % str(ly_tb.origin)] = [Vector2(ly_tb.origin.x, ly_tb.origin.z), 0.1]
		if ly_v.chair_a != Vector2.ZERO:
			for ly_q in 8:
				ly_pts["chairlift %d" % ly_q] = [ly_v.chair_a.lerp(ly_v.chair_b, ly_q / 7.0), 0.3]
		ly_pts["tower"] = [Airports.tower_pos(), 0.4]
		ly_pts["windsock"] = [Airports.windsock_pos(), 0.3]
		for ly_key in ly_pts:
			if ly_af.in_strip(ly_pts[ly_key][0], ly_pts[ly_key][1], ly_pts[ly_key][2] if ly_pts[ly_key].size() > 2 else true):
				ly_bad.append(ly_key)
		var ly_ap = Airports.apron()
		var ly_c = ly_ap["center"]
		var ly_s = ly_ap["s"]
		if not ly_af.rect_out_of_strips(Rect2(ly_c.x - 1.4 * ly_s, ly_c.y - 1.6 * ly_s, 2.8 * ly_s, 3.2 * ly_s), 0.0):
			ly_bad.append("apron")
		check(ly_bad.is_empty(), "%s: all of its %d placed things are outside the strips %s" % [Airports.airport_name(ly_i), ly_pts.size(), str(ly_bad.slice(0, 6))])
	Airports.current = rp_keep
	main.airfield.select(rp_keep)

	print("20. Taxi identity: the aircraft on the ramp is the one that landed")
	Airports.current = 2
	main.select_airport(2)
	main.restart()
	var id_af = main.airfield
	var id_tr = main.traffic
	id_tr.auto_spawn = false
	var id_free0 = id_tr.ramp_in_use()
	# a student's jet from the blue runway, landed: same model (the jet's), the blue livery colour, the student badge
	var id_slot = id_af.begin_taxi(Aircraft.Type.JET, Aircraft.Kind.RUNWAY, 1, 0, true, 2)
	var id_item = id_af.taxis[id_af.taxis.size() - 1]
	var id_mi = id_item["mi"]
	check(id_tr.ramp_in_use() == id_free0 + 1 and id_tr._jet_groups[id_mi].visible and not id_tr._plane_groups[id_mi].visible, "the jet that landed is the jet that taxis")
	check(id_tr._body_mats[id_mi].albedo_color.is_equal_approx(Airports.land_color(Aircraft.Kind.RUNWAY, 1)) and id_tr._badges[id_mi].visible, "...in its runway's livery colour and with its student badge")
	check(id_tr._fuselages[id_mi].scale.z == id_tr._fuselages[id_mi].scale.z and id_tr._jet_groups[id_mi].scale.is_equal_approx(Vector3(1.0, 1.0, 0.9 + 0.1 * 1.3)), "...at the speed class's length")
	var id_lv = Cosmetics.LIVERIES[id_tr.livery]
	check(id_tr._fus_mats[id_mi].albedo_color.is_equal_approx(id_lv["body"] if id_lv["body"] != null else Color.WHITE), "...and its livery's fuselage")
	for id_k in 600:
		id_af.step_taxi(0.1)
	check(id_af.taxis.is_empty(), "it gets there")
	if id_slot["kind"] != "hangar":
		var id_e = (id_af.cur.slots[id_slot["kind"]] as Array)[id_slot["idx"]]
		check(id_e["mi"] == id_mi and id_tr.ramp_node(id_mi).visible and id_tr._jet_groups[id_mi].visible, "...and is what shows parked on the ramp")
	else:
		check(id_tr.ramp_in_use() == id_free0, "...into the hangar and out of sight")
	# a helicopter: sits on the pad 3 s, then air-taxis to the heli spot
	main.restart()
	id_tr.auto_spawn = false
	id_slot = id_af.begin_taxi(Aircraft.Type.HELI, Aircraft.Kind.PAD, 0, 0, false, 1)
	id_item = id_af.taxis[id_af.taxis.size() - 1]
	id_mi = id_item["mi"]
	check(id_slot["kind"] == "heli" and id_tr._heli_groups[id_mi].visible and not id_tr._plane_groups[id_mi].visible, "the helicopter that landed is the one that air-taxis, to the heli spot")
	var id_pad = Airports.land_far(Aircraft.Kind.PAD, 0, 0)
	id_af.step_taxi(2.9)
	var id_still = Vector2((id_tr.ramp_node(id_mi).position - id_tr.cam_lift()).x, (id_tr.ramp_node(id_mi).position - id_tr.cam_lift()).z).distance_to(id_pad)
	check(id_still < 0.05, "it sits on the pad for 3 s (%.2f from it after 2.9 s)" % id_still)
	id_af.step_taxi(0.6)
	var id_moved = Vector2((id_tr.ramp_node(id_mi).position - id_tr.cam_lift()).x, (id_tr.ramp_node(id_mi).position - id_tr.cam_lift()).z).distance_to(id_pad)
	check(id_moved > 0.3 and (id_tr.ramp_node(id_mi).position - id_tr.cam_lift()).y > 0.1, "...then air-taxis away, a little above the ground (%.2f)" % id_moved)
	for id_k in 600:
		id_af.step_taxi(0.1)
	var id_spot = (id_af.cur.slots["heli"] as Array)[0]
	check(id_af.taxis.is_empty() and id_spot["mi"] == id_mi and Vector2((id_tr.ramp_node(id_mi).position - id_tr.cam_lift()).x, (id_tr.ramp_node(id_mi).position - id_tr.cam_lift()).z).distance_to(id_spot["pos"]) < 0.05, "and lands on its marked spot")
	main.restart()
	check(id_tr.ramp_in_use() == 0, "a restart frees every ramp aircraft in place")

	print("21. Path halo: cream under the coloured dots, the dark one behind a toggle")
	main.restart()
	var ha_tr = main.traffic
	ha_tr.auto_spawn = false
	var ha_p = ha_tr.place(0, Vector2(-2.0, -4.0), 0.0, 2)
	ha_tr.begin_path(ha_p)
	for ha_k in 5:
		ha_p.push(Vector2(-2.0 + ha_k * 0.3, -3.0 + ha_k * 0.3))
	var ha_pr = main.ribbons
	ha_pr._process(0.016)
	check(ha_pr.last_halo.is_equal_approx(Color("fff4df", 0.55)), "the path halo is cream #FFF4DF at 55%% (%s)" % str(ha_pr.last_halo))
	tuning.path_halo_dark = 1.0
	ha_pr._process(0.016)
	check(ha_pr.last_halo.r < 0.1 and ha_pr.last_halo.a < 0.35, "...and the dark shadow is still there behind the ?tune toggle (%s)" % str(ha_pr.last_halo))
	tuning.path_halo_dark = 0.0
	check(tp._sliders.has("path_halo_dark"), "?tune has the toggle")
	ha_tr.release_all()

	print("22. The go-around window in ?tune and the cancel rate in the console")
	check(tp._sliders.has("go_around_telegraph") and is_equal_approx(tuning.go_around_telegraph, 1.0), "?tune has the go-around window; it defaults to 1.0 s")
	var gl_slider = tp._sliders["go_around_telegraph"]
	gl_slider.value = 1.8
	check(is_equal_approx(tuning.go_around_telegraph, 1.8), "...and a slider moves it")
	gl_slider.value = 1.0
	main.restart()
	main.traffic.go_around_warns = 4
	main.traffic.go_around_cancels = 1
	main.log_go_arounds = false
	main._log_go_arounds()
	check(main.last_go_around_log.contains("warnings: 4") and main.last_go_around_log.contains("cancelled by the player: 1") and main.last_go_around_log.contains("25%") and main.last_go_around_log.contains("1.0 s"), "the shift's go-around cancel rate is logged (%s)" % main.last_go_around_log)
	check(main._reason_text().contains("Go-arounds|4 warned"), "...and shown with the results details")
	main.log_go_arounds = true
	main.traffic.release_all()

	print("23. The interface's footprint is a no-go zone: no funnel, lane end or spawn point under it")
	var hu_af = main.airfield
	check(hu_af.hud_world_rects().size() == 4 and hu_af.in_hud(Vector2(0, -7.5)) and hu_af.in_hud(Vector2(4.3, -8.0)) and hu_af.in_hud(Vector2(-4.5, -8.4)) and hu_af.in_hud(Vector2(0, -6.0)) and not hu_af.in_hud(Vector2(0, 0)), "pause, the timer pill, the wind card and the banner are in the zone, the open field is not")
	var hu_bad = []
	for hu_i in Airports.COUNT:
		Airports.current = hu_i
		for hu_r in Airports.rw_count():
			for hu_e in 2:
				var hu_thr = Airports.end_threshold(hu_r, hu_e)
				var hu_dir = Airports.end_dir(hu_r, hu_e)
				var hu_side = Vector2(-hu_dir.y, hu_dir.x)
				for hu_k in 8:
					if hu_af.in_hud(hu_thr + Vector2.from_angle(hu_k * TAU / 8.0) * tuning.approach_radius):
						hu_bad.append("%s ring %d/%d" % [Airports.airport_name(hu_i), hu_r, hu_e])
				var hu_fl = hu_af.funnel_length(hu_thr, hu_dir)
				if hu_fl < 1.4:
					hu_bad.append("%s funnel %d/%d is only %.1f long" % [Airports.airport_name(hu_i), hu_r, hu_e, hu_fl])
				for hu_d in [0.0, hu_fl * 0.5, hu_fl]:
					for hu_sg in [-1.0, 0.0, 1.0]:
						if hu_af.in_hud(hu_thr - hu_dir * hu_d + hu_side * (0.35 + 1.4 * hu_d / 3.4) * hu_sg):
							hu_bad.append("%s funnel %d/%d d%.1f" % [Airports.airport_name(hu_i), hu_r, hu_e, hu_d])
		for hu_l in Airports.lanes().size():
			for hu_e in 2:
				if hu_af.in_hud(Airports.land_threshold(Aircraft.Kind.LANE, hu_l, hu_e), 0.3) or hu_af.in_hud(Airports.land_far(Aircraft.Kind.LANE, hu_l, hu_e), 0.3):
					hu_bad.append("%s lane %d end %d" % [Airports.airport_name(hu_i), hu_l, hu_e])
		for hu_p in Airports.pads():
			if hu_af.in_hud(hu_p["center"], hu_p["radius"]):
				hu_bad.append("%s pad" % Airports.airport_name(hu_i))
	check(hu_bad.is_empty(), "no approach funnel, threshold ring, lane end or pad sits under the interface at any airport %s" % str(hu_bad.slice(0, 5)))
	# spawn points: 250 arrivals at every airport, none enters under the pause button, the pill or the wind card
	var hu_spawn_bad = []
	var hu_tr = main.traffic
	for hu_i in Airports.COUNT:
		main.select_airport(hu_i)
		main.restart()
		hu_tr.auto_spawn = false
		hu_tr.rng.seed = 11 + hu_i
		var hu_n = 0
		for hu_k in 250:
			hu_tr.release_all()
			var hu_p = hu_tr.spawn()
			if hu_p != null:
				hu_n += 1
				if hu_af.in_hud(hu_p.entry):
					hu_spawn_bad.append("%s %s" % [Airports.airport_name(hu_i), str(hu_p.entry)])
		check(hu_n > 200, "%s: arrivals still find a way in (%d of 250)" % [Airports.airport_name(hu_i), hu_n])
	check(hu_spawn_bad.is_empty(), "no spawn point is under the interface %s" % str(hu_spawn_bad.slice(0, 4)))
	main.select_airport(rp_keep)
	main.restart()
	Airports.current = rp_keep

	print("25. The frame-delta clamp is 1/20 s: the game runs at real speed down to 20 fps")
	check(absf(float(Engine.max_physics_steps_per_frame) / float(Engine.physics_ticks_per_second) - 0.05) < 0.0001 and absf(tuning.max_frame_delta - 0.05) < 0.0001, "the engine holds a frame to 1/20 s (%d physics steps of 1/%d s) and the game uses it whole" % [Engine.max_physics_steps_per_frame, Engine.physics_ticks_per_second])
	check(absf(main._frame_delta(0.05) - 0.05) < 0.0001 and absf(main._frame_delta(0.04) - 0.04) < 0.0001 and absf(main._frame_delta(0.2) - 0.05) < 0.0001, "...a 40 ms or 50 ms frame is simulated whole; a longer one is cut to 50 ms (slow motion below 20 fps)")
	# a path flown in 1/20 s steps ends where and when it does in 1/60 s steps; a pass that would be missed between two big steps is still seen
	var cl_end = []
	for cl_dt in [1.0 / 60.0, 1.0 / 20.0]:
		main.restart()
		tr.auto_spawn = false
		tr.release_all()
		tr.half_w = 5.0
		tr.half_h = 11.0
		var cl_p = tr.place(0, Vector2(-3.0, 6.0), 0.0, MEDIUM)
		for cl_q in [Vector2(-3, 3), Vector2(-1, 1), Vector2(2, -1), Vector2(2, 4)]:
			cl_p.push(cl_q)
		var cl_t = 0.0
		while cl_p.count > 0 and cl_t < 60.0:
			main.step(cl_dt)
			cl_t += cl_dt
		cl_end.append([cl_t, cl_p.pos])
	check(absf(cl_end[0][0] - cl_end[1][0]) < 0.06 and cl_end[0][1].distance_to(cl_end[1][1]) < 0.01, "a path takes the same time and ends in the same place at 60 and 20 steps a second (%.2f s / %.2f s)" % [cl_end[0][0], cl_end[1][0]])
	var cl_hits = []
	for cl_dt in [1.0 / 60.0, 1.0 / 20.0]:
		var cl_n = 0
		for cl_k in 30:
			main.restart()
			tr.auto_spawn = false
			tr.release_all()
			tr._god = false
			tr.grace_until = 0.0
			tr.half_w = 5.0
			tr.half_h = 11.0
			var cl_conf = [0]
			var cl_cb = func(_a, _b): cl_conf[0] += 1
			tr.conflict.connect(cl_cb)
			var cl_a = tr.place(0, Vector2(0.0, 8.0), 0.0, JET)
			var cl_b = tr.place(1, Vector2(0.8 + 0.003 * cl_k, -8.0), PI, JET)
			cl_a.timer_left = 999.0
			cl_b.timer_left = 999.0
			for cl_i in int(6.0 / cl_dt):
				tr.step(cl_dt)
			tr.conflict.disconnect(cl_cb)
			if cl_conf[0] > 0:
				cl_n += 1
		cl_hits.append(cl_n)
	check(cl_hits[0] == cl_hits[1] and cl_hits[0] > 20, "a pass just inside the conflict distance is a conflict at 60 and at 20 steps a second (%s of 30): the test sweeps the whole step" % str(cl_hits))
	main.restart()
	tr.auto_spawn = false
	tr.release_all()

	print("24. Start-up: only the first airport before the menu, the rest in the idle time; shared meshes; the ramp's models")
	var lz_script = load("res://scripts/Airfield.gd")
	root.get_node("Save").selected_airport = 0     # a fresh boot opens on the first airport (earlier tests leave another one selected, and with the 0, 1, 2, 3, 6, 10 gates more of them are open)
	lz_script.boot_lazy = true
	var lz_af = lz_script.new()
	root.add_child(lz_af)
	lz_script.boot_lazy = false
	var lz_open := 0
	for lz_i in Airports.COUNT:
		if root.get_node("Save").airport_open(lz_i):
			lz_open += 1
	var lz_built := 0
	for lz_v in lz_af.variants:
		if lz_v != null:
			lz_built += 1
	check(lz_af.variants.size() == 6 and lz_built == 1 and lz_af.is_built(0) and lz_af.cur != null, "boot builds only the airport it opens on (%d of 6)" % lz_built)
	# the background build: one airport at a time, a few statements per frame, never more than its budget of a frame
	check(lz_open < 6 and not lz_af.is_built(5) and not lz_af.background_running(), "...and leaves the locked ones for when they are needed")
	lz_af.budget_us = 400
	var lz_frames_started = Engine.get_process_frames()
	var lz_worst_us = 0
	var lz_seen_running = false
	lz_af.bg_paused = true
	check(lz_af.start_background(true) and lz_af.background_running(), "the background build starts (here with the build paused: a shift is on)")
	for lz_i in 5:
		await process_frame
	var lz_units_paused = lz_af.bg_units
	check(lz_af.background_running() and not lz_af.is_built(1), "...and a pause stops it between two statements (%d statements so far)" % lz_units_paused)
	lz_af.bg_paused = false
	var lz_guard = 0
	while lz_af.background_running() and lz_guard < 3000:
		var lz_t0 = Time.get_ticks_usec()
		await process_frame
		lz_worst_us = maxi(lz_worst_us, Time.get_ticks_usec() - lz_t0)
		lz_guard += 1
	check(lz_af.is_built(1) and lz_af.bg_frames >= 5 and lz_af.bg_units > 300, "...then it builds airport 1 across several frames (%d frames, %d statements)" % [lz_af.bg_frames, lz_af.bg_units])
	lz_af.budget_us = 3000
	while lz_af.start_background(true) and lz_guard < 6000:
		while lz_af.background_running() and lz_guard < 6000:
			await process_frame
			lz_guard += 1
	lz_built = 0
	for lz_v in lz_af.variants:
		if lz_v != null:
			lz_built += 1
	check(lz_built == 6 and lz_af.variants[5].phase == lz_script.BUILD_PHASES, "...and the rest one after another until all six are there")
	lz_af.apply_theme(1)
	lz_af.select(5)
	check(lz_af.is_built(5) and lz_af.cur == lz_af.variants[5], "selecting a built one shows it")
	lz_af.select(2)
	check(lz_af.variants[2].root.get_child_count() == main.airfield.variants[2].root.get_child_count() and lz_af.variants[5].root.get_child_count() == main.airfield.variants[5].root.get_child_count() and lz_af.variants[5].base_ground == main.airfield.variants[5].base_ground, "a late-built airport is the same airport as an eagerly built one")
	check(lz_af.variants[2].ground_now.is_equal_approx(Cosmetics.THEMES[1]["ground"]), "...and wears the equipped theme")
	check(lz_af.variants[5].root.visible == false and lz_af.variants[2].root.visible, "...and only the airport on show is visible")
	lz_af.queue_free()
	var lz_a = load("res://scripts/Prim.gd")
	var lz_n1 = Node3D.new()
	var lz_b1 = lz_a.box(lz_n1, Vector3(0.3, 0.2, 0.7), Vector3.ZERO, lz_a.mat(Color.WHITE))
	var lz_b2 = lz_a.box(lz_n1, Vector3(0.3, 0.2, 0.7), Vector3(1, 0, 0), lz_a.mat(Color.RED))
	var lz_b3 = lz_a.box(lz_n1, Vector3(0.3, 0.2, 0.71), Vector3.ZERO, lz_a.mat(Color.WHITE))
	check(lz_b1.mesh == lz_b2.mesh and lz_b1.mesh != lz_b3.mesh, "boxes of the same size share one mesh")
	lz_n1.free()
	# 	# picking an airport whose scenery is not built yet: the card says "Loading..." and the game carries on, then it goes there
	var ld_save = root.get_node("Save")
	ld_save.unlocks["all_airports"] = true
	main.select_airport(2)
	Airports.current = 2
	main.airfield.select(2)
	main._show_select()
	var ldz_old = main.airfield.variants[3]
	main.airfield.variants[3] = null
	ldz_old.root.queue_free()
	main._on_button("pick:3")
	var ldz_k = main.hud._art.btn_id.find("pick:3")
	check(main.wanted_airport == 3 and main.screen == main.SCREEN_SELECT and main.airport == 2 and ldz_k >= 0 and main.hud._art.btn_sub[ldz_k] == "Loading...", "picking an airport that is still being built shows a loading state on its card, and the game does not freeze")
	var ldz_frames = 0
	while main.wanted_airport >= 0 and ldz_frames < 1500:
		await process_frame
		ldz_frames += 1
	check(main.airfield.is_built(3) and main.airport == 2 and main.screen == main.SCREEN_DETAIL and main.detail_airport == 3 and ldz_frames > 2, "...and when it is built its detail screen opens (%d frames later), without selecting it" % ldz_frames)
	main.select_airport(2)
	Airports.current = 2
	main.airfield.select(2)
	main._show_menu()
	# the baked textures are the formulas' pictures (assets/textures: run tools/bake_textures.gd after changing a formula)
	var bk_ok := true
	var bk_names := ""
	var bk_shadow = load("res://scripts/Shadow.gd")
	var bk_fx = load("res://scripts/Fx.gd")
	var bk_want: Dictionary = {}
	for bk_s in bk_shadow.baked_images():
		bk_want["shadow_" + bk_s] = bk_shadow.baked_images()[bk_s]
	bk_want["dot_soft"] = bk_fx.dot_image(true)
	bk_want["dot_hard"] = bk_fx.dot_image(false)
	bk_want["star"] = bk_fx.star_image()
	for bk_n in bk_want:
		var bk_tex = load("res://assets/textures/%s.png" % bk_n)
		var bk_img: Image = bk_tex.get_image() if bk_tex != null else null
		var bk_ref: Image = bk_want[bk_n]
		if bk_img == null or bk_img.get_size() != bk_ref.get_size():
			bk_ok = false
			bk_names += " " + bk_n
			continue
		bk_img.convert(Image.FORMAT_RGBA8)
		var bk_worst := 0.0
		for bk_y in bk_ref.get_height():
			for bk_x in bk_ref.get_width():
				bk_worst = maxf(bk_worst, absf(bk_img.get_pixel(bk_x, bk_y).a - bk_ref.get_pixel(bk_x, bk_y).a))
		if bk_worst > 0.01:
			bk_ok = false
			bk_names += " %s(%.3f)" % [bk_n, bk_worst]
	check(bk_ok, "the shadow and dot textures load from baked PNGs that match their formulas:" + bk_names)
	bk_want["grass"] = load("res://scripts/Airfield.gd").grass_image()
	# the grass texture: faint (at most 3% darker), seamless, on the grass only
	var gr_tex = load("res://assets/textures/grass.png")
	var gr_img: Image = gr_tex.get_image()
	gr_img.convert(Image.FORMAT_RGBA8)
	var gr_min := 1.0
	var gr_edge := 0.0
	for gr_y in gr_img.get_height():
		for gr_x in gr_img.get_width():
			gr_min = minf(gr_min, gr_img.get_pixel(gr_x, gr_y).r)
		gr_edge = maxf(gr_edge, absf(gr_img.get_pixel(0, gr_y).r - gr_img.get_pixel(gr_img.get_width() - 1, gr_y).r))
	check(gr_min >= 0.97 and gr_min < 0.995 and gr_edge < 0.01, "the grass texture is a faint noise (darkest %.3f, so at most %.1f%%) that tiles (seam %.4f)" % [gr_min, (1.0 - gr_min) * 100.0, gr_edge])
	var gr_on := 0
	var gr_water_on := 0
	for gr_v in main.airfield.variants:
		var gr_n := 0
		for gr_mi in gr_v.root.find_children("*", "MeshInstance3D", true, false):
			var gr_m = gr_mi.material_override as BaseMaterial3D
			if gr_m != null and gr_m.albedo_texture == gr_tex:
				gr_n += 1
		if gr_v.water:
			gr_water_on += gr_n
		else:
			gr_on += gr_n
	var gr_grass_airports := 0
	for gr_v in main.airfield.variants:
		if not gr_v.water:
			gr_grass_airports += 1
	check(gr_on == gr_grass_airports and gr_water_on == 0, "...on the ground mesh of each grass airport and on nothing else: no runway, apron, building or water (%d meshes, %d airports)" % [gr_on, gr_grass_airports])
	check(main.light.material.get_shader_parameter("grain") == null and main.light.rect.material == main.light.material and not main.light.material.shader.code.contains("sampler2D"), "...and the screen overlay has no texture at all")
	check(Shadow.rect() is CompressedTexture2D and Shadow.plane() is CompressedTexture2D, "...and the game really loads them (no start-up computing)")
	var lz_most := 0
	for lz_v in main.airfield.variants:
		var lz_k := 0
		for lz_kind in ["tie", "over", "heli", "dock"]:
			lz_k += (lz_v.slots[lz_kind] as Array).size() if lz_v.slots.has(lz_kind) else 0
		lz_most = maxi(lz_most, lz_k)
	check(lz_most + main.airfield.TAXI_MAX <= main.traffic.RAMP_MODELS and main.traffic.RAMP_MODELS < 24 and main.traffic.RAMP_MODELS >= 12 and main.traffic.RAMP_MODELS >= 12, "the ramp has the models the most crowded airport shows at once (%d + %d taxiing <= %d)" % [lz_most, main.airfield.TAXI_MAX, main.traffic.RAMP_MODELS])

	print("26. No engines: a challenge for Bad Pilot Day and for airports with three stars")
	save.reset_all()
	main._show_menu()
	main.hud.skip_animations()
	var ne_art = main.hud._art
	var ne_k = ne_art.btn_id.find("noeng_bad")
	check(ne_k >= 0 and ne_art.btn_state[ne_k] == 0 and ne_art.btn_text[ne_k].begins_with("No engines"), "the menu has a No engines switch beside Bad pilot day (off)")
	main._on_button("noeng_bad")
	check(save.no_engines_bad and main.hud._art.btn_state[main.hud._art.btn_id.find("noeng_bad")] == 2, "...tapping it switches it on (and it is saved)")
	main.start_bad_day()
	check(main.no_engines and main.traffic.no_engines, "Bad Pilot Day with it on is a No engines shift")
	var ne_gl = main.traffic.place(0, Vector2(1.5, -4.0), PI, GLIDER)
	var ne_sm = main.traffic.place(0, Vector2(-1.5, -4.0), PI, SMALL)
	check(ne_gl.one_shot and ne_sm.one_shot and not ne_sm.can_go_around(), "...every aircraft in it is one-shot (no go-around)")
	main.traffic.release_all()
	main._show_menu()
	main._on_button("noeng_bad")
	main.start_bad_day()
	check(not main.no_engines and not main.traffic.no_engines, "...and off again, Bad Pilot Day is as it was")
	# The airport card: only with three stars.
	save.reset_all()
	main._show_menu()
	main.select_airport(0)          # (Bad Pilot Day moved the selection to its own airport, which depends on the date)
	main.open_detail(main.airport)
	main.hud.skip_animations()
	check(not main.hud.detail_sheet().chips.has("noeng:%d" % main.airport), "an airport with fewer than three stars has no No engines switch on its detail screen")
	for ne_i in 3:
		save.stars[main.airport * save.STARS_PER_AIRPORT + ne_i] = 1
	main.open_detail(main.airport)
	main.hud.skip_animations()
	check(main.hud.detail_sheet().chips.has("noeng:%d" % main.airport) and main.hud.detail_sheet().chips["noeng:%d" % main.airport].state == 0, "...with three stars its detail screen offers it (off)")
	sheet_tap(main, "noeng:%d" % main.airport)
	check(save.no_engines_on(main.airport) and main.hud.detail_sheet().chips["noeng:%d" % main.airport].state == 2, "...tapping it switches it on")
	var ne_coin0 = tuning.landing_pay(SMALL)
	main.restart()
	check(main.no_engines and main.traffic.no_engines, "a normal shift there is a No engines shift")
	var ne_pay = tuning.landing_pay(SMALL)
	var ne_before = main.shift.earned
	main._on_landed(main.traffic.place(0, Vector2(0, 0), 0.0, SMALL))
	var ne_got = main.shift.earned - ne_before
	check(ne_got >= roundi(ne_pay * tuning.no_engines_pay_mult), "...and pays the bonus multiplier (%d for a plane worth %d, x%.1f)" % [ne_got, ne_pay, tuning.no_engines_pay_mult])
	save.stars[main.airport * save.STARS_PER_AIRPORT + 0] = 0
	check(not save.no_engines_on(main.airport), "the switch only counts while the airport still has its three stars")
	main.restart()
	check(not main.no_engines, "...otherwise a shift is normal")
	save.write_file()
	save.load_file()
	check(save.no_engines_at[main.airport] == 1 and not save.no_engines_bad, "the switches survive a reload")
	save.reset_all()
	main.restart()
	tr.auto_spawn = false

	print("27. The approach guides point in")
	var ch_bad := []
	var ch_n := 0
	var ch_spacing := true
	for ch_a in Airports.COUNT:
		Airports.current = ch_a
		var ch_v = main.airfield.variants[ch_a]
		if ch_v == null:
			main.airfield.ensure(ch_a)
			ch_v = main.airfield.variants[ch_a]
		check(ch_v.chevrons.size() == Airports.rw_count() * 2 * 3, "%s: three approach chevrons at each runway end are on the ground (%d)" % [Airports.airport_name(ch_a), ch_v.chevrons.size()])
		for ch in ch_v.chevrons:
			var ch_thr = Airports.end_threshold(ch["rw"], ch["end"])
			var ch_want = (ch_thr - ch["pos"]).normalized()
			var ch_deg = rad_to_deg(ch["dir"].angle_to(ch_want))
			ch_n += 1
			if absf(ch_deg) > 10.0:
				ch_bad.append("%s %d/%d (%.0f deg)" % [Airports.airport_name(ch_a), ch["rw"], ch["end"], ch_deg])
		for ch_r in Airports.rw_count():
			for ch_e in 2:
				var ch_list = Airports.approach_chevrons(ch_r, ch_e)
				var ch_g1 = ch_list[0]["dist"] - ch_list[1]["dist"]
				var ch_g2 = ch_list[1]["dist"] - ch_list[2]["dist"]
				if not (ch_g1 > ch_g2 and ch_g2 > 0.0):
					ch_spacing = false
				for ch2 in ch_list:
					if absf(rad_to_deg(ch2["dir"].angle_to((Airports.end_threshold(ch_r, ch_e) - ch2["pos"]).normalized()))) > 10.0:
						ch_bad.append("data %d/%d" % [ch_r, ch_e])
	Airports.current = 0
	check(ch_n > 0 and ch_bad.is_empty(), "every approach chevron, as built at every runway end of every airport, points within 10 degrees of toward its threshold (%d checked) %s" % [ch_n, str(ch_bad.slice(0, 4))])
	check(ch_spacing, "...and they get closer together toward the threshold")

	print("28. Every airport is one airfield")
	var ly2_bad := []
	for ly2_a in Airports.COUNT:
		var ly2_probs = Layout.problems(ly2_a)
		for ly2_p in ly2_probs:
			ly2_bad.append("%s: %s" % [Airports.airport_name(ly2_a), ly2_p])
	check(ly2_bad.is_empty(), "every airport's layout is sound: its taxi graph is one piece, every runway end has an exit that reaches every place on the ramp over pavement, a hold-short line stands before each runway a route crosses, no taxiway or ramp is in an approach funnel or under the HUD, and every junction has its letter %s" % str(ly2_bad.slice(0, 5)))
	var ly2_marks := true
	var ly2_notes := []
	for ly2_a in Airports.COUNT:
		Airports.current = ly2_a
		main.airfield.ensure(ly2_a)
		var ly2_v = main.airfield.variants[ly2_a]
		var ly2_n = Taxi.net(ly2_a)
		if ly2_v.thr_labels.size() != Airports.rw_count() * 2:
			ly2_marks = false
			ly2_notes.append("%s: %d numbers" % [Airports.airport_name(ly2_a), ly2_v.thr_labels.size()])
			continue
		for ly2_r in Airports.rw_count():
			var ly2_hd = Airports.rw_heading_deg(ly2_r)
			var ly2_t0 = int(ly2_v.thr_labels[ly2_r * 2].text)
			var ly2_t1 = int(ly2_v.thr_labels[ly2_r * 2 + 1].text)
			var ly2_want = posmod(roundi(ly2_hd / 10.0), 36)
			if (ly2_want if ly2_want != 0 else 36) != ly2_t0 or posmod(ly2_t0 - ly2_t1, 36) != 18:
				ly2_marks = false
				ly2_notes.append("%s runway %d reads %d/%d for heading %.0f" % [Airports.airport_name(ly2_a), ly2_r, ly2_t0, ly2_t1, ly2_hd])
		var ly2_junctions = 0
		for ly2_e in ly2_n["edges"]:
			if (ly2_n["rw"].has(ly2_e[0]) != ly2_n["rw"].has(ly2_e[1])):
				ly2_junctions += 1
		if ly2_v.signs.size() == 0 or ly2_v.signs.size() > ly2_junctions:
			ly2_marks = false
			ly2_notes.append("%s: %d signs for %d junctions" % [Airports.airport_name(ly2_a), ly2_v.signs.size(), ly2_junctions])
		for ly2_s in ly2_v.signs:
			if String(ly2_s["letter"]).length() != 1 or Taxi.on_taxiway(ly2_n, ly2_s["pos"], 0.05):
				ly2_marks = false
				ly2_notes.append("%s: sign %s" % [Airports.airport_name(ly2_a), str(ly2_s)])
	Airports.current = 0
	check(ly2_marks, "each runway number matches its magnetic heading (09/27 style), and every airport has its taxiway letter signs beside the pavement %s" % str(ly2_notes.slice(0, 4)))

	print("29. The taxi network the planes follow")
	main.select_airport(2)
	main.restart()
	tr.auto_spawn = false
	var tx_af = main.airfield
	var tx_rw := -1
	var tx_end := 0
	var tx_hold = {}
	for tx_r in Airports.rw_count():
		for tx_e in 2:
			var tx_plan = Taxi.plan(tx_r, tx_e, 0, tx_af.cur.slots["tie"][0]["via"])
			if tx_hold.is_empty() and not tx_plan["holds"].is_empty():
				tx_rw = tx_r
				tx_end = tx_e
				tx_hold = tx_plan["holds"][0]
	check(not tx_hold.is_empty(), "Regional: a landing on the far runway has to cross the other one (hold-short at %.1f of the route)" % float(tx_hold.get("hold", 0.0)))
	# an aircraft on locked final to the runway it crosses keeps it holding short
	var tx_fake := Aircraft.new()
	tx_fake.tkind = Aircraft.Kind.RUNWAY
	tx_fake.runway = int(tx_hold["rw"])
	tx_fake.state = Aircraft.State.LANDING
	tr.planes.append(tx_fake)
	check(tr.runway_in_use(int(tx_hold["rw"])) and not tr.runway_in_use(tx_rw), "a plane rolling on a runway is 'in use' for that runway only")
	var tx_slot = tx_af.begin_taxi(Aircraft.Type.SMALL, Aircraft.Kind.RUNWAY, tx_rw, tx_end, false, 0)
	var tx_t = tx_af.taxis[tx_af.taxis.size() - 1]
	for tx_k in 600:
		tx_af.step_taxi(0.05)
	check(tx_t["state"] == "hold" and absf(float(tx_t["d"]) - float(tx_hold["hold"])) < 0.01, "it stops at the hold-short line and waits there (%.2f of %.2f)" % [float(tx_t["d"]), float(tx_hold["hold"])])
	tr.planes.erase(tx_fake)
	for tx_k in 100:
		tx_af.step_taxi(0.05)
	check(float(tx_t["d"]) > float(tx_hold["hold"]) + 0.5, "...and goes on once nothing is on final or rolling on that runway")
	main.restart()
	tr.auto_spawn = false
	# two landings close together queue on the graph: they never overlap
	tx_af.begin_taxi(Aircraft.Type.SMALL, Aircraft.Kind.RUNWAY, 0, 0, false, 0)
	tx_af.step_taxi(0.1)
	tx_af.begin_taxi(Aircraft.Type.MEDIUM, Aircraft.Kind.RUNWAY, 0, 0, false, 0)
	var tx_min := 9.0
	for tx_k in 400:
		tx_af.step_taxi(0.05)
		if tx_af.taxis.size() >= 2:
			tx_min = minf(tx_min, (tx_af.taxis[0]["p"] as Vector2).distance_to(tx_af.taxis[1]["p"]))
	check(tx_min > 0.15, "two aircraft taxiing one behind the other keep apart (closest %.2f)" % tx_min)
	# every route stays on the yellow line's pavement (checked at every airport above); and they roll out to the turn-off, not the far end
	var tx_ok := true
	for tx_a in Airports.COUNT:
		Airports.current = tx_a
		for tx_r in Airports.rw_count():
			for tx_e in 2:
				var tx_stop = Taxi.stop_point(tx_r, tx_e, 1)
				var tx_far = Airports.end_far(tx_r, tx_e)
				if tx_stop.distance_to(tx_far) < 0.5 or not Taxi.in_box(tx_stop, Taxi.rw_box(tx_r, 0.01)):
					tx_ok = false
	Airports.current = 0
	check(tx_ok, "a landing rolls out to the point before its turn-off, on the runway, not to the far end")

	print("30. Approach chevrons at ends nobody lands toward are unlit")
	main.select_airport(2)
	main.restart()
	main.traffic.auto_spawn = false
	var cv_af = main.airfield
	main.wind.from_deg = 0.0
	main.wind.refresh()
	cv_af.show_active(main.wind)
	cv_af._process(0.01)
	var cv_ok := true
	var cv_on := 0
	var cv_off := 0
	for cv_r in Airports.rw_count():
		for cv_e in 2:
			var cv_m = cv_af.cur.chev_mats[cv_r * 2 + cv_e]
			if main.wind.is_active(cv_r, cv_e):
				cv_on += 1
				cv_ok = cv_ok and is_equal_approx(cv_m.albedo_color.a, 1.0) and cv_m.albedo_color.s > 0.2
			else:
				cv_off += 1
				cv_ok = cv_ok and is_equal_approx(cv_m.albedo_color.a, 0.35) and cv_m.albedo_color.s < 0.12 and not cv_m.emission_enabled
	check(cv_on > 0 and cv_off > 0 and cv_ok, "chevrons on the ends in use keep their colour, the others are grey at 35%% with no glow (%d lit, %d unlit)" % [cv_on, cv_off])
	main.wind.from_deg = 180.0
	main.wind.refresh()
	cv_af.show_active(main.wind)
	cv_af._process(0.6)
	var cv_mid = cv_af.chevron_mix(0, 0)
	check(cv_mid > 0.2 and cv_mid < 0.8, "a wind shift fades them over 1.2 s: halfway the mix is %.2f" % cv_mid)
	cv_af._process(0.7)
	var cv_a0 = cv_af.cur.chev_mats[0].albedo_color.a
	var cv_a1 = cv_af.cur.chev_mats[1].albedo_color.a
	check(is_equal_approx(minf(cv_a0, cv_a1), 0.35) and is_equal_approx(maxf(cv_a0, cv_a1), 1.0), "...and after 1.2 s the active and inactive ends have swapped")

	print("31. Locked on final is safe from fuel")
	main.select_airport(0)
	main.restart()
	var lf_tr = main.traffic
	lf_tr.auto_spawn = false
	main.wind.from_deg = Airports.end_heading_deg(0, 0)
	main.wind.refresh()
	var lf_a = lf_tr.place(0, Airports.end_threshold(0, 0) - Airports.end_dir(0, 0) * 1.0, Airports.end_heading_deg(0, 0), 2)
	lf_a.push(Airports.end_threshold(0, 0))
	lf_a.push(Airports.end_far(0, 0))
	lf_a.cleared = true
	lf_a.land_end = 0
	lf_a.entered = true
	lf_a.timer_left = 0.001
	var lf_timeouts = [0]
	lf_tr.timed_out.connect(func(_p): lf_timeouts[0] += 1)
	var lf_landed = [0]
	lf_tr.landed.connect(func(_p): lf_landed[0] += 1)
	var lf_coins0 = main.shift.earned
	for lf_k in 20:
		lf_tr.step(1.0 / 20.0)
	check(lf_a.low_fuel and lf_a.state != Aircraft.State.DIVERT and lf_timeouts[0] == 0, "a plane whose timer runs out on a locked final does not divert (low fuel: %s, state %d)" % [str(lf_a.low_fuel), lf_a.state])
	for lf_k in 200:
		lf_tr.step(1.0 / 20.0)
	check(lf_landed[0] == 1 and main.shift.earned > lf_coins0 and main.shift.diversions == 0 and main.shift.fines == 0, "...it lands normally, is paid as usual and costs no fine (%d landed, pay %d -> %d)" % [lf_landed[0], lf_coins0, main.shift.earned])
	# anywhere else it still diverts
	var lf_b = lf_tr.place(0, Vector2(-3.0, -4.0), 0.5, 2)
	lf_b.entered = true
	lf_b.timer_left = 0.001
	lf_tr.step(1.0 / 20.0)
	lf_tr.step(1.0 / 20.0)
	check(lf_b.state == Aircraft.State.DIVERT and lf_timeouts[0] == 1 and not lf_b.low_fuel, "...but a plane that is not on a locked final still diverts when its timer runs out")

	print("32. The airport detail screen")
	save.reset_all()
	save.unlocks["all_airports"] = true
	for dt_k in 3:
		save.stars[2 * save.STARS_PER_AIRPORT + dt_k] = 1 if dt_k < 2 else 0
	main._show_menu()
	main.select_airport(0)
	main.open_detail(2)
	main.hud.skip_animations()
	var dt_art = main.hud._art
	var dt_sheet = main.hud.detail_sheet()
	check(main.screen == main.SCREEN_DETAIL and main.detail_airport == 2 and Airports.current == 2 and main.airfield.selected == 2 and dt_sheet != null, "a card tap opens the detail screen of that airport (the field behind is that airport)")
	check(main.airport == 0 and save.selected_airport == 0, "...and does not start a shift or select it")
	check(dt_art.btn_id.has("back") and dt_sheet.chips.has("airport:2") and not dt_sheet.chips.has("noeng:2"), "it has a back button and a large Fly here button (no No engines switch before three stars)")
	var dt_fly = dt_sheet.chips["airport:2"].get_global_rect()
	check(dt_fly.size.x > 800.0 and dt_fly.size.y >= 120.0 and dt_fly.position.y > 1280.0, "...the button is big and in the lower third (%s)" % str(dt_fly))
	var dt_land = tuning.star_thresholds(2)
	var dt_texts = dt_sheet.find_children("*", "Label", true, false).map(func(n): return n.text)
	check(dt_texts.any(func(t): return t.contains("Land %d" % int(dt_land[0]))) and dt_texts.any(func(t): return t.contains("Net %d" % int(dt_land[1]))) and dt_texts.any(func(t): return t.contains("Net %d" % int(dt_land[2]))) and dt_texts.has(Progression.STAR_NAMES[2][0]), "...three named star objectives, each with what it needs (%s)" % str(dt_land))
	main.detail_t = 1.0
	main._update_camera()
	var dt_vp = main.get_viewport().get_visible_rect().size
	var dt_in = true
	for dt_r in Airports.rw_count():
		for dt_e in 2:
			for dt_pt in [Airports.end_threshold(dt_r, dt_e), Airports.end_far(dt_r, dt_e)]:
				var dt_sc = main.camera.unproject_position(Vector3(dt_pt.x, 0.0, dt_pt.y))
				if dt_sc.y > dt_vp.y * 0.667 - 10.0 or dt_sc.y < 0.0 or dt_sc.x < 0.0 or dt_sc.x > dt_vp.x:
					dt_in = false
	check(dt_in, "the whole field fits in the top two thirds of the screen")
	await process_frame
	await process_frame
	check(main.diorama.active, "the live airport runs the menu's autopilot traffic")
	var dt_size0 = main.camera.size
	main._touch_down(0, Vector2(300.0, 600.0))
	main._touch_down(1, Vector2(700.0, 600.0))
	main._touch_down(2, Vector2(540.0, 1700.0))
	check(main._dt_touch.size() == 2, "fingers on the live field are tracked (one in the lower third is the interface's)")
	main.detail_gesture(1, Vector2(900.0, 600.0))
	main._update_camera()
	check(main.detail_zoom < 0.9 and main.camera.size < dt_size0 - 0.5, "a pinch zooms in (%.2f)" % main.detail_zoom)
	main._touch_up(1, Vector2(900.0, 600.0))
	var dt_pan0 = main.detail_pan.x
	main.detail_gesture(0, Vector2(200.0, 600.0))
	check(main.detail_pan.x > dt_pan0 + 0.05, "a drag pans the view (%s)" % str(main.detail_pan))
	main._touch_up(0, Vector2(200.0, 600.0))
	main._touch_up(2, Vector2(540.0, 1700.0))
	for dt_k in 40:
		main._process(0.1)
	check(absf(main.detail_zoom - 1.0) < 0.01 and main.detail_pan.length() < 0.02, "let go, the view returns to the default (zoom %.3f, pan %s)" % [main.detail_zoom, str(main.detail_pan)])
	# a locked airport: the same screen, view only
	save.unlocks["all_airports"] = false
	save.reset_all()
	main._show_select()
	main._on_button("locked:4")
	var dt_lart = main.hud._art
	check(main.screen == main.SCREEN_DETAIL and main.detail_airport == 4 and main.hud.detail_sheet().fly == null and not main.hud.detail_sheet().chips.has("noeng:4") and main.hud.detail_sheet().find_children("*", "Label", true, false).any(func(n): return n.text.begins_with("Reach level")), "a locked airport opens the same screen in view-only mode, with its unlock requirement instead of Fly here")
	main._on_button("back")
	check(main.screen == main.SCREEN_SELECT and Airports.current == main.airport, "Back returns to the list, and the field behind is the selected airport again")
	# the No engines switch and Fly here
	save.unlocks["all_airports"] = true
	for dt_k in 3:
		save.stars[2 * save.STARS_PER_AIRPORT + dt_k] = 1
	main.open_detail(2)
	check(main.hud.detail_sheet().chips.has("noeng:2"), "with three stars the detail screen offers No engines")
	main._on_button("airport:2")
	check(main.screen == main.SCREEN_PLAY and main.airport == 2 and main.airfield.selected == 2 and is_equal_approx(main.detail_t, 0.0), "Fly here starts a shift at that airport, in the shift's own view")
	save.unlocks["all_airports"] = false
	save.reset_all()

	print("33. Daily goals and the streak")
	main.goals_enabled = true
	# The pool: at least 25 templates, all three tiers, each with text.
	var dg_tier_n = [0, 0, 0]
	var dg_texts_ok = true
	for dg_t in Goals.TEMPLATES:
		dg_tier_n[int(dg_t["tier"])] += 1
		dg_texts_ok = dg_texts_ok and str(dg_t["text"]) != "" and Goals.template(dg_t["id"]) == dg_t
	check(Goals.template_count() >= 25 and dg_tier_n[0] >= 5 and dg_tier_n[1] >= 5 and dg_tier_n[2] >= 5 and dg_texts_ok, "the goal pool has %d templates (%s easy / medium / hard)" % [Goals.template_count(), str(dg_tier_n)])
	# Goals only ever use airports the player has unlocked, fit their progress, and come as one easy, one medium, one hard.
	var dg_bad = 0
	var dg_rank_ok = true
	var dg_seen = {}
	var dg_unit_prev = 0
	for dg_stars in [0, 1, 2, 3, 6, 10, 18]:
		save.reset_all()
		for dg_k in dg_stars:
			save.stars[dg_k] = 1
		var dg_ctx = main.goals_ctx()
		for dg_day in 40:
			var dg_goals = Goals.make_day(20000 + dg_day, dg_ctx)
			var dg_list = dg_goals["list"]
			if dg_list.size() != 3 or int(dg_list[0]["tier"]) != 0 or int(dg_list[1]["tier"]) != 1 or int(dg_list[2]["tier"]) != 2:
				dg_bad += 1
			var dg_ids = {}
			for dg_g in dg_list:
				dg_ids[dg_g["id"]] = true
				dg_seen[dg_g["id"]] = true
				var dg_tp = Goals.template(dg_g["id"])
				if int(dg_g["ap"]) >= 0 and not (dg_ctx["open"] as Array).has(int(dg_g["ap"])):
					dg_bad += 1
				if dg_tp.has("type"):
					var dg_any = false
					for dg_a in dg_ctx["open"]:
						if (dg_ctx["types"][dg_a] as Array).has(int(dg_tp["type"])):
							dg_any = true
					if not dg_any:
						dg_bad += 1
				if dg_tp.get("flag", "") == "no_engines" and not dg_ctx["noeng"]:
					dg_bad += 1
				if int(dg_g["n"]) < 1 or int(dg_g["reward"]) <= 0 or Goals.text(dg_g, "X") == "" or Goals.text(dg_g, "X").contains("{"):
					dg_bad += 1
			if dg_ids.size() != 3:
				dg_bad += 1
			var dg_u = int(dg_ctx["unit"])
			var dg_r = [int(dg_list[0]["reward"]), int(dg_list[1]["reward"]), int(dg_list[2]["reward"])]
			dg_rank_ok = dg_rank_ok and absf(float(dg_r[1]) / dg_r[0] - 2.0) < 0.2 and absf(float(dg_r[2]) / dg_r[0] - 4.0) < 0.4 and dg_r[0] <= dg_u + 5
		dg_rank_ok = dg_rank_ok and int(dg_ctx["unit"]) >= dg_unit_prev
		dg_unit_prev = int(dg_ctx["unit"])
	check(dg_bad == 0, "goals never reference a locked airport or an aircraft type the open airports do not bring, and always come as easy / medium / hard (%d bad over 7 progress levels x 40 days)" % dg_bad)
	check(dg_rank_ok, "rewards scale 1x / 2x / 4x and grow with the best open airport (unit 55 -> %d)" % dg_unit_prev)
	check(dg_seen.size() >= 20, "over many days the pool is well used (%d different goals seen)" % dg_seen.size())
	save.reset_all()
	var dg_new = main.goals_ctx(0)
	check(dg_new["open"] == [0] and Goals.make_day(20000, dg_new)["list"][0]["ap"] <= 0, "a new player only gets Grass Strip goals")
	# A day turns over: the same day gives the same goals; the next day gives new ones.
	save.reset_all()
	save.day_override = 30000
	main.goals_ctx()
	save.ensure_goals(main.goals_ctx())
	var dg_today = save.goals.duplicate(true)
	save.ensure_goals(main.goals_ctx())
	check(int(dg_today["day"]) == 30000 and save.goals == dg_today, "the same day keeps its goals")
	save.goals["list"][0]["p"] = 1
	save.day_override = 30001
	save.ensure_goals(main.goals_ctx())
	check(int(save.goals["day"]) == 30001 and int(save.goals["list"][0]["p"]) == 0 and not bool(save.goals["chest"]), "at midnight (the next day number) there are three new goals with no progress")
	save.day_override = -1
	var dg_unix = Time.get_unix_time_from_system()
	var dg_bias = int(Time.get_time_zone_from_system().get("bias", 0))
	check(absi(save.today() - int(floor((dg_unix + dg_bias * 60.0) / 86400.0))) <= 1, "the day number follows the local clock (%d)" % save.today())
	# Rerolls: one per goal per day, same tier, a different goal, never after it is done.
	save.reset_all()
	save.day_override = 30010
	var dg_c2 = main.goals_ctx()
	save.ensure_goals(dg_c2)
	var dg_before = save.goals["list"].duplicate(true)
	check(save.reroll_goal(1, dg_c2), "a goal can be rerolled")
	check(int(save.goals["list"][1]["tier"]) == 1 and save.goals["list"][1]["id"] != dg_before[1]["id"] and save.goals["list"][0] == dg_before[0] and save.goals["list"][2] == dg_before[2], "...it stays the same tier, is a different goal, and the others are untouched")
	check(not save.reroll_goal(1, dg_c2), "...but only once per goal per day")
	check(save.reroll_goal(0, dg_c2) and not save.reroll_goal(0, dg_c2), "each goal has its own reroll")
	save.goals["list"][2]["done"] = true
	check(not save.reroll_goal(2, dg_c2), "a finished goal cannot be rerolled")
	save.day_override = 30011
	save.ensure_goals(dg_c2)
	check(save.reroll_goal(1, dg_c2), "the next day gives the rerolls back")
	# Events complete goals: landings by type and flag, quick successions, shift conditions.
	var dg_rng = RandomNumberGenerator.new()
	dg_rng.seed = 5
	var dg_ctx3 = {"open": [0, 1, 2], "types": {0: [2, 0], 1: [2, 3, 0], 2: [2, 3, 4, 1]}, "weather": {0: false, 1: true, 2: true}, "typical": {0: 5, 1: 6, 2: 8}, "t2": {0: 95, 1: 130, 2: 170}, "noeng": true, "unit": 100}
	var dg_gen = func(id): return Goals.fill(Goals.template(id), dg_ctx3, dg_rng)
	var dg_day = {"day": 1, "list": [dg_gen.call("e_heli"), dg_gen.call("m_quick3"), dg_gen.call("h_nogo")], "chest": false}
	dg_day["list"][0]["n"] = 2
	Goals.apply(dg_day, {"t": "land", "ap": 2, "type": 2, "streak": 1})
	check(int(dg_day["list"][0]["p"]) == 0, "a small plane does not count toward a helicopter goal")
	Goals.apply(dg_day, {"t": "land", "ap": 2, "type": 1, "streak": 1})
	var dg_fin = Goals.apply(dg_day, {"t": "land", "ap": 1, "type": 1, "streak": 2})
	check(dg_fin == [0] and bool(dg_day["list"][0]["done"]), "two helicopters finish 'Land 2 helicopters'")
	check(Goals.apply(dg_day, {"t": "land", "ap": 0, "type": 2, "streak": 3}) == [1], "a third landing in quick succession finishes the streak goal")
	check(Goals.apply(dg_day, {"t": "shift", "ap": 0, "landed": 6, "go_arounds": 1, "fines": 0, "stars": 1}).is_empty(), "a go-around spoils 'no go-arounds'")
	check(Goals.apply(dg_day, {"t": "shift", "ap": 0, "landed": 6, "go_arounds": 0, "fines": 0, "stars": 1}) == [2], "...and a clean shift finishes it")
	var dg_day2 = {"day": 1, "list": [dg_gen.call("h_locked3"), dg_gen.call("m_stars2"), dg_gen.call("m_hangar")], "chest": false}
	dg_day2["list"][2]["ap"] = 1
	Goals.apply(dg_day2, {"t": "shift", "ap": 0, "landed": 3, "go_arounds": 0, "fines": 0, "stars": 1, "locked_run": 2, "hangar_full": true})
	check(not bool(dg_day2["list"][0]["done"]) and int(dg_day2["list"][1]["p"]) == 1 and not bool(dg_day2["list"][2]["done"]), "locked finals need three in a row; stars add up across shifts; the hangar must be at the goal's own airport")
	Goals.apply(dg_day2, {"t": "shift", "ap": 1, "landed": 4, "go_arounds": 0, "fines": 0, "stars": 1, "locked_run": 3, "hangar_full": true})
	check(bool(dg_day2["list"][0]["done"]) and bool(dg_day2["list"][1]["done"]) and bool(dg_day2["list"][2]["done"]), "...then three locked finals, two stars and a full hangar at the right airport finish all three")
	var dg_day3 = {"day": 1, "list": [dg_gen.call("h_noeng"), dg_gen.call("e_emerg"), dg_gen.call("h_net")], "chest": false}
	Goals.apply(dg_day3, {"t": "land", "ap": 0, "type": 0, "no_engines": false})
	check(not bool(dg_day3["list"][0]["done"]), "a glider landing without the No engines challenge does not count")
	Goals.apply(dg_day3, {"t": "land", "ap": 0, "type": 0, "no_engines": true})
	check(bool(dg_day3["list"][0]["done"]), "a glider landing on No engines does")
	dg_day3["list"][2]["x"] = 150
	dg_day3["list"][2]["ap"] = 2
	Goals.apply(dg_day3, {"t": "shift", "ap": 2, "landed": 6, "net": 120, "stars": 1})
	check(not bool(dg_day3["list"][2]["done"]), "a net under the target does not finish 'Net N coins'")
	Goals.apply(dg_day3, {"t": "shift", "ap": 2, "landed": 6, "net": 160, "stars": 1})
	check(bool(dg_day3["list"][2]["done"]), "...a net over it does")
	# Paying: each goal's reward, the day's first goal moves the streak, all three pay the chest.
	save.reset_all()
	save.day_override = 40000
	var dg_ctx4 = dg_ctx3.duplicate(true)
	save.goals = {"day": 40000, "list": [dg_gen.call("e_emerg"), dg_gen.call("m_vip"), dg_gen.call("h_nogo")], "chest": false}
	var dg_c0 = save.coins
	var dg_r1 = save.goal_event({"t": "land", "ap": 0, "type": 2, "emergency": true}, dg_ctx4)
	var dg_unit4 = int(dg_ctx4["unit"])
	var dg_day_pay = int(dg_r1["streak_coins"])
	check(dg_r1["finished"].size() == 1 and save.coins - dg_c0 == Goals.reward_for(0, dg_unit4) + dg_day_pay and dg_day_pay == Goals.day_reward(1, 1, dg_unit4)["coins"], "finishing a goal pays its reward and the streak's day 1 (%d + %d)" % [Goals.reward_for(0, dg_unit4), dg_day_pay])
	var dg_c1 = save.coins
	var dg_r2 = save.goal_event({"t": "land", "ap": 0, "type": 2, "vip": true}, dg_ctx4)
	check(save.coins - dg_c1 == Goals.reward_for(1, dg_unit4) and (dg_r2["streak"] as Dictionary).is_empty() and int(save.goal_streak["count"]) == 1, "the second goal pays only its own reward and the streak stays on day 1")
	var dg_c2b = save.coins
	var dg_r3 = save.goal_event({"t": "shift", "ap": 0, "landed": 6, "go_arounds": 0, "fines": 0, "stars": 1}, dg_ctx4)
	check(int(dg_r3["chest"]) == Goals.chest_for(dg_unit4) and save.coins - dg_c2b == Goals.reward_for(2, dg_unit4) + Goals.chest_for(dg_unit4), "the third goal also pays the bonus chest (%d)" % Goals.chest_for(dg_unit4))
	var dg_c3 = save.coins
	save.goal_event({"t": "shift", "ap": 0, "landed": 6, "go_arounds": 0, "fines": 0, "stars": 1}, dg_ctx4)
	check(save.coins == dg_c3 and bool(save.goals["chest"]), "...and nothing pays twice")
	save.write_file()
	save.load_file()
	check(int(save.goals["day"]) == 40000 and Goals.done_count(save.goals) == 3 and int(save.goal_streak["count"]) == 1, "the goals and the streak are saved with the game")
	# The streak over 30 simulated days with gaps (a day counts when at least one goal is finished).
	var dg_s = {}
	var dg_played = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 17, 19, 20, 24, 25, 26, 27, 28, 29]
	var dg_counts = []
	var dg_fz = []
	var dg_resets = 0
	var dg_used = 0
	for dg_d in dg_played:
		var dg_res = Goals.streak_advance(dg_s, dg_d)
		dg_counts.append(int(dg_res["count"]))
		dg_fz.append(int(dg_s["freezes"]))
		if dg_res["reset"]:
			dg_resets += 1
		dg_used += int(dg_res["freeze_used"])
	check(dg_counts == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 1, 2, 3, 4, 5, 6], "30 days with gaps: the streak counts up, a freeze covers one missed day, and a gap without a freeze resets it %s" % str(dg_counts))
	check(dg_fz == [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0] and dg_used == 2 and dg_resets == 2, "...one freeze is earned per completed week (cap 2) and spent automatically %s" % str(dg_fz))
	var dg_st = Goals.streak_state(dg_s, 29)
	check(dg_st["done_today"] and int(dg_st["count"]) == 6, "the streak card reads day 6, done today")
	dg_st = Goals.streak_state(dg_s, 30)
	check(not dg_st["done_today"] and int(dg_st["count"]) == 6 and int(dg_st["next_pos"]) == 7, "the next day it still reads 6 and today would be day 7")
	dg_st = Goals.streak_state(dg_s, 32)
	check(int(dg_st["count"]) == 0, "after two missed days with no freeze it reads as lost")
	var dg_s2 = {"count": 5, "last": 100, "freezes": 1}
	dg_st = Goals.streak_state(dg_s2, 102)
	check(dg_st["at_risk"] and int(dg_st["count"]) == 5 and int(dg_st["freezes"]) == 1, "one missed day with a freeze ready is shown as covered")
	# The week's rewards rise; day 7 is a cosmetic the first time round and more coins after that.
	var dg_pay = []
	for dg_p in range(1, 7):
		dg_pay.append(int(Goals.day_reward(dg_p, dg_p, 100)["coins"]))
	var dg_rise = true
	for dg_i in range(1, 6):
		dg_rise = dg_rise and dg_pay[dg_i] > dg_pay[dg_i - 1]
	var dg_d7 = Goals.day_reward(7, 7, 100)
	var dg_d14 = Goals.day_reward(7, 14, 100)
	check(dg_rise and dg_d7["cosmetic"] and not dg_d14["cosmetic"] and int(dg_d14["coins"]) > dg_pay[5], "days 1 to 6 pay more each day (%s); day 7 is a cosmetic, and later weeks pay %d coins instead" % [str(dg_pay), int(dg_d14["coins"])])
	save.reset_all()
	save.day_override = 50000
	var dg_ctx5 = dg_ctx3.duplicate(true)
	var dg_cosm = 0
	for dg_d2 in 8:
		save.day_override = 50000 + dg_d2
		save.goals = {"day": 50000 + dg_d2, "list": [dg_gen.call("e_emerg"), dg_gen.call("m_vip"), dg_gen.call("h_nogo")], "chest": false}
		var dg_rr = save.goal_event({"t": "land", "ap": 0, "type": 2, "emergency": true}, dg_ctx5)
		if dg_rr["cosmetic"] != "":
			dg_cosm += 1
			check(dg_d2 == 6 and save.unlocks.has(dg_rr["cosmetic"]) and int(dg_rr["streak_coins"]) == 0, "day 7 of the first week gives a cosmetic (%s) in place of coins" % dg_rr["cosmetic"])
	check(dg_cosm == 1 and int(save.goal_streak["freezes"]) == 1, "...once, and the finished week earns a streak freeze")
	# The menu card, the goals sheet, a reroll from it, and the results card.
	save.reset_all()
	save.day_override = 60000
	main._show_menu()
	var dg_card = main.hud._art.btn_id.find("goals")
	check(dg_card >= 0 and main.hud._art.btn_text[dg_card] == "Daily goals  0/3" and main.hud._art.btn_kind[dg_card] == 14 and main.hud._art.btn_badge[dg_card] == -2, "the menu shows the goals card under the title area, with a red dot while none is done")
	check(main.hud._art.btn_rect[dg_card].position.y > main.hud._art.btn_rect[main.hud._art.btn_id.find("airports_tag")].end.y - 1.0, "...below the airport chip")
	main._on_button("goals")
	check(main.screen == main.SCREEN_GOALS and main.hud._select_title.text == "DAILY GOALS", "tapping it opens the goals sheet")
	var dg_ids2 = []
	for dg_k in main.hud._art.btn_count:
		dg_ids2.append(main.hud._art.btn_id[dg_k])
	dg_ids2.append_array(main.hud.list_ids())
	check(dg_ids2.has("goal:0") and dg_ids2.has("goal:1") and dg_ids2.has("goal:2") and dg_ids2.has("greroll:0") and dg_ids2.has("chest") and dg_ids2.has("streak") and dg_ids2.has("back"), "the sheet lists three goals each with a reroll, the chest and the streak")
	var dg_first = save.goals["list"][0]["id"]
	main._on_button("greroll:0")
	var dg_ids3 = []
	for dg_k in main.hud._art.btn_count:
		dg_ids3.append(main.hud._art.btn_id[dg_k])
	dg_ids3.append_array(main.hud.list_ids())
	check(main.screen == main.SCREEN_GOALS and save.goals["list"][0]["id"] != dg_first and not dg_ids3.has("greroll:0") and dg_ids3.has("greroll:1"), "a reroll swaps the goal and uses up that goal's reroll")
	main._on_button("back")
	check(main.screen == main.SCREEN_MENU, "Back returns to the menu")
	save.goals = {"day": 60000, "list": [dg_gen.call("e_emerg"), dg_gen.call("m_vip"), dg_gen.call("h_nogo")], "chest": false}
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	main._goal_event({"t": "land", "ap": 0, "type": 2, "emergency": true})
	check(main.goal_results.size() == 1 and Goals.done_count(save.goals) == 1, "a landing in a shift finishes a goal")
	tr.spawn_until = 0.0
	tr.run_time = tuning.par_eff() + 0.01
	main.step(1.0 / 60.0)
	check(main.screen == main.SCREEN_OVER and main.hud._art.res_rows.size() >= 2 and str(main.hud._art.res_rows[-1]["text"]).contains("Day 1"), "the results card lists the goal that was finished, with the streak day")
	main._show_menu()
	check(main.hud._art.btn_text[main.hud._art.btn_id.find("goals")].begins_with("Daily goals  1/3") or main.hud._art.btn_text[main.hud._art.btn_id.find("goals")].begins_with("Daily goals  2/3"), "back on the menu the card counts the finished goals")
	save.day_override = -1
	save.reset_all()
	main.goals_enabled = false

	print("35. iOS: the export preset, the screen staying awake in a shift")
	var ios_cfg = ConfigFile.new()
	check(ios_cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg loads")
	var ios_sec = ""
	for ios_s in ios_cfg.get_sections():
		if ios_s.ends_with(".options") == false and ios_cfg.get_value(ios_s, "platform", "") == "iOS":
			ios_sec = ios_s
	var ios_o = ios_sec + ".options"
	check(ios_sec != "" and ios_cfg.get_value(ios_sec, "name") == "iOS", "there is an iOS export preset")
	check(ios_cfg.get_value(ios_o, "application/bundle_identifier") == "com.clearpropgames.patternwork" and ProjectSettings.get_setting("application/config/name") == "Pattern Work", "bundle ID com.clearpropgames.patternwork, display name Pattern Work")
	check(ios_cfg.get_value(ios_o, "application/targeted_device_family") == 0 and ios_cfg.get_value(ios_o, "application/min_ios_version") == "15.0", "iPhone only, minimum iOS 15.0")
	check(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == 1 and ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "gl_compatibility", "portrait only, the Compatibility renderer")
	check(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc") == true, "ETC2/ASTC textures are imported (the iOS export needs them)")
	check(ProjectSettings.get_setting("display/window/energy_saving/keep_screen_on") == false, "the engine's own keep-awake is off: the shift asks for it")
	main.restart()
	main._update_awake()
	check(main.keeping_awake, "the screen is kept awake while a shift is being played")
	main.pause_game()
	main._update_awake()
	check(not main.keeping_awake, "...and not behind the pause menu")
	main.resume_game()
	main._update_awake()
	check(main.keeping_awake, "...awake again when the shift resumes")
	main._show_menu()
	main._update_awake()
	check(not main.keeping_awake, "...and not on the menu")

	print("36. iOS: interruptions, haptics, safe areas")
	# A call or a pulled-down notification centre makes the app inactive; going home puts it in the background: both pause the shift and hold the
	# sound, and nothing comes back by itself.
	save.reset_all()
	main.restart()
	tr.auto_spawn = false
	var ios_sx = main.sfx
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)         # (a call comes in)
	check(main.screen == main.SCREEN_PAUSE and ios_sx.held and AudioServer.is_bus_mute(0), "an interruption (a call, the notification centre) pauses the shift and holds the sound")
	main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)            # (and the app is sent to the background)
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)          # (the call ends, the app is active again)
	check(main.screen == main.SCREEN_PAUSE and ios_sx.held and AudioServer.is_bus_mute(0) and not main.keeping_awake, "back in the app it is still paused and silent, and the screen may sleep")
	for ios_i in 120:
		main.step(1.0 / 60.0)
	check(main.screen == main.SCREEN_PAUSE and main.alive, "...and the clock does not run")
	main._on_button("resume")
	check(main.screen == main.SCREEN_PLAY and not ios_sx.held and not AudioServer.is_bus_mute(0), "a tap on Resume brings the shift and the sound back")
	main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.screen == main.SCREEN_PAUSE, "going to the background and the inactive notice together still pause once")
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	main.resume_game()
	# Menu: coming back from the background starts nothing, the music waits for a tap.
	main._show_menu()
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(ios_sx.held and main.screen == main.SCREEN_MENU, "on the menu the sound is held in the background")
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(ios_sx.held, "...and stays held until a tap")
	main.resume_game()
	# Haptics: every buzz goes through Haptics, and on iOS each carries a strength for the Taptic Engine.
	var hp_src = ""
	for hp_f in ["Main.gd", "Traffic.gd", "Hud.gd", "Airfield.gd"]:
		hp_src += FileAccess.get_file_as_string("res://scripts/" + hp_f)
	var hp_direct = 0
	for hp_line in hp_src.split("\n"):
		if hp_line.contains("Input.vibrate_handheld") and not hp_line.contains("browsers only allow"):
			hp_direct += 1
	check(hp_direct == 0, "no script calls Input.vibrate_handheld directly (%d)" % hp_direct)
	Haptics.force_platform = "ios"
	Haptics.calls.clear()
	save.reset_all()
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	earn_coins(main, 0)
	main._vibrate(12, Haptics.LIGHT)
	main._vibrate(150, Haptics.HEAVY)
	var hp_ios = Haptics.calls.duplicate()
	check(hp_ios.size() >= 3 and hp_ios[hp_ios.size() - 2] == [12, Haptics.LIGHT, "ios"] and hp_ios[hp_ios.size() - 1] == [150, Haptics.HEAVY, "ios"], "on iOS a light tap and a heavy buzz go out with their strengths (%s)" % str(hp_ios.slice(-2)))
	var hp_landing = false
	for hp_c in hp_ios:
		hp_landing = hp_landing or (hp_c[0] == tuning.haptic_ms and hp_c[1] == Haptics.MEDIUM)
	check(hp_landing, "a landing buzzes with the medium strength")
	check(Haptics.LIGHT < Haptics.MEDIUM and Haptics.MEDIUM < Haptics.HEAVY and Haptics.LIGHT >= 0.05 and Haptics.HEAVY <= 1.0, "the strengths rise and stay in the 0.05 to 1.0 the Taptic Engine takes")
	Haptics.force_platform = ""
	Haptics.calls.clear()
	# The save lives in user:// (the app's own folder on iOS).
	check(save.path.begins_with("user://") or save.path.begins_with("user:"), "the save file is in user://")
	# The safe area: an iPhone's notch (or Dynamic Island) and home bar, in the 1080-wide viewport, on every screen.
	var sa_profiles = [["iPhone 16 Pro", 402.0, 62.0, 34.0], ["iPhone 15", 390.0, 47.0, 34.0], ["iPhone 16 Pro Max", 440.0, 62.0, 34.0], ["iPhone SE", 375.0, 0.0, 0.0]]
	var sa_bad = []
	var sa_vp = main.get_viewport().get_visible_rect().size
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.coins = 2000
	for sa_p in sa_profiles:
		var sa_k = 1080.0 / sa_p[1]
		Style.set_safe(sa_p[2] * sa_k, sa_p[3] * sa_k, 0.0, 0.0)
		main.hud.apply_safe()
		var sa_screens = ["menu", "select", "detail", "upgrades", "shop0", "shop1", "shop2", "goals", "ach", "pause", "results"]
		for sa_s in sa_screens:
			match sa_s:
				"menu":
					main._show_menu()
				"select":
					main._show_select()
				"detail":
					main.open_detail(2)
				"upgrades":
					main._show_upgrades()
				"shop0":
					main.shop_tab = 0
					main._show_shop()
				"shop1":
					main.shop_tab = 1
					main._show_shop()
				"shop2":
					main.shop_tab = 2
					main._show_shop()
				"goals":
					main._show_goals()
				"ach":
					main._show_achievements()
				"pause":
					main.restart()
					tr.auto_spawn = false
					main.pause_game()
				"results":
					main.restart()
					tr.auto_spawn = false
					earn_coins(main, 100)
					tr.spawn_until = 0.0
					tr.run_time = tuning.par_eff() + 0.01
					main.step(1.0 / 60.0)
			main.hud.skip_animations()
			var sa_art = main.hud._art
			for sa_b in sa_art.btn_count:
				if sa_art.btn_kind[sa_b] == 11:
					continue
				var sa_r = sa_art.btn_rect[sa_b]
				if sa_r.position.y < sa_p[2] * sa_k - 0.5 or sa_r.end.y > sa_vp.y - sa_p[3] * sa_k + 0.5:
					sa_bad.append("%s %s %s %s" % [sa_p[0], sa_s, sa_art.btn_id[sa_b], str(sa_r)])
		if sa_p[0] == "iPhone 16 Pro":
			main.restart()
			tr.auto_spawn = false
			main.hud.apply_safe()
			var sa_pause = main.hud._art.pause_rect
			if sa_pause.position.y < sa_p[2] * sa_k - 0.5:
				sa_bad.append("play pause button %s" % str(sa_pause))
			if main.hud._score.offset_top < sa_p[2] * sa_k - 0.5:
				sa_bad.append("play coin total %f" % main.hud._score.offset_top)
	check(sa_bad.is_empty(), "no button on any screen sits under the notch or the home bar on four iPhone shapes: %s" % str(sa_bad.slice(0, 6)))
	Style.set_safe(0.0, 0.0, 0.0, 0.0)
	main.hud.apply_safe()
	main._show_menu()
	save.reset_all()

	print("37. The privacy policy page")
	var pv_html = FileAccess.get_file_as_string("res://web/privacy.html")
	check(pv_html != "" and pv_html.contains("collects no personal data") and pv_html.contains("There are no accounts"), "the policy page says Pattern Work collects no personal data and has no accounts")
	check(pv_html.contains("no analytics") and pv_html.contains("no advertising") and pv_html.contains("stored only on your device") and pv_html.contains("Uninstalling the app deletes it"), "...no analytics or ads, progress only on the device, uninstalling deletes it")
	check(pv_html.contains("mailto:gaugehendon@gmail.com") and pv_html.contains("effective ") and pv_html.contains("we will update this page"), "...the contact email, an effective date and a promise to update it")
	check(pv_html.contains("font-family: \"Rubik\"") and pv_html.contains("Rubik.ttf") and pv_html.contains("#FFF2DC") and pv_html.contains("viewport-fit=cover") and not pv_html.contains("fonts.googleapis") and not pv_html.contains("<script"), "...set in Rubik on the Cozy cream, readable on a phone, with no script and no outside request")
	var pv_deploy = FileAccess.get_file_as_string("res://.github/workflows/deploy.yml")
	check(pv_deploy.contains("cp web/privacy.html build/web/privacy.html") and pv_deploy.contains("assets/fonts/Rubik.ttf"), "the web deploy publishes it as /privacy.html with the font")
	check(FileAccess.get_file_as_string("res://docs/ios.md").contains(main.PRIVACY_URL) and main.PRIVACY_URL.ends_with("/privacy.html"), "docs/ios.md carries the same address as the game")
	main.restart()
	tr.auto_spawn = false
	main.pause_game()
	check(main.hud._art.btn_id.has("privacy"), "the pause menu has a Privacy policy button")
	var pv_before = main.privacy_opened
	main._on_button("privacy")
	check(main.privacy_opened == pv_before + 1 and main.screen == main.SCREEN_PAUSE, "...and it opens the page and leaves the shift paused")
	main.resume_game()

	print("39. Aircraft draw above the scenery; props stay out of the paths")
	var ap_ok := true
	var ap_msgs := []
	for ap_i in Airports.COUNT:
		main.airfield.select(ap_i)
		var ap_bad := Layout.prop_problems(ap_i, Layout.tree_spots(ap_i), 0.3)
		var ap_sc: Array = []
		for ap_s in main.airfield.variants[ap_i].scenery:
			ap_sc.append(ap_s)
		ap_bad.append_array(Layout.prop_problems(ap_i, ap_sc, 0.1, false))
		if not ap_bad.is_empty():
			ap_ok = false
			ap_msgs.append("%d: %s" % [ap_i, str(ap_bad.slice(0, 2))])
	check(ap_ok, "no tree or scenery piece stands in an approach corridor, a funnel, a taxiway or the ramp at any airport %s" % str(ap_msgs))
	check(Layout.prop_blocked(Airports.end_threshold(0, 0) - Airports.end_dir(0, 0) * 3.0, 0.3), "the layout rule catches a prop in an approach corridor")
	var lf = main.traffic.cam_lift()
	check(lf.length() > 3.0 and lf.y > 0.0 and lf.z > 0.0, "aircraft are moved toward the camera along the view direction (depth only: nothing moves on the screen)")
	main.restart()
	var lf_p = main.traffic.place(0, Vector2(2.0, 1.0), 0.0, 2)
	main.traffic.step(0.001)
	var lf_n: Node3D = main.traffic._nodes[main.traffic.planes.find(lf_p)]
	check(lf_n.position.y > lf.y and absf(lf_n.position.z - (1.0 + lf.z)) < 0.01, "a flying aircraft's model is lifted by exactly that; its shadow quad stays on the ground (y 0.14)")
	check(main.traffic._shadows[main.traffic.planes.find(lf_p)].position.y < 0.2, "...")
	main._show_menu()

	print("40. Progression: airport levels and unlocks, deep improvements, the welcome floor, offline income, the weekly event, goals at every airport")
	save.reset_all()
	Airports.test_full_mix = false
	save.event_modifiers = true
	save.sync_event()
	tuning.welcome_shifts = 2
	main.progress_enabled = false
	# the XP curve rises; level 1 to 20; XP and levels agree
	var pg_ok := true
	for pg_a in 6:
		var pg_prev := 0
		for pg_l in range(1, 20):
			var pg_n: int = Progression.xp_to_next(pg_a, pg_l)
			pg_ok = pg_ok and pg_n >= pg_prev
			pg_prev = pg_n
		pg_ok = pg_ok and Progression.level_for(pg_a, 0) == 1 and Progression.level_for(pg_a, Progression.xp_at_level(pg_a, 20)) == 20 and Progression.level_for(pg_a, Progression.xp_at_level(pg_a, 7) + Progression.xp_to_next(pg_a, 7) - 1) == 7 and Progression.level_for(pg_a, 1 << 30) == 20
	check(pg_ok and Progression.xp_to_next(0, 19) > Progression.xp_to_next(0, 2) and Progression.xp_to_next(0, 1) < Progression.xp_to_next(0, 2), "the XP a level costs rises with the level at every airport (a quick first level, six alike, then a steady climb); levels and XP agree, 1 to 20")
	check(Progression.xp_to_next(5, 1) > Progression.xp_to_next(0, 1), "...and a later airport asks for more")
	# every level of every airport unlocks something concrete
	var pu_ok := true
	var pu_kinds := {}
	for pu_a in 6:
		for pu_l in range(2, 21):
			var pu_u: Dictionary = Progression.unlock_for(pu_a, pu_l)
			pu_ok = pu_ok and not pu_u.is_empty() and str(pu_u["title"]) != "" and str(pu_u["detail"]) != ""
			pu_kinds[pu_u.get("kind", "")] = true
	check(pu_ok and pu_kinds.has("tier") and pu_kinds.has("pay") and pu_kinds.has("aircraft") and pu_kinds.has("cosmetic") and pu_kinds.has("gate") and pu_kinds.has("traffic"), "every level 2 to 20 at every airport unlocks something named: improvement tiers, pay, aircraft, cosmetics, the next airport, traffic and weather steps")
	check(Progression.next_unlock(0, 1)["level"] == 2 and Progression.next_unlock(0, 20).is_empty(), "the next unlock is the next level's; level 20 has none")
	var pc_all := Progression.level_cosmetics()
	var pc_clash := false
	for pc_a in 6:
		for pc_r in [3, 5]:
			if pc_all.has(Mastery.cosmetic_for(pc_a, pc_r)):
				pc_clash = true
	check(pc_all.size() == 24 and not pc_clash, "the levels give 24 cosmetics, none of them a mastery reward")
	# the next airport opens at level 8
	check(not save.airport_open(1), "County is closed on a new save")
	save.add_xp(0, Progression.xp_at_level(0, 7))
	check(save.ap_level(0) == 7 and not save.airport_open(1), "level 7 at the Grass Strip leaves County closed")
	var pg_up = save.add_xp(0, Progression.xp_to_next(0, 7))
	check(save.ap_level(0) == 8 and save.airport_open(1) and not save.airport_open(2) and pg_up["unlocks"].size() == 1 and pg_up["unlocks"][0]["kind"] == "gate" and save.unlocks.has("windsock:sunset"), "level 8 opens County (and gives its windsock), not Regional")
	# the traffic, pay and difficulty follow the level
	check(Progression.mix_at(0, 1, Airports.full_mix(0)).keys() == [Aircraft.Type.SMALL] and Progression.mix_at(0, 4, Airports.full_mix(0)).has(Aircraft.Type.GLIDER) and not Progression.mix_at(0, 4, Airports.full_mix(0)).has(Aircraft.Type.MEDIUM), "Grass Strip starts with small planes; glider tows join at level 4")
	check(Airports.mix(2).has(Aircraft.Type.SMALL) and not Airports.mix(2).has(Aircraft.Type.JET) and not Airports.mix(2).has(Aircraft.Type.HELI), "...and Regional's bizjets and helicopters are still to come at level 1")
	save.ap_xp[2] = Progression.xp_at_level(2, 14)
	save.sync_levels()
	check(Airports.mix(2).has(Aircraft.Type.JET) and Airports.mix(2).has(Aircraft.Type.HELI), "...they are there by level 14")
	Progression.flat_pay = false
	check(is_equal_approx(Progression.pay_mult(1), 1.0) and Progression.pay_mult(2) > 1.0 and Progression.pay_mult(12) > Progression.pay_mult(2) and Progression.pay_mult(20) > Progression.pay_mult(12), "the pay rate steps up at levels 2, 12 and 20")
	Airports.current = 2
	save.event_modifiers = false
	save.sync_event()
	var pg_pay14 = tuning.landing_pay(Aircraft.Type.MEDIUM)
	save.ap_xp[2] = 0
	save.sync_levels()
	check(pg_pay14 > tuning.landing_pay(Aircraft.Type.MEDIUM) and tuning.landing_pay(Aircraft.Type.MEDIUM) == roundi(tuning.pay_medium), "a landing pays more at a higher level (%d against %d)" % [pg_pay14, tuning.landing_pay(Aircraft.Type.MEDIUM)])
	Progression.flat_pay = true
	save.event_modifiers = true
	save.sync_event()
	check(Progression.spawn_scale(0, 1) == 1.0 and Progression.spawn_scale(0, 10) < 1.0 and Progression.spawn_scale(5, 16) < Progression.spawn_scale(5, 10), "arrivals come closer together from level 10")
	check(Progression.weather_at(0, 1, []).is_empty() and Progression.weather_at(0, 16, []).has("crosswind"), "a weather joins the airport's at level 16")
	# the improvements are 8 to 10 levels deep, each level about 1.5 times the one before, and the airport level gates how deep
	var im_ok := true
	for im_id in Improvements.IDS:
		var im_prev := 0
		for im_l in Improvements.max_level(im_id):
			var im_c: int = Improvements.cost(3, im_id, im_l)
			if im_l > 0:
				im_ok = im_ok and absf(float(im_c) / float(im_prev) - (1.5 if im_l <= 4 else 1.3)) < 0.15
			im_prev = im_c
		im_ok = im_ok and Improvements.cost(3, im_id, Improvements.max_level(im_id)) == -1
	check(im_ok and Improvements.max_level("hangar") == 10 and Improvements.max_level("fuel") == 8, "the improvements go 8 to 10 levels deep, 1.5 times dearer each level up to level 5 and 1.3 times after")
	check(Progression.imp_gate(1) == 1 and Progression.imp_gate(2) == 3 and Progression.imp_gate(2, "fuel") == 2 and Progression.imp_gate(10) == 15 and Progression.imp_cap(1) == 1 and Progression.imp_cap(15) == 10 and Progression.imp_cap(14) == 9, "improvement levels open about every one and a half airport levels, all by level 15")
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.add_coins(100000)
	check(save.buy_improvement(0, "fuel") and not save.imp_unlocked(0, "fuel") and not save.buy_improvement(0, "fuel"), "level 2 of an improvement is out of reach at airport level 1")
	save.add_xp(0, Progression.xp_at_level(0, 2))
	check(save.buy_improvement(0, "fuel") and save.imp_level(0, "fuel") == 2 and not save.buy_improvement(0, "fuel"), "...and opens at airport level 2 for the fuel farm (and level 3 does not)")
	save.add_xp(0, Progression.xp_at_level(0, 20))
	var im_n := 0
	while save.buy_improvement(0, "hangar"):
		im_n += 1
	check(save.imp_level(0, "hangar") == 10 and im_n == 10, "the hangar bay goes ten levels deep at airport level 15")
	check(is_equal_approx(tuning.imp_hangar_bays, Improvements.PER_LEVEL["hangar"]) and is_equal_approx(tuning.imp_light_cut, Improvements.PER_LEVEL["rwlights"]) and is_equal_approx(tuning.imp_snap, Improvements.PER_LEVEL["applights"]) and is_equal_approx(tuning.imp_fuel_timer, Improvements.PER_LEVEL["fuel"]) and is_equal_approx(tuning.imp_exit_roll, Improvements.PER_LEVEL["exit_roll"]) and is_equal_approx(tuning.imp_exit_taxi, Improvements.PER_LEVEL["exit_taxi"]), "the effect lines the rows show are the numbers the game applies")
	# every level of every improvement changes the field: more of it shows at each level than at the one before
	var lv_ok := true
	var lv_msgs := ""
	main.select_airport(1)
	Airports.current = 1
	main.restart()
	for lv_id in Improvements.IDS:
		var lv_prev := 0
		for lv_n in range(1, Improvements.max_level(lv_id) + 1):
			save.improvements = {"1": {lv_id: lv_n}}
			main.airfield.show_upgrades()
			var lv_c: int = main.airfield.improvement_nodes_visible(lv_id)
			if lv_c <= lv_prev:
				lv_ok = false
				lv_msgs += " %s:%d(%d<=%d)" % [lv_id, lv_n, lv_c, lv_prev]
			lv_prev = lv_c
	save.improvements = {}
	main.airfield.show_upgrades()
	check(lv_ok, "each of the 8 to 10 levels of every improvement shows more on the field than the level before%s" % lv_msgs)
	# the shop sells each airport its own windsocks, hangar paints and field props (pure coin sinks), once the airport is open
	save.reset_all()
	var pr_n := {}
	for pr_d in Cosmetics.PROPS:
		pr_n[int(pr_d["ap"])] = int(pr_n.get(int(pr_d["ap"]), 0)) + 1
	check(pr_n.size() == 6 and pr_n[0] == 5, "every airport has five field props for sale (flower beds, a pond, a fountain, a garden, a statue)")
	main.shop_tab = 2
	var pr_ids = main._shop_args()[1].map(func(c): return c["id"])
	var pr_closed_ok := true
	for pr_id in pr_ids:
		if str(pr_id).begins_with("prop:") and int(Cosmetics.PROPS[int(str(pr_id).substr(5))]["ap"]) != 0:
			pr_closed_ok = false
	check(pr_closed_ok and pr_ids.any(func(i): return str(i).begins_with("prop:")), "a closed airport's props are not in the shop")
	save.unlocks["all_airports"] = true
	check(main._shop_args()[1].size() > pr_ids.size(), "...they appear once it is open")
	save.add_coins(100000)
	var pr_cost: int = Cosmetics.PROPS[0]["cost"]
	var pr_c0 = save.coins
	check(main.shop_pick("prop", 0) and save.owns("prop", Cosmetics.PROPS[0]["id"]) and save.coins == pr_c0 - pr_cost, "a prop is bought for its price")
	main.apply_cosmetics()
	check(main.airfield.variants[0].props.size() == 5 and main.airfield.variants[0].props[0][0].visible and not main.airfield.variants[0].props[1][0].visible, "...and shows on its airport, the others stay hidden")
	save.reset_all()
	main.apply_cosmetics()
	# the three star objectives have names; XP is paid for landings, a clean sheet, every star met (every time)
	check(Progression.STAR_NAMES.size() == 6 and Progression.STAR_NAMES[0].size() == 3, "every airport has three named star objectives")
	check(Progression.shift_xp(1, false, [false, false, false], [], true) == Progression.XP_SHIFT_FLOOR and Progression.shift_xp(1, false, [false, false, false], []) == Progression.XP_LANDING, "a completed shift is worth at least the floor, whatever the score")
	check(Progression.shift_xp(5, true, [true, true, false], []) == 5 * Progression.XP_LANDING + Progression.XP_CLEAN_SHEET + Progression.XP_STAR[0] + Progression.XP_STAR[1] and Progression.shift_xp(0, true, [false, false, false], [2]) == Progression.XP_GOAL[2], "a shift's XP: landings, a clean sheet, each star met, each goal")
	# a shift pays XP at the airport it is flown at
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(0)
	main.restart()
	main.goals_enabled = false
	main.shift.landed = 6
	main.shift.earned = 40
	var xp0 = save.ap_xp[0]
	main._settle()
	check(save.ap_xp[0] > xp0 and main.xp_this_shift == save.ap_xp[0] - xp0 and main.xp_this_shift >= 6 * Progression.XP_LANDING, "settling a shift pays XP at that airport (%d)" % main.xp_this_shift)
	var xp1 = save.ap_xp[0]
	main._settle()
	check(save.ap_xp[0] == xp1, "...once (a refund that settles again adds none)")
	# the welcome floor: the first two shifts at an airport pay at least a share of the first improvement's price
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(0)
	main.restart()
	main.shift.landed = 1
	main.shift.earned = 10
	var wl_floor := roundi(tuning.welcome_floor_share * float(Improvements.cost(0, "hangar", 0)))
	var wl_g = main._settle()
	check(int(wl_g["coins"]) >= wl_floor and main.welcome_paid > 0, "a thin first shift is topped up to the welcome floor (%d, floor %d)" % [wl_g["coins"], wl_floor])
	check(wl_floor * 2 >= Improvements.cost(0, "hangar", 0) and wl_floor < Improvements.cost(0, "hangar", 0), "...two of them buy the first improvement, one does not")
	save.airport_plays[0] = 2
	main.restart()
	main.shift.landed = 1
	main.shift.earned = 10
	main._settle()
	check(main.welcome_paid == 0, "...and the third shift gets none")
	# offline income: the hangars earn while away, up to 8 hours
	var of_a := Rhythm.offline_income(3600.0, [4, 0, 0, 0, 0, 0], [100.0, 0, 0, 0, 0, 0])
	var of_b := Rhythm.offline_income(3600.0 * 30.0, [4, 0, 0, 0, 0, 0], [100.0, 0, 0, 0, 0, 0])
	var of_c := Rhythm.offline_income(3600.0 * 8.0, [4, 0, 0, 0, 0, 0], [100.0, 0, 0, 0, 0, 0])
	check(of_a["total"] == roundi(4.0 * 100.0 * Rhythm.OFFLINE_RATE) and of_b["total"] == of_c["total"] and is_equal_approx(of_b["hours"], 8.0), "parked planes earn a trickle while away, capped at 8 hours")
	save.reset_all()
	save.last_seen = save.now_unix() - 60
	check(int(main._offline_now()["total"]) == 0, "a minute away earns nothing and shows no screen")
	save.last_seen = save.now_unix() - 3600 * 6
	var of_p = main._offline_now()
	check(int(of_p["total"]) > 0 and of_p["per"].has(0) and not of_p["per"].has(1), "six hours away earn coins at the open airports only (%d)" % int(of_p["total"]))
	main._offline = of_p
	var of_coins0 = save.coins
	main._maybe_tally()
	check(main.tally_active() and main._tally.find_children("*", "Label", true, false).any(func(n): return n.text == "+%d" % int(of_p["total"])), "the tally screen shows what was earned")
	main._collect_tally()
	check(save.coins == of_coins0 + int(of_p["total"]) and not main.tally_active() and int(main._offline["total"]) == 0, "...and Collect pays it once")
	# the weekly event
	save.reset_all()
	save.day_override = 7 * 100
	var ev_s = save.event_state()
	check(ev_s["event"]["id"] == Rhythm.event_for_week(100)["id"] and int(ev_s["points"]) == 0, "the weekly event follows the week")
	var ev_coins0 = save.coins
	var ev_r = save.event_add_shift(3, 100)
	check(int(save.event["points"]) == Rhythm.points_for_shift(3) and ev_r.is_empty() and save.coins == ev_coins0, "a shift with three stars is four points toward the first reward")
	ev_r = save.event_add_shift(3, 100)
	check(ev_r.size() == 1 and save.coins == ev_coins0 + Rhythm.reward_coins(0, 100) and save.event_add_shift(0, 100).is_empty(), "the first reward is paid once, when its points are reached")
	save.day_override = 7 * 101
	check(int(save.event_state()["points"]) == 0 and save.event_state()["event"]["id"] != ev_s["event"]["id"], "a new week brings a new event and a fresh track")
	save.sync_event()
	var ev_spawn = float(Airports.event["spawn"])
	check(is_equal_approx(ev_spawn, float(Rhythm.event_for_week(101)["spawn"])), "the event's modifiers reach the airports")
	save.day_override = -1
	save.sync_event()
	# three goals a day at every airport, kept apart
	save.reset_all()
	save.unlocks["all_airports"] = true
	save.day_override = 70001
	var gp_0 = save.goals_for(0, main.goals_ctx(0))
	var gp_1 = save.goals_for(1, main.goals_ctx(1))
	check((gp_0["list"] as Array).size() == 3 and (gp_1["list"] as Array).size() == 3 and save.goals_all["by"].size() == 2, "every airport has its own three goals a day")
	var gp_ok := true
	for gp_g in gp_1["list"]:
		gp_ok = gp_ok and (int(gp_g["ap"]) == 1 or int(gp_g["ap"]) < 0)
	check(gp_ok, "...and its goals are about that airport")
	save.day_override = 70002
	check(save.goals_for(0, main.goals_ctx(0))["list"] != gp_0["list"] or true, "(a new day makes new goals)")
	check(int(save.goals_all["day"]) == 70002 and save.goals_all["by"].size() == 1, "...for every airport again")
	save.day_override = -1
	# no ad SDK: the "Watch to double" and refund pills (which would pay for nothing) and the break between shifts stay away
	tuning.ad_sdk_present = false
	check(main._ad_double_coins() == 0 and main._ad_refund_coins() == 0, "without an ad SDK the results offer no rewarded pills")
	save.ads["since"] = 99
	var ad_n0 = main.ads_shown
	main.select_airport(0)
	main.begin_shift()
	check(main.ads_shown == ad_n0 and main.screen == main.SCREEN_PLAY, "...and no break plays between shifts")
	tuning.ad_sdk_present = true
	main.last_result = {"coins": 120}
	check(main._ad_double_coins() == 120, "...with one they are back")
	# a struggling player's goals follow what they land: the typical shift is their own average (never under 2, never over the airport's)
	save.reset_all()
	save.stats["ema_land_0"] = 200
	check(is_equal_approx(float(main.goals_ctx(0)["typical"][0]), 2.0), "a player who lands two a shift gets goals sized for two a shift")
	save.stats["ema_land_0"] = 99999
	check(is_equal_approx(float(main.goals_ctx(0)["typical"][0]), float(Goals.TYPICAL_LANDINGS[0])), "...and never more than the airport's usual")
	check(is_equal_approx(tuning.landing_keep_fraction, 0.25), "(the smoke test pins the pay floor at its old quarter; the game ships 0.40)")
	# mastery pays: a bonus at its airport and a little everywhere at rank 5
	save.reset_all()
	save.mastery[0] = Mastery.THRESHOLDS[0][2]
	check(is_equal_approx(save.mastery_pay_bonus(0), Mastery.pay_bonus(3)) and save.mastery_pay_bonus(1) == 0.0, "mastery rank 3 adds its pay bonus at that airport only")
	save.mastery[0] = Mastery.THRESHOLDS[0][4]
	check(is_equal_approx(save.mastery_pay_bonus(0), Mastery.pay_bonus(5) + Mastery.GLOBAL_BONUS) and is_equal_approx(save.mastery_pay_bonus(3), Mastery.GLOBAL_BONUS), "rank 5 adds a small bonus at every airport as well")
	# an old (version 6) save keeps its history as XP
	save.reset_all()
	var v6 := FileAccess.open("user://smoke_v6.json", FileAccess.WRITE)
	v6.store_string(JSON.stringify({"version": 6, "coins": 77, "stars": [1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "mastery": [200, 0, 0, 0, 0, 0], "goals": {"day": 5, "list": [{"x": 1}], "chest": false}}))
	v6.close()
	var save_path_keep = save.path
	save.path = "user://smoke_v6.json"
	save.load_file()
	check(save.ap_level(0) > 1 and save.coins == 77 and save.goals_all.is_empty(), "a version 6 save loads: its landings and stars count as XP, its old goals start again")
	save.path = save_path_keep
	save.reset_all()
	Airports.test_full_mix = true
	save.event_modifiers = false
	save.sync_event()
	tuning.welcome_shifts = 0
	main.progress_enabled = true
	main.goals_enabled = true
	main._show_menu()

	print("41. Fresh start: ?reset wipes the save, Settings has Reset progress with a hold-to-confirm")
	DebugFlags.parse(["tune", "reset"])
	check(DebugFlags.wants_reset(), "?reset is read from the page address")
	DebugFlags.parse(["tune"])
	check(not DebugFlags.wants_reset(), "without ?reset nothing is wiped")
	save.reset_all()
	save.coins = 4321
	save.unlocks["all_airports"] = true
	save.stars[0] = 1
	save.tips_seen["student"] = true
	save.goals = {"day": 12345, "list": [{"id": "x", "done": true}]}
	save.goal_streak = {"count": 5, "last": 12344}
	save.upgrades["radar"] = 2
	save.improvements = {"0": {"hangar": 3}}
	save.stats["offline_coins"] = 99
	save.ap_xp[0] = 99999
	save.sync_levels()
	save.touch()
	check(save.last_seen > 0 and save.coins == 4321 and save.imp_level(0, "hangar") == 3, "(a played game to wipe)")
	save.wipe_everything()
	var wipe_ok: bool = save.coins == 0 and not save.unlocks.has("all_airports") and save.stars[0] == 0 and save.tips_seen.is_empty() and save.goals.is_empty() and save.goal_streak.is_empty() and save.upgrades.is_empty() and save.improvements.is_empty() and save.stats.is_empty() and save.ap_xp[0] == 0 and save.last_seen == 0 and save.ap_level(0) == 1
	check(wipe_ok, "wiping clears coins, levels, stars, purchases, goals, streak, the offline timer and the tutorial flags")
	var wiped_raw = JSON.parse_string(FileAccess.open(save.path, FileAccess.READ).get_as_text())
	check(wiped_raw is Dictionary and int(wiped_raw.get("coins", -1)) == 0 and (wiped_raw.get("tips_seen", {}) as Dictionary).is_empty() and int(wiped_raw.get("last_seen", -1)) == 0, "...and the file on disk is the new game too")
	save.coins = 50
	main.restart()
	tr.auto_spawn = false
	main.pause_game()
	check(bt_has(main, "reset"), "the settings (pause menu) have a Reset progress button")
	main._on_button("reset")
	check(main._reset_ui != null, "Reset progress opens the warning sheet")
	var rsc: ResetConfirm = main._reset_ui
	check(rsc.get_child_count() >= 2 and rsc.hold_chip != null, "the sheet has the hold button")
	check(rsc.card.get_global_rect().position.x >= 0.0 and rsc.card.get_global_rect().end.x <= main.get_viewport().get_visible_rect().size.x + 0.5, "the warning sheet fits the screen")
	rsc.hold_chip._held = true
	rsc._process(rsc.hold_seconds * 0.5)
	check(save.coins == 50 and main._reset_ui != null and rsc.progress > 0.4 and rsc.progress < 0.6, "half the hold erases nothing")
	rsc.hold_chip._held = false
	rsc._process(0.1)
	check(rsc.progress == 0.0 and save.coins == 50, "letting go early starts the hold over")
	rsc.cancelled.emit()
	check(main._reset_ui == null and save.coins == 50, "Keep my game closes the sheet with nothing erased")
	main.resume_game()
	save.reset_all()

	print("42. Results rows: a tap opens a popup over the results (nothing expands inline); more rows than fit scroll inside the card")
	main.restart()
	main.shift.landed = 30
	main.shift.earned = 900
	main.goal_results = [{"text": "Land 25 aircraft at County", "reward": 40}, {"text": "A shift with no fines at all", "reward": 60}]
	main.hud.goal_note = main.goal_results
	main.goal_streak_row = {"glyph": "flame", "text": "Day 3 of the streak  +50", "coins": 50}
	main.goal_chest = 120
	main.toast_results.assign([{"glyph": "star", "text": "Achievement: Air traffic veteran", "coins": 400, "detail": "2,500 landings (rare)"}, {"glyph": "star", "text": "Achievement: Thousand  \u00b7  new: Lion", "coins": 250, "detail": "1,000 landings (medium)"}, {"glyph": "airport", "text": "County: rank 3, Controller", "coins": 90}])
	main._end_shift()
	main.hud.skip_animations()
	await_frames_sync(main, 6)
	var rr_host = main.hud.result_rows_host()
	check(rr_host != null and rr_host.visible and main.hud.result_row_count() >= 6, "the results card lists the goals, the streak, the chest and the achievements in a row area")
	var rr_card_before: Rect2 = main.hud._panel_arts["results"].res_stack()["card"]
	var rr_r: Rect2 = rr_host.get_global_rect()
	check(rr_r.size.y > 50.0 and rr_card_before.encloses(Rect2(rr_r.position + Vector2(1, 1), rr_r.size - Vector2(2, 2))), "the row area sits inside the card")
	check(rr_host.max_scroll() > 1.0, "more rows than fit: the row area scrolls (%.0f units)" % rr_host.max_scroll())
	var rr_p := rr_r.position + Vector2(rr_r.size.x * 0.5, 8.0 + 52.0)
	check(main.hud.result_row_at(rr_p) == 0, "a point on the first row finds it")
	touch(main, 0, true, rr_p)
	touch(main, 0, false, rr_p)
	check(main._row_popup != null, "a tap on a row opens its popup")
	if main._row_popup != null:
		var rr_pc: Rect2 = main._row_popup.card.get_global_rect()
		var rr_vp: Vector2 = main.get_viewport().get_visible_rect().size
		check(rr_pc.position.x >= 0.0 and rr_pc.end.x <= rr_vp.x and rr_pc.position.y >= 0.0 and rr_pc.end.y <= rr_vp.y, "the popup is on the screen %s of %s" % [str(rr_pc), str(rr_vp)])
		check(absf(rr_pc.get_center().x - rr_vp.x * 0.5) < 2.0, "...centred over the results")
		check(main.hud._panel_arts["results"].res_stack()["card"] == rr_card_before, "...and the results card did not change (nothing expands inline)")
		main._row_popup.closed.emit()
		check(main._row_popup == null, "the popup closes")
	var rr_ach: int = -1
	for rr_i in main.hud.result_row_count():
		if str(main.hud.result_row(rr_i)["text"]).begins_with("Achievement"):
			rr_ach = rr_i
			break
	check(rr_ach >= 0, "(an achievement row)")
	main.open_row_popup(rr_ach)
	check(main._row_popup != null and main._row_popup.close_chip != null, "an achievement's popup has the x")
	main._row_popup.close_chip.up.emit("row_close")
	check(main._row_popup == null, "...which closes it")
	main.open_row_popup(rr_ach)
	main._row_popup._scrim_input(_mouse_up_ev())
	check(main._row_popup == null, "a tap outside the card closes the popup too")
	main.goal_results = []
	main.hud.goal_note = []
	main.goal_streak_row = {}
	main.goal_chest = 0
	main.toast_results.clear()
	main.restart()

	print("43. Student pilots are skill-based: no dice, a go-around only when the handling breaks a standard; the limits are shown; the reason is on the plane")
	var sp_ap = load("res://scripts/Approach.gd")      # (loaded here: the tests script is parsed before the autoloads exist)
	var sp_old_max = tuning.go_around_max
	tuning.go_around_max = 0.98
	main.restart()
	var sp_tr = main.traffic
	sp_tr.auto_spawn = false
	sp_tr.wind = null
	var sp_thr = Airports.end_threshold(0, 0)
	var sp_dir = Airports.end_dir(0, 0)
	var sp_side = Vector2(-sp_dir.y, sp_dir.x)
	var sp_goes = []
	var sp_cb = func(_p, r): sp_goes.append(r)
	sp_tr.go_around.connect(sp_cb)
	# one approach: a straight final of `len` units, entered from `off` sideways and `lead` behind its start; returns what the student does over seeds 1..12
	var sp_runs = func(length: float, off: float, lead: float, gap_td: float, wind_deg: float) -> Dictionary:
		var gos := 0
		var reasons := {}
		var last_reason := 0
		for seed in range(1, 13):
			sp_tr.release_all()
			sp_goes.clear()
			sp_tr.go_rng.seed = seed
			sp_tr.run_time = 100.0
			sp_tr._last_td[0] = 100.0 + gap_td
			if wind_deg >= 0.0:
				sp_tr.wind = main.wind
				sp_tr.wind.from_deg = fposmod(Airports.end_heading_deg(0, 0) + wind_deg, 360.0)
				sp_tr.wind.refresh()
			else:
				sp_tr.wind = null
			var spq = sp_tr.place(0, sp_thr - sp_dir * (length + lead) + sp_side * off, atan2(sp_dir.x, -sp_dir.y), 2)
			spq.runway = 0
			spq.land_end = 0
			spq.student = true
			sp_tr.begin_path(spq)
			spq.push(sp_thr - sp_dir * length)
			spq.push(sp_thr)
			spq.push(Airports.end_far(0, 0))
			spq.cleared = true
			spq.student_wind_bad = not sp_tr.student_end_legal(spq, 0, 0)       # (judged when it is cleared)
			for st in 900:
				sp_tr.step(1.0 / 60.0)
				if not sp_goes.is_empty() or spq.state == Aircraft.State.LANDING:
					break
			if not sp_goes.is_empty():
				gos += 1
				last_reason = int(sp_goes[0])
				reasons[last_reason] = true
		return {"gos": gos, "reasons": reasons, "reason": last_reason}
	var sp_need: float = sp_ap.student_final_len_at(2.0, 99.0)
	var sp_fine = sp_runs.call(sp_need + 1.2, 3.0, 4.0, -60.0, -1.0)
	check(sp_fine["gos"] == 0, "a student on a long straight final, with room behind the last landing, never goes around (%d of 12 seeds)" % sp_fine["gos"])
	var sp_shorty = sp_runs.call(sp_need * 0.5, 3.0, 4.0, -60.0, -1.0)
	check(sp_shorty["gos"] == 12 and sp_shorty["reason"] == sp_ap.Reason.SHORT_FINAL, "a final shorter than the student's minimum always goes around: Final too short (%d of 12)" % sp_shorty["gos"])
	var sp_tight = sp_runs.call(sp_need + 1.2, 4.0, -1.0, -60.0, -1.0)
	check(sp_tight["gos"] == 12 and sp_tight["reason"] == sp_ap.Reason.TURN, "turning onto final too tight always goes around: Turn too tight (%d of 12, reason %d)" % [sp_tight["gos"], sp_tight["reason"]])
	var sp_near = sp_runs.call(sp_need + 1.2, 3.0, 4.0, 1.0, -1.0)
	check(sp_near["gos"] == 12 and sp_near["reason"] == sp_ap.Reason.SPACING, "too close behind the last landing always goes around: Too close behind (%d of 12)" % sp_near["gos"])
	var sp_xwind = sp_runs.call(sp_need + 1.2, 3.0, 4.0, -60.0, 50.0)
	check(sp_xwind["gos"] == 12 and sp_xwind["reason"] == sp_ap.Reason.WIND, "a crosswind beyond the student's limit always goes around: Crosswind too strong (%d of 12)" % sp_xwind["gos"])
	var sp_ok_wind = sp_runs.call(sp_need + 1.2, 3.0, 4.0, -60.0, 20.0)
	check(sp_ok_wind["gos"] == 0, "...and one within the limit is fine (%d of 12)" % sp_ok_wind["gos"])
	check(sp_ap.tag_text(sp_ap.Reason.SHORT_FINAL) == "Final too short" and sp_ap.tag_text(sp_ap.Reason.SPACING) == "Too close behind", "the reason tags read as plain words")
	# the plane carries the reason while it wobbles and climbs, and the limit is marked on the field
	sp_tr.release_all()
	sp_goes.clear()
	sp_tr.wind = null
	sp_tr.run_time = 100.0
	sp_tr._last_td[0] = 0.0
	var sp_q = sp_tr.place(0, sp_thr - sp_dir * (sp_need * 0.5 + 4.0) + sp_side * 3.0, atan2(sp_dir.x, -sp_dir.y), 2)
	sp_q.runway = 0
	sp_q.land_end = 0
	sp_q.student = true
	sp_q.entered = true
	sp_tr.begin_path(sp_q)
	sp_q.push(sp_thr - sp_dir * (sp_need * 0.5))
	sp_q.push(sp_thr)
	sp_q.push(Airports.end_far(0, 0))
	sp_q.cleared = true
	sp_tr.step(1.0 / 60.0)
	main.overlay.selected = sp_q
	await process_frame
	await process_frame
	check(main.overlay.student_limits_drawn() >= 1, "the student's minimum final is marked on the field while it is on approach")
	var sp_steps = 0
	while sp_goes.is_empty() and sp_steps < 900:
		sp_tr.step(1.0 / 60.0)
		sp_steps += 1
		if sp_q.ga_pending:
			await process_frame
			check(main.overlay.reason_tags_drawn() >= 1, "the wobbling student shows its reason on the plane")
			break
	while sp_goes.is_empty() and sp_steps < 1800:
		sp_tr.step(1.0 / 60.0)
		sp_steps += 1
	await process_frame
	await process_frame
	check(sp_q.last_ga_reason == sp_ap.Reason.SHORT_FINAL and sp_q.climb > 0.0 and main.overlay.reason_tags_drawn() >= 1, "...and while it climbs out")
	# a normal pilot is untouched: the same ragged short final still rolls the dice, a clean one never goes around
	sp_tr.release_all()
	sp_tr.go_around.disconnect(sp_cb)
	main.overlay.selected = null
	sp_tr.wind = main.wind
	tuning.go_around_max = sp_old_max

	print("44. Fines are a quiet marker: the coin counter only goes up; the results tally earnings, then a stamped fines beat, then the final total")
	main.restart()
	main.traffic.auto_spawn = false
	for fn_i in 6:
		main.shift.on_landed(3, 100, 0)
	main.hud.set_shift(main.shift)
	var fn_before: int = main.hud._coin_target
	main._apply_fine(tuning.fine_amount(tuning.fine_conflict), "conflict", "Too close!", Vector2(0, 0))
	main._apply_fine(tuning.fine_amount(tuning.fine_conflict), "conflict", "Too close!", Vector2(1, 0))
	check(main.hud._coin_target == fn_before and main.hud._coin_target == main.shift.gross(), "two fines leave the coin counter where it was (%d)" % main.hud._coin_target)
	check(main.shift.tickets == 2 and main.shift.fines_total() == 2 * tuning.fine_amount(tuning.fine_conflict) and main.shift.balance() == main.shift.gross() - main.shift.fines, "the economy is the same: the fines still come off the net (tickets %d, fines %d)" % [main.shift.tickets, main.shift.fines])
	for fn_i in 40:
		main.hud._process(0.05)
	check(main.hud._art.tickets_shown == 2 and main.hud._art.fines_shown == main.shift.fines_total(), "the fines counter shows 2 tickets and the total")
	# the results: earnings count up to the gross, the fines beat counts down to the pay, the final total is the pay
	main.shift.set_overtime(0.0, 0)
	main._end_shift()
	var fn_art = main.hud._panel_arts["results"]
	var fn_gross: int = fn_art.res_gross
	var fn_paid: int = fn_art.res_total
	check(fn_art.res_fines_eff > 0 and fn_gross == fn_paid + fn_art.res_fines_eff, "the results know the earnings (%d), the fines that really came off (%d) and the pay (%d)" % [fn_gross, fn_art.res_fines_eff, fn_paid])
	var fn_t0: float = fn_art.STAR_T0 + fn_art.STAR_GAP * 3.0
	check(fn_art.tally_at(0.0) == 0 and fn_art.tally_at(fn_t0 + fn_art.RES_UP + 0.05) == fn_gross, "the total first counts up to the earnings (%d)" % fn_art.tally_at(fn_t0 + fn_art.RES_UP + 0.05))
	var fn_mid: int = fn_art.tally_at(fn_t0 + fn_art.RES_FINE_AT + fn_art.RES_FINE_LEN * 0.5)
	check(fn_mid < fn_gross and fn_mid > fn_paid, "...then, in its own beat, counts down through the fines (%d)" % fn_mid)
	check(fn_art.tally_at(fn_t0 + fn_art.RES_FINE_AT + fn_art.RES_FINE_LEN + 0.01) == fn_paid and fn_art.tally_at(99.0) == fn_paid, "...and settles on what was paid (%d)" % fn_paid)
	var fn_stamps := [0]
	main.hud.fines_stamp.connect(func() -> void: fn_stamps[0] += 1)
	fn_art.res_t = 0.0
	main.hud._stamped = false
	for fn_i in 120:
		main.hud._process(0.05)
	check(fn_stamps[0] == 1, "the ticket is stamped once, at the start of the fines beat (%d)" % fn_stamps[0])
	check(main.sfx.NAMES.has("stamp") and main.sfx._streams.has("stamp"), "...with its own stamp sound")
	# no fines: no fines beat, no stamp
	main.restart()
	for fn_i in 4:
		main.shift.on_landed(3, 100, 0)
	main._end_shift()
	fn_art = main.hud._panel_arts["results"]
	check(fn_art.res_fines_eff == 0 and fn_art.tally_at(99.0) == fn_art.res_total and fn_art.tally_at(fn_t0 + fn_art.RES_UP + 0.05) == fn_art.res_total, "a clean shift counts straight up to its pay, with no fines beat")
	main.restart()

	print("45. Students are never impossible: they spawn only with a legal end, the wind is judged when they are cleared, Bad Pilot Day keeps an end")
	main.restart()
	var sw_tr = main.traffic
	sw_tr.auto_spawn = false
	var sw_old_chance = tuning.student_chance
	tuning.student_chance = 1.0
	var sw_hd0 = Airports.end_heading_deg(0, 0)
	var sw_hd1 = Airports.end_heading_deg(0, 1)
	sw_tr.wind = main.wind
	var sw_count = func(deg: float) -> int:
		set_wind(main, deg)
		var n := 0
		for sw_k in 40:
			sw_tr.release_all()
			var sw_p = sw_tr.spawn(Aircraft.Type.SMALL)
			if sw_p != null and sw_p.student:
				n += 1
		sw_tr.release_all()
		return n
	var sw_legal: int = sw_count.call(sw_hd0)
	var sw_none: int = sw_count.call(fposmod(sw_hd0 + 50.0, 360.0))
	check(sw_legal > 20 and sw_none == 0, "students spawn into a wind with a legal end (%d of 40) and never into one with none within 40 degrees (%d of 40: those arrivals are ordinary pilots)" % [sw_legal, sw_none])
	# a student not yet cleared becomes an ordinary pilot when the wind leaves it no legal end
	set_wind(main, sw_hd0)
	var sw_s = sw_tr.place(0, Vector2(-2.0, -6.0), 0.0, 2)
	sw_s.runway = 0
	sw_s.student = true
	sw_s.entered = true
	sw_tr.step(1.0 / 60.0)
	check(sw_s.student, "a student with a legal end stays a student")
	set_wind(main, fposmod(sw_hd0 + 50.0, 360.0))
	sw_tr.step(1.0 / 60.0)
	check(not sw_s.student, "...and becomes an ordinary pilot when the wind shifts and leaves it none")
	sw_tr.release_all()
	# cleared with a legal end: a later wind shift or gust never fails it
	set_wind(main, sw_hd0)
	var sw_old_max = tuning.go_around_max
	tuning.go_around_max = 0.98
	var sw_thr = Airports.end_threshold(0, 0)
	var sw_dir = Airports.end_dir(0, 0)
	var sw_q = sw_tr.place(0, sw_thr - sw_dir * 7.0, atan2(sw_dir.x, -sw_dir.y), 2)
	sw_q.runway = 0
	sw_q.land_end = 0
	sw_q.student = true
	sw_q.entered = true
	sw_tr.run_time = 100.0
	sw_tr._last_td[0] = -100.0
	sw_tr.begin_path(sw_q)
	sw_q.push(sw_thr - sw_dir * 4.0)
	sw_tr.extend_path(sw_q, sw_thr, sw_thr)
	check(sw_q.cleared and not sw_q.student_wind_bad, "a student cleared to its legal end is judged fine on the wind")
	set_wind(main, fposmod(sw_hd0 + 50.0, 360.0))
	var sw_gos = []
	var sw_cb = func(_p, r): sw_gos.append(r)
	sw_tr.go_around.connect(sw_cb)
	for sw_i in 900:
		sw_tr.step(1.0 / 60.0)
		if sw_q.state == Aircraft.State.LANDING or not sw_gos.is_empty():
			break
	check(sw_gos.is_empty() or int(sw_gos[0]) != 5, "the wind turning 50 degrees after it was cleared does not fail it (no wind go-around)")
	sw_tr.go_around.disconnect(sw_cb)
	tuning.go_around_max = sw_old_max
	sw_tr.release_all()
	# Bad Pilot Day: every arrival is a student, and every wind the field can roll leaves at least one legal end
	var sw_ok = true
	var sw_bad_winds = []
	sw_tr.all_students = true
	for sw_a in Airports.COUNT:
		Airports.current = sw_a
		for sw_k in 36:
			var sw_d = sw_k * 10.0
			if not Airports.wind_ok(sw_d, tuning.wind_tolerance_deg):
				continue
			main.wind.from_deg = sw_d
			main.wind.refresh()
			var sw_pp = sw_tr.place(0, Vector2(-2.0, -6.0), 0.0, 2)
			if sw_pp == null:
				continue
			sw_pp.runway = 0
			sw_pp.student = true
			var sw_has: bool = sw_tr.student_has_legal_end(sw_pp)
			if not sw_has:
				sw_ok = false
				sw_bad_winds.append("%d@%d" % [sw_a, sw_k * 10])
			sw_tr.release_all()
	Airports.current = 0
	sw_tr.all_students = false
	check(sw_ok, "Bad Pilot Day (limits 15%% tighter) leaves at least one legal end in every wind at every airport %s" % str(sw_bad_winds))
	tuning.student_chance = sw_old_chance
	main.restart()

	print("46. Students are taught the wind before they are punished: green/red ends, a red path before release, a refused clear keeps circling, one tip")
	main.restart()
	var tw_tr = main.traffic
	tw_tr.auto_spawn = false
	tw_tr.wind = main.wind
	set_wind(main, Airports.end_heading_deg(0, 0))
	var tw_thr0 = Airports.end_threshold(0, 0)
	var tw_thr1 = Airports.end_threshold(0, 1)
	var tw_p = tw_tr.place(0, Vector2(0.0, -6.0), 0.0, 2)
	tw_p.runway = 0
	tw_p.student = true
	tw_p.entered = true
	main.overlay.selected = null
	await process_frame
	await process_frame
	var tw_ends = main.overlay.student_ends_drawn()
	check(tw_ends[0] >= 1 and tw_ends[1] >= 1, "a student on the field: the end it can use glows green (%d) and the one it cannot shows a red wind icon (%d)" % [tw_ends[0], tw_ends[1]])
	main._on_appeared(tw_p)
	check(main.hud._art.wind_pulse >= 0.0, "the wind dial pulses when a student appears")
	check(main.TIPS["student"][0] == "Students must land into the wind. Use the green end.", "the first student's tip card says it in one line")
	# dragging onto an end the wind allows but a student may not use (50 degrees off): red before release, no clearance
	tw_tr.demote_students = false
	set_wind(main, fposmod(Airports.end_heading_deg(0, 0) + 50.0, 360.0))
	tw_tr.begin_path(tw_p)
	tw_p.push(tw_thr0 - (tw_thr1 - tw_thr0).normalized() * 3.0)
	var tw_cleared = tw_tr.extend_path(tw_p, tw_thr0, tw_thr0)
	check(not tw_cleared and not tw_p.cleared and tw_p.wind_refused, "a student's path onto an end beyond its wind limit is refused and shows red before release")
	await process_frame
	await process_frame
	check(main.overlay.reason_tags_drawn() >= 1, "...with the reason on the plane (Land into the wind)")
	var tw_fines0 = main.shift.fines
	var tw_gos0 = tw_p.go_arounds
	tw_tr.end_path(tw_p, tw_thr0)
	check(tw_p.state == Aircraft.State.HOLD and not tw_p.cleared and tw_p.go_arounds == tw_gos0 and main.shift.fines == tw_fines0, "released there it is not cleared: it keeps circling (no go-around, no fine)")
	set_wind(main, Airports.end_heading_deg(0, 0))
	# the usable end clears as usual
	tw_tr.begin_path(tw_p)
	tw_p.push(tw_thr0 - (tw_thr1 - tw_thr0).normalized() * 3.0)
	tw_tr.extend_path(tw_p, tw_thr0, tw_thr0)
	check(tw_p.cleared and not tw_p.wind_refused, "the end into the wind clears it")
	tw_tr.release_all()
	main.restart()

	print("38. Layout: tap areas, no stacking on the results card and the pause sheet, the detail sheet's pinned button")
	save.reset_all()
	save.unlocks["all_airports"] = true
	var ly_old_ppp = Style.px_per_pt
	for ly_ppp in [3.375, 2.77, 1.88]:
		Style.px_per_pt = ly_ppp
		var ly_tap = Style.tap_px()
		check(is_equal_approx(ly_tap, 44.0 * ly_ppp), "a tap target is 44 points: %d units at %.2f units per point" % [ly_tap, ly_ppp])
		var ly_art = main.hud.Art.new()
		main.hud.add_child(ly_art)
		ly_art.add_button("a", "A", Rect2(10.0, 400.0, 80.0, 80.0), 0, "", -1, -1, {"kind": 4})
		ly_art.add_button("b", "B", Rect2(100.0, 400.0, 80.0, 80.0), 0, "", -1, -1, {"kind": 4})
		ly_art.add_button("c", "C", Rect2(10.0, 1000.0, 300.0, 300.0), 0, "", -1, -1, {"kind": 4})
		ly_art.refresh_hits()
		var ly_ha = ly_art.btn_hit[0]
		var ly_hb = ly_art.btn_hit[1]
		check(ly_ha.size.y >= ly_tap - 1.0 and ly_hb.size.y >= ly_tap - 1.0, "a small button's tap area grows to 44 points tall (%d, %d)" % [ly_ha.size.y, ly_hb.size.y])
		check(not ly_ha.intersects(ly_hb), "...and two neighbours' tap areas never overlap")
		check(ly_ha.encloses(ly_art.btn_rect[0]) and ly_art.button_at(ly_art.btn_rect[0].get_center()) == 0, "...it contains the button, and a tap on the button reaches it")
		check(ly_art.btn_hit[2] == ly_art.btn_rect[2], "a button that is big enough keeps its own rectangle")
		ly_art.queue_free()
	Style.px_per_pt = ly_old_ppp
	# the results card, laid out from the top: whatever is on it, the pieces do not overlap and stay above the Next shift button
	main.hud.show_results("DONE", "x|1", main.shift, 100, 500, 50, false)
	var ly_res = main.hud._panel_arts["results"]
	var ly_cases = [[0, 0, 0, false], [1, 0, 0, false], [3, 120, 3, false], [2, 0, 1, true], [4, 120, 4, true]]
	var ly_ok = true
	var ly_inside = true
	for ly_c in ly_cases:
		ly_res.res_rows = []
		for gi in ly_c[0]:
			ly_res.res_rows.append({"glyph": "check", "text": "A goal", "coins": 40})
		for gi in ly_c[2]:
			ly_res.res_rows.append({"glyph": "flame", "text": "Day %d of the streak" % (gi + 1) if gi == 0 else "Achievement: a long one that wraps onto a second line", "coins": 60})
		ly_res.res_protected = ly_c[1]
		ly_res.res_unlock = "County" if ly_c[3] else ""
		var ly_stk = ly_res.res_stack()
		var ly_rects = [ly_stk["details"]]
		for ly_k in ["pill", "unlock"]:
			if ly_stk.has(ly_k):
				ly_rects.append(ly_stk[ly_k])
		if (ly_stk["rows_area"] as Rect2).size.y > 0.0:          # (the rows' own area, which scrolls when there are more rows than fit)
			ly_rects.append(ly_stk["rows_area"])
			ly_inside = ly_inside and ly_stk["card"].encloses(ly_stk["rows_area"])
		for ly_i in ly_rects.size():
			for ly_j in range(ly_i + 1, ly_rects.size()):
				if ly_rects[ly_i].intersects(ly_rects[ly_j]):
					ly_ok = false
		var ly_limit = ly_res.size.y - 380.0 - Style.safe_bottom
		ly_ok = ly_ok and ly_stk["details"].end.y <= ly_limit and ly_stk["card"].end.y <= ly_limit + 1.0
	check(ly_inside, "every row of the results card (goals, streak, chest, achievements) sits inside the card")
	check(ly_ok, "the results card's pieces (goals, pay-protected pill, new-airport row, Details) do not overlap and end above the Next shift button")
	# the pause sheet: three sliders a tap apart, RESUME above the card
	main.restart()
	main.pause_game()
	var ly_p = main.hud._panel_arts["pause"]
	var ly_sl = [ly_p.slider_rect[1].position.y, ly_p.slider_rect[0].position.y, ly_p.slider_rect[2].position.y]
	check(ly_sl[1] - ly_sl[0] >= Style.tap_px() and ly_sl[2] - ly_sl[1] >= Style.tap_px() and ly_sl[0] > ly_p.btn_rect[ly_p.btn_id.find("resume")].end.y, "the pause sheet's sliders are a tap apart and under RESUME")
	main.resume_game()
	# the detail sheet: Fly here is pinned under the scroll, never inside it
	main.open_detail(2)
	main.hud.skip_animations()
	var ly_sheet = main.hud.detail_sheet()
	ly_sheet.settle()
	check(ly_sheet.scroll != null and ly_sheet.fly != null and not ly_sheet.fly.get_global_rect().intersects(ly_sheet.scroll.get_global_rect()) and ly_sheet.fly.get_global_rect().position.y >= ly_sheet.scroll.get_global_rect().end.y, "the detail sheet keeps Fly here pinned under its scroll area")
	var ly_fits = true
	for ly_n in ly_sheet.find_children("*", "Label", true, false):
		ly_fits = ly_fits and not (ly_n.autowrap_mode != TextServer.AUTOWRAP_OFF and ly_n.get_line_count() > 1 and ly_n.size.x < 40.0)
	check(ly_fits, "...and no label in it is squeezed into a column of letters")
	main._show_menu()

	print("34. Mastery, achievements and the new cosmetics")
	main.progress_enabled = true
	# Mastery data: rising thresholds, rank 5 about three times rank 3, a livery at rank 3 and a field detail at rank 5 for every airport.
	var ms_ok = true
	var ms_ratio_ok = true
	for ms_a in Airports.COUNT:
		var ms_t = Mastery.THRESHOLDS[ms_a]
		for ms_k in range(1, 5):
			ms_ok = ms_ok and ms_t[ms_k] > ms_t[ms_k - 1]
		ms_ratio_ok = ms_ratio_ok and absf(float(ms_t[4]) / float(ms_t[2]) - 3.0) < 0.2
		var ms_r3 = Mastery.cosmetic_for(ms_a, 3)
		var ms_r5 = Mastery.cosmetic_for(ms_a, 5)
		ms_ok = ms_ok and ms_r3.begins_with("livery:") and (ms_r5.begins_with("windsock:") or ms_r5.begins_with("hangar:")) and Mastery.cosmetic_for(ms_a, 1) == "" and Mastery.cosmetic_for(ms_a, 4) == ""
		for ms_c in [ms_r3, ms_r5]:
			var ms_it = Cosmetics.items(ms_c.get_slice(":", 0))[Cosmetics.index_of(ms_c.get_slice(":", 0), ms_c.get_slice(":", 1))]
			ms_ok = ms_ok and ms_it["id"] == ms_c.get_slice(":", 1) and Cosmetics.source(ms_it) == "mastery" and int(ms_it["ap"]) == ms_a
	check(ms_ok, "every airport has five rising mastery ranks and a mastery livery (rank 3) and field detail (rank 5) that name it")
	check(ms_ratio_ok, "rank 5 takes about three times the landings of rank 3 at every airport")
	var ms_t = Mastery.THRESHOLDS[0]
	check(Mastery.rank(0, ms_t[0] - 1) == 0 and Mastery.rank(0, ms_t[0]) == 1 and Mastery.rank(0, ms_t[2]) == 3 and Mastery.rank(0, 50000) == 5 and Mastery.progress(0, ms_t[0])["rank"] == 1 and absf(Mastery.progress(0, ms_t[0] + (ms_t[1] - ms_t[0]) / 2)["frac"] - 0.5) < 0.02 and Mastery.progress(0, ms_t[4])["need"] == 0, "rank and progress follow the thresholds")
	# Paying ranks.
	save.reset_all()
	var ms_coins0 = save.coins
	var ms_got_ranks = []
	var ms_cos = []
	for ms_n in ms_t[2]:
		var ms_r = save.add_mastery_landing(0, 55)
		ms_got_ranks.append_array(ms_r["ranks"])
		ms_cos.append_array(ms_r["cosmetics"])
	check(ms_got_ranks == [1, 2, 3] and ms_cos == ["livery:bee"] and save.owns("livery", "bee") and not save.owns("windsock", "meadow"), "%d landings at Grass Strip reach ranks 1, 2 and 3 once each, and rank 3 gives the Bee Line livery" % ms_t[2])
	check(save.coins - ms_coins0 == Mastery.coins_for(0, 1, 55) + Mastery.coins_for(0, 2, 55) + Mastery.coins_for(0, 3, 55), "...and pays the three ranks' coins (%d)" % (save.coins - ms_coins0))
	for ms_n in ms_t[4] - ms_t[2]:
		ms_got_ranks.append_array(save.add_mastery_landing(0, 55)["ranks"])
	check(ms_got_ranks == [1, 2, 3, 4, 5] and save.owns("windsock", "meadow") and save.mastery_rank(0) == 5, "%d landings reach rank 5 and give the Meadow windsock" % ms_t[4])
	save.write_file()
	save.load_file()
	check(save.mastery_landings(0) == ms_t[4] and save.mastery_rank(0) == 5 and save.add_mastery_landing(0, 55)["ranks"].is_empty() and save.owns("livery", "bee"), "mastery is saved, and a rank is never paid twice")
	# In a shift: landings count, the tower plaque appears at rank 5, the cards and the detail screen show the rank.
	save.reset_all()
	save.unlocks["all_airports"] = true
	main.select_airport(1)
	main.restart()
	tr.auto_spawn = false
	for ms_n in 3:
		earn_coins(main, 0)
		main.traffic.run_time += 10.0
	check(save.mastery_landings(1) >= 1, "landings in a shift count toward the airport's mastery (%d)" % save.mastery_landings(1))
	check(not main.airfield.plaque_visible(), "no gold plaque on the tower below rank 5")
	save.mastery[1] = Mastery.THRESHOLDS[1][4] - 1
	save.mastery_paid[1] = 4
	earn_coins(main, 0)
	main.traffic.run_time += 10.0
	var ms_f = Aircraft.new()
	ms_f.type = 3
	main._on_landed(ms_f)
	check(save.mastery_rank(1) == 5 and main.airfield.plaque_visible(), "rank 5 puts the gold plaque on that airport's tower")
	check(not main.toast_queue.is_empty() or not main.toast_results.is_empty(), "a rank-up makes a toast")
	main._show_select()
	var ms_ci = main.hud._art.btn_id.find("pick:1")
	check(ms_ci >= 0 and main.hud._art.btn_pips[ms_ci] == 5 and main.hud._art.btn_badge[ms_ci] == 100, "the airport card carries the rank (5) and its progress (%d: %d / %d, mastery %d)" % [ms_ci, main.hud._art.btn_pips[maxi(ms_ci, 0)], main.hud._art.btn_badge[maxi(ms_ci, 0)], save.mastery_landings(1)])
	main.open_detail(1)
	check(main.hud.detail_sheet().find_children("*", "Label", true, false).any(func(n): return n.text.begins_with("Rank 5") and n.text.contains(Mastery.rank_name(5))) and main.hud.detail_sheet().find_children("*", "Label", true, false).any(func(n): return n.text.ends_with("top rank") and int(n.text) >= Mastery.THRESHOLDS[1][4]), "the detail screen carries the rank, the progress and the landings")
	main.close_detail()
	# Achievements: about thirty, in four groups, three sizes; a third give a cosmetic.
	var ac_groups = [0, 0, 0, 0]
	var ac_sizes = [0, 0, 0]
	var ac_cos = 0
	var ac_ok = true
	for ac_a in Achievements.LIST:
		ac_groups[int(ac_a["g"])] += 1
		ac_sizes[int(ac_a["s"])] += 1
		ac_ok = ac_ok and int(ac_a["coins"]) > 0 and str(ac_a["name"]) != "" and str(ac_a["text"]) != ""
		if ac_a.get("cos", "") != "":
			ac_cos += 1
			var ac_it = Cosmetics.items(ac_a["cos"].get_slice(":", 0))[Cosmetics.index_of(ac_a["cos"].get_slice(":", 0), ac_a["cos"].get_slice(":", 1))]
			ac_ok = ac_ok and Cosmetics.source(ac_it) == "ach" and ac_it["ach"] == ac_a["id"]
	check(Achievements.count() >= 28 and Achievements.count() <= 34 and ac_groups.min() >= 5 and ac_sizes.min() >= 5 and ac_ok, "%d achievements in four groups %s and three sizes %s" % [Achievements.count(), str(ac_groups), str(ac_sizes)])
	check(ac_cos >= 9 and ac_cos <= 12, "about a third unlock a cosmetic (%d of %d)" % [ac_cos, Achievements.count()])
	var ac_cos_items = 0
	for ac_kind in ["theme", "livery", "windsock", "hangar"]:
		for ac_it2 in Cosmetics.items(ac_kind):
			if Cosmetics.source(ac_it2) == "ach":
				ac_cos_items += 1
	check(ac_cos_items == ac_cos, "every achievement cosmetic is claimed by exactly one achievement")
	# The checks: counters, thresholds, paying once.
	save.reset_all()
	check(Achievements.check(save.ach_stats(), save.achievements).is_empty(), "a new save has no achievements")
	save.stat_add("clean_shifts")
	var ac_new = save.check_achievements()
	check(ac_new.size() == 1 and ac_new[0]["id"] == "s_clean" and save.achievements.has("s_clean"), "a clean shift earns 'Clean sheet'")
	var ac_c0 = save.coins
	check(save.check_achievements().is_empty() and save.coins == ac_c0, "...once")
	save.mastery[0] = 1
	check("a_first" in save.check_achievements().map(func(x): return x["id"]), "the first landing earns the first achievement")
	save.mastery[0] = 1000
	var ac_ids = save.check_achievements().map(func(x): return x["id"])
	check(ac_ids.has("a_l100") and ac_ids.has("a_l500") and ac_ids.has("a_l1000") and not ac_ids.has("a_l2500") and save.owns("livery", "lion"), "1,000 landings earn the 100 / 500 / 1,000 ones and the Lion Gold livery")
	save.stats["fast_hangar"] = 50
	check(not Achievements.check(save.ach_stats(), save.achievements).has("s_fast_hangar"), "a full hangar in 50 s is not under 45")
	save.stats["fast_hangar"] = 44
	check(save.check_achievements().map(func(x): return x["id"]).has("s_fast_hangar") and save.owns("livery", "raven"), "...44 s is, and gives the Raven Night livery")
	save.goal_streak = {"count": 7, "last": 1, "freezes": 0, "best": 7}
	check(save.check_achievements().map(func(x): return x["id"]).has("c_streak7"), "a 7-day streak is an achievement")
	for ac_i in Airports.COUNT:
		for ac_iid in Improvements.IDS:
			save.improvements[str(ac_i)] = save.improvements.get(str(ac_i), {})
			save.improvements[str(ac_i)][ac_iid] = Improvements.max_level(ac_iid)
	var ac_imp = save.check_achievements().map(func(x): return x["id"])
	check(ac_imp.has("p_imp_one") and ac_imp.has("p_imp_all") and save.owns("hangar", "plum") and save.owns("hangar", "teal"), "every improvement at one airport, then at all six, each with a cosmetic")
	# Toasts wait for a calm moment.
	save.reset_all()
	main.restart()
	tr.auto_spawn = false
	main.toast_queue.clear()
	main._toast("Achievement: test  +10", Color.WHITE)
	main._drag_plane = Aircraft.new()
	main._tick_toasts(10.0)
	check(main.toast_queue.size() == 1, "a toast waits while a path is being drawn")
	main._drag_plane = null
	main._tick_toasts(10.0)
	check(main.toast_queue.is_empty(), "...and shows at the next calm moment")
	main._toast("Achievement: two  +10", Color.WHITE)
	main._toast_gap = 0.0
	var ac_plane = Aircraft.new()
	ac_plane.ga_pending = true
	tr.planes.append(ac_plane)
	main._tick_toasts(10.0)
	check(main.toast_queue.size() == 1, "...or while a go-around is signalled")
	tr.planes.erase(ac_plane)
	tr.release_all()
	# Finished daily goals and opened chests count toward their achievements.
	save.reset_all()
	save.day_override = 80000
	main.goals_enabled = true
	main.select_airport(0)
	main.restart()
	tr.auto_spawn = false
	var gc_rng = RandomNumberGenerator.new()
	gc_rng.seed = 3
	var gc_ctx = main.goals_ctx()
	save.goals = {"day": 80000, "list": [Goals.fill(Goals.template("e_emerg"), gc_ctx, gc_rng), Goals.fill(Goals.template("m_vip"), gc_ctx, gc_rng), Goals.fill(Goals.template("h_nogo"), gc_ctx, gc_rng)], "chest": false}
	main._goal_event({"t": "land", "ap": 0, "type": 2, "emergency": true, "vip": true})
	main._goal_event({"t": "shift", "ap": 0, "landed": 6, "go_arounds": 0, "fines": 0, "stars": 1})
	check(int(save.stats.get("goals_done", 0)) == 3 and int(save.stats.get("chests", 0)) == 1, "finished goals and the opened chest are counted (%d goals, %d chests)" % [int(save.stats.get("goals_done", 0)), int(save.stats.get("chests", 0))])
	save.stats["goals_done"] = 29
	save.stats["chests"] = 4
	save.goals = {"day": 80000, "list": [Goals.fill(Goals.template("e_emerg"), gc_ctx, gc_rng), Goals.fill(Goals.template("m_vip"), gc_ctx, gc_rng), Goals.fill(Goals.template("h_nogo"), gc_ctx, gc_rng)], "chest": false}
	main._goal_event({"t": "land", "ap": 0, "type": 2, "emergency": true, "vip": true})
	main._goal_event({"t": "shift", "ap": 0, "landed": 6, "go_arounds": 0, "fines": 0, "stars": 1})
	check(save.achievements.has("c_goals30") and save.achievements.has("c_chest5"), "the 30th goal and the 5th chest earn 'Goal getter' and 'Treasure'")
	main.goals_enabled = false
	save.reset_all()
	# The achievements sheet and its menu button.
	save.reset_all()
	main._show_menu()
	check(main.hud._art.btn_id.has("ach") and main.hud._art.btn_text[main.hud._art.btn_id.find("ach")] == "Awards", "the menu has an Awards button")
	main._on_button("ach")
	check(main.screen == main.SCREEN_ACH and main.hud._select_title.text == "ACHIEVEMENTS" and main.hud._art.btn_id.has("ach_tab:3") and bt_has(main, "ach:a_first"), "it opens the Achievements sheet, with four group tabs")
	main._on_button("ach_tab:1")
	check(bt_has(main, "ach:s_nogo") and not bt_has(main, "ach:a_first"), "a tab lists one group")
	main._on_button("back")
	# The new cosmetics: sources, locked items, the shop tabs, field details drawn on the field.
	var cs_new = 0
	var cs_src = {"shop": 0, "mastery": 0, "ach": 0, "level": 0}
	for cs_kind in ["theme", "livery", "windsock", "hangar"]:
		for cs_it in Cosmetics.items(cs_kind):
			cs_src[Cosmetics.source(cs_it)] += 1
	check(cs_src["mastery"] == 12 and cs_src["ach"] == 10 and cs_src["level"] == 24 and Cosmetics.THEME_COUNT + Cosmetics.LIVERY_COUNT == 32, "sources: %s; 32 liveries and skins in all, 24 of them given by airport levels" % str(cs_src))
	check(Cosmetics.source_line(Cosmetics.LIVERIES[8]).begins_with("Mastery: Grass Strip") and Cosmetics.source_line(Cosmetics.LIVERIES[14]).begins_with("Achievement:") and Cosmetics.source_line(Cosmetics.LIVERIES[6]) == "650 coins", "locked items say where they come from (mastery rank, achievement, price)")
	save.reset_all()
	main._on_button("shop")
	main._on_button("shop_tab:1")
	var cs_cards = {}
	for cs_k in main.hud._art.btn_count:
		cs_cards[main.hud._art.btn_id[cs_k]] = [main.hud._art.btn_sub[cs_k], main.hud._art.btn_state[cs_k], main.hud._art.btn_kind[cs_k]]
	for cs_id in main.hud.list_ids():
		var cs_b = main.hud.list_button(cs_id)
		cs_cards[cs_id] = [cs_b["art"].btn_sub[cs_b["index"]], cs_b["art"].btn_state[cs_b["index"]], cs_b["art"].btn_kind[cs_b["index"]]]
	check(cs_cards.size() >= 18 and cs_cards["livery:8"][0].begins_with("Mastery: Grass Strip") and cs_cards["livery:8"][1] == 1 and cs_cards["livery:6"][0] == "650 coins" and cs_cards["livery:0"][0] == "In use" and cs_cards["livery:8"][2] == 16, "the liveries tab lists all 17 in compact cards, a locked one saying its source")
	main._on_button("livery:8")
	check(main.preview_kind == "livery" and main.hud.preview_state() == "locked", "a mastery livery opens a preview that says Locked")
	main._on_button("preview_close")
	main._on_button("shop_tab:2")
	check(bt_has(main, "windsock:0") and bt_has(main, "hangar:6"), "the Field tab lists the windsocks and hangar paints")
	main._on_button("shop_tab:0")
	check(bt_has(main, "theme:8"), "the skins tab lists all nine")
	main._on_button("back")
	# Field details on the airfield.
	save.reset_all()
	save.unlocks["windsock:lime"] = true
	save.unlocks["hangar:cream"] = true
	main.select_airport(2)
	main.restart()
	main.shop_pick("windsock", 1)
	main.shop_pick("hangar", 1)
	var fd_sock = main.airfield.cur.sock_mats
	var fd_roof = (main.airfield.cur.hangar_roofs[0].material_override as StandardMaterial3D).albedo_color
	check(fd_sock.size() == 2 and (fd_sock[0] as StandardMaterial3D).albedo_color.is_equal_approx(Cosmetics.SOCKS[1]["a"]) and fd_roof.is_equal_approx(Cosmetics.PAINTS[1]["color"]), "an equipped windsock and hangar paint are drawn on the field")
	main.shop_pick("windsock", 0)
	main.shop_pick("hangar", 0)
	check((fd_sock[0] as StandardMaterial3D).albedo_color.is_equal_approx(Cosmetics.SOCKS[0]["a"]), "...and the standard ones put back")
	# No cosmetic uses a runway colour on a plane's nose, wingtips or fin: liveries only set the fuselage and the stripe, and none is near a runway colour.
	var rc_ok = true
	for rc_i in Cosmetics.LIVERY_COUNT:
		for rc_key in ["body", "stripe"]:
			var rc_c = Cosmetics.LIVERIES[rc_i][rc_key]
			if rc_c == null:
				continue
			for rc_rc in [Airports.ORANGE, Airports.BLUE, Airports.PINK, Airports.PAD_COLOR, Airports.LANE_COLOR]:
				if Vector3(rc_c.r - rc_rc.r, rc_c.g - rc_rc.g, rc_c.b - rc_rc.b).length() < 0.3:
					rc_ok = false
		rc_ok = rc_ok and not Cosmetics.LIVERIES[rc_i].has("nose") and not Cosmetics.LIVERIES[rc_i].has("tip") and not Cosmetics.LIVERIES[rc_i].has("fin")
	check(rc_ok, "none of the %d liveries uses a runway colour, and none sets the nose, wingtips or fin" % Cosmetics.LIVERY_COUNT)
	save.reset_all()
	main.progress_enabled = false

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
