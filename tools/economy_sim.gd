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
var SURVEY := false               # per-airport star survey instead of the 20-shift progression
var SURVEY_SHIFTS := 8
var ONLY_BOTS := ["poor", "average", "good"]
var ONLY_AIRPORTS := [0, 1, 2, 3, 4, 5]
## ignore: share of aircraft never helped; react: chance per autopilot tick (10 Hz) of dealing with a waiting
## aircraft; aligned: how often the path is a proper straight final; wrong_end: picks a closed runway end;
## notice: how soon an aircraft whose path did not work gets a new one (s); avoid: chance per tick to put an
## aircraft in a hold when it is about to conflict; sequence: chance of waiting for the runway's previous arrival
## to be nearly down before sending the next one. fix: chance per tick that an aircraft that wobbles (a go-around is a second away)
## gets a new, straight final.
const PLAYERS := {
	"poor":    {"ignore": 0.20, "react": 0.04, "aligned": 0.15, "wrong_end": 0.25, "notice": 8.0, "avoid": 0.12, "sequence": 0.10, "gap": 3.0, "fix": 0.01},
	"average": {"ignore": 0.06, "react": 0.12, "aligned": 0.55, "wrong_end": 0.06, "notice": 4.0, "avoid": 0.5, "sequence": 0.50, "gap": 2.5, "fix": 0.04},
	"good":    {"ignore": 0.01, "react": 0.5, "aligned": 0.92, "wrong_end": 0.00, "notice": 2.0, "avoid": 0.9, "sequence": 0.95, "gap": 1.0, "fix": 0.12},
}

var main: Node
var tun: Node
var rng := RandomNumberGenerator.new()
var _tags := {}
var _spawned := 0
var _gos := 0

func _initialize() -> void:
	var save = root.get_node("Save")
	save.path = "user://sim_save.json"
	tun = root.get_node("Tuning")
	tun.ad_stub_seconds = 0.0
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
		elif a == "survey":
			SURVEY = true
		elif a.begins_with("bots="):
			ONLY_BOTS = Array(a.substr(5).split(","))
		elif a.begins_with("aps="):
			ONLY_AIRPORTS = []
			for x in a.substr(4).split(","):
				ONLY_AIRPORTS.append(int(x))
		elif a.begins_with("per="):
			SURVEY_SHIFTS = int(a.substr(4))
	if SURVEY:
		_survey()
		quit()
		return
	var report := {}
	for who in ["poor", "average", "good"]:
		for mode in MODES:
			report[who + "/" + mode] = _run_player(who, mode)
	_print(report)
	quit()

## Every bot plays SURVEY_SHIFTS shifts at every airport (the first one is that airport's gentle intro shift).
func _survey() -> void:
	var save = root.get_node("Save")
	print("Stars per airport (net coins after fines; %d shifts each, the first is the gentle intro shift)" % SURVEY_SHIFTS)
	print("bot      airport          thresholds       landed/arr  confl  net(avg)  stars(avg) [0 1 2 3 stars]  intro-shift stars   no-fine stars(avg)")
	for who in ONLY_BOTS:
		var skill: Dictionary = PLAYERS[who]
		for ap in ONLY_AIRPORTS:
			save.reset_all()
			save.unlocks["all_airports"] = true
			rng.seed = hash(who) + 100 * ap + 3
			var dist := [0, 0, 0, 0]
			var tot_land := 0
			var tot_arr := 0
			var tot_conf := 0
			var tot_net := 0
			var tot_stars := 0
			var tot_clean := 0
			var intro_stars := 0
			for n in SURVEY_SHIFTS:
				var r := _play_shift(skill, ap, n, who)
				dist[r["stars"]] += 1
				tot_land += r["landed"]
				tot_arr += r["spawned"]
				tot_conf += r["conflicts"]
				tot_net += r["net"]
				tot_stars += r["stars"]
				tot_clean += r["clean_stars"]
				if n == 0:
					intro_stars = r["stars"]
			var th: Array = tun.star_thresholds(ap)
			print("%-8s %-16s %-16s %5.1f/%-5.1f %5.1f %9.0f %10.2f  %s %17d %20.2f" % [who, Airports.airport_name(ap), str(th), float(tot_land) / SURVEY_SHIFTS, float(tot_arr) / SURVEY_SHIFTS, float(tot_conf) / SURVEY_SHIFTS, float(tot_net) / SURVEY_SHIFTS, float(tot_stars) / SURVEY_SHIFTS, str(dist), intro_stars, float(tot_clean) / SURVEY_SHIFTS])
	save.reset_all()

