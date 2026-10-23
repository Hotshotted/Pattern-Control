extends Node
## Every "feel" value of the game lives here, in one place.
## Registered as the autoload `Tuning`, so any script can read `Tuning.some_value`.
## They are plain vars (not consts) so the ?tune panel can edit them live.
## Distances are world units on the airfield plane: screen-right = +x, screen-down = +z.
## Headings are radians, 0 = screen-up, clockwise positive (direction = (sin h, -cos h)).

# ---------- Frame time ----------
## The simulation never advances more than this per frame (seconds), whatever the real frame took.
var max_frame_delta := 0.05
## A frame longer than this (a tab switch, a long hitch) is a stall: it is not simulated at all.
var stall_delta := 0.25
## Frames skipped (no simulation) after a stall or the window coming back, so nothing catches up.
var resume_skip_frames := 2

# ---------- Camera / screen ----------
## Camera tilt away from straight-down, in degrees, so the sides of the low-poly shapes show.
var camera_tilt_deg := 10.0
## World units visible across the screen WIDTH (orthographic camera size, width locked).
var ortho_size := 10.0

# ---------- Airfield ----------
## (The runways themselves are in Airports.gd.) A path whose end comes within this of the matching
## approach end is cleared to land.
var approach_radius := 1.0
var runway_asphalt := Color("6a7079")      # the lit end; the shading takes it to about #565B66

# ---------- Planes ----------
## Speed classes (units / second): slow props, medium, fast jets.
var speed_slow := 1.5
var speed_medium := 2.2
var speed_fast := 3.1
## All speeds grow up to this multiple over the ramp.
var speed_ramp_max := 1.3
## The plane's visual heading turns this fast (radians / s); its position always follows the path exactly.
var plane_turn_rate := 7.0
## Seconds a landing plane takes to roll out along the runway, and the fraction of the roll before it is on the ground.
var landing_roll_time := 1.5
var touchdown_fraction := 0.2
## A runway stays busy this long after a landing roll ends (a second aircraft reaching it goes around; a landing
## on a CROSSING runway meanwhile is a runway conflict).
var runway_clear_seconds := 1.5
## Terrain hit: an aircraft within a hazard's radius plus this is lost.
var hazard_margin := 0.1
## A plane with no path that gets this close to the edge of the screen turns back toward the field.
var edge_turn_margin := 1.1
## ...in an arc of this radius.
var edge_turn_radius := 1.0

# ---------- Traffic ----------
## How hard each airport is: see `airport_profiles` below (arrival pace, peak traffic, speeds, timers, weather...).
var first_spawn_delay := 0.8
## A new plane is not placed within this of another plane.
var spawn_clear_distance := 2.6

# ---------- Conflicts ----------
## Two airborne planes closer than this end the run.
var conflict_distance := 0.9
## ...and from this distance a warning ring grows around both.
var warn_distance := 2.5

# ---------- Controls ----------
## A touch picks the nearest plane within this of the finger.
var tap_radius := 1.1
## A touch that moves less than this (world units) and is released within tap_max_ms is a tap (holding pattern).
var tap_slop := 0.35
var tap_max_ms := 350
## Points are added to a path this far apart, up to path_max_points.
var path_spacing := 0.3
## Holding pattern: radius of the circle, in world units.
var hold_radius := 1.1

# ---------- Timers and strikes ----------
## Every aircraft has a timer that runs down from when it enters the screen (seconds), by type, shortest first.
var timer_glider := 20.0
var timer_heli := 28.0
var timer_small := 36.0
var timer_medium := 44.0
var timer_jet := 52.0
var timer_seaplane := 32.0
## The ring turns yellow below this fraction of the timer, red below the next one.
var timer_yellow_fraction := 0.5
var timer_red_fraction := 0.25
## A circling aircraft burns its timer at this fraction of the normal rate.
var hold_drain_mult := 0.45
## A timed-out aircraft is diverted (and fined): it flies off at this multiple of its speed.
var divert_speed_mult := 1.6
## Ring colours: plenty of time / low / nearly out.
var timer_color_ok := Color("35c98a")
var timer_color_low := Color("ffc933")
var timer_color_red := Color("ff5c4d")

