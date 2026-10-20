extends SceneTree
## Economy simulation: three autopilot "players" (poor, average, good) play their first 20 shifts on the real game
## and the script reports coins per shift, stars, and when each upgrade becomes affordable.
##   godot --headless --path . --script tools/economy_sim.gd
## Each player type runs twice: "saving" (nothing is bought, so you can see when every price is first reachable) and
## "buying" (always buys the cheapest upgrade it can afford, so you can see how early upgrades arrive).
## The autopilot's skill is: how many aircraft it never helps, how slowly it reacts, how often it lines up a proper
## final, and how often it picks a runway end the wind has closed.

var SHIFTS := 20
var MODES := ["saving", "buying"]
## ignore: share of aircraft never helped; react: chance per autopilot tick (10 Hz) of dealing with a waiting
## aircraft; aligned: how often the path is a proper straight final; wrong_end: picks a closed runway end;
## notice: how soon an aircraft whose path did not work gets a new one (s); avoid: chance per tick to put an
## aircraft in a hold when it is about to conflict; sequence: chance of waiting for the runway's previous arrival
## to be nearly down before sending the next one.
const PLAYERS := {
	"poor":    {"ignore": 0.20, "react": 0.04, "aligned": 0.15, "wrong_end": 0.25, "notice": 8.0, "avoid": 0.03, "sequence": 0.10},
	"average": {"ignore": 0.06, "react": 0.12, "aligned": 0.55, "wrong_end": 0.06, "notice": 4.0, "avoid": 0.12, "sequence": 0.50},
	"good":    {"ignore": 0.01, "react": 0.30, "aligned": 0.92, "wrong_end": 0.00, "notice": 2.0, "avoid": 0.35, "sequence": 0.95},
}

var main: Node
var rng := RandomNumberGenerator.new()
var _tags := {}
var _spawned := 0
var _gos := 0

