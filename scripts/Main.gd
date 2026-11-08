class_name Main
extends Node3D
## Wires the game together and runs the three screens (menu -> play -> game over -> play ...).
## Restarting is IN PLACE: nothing is reloaded, created or freed; only the game state resets.

const SCREEN_MENU := 0
const TICK_PITCH := [1.0, 1.1225, 1.3348]    # G4, A4, C5 (the tick clip is G4)
const TICK_WARN := 8.0                   # seconds left (clock or aircraft timer) when the ticking starts
const SCREEN_PLAY := 1
const SCREEN_OVER := 2
const SCREEN_SELECT := 3
const SCREEN_UPGRADES := 4
const SCREEN_SHOP := 5
const SCREEN_AD := 6
const SCREEN_PAUSE := 7
const SCREEN_ACH := 10           # the Achievements sheet
const SCREEN_GOALS := 9          # today's three goals, the chest and the streak
const SCREEN_DETAIL := 8         # one airport's detail screen (see open_detail)

const HEADER_DONE := "SHIFT\nCOMPLETE"

@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var airfield: Airfield = $Airfield
@onready var traffic: Traffic = $Traffic
var diorama: Diorama
var _shake_left := 0.0
var _audio_hold := false                 # the page went to the background: sound is held until the player taps Resume
var _page_hidden := false
var _poll_t := 0.0
var _coin_step := 0
var _coin_last_ms := -10000
var _tick_next := 0.0                    # run time of the next timer tick
var _shake_dur := 0.3
var _shake_mag := 0.0
var shake_offset := Vector2.ZERO          # the camera's current shake (world units)
@onready var ribbons: PathRibbons = $Ribbons
var clouds: CloudShadows
@onready var fx: Fx = $Fx
@onready var overlay: Overlay = $Overlay
@onready var hud: Hud = $Hud

var tune_panel: TunePanel
var screen := SCREEN_MENU
var alive := false
var airport := 0                      # the airport being played
var shift := Shift.new()
var wind := Wind.new()
var rng_env := RandomNumberGenerator.new()   # wind, weather and storms (seeded for the daily shift)
var weather := Weather.new()
var log_go_arounds := true               # print the go-around cancel rate after every shift (the sims switch it off)
var last_go_around_log := ""
var score := 0                        # aircraft landed this shift (the big number)
var _event_key := ""
var no_engines := false                 # the "No engines" challenge is on for this shift (see Tuning.no_engines_pay_mult)
var force_no_engines := false           # (the simulations)
var bad_mode := false                 # Bad Pilot Day (also a seeded daily-style shift: daily_mode is true too)
var daily_mode := false               # playing today's seeded daily shift
var shop_tab := 0                     # 0 themes, 1 liveries
var _ad_kind := ""
var _ad_left := 0.0
var _ad_done: Callable
var _results_ad_used := false        # on the results, one rewarded offer (double coins OR refund) per shift
var _paid_payout := 0                 # the payout already credited this shift (a refund only adds the difference)
var _slider_drag := -1                # pause menu: the volume slider being dragged
var _pause_since_ms := 0
var _last_land_t := -100.0            # run time of the previous landing (quick-succession bonus)
var sfx: Sfx
var light: LightOverlay            # the warm / cool light over the field (see LightOverlay)
var _finale := 0                      # 0 spawning, 1 'LAST ARRIVALS' banner, 2 'CLEAR THE SKY' counter
var _finale_start := 0.0
var _last_over := -1
var _last_wind_deg := -1.0
var _doubled := false                 # the rewarded "double coins" is once per shift
var ads_shown := 0                    # (tests) how many fake ads have played
var streak := 0                       # landings in a row, each within Tuning.streak_window_seconds of the last
var last_result := {}                 # what the last shift ended with (header, reason, coins, stars...)
var over_reason := ""
var over_header := ""
var new_best := false
var elapsed := 0.0                    # seconds into this run

var _warming := false
var _warmed := false
var _death_ms := 0
var _haptic_warmed := false
var _env: Environment
var view_size := 10.0                 # world units across the screen width (the radar upgrade widens it, smoothly)
# touch
var _drag_index := -1
var _drag_plane: Aircraft = null
var _drag_active := false
var _smooth_buf := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _smooth_count := 0
var _touch_start := Vector2.ZERO
var _touch_ms := 0
var _last_world := Vector2.ZERO


func _ready() -> void:
	Boot.mark("main: children ready")
	_offline = _offline_now()               # (what the parked planes earned while the game was closed: read before anything writes the save)
	Save.touch()
	if DebugFlags.perf_enabled():
		Tuning.menu_log_all = true
		if OS.has_feature("web"):          # (the web checks end a shift on demand)
			_end_cb = JavaScriptBridge.create_callback(func(_a): _end_shift())
			JavaScriptBridge.get_interface("window").__endShift = _end_cb
		process_priority = -1000                  # (first of the frame's _process calls, and the probe last: the game's own code, timed)
		var probe := Node.new()
		probe.process_priority = 1000
		probe.set_script(load("res://scripts/FrameProbe.gd"))
		probe.main = self
		add_child(probe)
	# The engine holds every frame's delta to max_physics_steps_per_frame / physics_ticks_per_second: 3 / 60 = 1/20 s. The game runs at real
	# speed down to 20 fps and only below that in slow motion (so a tab-switch spike is never simulated). With 1 step the clamp was 1/60 s
	# and anything under 60 fps ran in slow motion. (There is no physics here, so the extra steps cost nothing and nothing catches up.)
	Engine.max_physics_steps_per_frame = 3
	view_size = Tuning.view_size()
	_setup_environment()
	sun.look_at_from_position(Vector3.ZERO, Vector3(0.3, -0.8, -0.5))
	sun.shadow_enabled = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.1
	camera.far = 100.0
	_update_camera()
	overlay.traffic = traffic
	overlay.wind = wind
	overlay.airfield = airfield
	traffic.wind = wind
	airfield.wind = wind
	airfield.traffic = traffic
	wind.warned.connect(_on_wind_warned)
	wind.shifted.connect(_on_wind_shifted)
	traffic.inactive_end.connect(_on_inactive_end)
	traffic.rerouted.connect(_on_rerouted)
	traffic.crashed.connect(_on_crashed)
	traffic.go_around.connect(_on_go_around)
	traffic.go_around_warned.connect(func(_p, _r): sfx.play("rev"))
	hud.star_reached.connect(_on_star_reached)
	hud.coin_arrived.connect(_on_coin_arrived)
	hud.transition_started.connect(func(_d: int): if not _warming: sfx.play("whoosh"))
	hud.unlock_shown.connect(func(): sfx.play("unlock"))
	hud.confetti_started.connect(func(): sfx.play("unlock"))
	hud.star_slam.connect(_on_star_slam)
	hud.sheet_pressed.connect(_on_sheet_pressed)
	hud.sheet_tapped.connect(_on_sheet_tapped)
	traffic.refused.connect(_on_refused)
	wind.reopened.connect(_on_runway_reopened)
	weather.warned.connect(_on_weather_warned)
	weather.started.connect(_on_weather_started)
	weather.ended.connect(_on_weather_ended)
	traffic.appeared.connect(_on_appeared)
	ribbons.traffic = traffic
	clouds = CloudShadows.new()
	clouds.wind = wind
	add_child(clouds)
	Boot.mark("main: wiring, cloud shadows")
	diorama = Diorama.new()
	diorama.wind = wind
	add_child(diorama)
	Boot.mark("main: diorama")
	overlay.camera = camera
	light = LightOverlay.new()
	add_child(light)
	traffic.landed.connect(_on_landed)
	traffic.spawned.connect(func(_p: Aircraft): sfx.play("arrive"))      # (a very soft tone, on the beat)
	traffic.touchdown.connect(_on_touchdown)
	traffic.conflict.connect(_on_conflict)
	traffic.timed_out.connect(_on_timed_out)
	traffic.cleared.connect(_on_cleared)
	traffic.snapped.connect(_on_snapped)
	traffic.wrong_runway.connect(_on_wrong_runway)
	airport = Save.selected_airport if Save.airport_open(Save.selected_airport) else 0
	Airports.current = airport
	airfield.select(airport)
	traffic.load_terrain()
	Boot.mark("main: select airport, terrain")
	shift.reset(Tuning.star_thresholds(), Tuning.landing_keep_fraction)
	wind.start(rng_env)
	airfield.show_active(wind)
	hud.set_wind(wind.from_deg, wind.toward_deg())
	airfield.show_upgrades()
	apply_cosmetics()
	_apply_volumes()
	Boot.mark("main: shift, wind, upgrades, cosmetics")
	sfx = Sfx.new()
	add_child(sfx)
	Boot.mark("main: sounds loaded")
	rng_env.randomize()
	hud.set_best(Save.best_for(airport))
	if DebugFlags.tune_enabled():
		tune_panel = TunePanel.new()
		add_child(tune_panel)
		tune_panel.build()
		tune_panel.changed.connect(func(_p: String): pass)
	if not _warmed:
		_warmed = true
		if DebugFlags.prewarm_enabled():
			_prewarm()
	if not _warming:
		_boot_to_menu()
	if not _warming and tune_panel:
		tune_panel.set_available(true)

## While the menu (or any screen but a shift) is up, the airports that are not built yet are built in the background (unlocked ones
## first): once the screen has been up for IDLE_BUILD_AFTER_MS, one airport at a time, a few statements between frames, never more than
## `Airfield.budget_us` (3 ms) of any frame (see Airfield._slice). A shift pauses the build. The player picking an airport that is not
## built yet gets a short loading state on its card (`request_airport`), and the build takes more of each frame until it is there.
const IDLE_BUILD_AFTER_MS := 2000
var _idle_since_ms := 0
var _idle_transitions := 0
var wanted_airport := -1               # an airport the player picked that is still being built
# The airport detail screen: the live airport in the top two thirds (zoomed out to fit), pinch to zoom and drag to pan, it eases back when let go.
const DETAIL_SPLIT := 0.38            # the field fills the top 46% of the detail screen; the airport's card (level, unlock, objectives, mastery, goals) the rest
const DETAIL_FACTOR := 1.5 * 0.667 / DETAIL_SPLIT      # the camera's size on the detail screen, x the shift's (so the whole field fits above the card)
const DETAIL_ZOOM_MIN := 0.45         # how far a pinch zooms in (x the default size)...
const DETAIL_ZOOM_MAX := 1.12         # ...and out
var detail_airport := -1
var detail_tab := 0                    # the detail screen's tab: 0 stars, 1 improvements
var imp_selected := ""                # the Improve sheet's selected row (shows what the next level changes)
var _imp_hold_t := 0.0
var _imp_hold_id := ""
var _wanted_detail := false           # the airport being built is for its detail screen (not to be selected)
var detail_t := 0.0                    # 0 = the shift's view, 1 = the detail screen's
var detail_zoom := 1.0
var detail_pan := Vector2.ZERO         # the view's centre, in world units from the default
var _press_pos := Vector2.ZERO               # where the finger went down on a button (a drag that scrolls a list is not a tap)
var _dt_touch := {}                    # finger index -> position, for fingers down on the live view
var _dt_dist := 0.0
func _idle_build() -> void:
	var busy := _warming or screen == SCREEN_PLAY or screen == SCREEN_PAUSE or hud.logo_active()
	airfield.bg_paused = busy
	if busy:
		_idle_since_ms = 0
		return
	var now := Time.get_ticks_msec()
	if _idle_since_ms == 0 or hud.transition_count != _idle_transitions or _touch_ms > _idle_since_ms:
		_idle_since_ms = now          # (a screen change or a touch starts the wait again)
		_idle_transitions = hud.transition_count
	if wanted_airport >= 0:
		if airfield.is_built(wanted_airport):
			var a := wanted_airport
			wanted_airport = -1
			hud.set_loading_airport(-1)
			if _wanted_detail:
				_wanted_detail = false
				open_detail(a)
			else:
				select_airport(a)
				Airports.current = airport
				airfield.select(airport)
				_show_select() if screen == SCREEN_SELECT else _show_menu()
		return
	if screen == SCREEN_MENU and now - _idle_since_ms >= 600 and not hud.transitioning() and not _priming_busy:
		_prime_panels()
	if now - _idle_since_ms >= IDLE_BUILD_AFTER_MS and not airfield.background_running() and not _priming_busy:
		airfield.start_background()

## The three panels (Airports, Upgrades, Hangar) are laid out in advance while the menu sits idle, so opening one is only an animation
## of its layer (see Hud._use_panel). Quick when nothing has changed since: each just compares its data.
var _priming_busy := false
func _prime_panels() -> void:
	if _priming_busy:
		return
	_priming_busy = true
	var open := PackedByteArray()
	var stars := PackedInt32Array()
	var best := PackedInt32Array()
	for i in Airports.COUNT:
		open.append(1 if Save.airport_open(i) else 0)
		stars.append(Save.stars_of(i))
		best.append(Save.best_for(i))
	# (`priming` is on only while a panel is being laid out, never across a frame: a tap in between is a real one)
	hud.priming = true
	_mastery_for_hud()
	hud.show_select(Save.stars_total(), open, stars, best, airport, Save.no_engines_at)
	hud.priming = false
	await get_tree().process_frame
	if screen == SCREEN_MENU or _warming:
		var levels := PackedInt32Array()
		for id in Upgrades.IDS:
			levels.append(Save.upgrade_level(id))
		hud.priming = true
		hud.show_upgrades(Save.coins, levels)
		hud.priming = false
		await get_tree().process_frame
	if screen == SCREEN_MENU or _warming:
		var sh := _shop_args()
		hud.priming = true
		hud.show_list("SHOP", Save.coins, sh[0], sh[1], true)
		hud.priming = false
		await get_tree().process_frame
	if screen == SCREEN_MENU or _warming:
		hud.priming = true
		hud.show_pause(Save.sound_volume, Save.music_volume, Save.ambience_volume)
		hud.priming = false
		await get_tree().process_frame
	if screen == SCREEN_MENU or _warming:
		hud.prime_results()
		await get_tree().process_frame
	_priming_busy = false

## The player picked airport `i`: if its scenery is built, go there; if not, show a loading state on its card and carry on when it is.
func request_airport(i: int) -> bool:
	if airfield.is_built(i):
		return true
	wanted_airport = i
	hud.set_loading_airport(i)
	airfield.hurry(i)
	return false

