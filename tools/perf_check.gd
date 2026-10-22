extends SceneTree
## Frame times on International with a busy sky, rendered for real (needs a display: xvfb-run -a godot --path . --script tools/perf_check.gd).
## Prints the mean, 99th percentile and worst frame in ms and exits 1 if the worst of a warmed-up run is over 33 ms.

func _initialize() -> void:
	var save = root.get_node("Save")
	save.path = "user://perf_save.json"
	save.reset_all()
	save.unlocks["all_airports"] = true
	root.get_node("Tuning").intro_logo = false
	var main = load("res://scenes/main.tscn").instantiate()
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
	for i in 60:
		await process_frame
	main.select_airport(5)
	main.restart()
	var tr = main.traffic
	tr.auto_spawn = false
	var kinds := [0, 1, 2, 3, 4, 5]
	for k in 14:
		var p = tr.place(k % 3, Vector2(-3.5 + (k % 5) * 1.8, -6.0 + (k / 5) * 2.4), 0.3 * k, kinds[k % 6])
		var th: Vector2 = Airports.end_threshold(k % 3, 1)
		for j in 24:
			p.push(p.pos.lerp(th, float(j + 1) / 24.0))
		p.cleared = true
		p.timer_left = p.timer_max * 0.5
	var times: Array[float] = []
	for i in 40:
		await process_frame
	var last := Time.get_ticks_usec()
	for i in 400:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	var worst: float = times[times.size() - 1]
	print("perf: International, 14 aircraft with paths: mean %.2f ms, p99 %.2f ms, worst %.2f ms over %d frames" % [sum / times.size(), times[int(times.size() * 0.99)], worst, times.size()])
	quit(1 if worst > 33.0 else 0)
