extends SceneTree
## The long-term career model: poor, average and good players over the whole game (60 to 100 hours), on the REAL progression code (Save, Progression,
## Improvements, Rhythm, Goals, Mastery run as the game runs them). The one thing it does not run is the airfield itself: a shift's outcome (landings,
## pay, fines, stars, length) is drawn from SHIFTS THAT WERE REALLY PLAYED by the autopilot bots of tools/audit_sim.gd, surveyed at three stages of an
## airport's development (airport level 1 with nothing built, level 10 with four levels of everything, level 20 with eight), and blended by how far this
## airport has come. Playing 3,000 real shifts per bot would take days; this takes seconds, so the numbers can be tuned and re-run.
##
##   godot --headless --path . --script tools/career_model.gd -- surveys=<dir> [bots=poor,average,good] [mode=continuous|daily] [maxh=250] [policy=tour|newest]
##
## surveys: the folder with svy_l1_i0.txt, svy_l10_i4.txt and svy_l20_i8.txt (audit_sim.gd survey per=12 bots=... up=half lvl=L imp=I).
## mode continuous: the player plays back to back (hours of play); mode daily: one session of about 20 minutes a day, the hangars earn in between.
## policy tour: always play the open airport with the lowest level (every airport grows together); newest: always the newest open airport.
## Output: one block of tables per bot (see docs/content_audit.md, section 10) and lines "CAREER ..." that tools can read.

const ANCHORS := [["svy_l1_i0.txt", 0.0], ["svy_l10_i4.txt", 0.5], ["svy_l20_i8.txt", 1.0]]
const OVERHEAD := 20.0                  # seconds of menus, results and taps around a shift (as in audit_sim.gd)
const SESSION_MINUTES := 20.0
## Chance that a bot finishes a goal of each tier (easy / medium / hard) with a full day's play at that airport.
const GOAL_SKILL := {"poor": [0.75, 0.35, 0.08], "average": [1.0, 0.7, 0.3], "good": [1.0, 0.95, 0.6]}
const GOAL_SHIFTS := [1.0, 3.0, 5.0]    # shifts at an airport in a day that a goal of each tier needs to be within reach

var data := {}                          # bot -> airport -> anchor -> Array of shift dictionaries (n >= 1), plus "first" (n == 0)
var rng := RandomNumberGenerator.new()
var save: Node
var tun: Node

var bots: Array = ["poor", "average", "good"]
var mode := "continuous"
var policy := "tour"
var maxh := 250.0
var dir := ""
var src_shop := 0                         # coins spent in the cosmetic shop
var show_minutes := 0.0                  # show=N prints the events of the first N minutes

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("surveys="):
			dir = a.substr(8)
		elif a.begins_with("bots="):
			bots = a.substr(5).split(",")
		elif a.begins_with("mode="):
			mode = a.substr(5)
		elif a.begins_with("policy="):
			policy = a.substr(7)
		elif a.begins_with("maxh="):
			maxh = float(a.substr(5))
		elif a.begins_with("show="):
			show_minutes = float(a.substr(5))
	save = root.get_node("Save")
	tun = root.get_node("Tuning")
	save.path = "user://career_model.json"
	_load_surveys()
	for who in bots:
		_run(who)
	quit()

func _load_surveys() -> void:
	for k in ANCHORS.size():
		var f := FileAccess.open("%s/%s" % [dir, ANCHORS[k][0]], FileAccess.READ)
		if f == null:
			push_error("missing survey " + str(ANCHORS[k][0]))
			continue
		while not f.eof_reached():
			var l := f.get_line()
			if not l.begins_with("AUD "):
				continue
			var p := l.split(" ")
			var d := {}
			for kv in p.slice(5):
				var q := kv.split("=")
				if q.size() == 2:
					d[q[0]] = float(q[1])
			var who := p[1]
			var ap := int(p[2])
			var n := int(p[4])
			if not data.has(who):
				data[who] = {}
			if not data[who].has(ap):
				data[who][ap] = [{"shifts": [], "first": {}}, {"shifts": [], "first": {}}, {"shifts": [], "first": {}}]
			if n == 0:
				data[who][ap][k]["first"] = d
			else:
				data[who][ap][k]["shifts"].append(d)

## How far airport `ap` has come, 0 to 1: half its level, half what has been built there.
func _development(ap: int) -> float:
	return 0.5 * float(save.ap_level(ap) - 1) / float(Progression.MAX_LEVEL - 1) + 0.5 * float(save.imp_total(ap)) / float(Improvements.total_levels())

