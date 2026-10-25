extends SceneTree
## One system at a time at 60, 30 and 20 steps a second: does each give the same answer whatever the frame rate? (The frame-delta clamp
## is 1/20 s, so the game must run the same at 20 fps as at 60.) Path following, a landing, circling, the timers, the go-around warning,
## taxiing, and the detections that could "tunnel" at a big step: a conflict between two aircraft and a flight into a storm cell.
## Exits non-zero when a system differs from its 60 fps answer by more than its tolerance.
##   godot --headless --path . --script tools/step_micro.gd

const FPSES := [60, 30, 20]
var main: Node
var tr
var failed := false
var events := []

func _initialize() -> void:
	var save = root.get_node("Save")
	save.path = "user://step_micro_save.json"
	save.reset_all()
	root.get_node("Tuning").ad_stub_seconds = 0.0
	root.get_node("Tuning").intro_logo = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var guard := 0
	while (guard < 3 or main._warming) and guard < 3000:
		await process_frame
		guard += 1
	main.select_airport(2)
	Airports.current = 2
	main.restart()
	tr = main.traffic
	tr.auto_spawn = false
	tr.grace_until = 0.0
	tr.crashed.connect(func(_p, _k): events.append("crash"))
	tr.conflict.connect(func(_a, _b): events.append("conflict"))
	tr.timed_out.connect(func(_p): events.append("timeout"))
	tr.landed.connect(func(_p): events.append("landed"))
	tr.go_around.connect(func(_p, _r): events.append("go_around"))
	_run("path following: seconds to fly a zig-zag, and where it ends", _follow, 0.01)
	_run("a landing: seconds from the path's end to 'landed'", _landing, 0.02)
	_run("circling: where a held aircraft is after 7 s (x, y)", _circle, 0.01)
	_run("the timer: seconds until an aircraft that is never helped diverts", _timer, 0.01)
	_run("the go-around warning: seconds from the warning to the go-around", _telegraph, 0.01)
	_run("taxiing: seconds from landing to the parking place", _taxi, 0.01)
	_run("a head-on pass at a lateral offset: how many of 60 offsets are conflicts", _conflicts, 0.0)
	_run("a grazing head-on pass (lateral offsets just inside the conflict distance): how many of 60 are conflicts", _grazing, 0.0)
	_run("a flight past a storm cell's edge: how many of 60 offsets crash", _storm, 0.0)
	_run("the wind and weather clocks: seconds until the first wind shift", _wind, 0.02)
	quit(1 if failed else 0)

func _reset() -> void:
	main.restart()
	tr.auto_spawn = false
	tr.release_all()
	tr.run_time = 40.0
	tr.half_w = 5.0
	tr.half_h = 11.0
	tr.grace_until = 0.0
	events.clear()

## Run `f(dt)` at every frame rate; each returns an Array of numbers; they must agree with the 60 fps answer within `tol` (a fraction,
## or for tol 0 exactly one step's worth of tolerance: the counts may differ by 2 of 60).
func _run(title: String, f: Callable, tol: float) -> void:
	var base: Array = []
	var line := ""
	var ok := true
	for fps in FPSES:
		_reset()
		var r: Array = f.call(1.0 / fps)
		if fps == 60:
			base = r
		line += "  %d fps: %s" % [fps, str(r.map(func(x): return snappedf(x, 0.001)))]
		for k in r.size():
			var a: float = base[k]
			var b: float = r[k]
			var allowed := (2.0 if tol == 0.0 else maxf(absf(a) * tol, 0.06))
			if absf(a - b) > allowed:
				ok = false
	print("%s %s\n   %s" % ["ok  " if ok else "FAIL", title, line])
	if not ok:
		failed = true

func _step(dt: float) -> void:
	main.step(dt)

func _follow(dt: float) -> Array:
	var p = tr.place(0, Vector2(-3.0, 6.0), 0.0, Aircraft.Type.MEDIUM)
	var path := [Vector2(-3, 3), Vector2(-1, 1), Vector2(-2.5, -1), Vector2(0, -3), Vector2(2, -1), Vector2(2, 4)]
	for q in path:
		p.push(q)
	var t := 0.0
	while p.count > 0 and t < 60.0:
		_step(dt)
		t += dt
	return [t, p.pos.x, p.pos.y]

