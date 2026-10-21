class_name Sfx
extends Node
## Placeholder sound, all generated in code at start-up (no audio files): one-shot effects, an engine hum per
## aircraft type, and a light two-layer music loop that intensifies towards the end of a shift. One-shots go
## through a small pool of players on the "SFX" bus, hums and music on their own looping players ("SFX" /
## "Music"). Nothing is created or generated during play, and `plays` counts what was triggered (for the tests).

const RATE := 11025            # effects
const LOOP_RATE := 8000        # hums and music (lo-fi on purpose: it is a placeholder)
const POOL := 8
const NAMES := ["landing", "coin", "go_around", "alarm", "fine", "wind", "last_arrivals", "clear_sky", "tick", "tap", "press"]
const BEAT := 0.6              # music: seconds per beat, 8 beats per loop

var enabled := true
var plays := {}                # sound name -> how many times it was triggered
var hum_level := PackedFloat32Array()    # per aircraft type: current hum volume 0..1 (for the tests)
var music_level := 0.0         # the intense layer's volume 0..1
var music_pitch := 1.0
var fog_level := 0.0           # 0..1: the fog ambience and the tense music layer follow it

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _hums: Array[AudioStreamPlayer] = []
var _hum_target := PackedFloat32Array()
var _music_calm: AudioStreamPlayer
var _music_hot: AudioStreamPlayer
var _music_tense: AudioStreamPlayer
var _fog_amb: AudioStreamPlayer
var _music_on := false

func _ready() -> void:
	hum_level.resize(6)
	_hum_target.resize(6)
	for n in NAMES:
		plays[n] = 0
	if DebugFlags.off("sound"):
		enabled = false
		return
	_build_effects()
	for i in POOL:
		_pool.append(_player("SFX"))
	for t in 6:
		var p := _player("SFX")
		p.stream = _hum(t)
		p.volume_db = -80.0
		_hums.append(p)
	_music_calm = _player("Music")
	_music_hot = _player("Music")
	_music_calm.stream = _music(false)
	_music_hot.stream = _music(true)
	_music_calm.volume_db = -80.0
	_music_hot.volume_db = -80.0
	_music_tense = _player("Music")
	_music_tense.stream = _music_tense_loop()
	_music_tense.volume_db = -80.0
	_fog_amb = _player("SFX")
	_fog_amb.stream = _fog_ambience()
	_fog_amb.volume_db = -80.0

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

# ---------- Playing ----------

func play(sound: String) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.play()

## Aircraft per type currently on the field (index = Aircraft.Type): the hums follow these.
func set_hum_counts(counts: PackedInt32Array) -> void:
	for t in 6:
		_hum_target[t] = clampf(float(counts[t]) * 0.45, 0.0, 1.0) if counts[t] > 0 else 0.0

func silence_hums() -> void:
	_hum_target.fill(0.0)

## Start / stop the music. `progress` 0..1 through the shift: the intense layer fades in from 55% and the loop
## speeds up a little; `urgency` (the finale / overtime) pushes it to the top.
func set_music(on: bool, progress: float = 0.0, urgency: float = 0.0) -> void:
	_music_on = on
	var hot := clampf(maxf(smoothstep(0.55, 1.0, progress), urgency), 0.0, 1.0)
	music_level = hot if on else 0.0
	music_pitch = 1.0 + 0.1 * hot
	if not enabled:
		return
	if on and not _music_calm.playing:
		_music_calm.play()
		_music_hot.play()
	elif not on and _music_calm.playing:
		_music_calm.stop()
		_music_hot.stop()
	_music_calm.pitch_scale = music_pitch
	_music_hot.pitch_scale = music_pitch
	_music_calm.volume_db = -12.0 if on else -80.0
	_music_hot.volume_db = linear_to_db(maxf(hot * 0.8, 0.0001)) - 8.0 if on else -80.0

## Fog: a soft ambient bed, and a tense music layer on top of the music while it is around.
func set_fog(level: float) -> void:
	fog_level = clampf(level, 0.0, 1.0)
	if not enabled:
		return
	if fog_level > 0.01:
		if not _fog_amb.playing:
			_fog_amb.play()
		_fog_amb.volume_db = linear_to_db(fog_level) + Tuning.fog_ambient_db
	elif _fog_amb.playing:
		_fog_amb.stop()
	var tense := fog_level * Tuning.fog_music_tension if _music_on else 0.0
	if tense > 0.01:
		if not _music_tense.playing:
			_music_tense.play()
		_music_tense.volume_db = linear_to_db(tense) - 8.0
		_music_tense.pitch_scale = music_pitch
	elif _music_tense.playing:
		_music_tense.stop()

