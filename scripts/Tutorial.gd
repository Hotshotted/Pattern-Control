class_name Tutorial
extends RefCounted
## Day 1: the scripted first shift at the Grass Strip. Calm wind, slow traffic, no fines, no fail state (planes cannot be lost or collide: the red ring still shows).
##   0  plane 1 arrives alone, the game dims and TIME STOPS; a ghost finger draws the path to the runway end that is into the wind; the player draws it
##   1  it lands and taxis in: "Landed planes park in the hangar. Each landing pays."
##   2  a pause, then planes 2 and 3 arrive close together: "Keep planes apart. A red ring means a crash is coming."
##   3  three more ordinary arrivals with no tips, then the shift ends early with a decent result guaranteed (two stars)
## Main owns it (`_tut`) and calls `tick` from `step`; while `frozen` the simulation does not advance.

var m: Node
var step := 0
var frozen := false
var t := 0.0
var a: Aircraft
var b: Aircraft
var c: Aircraft
var spawned_later := 0
var ghost_clock := 0.0
var ghost_world := PackedVector2Array()
var done := false

const LATER := 3                 # ordinary arrivals after the pair
const GAP := 7.0                 # seconds between them

func begin(main: Node) -> void:
	m = main
	m.traffic.auto_spawn = false
	m.traffic.students_allowed = false
	m.traffic.set_safe(true)
	var e := _into_wind_end()
	a = _spawn(e, 0.0, 2.2, 4.8)
	frozen = true
	m.hud.set_tutorial_layer(1.0, PackedVector2Array(), -1.0, true)
	_show("t_draw")

## The runway end that is into the wind (the green one).
func _into_wind_end() -> int:
	return 0 if m.wind.is_active(0, 0) else 1

func _frame(e: int) -> Array:
	var thr: Vector2 = Airports.end_threshold(0, e)
	var dir: Vector2 = Airports.end_dir(0, e)
	return [thr, dir, Vector2(-dir.y, dir.x)]

## A small plane `back` units behind the threshold of end `e` and `side` to one side, flying at it; it cannot run out of fuel.
func _spawn(e: int, side_k: float, side: float, back: float) -> Aircraft:
	var f := _frame(e)
	var thr: Vector2 = f[0]
	var dir: Vector2 = f[1]
	var sd: Vector2 = f[2]
	var pos: Vector2 = thr - dir * back + sd * (side * (1.0 if side_k == 0.0 else side_k))
	pos.x = clampf(pos.x, -m.traffic.half_w + 0.7, m.traffic.half_w - 0.7)
	pos.y = clampf(pos.y, -m.traffic.half_h + 0.7, m.traffic.half_h - 0.7)
	var v: Vector2 = thr - pos
	var p: Aircraft = m.traffic.place(0, pos, atan2(v.x, -v.y), Aircraft.Type.SMALL)
	if p != null:
		p.runway = 0
		p.entered = true
		p.timer_max = 100000.0
		p.timer_left = 100000.0
	return p

func _show(id: String) -> void:
	var anchor := Vector2(INF, INF)
	if a != null and a.active() and step == 0:
		anchor = m.overlay.world_to_screen(a.pos)
	elif step == 3 and b != null and c != null:
		anchor = m.overlay.world_to_screen((b.pos + c.pos) * 0.5)
	elif step == 1:
		anchor = m.overlay.world_to_screen(Vector2.ZERO)
	m.try_tip(id, anchor)

## One step of the script (called every simulation step, also while frozen).
func tick(dt: float) -> void:
	if done:
		return
	t += dt
	match step:
		0:
			frozen = true
			_ghost(dt)
			if not m.hud.tip_active():
				m.hud.show_tip(Tips.text("t_draw"), "plane", m.overlay.world_to_screen(a.pos), true)
			if a == null or not a.active() or a.cleared:
				frozen = false
				m.hud.set_tutorial_layer(0.0, PackedVector2Array(), -1.0, true)
				m.hud.dismiss_tip()
				step = 1
				t = 0.0
		1:
			if m.shift.landed >= 1:
				_show("t_land")
				step = 2
				t = 0.0
		2:
			if t > 6.0:
				var e := _into_wind_end()
				b = _spawn(e, 1.0, 2.0, 4.6)
				c = _spawn(e, 1.0, 1.4, 6.0)
				step = 3
				t = 0.0
		3:
			if t > 2.5:
				_show("t_apart")
				step = 4
				t = 0.0
		4:
			if m.shift.landed >= 3 or (b != null and not b.active() and c != null and not c.active() and t > 4.0):
				step = 5
				t = GAP
		5:
			if spawned_later < LATER and t >= GAP:
				_spawn(_into_wind_end(), 1.0, -1.6 + 1.6 * float(spawned_later), 4.8)
				spawned_later += 1
				t = 0.0
			elif spawned_later >= LATER and m.traffic.active_count() == 0 and t > 1.5:
				step = 6
		6:
			finish()

## Day 1 is over: a decent result is guaranteed (two stars), and the normal results screen follows.
func finish() -> void:
	if done:
		return
	done = true
	frozen = false
	var th: Array = Tuning.star_thresholds(0)
	var need: int = int(th[1]) - m.shift.balance()
	if need > 0:
		m.shift.bonus += need
	m.tutorial_finished()

func _ghost(dt: float) -> void:
	ghost_clock += dt
	if a == null or not a.active():
		return
	var e := _into_wind_end()
	var f := _frame(e)
	var thr: Vector2 = f[0]
	var dir: Vector2 = f[1]
	var pts := PackedVector2Array()
	pts.append(m.overlay.world_to_screen(a.pos))
	pts.append(m.overlay.world_to_screen(a.pos.lerp(thr - dir * 2.6, 0.5)))
	pts.append(m.overlay.world_to_screen(thr - dir * 2.6))
	pts.append(m.overlay.world_to_screen(thr - dir * 1.2))
	pts.append(m.overlay.world_to_screen(thr))
	var k := fposmod(ghost_clock, 3.0) / 2.2
	m.hud.set_tutorial_layer(1.0, pts, minf(k, 1.0), true)