# ---------- Special aircraft ----------
## An emergency has this fraction of its type's timer, and may land on ANY suitable runway / pad / lane.
var emergency_timer_mult := 0.5
var emergency_bonus_coins := 60
## Chance that a new aircraft is an emergency / a VIP (scaled by the airport; none on the first one).
var emergency_chance := 0.05
## ...and emergencies only start this far into a shift.
var emergency_start_time := 20.0
var vip_chance := 0.08
var vip_bonus_coins := 25
## A helicopter lands when its path ends within this of a helipad's centre; the landing takes this long.
var pad_capture_radius := 0.95
var pad_land_seconds := 1.1
## How long a "first time this type appears" tip stays up.
var tip_seconds := 5.0

# ---------- Upgrades (effect per level; levels come from the save) ----------
var upg_radar_zoom := 0.12          # the view is this much wider per level...
var upg_radar_lead := 0.6           # ...and arrivals are announced this many seconds earlier
var upg_approach_bias := 0.25       # chance an arrival comes in lined up with an active runway, per level
var upg_tower_speed := 0.04         # traffic this much slower per level...
var upg_tower_spawn := 0.06         # ...and arrivals this much rarer
var upg_comms_timer := 0.10         # timers this much longer per level
var upg_holding_drain := 0.20       # holding drains this much slower per level...
var upg_holding_radius := 0.12      # ...and circles this much tighter
var upg_turnoff_clear := 0.30       # runways clear this much faster per level

# ---------- Daily shift and ad stubs ----------
## The first completed daily shift of a day pays this, plus this much per day of streak (up to 7 days).
var daily_bonus_coins := 75
var daily_streak_coins := 13
## The fake "Ad playing" screen lasts this long (no real ads yet). An interstitial comes between shifts at most
## once per this many finished shifts.
var ad_stub_seconds := 2.5
var interstitial_every_shifts := 3

# ---------- Wind ----------
## A runway end is active when its landing heading is within this many degrees of the wind's direction.
var wind_tolerance_deg := 60.0
## Seconds of warning before the wind shifts ("Wind shifting to 270").
var wind_warning_seconds := 8.0
## Seconds between shifts: starts at wind_interval_start, shrinks to wind_interval_min by the end of the shift
## (each airport scales this: later airports shift more often).
var wind_interval_start := 55.0
var wind_interval_min := 28.0   # (both are scaled by the airport's profile)
## A shift turns the wind by at least this many degrees.
var wind_min_change_deg := 60.0

# ---------- Weather events ----------
## The first event is announced this far into a shift; then every weather_interval_* seconds (shrinking over the
## shift, and scaled by the airport), each announced weather_warning_seconds ahead.
var weather_interval_start := 60.0
var weather_interval_min := 32.0
var weather_warning_seconds := 6.0
## Storm: how long the event lasts, how big the cells are, how fast they drift, and how many (1 to 2).
var storm_event_seconds := 22.0
var storm_radius := 1.5
var storm_speed := 0.8
## Fog: how long, how close to the field aircraft must be to be seen, and how fast it rolls in and out.
var fog_seconds := 22.0
var fog_max_alpha := 0.55               # how opaque the densest mist gets (it never hides anything: aircraft are drawn above it)
var fog_poor_go_around_mult := 1.3      # in full fog a POOR approach's go-around chance is this much higher (clean ones: unchanged)
var fog_ambient_db := -22.0             # the soft fog ambience at full fog
var fog_music_tension := 0.8            # the tense music layer at full fog (0..1)
var fog_fade_seconds := 2.5
## Crosswind: how long the runway stays closed.
var crosswind_seconds := 16.0

# ---------- Timed shifts, coins and fines ----------
## A shift lasts exactly this long (seconds), shown as a countdown. Aircraft keep arriving until it ends.
# The shift length is per airport (airport_profiles[i]["shift"]: seconds of arrivals, then "LAST ARRIVALS" and "CLEAR THE SKY").
var shift_scale := 1.0               # ...times this (a tuning knob for every airport at once)
var par_window := 15.0               # PAR comes this long after the last arrival: finish by then for a bonus, after it the clock runs red and costs coins
var early_bonus_per_second := 6      # coins per whole second the sky is clear before par
var overtime_penalty_per_second := 4 # coins per whole second after par
var last_arrivals_seconds := 3.0     # how long the "LAST ARRIVALS" banner shows before the "CLEAR THE SKY" counter
## What a landing pays, by aircraft type (special aircraft pay more).
var pay_glider := 22
var pay_heli := 18
var pay_small := 10
var pay_medium := 14
var pay_jet := 20
var pay_seaplane := 16
## Quick-succession bonus: a landing within this many seconds of the previous one earns streak_bonus_coins per
## landing already in the streak (capped at streak_bonus_cap).
var streak_window_seconds := 4.0
var streak_bonus_coins := 4
var streak_bonus_cap := 5
## Fines: a conflict (both aircraft are lost), a diverted aircraft, and a crash into terrain or a storm.
var fine_conflict := 100
var fine_timeout := 20
var fine_hazard := 50
## After a fine, the "watch an ad to refund it" offer stays up this long (once per shift).

