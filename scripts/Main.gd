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
var fog_layer: FogLayer
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
var score := 0                        # aircraft landed this shift (the big number)
var _event_key := ""
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
	Engine.max_physics_steps_per_frame = 1   # no physics here: a stall can never trigger catch-up steps
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
	traffic.wind = wind
	airfield.wind = wind
	airfield.traffic = traffic
	wind.warned.connect(_on_wind_warned)
	wind.shifted.connect(_on_wind_shifted)
	traffic.inactive_end.connect(_on_inactive_end)
	traffic.rerouted.connect(_on_rerouted)
	traffic.crashed.connect(_on_crashed)
	traffic.go_around.connect(_on_go_around)
	hud.star_reached.connect(_on_star_reached)
	hud.coin_arrived.connect(_on_coin_arrived)
	hud.transition_started.connect(func(_d: int): if not _warming: sfx.play("whoosh"))
	hud.unlock_shown.connect(func(): sfx.play("unlock"))
	hud.confetti_started.connect(func(): sfx.play("unlock"))
	hud.star_slam.connect(_on_star_slam)
	traffic.runway_conflict.connect(_on_runway_conflict)
	traffic.refused.connect(_on_refused)
	wind.reopened.connect(_on_runway_reopened)
	weather.warned.connect(_on_weather_warned)
	weather.started.connect(_on_weather_started)
	weather.ended.connect(_on_weather_ended)
	traffic.appeared.connect(_on_appeared)
	ribbons.traffic = traffic
	fog_layer = FogLayer.new()
	fog_layer.traffic = traffic
	fog_layer.wind = wind
	add_child(fog_layer)
	diorama = Diorama.new()
	diorama.wind = wind
	add_child(diorama)
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
	shift.reset(Tuning.star_thresholds(), Tuning.landing_keep_fraction)
	wind.start(rng_env)
	airfield.show_active(wind)
	hud.set_wind(wind.from_deg, wind.toward_deg())
	airfield.show_upgrades()
	apply_cosmetics()
	_apply_volumes()
	sfx = Sfx.new()
	add_child(sfx)
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
	hud.end_prewarm()
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
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
func restart() -> void:
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
	if daily_mode:
		var seed_v := (Save.today() * 2654435761) & 0x7fffffff
		if bad_mode:
			seed_v = (seed_v ^ 0x2f1d9a7) & 0x7fffffff
		traffic.rng.seed = seed_v
		rng_env.seed = seed_v ^ 0x5bd1e995
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
	hud.set_wind(wind.from_deg, wind.toward_deg())
	hud.set_shift(shift)

func _show_menu() -> void:
	screen = SCREEN_MENU
	alive = false
	daily_mode = false
	bad_mode = false
	hud.mode = ""
	hud.daily_streak = Save.daily_streak()
	hud.daily_done = Save.daily_done_today()
	hud.bad_streak = Save.daily_streak("bad")
	hud.bad_done = Save.daily_done_today("bad")
	airfield.progress = -1.0
	hud.show_menu(Airports.airport_name(airport), Save.coins, Save.stars_total(), Save.best_for(airport), Airports.tag(airport), Save.stars_of(airport))

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

func _process(raw_delta: float) -> void:
	_poll_page(raw_delta)
	_tick_shake(raw_delta)
	# Music: the shift's own while playing; the calm menu bed everywhere else; the two crossfade.
	if screen != SCREEN_PLAY and screen != SCREEN_PAUSE:
		sfx.set_music(false)
	sfx.set_menu_music(not _warming and screen != SCREEN_PLAY and screen != SCREEN_PAUSE and screen != SCREEN_AD)
	view_size = lerpf(view_size, Tuning.view_size(), 1.0 - exp(-raw_delta * 3.0))   # the radar re-frames the view smoothly
	_update_camera()
	traffic.half_w = view_size * 0.5
	traffic.half_h = _half_height()
	diorama.traffic.half_w = traffic.half_w
	diorama.traffic.half_h = traffic.half_h
	diorama.active = screen == SCREEN_MENU and not _warming
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

