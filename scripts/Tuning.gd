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
var runway_asphalt := Color(0.24, 0.25, 0.28)

# ---------- Planes ----------
## Speed classes (units / second): slow props, medium, fast jets.
var speed_slow := 1.5
var speed_medium := 2.2
var speed_fast := 3.1
## All speeds grow up to this multiple over `spawn_ramp_seconds`.
var speed_ramp_max := 1.3
## The plane's visual heading turns this fast (radians / s); its position always follows the path exactly.
var plane_turn_rate := 7.0
## Seconds a landing plane takes to roll out along the runway, and the fraction of the roll before it is on the ground.
var landing_roll_time := 1.5
var touchdown_fraction := 0.2
## A plane with no path that gets this close to the edge of the screen turns back toward the field.
var edge_turn_margin := 1.1
## ...in an arc of this radius.
var edge_turn_radius := 1.0

# ---------- Traffic ----------
## Seconds between new planes: starts at spawn_interval_start, shrinks to spawn_interval_min over spawn_ramp_seconds.
var spawn_interval_start := 5.0
var spawn_interval_min := 1.7
var spawn_ramp_seconds := 150.0
var first_spawn_delay := 0.8
## No more than this many planes at once (the pool holds MAX_POOL).
var max_planes := 12.0
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
## The ring turns yellow below this fraction of the timer, red below the next one.
var timer_yellow_fraction := 0.5
var timer_red_fraction := 0.25
## A circling aircraft burns its timer at this fraction of the normal rate.
var hold_drain_mult := 0.45
## A timed-out aircraft is diverted: it flies off at this multiple of its speed. It is a strike.
var divert_speed_mult := 1.6
var max_strikes := 3.0
## Ring colours: plenty of time / low / nearly out.
var timer_color_ok := Color(0.35, 0.92, 0.5)
var timer_color_low := Color(1.0, 0.86, 0.2)
var timer_color_red := Color(1.0, 0.2, 0.15)

# ---------- Shifts, stars, coins ----------
## Planes stop arriving after this long; the shift ends when the field is clear (or on 3 strikes / a conflict).
var shift_seconds := 150.0
var coins_per_landing := 5
var coins_per_star := 25
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
var grass_color := Color(0.36, 0.62, 0.36)
var outline_thickness := 0.05

# ---------- Derived ----------
func spawn_progress(t: float) -> float:
	return clampf(t / maxf(spawn_ramp_seconds, 1.0), 0.0, 1.0)

func spawn_interval(t: float) -> float:
	return lerpf(spawn_interval_start, spawn_interval_min, spawn_progress(t))

func speed_mult(t: float) -> float:
	return lerpf(1.0, speed_ramp_max, spawn_progress(t))

## The ring colour for a fraction of the timer left.
func timer_color(frac: float) -> Color:
	if frac <= timer_red_fraction:
		return timer_color_red
	if frac <= timer_yellow_fraction:
		return timer_color_low
	return timer_color_ok

func type_timer(type: int) -> float:
	return [timer_glider, timer_heli, timer_small, timer_medium, timer_jet][type]

## Speed by type (units / second), and the class (0 slow / 1 medium / 2 fast) that picks the entry glow and model.
func type_speed(type: int) -> float:
	return [speed_slow * 0.8, speed_slow * 1.2, speed_slow, speed_medium, speed_fast][type]

func type_speed_class(type: int) -> int:
	return [0, 1, 0, 1, 2][type]

func entry_color(c: int) -> Color:
	return [entry_color_slow, entry_color_medium, entry_color_fast][c]

func entry_pulse(c: int) -> float:
	return [entry_pulse_slow, entry_pulse_medium, entry_pulse_fast][c]
