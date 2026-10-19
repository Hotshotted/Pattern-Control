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
var locked := false             # gliders: the first path is final
var hovering := false
var fogged := false             # hidden in the fog (too far from the field to be seen)
var type := Type.SMALL
var speed_class := 0            # 0 slow, 1 medium, 2 fast (the entry glow colour and the model)
var speed := 2.0                # base units / second (before the run's speed ramp)
var pos := Vector2.ZERO
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
var student := false            # student pilot: far more go-arounds, double coins
var go_arounds := 0             # how many times it has gone around
var climb := 0.0                # seconds of go-around climb-out left (a small lift on screen)
var warn_other: Aircraft = null    # the plane it is close to (for the warning line)

# Path: points[head .. head+count) are still to be flown (a plain array that compacts when full).
var pts := PackedVector2Array()
var head := 0
var count := 0
var draw_buf := PackedVector2Array()   # scratch for the overlay (pos + remaining points)

func _init() -> void:
	pts.resize(PATH_MAX)
	draw_buf.resize(PATH_MAX + 1)

func reset() -> void:
	state = State.IDLE
	entered = false
	ground = false
	cleared = false
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
	student = false
	go_arounds = 0
	any_target = false
	emergency = false
	vip = false
	vip_ok = true
	locked = false
	hovering = false
	fogged = false
	tkind = Kind.RUNWAY
	roll_t = 0.0
	age = 0.0
	head = 0
	count = 0

func clear_path() -> void:
	head = 0
	count = 0
	cleared = false
	path_invalid = false
	ga_checked = false
	ga_geo = false
	ga_chance = 0.0
	ga_band = 0

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

## Ground planes, diverting planes and planes still off screen never conflict.
func can_conflict() -> bool:
	return state != State.IDLE and state != State.DIVERT and entered and not ground

## Fraction of the timer left, 1 -> 0.
func timer_frac() -> float:
	return clampf(timer_left / maxf(timer_max, 0.01), 0.0, 1.0)

## Gliders and emergencies never go around (they land or are lost); only runway landings are scored.
func can_go_around() -> bool:
	return tkind == Kind.RUNWAY and type != Type.GLIDER and not emergency