## The music intensifies through the shift and towards the finale (there is no engine hum: the music is the only continuous sound).
func _update_audio(frac: float) -> void:
	airfield.progress = frac
	sfx.set_music(true, frac, 1.0 if _finale > 0 else 0.0)
	sfx.set_fog(traffic.fog_amount)

# ---------- Game events ----------

## The wheels touch the runway: a puff of dust and a little pop of the aircraft.
func _on_touchdown(p: Aircraft) -> void:
	if p.tkind != Aircraft.Kind.PAD:
		fx.puff(p.pos)
		sfx.play("touch")
		sfx.play("chirp")

func _on_landed(p: Aircraft) -> void:
	if not alive:
		return
	score += 1
	var vip_paid := p.vip and p.vip_ok
	var base := Tuning.landing_pay(p.type)
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
	shift.on_landed(p.type, base, extra, vip_paid, p.emergency, p.student)
	var col := Airports.land_color(p.tkind, p.runway)
	var land_at := p.pos
	airfield.begin_taxi(p.type, p.tkind, p.runway, p.land_end)
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
	hud.fly_coins(overlay.world_to_screen(land_at), clampi((base + extra) / 8, 1, 5))
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
	_star_feedback(land_at)
	if not DebugFlags.off("haptic"):
		_vibrate(Tuning.haptic_ms)

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
		Input.vibrate_handheld(80)

## An aircraft flew into terrain or a storm cell: lost, and a medium fine.
func _on_crashed(p: Aircraft, kind: int) -> void:
	if not alive:
		return
	fx.burst(p.pos, Color(0.85, 0.6, 0.4), true)
	overlay.ripple(p.pos, Color(1, 0.35, 0.2), 1.1)
	shake(0.2, 0.25)
	_apply_fine(Tuning.fine_amount(Tuning.fine_hazard), "crash", "Struck by storm!" if kind == 1 else ("No room to land!" if kind == 2 else "Crashed!"), p.pos)

## A go-around: the aircraft climbs out along the runway heading and needs a new path (it keeps its timer).
func _on_go_around(p: Aircraft, reason: int) -> void:
	var why := Approach.reason_text(reason)
	sfx.play("go_around")
	hud.popup("Go-around!" if why == "" else "Go-around!\n%s" % why, Color(1, 0.85, 0.3), overlay.world_to_screen(p.pos) + Vector2(0, -60))
	overlay.ripple(p.pos, Color(1, 0.85, 0.3), 0.7)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(30)

## Two aircraft landed on crossing runways at once: a conflict.
func _on_runway_conflict(a: Aircraft, b: Aircraft) -> void:
	_conflict(a, b, "RUNWAY CONFLICT")

## A coin reaches the counter: a soft plink, each one a note higher in the key while they keep arriving.
func _on_coin_arrived() -> void:
	var now := Time.get_ticks_msec()
	_coin_step = 0 if now - _coin_last_ms > 700 else mini(_coin_step + 1, Sfx.STEPS - 1)
	_coin_last_ms = now
	sfx.play_step("coin", _coin_step)

## A star lit on the bar during a shift.
func _on_star_reached(_i: int) -> void:
	sfx.play("star")
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(20)

## A results star slammed in: an impact sound that rises with each star.
func _on_star_slam(i: int) -> void:
	sfx.play("slam", 1.0 + 0.14 * i)
	shake(0.12, 0.18)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(25)

## The aircraft can't follow a path or tap (and the reason is shown where it happened).
func _on_refused(_p: Aircraft, text: String, at: Vector2) -> void:
	overlay.ripple(at, Color(1, 0.6, 0.25), 0.6)
	hud.popup(text, Color(1, 0.75, 0.35), overlay.world_to_screen(at) + Vector2(0, 90))

