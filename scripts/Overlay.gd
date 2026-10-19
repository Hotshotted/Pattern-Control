class_name Overlay
extends CanvasLayer
## Everything drawn flat over the field: approach markers, flight paths, holding circles, the
## warning rings, the low-fuel timers, landing ripples and the selection ring. Drawn in world
## units through the camera's top-down transform. Nothing is allocated per frame: the ripple pool
## and every plane's point buffer are fixed-size.

const RIPPLES := 8
const BLACK := Color(0, 0, 0, 0.85)

var traffic: Traffic
var wind: Wind
var camera: Camera3D
var xf := Transform2D.IDENTITY       # world (x, z) -> viewport pixels
var inv := Transform2D.IDENTITY
var _students_drawn := 0
var selected: Aircraft = null           # the plane being dragged
var active_runway := -1              # runway the dragged plane is aiming for (its marker pulses)
var glows_drawn := 0                 # entry glows drawn last frame

var _c: Control
var _font: Font
var _rip_pos := PackedVector2Array()
var _rip_col := PackedColorArray()
var _rip_born := PackedInt64Array()
var _rip_scale := PackedFloat32Array()
var _next_rip := 0

func _ready() -> void:
	layer = 1
	_font = ThemeDB.fallback_font
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
	_draw_place_markers(t)
	for p in traffic.planes:
		if p.state == Aircraft.State.HOLD and not p.fogged and not DebugFlags.off("hold"):
			var col := Airports.land_color(p.tkind, p.runway)
			if p.hovering:   # a helicopter hovers on the spot
				_c.draw_arc(p.pos, 0.62, 0.0, TAU, 24, BLACK, 0.16)
				_c.draw_arc(p.pos, 0.62, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.8), 0.07)
			else:
				_c.draw_arc(p.hold_center, Tuning.hold_radius_eff(), 0.0, TAU, 40, BLACK, 0.16)
				_c.draw_arc(p.hold_center, Tuning.hold_radius_eff(), 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.8), 0.07)
	glows_drawn = 0
	_draw_hazards(t)
	for p in traffic.planes:
		if p.active() and not p.entered:
			_draw_entry_glow(p, t)
	for p in traffic.planes:
		if not p.active():
			continue
		if p.warn > 0.0:
			_draw_warning(p, t)
		if p.entered and not p.fogged and (p.state == Aircraft.State.FLY or p.state == Aircraft.State.HOLD):
			_draw_timer_ring(p, t)
	_draw_closures(t)
	_draw_fog()
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
	# Little text tags above special aircraft, in screen space.
	_c.draw_set_transform_matrix(Transform2D.IDENTITY)
	if wind != null:
		for r in Airports.rw_count():
			if wind.is_closed(r):
				_tag(xf * Airports.rw_center(r) + Vector2(0, -90), "CLOSED %d" % ceili(wind.closed_left[r]), Color(1.0, 0.4, 0.3))
	_students_drawn = 0
	for p in traffic.planes:
		if not p.active() or not p.entered or p.fogged or p.state == Aircraft.State.DIVERT or p.state == Aircraft.State.LANDING:
			continue
		var at := xf * p.pos + Vector2(-60, -62)
		if p.emergency:
			var blink := 0.55 + 0.45 * sin(t * 12.0)
			_tag(at, "SOS", Color(1.0, 0.25, 0.2, blink))
		elif p.vip:
			_tag(at, "VIP", Color(1.0, 0.84, 0.15) if p.vip_ok else Color(0.6, 0.6, 0.62))
		elif p.student:
			_students_drawn += 1
			_tag(at, "L", Color(1.0, 0.62, 0.15))
		elif p.type == Aircraft.Type.GLIDER and p.locked:
			_tag(at, "LOCKED", Color(0.8, 0.9, 1.0, 0.8))

## How many student badges the last draw showed (for the tests).
func student_tags_drawn() -> int:
	return _students_drawn

## No-fly zones: mountains get a dashed warning ring and a faint fill; storm cells are dark clouds with lightning.
func _draw_hazards(t: float) -> void:
	for k in traffic.hz_count:
		var c := traffic.hz_pos[k]
		var r := traffic.hz_r[k]
		if traffic.hz_kind[k] == 1:
			_draw_storm(c, r, t, k)
			continue
		var col := Color(1.0, 0.35, 0.2)
		_c.draw_circle(c, r, Color(col.r, col.g, col.b, 0.1))
		var phase := t * 0.6
		for seg in 16:
			var a0 := phase + seg * TAU / 16.0
			_c.draw_arc(c, r + 0.1, a0, a0 + TAU / 32.0, 4, Color(col.r, col.g, col.b, 0.8), 0.1)

func _draw_storm(c: Vector2, r: float, t: float, k: int) -> void:
	_c.draw_circle(c, r * 1.05, Color(0.1, 0.12, 0.2, 0.28))
	for j in 7:       # a lumpy cloud made of drifting puffs
		var ang := j * TAU / 7.0 + t * 0.3 + k
		var off := Vector2(cos(ang), sin(ang)) * r * 0.5
		_c.draw_circle(c + off, r * 0.55, Color(0.2, 0.22, 0.32, 0.5))
	_c.draw_circle(c, r * 0.6, Color(0.12, 0.13, 0.22, 0.6))
	_c.draw_arc(c, r, 0.0, TAU, 40, Color(0.75, 0.6, 1.0, 0.7), 0.08)
	if sin(t * 7.0 + k * 2.0) > 0.85:   # a flash of lightning
		var p0 := c + Vector2(0.1, -r * 0.6)
		var p1 := p0 + Vector2(-0.25, r * 0.45)
		var p2 := p1 + Vector2(0.3, 0.1)
		var p3 := p2 + Vector2(-0.3, r * 0.55)
		_c.draw_line(p0, p1, Color(1.0, 0.97, 0.6), 0.1)
		_c.draw_line(p1, p2, Color(1.0, 0.97, 0.6), 0.1)
		_c.draw_line(p2, p3, Color(1.0, 0.97, 0.6), 0.1)

