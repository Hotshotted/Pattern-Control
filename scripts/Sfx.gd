class_name Sfx
extends Node
## The game's sound, in the spirit of Mini Metro / Alto's Adventure: soft, rounded, cozy. Everything is rendered ONCE
## at start-up into 16-bit AudioStreamWAV clips (no files, no generators, no run-time buses): sines and gently
## filtered noise, every clip with a soft attack and a smooth release, a little baked-in reverb tail, and every
## pitched sound in one key (C major pentatonic, the key of the music), so whatever overlaps harmonises. Repeated sounds
## are varied by a few percent in pitch and level. Loudness is normalised per clip by role: UI is the quietest,
## gameplay sounds moderate, the big moments (a landing, a star, a new airport) stand out. The shared limiter lives on
## the Master bus (default_bus_layout.tres). `plays` counts what was triggered (for the tests). See docs/style.md.

const RATE := 16000            # every clip and loop
const POOL := 8
const STEPS := 7               # landing chimes / coin plinks: this many steps up the scale
const BEAT := 0.75             # music: seconds per beat, 8 beats per loop (6 s)
const NAMES := ["landing", "coin", "go_around", "alarm", "fine", "wind", "last_arrivals", "clear_sky", "tick", "tap", "press", "star", "slam", "back", "toggle", "buy", "error", "whoosh", "unlock", "chirp"]
const C4 := 261.6256
const PENTA := [0, 2, 4, 7, 9]  # C D E G A

# Loudness by role (peak, linear). The SFX bus sits at -1.9 dB.
const LVL_UI := 0.10
const LVL_GAME := 0.30
const LVL_BIG := 0.50
const LVL_HUM := 0.07

var enabled := true
var plays := {}                # sound name -> how many times it was triggered
var hum_level := PackedFloat32Array()    # per aircraft type: current hum volume 0..1 (for the tests)
var music_level := 0.0         # the intense layer's volume 0..1
var music_pitch := 1.0         # (always 1: shifting the music would take it out of key)
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
var _menu_on := false
var unlocked := false                  # the first user gesture has happened (browsers keep audio suspended until then)
var _calm_db := -80.0                  # what the players are at now; the targets come from the mode (a smooth crossfade)
var _hot_db := -80.0
var _calm_target := -80.0
var _hot_target := -80.0
var _pitch_target := 1.0
const FADE_DB_PER_S := 60.0
const MENU_CALM_DB := -13.0
const SHIFT_CALM_DB := -9.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
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
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"      # (a missing bus must never be named: the web build aborts)
	add_child(p)
	return p

# ---------- Playing ----------

## A one-shot. `pitch` is a ratio (1 = as rendered); every play also gets about +-3% random pitch and a hair of
## random level, so repeated sounds never feel mechanical.
func play(sound: String, pitch: float = 1.0) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or not _streams.has(sound):
		return
	_fire(_streams[sound], pitch)

## A sound that climbs the scale: "landing" and "coin" have STEPS clips, each a note higher in the key. Counts as `sound`.
func play_step(sound: String, step: int) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled:
		return
	var key := "%s_%d" % [sound, clampi(step, 0, STEPS - 1)]
	if _streams.has(key):
		_fire(_streams[key], 1.0)

func _fire(stream: AudioStream, pitch: float) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	p.volume_db = _rng.randf_range(-0.5, 0.3)
	p.play()

## The first touch: browsers only let audio run after a gesture. Looping layers that were started while the page was
## still locked are restarted now, so they begin cleanly with the audio context running.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if not enabled:
		return
	for p in [_music_calm, _music_hot, _music_tense, _fog_amb]:
		if p != null and p.playing:
			p.stop()
			p.play()

## Aircraft per type currently on the field (index = Aircraft.Type): the hums follow these.
func set_hum_counts(counts: PackedInt32Array) -> void:
	for t in 6:
		_hum_target[t] = clampf(float(counts[t]) * 0.45, 0.0, 1.0) if counts[t] > 0 else 0.0

func silence_hums() -> void:
	_hum_target.fill(0.0)

## Start / stop the music. `progress` 0..1 through the shift: the intense layer fades in from 55%; `urgency` (the
## finale / overtime) pushes it to the top. The key never changes.
func set_music(on: bool, progress: float = 0.0, urgency: float = 0.0) -> void:
	_music_on = on
	var hot := clampf(maxf(smoothstep(0.55, 1.0, progress), urgency), 0.0, 1.0)
	music_level = hot if on else 0.0
	_retarget(hot)

