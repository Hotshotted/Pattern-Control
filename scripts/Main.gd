class_name Main
extends Node3D
## Wires the game together and runs the three screens (menu -> play -> game over -> play ...).
## Restarting is IN PLACE: nothing is reloaded, created or freed; only the game state resets.

const SCREEN_MENU := 0
const SCREEN_PLAY := 1
const SCREEN_OVER := 2
const SCREEN_SELECT := 3
const SCREEN_UPGRADES := 4
const SCREEN_SHOP := 5
const SCREEN_AD := 6
const SCREEN_CONTINUE := 7

const HEADER_CONFLICT := "MID-AIR\nCONFLICT"
const HEADER_STRIKES := "3 STRIKES"
const HEADER_DONE := "SHIFT\nCOMPLETE"

@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var airfield: Airfield = $Airfield
@onready var traffic: Traffic = $Traffic
@onready var ribbons: PathRibbons = $Ribbons
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
var daily_mode := false               # playing today's seeded daily shift
var shop_tab := 0                     # 0 themes, 1 liveries
var _ad_kind := ""
var _ad_left := 0.0
var _ad_done: Callable
var _continue_used := false           # the rewarded "undo the conflict" is once per shift
var _doubled := false                 # the rewarded "double coins" is once per shift
var _conflict_a: Aircraft
var _conflict_b: Aircraft
var _conflict_header := ""
var _conflict_reason := ""
var ads_shown := 0                    # (tests) how many fake ads have played
var streak := 0                       # landings within STREAK_WINDOW_MS of each other
var shift_coins := 0                  # coins earned so far this shift (paid out when it ends)
var last_result := {}                 # what the last shift ended with (header, reason, coins, stars...)
var over_reason := ""
var over_header := ""
var new_best := false
var elapsed := 0.0                    # seconds into this run

var _warming := false
var _warmed := false
var _death_ms := 0
var _last_land_ms := 0
var _haptic_warmed := false
var _env: Environment
var view_size := 10.0                 # world units across the screen width (the radar upgrade widens it, smoothly)
# touch
var _drag_index := -1
var _drag_plane: Aircraft = null
var _drag_active := false
var _touch_start := Vector2.ZERO
var _touch_ms := 0
var _last_world := Vector2.ZERO

const STREAK_WINDOW_MS := 5000

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
	wind.warned.connect(_on_wind_warned)
	wind.shifted.connect(_on_wind_shifted)
	traffic.inactive_end.connect(_on_inactive_end)
	traffic.rerouted.connect(_on_rerouted)
	traffic.crashed.connect(_on_crashed)
	traffic.go_around.connect(_on_go_around)
	traffic.runway_conflict.connect(_on_runway_conflict)
	traffic.refused.connect(_on_refused)
	traffic.revealed.connect(_on_revealed)
	wind.reopened.connect(_on_runway_reopened)
	weather.warned.connect(_on_weather_warned)
	weather.started.connect(_on_weather_started)
	weather.ended.connect(_on_weather_ended)
	traffic.appeared.connect(_on_appeared)
	ribbons.traffic = traffic
	overlay.camera = camera
	traffic.landed.connect(_on_landed)
	traffic.conflict.connect(_on_conflict)
	traffic.timed_out.connect(_on_timed_out)
	traffic.cleared.connect(_on_cleared)
	traffic.wrong_runway.connect(_on_wrong_runway)
	airport = Save.selected_airport if Save.airport_open(Save.selected_airport) else 0
	Airports.current = airport
	airfield.select(airport)
	traffic.load_terrain()
	shift.reset(Airports.goals())
	wind.start(rng_env)
	airfield.show_active(wind)
	hud.set_wind(wind.from_deg, wind.toward_deg())
	airfield.show_upgrades()
	apply_cosmetics()
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
		_show_menu()
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
	overlay.clear()
	airfield.reset()
	hud.end_prewarm()
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
	_show_menu()