func _process(delta: float) -> void:
	for t in 6:
		hum_level[t] = move_toward(hum_level[t], _hum_target[t], delta * 1.5)
		if not enabled:
			continue
		var p := _hums[t]
		if hum_level[t] > 0.005:
			if not p.playing:
				p.play()
			p.volume_db = linear_to_db(hum_level[t]) - 22.0
		elif p.playing:
			p.stop()

# ---------- Synthesis ----------

func _build_effects() -> void:
	# landing: a quick rising two-note chirp
	_streams["landing"] = _wav(_seq([[660.0, 0.07, 0.5], [880.0, 0.07, 0.5], [1100.0, 0.12, 0.45]], RATE), RATE)
	# coin: two bright pings
	_streams["coin"] = _wav(_seq([[1319.0, 0.06, 0.4], [1760.0, 0.16, 0.4]], RATE, 0.5), RATE)
	# go-around: a swelling noisy roar
	_streams["go_around"] = _wav(_roar(0.9, RATE), RATE)
	# conflict alarm: alternating two-tone square wave
	_streams["alarm"] = _wav(_seq([[880.0, 0.14, 0.35], [660.0, 0.14, 0.35], [880.0, 0.14, 0.35], [660.0, 0.14, 0.35], [880.0, 0.14, 0.35]], RATE, 0.9, true), RATE)
	# fine: a low falling thunk
	_streams["fine"] = _wav(_sweep(220.0, 70.0, 0.28, 0.6, RATE), RATE)
	# wind-shift chime: three soft bell notes
	_streams["wind"] = _wav(_seq([[784.0, 0.18, 0.35], [988.0, 0.18, 0.35], [1175.0, 0.4, 0.35]], RATE, 0.4, false, true), RATE)
	# last arrivals: a rising brassy stinger
	_streams["last_arrivals"] = _wav(_seq([[392.0, 0.14, 0.4], [494.0, 0.14, 0.4], [587.0, 0.14, 0.4], [784.0, 0.4, 0.45]], RATE, 0.9, true), RATE)
	# clear the sky: a resolving chord
	_streams["clear_sky"] = _wav(_chord([262.0, 330.0, 392.0, 523.0], 0.8, RATE), RATE)
	# overtime tick: a short click
	_streams["tick"] = _wav(_seq([[1500.0, 0.025, 0.5]], RATE, 0.6, true), RATE)
	# UI tap: a soft blip
	_streams["tap"] = _wav(_seq([[740.0, 0.05, 0.35]], RATE), RATE)
	# a finger going down on a button: a short, soft low click
	_streams["press"] = _wav(_seq([[420.0, 0.03, 0.25]], RATE, 0.9), RATE)

## Notes [[hz, seconds, volume], ...] one after another with a short decay each. `square` = hollow tone,
## `bell` = a slow decay with an overtone.
func _seq(notes: Array, rate: int, decay: float = 0.6, square: bool = false, bell: bool = false) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in notes:
		var count := int(float(n[1]) * rate)
		var base := out.size()
		out.resize(base + count)
		for i in count:
			var t := float(i) / rate
			var env := (1.0 - float(i) / count) if not bell else exp(-t * 6.0)
			env = lerpf(1.0, env, decay) * minf(float(i) / 40.0, 1.0)
			var ph := TAU * float(n[0]) * t
			var v := signf(sin(ph)) * 0.6 if square else sin(ph)
			if bell:
				v += 0.4 * sin(ph * 2.76)
			out[base + i] = v * float(n[2]) * env
	return out