## First-use stutter fix: GL shaders / particle buffers / font glyphs set themselves up the first time
## they are used. So at boot, behind a splash, draw EVERYTHING for real (every plane, flashing; paths,
## rings, ripples, bursts, popups, every screen's text, the tuning panel) and KEEP drawing until frame
## times settle (Tuning.prewarm_*). Then hide it all. Runs once per session. Skip with ?noprewarm.
func _prewarm() -> void:
	_warming = true
	hud.begin_prewarm()
	airfield.show_all(true)
	wind.closed_left[0] = 30.0
	traffic.fog_amount = 0.6
	traffic.add_storm(Vector2(-2.5, -4.0), 1.5, Vector2.ZERO)
	hud.set_event_banner("Fog rolling in 0123456789", true)
	traffic.prewarm_show()
	diorama.prewarm(true)
	overlay.prewarm()
	if tune_panel:
		tune_panel.prewarm_show(true)
	Boot.mark("prewarm: everything shown")
	var t_start := Time.get_ticks_msec()
	var t_last := t_start
	var t_refresh := -100000
	var calm_frames := 0
	while true:
		var now := Time.get_ticks_msec()
		if now - t_refresh > 350:
			t_refresh = now
			fx.prewarm(Vector2(0, 0))
			hud.prewarm_popups()
			hud.prewarm_tip()
			overlay.prewarm()
			airfield.glow(0, 0)
			airfield.glow(1, 1)
		await get_tree().process_frame
		var t := Time.get_ticks_msec()
		calm_frames = calm_frames + 1 if (t - t_last) < Tuning.prewarm_stable_ms else 0
		t_last = t
		var elapsed_s := (t - t_start) / 1000.0
		Boot.progress(0.70 + 0.26 * minf(elapsed_s / maxf(Tuning.prewarm_max_seconds * 0.6, 0.1), 1.0))
		if elapsed_s >= Tuning.prewarm_max_seconds:
			break
		if elapsed_s >= Tuning.prewarm_min_seconds and calm_frames >= Tuning.prewarm_stable_frames:
			break
	fx.clear()
	airfield.show_all(false)
	wind.reopen_all()
	traffic.fog_amount = 0.0
	traffic.load_terrain()
	hud.set_event_banner("")
	traffic.prewarm_hide()
	diorama.prewarm(false)
	overlay.clear()
	airfield.reset()
	await _prime_panels()          # (the three panels' first draw happens here, behind the cover, not on the menu)
	hud.end_prewarm()
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
	Boot.mark("prewarm: finished")
	_boot_to_menu()

## After boot: the animated logo intro (skippable), then the menu. The intro is a setting so the tests can skip it.
func _boot_to_menu() -> void:
	if Tuning.intro_logo and not DebugFlags.off("logo"):
		screen = SCREEN_MENU
		alive = false
		if not hud.logo_finished.is_connected(_show_menu):
			hud.logo_finished.connect(_show_menu)
		hud.show_logo()
	else:
		_show_menu()

## Start a fresh shift IN PLACE.
var fixed_seed := -1                # >= 0: restart() seeds every random stream from it (tools/economy_sim.gd)

func restart() -> void:
	detail_t = 0.0
	detail_zoom = 1.0
	detail_pan = Vector2.ZERO
	detail_airport = -1
	_dt_touch.clear()
	Boot.mark("shift started")
	screen = SCREEN_PLAY
	_tick_next = 0.0
	alive = true
	score = 0
	streak = 0
	elapsed = 0.0
	new_best = false
	over_reason = ""
	over_header = ""
	last_result = {}
	sim_time = 0.0
	_run_start_ms = Time.get_ticks_msec()
	_paused_total_ms = 0
	_skip_frames = 0
	_last_land_t = -100.0
	_results_ad_used = false
	_paid_payout = 0
	hangar_full_t = -1.0
	toast_results = []
	goal_go_arounds = 0
	goal_locked_run = 0
	goal_max_locked = 0
	goal_weather = false
	goal_results = []
	goal_chest = 0
	goal_streak_text = ""
	goal_streak_row = {}
	xp_this_shift = 0
	welcome_paid = 0
	_event_counted = false
	_xp_paid = 0
	_goal_xp_pending = 0
	level_ups = []
	hud.goal_note = []
	hud.goal_rows = []
	_finale = 0
	_last_over = -1
	hud.set_finale("", Color.WHITE, false)
	_slider_drag = -1
	hud.hide_pause()
	_drag_index = -1
	_drag_plane = null
	_drag_active = false
	_doubled = false
	traffic.all_students = bad_mode
	no_engines = force_no_engines or (Save.no_engines_bad if bad_mode else (not daily_mode and Save.no_engines_on(airport)))
	traffic.no_engines = no_engines
	traffic.auto_spawn = not DebugFlags.windtest_enabled()
	if DebugFlags.windtest_enabled():       # (the web check's field: just the ground, the light and the wind; no interface, no marks)
		hud.visible = false
		overlay.visible = false
	if daily_mode:
		var seed_v := (Save.today() * 2654435761) & 0x7fffffff
		if bad_mode:
			seed_v = (seed_v ^ 0x2f1d9a7) & 0x7fffffff
		traffic.rng.seed = seed_v
		rng_env.seed = seed_v ^ 0x5bd1e995
	elif fixed_seed >= 0:           # (the simulations: the same shift every time, whatever the step size)
		traffic.rng.seed = fixed_seed
		traffic.go_rng.seed = fixed_seed ^ 0x3c6ef372
		rng_env.seed = fixed_seed ^ 0x5bd1e995
	else:
		traffic.rng.randomize()
		rng_env.randomize()
	traffic.grace_until = 0.0
	_note_event("shift started")
	get_tree().paused = false
	Airports.current = airport
	Tuning.intro_active = not daily_mode and Save.airport_plays[airport] == 0
	traffic.beats = [] if daily_mode else Tuning.profile()["beats"]
	airfield.select(airport)
	traffic.load_terrain()
	shift.reset(_thresholds(), Tuning.landing_keep_fraction)
	fx.clear()
	overlay.clear()
	airfield.reset()
	airfield.ramp_begin()
	_set_day(0.4 if bad_mode else 0.0)
	traffic.half_w = view_size * 0.5
	traffic.half_h = _half_height()
	traffic.release_all()
	traffic.spawn_until = Tuning.spawn_stop_eff()
	wind.start(rng_env)
	_last_wind_deg = wind.from_deg      # (a new shift's starting wind is not a "shift": no chime)
	weather.start()
	_event_key = ""
	airfield.show_active(wind)
	hud.mode = "bad" if bad_mode else ("daily" if daily_mode else "")
	hud.reset_for_run(Save.best_for(airport))
	if no_engines:
		hud.post_banner("No engines: no go-arounds, \u00d7%s pay" % str(snappedf(Tuning.no_engines_pay_mult, 0.1)), Color(1.0, 0.8, 0.3), "glider", 3.4)
	hud.set_wind(wind.from_deg, wind.toward_deg())
	hud.set_shift(shift)

## What the daily goals need to know about the player: the open airports, what they spawn, their weather, ordinary shift sizes.
func goals_ctx(ap: int = -1) -> Dictionary:
	var a := airport if ap < 0 else ap
	var open: Array = []
	var types := {}
	var weather := {}
	var typical := {}
	var t2 := {}
	var noeng := false
	for i in Airports.COUNT:
		if not Save.airport_open(i):
			continue
		open.append(i)
		types[i] = Airports.mix(i).keys()
		weather[i] = not (Airports.def(i)["weather"] as Array).is_empty()
		typical[i] = minf(float(Goals.TYPICAL_LANDINGS[i]), maxf(float(Save.stats.get("ema_land_%d" % i, Goals.TYPICAL_LANDINGS[i] * 100)) / 100.0, 2.0))
		t2[i] = Tuning.profile(i)["stars"][1]
		if Save.no_engines_on(i) and (types[i] as Array).has(Aircraft.Type.GLIDER):
			noeng = true
	if Save.no_engines_bad:
		noeng = true
	return {"ap": a, "open": [a], "types": types, "weather": weather, "typical": typical, "t2": t2, "noeng": noeng, "unit": Goals.unit_for([a], Tuning.goal_unit)}

## A landing or the end of a shift happened: the goals move along, and what they pay is credited (and noted for the results card).
func _goal_event(ev: Dictionary) -> void:
	if not goals_enabled:
		return
	var ctx := goals_ctx()
	var r := Save.goal_event(ev, ctx)
	if r["finished"].is_empty():
		return
	for f in r["finished"]:
		var g: Dictionary = Save.goals["list"][f["i"]]
		_goal_xp_pending += int(Progression.XP_GOAL[clampi(int(g["tier"]), 0, 2)])
		goal_results.append({"text": Goals.text(g, Airports.airport_name(maxi(int(g["ap"]), 0))), "reward": int(f["reward"]), "tier": int(g["tier"])})
		if screen == SCREEN_PLAY:
			hud.popup("Goal done!  +%d" % int(f["reward"]), Color(1.0, 0.85, 0.3), Vector2(get_viewport().get_visible_rect().size.x * 0.5, get_viewport().get_visible_rect().size.y * 0.3))
	goal_chest += int(r["chest"])
	goal_coins_total += int(r["coins"])
	Save.stat_add("goals_done", (r["finished"] as Array).size())
	if int(r["chest"]) > 0:
		Save.stat_add("chests")
	_check_achievements()
	if not (r["streak"] as Dictionary).is_empty():
		goal_streak_text = _streak_text(r)
		var srow := {"glyph": "flame", "text": "Day %d of the streak" % int((r["streak"] as Dictionary)["pos"]), "coins": int(r["streak_coins"])}
		if r["cosmetic"] != "":
			srow["text"] += "  \u00b7  new: " + str(r["cosmetic"]).split(":")[1].capitalize()
		goal_streak_row = srow
	hud.goal_note = goal_results
	hud.goal_rows = _extra_rows(false)
	Save.write_file()

## The results card's rows beyond the goals: the streak day, the bonus chest and (when `with_toasts`) the achievements and ranks of the shift. Each is {"glyph", "text", "coins"}.
func _extra_rows(with_toasts: bool) -> Array:
	var rows: Array = []
	if goal_streak_row.size() > 0:
		rows.append(goal_streak_row)
	if welcome_paid > 0:
		rows.append({"glyph": "star", "text": "Welcome bonus", "coins": welcome_paid})
	if goal_chest > 0:
		rows.append({"glyph": "star", "text": "Bonus chest", "coins": goal_chest})
	if with_toasts:
		rows.append_array(toast_results)
	return rows

func _streak_text(r: Dictionary) -> String:
	var sr: Dictionary = r["streak"]
	var t := "Day %d of the streak" % int(sr["pos"])
	if r["cosmetic"] != "":
		t += "  +" + str(r["cosmetic"]).split(":")[1].capitalize()
	elif int(r["streak_coins"]) > 0:
		t += "  +%d" % int(r["streak_coins"])
	return t

## The menu's goals card: how many goals are done today and the streak line.
func _goals_for_hud() -> void:
	Save.ensure_goals(goals_ctx())
	hud.goals_done = Goals.done_count(Save.goals)
	hud.goals_line = _streak_line()

func _streak_line() -> String:
	var ss := Goals.streak_state(Save.goal_streak, Save.today())
	var t := ""
	if int(ss["count"]) <= 0:
		t = "No streak yet"
	elif ss["done_today"]:
		t = "Streak: day %d done" % ((int(ss["count"]) - 1) % Goals.STREAK_LEN + 1)
	else:
		t = "Streak: day %d today" % (int(ss["next_pos"]))
	if int(ss["freezes"]) > 0:
		t += "  \u00b7  %d freeze%s" % [int(ss["freezes"]), "" if int(ss["freezes"]) == 1 else "s"]
	return t

## The privacy policy page, served next to the game (docs/ios.md has the same address for the store listing). On the web it opens beside the game
## (a relative address: it follows wherever the game is hosted), on a phone in the browser.
const PRIVACY_URL := "https://hotshotted.github.io/Pattern-Control/privacy.html"
var privacy_opened := 0                 # (how many times it was opened: the tests read it)

func open_privacy_policy() -> void:
	privacy_opened += 1
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('privacy.html', '_blank')")
	else:
		OS.shell_open(PRIVACY_URL)

## The Achievements sheet, one group at a time.
func _show_achievements() -> void:
	screen = SCREEN_ACH
	alive = false
	var st := Save.ach_stats()
	var items: Array = []
	for a in Achievements.in_group(ach_tab):
		var done := Save.achievements.has(a["id"])
		var pr := Achievements.progress(a, st)
		var sub: String = a["text"]
		if done:
			sub += "  \u00b7  done"
		elif a.has("ge") and int(a["ge"]) > 1:
			sub += "  \u00b7  %d / %d" % [pr["value"], pr["target"]]
		if a.get("cos", "") != "":
			sub += "  \u00b7  + " + _cosmetic_name(a["cos"])
		items.append({"id": a["id"], "name": a["name"], "sub": sub, "coins": int(a["coins"]), "size": int(a["s"]), "done": done})
	Save.stats["ach_seen"] = Save.achievements.size()
	hud.show_achievements({"tabs": Achievements.GROUP_NAMES, "tab": ach_tab, "items": items, "coins": Save.coins, "done": Save.achievements.size()})

## The goals sheet.
func _show_goals() -> void:
	screen = SCREEN_GOALS
	alive = false
	var ctx := goals_ctx()
	Save.ensure_goals(ctx)
	var items: Array = []
	for i in (Save.goals["list"] as Array).size():
		var g: Dictionary = Save.goals["list"][i]
		var sub: String = "%s  \u00b7  %s" % [Goals.TIER_NAMES[int(g["tier"])], Goals.progress_text(g)] if not Goals.progress_text(g).is_empty() else Goals.TIER_NAMES[int(g["tier"])]
		items.append({"text": Goals.text(g, Airports.airport_name(maxi(int(g["ap"]), 0))), "sub": sub, "reward": int(g["reward"]), "tier": int(g["tier"]), "done": bool(g["done"]), "can_reroll": not bool(g["done"]) and not bool(g["rr"])})
	var ss := Goals.streak_state(Save.goal_streak, Save.today())
	var week_pos := (int(ss["count"]) - 1) % Goals.STREAK_LEN + 1 if int(ss["count"]) > 0 else 0
	if int(ss["count"]) > 0 and not ss["done_today"]:
		week_pos = int(ss["count"]) % Goals.STREAK_LEN if int(ss["count"]) % Goals.STREAK_LEN != 0 else 0
	var nxt := Goals.day_reward(int(ss["next_pos"]), int(ss["count"]) + (0 if ss["done_today"] else 1), int(ctx["unit"]))
	hud.show_goals({"items": items, "chest": Goals.chest_for(int(ctx["unit"])), "chest_done": bool(Save.goals.get("chest", false)),
		"streak_title": "Streak", "streak_sub": "%s  \u00b7  next: %s" % [_streak_line().replace("Streak: ", ""), ("a free cosmetic" if nxt["cosmetic"] else "+%d coins" % int(nxt["coins"]))],
		"week_pos": week_pos, "coins": Save.coins})

func reroll_goal(i: int) -> bool:
	var ok := Save.reroll_goal(i, goals_ctx())
	if ok:
		Save.write_file()
		_show_goals()
	return ok

# ---------- Mastery, achievements and their toasts ----------

