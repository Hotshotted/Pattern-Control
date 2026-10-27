class_name Aircraft
extends RefCounted
## The state of one pooled aircraft. All of them are created once at start-up (Traffic.MAX_POOL);
## spawning only resets the fields, so nothing is allocated during a run.

const PATH_MAX := 220

enum State { IDLE, FLY, HOLD, LANDING, DIVERT }
## Aircraft types, shortest timer first. (Gliders and helicopters get their own rules in a later phase.)
enum Type { GLIDER, HELI, SMALL, MEDIUM, JET, SEAPLANE }
## What an aircraft lands on: a runway end, a helipad, or a water lane.
enum Kind { RUNWAY, PAD, LANE }

var state := State.IDLE
var tkind := Kind.RUNWAY        # what it lands on...
var runway := 0                 # ...which one (a runway, pad or lane index; it also gives the colour)
var any_target := false         # emergencies may use any suitable runway / pad / lane
var emergency := false
var vip := false
var vip_ok := true              # a VIP put into holding loses its bonus
var locked := false             # gliders with no engines (the "No engines" challenge): the first path is final
var one_shot := false           # "No engines": no go-around, a busy runway or a missed approach is a crash
var hovering := false
var fogged := false             # hidden in the fog (too far from the field to be seen)
var type := Type.SMALL
var speed_class := 0            # 0 slow, 1 medium, 2 fast (the entry glow colour and the model)
var speed := 2.0                # base units / second (before the run's speed ramp)
var pos := Vector2.ZERO
var step_from := Vector2.ZERO    # where it was at the start of this step (the conflict and storm tests sweep the whole step, so a big step cannot skip over a pass)
var heading := 0.0              # direction of travel
var vis_heading := 0.0          # drawn heading (turns toward `heading` at plane_turn_rate)
var entered := false            # has been on screen (planes still outside can't conflict)
var ground := false             # touched down: can't conflict any more
var cleared := false            # its path ends on the runway: it will land
var timer_max := 30.0           # seconds on screen before it is diverted (a strike)
var timer_left := 30.0
var warn := 0.0                 # 0..1 how close it is to another plane (drives the warning ring)
var roll_t := 0.0               # landing roll progress 0..1
var roll_from := Vector2.ZERO
var hold_center := Vector2.ZERO
var hold_angle := 0.0
var age := 0.0
var entry := Vector2.ZERO       # where it comes onto the screen (the edge glow shows here until it appears)
var wrong_shown := false        # this drag already flashed "wrong runway"
var inactive_shown := false     # ...or "runway not active"
var land_end := 0               # which end of its runway it is landing on
var path_invalid := false       # the wind shifted: its path ends on a closed runway end (drawn dashed red)
var ga_checked := false         # the short-final go-around decision has been made for this approach
var ga_geo := false             # the path's geometry (turning, final length) has been scored: it is fixed once drawn
var ga_turn_pen := 0.0
var ga_len_pen := 0.0
var ga_turn_deg := 0.0
var ga_chance := 0.0            # predicted go-around chance of the cleared approach (drives the path tint)
var ga_band := 0                # 0 green, 1 yellow, 2 red
var low_fuel := false           # its timer ran out while it was locked on final: it still lands, and the score pop says so
var student := false            # student pilot: far more go-arounds, double coins
var ga_pending := false         # a go-around is signalled and about to happen (wobble, '?' tag)
var ga_t := 0.0                 # seconds until it does
var ga_reason := 0
var ga_roll := 0.0              # the go-around chance it was rolled at
var ga_redrawn := false         # the player has started a new final since the warning
var red_seen := false           # its timer ring has turned red (it pulses once when it does)
var red_pulse_t := -1.0         # seconds since that pulse started (-1 = none)
var go_arounds := 0             # how many times it has gone around
var climb := 0.0                # seconds of go-around climb-out left (a small lift on screen)
var bank := 0.0                 # roll angle (radians) into a turn: drawn, smoothed
var prev_vis := 0.0             # last frame's drawn heading (for the turn rate)
var touched := false            # the wheels are down (the touchdown puff happened)
var pop_t := 0.0                # seconds of touchdown 'pop' left
var warn_other: Aircraft = null    # the plane it is close to (for the warning line)