## The menu's music: the calm layer alone, quieter. It crossfades with the shift's music.
func set_menu_music(on: bool) -> void:
	if on != _menu_on:
		_menu_on = on
		_retarget(music_level)

## Work out where each layer should be; the players glide there in _process (no jumps, no clicks).
func _retarget(hot: float) -> void:
	_calm_target = SHIFT_CALM_DB if _music_on else (MENU_CALM_DB if _menu_on else -80.0)
	_hot_target = linear_to_db(maxf(hot * 0.8, 0.0001)) - 6.0 if _music_on else -80.0
	_pitch_target = 1.0
	if not enabled:
		return
	if (_calm_target > -70.0 or _hot_target > -70.0) and not _music_calm.playing:
		_music_calm.play()
		_music_hot.play()

func _glide_music(delta: float) -> void:
	_calm_db = move_toward(_calm_db, _calm_target, FADE_DB_PER_S * delta)
	_hot_db = move_toward(_hot_db, _hot_target, FADE_DB_PER_S * delta)
	var k := 1.0 - exp(-delta * 2.0)
	var pitch := lerpf(_music_calm.pitch_scale, _pitch_target, k)
	_music_calm.pitch_scale = pitch
	_music_hot.pitch_scale = pitch
	_music_calm.volume_db = _calm_db
	_music_hot.volume_db = _hot_db
	if _music_calm.playing and _calm_db <= -75.0 and _hot_db <= -75.0 and _calm_target <= -70.0:
		_music_calm.stop()
		_music_hot.stop()

## Fog: a soft ambient bed, and a tense (but still soft) music layer on top of the music while it is around.
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
		_music_tense.volume_db = linear_to_db(tense) - 9.0
		_music_tense.pitch_scale = 1.0
	elif _music_tense.playing:
		_music_tense.stop()

func _process(delta: float) -> void:
	if enabled:
		_glide_music(delta)
	for t in 6:
		hum_level[t] = move_toward(hum_level[t], _hum_target[t], delta * 1.5)
		if not enabled:
			continue
		var p := _hums[t]
		if hum_level[t] > 0.005:
			if not p.playing:
				p.play()
			p.volume_db = linear_to_db(hum_level[t]) - 9.0
		elif p.playing:
			p.stop()

# ---------- The key ----------

## Frequency of scale degree `deg` of C major pentatonic: 0 = C4, 1 = D4, 2 = E4, 3 = G4, 4 = A4, 5 = C5, ...
static func note_hz(deg: int) -> float:
	var oct := floori(float(deg) / 5.0)
	return C4 * pow(2.0, float(PENTA[posmod(deg, 5)] + 12 * oct) / 12.0)

# ---------- The clips ----------