# Go-arounds: approach quality is scored when an aircraft reaches short final.
var short_final_distance := 1.4      # the decision point: this far (along its path) before the threshold
var approach_aligned_deg := 15.0     # path segments within this of the runway heading count as straight final
var approach_turn_window := 3.5      # turning is added up over this much path before the threshold
var approach_turn_free_deg := 45.0   # up to this much turning there costs nothing
var approach_turn_full_deg := 180.0  # ...and this much (a U-turn on final) is the worst
var final_need_base := 0.9           # straight final wanted (units) = base + per_speed * speed (jets need more)
var final_need_per_speed := 0.3
var spacing_need_seconds := 5.0      # wanted gap behind the previous aircraft landing on the same runway
var approach_w_turn := 0.55          # how much each factor counts towards the penalty
var approach_w_len := 0.30
var approach_w_space := 0.09
var approach_w_wind := 0.06
var go_around_free := 0.10           # penalty up to here: no go-around chance at all
var go_around_max := 0.98            # chance at the worst possible approach
var go_around_curve := 1.0
var tint_yellow_chance := 0.12       # final-segment tint: green below this go-around chance, yellow, then red
var tint_red_chance := 0.45
var student_go_around_mult := 2.2    # student pilots: go-around chance x this + the floor (capped at go_around_max)
var student_go_around_floor := 0.25
var tint_distance := 3.0            # how much of the path before the runway is tinted by approach quality
var student_chance := 0.12           # chance an ordinary runway arrival is a student pilot ("L" badge)
var student_pay_mult := 2.0          # students pay double when they land
var bad_day_go_around_mult := 3.0    # Bad Pilot Day: every aircraft is a student, with far higher go-around chances
var bad_day_go_around_floor := 0.6
var bad_day_pay_mult := 1.5          # ...and every landing pays big (x student_pay_mult as well)
var bad_day_threshold_mult := 2.5    # ...so the star thresholds are higher
var bad_day_bonus_mult := 2.0        # ...and so is the completion bonus
var go_around_climb_seconds := 1.6   # how long the climb-out lift shows
## The first time a star is ever earned at an airport it pays this much extra.
var landing_keep_fraction := 0.5   # the share of a shift's landing pay that is always kept, whatever the fines
var coins_first_star_bonus := 100

# ---------- Entry warning ----------
## Seconds before a plane appears on screen that a glow shows on the edge where it will come in.
var entry_warning_seconds := 2.0
## The glow's colour by speed class: green slow, yellow medium, red fast (kept apart from the runway
## colours and from the red/white low-fuel flash by the black ring and the arrow).
var entry_color_slow := Color(0.2, 0.95, 0.4)
var entry_color_medium := Color(1.0, 0.92, 0.15)
var entry_color_fast := Color(0.95, 0.1, 0.35)
## ...and how fast it pulses (Hz): faster planes pulse faster.
var entry_pulse_slow := 1.2
var entry_pulse_medium := 2.2
var entry_pulse_fast := 4.0

# ---------- Flight paths ----------
## The drawn path starts at the plane's nose, runs under the plane, and is faded to path_fade_min opacity
## at the nose, reaching full opacity path_fade_distance further along.
var path_fade_distance := 1.6
var path_fade_min := 0.25
var path_width := 0.1
var path_outline_width := 0.2

# ---------- Feedback ----------
var ripple_time := 0.8
var burst_count := 22
var burst_lifetime := 0.7
var popup_time := 0.9
var haptic_ms := 25
var score_punch := 0.35

# ---------- Start-up pre-warm ----------
var prewarm_min_seconds := 1.5
var prewarm_stable_frames := 10
var prewarm_stable_ms := 45.0
var prewarm_max_seconds := 6.0

# ---------- Look ----------
var intro_logo := true                # the animated studio / game logo at boot (skippable)
var grass_color := Color(0.36, 0.62, 0.36)
var outline_thickness := 0.03

