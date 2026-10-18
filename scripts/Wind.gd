class_name Wind
extends RefCounted
## The wind. `from_deg` is the compass direction it blows FROM (0 = north, 90 = east); aircraft land into it,
## so a runway end is ACTIVE when its landing heading is within Tuning.wind_tolerance_deg of that direction.
## The wind shifts now and then: `warned` fires about Tuning.wind_warning_seconds ahead (with the new
## direction), then `shifted` when the active ends change. Shifts come more often later in the shift and on
## later airports. Everything is plain numbers (nothing is allocated while it runs).

signal warned(next_deg: float)
signal shifted

var from_deg := 0.0
var next_deg := 0.0
var warning := false            # a shift has been announced and is counting down
var countdown := 30.0           # seconds until the next shift
var active := PackedByteArray() # runway * 2 + end -> 1 if landing there is allowed

func _init() -> void:
	active.resize(32)

## A new shift: pick a starting wind that works for every runway, and schedule the first change.
func start(rng: RandomNumberGenerator) -> void:
	from_deg = _pick(rng, -999.0)
	next_deg = from_deg
	warning = false
	countdown = interval(0.0)
	refresh()

## Seconds between shifts at this point of the shift (progress 0..1): shorter later, shorter on later airports.
func interval(progress: float) -> float:
	var base := lerpf(Tuning.wind_interval_start, Tuning.wind_interval_min, clampf(progress, 0.0, 1.0))
	return maxf(base * Airports.wind_scale(), Tuning.wind_warning_seconds + 2.0)

func is_active(runway: int, end: int) -> bool:
	return active[runway * 2 + end] != 0

func refresh() -> void:
	active.fill(0)
	for r in Airports.rw_count():
		for e in 2:
			if Airports.angle_diff(Airports.end_heading_deg(r, e), from_deg) <= Tuning.wind_tolerance_deg:
				active[r * 2 + e] = 1

## True if any end of this runway can be used.
func runway_open(r: int) -> bool:
	return is_active(r, 0) or is_active(r, 1)

## A wind direction (multiples of 10) that keeps every runway usable and differs from `avoid` by enough.
func _pick(rng: RandomNumberGenerator, avoid: float) -> float:
	var ok: Array[float] = []
	for k in 36:
		var d := k * 10.0
		if Airports.wind_ok(d, Tuning.wind_tolerance_deg) and (avoid < -900.0 or Airports.angle_diff(d, avoid) >= Tuning.wind_min_change_deg):
			ok.append(d)
	if ok.is_empty():
		return from_deg
	return ok[rng.randi() % ok.size()]

func step(dt: float, progress: float, rng: RandomNumberGenerator) -> void:
	countdown -= dt
	if not warning and countdown <= Tuning.wind_warning_seconds:
		next_deg = _pick(rng, from_deg)
		warning = true
		warned.emit(next_deg)
	if countdown <= 0.0:
		apply_shift(progress)

func apply_shift(progress: float) -> void:
	from_deg = next_deg
	warning = false
	countdown = interval(progress)
	refresh()
	shifted.emit()

## Debug / tests: announce a shift to `deg` right now (it happens after the usual warning).
func force_shift(deg: float = -1.0, rng: RandomNumberGenerator = null) -> void:
	if warning:
		return
	next_deg = deg if deg >= 0.0 else _pick(rng if rng != null else RandomNumberGenerator.new(), from_deg)
	warning = true
	countdown = Tuning.wind_warning_seconds
	warned.emit(next_deg)

## "270" style label (nearest 10 degrees, three digits).
static func label(deg: float) -> String:
	return "%03d" % ((roundi(deg / 10.0) * 10) % 360)

## Which compass direction the air is moving TOWARD (what the windsock points at).
func toward_deg() -> float:
	return fposmod(from_deg + 180.0, 360.0)