func _build_effects() -> void:
	# Tire chirp (at touchdown): a soft little squeak and puff, no edge.
	_streams["chirp"] = _wav(_norm(_chirp(), LVL_GAME * 0.8))
	# Landing: a warm two-note chime, each landing in quick succession one step higher up the scale.
	var base := [[5, 7], [6, 8], [7, 9], [8, 10], [9, 11], [10, 12], [11, 13]]
	for k in STEPS:
		var a := _bell(note_hz(base[k][0]), 0.9, 1.0, 0.8)
		var b := _bell(note_hz(base[k][1]), 1.0, 0.85, 0.8)
		_streams["landing_%d" % k] = _wav(_norm(_reverb(_mix_at(_mix_at(PackedFloat32Array(), a, 0), b, int(0.11 * RATE)), 0.35, 0.5), LVL_BIG))
		# Coins: bright-but-soft bell plinks, rising with each coin that reaches the counter.
		var c := _bell(note_hz(7 + k), 0.45, 1.0, 1.0)
		_streams["coin_%d" % k] = _wav(_norm(_reverb(c, 0.25, 0.35), LVL_GAME * 0.7))
	_streams["landing"] = _streams["landing_0"]
	_streams["coin"] = _streams["coin_0"]
	# Fine: a low, muted thud. Conflict: the thud with a soft descending two-tone over it.
	_streams["fine"] = _wav(_norm(_reverb(_thud(0.5), 0.15, 0.3), LVL_GAME))
	var tone1 := _soft(note_hz(4) * 0.5, 0.22, 0.8)       # A3
	var tone2 := _soft(note_hz(2) * 0.5, 0.34, 0.8)       # E3
	var alarm := _mix_at(_mix_at(_thud(0.5), tone1, int(0.02 * RATE)), tone2, int(0.2 * RATE))
	_streams["alarm"] = _wav(_norm(_reverb(alarm, 0.2, 0.4), LVL_GAME))
	# Go-around: a soft whoosh with a rising engine swell under it.
	_streams["go_around"] = _wav(_norm(_reverb(_swell(1.0), 0.2, 0.3), LVL_GAME))
	# Wind shift: three slow, low bell notes (E, D, A).
	var w := _mix_at(_mix_at(_bell(note_hz(7), 0.9, 1.0, 0.6), _bell(note_hz(6), 0.9, 0.9, 0.6), int(0.22 * RATE)), _bell(note_hz(4), 1.2, 0.9, 0.6), int(0.44 * RATE))
	_streams["wind"] = _wav(_norm(_reverb(w, 0.35, 0.6), LVL_GAME))
	# Last arrivals: a gentle rising figure (G A C E). Clear sky: a warm major chord, slowly blooming.
	var la := PackedFloat32Array()
	for k in 4:
		la = _mix_at(la, _bell(note_hz(3 + k + (1 if k > 1 else 0)), 0.8, 1.0 - 0.1 * k, 0.7), int(k * 0.16 * RATE))
	_streams["last_arrivals"] = _wav(_norm(_reverb(la, 0.35, 0.6), LVL_BIG * 0.8))
	_streams["clear_sky"] = _wav(_norm(_reverb(_chord([note_hz(0), note_hz(2), note_hz(3), note_hz(5)], 1.6), 0.4, 0.7), LVL_BIG * 0.8))
	# Timer tick: a tiny soft knock. (The game plays it faster and slightly higher as time runs short.)
	_streams["tick"] = _wav(_norm(_knock(640.0, 0.05), LVL_UI * 1.2))
	# UI: very quiet, very short, soft clicks.
	_streams["tap"] = _wav(_norm(_knock(520.0, 0.06), LVL_UI))
	_streams["press"] = _wav(_norm(_knock(330.0, 0.05), LVL_UI * 0.7))
	_streams["back"] = _wav(_norm(_mix_at(_knock(440.0, 0.05), _knock(330.0, 0.07), int(0.05 * RATE)), LVL_UI))
	_streams["toggle"] = _wav(_norm(_knock(720.0, 0.04), LVL_UI * 0.8))
	_streams["error"] = _wav(_norm(_soft(note_hz(2) * 0.5, 0.16, 0.9), LVL_UI * 1.5))
	_streams["whoosh"] = _wav(_norm(_whoosh(0.25, 500.0, 1100.0), LVL_UI * 1.1))
	# A purchase: three soft plinks up the scale. A star: a rising four-note bell figure. A new airport: a little melody.
	var buy := _mix_at(_mix_at(_bell(note_hz(7), 0.4, 1.0, 1.0), _bell(note_hz(9), 0.4, 0.9, 1.0), int(0.07 * RATE)), _bell(note_hz(10), 0.6, 0.9, 1.0), int(0.14 * RATE))
	_streams["buy"] = _wav(_norm(_reverb(buy, 0.3, 0.5), LVL_GAME))
	var star := PackedFloat32Array()
	for k in 4:
		star = _mix_at(star, _bell(note_hz(8 + k), 0.7, 1.0, 1.0), int(k * 0.09 * RATE))
	_streams["star"] = _wav(_norm(_reverb(star, 0.4, 0.6), LVL_BIG))
	var un := PackedFloat32Array()
	for k in 5:
		un = _mix_at(un, _bell(note_hz([5, 7, 8, 10, 12][k]), 0.9, 1.0, 0.9), int(k * 0.12 * RATE))
	_streams["unlock"] = _wav(_norm(_reverb(un, 0.45, 0.8), LVL_BIG))
	# A results star slamming in: a warm thud with a bell on top.
	_streams["slam"] = _wav(_norm(_reverb(_mix_at(_thud(0.45), _bell(note_hz(10), 0.8, 0.7, 0.8), int(0.03 * RATE)), 0.3, 0.5), LVL_BIG))