func _initialize() -> void:
	var save = root.get_node("Save")
	save.path = "user://sim_save.json"
	root.get_node("Tuning").ad_stub_seconds = 0.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var guard := 0
	while (guard < 3 or main._warming) and guard < 3000:
		await process_frame
		guard += 1
	main.traffic.spawned.connect(func(_p): _spawned += 1)
	main.traffic.go_around.connect(func(_p, _r): _gos += 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shifts="):
			SHIFTS = int(a.substr(7))
		elif a.begins_with("modes="):
			MODES = a.substr(6).split(",")
	var report := {}
	for who in ["poor", "average", "good"]:
		for mode in MODES:
			report[who + "/" + mode] = _run_player(who, mode)
	_print(report)
	quit()

func _run_player(who: String, mode: String) -> Dictionary:
	var save = root.get_node("Save")
	var skill: Dictionary = PLAYERS[who]
	save.reset_all()
	rng.seed = hash(who) + 7
	var rows := []
	var bank_history := []
	var buys := []
	for n in SHIFTS:
		var ap := 0
		for i in range(5, -1, -1):
			if save.airport_open(i):
				ap = i
				break
		main.daily_mode = false
		main.bad_mode = false
		main.select_airport(ap)
		main.restart()
		main.traffic.rng.seed = 1000 * (n + 1) + hash(who) % 1000
		main.traffic.go_rng.seed = 77 * (n + 1)
		main.rng_env.seed = 31 * (n + 1)
		_tags.clear()
		_spawned = 0
		_gos = 0
		var coins0: int = save.coins
		var steps := 0
		while main.alive and steps < 60 * 400:
			if steps % 6 == 0:
				_autopilot(skill)
			main.step(1.0 / 60.0)
			steps += 1
		var s = main.shift
		rows.append({"airport": ap, "landed": s.landed, "earned": s.earned, "bonus": s.bonus + s.time_bonus, "fines": s.fines + s.overtime_penalty,
				"net": s.balance(), "kept": s.kept(), "paid": s.payout(), "stars": s.stars(), "gain": save.coins - coins0, "end_t": main.traffic.run_time,
				"conflicts": s.conflicts, "diversions": s.diversions, "crashes": s.crashes, "clean_stars": _stars_for(s.earned + s.bonus + s.time_bonus, s.thresholds), "spawned": _spawned, "gos": _gos, "bank": save.coins})
		if mode == "buying":
			var progress := true
			while progress:
				progress = false
				var best_id := ""
				var best_cost := 1 << 30
				for id in Upgrades.IDS:
					var c := Upgrades.cost(id, save.upgrade_level(id))
					if c >= 0 and c < best_cost:
						best_cost = c
						best_id = id
				if best_id != "" and save.coins >= best_cost:
					save.buy_upgrade(best_id)
					buys.append("%s L%d @shift %d" % [Upgrades.upgrade_name(best_id), save.upgrade_level(best_id), n + 1])
					progress = true
		rows[rows.size() - 1]["spent_bank"] = save.coins
	var cum := 0
	var afford := {}
	if mode == "saving":
		for n in rows.size():
			cum += rows[n]["gain"]
			for id in Upgrades.IDS:
				for lv in 3:
					var key := "%s L%d" % [Upgrades.upgrade_name(id), lv + 1]
					if not afford.has(key) and cum >= Upgrades.cost(id, lv):
						afford[key] = n + 1
	save.reset_all()
	return {"rows": rows, "buys": buys, "afford": afford}

func _stars_for(coins: int, th: PackedInt32Array) -> int:
	var n := 0
	for t in th:
		if coins >= t:
			n += 1
	return n

func _autopilot(skill: Dictionary) -> void:
	var tr = main.traffic
	var react := float(skill["react"])
	var avoid := float(skill["avoid"])
	for p in tr.planes:
		if not p.active():
			continue
		var id: int = p.get_instance_id()
		var tag = _tags.get(id, {"age": 999.0, "state": ""})
		if p.age < float(tag["age"]):
			tag = {"age": p.age, "state": ""}
		tag["age"] = p.age
		_tags[id] = tag
		if not p.entered:
			continue
		# A hold: either waiting for its turn at the runway (route it once the runway is free) or put on to avoid a
		# conflict (let go again once the danger has passed).
		if p.state == Aircraft.State.HOLD:
			if tag["state"] == "wait":
				if rng.randf() < react and not (rng.randf() < float(skill["sequence"]) and _runway_busy(p)):
					_route(p, skill)
					tag["state"] = "done"
					tag["routed"] = p.age
					tag["gos"] = p.go_arounds
			elif p.warn <= 0.0 and p.age - float(tag.get("held", 0.0)) > 2.0 and rng.randf() < 0.3:
				tr.toggle_hold(p)
			continue
		if p.state != Aircraft.State.FLY:
			continue
		if p.warn > 0.3 and p.type != Aircraft.Type.GLIDER and p.pos.length() > 3.0 and not p.cleared and rng.randf() < avoid:
			tr.toggle_hold(p)
			tag["held"] = p.age
			continue
		# A go-around, or a path that never reached the runway: it needs a new one, after a while.
		if tag["state"] == "done" and not p.cleared and (p.go_arounds > int(tag.get("gos", 0)) or p.age - float(tag["routed"]) > float(skill["notice"])):
			tag["state"] = "wait"
		if p.cleared:
			continue
		if tag["state"] == "":
			tag["state"] = "ignore" if rng.randf() < float(skill["ignore"]) else "wait"
		if tag["state"] == "wait" and rng.randf() < react:
			if rng.randf() < float(skill["sequence"]) and _runway_busy(p):
				# circle until the runway is free, but only away from the field (a hold over the approach is a conflict)
				if p.type != Aircraft.Type.GLIDER and p.type != Aircraft.Type.HELI and p.pos.length() > 3.5:
					tr.toggle_hold(p)
				if p.pos.length() > 3.5:
					continue
			_route(p, skill)
			tag["state"] = "done"
			tag["routed"] = p.age
			tag["gos"] = p.go_arounds

func tr_begin(p: Aircraft) -> void:
	main.traffic.begin_path(p)

## Is another aircraft still coming in to this runway, with more than a few units of path to go?
func _runway_busy(p: Aircraft) -> bool:
	if p.tkind != Aircraft.Kind.RUNWAY:
		return false
	for o in main.traffic.planes:
		if o != p and o.active() and o.tkind == p.tkind and o.runway == p.runway and (o.cleared or o.state == Aircraft.State.LANDING):
			if o.state == Aircraft.State.LANDING:
				return true
			var d := 0.0
			var prev: Vector2 = o.pos
			for k in o.count:
				var q: Vector2 = o.pts[o.head + k]
				d += prev.distance_to(q)
				prev = q
			if d > 3.0:
				return true
	return false

func _route(p: Aircraft, skill: Dictionary) -> void:
	var r: int = p.runway
	var e := 0
	if p.tkind == Aircraft.Kind.RUNWAY:
		e = 0 if main.wind.is_active(r, 0) else 1
		if rng.randf() < float(skill["wrong_end"]):
			e = 1 - e
	var thr: Vector2 = Airports.land_threshold(p.tkind, r, e)
	var pts := []
	if p.tkind == Aircraft.Kind.RUNWAY and rng.randf() < float(skill["aligned"]):
		var rd: Vector2 = (Airports.land_far(p.tkind, r, e) - thr).normalized()
		for d in [3.6, 2.4, 1.2]:
			pts.append(thr - rd * d)
		pts.append(thr)
	else:
		pts = [p.pos.lerp(thr, 0.3), p.pos.lerp(thr, 0.7), thr]
	tr_begin(p)
	main._drag_plane = p
	main._drag_active = false
	main._touch_start = p.pos
	main.overlay.selected = p
	for w in pts:
		main.feed_drag(w)
		if main._drag_plane == null:
			break
	if main._drag_plane != null:
		main.traffic.end_path(p, pts[pts.size() - 1])
	main._cancel_drag()

func _print(report: Dictionary) -> void:
	for key in report:
		var rep: Dictionary = report[key]
		print("")
		print("=== %s ===" % key)
		print("shift airport landed  earned bonus fines  net kept paid  stars  coins+  bank  end_s  confl divert spawned go-arounds  stars-if-no-fines")
		var tot := 0
		for n in rep["rows"].size():
			var r: Dictionary = rep["rows"][n]
			tot += r["gain"]
			print("%5d %7d %6d %7d %5d %5d %4d %4d %4d %6d %7d %5d  %5.0f %5d %5d %7d %10d %14d" % [n + 1, r["airport"], r["landed"], r["earned"], r["bonus"], r["fines"], r["net"], r["kept"], r["paid"], r["stars"], r["gain"], r["bank"], r["end_t"], r["conflicts"], r["diversions"], r["spawned"], r["gos"], r["clean_stars"]])
		print("average coins/shift: %.0f   total after %d shifts: %d" % [float(tot) / rep["rows"].size(), rep["rows"].size(), tot])
		if rep["afford"].size() > 0:
			var parts := []
			for k in rep["afford"]:
				parts.append("%s: shift %d" % [k, rep["afford"][k]])
			print("first affordable (saving everything): " + "; ".join(parts))
		if rep["buys"].size() > 0:
			print("purchases (buy the cheapest as soon as affordable): " + "; ".join(rep["buys"]))
