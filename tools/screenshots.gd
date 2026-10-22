extends SceneTree
## Renders every screen to PNGs (needs a display: xvfb-run -a godot --path . --script tools/screenshots.gd -- out=/tmp/shots/before).
## Used for the clarity pass: it walks the menu, airport select, HUD, banners, pause, results, upgrades, shop,
## the daily modes and the aircraft tip, and saves one image each.

var out := "/tmp/shots"
var only := ""          # "types": just the aircraft line-up (a quick look while drawing them)
var main: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("only="):
			only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(out)
	var save = root.get_node("Save")
	save.path = "user://shots_save.json"
	save.reset_all()
	root.get_node("Tuning").ad_stub_seconds = 0.0
	root.get_node("Tuning").intro_logo = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var guard := 0
	while not main._warming and guard < 120:       # the pre-warm starts a moment after the scene is ready
		await process_frame
		guard += 1
	guard = 0
	while main._warming and guard < 6000:
		await process_frame
		guard += 1
	guard = 0
	while is_instance_valid(main.hud._splash) and guard < 600:
		await process_frame
		guard += 1
	await _frames(30)
	print("state: warming=", main._warming, " splash=", is_instance_valid(main.hud._splash), " ad=", main.hud._ad.visible, " menu=", main.hud._menu.visible, " screen=", main.screen)
	if only == "types":
		await _types_shots(save)
	else:
		await _walk(save)
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	main.hud.skip_animations()
	await _frames(6)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name, " ", img.get_size())

func _walk(save) -> void:
	# a save with some progress so the screens have something to show
	save.coins = 240
	save.stars[0] = 3
	save.stars[1] = 2
	save.stars[2] = 1
	save.best_coins[0] = 120
	save.unlocks["all_airports"] = false
	save.upgrades["comms"] = 1
	save.upgrades["holding"] = 2
	await _shot("01_menu")
	main._on_button("airports")
	await _shot("02_airport_select")
	main._on_button("upgrades")
	await _shot("03_upgrades")
	main._on_button("shop")
	await _shot("04_shop")
	main._show_menu()
	main.select_airport(2)
	main.restart()
	main.traffic.auto_spawn = false
	var tr = main.traffic
	# a busy-looking field
	for k in 4:
		var p = tr.place(k % 2, Vector2(-3.0 + k * 2.0, -3.0 + k), 0.4 * k, 2 + (k % 3))
		p.timer_left = p.timer_max * (0.9 - 0.25 * k)
	for i in 120:
		main.step(1.0 / 60.0)
	main.shift.on_landed(3, 14, 0)
	main.shift.on_landed(3, 14, 0)
	main.shift.on_landed(3, 14, 4)
	main.hud.set_shift(main.shift)
	await _shot("05_hud")
	tr.run_time = 85.0
	main.step(1.0 / 60.0)
	await _shot("06_last_arrivals")
	tr.run_time = 90.0
	for i in 5:
		main.step(1.0 / 60.0)
	await _shot("07_clear_the_sky")
	tr.run_time = 104.0
	main.step(1.0 / 60.0)
	await _shot("08_overtime")
	main.hud.set_wind_warning(270.0, 6)
	await _shot("09_wind_warning")
	main.pause_game()
	await _shot("10_pause")
	main.resume_game()
	main.hud.show_tip("Helicopters land on the H pad", "heli")
	await _shot("11_tip")
	main._apply_fine(80, "conflict", "CONFLICT", Vector2.ZERO)
	await _shot("12_fine_popup")
	tr.release_all()
	main.restart()
	tr.auto_spawn = false
	for k in 15:
		main.shift.on_landed(3, 14, 0)
	main.shift.fine(40, "conflict")
	main.hud.set_shift(main.shift)
	tr.run_time = main.get_node("/root/Tuning").par_eff() - 4.0
	main.step(1.0 / 60.0)
	await _shot("13_results")
	main.hud.toggle_details()
	await _shot("13b_results_details")
	main.restart()
	tr.auto_spawn = false
	main.shift.on_landed(3, 14, 0)
	main.shift.fine(100, "conflict")
	main.hud.set_shift(main.shift)
	tr.run_time = main.get_node("/root/Tuning").par_eff() + 8.0
	main.step(1.0 / 60.0)
	await _shot("13c_results_bad_shift")
	main._show_menu()
	await _shot("14_menu_after")
	main.start_daily()
	await _shot("15_daily_hud")
	main._show_menu()
	main.start_bad_day()
	await _shot("16_bad_day_hud")
	await _motion_shots()
	await _polish_shots()