## The fog: rings of grey that get thicker away from the field, hiding everything beyond the visible radius.
func _draw_fog() -> void:
	if traffic.fog_amount <= 0.001:
		return
	var center := Airports.field_center()
	var vis := lerpf(60.0, Tuning.fog_radius_eff(), traffic.fog_amount)
	for i in 26:
		var r := vis + i * 0.8
		var a := traffic.fog_amount * minf(0.12 + 0.88 * float(i + 1) / 10.0, 0.93)
		_c.draw_arc(center, r + 0.4, 0.0, TAU, 72, Color(0.82, 0.86, 0.9, a), 0.85)

## A closed runway: a red X across it and the time left.
func _draw_closures(t: float) -> void:
	if wind == null:
		return
	for r in Airports.rw_count():
		if not wind.is_closed(r):
			continue
		var c := Airports.rw_center(r)
		var dir := Airports.end_dir(r, 0)
		var side := Vector2(-dir.y, dir.x)
		var len := Airports.rw_length(r) * 0.3
		var a := 0.65 + 0.3 * sin(t * 6.0)
		for sgn in [-1.0, 1.0]:
			var p0: Vector2 = c - dir * len + side * (sgn * 0.5)
			var p1: Vector2 = c + dir * len - side * (sgn * 0.5)
			_c.draw_line(p0, p1, Color(0, 0, 0, 0.8), 0.34)
			_c.draw_line(p0, p1, Color(1.0, 0.18, 0.12, a), 0.2)

func _tag(at: Vector2, text: String, col: Color) -> void:
	_c.draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 30, 8, Color.BLACK)
	_c.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 30, col)

## Helipad and water-lane markers: a ring on each landing spot (always open), like a runway's approach end.
func _draw_place_markers(t: float) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	for kind in [Aircraft.Kind.PAD, Aircraft.Kind.LANE]:
		for i in Airports.land_count(kind):
			var col := Airports.land_color(kind, i)
			var hot: bool = selected != null and selected.tkind == kind
			var radius := Tuning.pad_capture_radius if kind == Aircraft.Kind.PAD else Tuning.approach_radius
			for e in Airports.land_ends(kind):
				var thr := Airports.land_threshold(kind, i, e)
				var r := radius * (1.0 + 0.08 * pulse if hot else 1.0)
				_c.draw_arc(thr, r, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 0.16)
				_c.draw_arc(thr, r, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.95 if hot else 0.65), 0.08)

func _draw_runway_markers(t: float) -> void:
	for i in Airports.rw_count():
		for e in 2:
			var col := Airports.rw_color(i)
			var thr := Airports.end_threshold(i, e)
			var dir := Airports.end_dir(i, e)
			var side := Vector2(-dir.y, dir.x)
			var active := wind == null or wind.is_active(i, e)
			var hot := active_runway == i and active
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			# While a wind shift is announced, ends that are about to change blink.
			var changing := false
			if wind != null and wind.warning:
				var next_on := Airports.angle_diff(Airports.end_heading_deg(i, e), wind.next_deg) <= Tuning.wind_tolerance_deg
				changing = next_on != active
			if not active:
				_c.draw_arc(thr, Tuning.approach_radius, 0.0, TAU, 40, Color(0.1, 0.1, 0.12, 0.35), 0.12)
				var x := 0.4
				_c.draw_line(thr + Vector2(-x, -x), thr + Vector2(x, x), Color(0.9, 0.25, 0.2, 0.55), 0.1)
				_c.draw_line(thr + Vector2(x, -x), thr + Vector2(-x, x), Color(0.9, 0.25, 0.2, 0.55), 0.1)
			else:
				var r := Tuning.approach_radius * (1.0 + 0.08 * pulse if hot else 1.0)
				_c.draw_arc(thr, r, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 0.16)
				_c.draw_arc(thr, r, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.95 if hot else 0.7), 0.08)
				# Approach funnel: two dashed lines opening out behind the threshold, with chevrons.
				var far := thr - dir * 3.4
				for s in [-1.0, 1.0]:
					_c.draw_dashed_line(thr + side * s * 0.35, far + side * s * 1.4, Color(col.r, col.g, col.b, 0.55), 0.07, 0.25)
				for k in 3:
					var c := thr - dir * (1.5 + k * 0.7)
					var a := 0.25 + 0.55 * clampf(1.0 - absf(fmod(t * 1.5, 3.0) - k), 0.0, 1.0)
					_c.draw_line(c - side * 0.3, c + dir * 0.3, Color(col.r, col.g, col.b, a), 0.09)
					_c.draw_line(c + side * 0.3, c + dir * 0.3, Color(col.r, col.g, col.b, a), 0.09)
			if changing and sin(t * 9.0) > 0.0:
				_c.draw_arc(thr, Tuning.approach_radius + 0.25, 0.0, TAU, 40, Color(1, 0.95, 0.4, 0.9), 0.1)

## The edge glow for an aircraft that is about to come in: a pulsing beacon in its speed colour on the screen
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
