class_name Weather
extends RefCounted
## Weather events: storm cells (drifting no-fly zones), fog (aircraft are hidden until they get close to the
## field) and a gusty crosswind (a runway closes for a while). They only happen at airports that list them,
## come more often later in a shift and on later airports, and each is announced about
## Tuning.weather_warning_seconds ahead. One event at a time. Plain numbers only.

signal warned(kind: String, text: String)
signal started(kind: String)
signal ended(kind: String)

enum Phase { IDLE, WARN, ACTIVE }

var phase := Phase.IDLE
var kind := ""                  # the announced / running event
var runway := -1                # crosswind: which runway is closing
var countdown := 40.0           # IDLE: seconds until the next event is announced
var elapsed := 0.0              # seconds into the shift (a closure never comes early)
var left := 0.0                 # WARN: seconds until it starts; ACTIVE: seconds until it ends

func start() -> void:
	phase = Phase.IDLE
	kind = ""
	runway = -1
	elapsed = 0.0
	countdown = Tuning.weather_first_eff()

## Seconds between events at this point of the shift (progress 0..1) on this airport.
func interval(progress: float) -> float:
	return lerpf(Tuning.weather_interval_start, Tuning.weather_interval_min, clampf(progress, 0.0, 1.0)) * Tuning.weather_scale_eff()

func duration(k: String) -> float:
	match k:
		"storm":
			return Tuning.storm_event_seconds
		"fog":
			return Tuning.fog_seconds
		_:
			return Tuning.crosswind_seconds

func step(dt: float, progress: float, rng: RandomNumberGenerator, wind: Wind) -> void:
	elapsed += dt
	var kinds := Airports.weather_kinds()
	if kinds.is_empty() or Tuning.weather_scale_eff() == INF:
		return
	match phase:
		Phase.IDLE:
			countdown -= dt
			if countdown <= 0.0:
				trigger(kinds[rng.randi() % kinds.size()], rng, wind)
		Phase.WARN:
			left -= dt
			if left <= 0.0:
				phase = Phase.ACTIVE
				left = duration(kind)
				started.emit(kind)
		Phase.ACTIVE:
			left -= dt
			if left <= 0.0:
				var k := kind
				phase = Phase.IDLE
				kind = ""
				countdown = interval(progress)
				ended.emit(k)

## Announce an event of this kind now (the scheduler uses it; so does the ?tune debug button).
func trigger(k: String, rng: RandomNumberGenerator, wind: Wind, force: bool = false) -> void:
	if phase != Phase.IDLE:
		return
	# A runway never closes in the first seconds of a shift, nor on the first airports (`force` is the ?tune button)
	if k == "crosswind" and not force and (Airports.current < Tuning.closure_min_airport or elapsed < Tuning.closure_min_time):
		countdown = maxf(Tuning.closure_min_time - elapsed, 0.0) + 5.0
		return
	kind = k
	var text := ""
	match k:
		"storm":
			text = "Storm cell approaching"
		"fog":
			text = "Fog rolling in"
		_:
			# Close a random runway, as long as another one stays open.
			var open_list: Array[int] = []
			for r in Airports.rw_count():
				if wind.runway_open(r):
					open_list.append(r)
			if open_list.size() < 2:
				kind = ""
				countdown = 15.0
				return
			runway = open_list[rng.randi() % open_list.size()]
			text = "%s runway closing in %d s" % [Airports.rw_name(runway).capitalize(), ceili(Tuning.closure_warning_seconds)]
	phase = Phase.WARN
	left = Tuning.closure_warning_seconds if k == "crosswind" else Tuning.weather_warning_seconds
	warned.emit(k, text)

## The banner line for the HUD ("" when nothing is going on).
func banner() -> String:
	match phase:
		Phase.WARN:
			var what := "Storm cell" if kind == "storm" else ("Fog" if kind == "fog" else "%s runway closing" % Airports.rw_name(runway).capitalize())
			return "%s in %d s" % [what, ceili(left)]
		Phase.ACTIVE:
			match kind:
				"storm":
					return "Storm over the field: %ds" % ceili(left)
				"fog":
					return "Fog: %ds" % ceili(left)
				_:
					return "%s runway closed: %d s" % [Airports.rw_name(runway).capitalize(), ceili(left)]
	return ""