## A landing: the airport's mastery, and the counters the achievements read.
func _on_progress_landing(p: Aircraft) -> void:
	var r := Save.add_mastery_landing(airport, Goals.AVG_PAY[clampi(airport, 0, 5)])
	for rank in r["ranks"]:
		var line := "%s: rank %d, %s  +%d" % [Airports.airport_name(airport), rank, Mastery.rank_name(rank), Mastery.coins_for(airport, rank, Goals.AVG_PAY[clampi(airport, 0, 5)])]
		var cid := Mastery.cosmetic_for(airport, rank)
		if cid != "":
			line += "  \u00b7  new: " + _cosmetic_name(cid)
		var mtxt := "%s rank %d: %s" % [Airports.airport_name(airport), rank, Mastery.rank_name(rank)]
		if cid != "":
			mtxt += "  \u00b7  new: " + _cosmetic_name(cid)
		_toast(line, Color(0.55, 0.85, 1.0), {"glyph": "airport", "text": mtxt, "coins": Mastery.coins_for(airport, rank, Goals.AVG_PAY[clampi(airport, 0, 5)])})
		if rank >= Mastery.MAX_RANK:
			airfield.show_mastery()
	if p.emergency:
		Save.stat_add("emergencies")
	Save.stat_max("quick_best", streak)
	Save.stat_max("locked_best", goal_locked_run)
	if no_engines and p.type == Aircraft.Type.GLIDER:
		Save.stat_add("noeng_landings")
		if airport == 5:
			Save.stat_add("noeng_intl")
	if hangar_full_t < 0.0 and shift.landed >= Ramp.star_landings():
		hangar_full_t = traffic.run_time
		if hangar_full_t < float(Save.stats.get("fast_hangar", 9999)):
			Save.stats["fast_hangar"] = int(ceil(hangar_full_t))
	_check_achievements()

## The shift is over: its counters.
func _on_progress_shift_end() -> void:
	Save.stat_add("shifts")
	if goal_go_arounds == 0 and shift.landed >= 4:
		Save.stat_add("nogo_shifts")
	if shift.fines == 0 and shift.landed >= 6:
		Save.stat_add("clean_shifts")
	if shift.stars() >= 3:
		Save.stat_add("three_star_shifts")
	Save.stat_max("net_best", shift.balance())
	if goal_weather and shift.stars() >= 1:
		Save.stat_add("weather_shifts")
	if bad_mode and shift.stars() >= 1:
		Save.stat_add("bad_stars")
	_check_achievements()

## Pay and announce any achievement that has just been met (several can follow each other: a cosmetic can complete a collection).
func _check_achievements() -> void:
	if not progress_enabled:
		return
	for guard in 4:
		var got := Save.check_achievements()
		if got.is_empty():
			return
		for g in got:
			var a := Achievements.def(g["id"])
			var line := "Achievement: %s  +%d" % [a["name"], int(g["coins"])]
			if g["cosmetic"] != "":
				line += "  \u00b7  new: " + _cosmetic_name(g["cosmetic"])
			var rtxt: String = "Achievement: %s" % a["name"]
			if g["cosmetic"] != "":
				rtxt += "  \u00b7  new: " + _cosmetic_name(g["cosmetic"])
			_toast(line, Color(1.0, 0.85, 0.3), {"glyph": "star", "text": rtxt, "coins": int(g["coins"])})

func _cosmetic_name(cid: String) -> String:
	var kind := cid.get_slice(":", 0)
	var id := cid.get_slice(":", 1)
	return str(Cosmetics.items(kind)[Cosmetics.index_of(kind, id)]["name"])

## Queue a toast; it shows at the next calm moment (see _tick_toasts), or on the results card.
func _toast(text: String, color: Color, row: Dictionary = {}) -> void:
	toast_queue.append({"text": text, "color": color})
	toast_results.append(row if not row.is_empty() else {"glyph": "star", "text": text, "coins": 0})

## In a shift a toast waits until no path is being drawn and nothing is about to happen (no alert, no go-around signalled); a few seconds apart.
func _tick_toasts(delta: float) -> void:
	_toast_gap = maxf(_toast_gap - delta, 0.0)
	if toast_queue.is_empty() or screen != SCREEN_PLAY or _toast_gap > 0.0:
		return
	if _drag_plane != null or _drag_active or traffic.go_around_pending_any():
		return
	var worst := 0.0
	for p in traffic.planes:
		if p.active():
			worst = maxf(worst, p.warn)
	if worst > 0.3:
		return
	var t: Dictionary = toast_queue.pop_front()
	hud.post_banner(t["text"], t["color"], "star", 3.2)
	_toast_gap = 3.4

## What the parked planes earned since the game was last played: the hangars and the average pay of every airport, from the game's own numbers.
func _offline_now() -> Dictionary:
	var caps := []
	var pays := []
	for a in Airports.COUNT:
		caps.append(Ramp.capacity(a))
		pays.append(Ramp.mean_pay(a))
	return Save.offline_pending(caps, pays)

var _offline := {"total": 0}                  # the offline income waiting to be collected (the tally screen)
var _tally: Tally = null

## The welcome-back screen over the menu, once, if the planes earned something while the game was closed.
func _maybe_tally() -> void:
	if int(_offline.get("total", 0)) <= 0 or _tally != null:
		return
	var lines := []
	for a in (_offline["per"] as Dictionary):
		lines.append([Airports.airport_name(int(a)), int((_offline["per"] as Dictionary)[a])])
	_tally = Tally.new()
	_tally.art_factory = func() -> Control: return hud.Art.new()
	hud.add_child(_tally)
	_tally.build({"total": _offline["total"], "hours": _offline["hours"], "lines": lines}, get_viewport().get_visible_rect().size, Style.safe_bottom)
	_tally.collected.connect(_collect_tally)

func _collect_tally() -> void:
	if _tally == null:
		return
	var total := int(_offline.get("total", 0))
	_offline = {"total": 0}
	Save.add_coins(total)
	Save.stats["offline_coins"] = int(Save.stats.get("offline_coins", 0)) + total
	Save.touch()
	Save.write_file()
	_tally.queue_free()
	_tally = null
	sfx.play("buy")
	hud.flash(Color(0.6, 1.0, 0.7))
	if screen == SCREEN_MENU:
		_show_menu()

func _maybe_tally_later() -> void:
	if int(_offline.get("total", 0)) > 0 and _tally == null:
		_later(2, _maybe_tally)

func tally_active() -> bool:
	return _tally != null

func _show_menu() -> void:
	preview_kind = ""
	Boot.mark("menu shown")
	if _menu_first_ms == 0:
		_menu_first_ms = Time.get_ticks_msec()
	screen = SCREEN_MENU
	alive = false
	daily_mode = false
	bad_mode = false
	hud.mode = ""
	_goals_for_hud()
	_check_achievements()
	_maybe_tally_later()
	hud.ach_unseen = Save.achievements.size() > int(Save.stats.get("ach_seen", 0))
	hud.bad_streak = Save.daily_streak("bad")
	hud.bad_done = Save.daily_done_today("bad")
	airfield.progress = -1.0
	_set_day(0.0)
	var sm_t0 := Time.get_ticks_usec()
	hud.show_menu(Airports.airport_name(airport), Save.coins, Save.stars_total(), Save.best_for(airport), Airports.tag(airport), Save.stars_of(airport), Save.no_engines_bad)
	Boot.add("hud.show_menu", float(Time.get_ticks_usec() - sm_t0) / 1000.0)

# ---------- Frame time: the simulation can never run ahead of the clock ----------
# However long the real frame was, the simulation advances by at most Tuning.max_frame_delta; a stall (a tab
# switch, a long hitch) is dropped, not simulated; and a couple of frames are skipped after a stall or the
# window coming back, so nothing catches up. ?perf logs every frame over 50 ms and what was going on.

var _skip_frames := 0
var _suspended := false
var _event := ""
var _event_frame := -100
var sim_time := 0.0
var _run_start_ms := 0
var _paused_since_ms := 0
var _paused_total_ms := 0

func _note_event(what: String) -> void:
	_event = what
	_event_frame = Engine.get_process_frames()

func _frame_delta(raw: float) -> float:
	var used := 0.0
	var why := ""
	if _suspended:
		why = "window in the background"
	elif _skip_frames > 0:
		_skip_frames -= 1
		why = "skipped (resuming)"
	elif raw > Tuning.stall_delta:
		_skip_frames = Tuning.resume_skip_frames
		why = "stall dropped"
	else:
		used = minf(raw, Tuning.max_frame_delta)
		why = "clamped" if raw > Tuning.max_frame_delta else ""
	if raw > 0.05 and DebugFlags.perf_enabled():
		hud.note_hitch(raw, used, why, _hitch_context())
	return used

func _hitch_context() -> String:
	var parts: Array[String] = []
	if Engine.get_process_frames() - _event_frame <= 4 and _event != "":
		parts.append(_event)
	parts.append("%d plane(s)" % traffic.active_count())
	return ", ".join(parts)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if sfx != null:
				_background()     # silence everything (held until the player taps Resume); pauses a shift in progress
			if screen == SCREEN_PLAY and alive and not _warming:
				pause_game()      # losing focus pauses the shift: it is waiting behind the pause menu when you come back
			if not _suspended:
				_suspended = true
				_paused_since_ms = Time.get_ticks_msec()
				_note_event("window went to the background")
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if sfx != null:
				_foreground()
			if _suspended:
				_suspended = false
				_paused_total_ms += Time.get_ticks_msec() - _paused_since_ms
				_skip_frames = Tuning.resume_skip_frames
				_cancel_drag()
				_note_event("window came back")

func run_wall_time() -> float:
	return maxf((Time.get_ticks_msec() - _run_start_ms - _paused_total_ms) / 1000.0, 0.0)

# ---------- Background audio ----------

## The page was hidden, blurred or the phone locked: silence everything, and pause a shift in progress. Nothing resumes by
## itself: the player has to come back to the page and tap Resume (or, from the menu, tap anywhere).
func _background() -> void:
	_page_hidden = true
	if not _audio_hold:
		_audio_hold = true
		sfx.hold()
	if screen == SCREEN_PLAY and alive and not _warming:
		pause_game()
	_publish_state()

func _foreground() -> void:
	_page_hidden = false
	_publish_state()

## The player is back and has tapped (Resume, or any tap on a menu): sound may run again.
func _release_audio() -> void:
	if _page_hidden:
		return
	if _audio_hold:
		_audio_hold = false
		sfx.release()
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__pwRelease && window.__pwRelease()")
	_publish_state()

