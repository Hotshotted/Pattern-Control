class_name KScroll
extends Container
## The one scrolling list of the game (the shop, achievements and goals lists, the Improve sheet, the airport detail sheet): a clipping container
## with one child that it moves up and down. Nothing else scrolls a list, so a finger cannot move one twice.
##   - The content follows the finger 1:1 in screen space. The offset comes from the finger's ABSOLUTE position (viewport units), never from the
##     events' `relative` (which a browser reports in device pixels and the content scale can multiply a second time): a drag of N screen pixels
##     moves the content N screen pixels at any content scale and DPI.
##   - A press becomes a scroll after THRESHOLD_PT points of vertical travel (the content then catches up to the finger, there is no lag);
##     until then it is still a tap. A touch that scrolled, or that stopped a moving list, fires no tap (`touch_scrolled`).
##   - Let go, the list keeps going with a gentle momentum (exponential friction, like a phone's own lists); past either end it stretches with
##     resistance while dragged, and springs back (also from a fast fling).
## Touches come in through `KScroll.feed` (Main._input passes every ScreenTouch / ScreenDrag); the mouse wheel is handled by the list itself.

const THRESHOLD_PT := 10.0           # points of travel before a press becomes a scroll
const FRICTION := 2.4                # momentum: speed decays as e^(-FRICTION * seconds)
const STOP_SPEED := 18.0             # units per second under which the momentum ends
const MAX_SPEED := 6000.0            # units per second
const RUBBER := 0.55                 # the stretch past an end: the finger's travel x this, softened (iOS-like)
const SPRING_K := 220.0
const SPRING_C := 28.0
const WHEEL_STEP_PT := 48.0

static var all: Array = []           # every KScroll in the tree
static var touch_scrolled := false   # the touch now down (or just up) scrolled a list, or stopped one that was moving: it is not a tap
static var last_scroll_msec := -100000

var enabled := true                  # false: touches pass through (a sheet is up over the list)
var offset := 0.0                    # how far the content is scrolled, in units (may be past the ends while stretched)
var _vel := 0.0                      # units per second (content direction), while coasting
var _mode := 0                       # 0 idle, 1 finger down, 2 dragging, 3 coasting / springing back
var _finger := -1
var _press := Vector2.ZERO
var _start_off := 0.0
var _samples: Array = []             # [msec, y] of the finger's last 120 ms

## How far the finger must travel before it is a scroll, in viewport units.
static func threshold() -> float:
	return THRESHOLD_PT * Style.px_per_pt

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(false)

func _enter_tree() -> void:
	all.append(self)

func _exit_tree() -> void:
	all.erase(self)
	_mode = 0
	_finger = -1

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout()
	elif what == NOTIFICATION_RESIZED:
		queue_sort()

func content() -> Control:
	for c in get_children():
		if c is Control and (c as Control).visible:
			return c
	return null

func content_height() -> float:
	var c := content()
	return maxf(c.get_combined_minimum_size().y, 0.0) if c != null else 0.0

func max_scroll() -> float:
	return maxf(content_height() - size.y, 0.0)

func _layout() -> void:
	var c := content()
	if c == null:
		return
	if _mode != 2 and _mode != 3:
		offset = clampf(offset, 0.0, max_scroll())
	fit_child_in_rect(c, Rect2(0.0, -roundf(offset), size.x, maxf(content_height(), 0.0)))

func _place() -> void:
	var c := content()
	if c != null:
		c.position.y = -roundf(offset)

## The scroll position as the old ScrollContainer property read: whole units, within the ends.
var scroll_vertical: int:
	get:
		return roundi(clampf(offset, 0.0, max_scroll()))
	set(v):
		jump_to(float(v))

func jump_to(v: float) -> void:
	_mode = 0
	_vel = 0.0
	set_process(false)
	offset = clampf(v, 0.0, max_scroll())
	_place()

# ---------- touches ----------