## One shift at `ap`, drawn from the surveyed shifts of the anchor stage this airport is at.
func _draw_shift(who: String, ap: int, first: bool) -> Dictionary:
	var dev := clampf(_development(ap) / 0.97, 0.0, 1.0)
	var k := 0 if dev < 0.5 else 1
	var t := dev / 0.5 if dev < 0.5 else (dev - 0.5) / 0.5
	var anchor := k + (1 if rng.randf() < t else 0)       # (a blend: the nearer stage more often)
	var set: Dictionary = data[who][ap][anchor]
	if first and not (set["first"] as Dictionary).is_empty():
		return set["first"]
	var arr: Array = set["shifts"]
	return arr[rng.randi() % arr.size()]

func _open_airports() -> Array:
	var out := []
	for a in 6:
		if save.airport_open(a):
			out.append(a)
	return out

func _pick_airport() -> int:
	var open := _open_airports()
	if policy == "newest":
		return open[open.size() - 1]
	var best: int = open[0]
	var all20 := true
	for a in open:
		if save.ap_level(a) < Progression.MAX_LEVEL:
			all20 = false
		if save.ap_level(a) < Progression.MAX_LEVEL and (save.ap_level(best) >= Progression.MAX_LEVEL or save.ap_level(a) <= save.ap_level(best)):
			best = a
	if all20:                # (every airport at level 20: the mastery ranks are what is left, so play where they are furthest from done)
		var low := 2.0
		for a in open:
			var f := float(save.mastery[a]) / float(Mastery.THRESHOLDS[a][Mastery.MAX_RANK - 1])
			if f < low:
				low = f
				best = a
	return best

## What is bought next: the cheapest thing that can be bought now (an improvement level the airport's level allows, or a Tower level).
func _buy_cheapest() -> Array:
	var bought := []
	for guard in 40:
		var best_cost := 1 << 30
		var best := ["", -1, ""]
		for a in _open_airports():
			for iid in Improvements.IDS:
				if save.imp_unlocked(a, iid):
					var c := Improvements.cost(a, iid, save.imp_level(a, iid))
					if c < best_cost:
						best_cost = c
						best = ["imp", a, iid]
		for uid in Upgrades.IDS:
			var c2 := Upgrades.cost(uid, save.upgrade_level(uid))
			if c2 >= 0 and c2 < best_cost:
				best_cost = c2
				best = ["up", -1, uid]
		for kind in ["theme", "livery", "windsock", "hangar", "prop"]:       # the shop: pure coin sinks (an airport's own things once it is open)
			for d in Cosmetics.items(kind):
				if Cosmetics.source(d) != "shop" or int(d["cost"]) <= 0 or save.owns(kind, d["id"]):
					continue
				if d.has("ap") and not save.airport_open(int(d["ap"])):
					continue
				if int(d["cost"]) < best_cost:
					best_cost = int(d["cost"])
					best = ["shop", kind, str(d["id"])]
		if best[0] == "" or save.coins < best_cost:
			break
		if best[0] == "imp":
			save.buy_improvement(best[1], best[2])
		elif best[0] == "shop":
			save.buy_cosmetic(best[1], best[2], best_cost, false)
			src_shop += best_cost
		else:
			save.buy_upgrade(best[2])
		bought.append([best[0], best[1], best[2], best_cost])
	return bought

func _everything_bought() -> bool:
	for a in 6:
		for iid in Improvements.IDS:
			if save.imp_level(a, iid) < Improvements.max_level(iid):
				return false
	for uid in Upgrades.IDS:
		if save.upgrade_level(uid) < Upgrades.MAX_LEVEL:
			return false
	return true