## Web: the page tells us about visibility too (a hidden tab, a locked phone) in case the engine's own focus
## notifications do not arrive; and we publish our state for the automated audio check.
func _poll_page(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_poll_t += delta
	if _poll_t < 0.25:
		return
	_poll_t = 0.0
	var hidden := bool(JavaScriptBridge.eval("!!window.__pwHidden"))
	if hidden and not _page_hidden:
		_background()
	elif not hidden and _page_hidden:
		_foreground()

func _publish_state() -> void:
	if not OS.has_feature("web"):
		return
	var rx := 195.0
	var ry := 311.0
	for k in hud._art.btn_count:
		if hud._art.btn_id[k] == "resume":
			var vp := get_viewport().get_visible_rect().size
			var css_w := float(JavaScriptBridge.eval("window.innerWidth"))
			var sc := css_w / vp.x
			var c: Vector2 = hud._art.btn_rect[k].get_center()
			rx = c.x * sc
			ry = c.y * sc
	JavaScriptBridge.eval("window.__pw = {paused: %s, muted: %s, held: %s, resume: [%.1f, %.1f]}" % [str(screen == SCREEN_PAUSE).to_lower(), str(AudioServer.is_bus_mute(0)).to_lower(), str(_audio_hold).to_lower(), rx, ry])

## ?perf on the web: how long the game's own code (every _process, no rendering) took per frame, in blocks of 30 frames
## (`window.__procs` = [[mean ms, worst ms, frames over 33 ms], ...]): the web check reads it, since the frame times of a headless
## browser are those of its software renderer, not of the game.
var _proc_n := 0
var _proc_sum := 0.0
var _proc_max := 0.0
var _proc_over := 0
var _probe_t0 := 0
var _end_cb: JavaScriptObject
var _menu_first_ms := 0
var _frame_last_us := 0
var menu_worst_script := 0.0          # the slowest frame of the game's own code on the menu in its first 20 s (ms)
var menu_hitches := 0
## ?perf: every menu frame over 33 ms in the first 20 s, with what ran in it (the build of another airport, the pre-warm, audio, the
## interface), to the console and, on the web, `window.__menu` (the web boot check reads it). `script_ms` is the game's own code in the
## frame (first _process to last); `wall` is the frame as the browser saw it.
func _log_menu_frame(script_ms: float) -> void:
	# (the background build runs as the frame starts, before the first _process, and the interface's canvas is redrawn after the last one:
	# both are ours and both are part of the frame)
	script_ms += float(Boot.frame_spans.get("airport build (background)", 0.0)) + float(Boot.frame_spans.get("interface art redraw", 0.0))
	var now := Time.get_ticks_usec()
	var wall := float(now - _frame_last_us) / 1000.0 if _frame_last_us > 0 else 0.0
	_frame_last_us = now
	if _menu_first_ms == 0:
		Boot.frame_spans.clear()
		return
	var since := float(Time.get_ticks_msec() - _menu_first_ms) / 1000.0
	if since <= 20.0 or Tuning.menu_log_all:
		menu_worst_script = maxf(menu_worst_script, script_ms)
		if script_ms > 33.0 or wall > 33.0:
			menu_hitches += 1
			var parts: Array[String] = []
			for k in Boot.frame_spans:
				parts.append("%s %.1f ms" % [k, Boot.frame_spans[k]])
			var what := ", ".join(parts) if not parts.is_empty() else "nothing of ours"
			print("[menu-hitch] t=%.1fs wall %.0f ms, our code %.1f ms: %s" % [since, wall, script_ms, what])
			if OS.has_feature("web"):
				JavaScriptBridge.eval("(window.__menu = window.__menu || []).push([%.2f, %.1f, %.2f, %s, performance.now()])" % [since, wall, script_ms, JSON.stringify(what)])
	Boot.frame_spans.clear()

func _log_process_time(ms: float) -> void:
	_proc_n += 1
	_proc_sum += ms
	_proc_max = maxf(_proc_max, ms)
	if ms > 33.0:
		_proc_over += 1
	if _proc_n >= 30:
		JavaScriptBridge.eval("(window.__procs = window.__procs || []).push([%.2f, %.2f, %d])" % [_proc_sum / _proc_n, _proc_max, _proc_over])
		_proc_n = 0
		_proc_sum = 0.0
		_proc_max = 0.0
		_proc_over = 0

## The screen stays awake while a shift is being played, and only then (the menu, the pause menu and the results may dim and lock the phone as
## usual; project.godot turns the engine's own keep-awake off). Asked of the display server only when it changes.
var keeping_awake := false

func _update_awake() -> void:
	var want := screen == SCREEN_PLAY and alive and not _suspended
	if want != keeping_awake:
		keeping_awake = want
		DisplayServer.screen_set_keep_on(want)

func _process(raw_delta: float) -> void:
	_probe_t0 = Time.get_ticks_usec()
	_poll_page(raw_delta)
	if DebugFlags.windtest_enabled() and OS.has_feature("web") and screen == SCREEN_PLAY and alive:
		JavaScriptBridge.eval("window.__wt = {t: %.2f}" % traffic.run_time)       # (the web wind check waits for the shift to be under way)
	_tick_shake(raw_delta)
	_tick_preview(raw_delta)
	_tick_imp_hold(raw_delta)
	_idle_build()
	_update_awake()
	# Music: the shift's own while playing; the calm menu bed everywhere else; the two crossfade.
	if screen != SCREEN_PLAY and screen != SCREEN_PAUSE:
		sfx.set_music(false)
	sfx.set_menu_music(not _warming and screen != SCREEN_PLAY and screen != SCREEN_PAUSE and screen != SCREEN_AD)
	view_size = lerpf(view_size, Tuning.view_size(), 1.0 - exp(-raw_delta * 3.0))   # the radar re-frames the view smoothly
	detail_t = move_toward(detail_t, 1.0 if screen == SCREEN_DETAIL else 0.0, raw_delta / 0.4)
	if _dt_touch.is_empty():              # (let go: the view eases back to the default one)
		var back_k := 1.0 - exp(-raw_delta * 7.0)
		detail_zoom = lerpf(detail_zoom, 1.0, back_k)
		detail_pan = detail_pan.lerp(Vector2.ZERO, back_k)
	_update_camera()
	traffic.half_w = view_size * 0.5
	traffic.half_h = _half_height()
	diorama.traffic.half_w = traffic.half_w
	diorama.traffic.half_h = traffic.half_h
	diorama.active = (screen == SCREEN_MENU or screen == SCREEN_DETAIL) and not _warming
	if screen == SCREEN_AD:
		_tick_ad(raw_delta)
	if _warming or not alive or screen == SCREEN_PAUSE:
		return
	var delta := _frame_delta(raw_delta)
	if DebugFlags.perf_enabled():
		hud.set_perf_clock(sim_time, run_wall_time())
		hud.perf_extra = "draw: overlay %d us, hud %d us" % [overlay.last_draw_us, hud._art.last_draw_us]
	if delta <= 0.0:
		return
	sim_time += delta
	elapsed += delta
	step(delta)

## One simulation step (the tests call this directly). A paused shift does not advance.
func step(delta: float) -> void:
	if screen == SCREEN_PAUSE:
		return
	traffic.step(delta)
	airfield.step_taxi(delta)
	_tick_toasts(delta)
	var worst := 0.0
	for p in traffic.planes:
		if p.active():
			worst = maxf(worst, p.warn)
	hud.set_alert(alive and worst > 0.55)
	var t := traffic.run_time
	var frac := clampf(t / maxf(Tuning.spawn_stop_eff(), 1.0), 0.0, 1.0)
	hud.set_shift_fraction(frac)
	if t < Tuning.spawn_stop_eff() or weather.phase != Weather.Phase.IDLE:
		weather.step(delta, frac, rng_env, wind)
		wind.closing = weather.runway if weather.phase == Weather.Phase.WARN and weather.kind == "crosswind" else -1
		wind.closing_left = weather.left
		var key := "%d:%d" % [weather.phase, ceili(weather.left)]
		if key != _event_key:    # (the banner text is only rebuilt when the second changes)
			_event_key = key
			hud.set_event_banner(weather.banner(), weather.phase == Weather.Phase.WARN)
	if t < Tuning.spawn_stop_eff():
		wind.step(delta, frac, rng_env)
		if wind.warning:
			hud.set_wind_warning(wind.next_deg, ceili(wind.countdown))
	if wind.from_deg != _last_wind_deg:
		if _last_wind_deg >= 0.0:
			sfx.play("wind")
			if DebugFlags.wind_enabled():
				sfx.play("gust")
		_last_wind_deg = wind.from_deg
	if _drag_active and (_drag_plane == null or not _drag_plane.active()):
		_cancel_drag()
	_step_clock(t)
	_update_audio(frac)

## The shift clock, the overtime meter and the finale: spawning stops, the last arrivals come in, and the shift
## ends only when every aircraft has landed or been lost.
func _step_clock(t: float) -> void:
	var par := Tuning.par_eff()
	if t < par:
		hud.set_timer(ceili(par - t))
	else:
		var over := floori(t - par)
		hud.set_overtime(over)
		shift.set_overtime(t - par, int(Tuning.overtime_penalty_per_second))
		if over != _last_over:
			_last_over = over
			hud.set_shift(shift)
	_timer_ticks(t, par)
	if t < Tuning.spawn_stop_eff() or not alive:
		return
	var left := traffic.remaining()
	if _finale == 0:
		_finale = 1
		_finale_start = t
		sfx.play("last_arrivals")
		_note_event("last arrivals")
	elif _finale == 1 and t - _finale_start >= Tuning.last_arrivals_seconds:
		_finale = 2
		sfx.play("clear_sky")
	if _finale == 1:
		hud.set_finale("LAST ARRIVALS", Color(1.0, 0.85, 0.3), true)
	else:
		hud.set_finale("CLEAR THE SKY  %d left" % left, Color(1.0, 0.45, 0.4) if t >= par else Color(0.7, 0.95, 1.0), false)
	if left == 0:
		_end_shift()

## Timer warnings: a gentle tick that comes faster, and a little higher, the closer the shift clock or the most
## hurried aircraft is to running out (in overtime it ticks steadily and quickly).
func _timer_ticks(t: float, par: float) -> void:
	if not alive:
		return
	var urgency := par - t
	for p in traffic.planes:
		if p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD:
			if p.entered and not p.fogged:
				urgency = minf(urgency, p.timer_left)
	if urgency > TICK_WARN or t < _tick_next:
		return
	var k := clampf(urgency / TICK_WARN, 0.0, 1.0)
	sfx.play("tick", TICK_PITCH[0 if k > 0.66 else (1 if k > 0.33 else 2)])      # G, then A, then C: the ticks climb the scale as time runs out
	_tick_next = t + lerpf(0.22, 0.9, k)

## The light moves on through the shift: a warmer glow, a cooler shade, longer shadows, warmer grass (Bad Pilot Day starts 40% in).
func _set_day(t: float) -> void:
	light.set_time(t)
	airfield.set_time(t)
	traffic.shadow_scale = Shadow.offset_scale(t)

## The music's layers follow the traffic and the clock (there is no engine hum: the music is the only continuous sound).
func _update_audio(frac: float) -> void:
	airfield.progress = frac
	_set_day(0.4 + 0.6 * frac if bad_mode else frac)
	# the music follows the traffic: the rhythm guitar joins at 3 aircraft inbound, the lead at 5 or in the last 20 s (see Sfx.set_music)
	var last := _finale > 0 or Tuning.spawn_stop_eff() - traffic.run_time <= Sfx.LAST_SECS
	sfx.set_music(true, traffic.inbound_count(), last)
	sfx.set_fog(traffic.fog_amount)

# ---------- Game events ----------

## The wheels touch the runway: a puff of dust and a little pop of the aircraft.
func _on_touchdown(p: Aircraft) -> void:
	if p.tkind != Aircraft.Kind.PAD:
		fx.puff(p.pos)
		sfx.play("touch")
		sfx.play("chirp")
	# the coins leave the wheels the moment they touch and arc to the counter one by one (the counter bumps and ticks on each)
	var pay := Tuning.landing_pay(p.type) * (Tuning.student_pay_mult if p.student else 1.0)
	hud.fly_coins(overlay.world_to_screen(p.pos), clampi(roundi(pay / 8.0), 1, 5))

func _on_landed(p: Aircraft) -> void:
	if not alive:
		return
	score += 1
	var vip_paid := p.vip and p.vip_ok
	var base := Tuning.landing_pay(p.type)
	if no_engines:
		base = roundi(base * Tuning.no_engines_pay_mult)
	if p.student:
		base = roundi(base * Tuning.student_pay_mult * (Tuning.bad_day_pay_mult if bad_mode else 1.0))
	var extra := 0
	# Quick succession: landings close together earn a growing bonus.
	var t := traffic.run_time
	streak = streak + 1 if t - _last_land_t <= Tuning.streak_window_seconds else 1
	_last_land_t = t
	extra += Tuning.streak_bonus_coins * mini(streak - 1, Tuning.streak_bonus_cap)
	if p.emergency:
		extra += Tuning.emergency_bonus_coins
	elif vip_paid:
		extra += Tuning.vip_bonus_coins
	# Hangar bays: a landing that parks in one of the bays bought at this airport (beyond the break-even landings) pays a hangar fee.
	var hangar_fee := 0
	var landing_no := shift.landed + 1
	if landing_no > Ramp.star_landings() and landing_no <= Ramp.capacity():
		hangar_fee = roundi(base * Tuning.imp_hangar_fee)
		extra += hangar_fee
		if not bool(Save.stats.get("bay_seen_%d" % airport, 0)):          # the first time a plane parks in a bay bought at this airport: say so
			Save.stats["bay_seen_%d" % airport] = 1
			hud.post_banner("Your new hangar bay: it parks here instead of on the ramp, and pays a fee", Color(0.6, 1.0, 0.7), "hangar", 3.6)
	shift.on_landed(p.type, base, extra, vip_paid, p.emergency, p.student)
	goal_locked_run = goal_locked_run + 1 if p.locked else 0
	goal_max_locked = maxi(goal_max_locked, goal_locked_run)
	if progress_enabled:
		_on_progress_landing(p)
	_goal_event({"t": "land", "ap": airport, "type": p.type, "emergency": p.emergency, "vip": vip_paid, "student": p.student, "no_engines": no_engines, "streak": streak})
	var col := Airports.land_color(p.tkind, p.runway)
	var land_at := p.pos
	airfield.begin_taxi(p.type, p.tkind, p.runway, p.land_end, p.student, p.speed_class)
	sfx.play_step("landing", mini(streak - 1, Sfx.STEPS - 1))      # (landings in quick succession climb the scale)
	hud.set_landed(score, true)
	hud.set_shift(shift)
	fx.burst(land_at, col)
	fx.burst(land_at, Color.WHITE)
	fx.sparkle(land_at)
	overlay.ripple(land_at, col, 1.0)
	overlay.ripple(land_at, Color.WHITE, 0.6)
	if p.tkind == Aircraft.Kind.RUNWAY:
		airfield.glow(p.runway, p.land_end)
	var text := "+%d" % (base + extra)
	var tcol := Color(1, 1, 1)
	if streak >= 2:
		text += "  x%d" % streak
		tcol = col.lerp(Color.WHITE, 0.4)
	if p.emergency:
		text = "EMERGENCY SAVED! +%d" % (base + extra)
		tcol = Color(1.0, 0.45, 0.4)
		fx.burst(land_at, Color(1.0, 0.3, 0.25), true)
	elif p.vip:
		if vip_paid:
			text = "VIP +%d" % (base + extra)
			tcol = Color(1.0, 0.84, 0.15)
		else:
			text = "VIP +%d (no bonus)" % (base + extra)
			tcol = Color(0.7, 0.7, 0.72)
	hud.popup(text, tcol, overlay.world_to_screen(land_at) + Vector2(0, -80))
	if p.low_fuel:
		hud.popup("Low fuel", Color(1.0, 0.75, 0.3), overlay.world_to_screen(land_at) + Vector2(0, -38))
	if hangar_fee > 0:
		hud.popup("Hangar fee +%d" % hangar_fee, Color(0.75, 0.95, 1.0), overlay.world_to_screen(land_at) + Vector2(0, -118))
	_star_feedback(land_at)
	if not DebugFlags.off("haptic"):
		_vibrate(Tuning.haptic_ms, Haptics.MEDIUM)

## A star threshold was just crossed: a gold burst and a "STAR!" popup.
func _star_feedback(at: Vector2) -> void:
	if shift.just_stars == 0:
		return
	fx.burst(at, Color(1.0, 0.84, 0.15), true)
	overlay.ripple(at, Color(1.0, 0.84, 0.15), 1.6)
	var vp := get_viewport().get_visible_rect().size
	hud.popup("STAR!", Color(1.0, 0.84, 0.15), Vector2(vp.x * 0.5, vp.y * 0.3))

## A fine: coins come off the balance (it may go negative) with a red popup.
func _apply_fine(amount: int, kind: String, label: String, world_at: Vector2) -> void:
	shift.fine(amount, kind)
	sfx.play("fine")
	hud.set_shift(shift)
	hud.popup("%s  -%d" % [label, amount], Color(1.0, 0.25, 0.2), overlay.world_to_screen(world_at))
	hud.flash(Color(1.0, 0.2, 0.15))
	if not DebugFlags.off("haptic"):
		_vibrate(80, Haptics.HEAVY)

## An aircraft flew into terrain or a storm cell: lost, and a medium fine.
func _on_crashed(p: Aircraft, kind: int) -> void:
	if not alive:
		return
	fx.burst(p.pos, Color(0.85, 0.6, 0.4), true)
	overlay.ripple(p.pos, Color(1, 0.35, 0.2), 1.1)
	shake(0.2, 0.25)
	_apply_fine(Tuning.fine_amount(Tuning.fine_hazard), "crash", "Struck by storm!" if kind == 1 else ("No room to land!" if kind == 2 else ("Missed approach!" if kind == 3 else "Crashed!")), p.pos)

## A go-around: the aircraft climbs out along the runway heading and needs a new path (it keeps its timer).
func _on_go_around(p: Aircraft, reason: int) -> void:
	var why := Approach.reason_text(reason)
	goal_go_arounds += 1
	goal_locked_run = 0
	sfx.play("go_around")
	hud.popup("Go-around!" if why == "" else "Go-around!\n%s" % why, Color(1, 0.85, 0.3), overlay.world_to_screen(p.pos) + Vector2(0, -60))
	overlay.ripple(p.pos, Color(1, 0.85, 0.3), 0.7)
	if not DebugFlags.off("haptic"):
		_vibrate(30, Haptics.MEDIUM)

## A coin reaches the counter: a soft plink, each one a note higher in the key while they keep arriving.
func _on_coin_arrived() -> void:
	var now := Time.get_ticks_msec()
	_coin_step = 0 if now - _coin_last_ms > 700 else mini(_coin_step + 1, Sfx.STEPS - 1)
	_coin_last_ms = now
	sfx.play_step("coin", _coin_step)

## A star lit on the bar during a shift.
func _on_star_reached(_i: int) -> void:
	if screen != SCREEN_PLAY:
		return              # (the end of a shift lights stars too: the results card slams them in with its own sounds)
	sfx.play("star")
	if not DebugFlags.off("haptic"):
		_vibrate(20, Haptics.LIGHT)

## A results star slammed in: an impact sound that rises with each star.
func _on_star_slam(i: int) -> void:
	sfx.play("slam", 1.0 + 0.14 * i)
	shake(0.12, 0.18)
	if not DebugFlags.off("haptic"):
		_vibrate(25, Haptics.MEDIUM)

## The aircraft can't follow a path or tap (and the reason is shown where it happened).
func _on_refused(_p: Aircraft, text: String, at: Vector2) -> void:
	overlay.ripple(at, Color(1, 0.6, 0.25), 0.6)
	hud.popup(text, Color(1, 0.75, 0.35), overlay.world_to_screen(at) + Vector2(0, 90))

## First time a kind of aircraft is on screen: a one-line tip. Emergencies announce themselves every time.
const TIPS := {
	"drag": ["Drag from an aircraft to its runway", "plane"],
	"glider": ["Glider: short timer, watch the ring", "glider"],
	"heli": ["Helicopters land on the H pad", "heli"],
	"jet": ["Jets need a long runway", "jet"],
	"seaplane": ["Seaplanes land on water", "seaplane"],
	"emergency": ["Emergency: land it fast", "emergency"],
	"vip": ["VIP: don't hold it for a bonus", "vip"],
	"student": ["Student pilot: more go-arounds, 2x pay", "student"],
}

func _on_appeared(p: Aircraft) -> void:
	if p.emergency:
		hud.popup("EMERGENCY", Color(1.0, 0.3, 0.25), overlay.world_to_screen(p.pos))
	var key := ""
	if p.emergency:
		key = "emergency"
	elif p.vip:
		key = "vip"
	elif p.student:
		key = "student"
	else:
		match p.type:
			Aircraft.Type.GLIDER:
				key = "glider"
			Aircraft.Type.HELI:
				key = "heli"
			Aircraft.Type.JET:
				key = "jet"
			Aircraft.Type.SEAPLANE:
				key = "seaplane"
	if key == "" and not Save.tips_seen.has("drag"):
		key = "drag"
	if key != "" and not Save.tips_seen.has(key):
		Save.tips_seen[key] = true
		Save.write_file()
		hud.show_tip(TIPS[key][0], TIPS[key][1])

## A path snapped onto a runway's centreline and locked: a soft click, a pulse ring where it locked and a short buzz.
func _on_snapped(p: Aircraft, at: Vector2) -> void:
	var col := Airports.land_color(p.tkind, p.runway)
	overlay.ripple(at, col, 0.45)
	overlay.ripple(at, Color.WHITE, 0.3)
	sfx.play("tap")
	_vibrate(Tuning.snap_haptic_ms, Haptics.LIGHT)

## A short buzz: the browser's navigator.vibrate on the web (Godot's own call is a no-op there on some browsers), else the handheld's.
func _vibrate(ms: int, strength: float = Haptics.MEDIUM) -> void:
	if DebugFlags.off("haptic"):
		return
	Haptics.play(ms, strength)

func _on_cleared(p: Aircraft) -> void:
	overlay.ripple(Airports.land_threshold(p.tkind, p.runway, p.land_end), Airports.land_color(p.tkind, p.runway), 0.5)

func _on_wrong_runway(_p: Aircraft, runway: int) -> void:
	overlay.ripple(Airports.end_threshold(runway, 0), Color(1, 0.25, 0.2), 0.7)
	hud.popup("WRONG RUNWAY", Color(1, 0.4, 0.35), overlay.world_to_screen(Airports.rw_center(runway)) + Vector2(0, 120))

## A path reached an end the wind doesn't allow.
func _on_inactive_end(_p: Aircraft, runway: int, end: int) -> void:
	overlay.ripple(Airports.end_threshold(runway, end), Color(1, 0.6, 0.2), 0.7)
	hud.popup("Runway closed" if wind.is_closed(runway) else "Not into the wind", Color(1, 0.7, 0.3), overlay.world_to_screen(Airports.end_threshold(runway, end)) + Vector2(0, 100))

## "Wind shifting to 270" is announced about wind_warning_seconds ahead.
func _on_wind_warned(next_deg: float) -> void:
	hud.set_wind_warning(next_deg, ceili(wind.countdown))

## The wind changed: the active ends change, and aircraft cleared for a closed end must be re-routed.
func _on_wind_shifted() -> void:
	hud.set_wind_warning(0.0, -1)
	hud.set_wind(wind.from_deg, wind.toward_deg())
	airfield.show_active(wind)
	for r in Airports.rw_count():
		for e in 2:
			if wind.is_active(r, e):
				overlay.ripple(Airports.end_threshold(r, e), Airports.rw_color(r), 0.8)
	traffic.reroute_closed_ends()

## Weather: announced, started, ended.
func _on_weather_warned(_kind: String, text: String) -> void:
	_event_key = "%d:%d" % [weather.phase, ceili(weather.left)]
	hud.set_event_banner(weather.banner(), true)
	hud.popup(text, Color(1.0, 0.85, 0.4), Vector2(get_viewport().get_visible_rect().size.x * 0.5, get_viewport().get_visible_rect().size.y * 0.4))

func _on_weather_started(kind: String) -> void:
	traffic.event_active = true
	goal_weather = true
	match kind:
		"storm":
			var n := 1 + (1 if rng_env.randf() < 0.3 + 0.5 * traffic.run_time / maxf(Tuning.par_eff(), 1.0) else 0)
			for k in n:
				_spawn_storm()
		"fog":
			traffic.fog_target = 1.0
		_:
			wind.closing = -1
			if wind.close_runway(weather.runway, Tuning.crosswind_seconds):
				airfield.show_active(wind)
				traffic.reroute_closed_ends()
				overlay.ripple(Airports.rw_center(weather.runway), Color(1, 0.3, 0.2), 1.6)

func _on_weather_ended(kind: String) -> void:
	traffic.event_active = false
	if kind == "fog":
		traffic.fog_target = 0.0
	hud.set_event_banner("")
	_event_key = ""

## A storm cell comes in from a random edge and drifts across the field.
func _spawn_storm() -> void:
	var rng := rng_env
	var r := Tuning.storm_radius * rng.randf_range(0.85, 1.2)
	var side := rng.randi() % 4
	var hw := traffic.half_w
	var hh := traffic.half_h
	var from := Vector2.ZERO
	match side:
		0:
			from = Vector2(rng.randf_range(-hw, hw), -hh - r)
		1:
			from = Vector2(hw + r, rng.randf_range(-hh, hh))
		2:
			from = Vector2(rng.randf_range(-hw, hw), hh + r)
		_:
			from = Vector2(-hw - r, rng.randf_range(-hh, hh))
	var aim := Airports.field_center() + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
	traffic.add_storm(from, r, (aim - from).normalized() * Tuning.storm_speed)

## A closed runway is open again.
func _on_runway_reopened(r: int) -> void:
	airfield.show_active(wind)
	overlay.ripple(Airports.rw_center(r), Airports.rw_color(r), 1.2)
	hud.popup("%s runway open" % Airports.rw_name(r), Color(0.6, 1.0, 0.7), overlay.world_to_screen(Airports.rw_center(r)))

## Debug (?tune): announce a weather event now.
func trigger_weather(kind: String) -> void:
	weather.trigger(kind, rng_env, wind, true)

func _on_rerouted(p: Aircraft) -> void:
	hud.popup("Re-route!", Color(1, 0.35, 0.3), overlay.world_to_screen(p.pos) + Vector2(0, -60))

func _on_conflict(a: Aircraft, b: Aircraft) -> void:
	_conflict(a, b, "CONFLICT")

## A conflict: a large fine, and both aircraft are lost.
func _conflict(a: Aircraft, b: Aircraft, label: String) -> void:
	if not alive:
		return
	var mid := (a.pos + b.pos) * 0.5
	sfx.play("alarm")
	fx.burst(mid, Color(1.0, 0.5, 0.1), true)
	fx.burst(mid, Color(1.0, 0.15, 0.1), true)
	overlay.ripple(mid, Color(1, 0.3, 0.2), 1.3)
	overlay.ripple(mid, Color.WHITE, 2.4)
	shake(0.32, 0.32)
	if not DebugFlags.off("haptic"):
		_vibrate(150, Haptics.HEAVY)
	traffic.lose(a)
	traffic.lose(b)
	_cancel_drag()
	_apply_fine(Tuning.fine_amount(Tuning.fine_conflict), "conflict", label, mid)

## An aircraft's timer ran out: it is diverted, and that is a small fine.
func _on_timed_out(p: Aircraft) -> void:
	if not alive:
		return
	overlay.ripple(p.pos, Color(1, 0.5, 0.2), 1.0)
	_apply_fine(Tuning.fine_amount(Tuning.fine_timeout), "diversion", "Diverted", p.pos)

## The clock ran out: pay out (never below zero), award stars, save, show the results.
func _end_shift() -> void:
	if screen != SCREEN_PLAY:
		return
	alive = false
	screen = SCREEN_OVER
	_death_ms = Time.get_ticks_msec()
	_paid_payout = 0
	_daily_note = ""
	hud.set_finale("", Color.WHITE, false)
	var t_end := traffic.run_time
	if t_end < Tuning.par_eff():
		shift.set_finish(t_end, Tuning.par_eff(), int(Tuning.early_bonus_per_second))
	else:
		shift.set_overtime(t_end - Tuning.par_eff(), int(Tuning.overtime_penalty_per_second))
	_stinger_later("clear_sky" if shift.balance() >= 0 else "fine")
	var gained := _settle()
	_goal_event({"t": "shift", "ap": airport, "landed": shift.landed, "go_arounds": goal_go_arounds, "fines": shift.fines, "stars": shift.stars(), "net": shift.balance(), "hangar_full": shift.landed >= Ramp.star_landings(), "locked_run": goal_max_locked, "weather": goal_weather, "bad": bad_mode})
	if progress_enabled:
		_on_progress_shift_end()
	if not daily_mode and shift.landed >= 0:          # (what this player lands in a shift: the daily goals' targets follow it, so a struggling player's goals are within reach)
		var ek := "ema_land_%d" % airport
		var ev0 := float(Save.stats.get(ek, Goals.TYPICAL_LANDINGS[airport] * 100)) / 100.0
		Save.stats[ek] = roundi((ev0 * 0.7 + float(shift.landed) * 0.3) * 100.0)
	if not daily_mode and _goal_xp_pending > 0:
		_award_xp(_goal_xp_pending)
		_goal_xp_pending = 0
	if not daily_mode:
		Save.submit_best(airport, shift.landed)
	Save.shifts_played += 1
	if not daily_mode:
		Save.airport_plays[airport] += 1
	Save.ads["since"] = int(Save.ads.get("since", 0)) + 1
	Save.write_file()
	over_header = HEADER_DONE
	_log_go_arounds()
	new_best = gained["new_best"]
	var coins_before := Save.coins - int(gained["coins"])
	last_result = {"goal": _nearest_goal(coins_before), "header": HEADER_DONE, "reason": _reason_text(), "coins": gained["coins"], "payout": shift.payout(), "stars": shift.stars(), "first_stars": gained["first_stars"], "new_best": new_best, "unlocked": gained["unlocked"]}
	over_reason = last_result["reason"]
	_cancel_drag()
	hud.set_alert(false)
	hud.set_event_banner("")
	hud.flash(Color(1, 0.84, 0.15))
	hud.set_shift(shift)
	_show_results(false)
	if not DebugFlags.off("haptic"):
		_later(2, func(): _vibrate(150, Haptics.HEAVY))      # (not in the frame that lays the results card out)

var _daily_note := ""

# What the daily goals watch during a shift.
var goal_coins_total := 0              # (everything the goals have paid since the game started: the sims read it)
var ach_tab := 0
var toast_queue: Array = []             # [{"text", "color"}] waiting for a calm moment (an achievement, a mastery rank)
var goal_streak_row: Dictionary = {}
var toast_results: Array = []   # ...what happened this shift, listed on the results card
var _toast_gap := 0.0
var hangar_full_t := -1.0               # when this shift's hangar filled (star 1's landings), for 'a full hangar in under 45 s'
var progress_enabled := true            # (the tests switch mastery and achievements off like the goals, to keep coin counts exact)
var goals_enabled := true              # (the tests switch the goals off so their coin counts stay exact)
var goal_go_arounds := 0
var goal_locked_run := 0
var goal_max_locked := 0
var goal_weather := false
var goal_results: Array = []           # the goals this shift finished (for the results card): {"text", "reward"}
var goal_chest := 0
var goal_streak_text := ""
var _event_counted := false             # this shift has already counted toward the weekly event
var welcome_paid := 0                  # the welcome floor's top-up in this shift's pay (a row on the results card)
var xp_this_shift := 0                 # XP this shift has earned (landings, clean sheet, stars, goals), at the airport played
var _xp_paid := 0                      # ...of the shift's own XP (landings, clean sheet, stars) already credited (a refund settles again)
var _goal_xp_pending := 0              # XP of goals finished during the shift: credited at its end, so the airport never levels up mid-shift
var level_ups: Array = []              # the airport levels this shift reached: Save.add_xp's unlock entries

## Run `c` after `frames` frames: work that is not part of drawing a screen waits for the frames after it.
func _later(frames: int, c: Callable) -> void:
	for i in frames:
		await get_tree().process_frame
	c.call()

## The end-of-shift sting starts two frames after the results card is laid out, so its audio work is not in the frame that draws the card.
func _stinger_later(sound: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	sfx.play(sound)

## Credit what the shift is worth right now and return what was added: coins, first-time stars, a new best, a note.
## Safe to call again after a refund: it pays only the difference, and each star and daily bonus only once.
func _settle() -> Dictionary:
	var payout := shift.payout()
	# A welcome floor: the first two shifts at an airport pay at least this much (a share of its first improvement's price), so a player who struggles
	# is still a shift or two from the first thing to buy (the average player has it after one).
	var welcome_total := 0
	if not daily_mode and Save.airport_plays[airport] < Tuning.welcome_shifts:
		welcome_total = maxi(roundi(Tuning.welcome_floor_share * float(Improvements.cost(airport, "hangar", 0))) - payout, 0)
	welcome_paid = welcome_total
	var coins := payout + welcome_total - _paid_payout
	_paid_payout = payout + welcome_total
	var first_stars := 0
	var stars := shift.stars()
	var open_before := PackedByteArray()
	for i in Airports.COUNT:
		open_before.append(1 if Save.airport_open(i) else 0)
	if not daily_mode:       # (the daily shifts don't earn permanent stars)
		for i in stars:
			if Save.award_star(airport, i):
				first_stars += 1
				coins += Tuning.coins_first_star_bonus
	var note := ""
	if daily_mode:
		var kind := "bad"
		Save.daily_note_score(payout, kind)
		if stars >= 1 and not Save.daily_done_today(kind):
			var streak_now := Save.daily_complete(payout, kind)
			var bonus := _daily_bonus(streak_now)
			if bad_mode:
				bonus = roundi(bonus * Tuning.bad_day_bonus_mult)
			coins += bonus
			note = "\nBad day bonus|+%d (streak %d)" % [bonus, streak_now]
			_daily_note = note
	if not daily_mode:       # the shift's XP at this airport: landings, a clean sheet, the star objectives it met (every time, not only the first)
		var xp_total := Progression.shift_xp(shift.landed, shift.fines == 0, [stars >= 1, stars >= 2, stars >= 3], [], true)
		_award_xp(xp_total - _xp_paid)
		_xp_paid = xp_total
		if progress_enabled and not _event_counted and shift.landed >= 1:
			_event_counted = true
			var open_ids: Array = []
			for ai in Airports.COUNT:
				if Save.airport_open(ai):
					open_ids.append(ai)
			var ev_name: String = str(Airports.event.get("name", "Weekly event"))
			for er in Save.event_add_shift(stars, Goals.unit_for(open_ids, 1.0)):
				var etxt := "%s: reward %d" % [ev_name, int(er["i"]) + 1]
				_toast("%s  +%d" % [etxt, int(er["coins"])], Color(1.0, 0.75, 0.4), {"glyph": "star", "text": etxt, "coins": int(er["coins"])})
	Save.add_coins(coins)
	var is_best := (not daily_mode) and Save.submit_best_coins(airport, payout)
	Save.write_file()
	var unlocked: Array[int] = []
	for i in Airports.COUNT:
		if open_before[i] == 0 and Save.airport_open(i):
			unlocked.append(i)
	return {"coins": coins, "first_stars": first_stars, "new_best": is_best, "note": note, "unlocked": unlocked}

## The nearest goal after a shift, for the results card: the cheapest improvement that can be bought here (a bar to its price, filling from where the bank was
## before the shift to where it is now), or the next airport level when that is closer. {"text", "glyph", "frac0", "frac1", "tail", "ready"}.
func _nearest_goal(coins_before: int) -> Dictionary:
	var ap := airport
	var coin_goal := {}
	for iid in Improvements.IDS:
		if Save.imp_unlocked(ap, iid):
			var p := Improvements.cost(ap, iid, Save.imp_level(ap, iid))
			if coin_goal.is_empty() or p < int(coin_goal["price"]):
				coin_goal = {"price": p, "name": "%s %d" % [Improvements.improvement_name(iid), Save.imp_level(ap, iid) + 1]}
	var xp := Save.ap_progress(ap)
	var coin_frac := minf(float(Save.coins) / float(coin_goal["price"]), 1.0) if not coin_goal.is_empty() else -1.0
	var first := Save.imp_total(ap) == 0
	if not coin_goal.is_empty() and (first or Save.coins >= int(coin_goal["price"]) or coin_frac >= float(xp["frac"]) or int(xp["need"]) <= 0):
		var have := Save.coins
		var price: int = coin_goal["price"]
		if have >= price:
			return {"text": str(coin_goal["name"]), "glyph": "coin", "frac0": minf(float(coins_before) / float(price), 1.0), "frac1": 1.0, "tail": "Ready to buy!", "ready": true}
		return {"text": "%d coins to %s" % [price - have, coin_goal["name"]], "glyph": "coin", "frac0": minf(float(coins_before) / float(price), 1.0), "frac1": coin_frac, "tail": "%d more" % (price - have), "ready": false}
	if int(xp["need"]) > 0:
		var left := int(xp["left"])
		var before := maxf(float(int(xp["into"]) - xp_this_shift), 0.0) / float(xp["need"])
		return {"text": "%d XP to level %d" % [left, int(xp["level"]) + 1], "glyph": "star", "frac0": before, "frac1": float(xp["frac"]), "tail": "%d XP" % left, "ready": false}
	return {}

## Credit XP at the airport being played; each level it reaches is a row on the results card (with what it unlocks) and a banner.
func _award_xp(n: int) -> void:
	if n <= 0:
		return
	xp_this_shift += n
	var r := Save.add_xp(airport, n, progress_enabled)
	for h in r["half"]:
		var htxt := "%s of the way to level %d" % [("A third" if int(h.get("part", 1)) == 1 else "Two thirds"), int(h["level"]) + 1]
		_toast("%s  +%d" % [htxt, int(h["coins"])], Color(1.0, 0.85, 0.4), {"glyph": "star", "text": htxt, "coins": int(h["coins"])})
	for u in r["unlocks"]:
		level_ups.append(u)
		var txt := "Level %d: %s" % [int(u["level"]), str(u["title"])]
		_toast("%s  \u00b7  %s" % [Airports.airport_name(airport), txt], Color(0.55, 0.9, 1.0), {"glyph": "airport", "text": txt, "coins": 0})
		if u.has("opens"):
			Save.write_file()

## After a shift: how many go-arounds were signalled and how many the player cancelled by redrawing a cleaner final in time, printed to the
## console (the browser's, on the web) so the window can be tuned: the share is the human cancel rate.
func _log_go_arounds() -> void:
	var warns := traffic.go_around_warns
	var cancels := traffic.go_around_cancels
	last_go_around_log = "go-around warnings: %d, cancelled by the player: %d (cancel rate %.0f%%, window %.1f s)" % [warns, cancels, 100.0 * cancels / maxf(warns, 1), Tuning.go_around_telegraph]
	if log_go_arounds:
		var line := "[go-around] %s  airport=%s" % [last_go_around_log, Airports.airport_name(airport)]
		_later(3, func(): print(line))

## The results breakdown, one "label|value" line each (the "Details" panel draws them as two columns).
func _reason_text() -> String:
	var lines: Array[String] = [
		"Landings earned|+%d" % shift.earned,
		"Bonuses|+%d" % shift.bonus,
		"Early bonus|+%d (%d s)" % [shift.time_bonus, shift.early_seconds],
		"Fines|-%d" % shift.fines,
		"Overtime|-%d (%d s)" % [shift.overtime_penalty, shift.overtime_seconds],
		"Ramp|%s" % airfield.ramp.summary(),
		"Go-arounds|%d warned · %d cancelled" % [traffic.go_around_warns, traffic.go_around_cancels],
		"Net total (stars)|%d" % shift.balance(),
		"Pay floor (%d%% of gross)|%d" % [roundi(Tuning.landing_keep_fraction * 100.0), shift.kept()],
	]
	if shift.is_protected():
		lines.append("Shift pay protected|+%d" % (shift.kept() - shift.balance()))
	return "\n".join(lines) + _daily_note

## The rewarded pills on the results: only with an ad SDK behind them (the stub plays a fake 2.5 s "ad" and then pays, so without an SDK they would hand out free doubling).
func _ad_double_coins() -> int:
	return 0 if (_results_ad_used or not Tuning.ad_sdk_present) else int(last_result["coins"])

func _ad_refund_coins() -> int:
	return 0 if (_results_ad_used or not Tuning.ad_sdk_present) else shift.biggest_fine

## Fill in the results screen from `last_result`; the rewarded offers show until one has been used.
func _show_results(doubled: bool) -> void:
	var lv: Dictionary = Cosmetics.LIVERIES[Cosmetics.livery_index(Save.equipped_id("livery"))]
	hud.ramp_note = airfield.ramp.summary() if airfield.ramp_active or airfield.ramp.landed > 0 else ""
	hud.goal_rows = _extra_rows(true)
	hud.goal_strip = last_result.get("goal", {})
	toast_queue.clear()
	hud.show_results(HEADER_DONE, last_result["reason"], shift, last_result["coins"], Save.coins, Save.best_coins_for(airport), last_result["new_best"], lv["animal"], "%s: %s" % [lv["pilot"], lv["quote"]], doubled)
	hud.set_results_ads(_ad_double_coins(), _ad_refund_coins())
	var unlocked: Array = last_result.get("unlocked", [])
	if not unlocked.is_empty() and not last_result.get("unlock_seen", false):
		last_result["unlock_seen"] = true
		hud.queue_unlock(Airports.airport_name(unlocked[0]))

# ---------- Pause and volume ----------

## Freeze the shift (the clock and all traffic) behind the pause menu.
func pause_game() -> void:
	if screen != SCREEN_PLAY or not alive:
		return
	sfx.play("tap")
	screen = SCREEN_PAUSE
	_pause_since_ms = Time.get_ticks_msec()
	_cancel_drag()
	hud.show_pause(Save.sound_volume, Save.music_volume, Save.ambience_volume)
	_publish_state()

func resume_game() -> void:
	if screen != SCREEN_PAUSE:
		return
	_release_audio()
	_paused_total_ms += Time.get_ticks_msec() - _pause_since_ms
	_skip_frames = Tuning.resume_skip_frames
	screen = SCREEN_PLAY
	hud.hide_pause()
	_publish_state()

## Slider 0 = effects (the SFX bus), 1 = music, 2 = ambience.
func _set_volume(which: int, v: float) -> void:
	if which == 0:
		Save.sound_volume = v
	elif which == 1:
		Save.music_volume = v
	else:
		Save.ambience_volume = v
	_apply_volumes()

## The SFX, Music and Ambience buses come from default_bus_layout.tres (loaded before the audio driver starts). They are NEVER
## created at run time: in the single-threaded web export, adding a bus after start-up silences all audio.
func _apply_volumes() -> void:
	for pair in [["SFX", Save.sound_volume], ["Music", Save.music_volume], ["Ambience", Save.ambience_volume]]:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx < 0:
			continue
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(pair[1], 0.0001)))
		AudioServer.set_bus_mute(idx, pair[1] <= 0.001)