## Engine beds: low, smooth and quiet. All frequencies are whole Hz, so the one-second loop is seamless.
func _hum(t: int) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(RATE)
	for i in RATE:
		var s := float(i) / RATE
		var v := 0.0
		match t:
			0:      # glider: air moving over wings
				v = 0.6 * sin(TAU * 220.0 * s) * (0.7 + 0.3 * sin(TAU * 3.0 * s)) + 0.35 * sin(TAU * 330.0 * s + 1.0) * (0.7 + 0.3 * sin(TAU * 2.0 * s)) + 0.2 * sin(TAU * 440.0 * s)
			1:      # helicopter: a slow, soft chop
				v = (sin(TAU * 70.0 * s) + 0.5 * sin(TAU * 140.0 * s)) * (0.6 + 0.4 * sin(TAU * 6.0 * s))
			2:      # small plane: a mellow propeller
				v = (sin(TAU * 90.0 * s) + 0.4 * sin(TAU * 180.0 * s) + 0.15 * sin(TAU * 270.0 * s)) * (0.8 + 0.2 * sin(TAU * 24.0 * s))
			3:      # medium plane: deeper twin props
				v = (sin(TAU * 65.0 * s) + 0.45 * sin(TAU * 130.0 * s) + 0.15 * sin(TAU * 195.0 * s)) * (0.8 + 0.2 * sin(TAU * 15.0 * s))
			4:      # jet: a low rumble with a faint whisper above it
				v = sin(TAU * 55.0 * s) + 0.5 * sin(TAU * 110.0 * s) + 0.12 * sin(TAU * 330.0 * s) + 0.1 * sin(TAU * 440.0 * s + 2.0)
			_:      # seaplane: a prop with a slow wobble
				v = (sin(TAU * 80.0 * s) + 0.4 * sin(TAU * 160.0 * s)) * (0.75 + 0.25 * sin(TAU * 8.0 * s))
		out[i] = v
	return _wav(_norm(out, LVL_HUM), true)