## One shift at airport `ap` by a bot; returns its numbers. (Shifts at the same airport count as replays after the first.)
func _play_shift(skill: Dictionary, ap: int, n: int, who: String) -> Dictionary:
	main.daily_mode = false
	main.bad_mode = false
	main.select_airport(ap)
	main.restart()
	main.traffic.rng.seed = 1000 * (n + 1) + hash(who) % 1000 + ap * 7
	main.traffic.go_rng.seed = 77 * (n + 1) + ap
	main.rng_env.seed = 31 * (n + 1) + ap
	_tags.clear()
	_spawned = 0
	_gos = 0
	var steps := 0
	while main.alive and steps < 60 * 400:
		if steps % 6 == 0:
			_autopilot(skill)
		main.step(1.0 / 60.0)
		steps += 1
	var s = main.shift
	return {"landed": s.landed, "spawned": _spawned, "conflicts": s.conflicts, "net": s.balance(), "stars": s.stars(), "clean_stars": _stars_for(s.earned + s.bonus + s.time_bonus, s.thresholds)}

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
				"conflicts": s.conflicts, "diversions": s.diversions, "crashes": s.crashes, "clean_stars": _stars_for(s.earned + s.bonus + s.time_bonus, s.thresholds), "spawned": _spawned, "gos": _gos, "warns": main.traffic.go_around_warns, "cancels": main.traffic.go_around_cancels, "bank": save.coins})
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
				if rng.randf() < react and not (rng.randf() < float(skill["sequence"]) and _runway_busy(p, float(skill["gap"]))):
					_route(p, skill)
					tag["state"] = "done"
					tag["routed"] = p.age
					tag["gos"] = p.go_arounds
			elif p.age - float(tag.get("held", 0.0)) > 1.5 and _threat(p) == null and rng.randf() < 0.4:
				tr.toggle_hold(p)
				tag["state"] = "wait"
			continue
		if p.state != Aircraft.State.FLY:
			continue
		if p.ga_pending and not p.ga_redrawn and rng.randf() < float(skill.get("fix", 0.0)):
			_route(p, skill, true)       # the wobble: redraw a clean, straight final
			continue
		if p.type != Aircraft.Type.GLIDER and rng.randf() < avoid and _threat(p) != null:
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
			if rng.randf() < float(skill["sequence"]) and _runway_busy(p, float(skill["gap"])):
				# circle until the runway is free, but only away from the field (a hold over the approach is a conflict)
				if p.type != Aircraft.Type.GLIDER and p.type != Aircraft.Type.HELI and p.pos.length() > 2.0:
					tr.toggle_hold(p)
				if p.pos.length() > 2.0:
					continue
			_route(p, skill)
			tag["state"] = "done"
			tag["routed"] = p.age
			tag["gos"] = p.go_arounds

## An aircraft that p is on course to conflict with in the next few seconds, and that p should give way to
## (null if none, or if the other should give way). Straight-line prediction from heading and speed.
func _threat(p: Aircraft) -> Aircraft:
	var tr: Traffic = main.traffic
	var mult: float = tun.speed_mult(tr.run_time) * tun.traffic_speed_mult()
	var vp: Vector2 = Vector2(sin(p.heading), -cos(p.heading)) * p.speed * mult if p.state == Aircraft.State.FLY else Vector2.ZERO
	for o: Aircraft in tr.planes:
		if o == p or not o.active() or not o.entered or o.ground or o.state == Aircraft.State.DIVERT or o.state == Aircraft.State.LANDING:
			continue
		var vo: Vector2 = Vector2(sin(o.heading), -cos(o.heading)) * o.speed * mult if o.state == Aircraft.State.FLY else Vector2.ZERO
		var rel: Vector2 = o.pos - p.pos
		var dv: Vector2 = vo - vp
		var t_c := 0.0
		if dv.length_squared() > 0.0001:
			t_c = clampf(-rel.dot(dv) / dv.length_squared(), 0.0, 5.0)
		var dmin: float = (rel + dv * t_c).length()
		var margin: float = tun.conflict_distance * 1.7 + (tun.hold_radius if o.state == Aircraft.State.HOLD else 0.0)
		if dmin < margin:
			# give way: the one with no path yields to one with a path; otherwise the lower id yields
			if p.cleared and not o.cleared:
				continue
			if p.cleared == o.cleared and p.get_instance_id() > o.get_instance_id():
				continue
			return o
	return null

func tr_begin(p: Aircraft) -> void:
	main.traffic.begin_path(p)

## Is another aircraft still coming in to this runway, with more than a few units of path to go?
func _runway_busy(p: Aircraft, gap: float = 3.0) -> bool:
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
			if d > gap:
				return true
	return false

func _route(p: Aircraft, skill: Dictionary, clean: bool = false) -> void:
	var r: int = p.runway
	var e := 0
	if p.tkind == Aircraft.Kind.RUNWAY:
		e = 0 if main.wind.is_active(r, 0) else 1
		if clean:
			e = p.land_end
		elif rng.randf() < float(skill["wrong_end"]):
			e = 1 - e
	var thr: Vector2 = Airports.land_threshold(p.tkind, r, e)
	var pts := []
	if p.tkind == Aircraft.Kind.RUNWAY and (clean or rng.randf() < float(skill["aligned"])):
		var rd: Vector2 = (Airports.land_far(p.tkind, r, e) - thr).normalized()
		if clean:        # straight at the threshold, along the runway line for the last stretch
			pts.append(p.pos.lerp(thr - rd * 1.0, 0.5))
			pts.append(thr - rd * 1.0)
		else:
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
		var warns := 0
		var cancels := 0
		for r in rep["rows"]:
			warns += int(r.get("warns", 0))
			cancels += int(r.get("cancels", 0))
		print("go-around warnings: %d, cancelled by a cleaner final: %d (cancel rate %.0f%%)" % [warns, cancels, 100.0 * cancels / maxf(warns, 1)])
		if rep["afford"].size() > 0:
			var parts := []
			for k in rep["afford"]:
				parts.append("%s: shift %d" % [k, rep["afford"][k]])
			print("first affordable (saving everything): " + "; ".join(parts))
		if rep["buys"].size() > 0:
			print("purchases (buy the cheapest as soon as affordable): " + "; ".join(rep["buys"]))