# ---------- Input ----------

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# A touch on the tuning panel's TUNE button belongs to the button, not the game.
	if TunePanel.button_hit(event.position):
		return
	if not _haptic_warmed:
		_haptic_warmed = true
		sfx.unlock()
		if not DebugFlags.off("haptic"):
			Input.vibrate_handheld(1)   # browsers only allow vibration after a touch: connect it early
	if _warming:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index, event.position)
	else:
		_touch_move(event.index, event.position)

func _touch_down(index: int, pos: Vector2) -> void:
	if _audio_hold and screen != SCREEN_PAUSE:
		_release_audio()          # (back from the background, on a menu: any tap brings the sound back)
	if hud.logo_active():
		hud.skip_logo()
		return
	if screen == SCREEN_PLAY and alive and hud.pause_hit(pos):
		pause_game()
		return
	if screen == SCREEN_PAUSE:
		var sl := hud.slider_at(pos)
		if sl >= 0:
			_slider_drag = sl
			_set_volume(sl, hud.slider_set(sl, pos.x))
			return
	if screen != SCREEN_PLAY:
		_press_pos = pos
		hud.press(pos)
		var id := hud.button_at(pos)
		if id != "":
			# Down: the button squashes with a soft click and a light buzz; the action itself fires on release.
			sfx.play("press")
			if not DebugFlags.off("haptic"):
				_vibrate(12, Haptics.LIGHT)
			return
		if hud.ui_hit(pos):
			sfx.play("error")
			return   # a disabled button
	if screen == SCREEN_OVER and not hud.results_revealed():
		hud.skip_animations()         # a tap on the empty screen finishes the reveal; the buttons do the rest
		return
	if screen == SCREEN_DETAIL:
		if pos.y < get_viewport().get_visible_rect().size.y * DETAIL_SPLIT:
			_dt_touch[index] = pos          # (a finger on the live field: it pans, two of them pinch)
			_dt_dist = _dt_fingers_dist()
		return
	if screen == SCREEN_MENU or screen == SCREEN_OVER:
		return
	if screen != SCREEN_PLAY or not alive or _drag_index != -1:
		return
	var w := overlay.screen_to_world(pos)
	var p := traffic.pick(w)
	if p == null:
		return
	_drag_index = index
	_drag_plane = p
	_drag_active = false
	_smooth_count = 0
	_touch_start = w
	_touch_ms = Time.get_ticks_msec()
	_last_world = w
	overlay.selected = p