# ---------- Airport difficulty ----------
## One profile per airport, in order: easy first, building up. Keys:
##   shift          seconds of arrivals (the spawning window); par is 15 s later
##   max_planes     peak traffic: no new arrival while this many aircraft are on the field
##   spawn_start / spawn_min   seconds between arrivals at the start / at the busiest point
##   ramp           how soon the busiest point is reached, as a fraction of the spawning window (lower = steeper)
##   speed, timer   multiply every aircraft's speed / its timer
##   specials       emergency + VIP chance multiplier (0 = none)
##   weather        how often weather events come (1 = normal, bigger = rarer, 0 = none at all)
##   wind           how often the wind shifts (1 = normal, bigger = rarer, 0 = it never shifts)
##   weather_first / wind_first   no weather / wind shift before this many seconds into a shift
##   fines          multiplies every fine (conflict / diversion / terrain / storm)
##   stars          net coins for 1, 2 and 3 stars
##   beats          [[seconds, aircraft type], ...]: a new mechanic arrives alone at about this time
##                  (types: 0 glider, 1 helicopter, 2 small, 3 medium, 4 jet, 5 seaplane)
## Today's (pre-profile) intensity was: 12 planes, 5.0 -> 1.7 s, ramp 0.83, speed 1, timer 1, specials 1.
var airport_profiles := [
	{"name": "Grass Strip", "shift": 45, "max_planes": 3, "spawn_start": 7.0, "spawn_min": 4.4, "ramp": 0.9, "speed": 0.75, "timer": 1.5,
		"specials": 0.0, "weather": 0.0, "wind": 0.0, "weather_first": 999.0, "wind_first": 999.0, "fines": 0.4, "stars": [15, 35, 55], "beats": [[5.0, 0]]},
	{"name": "County", "shift": 60, "max_planes": 4, "spawn_start": 6.5, "spawn_min": 4.0, "ramp": 0.9, "speed": 0.85, "timer": 1.35,
		"specials": 0.3, "weather": 0.0, "wind": 2.2, "weather_first": 999.0, "wind_first": 35.0, "fines": 0.6, "stars": [30, 60, 90], "beats": [[5.0, 2]]},
	{"name": "Regional", "shift": 75, "max_planes": 6, "spawn_start": 6.0, "spawn_min": 3.2, "ramp": 0.85, "speed": 0.92, "timer": 1.2,
		"specials": 0.6, "weather": 1.6, "wind": 1.5, "weather_first": 50.0, "wind_first": 38.0, "fines": 0.8, "stars": [50, 100, 150], "beats": [[5.0, 1], [24.0, 4]]},
	{"name": "Mountain Field", "shift": 75, "max_planes": 10, "spawn_start": 5.2, "spawn_min": 2.2, "ramp": 0.83, "speed": 1.0, "timer": 1.0,
		"specials": 1.0, "weather": 1.0, "wind": 1.0, "weather_first": 45.0, "wind_first": 35.0, "fines": 1.0, "stars": [65, 130, 200], "beats": [[5.0, 2]]},
	{"name": "Island", "shift": 90, "max_planes": 12, "spawn_start": 4.8, "spawn_min": 1.9, "ramp": 0.8, "speed": 1.05, "timer": 0.95,
		"specials": 1.1, "weather": 0.85, "wind": 0.8, "weather_first": 40.0, "wind_first": 32.0, "fines": 1.0, "stars": [100, 200, 300], "beats": [[5.0, 5]]},
	{"name": "International", "shift": 90, "max_planes": 14, "spawn_start": 4.2, "spawn_min": 1.5, "ramp": 0.75, "speed": 1.12, "timer": 0.9,
		"specials": 1.5, "weather": 0.7, "wind": 0.6, "weather_first": 35.0, "wind_first": 30.0, "fines": 1.0, "stars": [115, 230, 340], "beats": [[5.0, 1], [22.0, 5], [40.0, 4]]},
]
## An airport's first shift is gentler: arrivals this much further apart, timers this much longer.
var intro_spawn_scale := 1.3
var intro_timer_scale := 1.2
var intro_active := false              # set by the game at the start of a shift
## A beat's aircraft arrives alone: nothing else is sent this long before it, and for this long after it.
var beat_quiet_lead := 4.0
var beat_gap := 10.0

