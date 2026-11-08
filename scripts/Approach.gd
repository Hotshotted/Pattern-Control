class_name Approach
extends RefCounted
## Approach quality: how well set up is a runway landing? Scored from the path's last stretch before the
## threshold: how much it turns there, how much straight, aligned final it has (jets need more), the gap to the
## previous aircraft on the same runway, and how well the runway lines up with the wind. Everything it reads
## is written into this one object, so scoring (every frame, for the path tint) allocates nothing.

enum Reason { NONE, BUSY, TURN, SHORT_FINAL, SPACING, WIND, STUDENT, DOWNWIND }

var penalty := 0.0         # 0 = perfect .. 1 = hopeless
var chance := 0.0          # go-around chance at the decision point (0..1)
var reason := Reason.NONE  # the biggest contributor (when there is a problem at all)
var turn_deg := 0.0        # total turning in the last stretch
var straight_len := 0.0    # straight, aligned final before the threshold
var need_len := 0.0        # ...and how much this aircraft wanted
var pen_turn := 0.0
var pen_len := 0.0
var pen_space := 0.0
var pen_wind := 0.0
var student_near := false  # a student's approach is within Tuning.student_near of a limit (still fine, but close)
var land_off_deg := 0.0    # how far the runway end is off the wind (0 = a headwind)

## Point k of the approach: 0 is the aircraft, then the path points up to the threshold (the last path point,
## the runway's far end, is not part of the approach).
static func _pt(p: Aircraft, k: int) -> Vector2:
	return p.pos if k == 0 else p.pts[p.head + k - 1]

## Score the approach of `p` (a cleared runway path). `gap_s` is the predicted time between the previous
## touchdown on that runway and this aircraft's (a big number when there was none). `wind_from_deg` is the
## wind's compass direction (-1 = no wind data).
func evaluate(p: Aircraft, gap_s: float, wind_from_deg: float) -> void:
	var land_h := deg_to_rad(Airports.land_heading_deg(p.tkind, p.runway, p.land_end))
	# The path's shape is scored once, as drawn (the turn behind the aircraft still counts when it reaches short final).
	if not p.ga_geo:
		_geometry(p, land_h)
		p.ga_turn_pen = pen_turn
		p.ga_len_pen = pen_len
		p.ga_turn_deg = turn_deg
		p.ga_straight = straight_len
		p.ga_geo = true
	else:
		pen_turn = p.ga_turn_pen
		pen_len = p.ga_len_pen
		turn_deg = p.ga_turn_deg
		straight_len = p.ga_straight
	need_len = Tuning.final_need_base + Tuning.final_need_per_speed * p.speed
	pen_space = clampf(1.0 - gap_s / maxf(Tuning.spacing_need_seconds, 0.1), 0.0, 1.0)
	pen_wind = 0.0
	land_off_deg = 0.0
	if wind_from_deg >= 0.0:
		land_off_deg = Airports.angle_diff(rad_to_deg(land_h), wind_from_deg)
		pen_wind = clampf(land_off_deg / 60.0, 0.0, 1.0)
	var c_turn := Tuning.approach_w_turn * pen_turn
	var c_len := Tuning.approach_w_len * pen_len
	var c_space := Tuning.approach_w_space * pen_space
	var c_wind := Tuning.approach_w_wind * pen_wind
	penalty = clampf(c_turn + c_len + c_space + c_wind, 0.0, 1.0)
	reason = Reason.NONE
	if penalty > Tuning.go_around_free:
		var best := c_turn
		reason = Reason.TURN
		if c_len > best:
			best = c_len
			reason = Reason.SHORT_FINAL
		if c_space > best:
			best = c_space
			reason = Reason.SPACING
		if c_wind > best:
			reason = Reason.WIND
	chance = chance_for(penalty)


## A student pilot's standards: the reason this (just evaluated) approach breaks one, or NONE. No dice: the same approach always gives the same answer.
## `gap_s` is the same predicted gap `evaluate` got. `strict` is 1 normally, Tuning.bad_day_limit_mult on Bad Pilot Day (every limit tighter).
## Sets `student_near` when no limit is broken but one is within Tuning.student_near of it.
func student_check(p: Aircraft, gap_s: float, strict: float = 1.0) -> int:
	student_near = false
	var near := Tuning.student_near
	var len_need := student_final_len(p, strict)
	var turn_max := Tuning.student_turn_max_deg * strict
	var gap_need := Tuning.student_gap_seconds / strict
	var wind_max := Tuning.student_wind_deg * strict
	if straight_len < len_need:
		return Reason.SHORT_FINAL
	if turn_deg > turn_max:
		return Reason.TURN
	if gap_s < gap_need:
		return Reason.SPACING
	if land_off_deg > wind_max:
		return Reason.DOWNWIND if land_off_deg > 100.0 else Reason.WIND
	student_near = straight_len < len_need * (1.0 + near) or turn_deg > turn_max * (1.0 - near) or gap_s < gap_need * (1.0 + near) or land_off_deg > wind_max * (1.0 - near)
	return Reason.NONE