## A finger went down on a button of the detail sheet (its Control tree has its own buttons): the same click and buzz as a drawn one.
func _on_sheet_pressed(_id: String) -> void:
	sfx.play("press")
	if not DebugFlags.off("haptic"):
		_vibrate(12, Haptics.LIGHT)

## ...and came up on it. A dimmed chip (an improvement out of reach) only answers with the error sound, as a dimmed drawn one does.
func _on_sheet_tapped(id: String) -> void:
	if screen != SCREEN_DETAIL:
		return
	var c = hud.detail_sheet().chips.get(id)
	if c != null and c.state == 1:
		sfx.play("error")
		return
	_on_button(id)

## A button / card on the menu, results or airport screen.
func _on_button(id: String) -> void:
	var coins_before := Save.coins
	var snd := _ui_sound(id)
	if snd != "":
		sfx.play(snd)
	if id == "play" or id == "again":
		begin_shift()
	elif id == "details":
		hud.toggle_details()
	elif id == "unlock_ok":
		hud.hide_unlock()
		hud.set_results_ads(_ad_double_coins(), _ad_refund_coins())
	elif id == "airports" or id == "airports_tag":
		_show_select()
	elif id.begins_with("noeng:"):
		var ne_i := int(id.substr(6))
		Save.no_engines_at[ne_i] = 0 if Save.no_engines_at[ne_i] != 0 else 1
		Save.write_file()
		if screen == SCREEN_DETAIL:
			_show_detail()
		else:
			_show_select()
	elif id == "noeng_bad":
		Save.no_engines_bad = not Save.no_engines_bad
		Save.write_file()
		_show_menu()
	elif id.begins_with("dtab:") or id == "imp_done":
		detail_tab = int(id.substr(5)) if id != "imp_done" else 0
		_show_detail()
	elif id.begins_with("imp:"):
		var sel := id.get_slice(":", 2)
		imp_selected = "" if imp_selected == sel else sel          # (a tap on a row selects it: it shows what the next level changes)
		_show_detail()
	elif id.begins_with("impbuy:"):         # (a tap, not a hold: a hold that fills buys and rebuilds the sheet before the finger lifts)
		hud.popup("Hold to buy", Color(1.0, 0.85, 0.45), get_viewport().get_visible_rect().size * Vector2(0.5, 0.42))
	elif id.begins_with("pick:") or id.begins_with("locked:"):
		open_detail(int(id.get_slice(":", 1)))
	elif id == "airport_prev" or id == "airport_next":
		_cycle_airport(-1 if id == "airport_prev" else 1)
	elif id == "upgrades":
		_show_upgrades()
	elif id == "shop":
		_show_shop()
	elif id.begins_with("shop_tab:"):
		shop_tab = int(id.substr(9))
		_show_shop()
	elif id.begins_with("theme:"):
		open_preview("theme", int(id.substr(6)))
	elif id.begins_with("livery:"):
		open_preview("livery", int(id.substr(7)))
	elif id.begins_with("windsock:"):
		open_preview("windsock", int(id.substr(9)))
	elif id.begins_with("hangar:"):
		open_preview("hangar", int(id.substr(7)))
	elif id.begins_with("prop:"):
		open_preview("prop", int(id.substr(5)))
	elif id == "preview_close" or id == "preview_scrim":
		close_preview()
	elif id.begins_with("pv_mode:"):
		preview_mode = int(id.substr(8))
		_refresh_preview()
	elif id == "pv_buy":
		_preview_tap()
	elif id == "privacy":
		open_privacy_policy()
	elif id == "goals":
		_show_goals()
	elif id == "ach":
		_show_achievements()
	elif id.begins_with("ach_tab:"):
		ach_tab = int(id.substr(8))
		_show_achievements()
	elif id.begins_with("greroll:"):
		reroll_goal(int(id.substr(8)))
	elif id == "bad":
		start_bad_day()
	elif id == "ad_refund":
		show_ad("Reward: refund your biggest fine", func(): _refund_biggest_fine(), SCREEN_OVER)
	elif id == "resume":
		resume_game()
	elif id == "restart":
		resume_game()
		restart()
	elif id == "quit":
		resume_game()
		_show_menu()
	elif id == "ad_double":
		show_ad("Reward: double your coins", func(): _double_coins(), SCREEN_OVER)
	elif id.begins_with("upg:"):
		buy_upgrade(id.substr(4))
	elif id == "back" and screen == SCREEN_DETAIL:
		close_detail()
	elif id == "back" or id == "menu":
		_show_menu()
	elif id.begins_with("airport:"):
		daily_mode = false
		bad_mode = false
		select_airport(int(id.substr(8)))
		Airports.current = airport
		airfield.select(airport)
		begin_shift()
	# Buying is judged by whether it cost anything.
	if id.begins_with("upg:"):
		sfx.play("buy" if Save.coins < coins_before else "error")
	elif id.begins_with("theme:") or id.begins_with("livery:") or id.begins_with("windsock:") or id.begins_with("hangar:"):
		sfx.play("buy" if Save.coins < coins_before else "toggle")