## Start a fresh shift IN PLACE.
func restart() -> void:
	screen = SCREEN_PLAY
	alive = true
	score = 0
	streak = 0
	shift_coins = 0
	elapsed = 0.0
	new_best = false
	over_reason = ""
	over_header = ""
	last_result = {}
	sim_time = 0.0
	_run_start_ms = Time.get_ticks_msec()
	_paused_total_ms = 0
	_skip_frames = 0
	_last_land_ms = 0
	_drag_index = -1
	_drag_plane = null
	_drag_active = false
	_continue_used = false
	_doubled = false
	if daily_mode:
		var seed_v := (Save.today() * 2654435761) & 0x7fffffff
		traffic.rng.seed = seed_v
		rng_env.seed = seed_v ^ 0x5bd1e995
	else:
		traffic.rng.randomize()
		rng_env.randomize()
	traffic.grace_until = 0.0
	_note_event("shift started")
	get_tree().paused = false
	Airports.current = airport
	airfield.select(airport)
	traffic.load_terrain()
	shift.reset(Airports.goals())
	fx.clear()
	overlay.clear()
	airfield.reset()
	traffic.half_w = view_size * 0.5
	traffic.half_h = _half_height()
	traffic.release_all()
	traffic.spawn_until = Tuning.shift_seconds
	wind.start(rng_env)
	weather.start()
	_event_key = ""
	airfield.show_active(wind)
	hud.reset_for_run(Save.best_for(airport))
	hud.set_wind(wind.from_deg, wind.toward_deg())
	hud.set_shift(shift, int(Tuning.max_strikes))

func _show_menu() -> void:
	screen = SCREEN_MENU
	alive = false
	daily_mode = false
	hud.daily_label = "DAILY SHIFT"
	hud.daily_sub = "done today - streak %d" % Save.daily_streak() if Save.daily_done_today() else "streak %d   bonus +%d" % [Save.daily_streak(), _daily_bonus(Save.daily_streak() + 1)]
	hud.show_menu(Airports.airport_name(airport), Save.coins, Save.stars_total(), Save.best_for(airport), Airports.tag(airport))

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
			if not _suspended:
				_suspended = true
				_paused_since_ms = Time.get_ticks_msec()
				_note_event("window went to the background")
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _suspended:
				_suspended = false
				_paused_total_ms += Time.get_ticks_msec() - _paused_since_ms
				_skip_frames = Tuning.resume_skip_frames
				_cancel_drag()
				_note_event("window came back")

func run_wall_time() -> float:
	return maxf((Time.get_ticks_msec() - _run_start_ms - _paused_total_ms) / 1000.0, 0.0)

func _process(raw_delta: float) -> void:
	view_size = lerpf(view_size, Tuning.view_size(), 1.0 - exp(-raw_delta * 3.0))   # the radar re-frames the view smoothly
	_update_camera()
	traffic.half_w = view_size * 0.5
	traffic.half_h = _half_height()
	if screen == SCREEN_AD:
		_tick_ad(raw_delta)
	if _warming or not alive:
		return
	var delta := _frame_delta(raw_delta)
	if DebugFlags.perf_enabled():
		hud.set_clock(sim_time, run_wall_time())
	if delta <= 0.0:
		return
	sim_time += delta
	elapsed += delta
	step(delta)

## One simulation step (the tests call this directly).
func step(delta: float) -> void:
	traffic.step(delta)
	var worst := 0.0
	for p in traffic.planes:
		if p.active():
			worst = maxf(worst, p.warn)
	hud.set_alert(alive and worst > 0.55)
	hud.set_shift_fraction(traffic.run_time / maxf(Tuning.shift_seconds, 1.0))
	if traffic.run_time < Tuning.shift_seconds or weather.phase != Weather.Phase.IDLE:
		weather.step(delta, traffic.run_time / maxf(Tuning.shift_seconds, 1.0), rng_env, wind)
		var key := "%d:%d" % [weather.phase, ceili(weather.left)]
		if key != _event_key:    # (the banner text is only rebuilt when the second changes)
			_event_key = key
			hud.set_event_banner(weather.banner(), weather.phase == Weather.Phase.WARN)
	if traffic.run_time < Tuning.shift_seconds:
		wind.step(delta, traffic.run_time / maxf(Tuning.shift_seconds, 1.0), rng_env)
		if wind.warning:
			hud.set_wind_warning(wind.next_deg, ceili(wind.countdown))
	if _drag_active and (_drag_plane == null or not _drag_plane.active()):
		_cancel_drag()
	# The shift is over once the planes have stopped coming and the field is clear.
	if alive and traffic.run_time >= Tuning.shift_seconds and traffic.active_count() == 0:
		_end_shift(HEADER_DONE, "Shift complete!", true)

# ---------- Game events ----------