func _run(who: String) -> void:
	rng.seed = hash(who) + 17
	save.reset_all()
	src_shop = 0
	save.unlocks.erase("all_airports")
	save.day_override = 20000
	save.coins = 0
	tun.welcome_shifts = 2
	var minutes := 0.0                          # minutes of play
	var day := 20000
	var src := {"shifts": 0, "goals": 0, "offline": 0, "events": 0, "mastery": 0, "welcome": 0, "half": 0}
	var log: Array = []                         # [minutes, kind, text]
	var milestones := {"open": {}, "l20": {}}
	var done_at := {"improvements": -1.0, "tower": -1.0, "everything": -1.0, "stars": -1.0, "mastery": -1.0, "levels": -1.0}
	var shifts_total := 0
	var first_buy_shift := -1
	var shifts_since_buy := 0
	var max_shifts_without_buy := 0
	var early_max_shifts_without_buy := 0
	var sessions := 0
	var sessions_with_reward := 0
	var session_rewarded := false
	var daily_left := SESSION_MINUTES
	var plays_today := {}
	var goals_done := {}                        # airport -> [tier flags] today
	var day_streak_paid := false
	var open_seen := {0: 0.0}
	while minutes / 60.0 < maxh:
		var ap := _pick_airport()
		var first: bool = save.airport_plays[ap] == 0
		var sh := _draw_shift(who, ap, first)
		var paid := float(sh["paid"])
		var landed := int(sh["landed"])
		var stars := int(sh["stars"])
		var fines := int(sh["fines"])
		var ev = save.event_state()
		paid *= (1.0 + save.mastery_pay_bonus(ap)) * float(ev["event"]["pay"])
		var welcome := 0
		if save.airport_plays[ap] < tun.welcome_shifts:
			welcome = maxi(roundi(tun.welcome_floor_share * float(Improvements.cost(ap, "hangar", 0))) - roundi(paid), 0)
		var coins := roundi(paid) + welcome
		save.add_coins(coins)
		src["shifts"] += roundi(paid)
		src["welcome"] += welcome
		minutes += (float(sh["end_t"]) + OVERHEAD) / 60.0
		daily_left -= (float(sh["end_t"]) + OVERHEAD) / 60.0
		shifts_total += 1
		shifts_since_buy += 1
		save.airport_plays[ap] += 1
		# XP and what the levels unlock
		var xp := Progression.shift_xp(landed, fines == 0, [stars >= 1, stars >= 2, stars >= 3], [])
		xp = roundi(float(xp) * float(ev["event"]["xp"]))
		var up = save.add_xp(ap, xp)
		for hh in up["half"]:
			src["half"] += int(hh["coins"])
			log.append([minutes, "half", "%s halfway to level %d" % [Airports.airport_name(ap), int(hh["level"]) + 1]])
			session_rewarded = true
		for u in up["unlocks"]:
			log.append([minutes, "level", "%s level %d: %s" % [Airports.airport_name(ap), int(u["level"]), str(u["title"])]])
			session_rewarded = true
			if int(u["level"]) == 20:
				milestones["l20"][ap] = minutes
		for a in 6:
			if save.airport_open(a) and not open_seen.has(a):
				open_seen[a] = minutes
				milestones["open"][a] = minutes
		# mastery, stars
		for i in landed:
			var mr = save.add_mastery_landing(ap, Goals.AVG_PAY[ap])
			src["mastery"] += int(mr["coins"])
			for rk in mr["ranks"]:
				log.append([minutes, "mastery", "%s rank %d" % [Airports.airport_name(ap), int(rk)]])
				session_rewarded = true
		for k in stars:
			save.award_star(ap, k)
		# the weekly event
		save.day_override = day
		for er in save.event_add_shift(stars, Goals.unit_for(_open_airports(), 1.0)):
			src["events"] += int(er["coins"])
			log.append([minutes, "event", "event reward %d" % (int(er["i"]) + 1)])
			session_rewarded = true
		# daily goals at this airport, settled as the day goes (a goal is done when its shifts have been played)
		plays_today[ap] = int(plays_today.get(ap, 0)) + 1
		var skill: Array = GOAL_SKILL[who]
		if not goals_done.has(ap):
			goals_done[ap] = [false, false, false]
		var unit := Goals.unit_for([ap], tun.goal_unit)
		for tier in 3:
			if not goals_done[ap][tier] and float(plays_today[ap]) >= GOAL_SHIFTS[tier] and rng.randf() < float(skill[tier]) * 0.55:
				goals_done[ap][tier] = true
				var gc := Goals.reward_for(tier, unit)
				save.add_coins(gc)
				src["goals"] += gc
				var gx = save.add_xp(ap, int(Progression.XP_GOAL[tier]))
				for u2 in gx["unlocks"]:
					log.append([minutes, "level", "%s level %d: %s" % [Airports.airport_name(ap), int(u2["level"]), str(u2["title"])]])
					if int(u2["level"]) == 20:
						milestones["l20"][ap] = minutes
				log.append([minutes, "goal", "%s goal (tier %d)" % [Airports.airport_name(ap), tier]])
				session_rewarded = true
				if not day_streak_paid:
					day_streak_paid = true
					var sr: Dictionary = Goals.streak_advance(save.goal_streak, day)
					if not bool(sr.get("already", false)):
						var dr: Dictionary = Goals.day_reward(int(sr["pos"]), int(sr["count"]), unit)
						save.add_coins(int(dr["coins"]))
						src["goals"] += int(dr["coins"])
				if goals_done[ap][0] and goals_done[ap][1] and goals_done[ap][2]:
					var ch: int = Goals.chest_for(unit)
					save.add_coins(ch)
					src["goals"] += ch
		# buy
		var got := _buy_cheapest()
		if not got.is_empty():
			if first_buy_shift < 0:
				first_buy_shift = shifts_total
			max_shifts_without_buy = maxi(max_shifts_without_buy, shifts_since_buy)
			if minutes < 120.0:
				early_max_shifts_without_buy = maxi(early_max_shifts_without_buy, shifts_since_buy)
			shifts_since_buy = 0
			session_rewarded = true
			for g in got:
				log.append([minutes, "buy" if g[0] != "shop" else "shop", "%s %s" % [("%s %s" % [Airports.airport_name(g[1]), g[2]]) if g[0] == "imp" else str(g[2]), g[3]]])
		elif minutes < 120.0:
			early_max_shifts_without_buy = maxi(early_max_shifts_without_buy, shifts_since_buy)
		# milestones
		if done_at["improvements"] < 0.0:
			var all_imp := true
			for a in 6:
				for iid in Improvements.IDS:
					if save.imp_level(a, iid) < Improvements.max_level(iid):
						all_imp = false
			if all_imp:
				done_at["improvements"] = minutes
		if done_at["tower"] < 0.0:
			var all_t := true
			for uid in Upgrades.IDS:
				if save.upgrade_level(uid) < Upgrades.MAX_LEVEL:
					all_t = false
			if all_t:
				done_at["tower"] = minutes
		if done_at["levels"] < 0.0 and milestones["l20"].size() == 6:
			done_at["levels"] = minutes
		if done_at["stars"] < 0.0 and save.stars_total() >= 18:
			done_at["stars"] = minutes
		if done_at["mastery"] < 0.0:
			var all_m := true
			for a in 6:
				if save.mastery_rank(a) < Mastery.MAX_RANK:
					all_m = false
			if all_m:
				done_at["mastery"] = minutes
		if done_at["everything"] < 0.0 and _everything_bought():
			done_at["everything"] = minutes
		if mode == "continuous" and minutes >= float(day - 20000 + 1) * 180.0:
			day += 1
			save.day_override = day
			plays_today.clear()
			goals_done.clear()
			day_streak_paid = false
		# the end of a day's session (daily mode): the hangars earn while the player is away, and the goals start over
		if mode == "daily" and daily_left <= 0.0:
			sessions += 1
			if session_rewarded:
				sessions_with_reward += 1
			session_rewarded = false
			daily_left = SESSION_MINUTES
			day += 1
			save.day_override = day
			plays_today.clear()
			goals_done.clear()
			day_streak_paid = false
			var caps := []
			var pays := []
			for a in 6:
				caps.append(int(tun.star_thresholds(a)[0]) + int(tun.imp_hangar_bays) * save.imp_level(a, "hangar") if save.airport_open(a) else 0)
				var mix: Dictionary = Airports.mix(a)
				var tot := 0.0
				var pay := 0.0
				for t in mix:
					tot += float(mix[t])
					pay += float(mix[t]) * tun.landing_pay(int(t), a)
				pays.append(pay / maxf(tot, 0.0001))
			var off: Dictionary = Rhythm.offline_income(24.0 * 3600.0 - SESSION_MINUTES * 60.0, caps, pays)
			save.add_coins(int(off["total"]))
			src["offline"] += int(off["total"])
			if int(off["total"]) > 0:
				log.append([minutes, "offline", "tally %d" % int(off["total"])])
		if done_at["levels"] >= 0.0 and done_at["everything"] >= 0.0 and done_at["mastery"] >= 0.0:
			break
	_report(who, minutes, src, log, milestones, done_at, shifts_total, first_buy_shift, early_max_shifts_without_buy, sessions, sessions_with_reward)