func _sweep(f0: float, f1: float, secs: float, vol: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var ph := 0.0
	for i in count:
		var k := float(i) / count
		ph += TAU * lerpf(f0, f1, k) / rate
		out[i] = sin(ph) * vol * (1.0 - k) * minf(float(i) / 30.0, 1.0)
	return out

func _roar(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 12345
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += (noise - lp) * 0.25
		var k := float(i) / count
		var env := sin(PI * k) * (0.5 + 0.5 * k)
		out[i] = (lp * 1.4 + 0.3 * sin(TAU * lerpf(90.0, 200.0, k) * float(i) / rate)) * env * 0.7
	return out

func _chord(freqs: Array, secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / rate
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t) + 0.3 * sin(TAU * float(f) * 2.0 * t)
		out[i] = v / freqs.size() * 0.5 * exp(-t * 2.5) * minf(float(i) / 60.0, 1.0)
	return out

## One second of engine hum for aircraft type `t` (Aircraft.Type order: glider, heli, small, medium, jet, seaplane).
## Every frequency is a whole number of Hz, so the one-second loop is seamless.
func _hum(t: int) -> AudioStreamWAV:
	var count := LOOP_RATE
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var s := float(i) / LOOP_RATE
		var v := 0.0
		match t:
			0:      # glider: airy rushing wind (many soft partials)
				for k in 12:
					v += 0.12 * sin(TAU * (300.0 + 53.0 * k) * s + k * 1.7)
			1:      # helicopter: a chopping rotor
				v = (sin(TAU * 90.0 * s) + 0.5 * sin(TAU * 180.0 * s)) * (0.55 + 0.45 * sin(TAU * 11.0 * s))
			2:      # small plane: a buzzy propeller
				v = (sin(TAU * 120.0 * s) + 0.5 * sin(TAU * 240.0 * s) + 0.3 * sin(TAU * 360.0 * s)) * (0.7 + 0.3 * sin(TAU * 30.0 * s))
			3:      # medium plane: a deeper twin-prop drone
				v = (sin(TAU * 80.0 * s) + 0.6 * sin(TAU * 160.0 * s) + 0.3 * sin(TAU * 241.0 * s)) * (0.75 + 0.25 * sin(TAU * 19.0 * s))
			4:      # jet: a whine over a rumble
				v = 0.5 * sin(TAU * 70.0 * s) + 0.4 * sin(TAU * 480.0 * s) + 0.25 * sin(TAU * 960.0 * s)
				for k in 6:
					v += 0.1 * sin(TAU * (610.0 + 71.0 * k) * s + k)
			_:      # seaplane: a prop with a gurgle
				v = (sin(TAU * 100.0 * s) + 0.5 * sin(TAU * 200.0 * s)) * (0.7 + 0.3 * sin(TAU * 7.0 * s)) + 0.1 * sin(TAU * 520.0 * s)
		out[i] = v * 0.35
	return _wav(out, LOOP_RATE, true)

## An 8-beat loop (A minor: Am F C G, two beats each). The calm layer is a pad and a bass; the intense layer is a
## plucked arpeggio and a kick on every beat.
func _music(hot: bool) -> AudioStreamWAV:
	var chords := [[220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [261.6, 329.6, 392.0], [196.0, 246.9, 293.7]]
	var count := int(BEAT * 8.0 * LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / LOOP_RATE
		var beat := t / BEAT
		var ch: Array = chords[int(beat / 2.0) % 4]
		var v := 0.0
		if not hot:
			for f in ch:
				v += 0.18 * sin(TAU * f * t * 0.5)
			var bt := fmod(beat, 2.0)
			v += 0.3 * sin(TAU * ch[0] * 0.25 * t) * (1.0 - 0.4 * bt)
		else:
			var step := fmod(beat * 2.0, 1.0)          # eighth notes
			var note: float = ch[int(beat * 2.0) % 3] * 2.0
			v += 0.35 * sin(TAU * note * t) * exp(-step * 5.0)
			var kb := fmod(beat, 1.0)
			v += 0.5 * sin(TAU * lerpf(110.0, 45.0, minf(kb * 8.0, 1.0)) * kb * BEAT) * exp(-kb * 9.0)
		out[i] = v * 0.5
	return _wav(out, LOOP_RATE, true)

## Fog ambience: a soft airy bed (a one-second loop of many quiet partials) that swells and fades slowly.
func _fog_ambience() -> AudioStreamWAV:
	var count := LOOP_RATE * 2
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var s := float(i) / LOOP_RATE
		var v := 0.0
		for k in 10:
			v += 0.07 * sin(TAU * (90.0 + 41.0 * k) * s + k * 2.1) * (0.6 + 0.4 * sin(TAU * 0.5 * s + k))
		out[i] = v * 0.5
	return _wav(out, LOOP_RATE, true)

## A low tense drone for the fog: a tritone pair that slowly shivers, in the same 8-beat length as the other layers.
func _music_tense_loop() -> AudioStreamWAV:
	var secs := BEAT * 8.0
	var count := int(secs * LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / LOOP_RATE
		var f1 := roundf(55.0 * secs) / secs          # whole cycles per loop: no click at the seam
		var f2 := roundf(77.8 * secs) / secs
		var trem := 0.65 + 0.35 * sin(TAU * roundf(2.5 * secs) / secs * t)
		var v := (sin(TAU * f1 * t) + 0.8 * sin(TAU * f2 * t) + 0.3 * sin(TAU * f2 * 2.0 * t)) * trem
		out[i] = v * 0.3
	return _wav(out, LOOP_RATE, true)

func _wav(samples: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w