# ---------- Derived ----------
func profile(i: int = -1) -> Dictionary:
	return airport_profiles[clampi(Airports.current if i < 0 else i, 0, airport_profiles.size() - 1)]

## This airport's shift: arrivals for this long (45 / 60 / 75 / 90 s by airport), then par a fixed window later.
func spawn_stop_eff() -> float:
	return float(profile()["shift"]) * shift_scale

func par_eff() -> float:
	return spawn_stop_eff() + par_window

func star_thresholds(i: int = -1) -> Array:
	return profile(i)["stars"]

## A fine's size at this airport: the base amount (fine_conflict...) scaled by the airport's profile.
func fine_amount(base: float) -> int:
	return roundi(base * float(profile()["fines"]))

func max_planes_eff() -> int:
	return int(profile()["max_planes"])

func specials_mult() -> float:
	return float(profile()["specials"])

## Seconds between arrivals at run time t, from the profile (and the gentle first shift).
func spawn_interval(t: float) -> float:
	var p := profile()
	return lerpf(float(p["spawn_start"]), float(p["spawn_min"]), spawn_progress(t)) * (intro_spawn_scale if intro_active else 1.0)

## Seconds until the first wind shift, and between shifts (INF = this airport's wind never shifts).
func wind_first_eff() -> float:
	var p := profile()
	return INF if float(p["wind"]) <= 0.0 else float(p["wind_first"])

func wind_scale_eff() -> float:
	var w := float(profile()["wind"])
	return INF if w <= 0.0 else w

func weather_scale_eff() -> float:
	var w := float(profile()["weather"])
	return INF if w <= 0.0 else w

func weather_first_eff() -> float:
	return float(profile()["weather_first"])

func upg(id: String) -> int:
	return Save.upgrade_level(id)

func timer_mult() -> float:
	return (1.0 + upg_comms_timer * upg("comms")) * float(profile()["timer"]) * (intro_timer_scale if intro_active else 1.0)

func hold_drain() -> float:
	return hold_drain_mult * (1.0 - upg_holding_drain * upg("holding"))

func hold_radius_eff() -> float:
	return hold_radius * (1.0 - upg_holding_radius * upg("holding"))

func runway_clear() -> float:
	return runway_clear_seconds * (1.0 - upg_turnoff_clear * upg("turnoffs"))

func traffic_speed_mult() -> float:
	return 1.0 - upg_tower_speed * upg("tower")

func traffic_spawn_mult() -> float:
	return 1.0 + upg_tower_spawn * upg("tower")

func approach_bias() -> float:
	return upg_approach_bias * upg("approach")

func entry_lead() -> float:
	return entry_warning_seconds + upg_radar_lead * upg("radar")

## World units visible across the screen width: the radar zooms out.
func view_size() -> float:
	return ortho_size * (1.0 + upg_radar_zoom * upg("radar"))

## How far up the traffic ramp we are, 0..1: it always reaches the full, busy finish by the time spawning stops.
func spawn_progress(t: float) -> float:
	return clampf(t / maxf(float(profile()["ramp"]) * spawn_stop_eff(), 1.0), 0.0, 1.0)

func speed_mult(t: float) -> float:
	return lerpf(1.0, speed_ramp_max, spawn_progress(t)) * float(profile()["speed"])

## The ring colour for a fraction of the timer left.
func timer_color(frac: float) -> Color:
	if frac <= timer_red_fraction:
		return timer_color_red
	if frac <= timer_yellow_fraction:
		return timer_color_low
	return timer_color_ok

func landing_pay(type: int) -> int:
	return [pay_glider, pay_heli, pay_small, pay_medium, pay_jet, pay_seaplane][type]

func type_timer(type: int) -> float:
	return [timer_glider, timer_heli, timer_small, timer_medium, timer_jet, timer_seaplane][type]

## Speed by type (units / second), and the class (0 slow / 1 medium / 2 fast) that picks the entry glow and model.
func type_speed(type: int) -> float:
	return [speed_slow * 0.8, speed_slow * 1.2, speed_slow, speed_medium, speed_fast, speed_slow * 1.1][type]

func type_speed_class(type: int) -> int:
	return [0, 1, 0, 1, 2, 0][type]

func entry_color(c: int) -> Color:
	return [entry_color_slow, entry_color_medium, entry_color_fast][c]

func entry_pulse(c: int) -> float:
	return [entry_pulse_slow, entry_pulse_medium, entry_pulse_fast][c]