func _landing(dt: float) -> Array:
	main.wind.from_deg = 0.0
	var thr: Vector2 = Airports.end_threshold(0, 0)
	var dir: Vector2 = Airports.end_dir(0, 0)
	var p = tr.place(0, thr - dir * 3.0, atan2(dir.x, -dir.y), Aircraft.Type.MEDIUM)
	p.push(thr - dir * 1.5)
	p.push(thr)
	p.push(Airports.end_far(0, 0))
	p.cleared = true
	p.land_end = 0
	var t := 0.0
	while not events.has("landed") and t < 30.0:
		_step(dt)
		t += dt
	return [t, 1.0 if events.has("landed") else 0.0]

func _circle(dt: float) -> Array:
	var p = tr.place(0, Vector2(-4.0, 6.0), 0.0, Aircraft.Type.SMALL)
	tr.toggle_hold(p)
	var t := 0.0
	while t < 7.0 - 0.0001:
		_step(dt)
		t += dt
	return [p.pos.x, p.pos.y]

func _timer(dt: float) -> Array:
	var p = tr.place(0, Vector2(-4.0, 8.0), 0.0, Aircraft.Type.MEDIUM)
	p.timer_left = 6.0
	p.timer_max = 6.0
	var t := 0.0
	while not events.has("timeout") and t < 30.0:
		_step(dt)
		t += dt
	return [t]

func _telegraph(dt: float) -> Array:
	var p = tr.place(0, Vector2(0.0, 4.0), 0.0, Aircraft.Type.MEDIUM)
	p.ga_pending = true
	p.ga_t = 1.0
	p.ga_reason = 0
	p.cleared = true
	p.runway = 0
	p.land_end = 0
	p.pts[0] = Vector2(0.0, 3.0)
	p.count = 1
	var t := 0.0
	while not events.has("go_around") and t < 5.0:
		_step(dt)
		t += dt
	return [t]

func _taxi(dt: float) -> Array:
	main.select_airport(2)
	var af = main.airfield
	var slot = af.begin_taxi(Aircraft.Type.MEDIUM, Aircraft.Kind.RUNWAY, 0, 0, false, 1)
	var t := 0.0
	while not af.taxis.is_empty() and t < 200.0:
		af.step_taxi(dt)
		t += dt
	return [t]

func _pass(dt: float, lo: float, hi: float, _cd: float) -> Array:
	var n := 0
	for k in 60:
		_reset()
		tr._god = false
		var off := lo + (hi - lo) * float(k) / 59.0         # lateral offset (the conflict distance is 0.9)
		var a = tr.place(0, Vector2(0.0, 8.0), 0.0, Aircraft.Type.JET)
		var b = tr.place(1, Vector2(off, -8.0), PI, Aircraft.Type.JET)
		a.timer_left = 999.0
		b.timer_left = 999.0
		var t := 0.0
		while not events.has("conflict") and t < 6.0:
			_step(dt)
			t += dt
		if events.has("conflict"):
			n += 1
			if k == 59:
				print("   debug k=59 conflict at t=%.2f a=%s b=%s cd=%s" % [t, str(a.pos), str(b.pos), str(root.get_node("Tuning").conflict_distance)])
	return [float(n)]

func _grazing(dt: float) -> Array:
	return _pass(dt, 0.8, 0.9, 0.9)

func _conflicts(dt: float) -> Array:
	return _pass(dt, 0.5, 2.3, 0.9)

func _storm(dt: float) -> Array:
	var n := 0
	for k in 60:
		_reset()
		tr._god = false
		var r := Tuning_radius()
		var off := r + 0.05 + float(k) * 0.002         # the flight offset from the cell centre: either side of its edge (r + the margin 0.1)
		tr.add_storm(Vector2(0.0, 0.0), r, Vector2.ZERO)
		var p = tr.place(0, Vector2(-5.0, off), PI * 0.5, Aircraft.Type.JET)
		p.timer_left = 999.0
		var t := 0.0
		while not events.has("crash") and t < 8.0 and p.active():
			_step(dt)
			t += dt
		if events.has("crash"):
			n += 1
		tr.clear_hazards() if tr.has_method("clear_hazards") else null
	return [float(n)]

func Tuning_radius() -> float:
	return 1.5

func _wind(dt: float) -> Array:
	main.wind.countdown = 20.0
	var from0: float = main.wind.from_deg
	var t := 0.0
	while main.wind.from_deg == from0 and t < 60.0:
		_step(dt)
		t += dt
	return [t]