func _fmt_h(m: float) -> String:
	return "-" if m < 0.0 else "%.1f h" % (m / 60.0)

func _gap_report(log: Array, kinds: Array, from_m: float, to_m: float) -> float:
	var last := from_m
	var worst := 0.0
	for e in log:
		if float(e[0]) < from_m or float(e[0]) > to_m or not kinds.has(e[1]):
			continue
		worst = maxf(worst, float(e[0]) - last)
		last = float(e[0])
	worst = maxf(worst, minf(to_m, 1.0e9) - last) if to_m < 1.0e8 else worst
	return worst

func _report(who: String, minutes: float, src: Dictionary, log: Array, ms: Dictionary, done: Dictionary, shifts: int, first_buy: int, early_nobuy: int, sessions: int, sess_ok: int) -> void:
	if show_minutes > 0.0:
		for e in log:
			if float(e[0]) <= show_minutes:
				print("  %6.1f min  %-8s %s" % [float(e[0]), e[1], e[2]])
	print("")
	print("==== %s bot, %s, policy %s: %.1f h of play, %d shifts ====" % [who, mode, policy, minutes / 60.0, shifts])
	var open_line := "unlock hours:"
	for a in range(1, 6):
		open_line += "  %s %s" % [Airports.airport_name(a), _fmt_h(float(ms["open"].get(a, -1.0)))]
	print(open_line)
	var l20 := "level 20 at:"
	for a in 6:
		l20 += "  %s %s" % [Airports.airport_name(a), _fmt_h(float(ms["l20"].get(a, -1.0)))]
	print(l20)
	print("everything bought %s (improvements %s, tower %s); all 18 stars %s; max mastery %s; all level 20 %s" % [_fmt_h(done["everything"]), _fmt_h(done["improvements"]), _fmt_h(done["tower"]), _fmt_h(done["stars"]), _fmt_h(done["mastery"]), _fmt_h(done["levels"])])
	var finished := true
	var fin := 0.0
	for k in ["improvements", "tower", "mastery", "levels"]:
		if float(done[k]) < 0.0:
			finished = false
		fin = maxf(fin, float(done[k]))
	print("total game length: %s" % (_fmt_h(fin) if finished else "not finished in %.0f h (%s)" % [maxh, _fmt_h(minutes)]))
	var all := 0
	for k in src:
		all += int(src[k])
	var share := "coin share:"
	for k in src:
		share += "  %s %d (%.0f%%)" % [k, int(src[k]), 100.0 * float(src[k]) / maxf(float(all), 1.0)]
	print(share)
	print("first upgrade bought after shift %d; most shifts in a row without a purchase in the first 2 h: %d" % [first_buy, early_nobuy])
	# gaps in play minutes between rewards of a kind, by phase (early 0-2 h, mid 2-20 h, late after 20 h)
	var phases := [["early (0-2 h)", 0.0, 120.0], ["mid (2-20 h)", 120.0, 1200.0], ["late (20 h on)", 1200.0, minutes]]
	for ph in phases:
		# (a kind of reward is measured up to the moment there is none left of it: the last level-up, the last thing to buy)
		var lvl_end := float(done["levels"]) if float(done["levels"]) >= 0.0 else minutes
		var buy_end := float(done["everything"]) if float(done["everything"]) >= 0.0 else minutes
		var lvl := _gap_report(log, ["level"], ph[1], minf(minf(ph[2], minutes), lvl_end))
		var buy := _gap_report(log, ["buy", "shop"], ph[1], minf(minf(ph[2], minutes), buy_end))
		var any := _gap_report(log, ["level", "buy", "shop", "mastery", "event", "goal", "offline", "half"], ph[1], minf(ph[2], minutes))
		var unl := _gap_report(log, ["level", "buy", "shop", "mastery", "event", "half"], ph[1], minf(ph[2], minutes))
		print("longest gap %-15s  level-up %5.1f min   purchase %5.1f min   unlock or purchase or event/mastery %5.1f min   anything %5.1f min" % [ph[0], lvl, buy, unl, any])
	if mode == "daily":
		print("20-minute sessions: %d, %d of them ended with a purchase, level-up, rank or event reward (%.0f%%); days to finish: %d" % [sessions, sess_ok, 100.0 * float(sess_ok) / maxf(float(sessions), 1.0), sessions])
	print("CAREER %s %s %s hours=%.1f finished=%s" % [who, mode, policy, minutes / 60.0, str(finished)])