## How long a straight final a student wants at this speed (units, behind the threshold): the line the overlay marks. It is never more than the
## field leaves behind that runway end (the drawn approach funnel, less 0.3), so it can always be met; where the field leaves less than a normal
## pilot wants, a student wants what a normal pilot does.
static func student_final_len_at(speed: float, room: float, strict: float = 1.0) -> float:
	var normal := Tuning.final_need_base + Tuning.final_need_per_speed * speed
	return minf(normal * Tuning.student_final_mult / strict, maxf(room - 0.3, normal))

## ...for this plane on its runway end.
static func student_final_len(p: Aircraft, strict: float = 1.0) -> float:
	return student_final_len_at(p.speed, final_room(p.tkind, p.runway, p.land_end), strict)

## The room the field leaves for a final behind a runway end (the approach funnel's length).
static func final_room(kind: int, runway: int, end: int) -> float:
	if kind != Aircraft.Kind.RUNWAY or runway < 0:
		return 99.0
	return Airfield.funnel_length(Airports.end_threshold(runway, end), Airports.end_dir(runway, end))

func _geometry(p: Aircraft, land_h: float) -> void:
	var m := p.count      # aircraft + (count - 1) path points = every point up to the threshold
	var rd := Vector2(sin(land_h), -cos(land_h))
	var aligned := deg_to_rad(Tuning.approach_aligned_deg)
	# Straight, aligned final: walk back from the threshold while the segments follow the runway heading.
	straight_len = 0.0
	var k := m - 1
	while k >= 1:
		var seg := _pt(p, k) - _pt(p, k - 1)
		var l := seg.length()
		if l > 0.0001:
			if absf(rd.angle_to(seg / l)) > aligned:
				break
			straight_len += l
		k -= 1
	# Turning in the last stretch (including the last segment against the runway heading itself).
	var sum := 0.0
	var walked := 0.0
	var prev_dir := rd
	k = m - 1
	while k >= 1 and walked < Tuning.approach_turn_window:
		var seg2 := _pt(p, k) - _pt(p, k - 1)
		var l2 := seg2.length()
		if l2 > 0.0001:
			var dir := seg2 / l2
			sum += absf(prev_dir.angle_to(dir))
			prev_dir = dir
			walked += l2
		k -= 1
	turn_deg = rad_to_deg(sum)
	pen_turn = clampf((turn_deg - Tuning.approach_turn_free_deg) / maxf(Tuning.approach_turn_full_deg - Tuning.approach_turn_free_deg, 1.0), 0.0, 1.0)
	need_len = Tuning.final_need_base + Tuning.final_need_per_speed * p.speed
	pen_len = clampf(1.0 - straight_len / need_len, 0.0, 1.0)

## Penalty -> go-around chance: nothing for a well set-up approach, rising steeply for a bad one.
static func chance_for(pen: float) -> float:
	var x := clampf((pen - Tuning.go_around_free) / maxf(1.0 - Tuning.go_around_free, 0.01), 0.0, 1.0)
	return Tuning.go_around_max * pow(x, Tuning.go_around_curve)

## 0 green, 1 yellow, 2 red.
func band(c: float) -> int:
	return 0 if c < Tuning.tint_yellow_chance else (1 if c < Tuning.tint_red_chance else 2)

static func reason_text(r: int) -> String:
	match r:
		Reason.BUSY: return "runway busy"
		Reason.TURN: return "too sharp a turn"
		Reason.SHORT_FINAL: return "final too short"
		Reason.SPACING: return "too close behind"
		Reason.WIND: return "crosswind"
		Reason.DOWNWIND: return "wind from behind"
		Reason.STUDENT: return "student pilot"
	return ""

## The short tag shown on a student's plane when it breaks a standard.
static func tag_text(r: int) -> String:
	match r:
		Reason.BUSY: return "Runway busy"
		Reason.TURN: return "Turn too tight"
		Reason.SHORT_FINAL: return "Final too short"
		Reason.SPACING: return "Too close behind"
		Reason.WIND: return "Crosswind too strong"
		Reason.DOWNWIND: return "Wind from behind"
	return ""