## Motion: frames of the logo intro, a screen mid-transition, the living menu, coins in flight.
func _motion_shots() -> void:
	var hud = main.hud
	var tuning = root.get_node("Tuning")
	tuning.intro_logo = true
	main._boot_to_menu()
	for i in 20:
		await process_frame
	hud._art.logo_t = 0.4
	hud._art.queue_redraw()
	await _frames(2)
	_save_raw("17_logo_studio")
	hud._art.logo_t = 1.9
	hud._art.queue_redraw()
	await _frames(2)
	_save_raw("18_logo_title")
	hud.skip_logo()
	tuning.intro_logo = false
	await _frames(40)
	hud.skip_animations()
	main._show_menu()
	main.hud.skip_animations()
	for i in 60 * 7:
		main.diorama.tick(1.0 / 60.0)
		if i % 20 == 0:
			await process_frame
	await _frames(3)
	_save_raw("19_menu_living")
	main._show_select()
	hud._tr_t = 0.12
	hud._apply_transition()
	hud._art.btn_age = 0.12
	hud._art.queue_redraw()
	await _frames(2)
	_save_raw("20_transition_mid")
	main.restart()
	main.traffic.auto_spawn = false
	hud.skip_animations()
	main.hud.fly_coins(Vector2(540, 900), 5)
	for i in 14:
		hud._process(0.05)
	await _frames(2)
	_save_raw("21_coins_flying")

func _save_raw(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name)

## In-game polish: banking aircraft with shadows and contrails, a touchdown puff, a go-around, the star bar, results.
func _polish_shots() -> void:
	var hud = main.hud
	var tr = main.traffic
	var tuning = root.get_node("Tuning")
	main.select_airport(3)
	main.restart()
	tr.auto_spawn = false
	var a = tr.place(0, Vector2(-2.0, -2.0), 0.3, 4)
	a.heading = 1.4
	var b = tr.place(1, Vector2(2.2, -3.6), -0.4, 3)
	b.heading = -1.2
	var c = tr.place(0, Vector2(0.4, 1.8), 0.0, 2)
	var thr = Airports.end_threshold(0, 0)
	var rd = Airports.end_dir(0, 0)
	var l = tr.place(0, thr - rd * 0.9, atan2(rd.x, -rd.y), 3)
	l.push(thr)
	l.push(Airports.end_far(0, 0))
	l.cleared = true
	l.land_end = 0
	var seen := false
	for i in 220:
		main.step(1.0 / 60.0)
		if l.pop_t > 0.1 and not seen:
			seen = true
			await _frames(2)
			_save_raw("22_touchdown_puff")
	for p in [a, b, c]:
		p.timer_left = p.timer_max * 0.9
	tr._start_go_around(c, 0)
	c.climb = tuning.go_around_climb_seconds * 0.5
	main.step(1.0 / 60.0)
	await _frames(2)
	_save_raw("23_banking_goaround")
	main.restart()
	tr.auto_spawn = false
	for i in 40:
		main.shift.on_landed(3, 14, 0)
	main.hud.set_shift(main.shift)
	hud._process(0.01)
	await _frames(2)
	_save_raw("24_star_sparkle")
	tr.run_time = tuning.par_eff() - 4.0
	main.step(1.0 / 60.0)
	main.step(1.0 / 60.0)
	hud._art.res_t = 0.0
	for i in 28:
		hud._process(0.05)
	await _frames(2)
	_save_raw("25_results_slam")
	for i in 22:
		hud._process(0.05)
	await _frames(2)
	_save_raw("26_results_confetti")
	hud.queue_unlock("Regional")
	hud._art.res_t = 3.7
	hud._process(0.01)
	for i in 14:
		hud._process(0.05)
	await _frames(2)
	_save_raw("27_unlock_reveal")

## Every aircraft type on one airport, each in a runway colour (and a student pilot), plus the other airports' ground.
func _types_shots(save) -> void:
	save.unlocks["all_airports"] = true
	for a in [5, 0, 1, 2, 3, 4]:
		main.select_airport(a)
		main.restart()
		var tr = main.traffic
		tr.auto_spawn = false
		if a == 5:
			var k := 0
			for t in [0, 1, 2, 3, 4, 5]:
				var target := 0 if t != 1 else 0
				var p = tr.place(k % 3 if t != 1 and t != 5 else 0, Vector2(-3.2 + (k % 3) * 3.2, -5.0 + (k / 3) * 3.0), 0.5 * k, t)
				if t == 3:
					p.student = true
				p.timer_left = p.timer_max * (0.9 - 0.15 * k)
				k += 1
			for i in 20:
				main.step(1.0 / 60.0)
		await _shot("30_airport_%d" % a)
