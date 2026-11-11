extends SceneTree
## Which wind directions leave a student pilot no runway end within its wind limit, per airport (and once a gust has closed a runway)?
##   godot --headless --path . --script tools/student_wind_cases.gd
func _initialize() -> void:
	var tol := 60.0
	for lim in [40.0, 34.0]:
		print("=== student limit %.0f deg ===" % lim)
		for a in Airports.COUNT:
			Airports.current = a
			var n := Airports.rw_count()
			var none := []
			var none_gust := []
			var total := 0
			var minopt := 99
			for k in 36:
				var d := k * 10.0
				if not Airports.wind_ok(d, tol):
					continue
				total += 1
				var opts := []
				for r in n:
					for e in 2:
						if Airports.angle_diff(Airports.end_heading_deg(r, e), d) <= lim:
							opts.append(r)
				minopt = mini(minopt, opts.size())
				if opts.is_empty():
					none.append(int(d))
				else:
					# a gust closes one runway (never the last open one): does a closure of the runway with the only legal end(s) leave none?
					var bad := false
					for cr in n:
						var open_after := 0
						for r in n:
							if r != cr:
								for e in 2:
									if Airports.angle_diff(Airports.end_heading_deg(r, e), d) <= tol:
										open_after += 1
										break
						if open_after < 1:
							continue            # (the last open runway is never closed)
						var left := 0
						for o in opts:
							if o != cr:
								left += 1
						if left == 0:
							bad = true
					if bad:
						none_gust.append(int(d))
			print("%-16s runways=%d winds=%d  no legal end: %s   none left once a gust closes a runway: %s   fewest legal ends in any wind: %d" % [Airports.airport_name(a), n, total, str(none), str(none_gust), minopt])
	quit()