## An 8-beat loop (6 s) in C major: C, Am, F, G, two beats each. The calm layer is a warm pad with a soft bass; the intense
## layer is a plucked pentatonic arpeggio with a very soft pulse underneath. Both loops are seamless, and equally long.
func _music(hot: bool) -> AudioStreamWAV:
	var n := int(BEAT * 8.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	if not hot:
		var chords := [[130.81, 261.63, 329.63, 392.0], [110.0, 220.0, 261.63, 329.63], [87.31, 174.61, 220.0, 261.63], [98.0, 196.0, 246.94, 293.66]]
		var seg := 2.0 * BEAT
		for c in 4:
			var start := c * seg - 0.25
			var length := seg + 0.5
			for f_v in chords[c]:
				var f: float = f_v
				for i in int(length * RATE):
					var t := float(i) / RATE
					var w := minf(smoothstep(0.0, 0.45, t), smoothstep(0.0, 0.45, length - t))
					var idx := posmod(int((start + t) * RATE), n)
					var ph: float = TAU * f * (start + t)
					out[idx] += (sin(ph) + 0.25 * sin(2.0 * ph)) * w * (0.28 if f > 150.0 else 0.4)
		return _wav(_norm(out, 0.35), true)
	var arps := [[5, 7, 8, 7], [4, 5, 7, 5], [4, 5, 6, 5], [3, 6, 8, 6]]
	var eighth := BEAT * 0.5
	for c in 4:
		for k in 4:
			var at := int((c * 4 + k) * eighth * RATE)
			var note := _bell(note_hz(arps[c][k]), 0.9, 0.55 if k > 0 else 0.7, 0.5)
			for i in note.size():
				out[posmod(at + i, n)] += note[i]
	for b in 8:
		var at2 := int(b * BEAT * RATE)
		for i in int(0.22 * RATE):
			var t2 := float(i) / RATE
			out[posmod(at2 + i, n)] += 0.22 * sin(TAU * lerpf(80.0, 50.0, minf(t2 * 6.0, 1.0)) * t2) * exp(-t2 * 14.0) * smoothstep(0.0, 0.012, t2)
	out = _reverb_loop(out, 0.3)
	return _wav(_norm(out, 0.35), true)

## Fog ambience: a soft, slow breath of low filtered air (a two-second loop; its ends are crossfaded so it is seamless).
func _fog_ambience() -> AudioStreamWAV:
	var n := RATE * 2
	var fade := RATE / 4
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var seed_v := 4242
	var lp := 0.0
	var lp2 := 0.0
	for i in n + fade:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += (noise - lp) * 0.04
		lp2 += (lp - lp2) * 0.08
		raw[i] = lp2 * (0.65 + 0.35 * sin(TAU * 0.5 * float(i) / RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		if i < fade:
			var a := float(i) / fade
			out[i] = raw[i] * a + raw[n + i] * (1.0 - a)
		else:
			out[i] = raw[i]
	return _wav(_norm(out, 0.25), true)

## A low, tense but soft drone for fog: a tritone pair that slowly shivers, in the same 6 s length as the music.
func _music_tense_loop() -> AudioStreamWAV:
	var secs := BEAT * 8.0
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f1 := roundf(55.0 * secs) / secs          # whole cycles per loop: no click at the seam
	var f2 := roundf(77.8 * secs) / secs
	var ft := roundf(2.0 * secs) / secs
	for i in n:
		var t := float(i) / RATE
		var trem := 0.7 + 0.3 * sin(TAU * ft * t)
		out[i] = (sin(TAU * f1 * t) + 0.7 * sin(TAU * f2 * t) + 0.2 * sin(TAU * f2 * 2.0 * t)) * trem
	return _wav(_norm(out, 0.3), true)

# ---------- Voices and DSP ----------

## Smooth fade in over `a` samples and out over `r` samples (raised-cosine): no clicks, ever.
static func _win(i: int, n: int, a: int, r: int) -> float:
	var v := 1.0
	if i < a:
		var s := sin(PI * 0.5 * float(i) / maxf(a, 1))
		v = s * s
	var j := n - 1 - i
	if j < r:
		var s2 := sin(PI * 0.5 * float(j) / maxf(r, 1))
		v *= s2 * s2
	return v

## A bell: a sine with two softer, quicker-fading overtones. `bright` scales the overtones.
func _bell(f: float, dur: float, amp: float, bright: float = 1.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.008 * RATE)
	var r_n := int(0.04 * RATE)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * f * t) * exp(-t * 4.5)
		if f * 2.0 < RATE * 0.5:
			v += 0.3 * bright * sin(TAU * f * 2.0 * t) * exp(-t * 8.0)
		if f * 3.0 < RATE * 0.5:
			v += 0.08 * bright * sin(TAU * f * 3.0 * t) * exp(-t * 13.0)
		out[i] = v * amp * _win(i, n, a_n, r_n)
	return out

## A soft, slightly hollow tone (a sine with a touch of triangle), lowpassed: for the muted "bonk" and the descending pair.
func _soft(f: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.012 * RATE)
	var r_n := int(0.06 * RATE)
	for i in n:
		var t := float(i) / RATE
		var ph := fposmod(f * t, 1.0)
		var tri := 4.0 * absf(ph - 0.5) - 1.0
		out[i] = (0.8 * sin(TAU * f * t) + 0.2 * tri) * exp(-t * 6.0) * amp * _win(i, n, a_n, r_n)
	return _lp(out, 900.0)

## A warm chord: sines with a slow bloom and a long release.
func _chord(freqs: Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.25 * RATE)
	var r_n := int(0.5 * RATE)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t) + 0.2 * sin(TAU * float(f) * 2.0 * t)
		out[i] = v / freqs.size() * exp(-t * 1.6) * _win(i, n, a_n, r_n)
	return out

## A low thud: a sine falling from 120 to 55 Hz with a soft attack and a rounded decay.
func _thud(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.01 * RATE)
	var r_n := int(0.08 * RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(120.0, 55.0, minf(t * 5.0, 1.0)) / RATE
		out[i] = sin(ph) * exp(-t * 9.0) * _win(i, n, a_n, r_n)
	return _lp(out, 500.0)

## A tiny soft knock: a short sine with a rounded start.
func _knock(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.006 * RATE)
	var r_n := int(0.014 * RATE)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * f * t) * exp(-t * 60.0) * _win(i, n, a_n, r_n)
	return _lp(out, 1400.0)

## The tire chirp: a brief breath of filtered noise and a faint, falling squeak.
func _chirp() -> PackedFloat32Array:
	var n := int(0.11 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.012 * RATE)
	var r_n := int(0.04 * RATE)
	var seed_v := 99
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		ph += TAU * lerpf(1050.0, 820.0, t / 0.11) / RATE
		out[i] = (0.5 * noise + 0.5 * sin(ph)) * exp(-t * 22.0) * _win(i, n, a_n, r_n)
	return _lp(_lp(out, 2200.0), 2200.0)

## Filtered noise that rises and falls in brightness: a swish.
func _whoosh(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_v := 777
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / n
		var fc := lerpf(f0, f1, sin(PI * k))
		var a := 1.0 - exp(-TAU * fc / RATE)
		lp += (noise - lp) * a
		lp2 += (lp - lp2) * a
		out[i] = lp2 * sin(PI * k)
	return out

## The go-around: a whoosh with a rising engine note (a sine climbing 90 -> 170 Hz and swelling).
func _swell(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var wh := _whoosh(dur, 300.0, 900.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * lerpf(90.0, 170.0, k * k) / RATE
		var env := sin(PI * minf(k * 1.1, 1.0)) * k
		out[i] = 0.9 * wh[i] * 0.6 + (sin(ph) + 0.4 * sin(2.0 * ph)) * env * 0.5
	return _lp(out, 1200.0)

## One-pole lowpass (applied to taste: twice is 12 dB per octave).
func _lp(x: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * fc / RATE)
	var y := 0.0
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		y += a * (x[i] - y)
		out[i] = y
	return out

## Scale a clip so its peak is `peak`.
func _norm(x: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in x:
		m = maxf(m, absf(v))
	var g := peak / m
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		out[i] = x[i] * g
	return out

## Add `src` into `dst` starting at sample `at` (growing `dst` as needed).
func _mix_at(dst: PackedFloat32Array, src: PackedFloat32Array, at: int) -> PackedFloat32Array:
	var out := dst.duplicate()
	if out.size() < at + src.size():
		out.resize(at + src.size())
	for i in src.size():
		out[at + i] += src[i]
	return out

## A short shared "room": four damped combs and a tail, mixed in at `wet`. The clip grows by `tail` seconds.
func _reverb(x: PackedFloat32Array, wet: float, tail: float) -> PackedFloat32Array:
	var n := x.size() + int(tail * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var d := [int(0.0297 * RATE), int(0.0371 * RATE), int(0.0411 * RATE), int(0.0437 * RATE)]
	var fb := [0.74, 0.72, 0.7, 0.68]
	var b0 := PackedFloat32Array()
	var b1 := PackedFloat32Array()
	var b2 := PackedFloat32Array()
	var b3 := PackedFloat32Array()
	b0.resize(d[0])
	b1.resize(d[1])
	b2.resize(d[2])
	b3.resize(d[3])
	var i0 := 0
	var i1 := 0
	var i2 := 0
	var i3 := 0
	var s0 := 0.0
	var s1 := 0.0
	var s2 := 0.0
	var s3 := 0.0
	for i in n:
		var inp := x[i] if i < x.size() else 0.0
		var o0 := b0[i0]
		var o1 := b1[i1]
		var o2 := b2[i2]
		var o3 := b3[i3]
		s0 += 0.45 * (o0 - s0)
		s1 += 0.45 * (o1 - s1)
		s2 += 0.45 * (o2 - s2)
		s3 += 0.45 * (o3 - s3)
		b0[i0] = inp + s0 * fb[0]
		b1[i1] = inp + s1 * fb[1]
		b2[i2] = inp + s2 * fb[2]
		b3[i3] = inp + s3 * fb[3]
		i0 = (i0 + 1) % d[0]
		i1 = (i1 + 1) % d[1]
		i2 = (i2 + 1) % d[2]
		i3 = (i3 + 1) % d[3]
		var tailv := t_fade(i, x.size(), n)
		out[i] = inp + wet * 0.25 * (o0 + o1 + o2 + o3) * tailv
	return out

## The tail fades out smoothly over the last third of its length (so a clip never ends on a sound).
static func t_fade(i: int, body: int, n: int) -> float:
	var tail := n - body
	if tail <= 0 or i < n - tail / 3:
		return 1.0
	var k := float(n - i) / maxf(tail / 3.0, 1.0)
	return k * k

## The room for a loop: run the loop twice through the reverb and keep the second pass (a seamless tail).
func _reverb_loop(x: PackedFloat32Array, wet: float) -> PackedFloat32Array:
	var two := PackedFloat32Array()
	two.resize(x.size() * 2)
	for i in x.size():
		two[i] = x[i]
		two[x.size() + i] = x[i]
	var r := _reverb(two, wet, 0.0)
	return r.slice(x.size(), x.size() * 2)

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w
