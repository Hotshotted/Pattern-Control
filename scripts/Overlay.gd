class_name Overlay
extends CanvasLayer
## Everything drawn flat over the field: approach markers, flight paths, holding circles, the
## warning rings, the low-fuel timers, landing ripples and the selection ring. Drawn in world
## units through the camera's top-down transform. Nothing is allocated per frame: the ripple pool
## and every plane's point buffer are fixed-size.

const RIPPLES := 8
const BLACK := Color(0, 0, 0, 0.85)

var traffic: Traffic
var camera: Camera3D
var xf := Transform2D.IDENTITY       # world (x, z) -> viewport pixels
var inv := Transform2D.IDENTITY
var selected: Aircraft = null           # the plane being dragged
var active_runway := -1              # runway the dragged plane is aiming for (its marker pulses)
var glows_drawn := 0                 # entry glows drawn last frame

var _c: Control
var _rip_pos := PackedVector2Array()
var _rip_col := PackedColorArray()
var _rip_born := PackedInt64Array()
var _rip_scale := PackedFloat32Array()
var _next_rip := 0

func _ready() -> void:
	layer = 1
	_c = Control.new()
	_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw_all)
	add_child(_c)
	_rip_pos.resize(RIPPLES)
	_rip_col.resize(RIPPLES)
	_rip_born.resize(RIPPLES)
	_rip_scale.resize(RIPPLES)

func _process(_delta: float) -> void:
	_update_transform()
	_c.queue_redraw()

func _update_transform() -> void:
	if camera == null:
		return
	var y := Traffic.PLANE_Y
	var o := camera.unproject_position(Vector3(0, y, 0))
	var ex := camera.unproject_position(Vector3(1, y, 0)) - o
	var ez := camera.unproject_position(Vector3(0, y, 1)) - o
	xf = Transform2D(ex, ez, o)
	inv = xf.affine_inverse()

func world_to_screen(w: Vector2) -> Vector2:
	return xf * w

func screen_to_world(s: Vector2) -> Vector2:
	return inv * s

## An expanding ring at a spot on the field.
func ripple(at: Vector2, color: Color, size: float = 1.0) -> void:
	if DebugFlags.off("ripple"):
		return
	_rip_pos[_next_rip] = at
	_rip_col[_next_rip] = color
	_rip_born[_next_rip] = Time.get_ticks_msec()
	_rip_scale[_next_rip] = size
	_next_rip = (_next_rip + 1) % RIPPLES

func clear() -> void:
	_rip_born.fill(0)
	selected = null
	active_runway = -1

func _draw_all() -> void:
	if traffic == null:
		return
	var now := Time.get_ticks_msec()
	var t := now / 1000.0
	_c.draw_set_transform_matrix(xf)
	_draw_runway_markers(t)
	for p in traffic.planes:
		if p.state == Aircraft.State.HOLD and not DebugFlags.off("hold"):
			var col := Airports.rw_color(p.runway)
			_c.draw_arc(p.hold_center, Tuning.hold_radius, 0.0, TAU, 40, BLACK, 0.16)
			_c.draw_arc(p.hold_center, Tuning.hold_radius, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.8), 0.07)
	glows_drawn = 0
	for p in traffic.planes:
		if p.active() and not p.entered:
			_draw_entry_glow(p, t)
	for p in traffic.planes:
		if not p.active():
			continue
		if p.warn > 0.0:
			_draw_warning(p, t)
		if p.entered and (p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD):
			_draw_timer_ring(p, t)
	if selected != null and selected.active():
		_c.draw_arc(selected.pos, 0.85, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 0.07)
	for i in RIPPLES:
		if _rip_born[i] == 0:
			continue
		var a := (now - _rip_born[i]) / (Tuning.ripple_time * 1000.0)
		if a >= 1.0:
			_rip_born[i] = 0
			continue
		var col := _rip_col[i]
		col.a = 1.0 - a
		_c.draw_arc(_rip_pos[i], (0.4 + 2.2 * a) * _rip_scale[i], 0.0, TAU, 40, col, 0.14 * (1.0 - a) + 0.03)

