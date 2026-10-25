extends SceneTree
## The "phone" check: a mid-shift (several aircraft, paths, a landed ramp) is rendered twice on a desktop GL, once normally and once as a
## phone with a 16-bit depth buffer would draw it (`lowz`: the depth range x256), and the two must be the same picture and have no
## magenta-ish pixel (r > 200, g < 80, b > 200: what a missing texture or a bad shader input looks like).
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script tools/mobile_check.gd -- [out=DIR]
## Exits non-zero on a failure; the two frames are saved when `out=` is given.

var main: Node
var out := ""

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _grab() -> Image:
	main.hud.skip_animations()
	await _frames(8)
	return root.get_viewport().get_texture().get_image()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DebugFlags.parse(["nowind", "nolife"])       # (a still field: only the depth range differs between the two frames)
	var save = root.get_node("Save")
	save.path = "user://mobile_check_save.json"
	save.reset_all()
	root.get_node("Tuning").ad_stub_seconds = 0.0
	root.get_node("Tuning").intro_logo = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var guard := 0
	while not main._warming and guard < 120:
		await process_frame
		guard += 1
	guard = 0
	while main._warming and guard < 6000:
		await process_frame
		guard += 1
	await _frames(30)
	main.select_airport(2)
	main.restart()
	var tr = main.traffic
	tr.auto_spawn = false
	tr.grace_until = 9999.0
	for k in 5:
		main.airfield.begin_taxi([2, 3, 2, 4, 2][k], 0, k % 2, k % 2, k == 3, -1)
	var spots := [Vector2(-3.0, -6.4), Vector2(0.8, -6.6), Vector2(-3.4, 6.2), Vector2(0.6, 6.4), Vector2(3.4, -4.6), Vector2(3.6, 6.8)]
	for k in 6:
		var p = tr.place(k % 2, spots[k], 0.5 * k - 0.4, [2, 3, 4, 1, 5, 0][k])
		p.timer_left = p.timer_max * (0.95 - 0.12 * k)
		if k % 2 == 0:
			var th: Vector2 = Airports.end_threshold(k % 2, 1)
			for j in 20:
				p.push(p.pos.lerp(th, float(j + 1) / 20.0))
			p.cleared = true
	for i in 200:
		main.step(1.0 / 60.0)
	main.hud.set_shift(main.shift)
	main.airfield.cur.lights.visible = false          # (the runway lights shimmer by the clock)
	main.set_process(false)                           # (nothing moves between the two frames)
	main.airfield.set_process(false)                  # (...not the runway lights, which the airfield would switch back on)
	main.diorama.active = false                       # (...nor the menu's scenic aircraft, which are still landing behind the field)
	main.diorama.set_process(false)
	main.diorama.traffic.release_all()
	var full := await _grab()                         # the whole picture, interface and marks too: for the magenta scan
	main.overlay.visible = false                      # the 3D field alone for the comparison (the marks pulse by the clock)
	main.hud.visible = false
	var normal := await _grab()
	DebugFlags.lowz = true
	await _frames(6)
	var phone := await _grab()
	DebugFlags.lowz = false
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
		full.save_png(out + "/full.png")
		normal.save_png(out + "/normal.png")
		phone.save_png(out + "/phone.png")
	var failed := false
	var w := normal.get_width()
	var h := normal.get_height()
	var magenta := 0
	for y in h:
		for x in w:
			var c := full.get_pixel(x, y)
			if c.r8 > 200 and c.g8 < 80 and c.b8 > 200:
				magenta += 1
	var differing := 0
	var sum_n := Vector3.ZERO
	var sum_p := Vector3.ZERO
	for y in h:
		for x in w:
			var a := normal.get_pixel(x, y)
			var b := phone.get_pixel(x, y)
			if b.r8 > 200 and b.g8 < 80 and b.b8 > 200:
				magenta += 1
			sum_n += Vector3(a.r, a.g, a.b)
			sum_p += Vector3(b.r, b.g, b.b)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.3:
				differing += 1
	var n := float(w * h)
	var mean_diff := ((sum_n - sum_p) / n).abs().length() * 255.0
	print("mobile check: %d x %d, %d magenta pixels, mean colour differs by %.2f levels, %.3f%% of the pixels differ visibly" % [w, h, magenta, mean_diff, 100.0 * differing / n])
	if magenta > 0:
		printerr("FAIL: %d magenta-ish pixels (a missing texture / a bad shader input)" % magenta)
		failed = true
	if mean_diff > 2.0:
		printerr("FAIL: the average colour of the 16-bit-depth render differs from the normal one by %.2f levels" % mean_diff)
		failed = true
	if 100.0 * differing / n > 1.0:
		printerr("FAIL: %.2f%% of the pixels differ between the normal and the 16-bit-depth render (z-fighting)" % (100.0 * differing / n))
		failed = true
	quit(1 if failed else 0)