func _on_landed(p: Aircraft) -> void:
	if not alive:
		return
	score += 1
	shift_coins += Tuning.coins_per_landing
	var vip_paid := p.vip and p.vip_ok
	shift.on_landed(p.type, vip_paid, p.emergency)
	var now := Time.get_ticks_msec()
	streak = streak + 1 if _last_land_ms != 0 and now - _last_land_ms < STREAK_WINDOW_MS else 1
	_last_land_ms = now
	var col := Airports.land_color(p.tkind, p.runway)
	var land_at := p.pos
	hud.set_landed(score, true)
	hud.set_shift(shift, int(Tuning.max_strikes))
	fx.burst(land_at, col)
	fx.burst(land_at, Color.WHITE)
	overlay.ripple(land_at, col, 1.0)
	overlay.ripple(land_at, Color.WHITE, 0.6)
	if p.tkind == Aircraft.Kind.RUNWAY:
		airfield.glow(p.runway, p.land_end)
	var text := "+1"
	var tcol := Color(1, 1, 1)
	if streak >= 3:
		text = "+1  x%d" % streak
		tcol = col.lerp(Color.WHITE, 0.4)
	if p.emergency:
		shift_coins += Tuning.emergency_bonus_coins
		text = "EMERGENCY SAVED! +%d" % Tuning.emergency_bonus_coins
		tcol = Color(1.0, 0.45, 0.4)
		fx.burst(land_at, Color(1.0, 0.3, 0.25), true)
	elif p.vip:
		if vip_paid:
			shift_coins += Tuning.vip_bonus_coins
			text = "VIP +%d" % Tuning.vip_bonus_coins
			tcol = Color(1.0, 0.84, 0.15)
		else:
			text = "VIP (no bonus)"
			tcol = Color(0.7, 0.7, 0.72)
	hud.popup(text, tcol, overlay.world_to_screen(land_at) + Vector2(0, -80))
	_star_feedback(land_at)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms)

## A goal was just reached: a gold burst and a "STAR!" popup.
func _star_feedback(at: Vector2) -> void:
	if shift.just_met == 0:
		return
	fx.burst(at, Color(1.0, 0.84, 0.15), true)
	overlay.ripple(at, Color(1.0, 0.84, 0.15), 1.6)
	var vp := get_viewport().get_visible_rect().size
	hud.popup("STAR!", Color(1.0, 0.84, 0.15), Vector2(vp.x * 0.5, vp.y * 0.3))

## An aircraft flew into terrain or a storm cell: lost, and a strike.
func _on_crashed(p: Aircraft, kind: int) -> void:
	if not alive:
		return
	shift.on_strike()
	hud.set_shift(shift, int(Tuning.max_strikes))
	fx.burst(p.pos, Color(0.85, 0.6, 0.4), true)
	overlay.ripple(p.pos, Color(1, 0.35, 0.2), 1.1)
	hud.popup("Struck by storm!" if kind == 1 else "Crashed!", Color(1, 0.4, 0.3) if kind == 0 else Color(0.8, 0.7, 1.0), overlay.world_to_screen(p.pos))
	hud.flash(Color(1, 0.3, 0.1))
	if shift.strikes >= int(Tuning.max_strikes):
		_end_shift(HEADER_STRIKES, "%d strikes." % shift.strikes, false)

## The runway was still busy: the aircraft goes around (no strike, but time passes).
func _on_go_around(p: Aircraft) -> void:
	hud.popup("Go around!", Color(1, 0.85, 0.3), overlay.world_to_screen(p.pos) + Vector2(0, -60))
	overlay.ripple(p.pos, Color(1, 0.85, 0.3), 0.7)

func _on_runway_conflict(a: Aircraft, b: Aircraft) -> void:
	if not alive:
		return
	var mid := (a.pos + b.pos) * 0.5
	fx.burst(mid, Color(1.0, 0.5, 0.1), true)
	overlay.ripple(mid, Color(1, 0.3, 0.2), 1.3)
	_conflict_or_end(HEADER_CONFLICT, "Simultaneous landings on crossing runways.", a, b)

## The aircraft can't follow a path or tap (and the reason is shown where it happened).
func _on_refused(_p: Aircraft, text: String, at: Vector2) -> void:
	overlay.ripple(at, Color(1, 0.6, 0.25), 0.6)
	hud.popup(text, Color(1, 0.75, 0.35), overlay.world_to_screen(at) + Vector2(0, 90))

## First time a kind of aircraft is on screen: a one-line tip. Emergencies announce themselves every time.
const TIPS := {
	"glider": "Glider: no engine. It can't hold and only gets one path.",
	"heli": "Helicopter: lands on the helipad only. Tap to hover.",
	"jet": "Jet: fast, and needs a long runway.",
	"seaplane": "Seaplane: lands on the water lane.",
	"emergency": "Emergency! Flashing aircraft can use any suitable runway. Land them fast.",
	"vip": "VIP flight: bonus coins, but not if you hold it.",
}