## First time a kind of aircraft is on screen: a one-line tip. Emergencies announce themselves every time.
const TIPS := {
	"drag": ["Drag from an aircraft to its runway", "plane"],
	"glider": ["Glider: one path, no holding", "glider"],
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
	_vibrate(Tuning.snap_haptic_ms)

## A short buzz: the browser's navigator.vibrate on the web (Godot's own call is a no-op there on some browsers), else the handheld's.
func _vibrate(ms: int) -> void:
	if DebugFlags.off("haptic"):
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (navigator.vibrate) navigator.vibrate(%d)" % ms)
	else:
		Input.vibrate_handheld(ms)

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
	match kind:
		"storm":
			var n := 1 + (1 if rng_env.randf() < 0.3 + 0.5 * traffic.run_time / maxf(Tuning.par_eff(), 1.0) else 0)
			for k in n:
				_spawn_storm()
		"fog":
			traffic.fog_target = 1.0
		_:
			if wind.close_runway(weather.runway, Tuning.crosswind_seconds):
				airfield.show_active(wind)
				traffic.reroute_closed_ends()
				overlay.ripple(Airports.rw_center(weather.runway), Color(1, 0.3, 0.2), 1.6)

func _on_weather_ended(kind: String) -> void:
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
	weather.trigger(kind, rng_env, wind)

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
		Input.vibrate_handheld(150)
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
	sfx.play("clear_sky" if shift.balance() >= 0 else "fine")
	var gained := _settle()
	if not daily_mode:
		Save.submit_best(airport, shift.landed)
	Save.shifts_played += 1
	if not daily_mode:
		Save.airport_plays[airport] += 1
	Save.ads["since"] = int(Save.ads.get("since", 0)) + 1
	Save.write_file()
	over_header = HEADER_DONE
	new_best = gained["new_best"]
	last_result = {"header": HEADER_DONE, "reason": _reason_text(), "coins": gained["coins"], "payout": shift.payout(), "stars": shift.stars(), "first_stars": gained["first_stars"], "new_best": new_best, "unlocked": gained["unlocked"]}
	over_reason = last_result["reason"]
	_cancel_drag()
	hud.set_alert(false)
	hud.set_event_banner("")
	hud.flash(Color(1, 0.84, 0.15))
	hud.set_shift(shift)
	_show_results(false)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(150)

var _daily_note := ""

## Credit what the shift is worth right now and return what was added: coins, first-time stars, a new best, a note.
## Safe to call again after a refund: it pays only the difference, and each star and daily bonus only once.
func _settle() -> Dictionary:
	var payout := shift.payout()
	var coins := payout - _paid_payout
	_paid_payout = payout
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
		var kind := "bad" if bad_mode else "daily"
		Save.daily_note_score(payout, kind)
		if stars >= 1 and not Save.daily_done_today(kind):
			var streak_now := Save.daily_complete(payout, kind)
			var bonus := _daily_bonus(streak_now)
			if bad_mode:
				bonus = roundi(bonus * Tuning.bad_day_bonus_mult)
			coins += bonus
			note = "\n%s bonus|+%d (streak %d)" % ["Bad day" if bad_mode else "Daily", bonus, streak_now]
			_daily_note = note
	Save.add_coins(coins)
	var is_best := (not daily_mode) and Save.submit_best_coins(airport, payout)
	Save.write_file()
	var unlocked: Array[int] = []
	for i in Airports.COUNT:
		if open_before[i] == 0 and Save.airport_open(i):
			unlocked.append(i)
	return {"coins": coins, "first_stars": first_stars, "new_best": is_best, "note": note, "unlocked": unlocked}

## The results breakdown, one "label|value" line each (the "Details" panel draws them as two columns).
func _reason_text() -> String:
	var lines: Array[String] = [
		"Landings earned|+%d" % shift.earned,
		"Bonuses|+%d" % shift.bonus,
		"Early bonus|+%d (%d s)" % [shift.time_bonus, shift.early_seconds],
		"Fines|-%d" % shift.fines,
		"Overtime|-%d (%d s)" % [shift.overtime_penalty, shift.overtime_seconds],
		"Ramp|%s" % airfield.ramp.summary(),
		"Net total (stars)|%d" % shift.balance(),
		"Guaranteed kept|%d" % shift.kept(),
	]
	return "\n".join(lines) + _daily_note

## Fill in the results screen from `last_result`; the rewarded offers show until one has been used.
func _show_results(doubled: bool) -> void:
	var lv: Dictionary = Cosmetics.LIVERIES[Cosmetics.livery_index(Save.equipped_id("livery"))]
	hud.ramp_note = airfield.ramp.summary() if airfield.ramp_active or airfield.ramp.landed > 0 else ""
	hud.show_results(HEADER_DONE, last_result["reason"], shift, last_result["coins"], Save.coins, Save.best_coins_for(airport), last_result["new_best"], lv["animal"], "%s: %s" % [lv["pilot"], lv["quote"]], doubled)
	hud.set_results_ads(0 if _results_ad_used else last_result["coins"], 0 if _results_ad_used else shift.biggest_fine)
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
		hud.press(pos)
		var id := hud.button_at(pos)
		if id != "":
			# Down: the button squashes with a soft click and a light buzz; the action itself fires on release.
			sfx.play("press")
			if not DebugFlags.off("haptic"):
				Input.vibrate_handheld(12)
			return
		if hud.ui_hit(pos):
			sfx.play("error")
			return   # a disabled button
	if screen == SCREEN_OVER and not hud.results_revealed():
		hud.skip_animations()         # a tap on the empty screen finishes the reveal; the buttons do the rest
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
		hud.set_results_ads(0 if _results_ad_used else last_result["coins"], 0 if _results_ad_used else shift.biggest_fine)
	elif id == "airports":
		_show_select()
	elif id.begins_with("pick:"):
		select_airport(int(id.substr(5)))
		Airports.current = airport
		airfield.select(airport)
		_show_select()
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
		shop_pick("theme", int(id.substr(6)))
	elif id.begins_with("livery:"):
		shop_pick("livery", int(id.substr(7)))
	elif id == "daily":
		start_daily()
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
	elif id == "back" or id == "menu":
		_show_menu()
	elif id.begins_with("airport:"):
		daily_mode = false
		bad_mode = false
		select_airport(int(id.substr(8)))
		begin_shift()
	# Buying is judged by whether it cost anything.
	if id.begins_with("upg:"):
		sfx.play("buy" if Save.coins < coins_before else "error")
	elif id.begins_with("theme:") or id.begins_with("livery:"):
		sfx.play("buy" if Save.coins < coins_before else "toggle")

## Each kind of tap has its own sound: forward, back, a small toggle, the confirm of a reward. (Purchases sound
## after the fact, by what they cost.)
func _ui_sound(id: String) -> String:
	if id == "back" or id == "menu" or id == "quit" or id == "restart" or id == "resume":
		return "back"
	if id == "details" or id.begins_with("shop_tab:"):
		return "toggle"
	if id == "unlock_ok" or id.begins_with("ad_"):
		return "unlock"
	if id.begins_with("upg:") or id.begins_with("theme:") or id.begins_with("livery:"):
		return ""
	return "tap"

func _show_upgrades() -> void:
	screen = SCREEN_UPGRADES
	alive = false
	var levels := PackedInt32Array()
	for id in Upgrades.IDS:
		levels.append(Save.upgrade_level(id))
	hud.show_upgrades(Save.coins, levels)

## Buy the next level of an upgrade: coins, saved, and visible on the airport (the radar re-frames the view).
func buy_upgrade(id: String) -> bool:
	if not Save.buy_upgrade(id):
		return false
	airfield.show_upgrades()
	hud.flash(Color(0.4, 1.0, 0.6))
	var vp := get_viewport().get_visible_rect().size
	hud.popup("%s level %d!" % [Upgrades.upgrade_name(id), Save.upgrade_level(id)], Color(0.6, 1.0, 0.7), Vector2(vp.x * 0.5, vp.y * 0.2))
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(40)
	if screen == SCREEN_UPGRADES:
		_show_upgrades()
	return true

# ---------- Cosmetics, daily shift, ads, debug ----------

## Dress the airport and aircraft in what is equipped (theme, livery, pilot).
func apply_cosmetics() -> void:
	var ti := Cosmetics.theme_index(Save.equipped_id("theme"))
	var li := Cosmetics.livery_index(Save.equipped_id("livery"))
	airfield.apply_theme(ti)
	var t: Dictionary = Cosmetics.THEMES[ti]
	_env.background_color = t["bg"]
	_env.ambient_light_color = t["ambient"]
	_env.ambient_light_energy = t["ambient_energy"]
	sun.light_energy = t["sun"]
	traffic.set_livery(li)
	diorama.traffic.set_livery(li)

func _show_shop() -> void:
	screen = SCREEN_SHOP
	alive = false
	var cards: Array = []
	var kind := "theme" if shop_tab == 0 else "livery"
	var n := Cosmetics.THEME_COUNT if shop_tab == 0 else Cosmetics.LIVERY_COUNT
	for i in n:
		var d: Dictionary = Cosmetics.THEMES[i] if shop_tab == 0 else Cosmetics.LIVERIES[i]
		var owned := Save.owns(kind, d["id"])
		var state := 0
		var sub := ""
		var cost := -1
		if Save.equipped_id(kind) == d["id"]:
			state = 2
			sub = "In use"
		elif owned:
			sub = "Owned"
		else:
			cost = d["cost"]
			state = 0 if Save.coins >= d["cost"] else 1
		cards.append({"id": "%s:%d" % [kind, i], "title": d["name"], "sub": sub, "state": state, "icon": (100 + i) if shop_tab == 0 else d["animal"], "cost": cost})
	hud.show_list("SHOP", Save.coins, [
		{"id": "shop_tab:0", "title": "THEMES", "selected": shop_tab == 0},
		{"id": "shop_tab:1", "title": "LIVERIES", "selected": shop_tab == 1}], cards)

## Tap a shop card: equip it if owned, otherwise buy (and equip) it.
func shop_pick(kind: String, i: int) -> bool:
	var d: Dictionary = Cosmetics.THEMES[i] if kind == "theme" else Cosmetics.LIVERIES[i]
	var ok := false
	if Save.owns(kind, d["id"]):
		ok = Save.equip(kind, d["id"])
	else:
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

## Today's seeded shift: the airport and the arrivals are the same for everyone today.
func start_daily() -> void:
	daily_mode = true
	bad_mode = false
	airport = Save.today() % Airports.COUNT
	begin_shift()

## Bad Pilot Day: a second daily challenge. Every aircraft is a student pilot, go-arounds are very likely and every
## landing pays big. Its own airport, best score and streak.
func start_bad_day() -> void:
	daily_mode = true
	bad_mode = true
	airport = (Save.today() + 3) % Airports.COUNT
	begin_shift()

## The star thresholds of this shift (Bad Pilot Day pays more, so it asks for more).
func _thresholds() -> Array:
	var th := Tuning.star_thresholds().duplicate()
	if bad_mode:
		for i in th.size():
			th[i] = roundi(th[i] * Tuning.bad_day_threshold_mult)
	return th

## Start a shift, with an interstitial ad first if one is due (never in the middle of a shift).
func begin_shift() -> void:
	if int(Save.ads.get("since", 0)) >= Tuning.interstitial_every_shifts:
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
	Save.daily = {}
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
	select_airport(i)
	Airports.current = airport           # (the field behind the menu follows)
	airfield.select(airport)
	airfield.show_active(wind)
	_show_menu()

func _show_select() -> void:
	screen = SCREEN_SELECT
	alive = false
	var open := PackedByteArray()
	var stars := PackedInt32Array()
	var best := PackedInt32Array()
	for i in Airports.COUNT:
		open.append(1 if Save.airport_open(i) else 0)
		stars.append(Save.stars_of(i))
		best.append(Save.best_for(i))
	hud.show_select(Save.stars_total(), open, stars, best, airport)

func _touch_move(index: int, pos: Vector2) -> void:
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
	var pressed_id := hud.pressed_id()
	hud.release()
	if pressed_id != "" and screen != SCREEN_PLAY and hud.button_at(pos) == pressed_id:
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
	camera.size = view_size
	camera.position = Vector3(0, cos(tilt), sin(tilt)) * 30.0
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
