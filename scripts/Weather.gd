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
var left := 0.0                 # WARN: seconds until it starts; ACTIVE: seconds until it ends

func start() -> void:
	phase = Phase.IDLE
	kind = ""
	runway = -1
	countdown = Tuning.weather_start_time

## Seconds between events at this point of the shift (progress 0..1) on this airport.
func interval(progress: float) -> float:
	return lerpf(Tuning.weather_interval_start, Tuning.weather_interval_min, clampf(progress, 0.0, 1.0)) * Airports.weather_scale()

func duration(k: String) -> float:
	match k:
		"storm":
			return Tuning.storm_event_seconds
		"fog":
			return Tuning.fog_seconds
		_:
			return Tuning.crosswind_seconds

func step(dt: float, progress: float, rng: RandomNumberGenerator, wind: Wind) -> void:
	var kinds := Airports.weather_kinds()
	if kinds.is_empty():
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
func trigger(k: String, rng: RandomNumberGenerator, wind: Wind) -> void:
	if phase != Phase.IDLE:
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
			text = "Gusty crosswind: %s runway closing" % Airports.rw_name(runway)
	phase = Phase.WARN
	left = Tuning.weather_warning_seconds
	warned.emit(k, text)

## The banner line for the HUD ("" when nothing is going on).
func banner() -> String:
	match phase:
		Phase.WARN:
			var what := "Storm cell" if kind == "storm" else ("Fog" if kind == "fog" else "Crosswind: %s runway closes" % Airports.rw_name(runway))
			return "%s in %ds" % [what, ceili(left)]
		Phase.ACTIVE:
			match kind:
				"storm":
					return "Storm over the field: %ds" % ceili(left)
				"fog":
					return "Fog: %ds" % ceili(left)
				_:
					return "%s runway closed: %ds" % [Airports.rw_name(runway), ceili(left)]
	return ""
