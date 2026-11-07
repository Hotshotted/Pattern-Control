extends SceneTree
## A picture of aircraft standing where trees stand (the case "a plane flies under a tree"), at a phone's size:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script tools/occlusion_shot.gd -- out=/tmp/x.png [airport=2]
func _initialize() -> void:
	var out := "/tmp/occlusion.png"
	var ap := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("airport="):
			ap = int(a.substr(8))
	root.size = Vector2i(390, 844)
	DisplayServer.window_set_size(root.size)
	var save = root.get_node("Save")
	save.path = "user://occ_save.json"
	save.reset_all()
	save.unlocks["all_airports"] = true
	root.get_node("Tuning").intro_logo = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var g := 0
	while not main._warming and g < 120:
		await process_frame
		g += 1
	while main._warming and g < 6000:
		await process_frame
		g += 1
	for i in 120:
		await process_frame
	main.select_airport(ap)
	main.restart()
	main.traffic.auto_spawn = false
	main.set_process(false)
	var spots := [Vector2(-4.4, 6.4), Vector2(4.3, 6.9), Vector2(4.5, -6.5), Vector2(-4.2, -3.9), Vector2(4.5, 4.4)]
	var n := 0
	for s in spots:
		var p = main.traffic.place(0, s, 0.3 * n, 2 if n % 2 == 0 else 3)
		if p != null:
			p.timer_left = p.timer_max
			p.speed = 0.0
		n += 1
	main.traffic.step(0.001)
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