# Path: points[head .. head+count) are still to be flown (a plain array that compacts when full).
var pts := PackedVector2Array()
var head := 0
var count := 0
var draw_buf := PackedVector2Array()   # scratch for the overlay (pos + remaining points)
var ghost := PackedVector2Array()      # the path a tap just cleared: it fades out (drawn by PathRibbons)
var ghost_n := 0
var ghost_t := 0.0                     # seconds of fade left

func _init() -> void:
	pts.resize(PATH_MAX)
	ghost.resize(PATH_MAX)
	draw_buf.resize(PATH_MAX + 1)

func reset() -> void:
	state = State.IDLE
	entered = false
	ground = false
	cleared = false
	low_fuel = false
	timer_left = timer_max
	warn = 0.0
	warn_other = null
	wrong_shown = false
	inactive_shown = false
	path_invalid = false
	ga_checked = false
	ga_geo = false
	ga_chance = 0.0
	ga_band = 0
	climb = 0.0
	bank = 0.0
	touched = false
	pop_t = 0.0
	student = false
	go_arounds = 0
	red_seen = false
	red_pulse_t = -1.0
	ga_pending = false
	ga_t = 0.0
	ga_redrawn = false
	ga_roll = 0.0
	any_target = false
	emergency = false
	vip = false
	vip_ok = true
	locked = false
	one_shot = false
	hovering = false
	fogged = false
	tkind = Kind.RUNWAY
	roll_t = 0.0
	age = 0.0
	head = 0
	count = 0
	ghost_t = 0.0
	ghost_n = 0

func clear_path() -> void:
	head = 0
	count = 0
	cleared = false
	path_invalid = false
	ga_checked = false
	ga_geo = false
	ga_chance = 0.0
	ga_band = 0

## Clear the path, but keep a copy that fades out (a tap on the plane).
func fade_path(seconds: float) -> void:
	if count > 0:
		for i in count:
			ghost[i] = pts[head + i]
		ghost_n = count
		ghost_t = seconds
	clear_path()

func last_point() -> Vector2:
	return pts[head + count - 1] if count > 0 else pos

## Add a point to the end of the path, leaving `reserve` slots free (for the runway points).
## Returns false if the path is full.
func push(p: Vector2, reserve: int = 0) -> bool:
	if head + count >= PATH_MAX - reserve:
		if head == 0:
			return false
		for i in count:          # compact: move the unflown points to the start
			pts[i] = pts[head + i]
		head = 0
		if count >= PATH_MAX - reserve:
			return false
	pts[head + count] = p
	count += 1
	return true

func pop() -> void:
	head += 1
	count -= 1
	if count == 0:
		head = 0

func active() -> bool:
	return state != State.IDLE

## Ground planes, planes in the landing roll, diverting planes and planes still off screen never conflict: only the air does.
func can_conflict() -> bool:
	return state != State.IDLE and state != State.DIVERT and state != State.LANDING and entered and not ground

## Fraction of the timer left, 1 -> 0.
func timer_frac() -> float:
	return clampf(timer_left / maxf(timer_max, 0.01), 0.0, 1.0)

## Emergencies never go around (they land or are lost), nor does anything in the "No engines" challenge; only runway landings are scored.
func can_go_around() -> bool:
	return tkind == Kind.RUNWAY and not emergency and not one_shot

## Is the approach judged (the path tint, the go-around dice)? Everything but an emergency. In "No engines" a failed one is a crash.
func approach_scored() -> bool:
	return tkind == Kind.RUNWAY and not emergency

## A glider in the "No engines" challenge: its first path is final and it cannot hold.
func glider_one_shot() -> bool:
	return type == Type.GLIDER and one_shot