func _draw_runway_markers(t: float) -> void:
	for i in Airports.rw_count():
		var col := Airports.rw_color(i)
		var thr := Airports.rw_threshold(i)
		var dir := Airports.rw_dir(i)
		var side := Vector2(-dir.y, dir.x)
		var hot := active_runway == i
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		var r := Tuning.approach_radius * (1.0 + 0.08 * pulse if hot else 1.0)
		_c.draw_arc(thr, r, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 0.16)
		_c.draw_arc(thr, r, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.95 if hot else 0.6), 0.08)
		# Approach funnel: two dashed lines opening out behind the threshold, with chevrons.
		var far := thr - dir * 3.4
		for s in [-1.0, 1.0]:
			_c.draw_dashed_line(thr + side * s * 0.35, far + side * s * 1.4, Color(col.r, col.g, col.b, 0.55), 0.07, 0.25)
		for k in 3:
			var c := thr - dir * (1.5 + k * 0.7)
			var a := 0.25 + 0.55 * clampf(1.0 - absf(fmod(t * 1.5, 3.0) - k), 0.0, 1.0)
			_c.draw_line(c - side * 0.3 - dir * 0.0, c + dir * 0.3, Color(col.r, col.g, col.b, a), 0.09)
			_c.draw_line(c + side * 0.3 - dir * 0.0, c + dir * 0.3, Color(col.r, col.g, col.b, a), 0.09)

## The edge glow for a plane that is about to come in: a pulsing beacon in its speed colour on the screen
## edge at its entry point (half of it is off screen), with an arrow pointing the way it will fly.
func _draw_entry_glow(p: Aircraft, t: float) -> void:
	glows_drawn += 1
	var col := Tuning.entry_color(p.speed_class)
	var hz := Tuning.entry_pulse(p.speed_class)
	var pulse := 0.5 + 0.5 * sin(TAU * hz * t)
	var fade := clampf(p.age / 0.25, 0.0, 1.0)
	var dir := Vector2(sin(p.heading), -cos(p.heading))
	var side := Vector2(-dir.y, dir.x)
	var e := p.entry
	for k in 4:   # soft glow: stacked translucent discs
		var r := (0.5 + 0.35 * k) * (1.0 + 0.18 * pulse)
		_c.draw_circle(e, r, Color(col.r, col.g, col.b, (0.16 + 0.1 * pulse) * fade))
	var ring := 0.55 + 0.25 * pulse
	_c.draw_arc(e, ring, 0.0, TAU, 32, Color(0, 0, 0, 0.75 * fade), 0.2)
	_c.draw_arc(e, ring, 0.0, TAU, 32, Color(col.r, col.g, col.b, (0.6 + 0.4 * pulse) * fade), 0.1)
	var tip := e + dir * (0.7 + 0.15 * pulse)
	for s in [-1.0, 1.0]:
		var wing: Vector2 = tip - dir * 0.4 + side * s * 0.3
		_c.draw_line(tip, wing, Color(0, 0, 0, 0.8 * fade), 0.2)
		_c.draw_line(tip, wing, Color(col.r, col.g, col.b, fade), 0.1)

func _draw_warning(p: Aircraft, t: float) -> void:
	var w := p.warn
	var pulse := 0.5 + 0.5 * sin(t * (8.0 + 10.0 * w))
	var r := 0.75 + 0.35 * w + 0.08 * pulse
	_c.draw_arc(p.pos, r, 0.0, TAU, 32, Color(0, 0, 0, 0.8), 0.2)
	_c.draw_arc(p.pos, r, 0.0, TAU, 32, Color(1.0, 0.15 + 0.2 * pulse, 0.1, 0.5 + 0.5 * w), 0.11)
	var o := p.warn_other
	if o != null and o.get_instance_id() > p.get_instance_id():
		_c.draw_dashed_line(p.pos, o.pos, Color(1, 0.2, 0.15, 0.4 + 0.5 * w), 0.07, 0.2)

## The timer ring around an aircraft: it empties as time runs out, yellow then red, and pulses when nearly out.
func _draw_timer_ring(p: Aircraft, t: float) -> void:
	var frac := p.timer_frac()
	var col := Tuning.timer_color(frac)
	var w := 0.1
	if frac <= Tuning.timer_red_fraction:
		w += 0.05 * (0.5 + 0.5 * sin(t * 14.0))
	var r := 0.95
	var end := -PI * 0.5 + TAU * maxf(frac, 0.01)
	_c.draw_arc(p.pos, r, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 0.2)          # the empty track
	_c.draw_arc(p.pos, r, -PI * 0.5, end, 32, Color(0, 0, 0, 0.85), w + 0.1)
	_c.draw_arc(p.pos, r, -PI * 0.5, end, 32, col, w)

## Pre-warm: draw every kind of mark at once (paths on every plane, rings, ripples, timers).
func prewarm() -> void:
	for p in traffic.planes:
		if p.state == Aircraft.State.FLY:
			p.count = 0
			p.head = 0
			for k in 24:
				p.push(p.pos + Vector2(sin(p.heading + k * 0.05), -cos(p.heading + k * 0.05)) * (0.4 * (k + 1)))
			p.warn = 0.6
	for i in RIPPLES:
		ripple(Vector2(-3.0 + (i % 4) * 2.0, 0.0 + (i / 4) * 3.0), Airports.rw_color(i % Airports.rw_count()), 1.0)