func _on_appeared(p: Aircraft) -> void:
	if p.emergency:
		hud.popup("EMERGENCY", Color(1.0, 0.3, 0.25), overlay.world_to_screen(p.pos))
	var key := ""
	if p.emergency:
		key = "emergency"
	elif p.vip:
		key = "vip"
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
	if key != "" and not Save.tips_seen.has(key):
		Save.tips_seen[key] = true
		Save.write_file()
		hud.show_tip(TIPS[key])

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
			var n := 1 + (1 if rng_env.randf() < 0.3 + 0.5 * traffic.run_time / maxf(Tuning.shift_seconds, 1.0) else 0)
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

## An aircraft came out of the fog.
func _on_revealed(p: Aircraft) -> void:
	overlay.ripple(p.pos, Color(0.9, 0.95, 1.0), 0.5)

## Debug (?tune): announce a weather event now.
func trigger_weather(kind: String) -> void:
	weather.trigger(kind, rng_env, wind)

func _on_rerouted(p: Aircraft) -> void:
	hud.popup("Re-route!", Color(1, 0.35, 0.3), overlay.world_to_screen(p.pos) + Vector2(0, -60))

func _on_conflict(a: Aircraft, b: Aircraft) -> void:
	if not alive:
		return
	var mid := (a.pos + b.pos) * 0.5
	fx.burst(mid, Color(1.0, 0.5, 0.1), true)
	fx.burst(mid, Color(1.0, 0.15, 0.1), true)
	overlay.ripple(mid, Color(1, 0.3, 0.2), 1.3)
	_conflict_or_end(HEADER_CONFLICT, "Two aircraft got too close.", a, b)

## An aircraft's timer ran out: it is diverted, and that is a strike.
func _on_timed_out(p: Aircraft) -> void:
	if not alive:
		return
	shift.on_strike()
	hud.set_shift(shift, int(Tuning.max_strikes))
	hud.popup("Diverted", Color(1, 0.55, 0.3), overlay.world_to_screen(p.pos))
	overlay.ripple(p.pos, Color(1, 0.5, 0.2), 1.0)
	hud.flash(Color(1, 0.5, 0.1))
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(80)
	if shift.strikes >= int(Tuning.max_strikes):
		_end_shift(HEADER_STRIKES, "%d aircraft diverted." % shift.strikes, false)

## The shift is over (complete, 3 strikes or a conflict): stars, coins, save, results screen.
func _end_shift(header: String, reason: String, complete: bool) -> void:
	if screen != SCREEN_PLAY and screen != SCREEN_CONTINUE:
		return
	alive = false
	screen = SCREEN_OVER
	_death_ms = Time.get_ticks_msec()
	over_header = header
	over_reason = reason
	shift.finish(complete)
	var first_stars := 0
	var coins := shift_coins
	for i in 3:
		if shift.state(i) == Shift.Goal.MET:
			coins += Tuning.coins_per_star
			if not daily_mode and Save.award_star(airport, i):    # (the daily shift doesn't earn permanent stars)
				first_stars += 1
				coins += Tuning.coins_first_star_bonus
	var daily_note := ""
	if daily_mode and shift.stars() >= 1 and not Save.daily_done_today():
		var streak_now := Save.daily_complete(shift.landed)
		var bonus := _daily_bonus(streak_now)
		coins += bonus
		daily_note = "\nDaily bonus +%d  (streak %d)" % [bonus, streak_now]
	Save.add_coins(coins)
	new_best = false if daily_mode else Save.submit_best(airport, shift.landed)
	Save.shifts_played += 1
	Save.ads["since"] = int(Save.ads.get("since", 0)) + 1
	Save.write_file()
	reason += daily_note
	last_result = {"header": header, "reason": reason, "coins": coins, "stars": shift.stars(), "first_stars": first_stars, "complete": complete, "new_best": new_best}
	_cancel_drag()
	hud.set_alert(false)
	hud.set_event_banner("")
	hud.flash(Color(1, 0.84, 0.15) if complete else Color(1, 0.1, 0.1))
	hud.set_shift(shift, int(Tuning.max_strikes))
	var lv: Dictionary = Cosmetics.LIVERIES[Cosmetics.livery_index(Save.equipped_id("livery"))]
	hud.show_results(header, reason, shift, coins, Save.coins, Save.best_for(airport), new_best, lv["animal"], "%s: %s" % [lv["pilot"], lv["quote"]])
	hud.set_double_button(coins > 0, coins)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(150)

# ---------- Input ----------

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# A touch on the tuning panel's TUNE button belongs to the button, not the game.
	if TunePanel.button_hit(event.position):
		return
	if not _haptic_warmed:
		_haptic_warmed = true
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
	if screen != SCREEN_PLAY:
		var id := hud.button_at(pos)
		if id != "":
			_on_button(id)
			return
		if hud.ui_hit(pos):
			return   # a disabled button
	if screen == SCREEN_MENU or (screen == SCREEN_OVER and Time.get_ticks_msec() - _death_ms > 600):
		begin_shift()
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
	_touch_start = w
	_touch_ms = Time.get_ticks_msec()
	_last_world = w
	overlay.selected = p