## Every ScreenTouch / ScreenDrag goes through here first. Returns true when a list took the touch for a scroll (the caller may skip taps).
static func feed(ev: InputEvent) -> bool:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			touch_scrolled = false
			var best: KScroll = null
			for s in all:
				var k := s as KScroll
				if k == null or not is_instance_valid(k) or not k.enabled or not k.is_visible_in_tree() or k._finger != -1:
					continue
				if k.max_scroll() < 1.0 or not k.get_global_rect().has_point(t.position):
					continue
				if best == null or k.size.x * k.size.y < best.size.x * best.size.y:
					best = k
			if best != null:
				best._down(t.index, t.position)
			return false
		for s in all:
			var k := s as KScroll
			if k != null and is_instance_valid(k) and k._finger == t.index:
				return k._up(t.position)
		return false
	if ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		for s in all:
			var k := s as KScroll
			if k != null and is_instance_valid(k) and k._finger == d.index:
				return k._move(d.position)
	return false

func _down(index: int, pos: Vector2) -> void:
	if _mode == 3 and absf(_vel) > STOP_SPEED * 2.0:
		touch_scrolled = true            # the finger stopped a moving list: that touch is not a tap
	_finger = index
	_press = pos
	_mode = 1
	_vel = 0.0
	_samples.clear()
	_sample(pos.y)
	_start_off = offset
	set_process(false)

func _sample(y: float) -> void:
	var now := Time.get_ticks_msec()
	_samples.append([now, y])
	while _samples.size() > 2 and now - int(_samples[0][0]) > 120:
		_samples.pop_front()

func _move(pos: Vector2) -> bool:
	if _mode == 1:
		if absf(pos.y - _press.y) < threshold():
			return false
		_mode = 2
		touch_scrolled = true
	if _mode != 2:
		return false
	last_scroll_msec = Time.get_ticks_msec()
	_sample(pos.y)
	_set_raw(_start_off - (pos.y - _press.y))
	return true

## The content position for a finger-driven raw offset: 1:1 inside the ends, stretched with resistance past them.
func _set_raw(raw: float) -> void:
	var mx := max_scroll()
	var d := maxf(size.y, 1.0)
	if raw < 0.0:
		offset = -_soft(-raw, d)
	elif raw > mx:
		offset = mx + _soft(raw - mx, d)
	else:
		offset = raw
	_place()

static func _soft(x: float, d: float) -> float:
	return (1.0 - 1.0 / (x * RUBBER / d + 1.0)) * d

func _up(pos: Vector2) -> bool:
	_finger = -1
	if _mode != 2:
		_mode = 0
		return false
	_sample(pos.y)
	var now := Time.get_ticks_msec()
	var v := 0.0
	if _samples.size() >= 2 and now - int(_samples[_samples.size() - 1][0]) < 90:
		var a = _samples[0]
		var b = _samples[_samples.size() - 1]
		var dt := float(int(b[0]) - int(a[0])) / 1000.0
		if dt > 0.004:
			v = -(float(b[1]) - float(a[1])) / dt
	_vel = clampf(v, -MAX_SPEED, MAX_SPEED)
	_mode = 3
	set_process(true)
	last_scroll_msec = now
	return true

func _process(delta: float) -> void:
	if _mode != 3:
		set_process(false)
		return
	var dt := minf(delta, 0.05)
	var mx := max_scroll()
	if offset < 0.0 or offset > mx:
		var edge := 0.0 if offset < 0.0 else mx
		var acc := -SPRING_K * (offset - edge) - SPRING_C * _vel
		_vel += acc * dt
		offset += _vel * dt
		if absf(offset - edge) < 0.5 and absf(_vel) < STOP_SPEED:
			offset = edge
			_vel = 0.0
	else:
		_vel *= exp(-FRICTION * dt)
		offset += _vel * dt
		if absf(_vel) < STOP_SPEED:
			_vel = 0.0
	_place()
	if _vel == 0.0 and offset >= 0.0 and offset <= mx:
		_mode = 0
		set_process(false)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var dir := -1.0 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		jump_to(offset + dir * WHEEL_STEP_PT * Style.px_per_pt)
		accept_event()