## Each kind of tap has its own sound: forward, back, a small toggle, the confirm of a reward. (Purchases sound
## after the fact, by what they cost.)
func _ui_sound(id: String) -> String:
	if id == "back" or id == "menu" or id == "quit" or id == "restart" or id == "resume":
		return "back"
	if id.begins_with("imp:"):
		return "toggle"
	if id == "details" or id.begins_with("shop_tab:") or id.begins_with("dtab:") or id == "imp_done" or id.begins_with("noeng") or id.begins_with("greroll:") or id.begins_with("ach_tab:"):
		return "toggle"
	if id == "unlock_ok" or id.begins_with("ad_"):
		return "unlock"
	if id.begins_with("upg:") or id.begins_with("imp:") or id.begins_with("theme:") or id.begins_with("livery:") or id.begins_with("windsock:") or id.begins_with("hangar:") or id.begins_with("prop:"):
		return ""
	return "tap"

func _show_upgrades() -> void:
	screen = SCREEN_UPGRADES
	alive = false
	var levels := PackedInt32Array()
	for id in Upgrades.IDS:
		levels.append(Save.upgrade_level(id))
	hud.show_upgrades(Save.coins, levels)

## While a finger is held on a row's cost button the fill runs across it; a full one buys (once), like the shop's sheet.
func _tick_imp_hold(delta: float) -> void:
	if screen != SCREEN_DETAIL or detail_tab != 1:
		_imp_hold_t = 0.0
		_imp_hold_id = ""
		return
	var sheet := hud.detail_sheet()
	var held := ""
	if sheet != null:
		for id in sheet.holds.keys():
			var c = sheet.chips.get(id)
			if c != null and c.state == 0 and c._held:
				held = id
				break
	if held == "":
		if _imp_hold_id != "":
			sheet.set_hold(_imp_hold_id, 0.0) if sheet != null else null
		_imp_hold_t = 0.0
		_imp_hold_id = ""
		return
	if held != _imp_hold_id:
		_imp_hold_id = held
		_imp_hold_t = 0.0
	_imp_hold_t += delta
	sheet.set_hold(held, minf(_imp_hold_t / maxf(Tuning.buy_hold_seconds, 0.05), 1.0))
	if _imp_hold_t >= Tuning.buy_hold_seconds:
		var ai := int(held.get_slice(":", 1))
		var iid := held.get_slice(":", 2)
		_imp_hold_t = 0.0
		_imp_hold_id = ""
		buy_improvement(ai, iid)

## Buy the next level of one of an airport's improvements: coins, saved, and built on the airport (the detail screen's Improve tab).
func buy_improvement(airport_i: int, id: String) -> bool:
	if not Save.buy_improvement(airport_i, id):
		return false
	airfield.show_upgrades(true)
	sfx.play("buy")
	hud.flash(Color(0.4, 1.0, 0.6))
	var vp := get_viewport().get_visible_rect().size
	hud.popup("%s level %d!" % [Improvements.improvement_name(id), Save.imp_level(airport_i, id)], Color(0.6, 1.0, 0.7), Vector2(vp.x * 0.5, vp.y * 0.2))
	if not DebugFlags.off("haptic"):
		_vibrate(40, Haptics.MEDIUM)
	if screen == SCREEN_DETAIL and detail_airport == airport_i:
		_show_detail()
		var first := Save.imp_total(airport_i) == 1
		if hud.detail_sheet() != null:
			hud.detail_sheet().peek(1.6 if first else 0.9)          # (the sheet fades away for a moment: the new building grows on the field behind it)
	return true

## Buy the next level of an upgrade: coins, saved, and visible on the airport (the radar re-frames the view).
func buy_upgrade(id: String) -> bool:
	if not Save.buy_upgrade(id):
		return false
	airfield.show_upgrades()
	hud.flash(Color(0.4, 1.0, 0.6))
	var vp := get_viewport().get_visible_rect().size
	hud.popup("%s level %d!" % [Upgrades.upgrade_name(id), Save.upgrade_level(id)], Color(0.6, 1.0, 0.7), Vector2(vp.x * 0.5, vp.y * 0.2))
	if not DebugFlags.off("haptic"):
		_vibrate(40, Haptics.MEDIUM)
	if screen == SCREEN_UPGRADES:
		_show_upgrades()
	return true

# ---------- Cosmetics, daily shift, ads, debug ----------

## Dress the airport and aircraft in what is equipped (theme, livery, pilot).
func apply_cosmetics() -> void:
	var ti := Cosmetics.theme_index(Save.equipped_id("theme"))
	var li := Cosmetics.livery_index(Save.equipped_id("livery"))
	airfield.apply_theme(ti)
	airfield.apply_details()
	var t: Dictionary = Cosmetics.THEMES[ti]
	_env.background_color = t["bg"]
	_env.ambient_light_color = t["ambient"]
	_env.ambient_light_energy = t["ambient_energy"]
	sun.light_energy = t["sun"]
	traffic.set_livery(li)
	diorama.traffic.set_livery(li)

## The Hangar's tabs and cards for the tab that is up. Tab 0 airport skins, 1 liveries, 2 field details (windsocks, then hangar paints). A card says
## where its item comes from while it is locked: its price in coins, a mastery rank, or an achievement.
func _shop_args() -> Array:
	var cards: Array = []
	var kinds: Array = [["theme"], ["livery"], ["windsock", "hangar", "prop"]][clampi(shop_tab, 0, 2)]
	for kind in kinds:
		var list: Array = Cosmetics.items(kind)
		for i in list.size():
			var d: Dictionary = list[i]
			if Cosmetics.source(d) == "shop" and d.has("ap") and not Save.airport_open(int(d["ap"])) and not Save.owns(kind, d["id"]):
				continue                      # (an airport's own things are for sale once the airport is open)
			var owned := Save.owns(kind, d["id"])
			var state := 0
			var sub := ""
			var cost := -1
			if Save.equipped_id(kind) == d["id"]:
				state = 2
				sub = "In use"
			elif owned:
				sub = "Owned"
			elif Cosmetics.source(d) == "shop":
				cost = d["cost"]
				state = 0 if Save.coins >= d["cost"] else 1
				sub = ("%d coins" % cost) if not d.has("ap") else ("%d coins \u00b7 %s" % [cost, Progression.NAMES[int(d["ap"])]])
			else:
				state = 1
				sub = Cosmetics.source_line(d)
			var card := {"id": "%s:%d" % [kind, i], "title": d["name"], "sub": sub, "state": state, "cost": -1, "locked": not owned and Cosmetics.source(d) != "shop"}
			match kind:
				"theme": card["icon"] = 100 + i
				"livery": card["icon"] = d["animal"]
				"windsock": card["swatch"] = [d["a"], d["b"]]
				"prop": card["swatch"] = [d["color"], Color("e8e1d2")]
				_: card["swatch"] = [d["color"] if d["color"] != null else Color("e2654a"), Color("e8e1d2")]
			cards.append(card)
	return [[
		{"id": "shop_tab:0", "title": "SKINS", "selected": shop_tab == 0},
		{"id": "shop_tab:1", "title": "LIVERIES", "selected": shop_tab == 1},
		{"id": "shop_tab:2", "title": "FIELD", "selected": shop_tab == 2}], cards]

func _show_shop() -> void:
	screen = SCREEN_SHOP
	alive = false
	var sh := _shop_args()
	hud.show_list("SHOP", Save.coins, sh[0], sh[1], true)

# ---------- The preview sheet: nothing is bought without it ----------
# A card opens a sheet over the list. Owned things have one "Equip" button. Things for sale have "Buy for N", which spends only when held
# (Tuning.buy_hold_seconds, with a fill that runs across the button); a tap just says to hold. Too poor: "Need N more", disabled.
# After the purchase a short animation, then one "Equip".

var preview_kind := ""
var preview_i := -1
var preview_mode := 1                     # themes: 0 = the current look, 1 = the new one
var preview_bought := false
var _hold_t := 0.0
var _hold_fired := false
var _swallow_tap := false

func open_preview(kind: String, i: int) -> void:
	preview_kind = kind
	preview_i = i
	preview_mode = 1
	preview_bought = false
	_hold_t = 0.0
	_hold_fired = false
	_swallow_tap = false
	_refresh_preview()

func close_preview() -> void:
	preview_kind = ""
	preview_i = -1
	hud.hide_preview()
	if screen == SCREEN_SHOP:
		_show_shop()

func _preview_item() -> Dictionary:
	return Cosmetics.items(preview_kind)[preview_i]

func _preview_args() -> Dictionary:
	var d := _preview_item()
	var owned := Save.owns(preview_kind, d["id"])
	var state := "buy"
	if owned and Save.equipped_id(preview_kind) == d["id"]:
		state = "equipped"
	elif owned:
		state = "bought" if preview_bought else "owned"
	elif Cosmetics.source(d) != "shop":
		state = "locked"
	elif Save.coins < d["cost"]:
		state = "need"
	var rw: Color = Airports.rw_color(0) if Airports.rw_count() > 0 else Airports.ORANGE
	var sub := "Airport skin"
	match preview_kind:
		"livery": sub = d["pilot"]
		"windsock": sub = "Windsock colours, on every airport"
		"hangar": sub = "Hangar paint, on every airport"
		"prop": sub = "A field prop at %s" % Progression.NAMES[int(d["ap"])]
	return {"kind": preview_kind, "index": preview_i, "name": d["name"], "state": state, "price": d["cost"], "balance": Save.coins, "need": maxi(d["cost"] - Save.coins, 0),
		"sub": sub, "source": Cosmetics.source_line(d), "mode": preview_mode, "airport": airport, "theme": preview_i if preview_kind == "theme" else 0,
		"current_theme": Cosmetics.theme_index(Save.equipped_id("theme")), "livery": d if preview_kind == "livery" else {}, "detail": d if preview_kind in ["windsock", "hangar", "prop"] else {}, "runway": rw}

func _refresh_preview() -> void:
	if preview_kind == "":
		return
	hud.show_preview(_preview_args())

## The buy button was tapped (not held). Equipping is a tap; buying is not.
func _preview_tap() -> void:
	if preview_kind == "":
		return
	if _swallow_tap:
		_swallow_tap = false              # (the release that ends the hold which just bought it)
		return
	match hud.preview_state():
		"owned", "bought":
			var d := _preview_item()
			if Save.equip(preview_kind, d["id"]):
				apply_cosmetics()
				sfx.play("toggle")
				_refresh_preview()
		"buy":
			hud.popup("Hold to buy", Color(1.0, 0.85, 0.45), get_viewport().get_visible_rect().size * Vector2(0.5, 0.42))

## Held long enough: spend the price, once.
func _buy_previewed() -> void:
	var d := _preview_item()
	if Save.owns(preview_kind, d["id"]):
		return
	if Save.buy_cosmetic(preview_kind, d["id"], d["cost"], false):
		preview_bought = true
		_swallow_tap = true
		sfx.play("buy")
		hud.flash(Color(0.6, 1.0, 0.7))
		_refresh_preview()

## Every frame while a sheet is up: the buy button's fill follows the finger, and a full one buys.
func _tick_preview(delta: float) -> void:
	if preview_kind == "" or not hud.preview_open():
		return
	if hud.preview_state() == "buy" and hud.pressed_id() == "pv_buy":
		_hold_t += delta
		hud.set_preview_hold(minf(_hold_t / maxf(Tuning.buy_hold_seconds, 0.05), 1.0))
		if _hold_t >= Tuning.buy_hold_seconds and not _hold_fired:
			_hold_fired = true
			_buy_previewed()
	else:
		_hold_t = 0.0
		_hold_fired = false
		hud.set_preview_hold(0.0)

## Tap a shop card: equip it if owned, otherwise buy (and equip) it.
func shop_pick(kind: String, i: int) -> bool:
	var d: Dictionary = Cosmetics.items(kind)[i]
	var ok := false
	if Save.owns(kind, d["id"]):
		ok = Save.equip(kind, d["id"])
	elif Cosmetics.source(d) == "shop":
		ok = Save.buy_cosmetic(kind, d["id"], d["cost"])
		if ok:
			hud.flash(Color(0.6, 1.0, 0.7))
	if ok:
		apply_cosmetics()
		if screen == SCREEN_SHOP:
			_show_shop()
	return ok

func _daily_bonus(streak_days: int) -> int:
	return Tuning.daily_bonus_coins + Tuning.daily_streak_coins * mini(streak_days, 7)

## The airport of Bad Pilot Day: one of the open airports, chosen by the day number (`offset` keeps it apart from other seeds).
## With every airport open this is `(day + offset) % 6`.
func daily_airport(offset: int) -> int:
	var open: Array[int] = []
	for i in Airports.COUNT:
		if Save.airport_open(i):
			open.append(i)
	return open[(Save.today() + offset) % open.size()] if not open.is_empty() else 0

## Bad Pilot Day: a second daily challenge. Every aircraft is a student pilot, go-arounds are very likely and every
## landing pays big. Its own airport, best score and streak.
func start_bad_day() -> void:
	daily_mode = true
	bad_mode = true
	airport = daily_airport(3)
	begin_shift()

## The star thresholds of this shift (Bad Pilot Day pays more, so it asks for more).
func _thresholds() -> Array:
	var th := Tuning.star_thresholds().duplicate()
	if bad_mode:
		for i in range(1, th.size()):         # (star 1 is a landing count: students go around, but it stays the same)
			th[i] = roundi(th[i] * Tuning.bad_day_threshold_mult)
	return th

## Start a shift, with an interstitial ad first if one is due (never in the middle of a shift).
func begin_shift() -> void:
	if Tuning.ad_sdk_present and int(Save.ads.get("since", 0)) >= Tuning.interstitial_every_shifts:
		Save.ads["since"] = 0
		show_ad("Between shifts: a short break", func(): restart(), SCREEN_MENU)
	else:
		restart()

## The fake ad screen. When it has run its course, `done` is called (it moves on to the right screen itself).
func show_ad(title: String, done: Callable, return_screen: int = SCREEN_MENU) -> void:
	ads_shown += 1
	if Tuning.ad_stub_seconds <= 0.0:
		done.call()
		return
	screen = SCREEN_AD
	alive = false
	_ad_kind = title
	_ad_left = Tuning.ad_stub_seconds
	_ad_done = done
	_ad_return = return_screen
	hud.show_ad(title)

