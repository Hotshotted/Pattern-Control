extends SceneTree
## Where does a busy frame's script time go? Sets up the International airport with a full field and drawn paths (as the smoke test's
## performance check does), then times 300 frames with each part of the game switched off in turn (its _process disabled): the drop
## is what that part costs. Headless, native speed - a ratio, not phone milliseconds.
##   godot --headless --path . --script tools/profile_frame.gd

var main: Node

func _initialize() -> void:
	var save = root.get_node("Save")
	save.path = "user://profile_save.json"
	save.reset_all()
	save.unlocks["all_airports"] = true
	root.get_node("Tuning").ad_stub_seconds = 0.0
	root.get_node("Tuning").intro_logo = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 400:
		await process_frame
	main.select_airport(5)
	save.airport_plays[5] = 3
	main.restart()
	var tr = main.traffic
	tr._god = true
	tr.auto_spawn = false
	for k in 14:
		var pl = tr.place(k % 2, Vector2(-4.0 + (k % 5) * 2.0, -7.0 + (k / 5) * 4.0), 0.3 * k, 2 + (k % 3))
		var d = Vector2(sin(pl.heading), -cos(pl.heading))
		for q in 40:
			pl.push(pl.pos + d * (q + 1) * 0.4 + Vector2(sin(q * 0.7), cos(q * 0.5)) * 0.5)
	for i in 120:
		await process_frame
	var all := {"warmup": null, "everything": null, "Main": main, "Traffic": main.traffic, "Airfield": main.airfield, "Overlay": main.overlay, "Hud": main.hud,
		"Fx": main.fx, "Ribbons": main.ribbons, "Diorama": main.diorama, "FogLayer": main.fog_layer, "LightOverlay": main.light, "Sfx": main.sfx}
	var base := 0.0
	for name in all:
		var node = all[name]
		var was := true
		if node != null:
			was = node.is_processing()
			node.set_process(false)
		var times: Array = []
		for i in 300:
			await process_frame
			times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if node != null:
			node.set_process(was)
		times.sort()
		var mean := 0.0
		for x in times:
			mean += x
		mean /= times.size()
		var median: float = times[times.size() / 2]
		if node == null:
			if name == "everything":
				base = mean
				print("%-16s mean %.2f ms   median %.2f   p95 %.2f   worst %.2f" % [name, mean, median, times[int(times.size() * 0.95)], times[-1]])
		else:
			print("%-16s mean %.2f ms   median %.2f   p95 %.2f   (saves %.2f ms on average)" % ["without " + name, mean, median, times[int(times.size() * 0.95)], base - mean])
	quit()