## A button / card on the menu, results or airport screen.
func _on_button(id: String) -> void:
	if id == "airports":
		_show_select()
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
	elif id == "ad_continue":
		show_ad("Reward: undo the conflict and keep flying", func(): _resume_after_conflict(), SCREEN_PLAY)
	elif id == "end_shift":
		_end_shift(_conflict_header, _conflict_reason, false)
	elif id == "ad_double":
		show_ad("Reward: double your coins", func(): _double_coins(), SCREEN_OVER)
	elif id.begins_with("upg:"):
		buy_upgrade(id.substr(4))
	elif id == "back" or id == "menu":
		_show_menu()
	elif id.begins_with("airport:"):
		daily_mode = false
		select_airport(int(id.substr(8)))
		begin_shift()

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
	hud.set_pilot(Cosmetics.LIVERIES[li]["animal"])

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
		if Save.equipped_id(kind) == d["id"]:
			state = 2
			sub = "EQUIPPED"
		elif owned:
			sub = "Owned - tap to equip"
		elif Save.coins >= d["cost"]:
			sub = "Tap to buy: %d coins" % d["cost"]
		else:
			state = 1
			sub = "%d coins (need %d more)" % [d["cost"], d["cost"] - Save.coins]
		var title: String = d["name"] if shop_tab == 0 else "%s  -  %s" % [d["name"], d["pilot"]]
		cards.append({"id": "%s:%d" % [kind, i], "title": title, "sub": sub, "state": state, "icon": (100 + i) if shop_tab == 0 else d["animal"]})
	hud.show_list("SHOP", "Coins %d" % Save.coins, [
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
	airport = Save.today() % Airports.COUNT
	begin_shift()

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

## A conflict: offer the rewarded "undo it and keep going" once per shift, else the shift ends.
func _conflict_or_end(header: String, reason: String, a: Aircraft, b: Aircraft) -> void:
	if _continue_used:
		_end_shift(header, reason, false)
		return
	alive = false
	screen = SCREEN_CONTINUE
	_conflict_a = a
	_conflict_b = b
	_conflict_header = header
	_conflict_reason = reason
	_cancel_drag()
	hud.set_alert(false)
	hud.flash(Color(1, 0.1, 0.1))
	hud.show_continue(header, reason)

## After the ad: pull the two aircraft apart, give them a moment's grace and carry on.
func _resume_after_conflict() -> void:
	_continue_used = true
	var a := _conflict_a
	var b := _conflict_b
	if a != null and b != null and a.active() and b.active():
		var d := a.pos - b.pos
		d = d.normalized() if d.length() > 0.01 else Vector2(1, 0)
		a.pos += d * Tuning.warn_distance * 0.6
		b.pos -= d * Tuning.warn_distance * 0.6
		for p in [a, b]:
			p.clear_path()
			if p.state == Aircraft.State.HOLD:
				p.state = Aircraft.State.FLY
				p.hovering = false
		a.heading = atan2(d.x, -d.y)
		b.heading = atan2(-d.x, d.y)
		a.vis_heading = a.heading
		b.vis_heading = b.heading
	traffic.grace_until = traffic.run_time + 2.5
	hud.resume_play()
	screen = SCREEN_PLAY
	alive = true

## Results: the rewarded "double the coins" (once per shift).
func _double_coins() -> void:
	_doubled = true
	Save.add_coins(last_result["coins"])
	Save.write_file()
	last_result["coins"] *= 2
	var lv: Dictionary = Cosmetics.LIVERIES[Cosmetics.livery_index(Save.equipped_id("livery"))]
	hud.show_results(last_result["header"], last_result["reason"], shift, last_result["coins"], Save.coins, Save.best_for(airport), last_result["new_best"], lv["animal"], "%s: %s" % [lv["pilot"], lv["quote"]], true)
	hud.set_double_button(false, 0)

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
	Save.write_file()

func select_airport(i: int) -> void:
	airport = clampi(i, 0, Airports.COUNT - 1)
	Save.selected_airport = airport
	Save.write_file()

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
	if index != _drag_index or _drag_plane == null:
		return
	var w := overlay.screen_to_world(pos)
	_last_world = w
	feed_drag(w)

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
	if traffic.extend_path(_drag_plane, w):
		_cancel_drag()

func _touch_up(index: int, pos: Vector2) -> void:
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

func _update_camera() -> void:
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
