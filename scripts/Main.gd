class_name Main
extends Node3D
## Wires the game together and runs the three screens (menu -> play -> game over -> play ...).
## Restarting is IN PLACE: nothing is reloaded, created or freed; only the game state resets.

const SCREEN_MENU := 0
const SCREEN_PLAY := 1
const SCREEN_OVER := 2
const SCREEN_SELECT := 3

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
var score := 0                        # aircraft landed this shift (the big number)
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
	wind.start(traffic.rng)
	airfield.show_active(wind)
	hud.set_wind(wind.from_deg, wind.toward_deg())
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
	_note_event("shift started")
	get_tree().paused = false
	Airports.current = airport
	airfield.select(airport)
	traffic.load_terrain()
	shift.reset(Airports.goals())
	fx.clear()
	overlay.clear()
	airfield.reset()
	traffic.half_w = Tuning.ortho_size * 0.5
	traffic.half_h = _half_height()
	traffic.release_all()
	traffic.spawn_until = Tuning.shift_seconds
	wind.start(traffic.rng)
	airfield.show_active(wind)
	hud.reset_for_run(Save.best_for(airport))
	hud.set_wind(wind.from_deg, wind.toward_deg())
	hud.set_shift(shift, int(Tuning.max_strikes))

func _show_menu() -> void:
	screen = SCREEN_MENU
	alive = false
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
	_update_camera()
	traffic.half_w = Tuning.ortho_size * 0.5
	traffic.half_h = _half_height()
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
	if traffic.run_time < Tuning.shift_seconds:
		wind.step(delta, traffic.run_time / maxf(Tuning.shift_seconds, 1.0), traffic.rng)
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
	shift.on_landed(p.type)
	var now := Time.get_ticks_msec()
	streak = streak + 1 if _last_land_ms != 0 and now - _last_land_ms < STREAK_WINDOW_MS else 1
	_last_land_ms = now
	var col := Airports.rw_color(p.runway)
	var land_at := p.pos
	hud.set_landed(score, true)
	hud.set_shift(shift, int(Tuning.max_strikes))
	fx.burst(land_at, col)
	fx.burst(land_at, Color.WHITE)
	overlay.ripple(land_at, col, 1.0)
	overlay.ripple(land_at, Color.WHITE, 0.6)
	airfield.glow(p.runway, p.land_end)
	var text := "+1"
	var tcol := Color(1, 1, 1)
	if streak >= 3:
		text = "+1  x%d" % streak
		tcol = col.lerp(Color.WHITE, 0.4)
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

## An aircraft flew into terrain: lost, and a strike.
func _on_crashed(p: Aircraft) -> void:
	if not alive:
		return
	shift.on_strike()
	hud.set_shift(shift, int(Tuning.max_strikes))
	fx.burst(p.pos, Color(0.85, 0.6, 0.4), true)
	overlay.ripple(p.pos, Color(1, 0.35, 0.2), 1.1)
	hud.popup("Crashed!", Color(1, 0.4, 0.3), overlay.world_to_screen(p.pos))
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
	_end_shift(HEADER_CONFLICT, "Simultaneous landings on crossing runways.", false)

func _on_cleared(p: Aircraft) -> void:
	overlay.ripple(Airports.end_threshold(p.runway, p.land_end), Airports.rw_color(p.runway), 0.5)

func _on_wrong_runway(_p: Aircraft, runway: int) -> void:
	overlay.ripple(Airports.end_threshold(runway, 0), Color(1, 0.25, 0.2), 0.7)
	hud.popup("WRONG RUNWAY", Color(1, 0.4, 0.35), overlay.world_to_screen(Airports.rw_center(runway)) + Vector2(0, 120))

## A path reached an end the wind doesn't allow.
func _on_inactive_end(_p: Aircraft, runway: int, end: int) -> void:
	overlay.ripple(Airports.end_threshold(runway, end), Color(1, 0.6, 0.2), 0.7)
	hud.popup("Not into the wind", Color(1, 0.7, 0.3), overlay.world_to_screen(Airports.end_threshold(runway, end)) + Vector2(0, 100))

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

func _on_rerouted(p: Aircraft) -> void:
	hud.popup("Re-route!", Color(1, 0.35, 0.3), overlay.world_to_screen(p.pos) + Vector2(0, -60))

func _on_conflict(a: Aircraft, b: Aircraft) -> void:
	if not alive:
		return
	var mid := (a.pos + b.pos) * 0.5
	fx.burst(mid, Color(1.0, 0.5, 0.1), true)
	fx.burst(mid, Color(1.0, 0.15, 0.1), true)
	overlay.ripple(mid, Color(1, 0.3, 0.2), 1.3)
	_end_shift(HEADER_CONFLICT, "Two aircraft got too close.", false)

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
	if not alive:
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
			if Save.award_star(airport, i):
				first_stars += 1
				coins += Tuning.coins_first_star_bonus
	Save.add_coins(coins)
	new_best = Save.submit_best(airport, shift.landed)
	Save.shifts_played += 1
	Save.write_file()
	last_result = {"header": header, "reason": reason, "coins": coins, "stars": shift.stars(), "first_stars": first_stars, "complete": complete}
	_cancel_drag()
	hud.set_alert(false)
	hud.flash(Color(1, 0.84, 0.15) if complete else Color(1, 0.1, 0.1))
	hud.set_shift(shift, int(Tuning.max_strikes))
	hud.show_results(header, reason, shift, coins, Save.coins, Save.best_for(airport), new_best)
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
		restart()
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
	elif id == "back" or id == "menu":
		_show_menu()
	elif id.begins_with("airport:"):
		select_airport(int(id.substr(8)))
		restart()

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
		_drag_active = true
		traffic.begin_path(_drag_plane)
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
	camera.size = Tuning.ortho_size
	camera.position = Vector3(0, cos(tilt), sin(tilt)) * 30.0
	camera.rotation = Vector3(-(PI / 2 - tilt), 0, 0)

## The screen spans z = -half .. +half (stretched slightly by the camera tilt).
func _half_height() -> float:
	var vp := get_viewport().get_visible_rect().size
	return Tuning.ortho_size * 0.5 * vp.y / vp.x / cos(deg_to_rad(Tuning.camera_tilt_deg))

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