var _ad_return := SCREEN_MENU

func _tick_ad(raw_delta: float) -> void:
	_ad_left -= raw_delta
	hud.set_ad_progress(1.0 - _ad_left / maxf(Tuning.ad_stub_seconds, 0.01))
	if _ad_left <= 0.0:
		hud.hide_ad()
		screen = _ad_return
		_ad_done.call()

## After the ad (results screen): the biggest fine is given back, so the payout, stars and bonuses are worked out again.
func _refund_biggest_fine() -> void:
	_results_ad_used = true
	var amount := shift.refund_biggest()
	var gained := _settle()
	last_result["coins"] += gained["coins"]
	last_result["payout"] = shift.payout()
	last_result["stars"] = shift.stars()
	last_result["first_stars"] += gained["first_stars"]
	if not gained["unlocked"].is_empty():
		last_result["unlocked"] = last_result.get("unlocked", []) + gained["unlocked"]
		last_result["unlock_seen"] = false
	last_result["new_best"] = last_result["new_best"] or gained["new_best"]
	last_result["reason"] = "%s\nFine refunded|+%d" % [_reason_text(), amount]
	over_reason = last_result["reason"]
	screen = SCREEN_OVER
	_death_ms = Time.get_ticks_msec()
	hud.set_shift(shift)
	_show_results(false)

## Results: the rewarded "double the coins" (once per shift, instead of the refund).
func _double_coins() -> void:
	_doubled = true
	_results_ad_used = true
	Save.add_coins(last_result["coins"])
	Save.write_file()
	last_result["coins"] *= 2
	_show_results(true)

## ---- Debug (?tune) ----

func debug_add_coins(n: int = 1000) -> void:
	Save.add_coins(n)
	Save.write_file()

func debug_unlock_all() -> void:
	Save.unlocks["all_airports"] = true
	Save.write_file()

func debug_max_upgrades() -> void:
	for id in Upgrades.IDS:
		Save.upgrades[id] = Upgrades.MAX_LEVEL
	Save.write_file()
	airfield.show_upgrades()

func debug_force_wind() -> void:
	wind.force_shift(-1.0, rng_env)

func debug_reset_save() -> void:
	Save.reset_all()
	airport = 0
	apply_cosmetics()
	airfield.show_upgrades()

func debug_reset_daily() -> void:
	Save.goals = {}
	Save.goal_streak = {}
	Save.bad_day = {}
	Save.write_file()

func select_airport(i: int) -> void:
	airport = clampi(i, 0, Airports.COUNT - 1)
	Save.selected_airport = airport
	Save.write_file()

## The menu's arrows: the next (or previous) airport that is open.
func _cycle_airport(dir: int) -> void:
	var i := airport
	for k in Airports.COUNT:
		i = posmod(i + dir, Airports.COUNT)
		if Save.airport_open(i):
			break
	if i != airport and not request_airport(i):
		return
	select_airport(i)
	Airports.current = airport           # (the field behind the menu follows)
	airfield.select(airport)
	airfield.show_active(wind)
	_show_menu()

## An airport card was tapped: its detail screen (the tests call this directly). A locked airport opens the same screen, view only.
## Its scenery is built first if it is not there yet (the card says "Loading...").
func open_detail(i: int) -> void:
	i = clampi(i, 0, Airports.COUNT - 1)
	if not airfield.is_built(i):
		_wanted_detail = true
		request_airport(i)
		return
	detail_airport = i
	Airports.current = i                # (the field behind follows: it is idle there, with the same autopilot traffic as the menu's)
	airfield.select(i)
	airfield.show_active(wind)
	_dt_touch.clear()
	_dt_dist = 0.0
	detail_tab = 0
	imp_selected = ""
	screen = SCREEN_DETAIL
	alive = false
	_show_detail()

func close_detail() -> void:
	detail_airport = -1
	Airports.current = airport
	airfield.select(airport)
	airfield.show_active(wind)
	_show_select()

func _show_detail() -> void:
	var i := detail_airport
	var th := Tuning.star_thresholds(i)
	var pay := maxf(Ramp.mean_pay(i), 1.0)
	var need := PackedInt32Array([int(th[0])])         # star 1 is a landing count; stars 2 and 3 are net coins (with the clean landings that pay it)
	for k in range(1, 3):
		need.append(maxi(ceili(float(th[k]) / pay), 1))
	var imps := []
	for iid in Improvements.IDS:
		var lv := Save.imp_level(i, iid)
		var mx := Improvements.max_level(iid)
		imps.append({"id": iid, "name": Improvements.improvement_name(iid), "level": lv, "max": mx, "price": Improvements.cost(i, iid, lv),
			"now": Improvements.short_effect(iid, lv) if lv > 0 else "", "next": Improvements.short_effect(iid, lv + 1) if lv < mx else "",
			"locked": lv < mx and not Save.imp_unlocked(i, iid), "gate": Progression.imp_gate(lv + 1, iid) if lv < mx else 0})
	var mp := Mastery.progress(i, Save.mastery_landings(i))
	var nx := Progression.next_unlock(i, Save.ap_level(i))
	var es := Save.event_state()
	var next_pts := 0
	for ti in Rhythm.TRACK.size():
		if not bool(es["claimed"][ti]):
			next_pts = int(Rhythm.TRACK[ti]["points"])
			break
	var event_info := {"name": str(es["event"]["name"]), "text": str(es["event"]["text"]), "points": int(es["points"]), "next": next_pts}
	var info_extra := {"event": event_info, "split": DETAIL_SPLIT, "level": Save.ap_progress(i), "next": nx, "star_names": Progression.STAR_NAMES[i], "daily": _daily_for_detail(i)}
	if Save.imp_total(i) == 0 and Save.airport_open(i):
		var fg := _first_goal(i)
		if not fg.is_empty():
			info_extra["first_goal"] = fg
	var info := {
		"rank": mp["rank"], "into": mp["into"], "need": mp["need"], "frac": mp["frac"], "landings": Save.mastery_landings(i),
		"tab": detail_tab, "imps": imps, "imp_sel": imp_selected, "bank": Save.coins, "hangar": Ramp.capacity(i),
		"i": i, "name": Airports.airport_name(i), "tag": Airports.tag(i), "open": Save.airport_open(i), "lock": Progression.GATE_LEVEL,
		"stars": Save.stars_of(i), "best": Save.best_for(i), "coins": th, "land": need,
		"no_engines": Save.no_engines_at[i] != 0, "no_engines_ok": Save.stars_of(i) >= 3 and Save.airport_open(i),
		"no_engines_mult": Tuning.no_engines_pay_mult,
		"lock_text": _lock_text(i),
	}
	info.merge(info_extra)
	hud.show_detail(info)

## What a closed airport says it needs: "Reach level 8 at County".
func _lock_text(i: int) -> String:
	return "Reach level %d at %s" % [Progression.GATE_LEVEL, Airports.airport_name(maxi(i - 1, 0))]

## The first thing to buy at an airport and what it costs (the detail screen's "first goal"): the hangar bay.
func _first_goal(i: int) -> Dictionary:
	var p := Improvements.cost(i, "hangar", 0)
	if p < 0:
		return {}
	return {"name": Improvements.improvement_name("hangar"), "price": p, "have": Save.coins}

## Today's goals at an airport for its detail screen: [{"text", "reward", "done"}].
func _daily_for_detail(i: int) -> Array:
	var out := []
	for g in (Save.goals_for(i, goals_ctx(i)).get("list", []) as Array):
		out.append({"text": Goals.text(g, Airports.airport_name(maxi(int(g["ap"]), 0))), "reward": int(g["reward"]), "done": bool(g["done"])})
	return out

func _mastery_for_hud() -> void:
	var ranks := []
	var pcts := []
	for i in Airports.COUNT:
		var mp := Mastery.progress(i, Save.mastery_landings(i))
		ranks.append(mp["rank"])
		pcts.append(roundi(float(mp["frac"]) * 100.0))
	hud.mastery_ranks = ranks
	hud.mastery_pcts = pcts

func _show_select() -> void:
	screen = SCREEN_SELECT
	alive = false
	_mastery_for_hud()
	var open := PackedByteArray()
	var stars := PackedInt32Array()
	var best := PackedInt32Array()
	for i in Airports.COUNT:
		open.append(1 if Save.airport_open(i) else 0)
		stars.append(Save.stars_of(i))
		best.append(Save.best_for(i))
	hud.show_select(Save.stars_total(), open, stars, best, airport, Save.no_engines_at)

## The distance between two fingers on the detail view (0 with fewer).
func _dt_fingers_dist() -> float:
	if _dt_touch.size() < 2:
		return 0.0
	var ks := _dt_touch.keys()
	return (_dt_touch[ks[0]] as Vector2).distance_to(_dt_touch[ks[1]])

## Fingers on the detail view: one pans, two pinch (and pan with their midpoint). `detail_zoom` and `detail_pan` follow them.
func detail_gesture(index: int, pos: Vector2) -> void:
	if not _dt_touch.has(index):
		return
	var vp := get_viewport().get_visible_rect().size
	var before: Vector2 = _dt_touch[index]
	var s_now := view_size * DETAIL_FACTOR * detail_zoom
	var per_px := s_now / vp.x                              # world units per pixel across
	var n_before := _dt_touch.size()
	var mid0 := Vector2.ZERO
	for q in _dt_touch.values():
		mid0 += q / float(n_before)
	_dt_touch[index] = pos
	var mid1 := Vector2.ZERO
	for q in _dt_touch.values():
		mid1 += q / float(n_before)
	var d := (mid1 - mid0) * per_px
	detail_pan -= Vector2(d.x, d.y / cos(deg_to_rad(Tuning.camera_tilt_deg)))
	if n_before >= 2:
		var dist := _dt_fingers_dist()
		if _dt_dist > 20.0 and dist > 20.0:
			detail_zoom = clampf(detail_zoom * _dt_dist / dist, DETAIL_ZOOM_MIN, DETAIL_ZOOM_MAX)
		_dt_dist = dist
	detail_pan = Vector2(clampf(detail_pan.x, -4.0, 4.0), clampf(detail_pan.y, -7.0, 7.0))

func _touch_move(index: int, pos: Vector2) -> void:
	if screen == SCREEN_DETAIL:
		detail_gesture(index, pos)
		return
	if _slider_drag >= 0:
		_set_volume(_slider_drag, hud.slider_set(_slider_drag, pos.x))
		return
	if index != _drag_index or _drag_plane == null:
		return
	var w := overlay.screen_to_world(pos)
	_last_world = w
	feed_drag(w)

## The path follows the average of the finger's last few points (Tuning.path_smooth_points), so a shaky finger draws a smooth line.
func _smooth(w: Vector2) -> Vector2:
	var n := clampi(roundi(Tuning.path_smooth_points), 1, _smooth_buf.size())
	if _smooth_count == 0:
		_smooth_buf.fill(w)
	_smooth_buf[_smooth_count % _smooth_buf.size()] = w
	_smooth_count += 1
	var sum := Vector2.ZERO
	var used := mini(n, _smooth_count)
	for k in used:
		sum += _smooth_buf[posmod(_smooth_count - 1 - k, _smooth_buf.size())]
	return sum / used

## The finger is at world position `w` (the tests call this directly).
func feed_drag(w: Vector2) -> void:
	if _drag_plane == null:
		return
	if not _drag_plane.active():
		_cancel_drag()
		return
	if not _drag_active:
		if w.distance_to(_touch_start) < Tuning.tap_slop:
			return
		if not traffic.begin_path(_drag_plane):
			_cancel_drag()
			return
		_drag_active = true
		overlay.active_runway = _drag_plane.runway
	if traffic.extend_path(_drag_plane, _smooth(w), w):
		_cancel_drag()

func _touch_up(index: int, pos: Vector2) -> void:
	if _dt_touch.erase(index):
		_dt_dist = _dt_fingers_dist()
	var pressed_id := hud.pressed_id()
	hud.release()
	if pressed_id != "" and screen != SCREEN_PLAY and hud.button_at(pos) == pressed_id and pos.distance_to(_press_pos) < 30.0:         # (a finger that dragged a list is not a tap)
		_on_button(pressed_id)
		return
	if _slider_drag >= 0:
		_slider_drag = -1
		Save.write_file()
		return
	if index != _drag_index:
		return
	var p := _drag_plane
	if p != null and p.active():
		if _drag_active:
			traffic.end_path(p, overlay.screen_to_world(pos))
		elif Time.get_ticks_msec() - _touch_ms <= Tuning.tap_max_ms:
			traffic.toggle_hold(p)
	_cancel_drag()

func _cancel_drag() -> void:
	_drag_index = -1
	_drag_plane = null
	_drag_active = false
	overlay.selected = null
	overlay.active_runway = -1

# ---------- Camera ----------

## A short, sharp camera shake: `mag` in world units, dying away over `dur` seconds.
func shake(mag: float, dur: float = 0.3) -> void:
	if DebugFlags.off("shake"):
		return
	_shake_mag = maxf(_shake_mag if _shake_left > 0.0 else 0.0, mag)
	_shake_dur = dur
	_shake_left = dur

func _tick_shake(raw_delta: float) -> void:
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - raw_delta, 0.0)
		var k := _shake_left / maxf(_shake_dur, 0.01)
		var t := Time.get_ticks_msec() / 1000.0
		shake_offset = Vector2(sin(t * 95.0), cos(t * 113.0)) * _shake_mag * k * k
	elif shake_offset != Vector2.ZERO:
		shake_offset = Vector2.ZERO
		_shake_mag = 0.0

func _update_camera() -> void:
	camera.h_offset = shake_offset.x
	camera.v_offset = shake_offset.y
	var tilt := deg_to_rad(Tuning.camera_tilt_deg)
	var k := smoothstep(0.0, 1.0, detail_t)
	var size_now := view_size * lerpf(1.0, DETAIL_FACTOR * detail_zoom, k)
	camera.size = size_now
	camera.near = Tuning.camera_near
	camera.far = Tuning.camera_near + (Tuning.camera_far - Tuning.camera_near) * (256.0 if DebugFlags.lowz_enabled() else 1.0)
	camera.position = Vector3(0, cos(tilt), sin(tilt)) * 30.0
	if k > 0.0:        # the detail screen: the field sits in the top two thirds (the camera moves south), shifted by the player's pan
		var vp := get_viewport().get_visible_rect().size
		var down := vp.y * (0.5 - DETAIL_SPLIT * 0.5) * (size_now / vp.x) / cos(tilt)
		camera.position += Vector3(detail_pan.x * k, 0.0, (down + detail_pan.y) * k)
	camera.rotation = Vector3(-(PI / 2 - tilt), 0, 0)

## The screen spans z = -half .. +half (stretched slightly by the camera tilt).
func _half_height() -> float:
	var vp := get_viewport().get_visible_rect().size
	return view_size * 0.5 * vp.y / vp.x / cos(deg_to_rad(Tuning.camera_tilt_deg))

func _setup_environment() -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.26, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
