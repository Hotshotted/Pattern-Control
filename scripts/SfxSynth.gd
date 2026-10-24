class_name SfxSynth
extends RefCounted
## Renders every sound of the game (see docs/style.md, "Audio") as float samples. Run offline by tools/render_audio.gd, which
## writes the 44.1 kHz 16-bit WAV files in assets/audio/ that the game loads; the game itself never synthesises anything.
## Soft sines and filtered noise, raised-cosine envelopes, a baked-in room, everything in D major pentatonic.
## (No autoload references: the smoke test re-renders everything and compares it with the committed files.)

const STEPS := 7               # landing chimes / coin plinks: this many steps up the scale
## The music: 112 BPM, D major, eight bars (32 beats, 17.14 s) in three layers that loop together. A beat is exactly 23 625 samples.
const BPM := 112.0
const BEAT := 60.0 / BPM       # seconds per beat
const BEATS := 32              # beats per loop
const LOOP_SECS := BEAT * BEATS
const D4 := 293.6648           # the key's tonic (every pitched sound is in D major pentatonic: D E F# A B)
const PENTA := [0, 2, 4, 7, 9]  # D E F# A B

# Loudness by role (peak, linear), with the MUSIC as the reference: the music as it is heard (the calm layer's peak 0.35 played at
# MUSIC_DB in Sfx.gd) peaks at MUSIC_REF; gameplay sounds sit at or below 0.8 of it, UI sounds at or below 0.5 of it.
const MUSIC_REF := 0.22
const LVL_UI := 0.09           # taps, ticks, clicks (<= 0.5 x MUSIC_REF)
const LVL_GAME := 0.14         # landings, fines, go-arounds, wind (<= 0.8 x MUSIC_REF)
const LVL_BIG := 0.16          # stars, a new airport, the results slam (<= 0.8 x MUSIC_REF)

var rate := 44100

## Every one-shot: name -> samples.
func clips() -> Dictionary:
	var out := {}
	_build_effects_into(out)
	return out

## Every loop: name -> samples. music1 (bass and percussion), music2 (rhythm guitar and keys) and music3 (the lead) are the same length
## and play together; tense is the fog's low drone, fog its breath of air. There is no engine hum: the music is the only continuous sound.
func loops() -> Dictionary:
	return {"music1": _layer_rhythm(), "music2": _layer_chords(), "music3": _layer_lead(), "tense": _music_tense_loop(), "fog": _fog_ambience()}

# ---------- The key ----------

## Frequency of scale degree `deg` of D major pentatonic: 0 = D4, 1 = E4, 2 = F#4, 3 = A4, 4 = B4, 5 = D5, ...
static func note_hz(deg: int) -> float:
	var oct := floori(float(deg) / 5.0)
	return D4 * pow(2.0, float(PENTA[posmod(deg, 5)] + 12 * oct) / 12.0)

# ---------- The clips ----------

func _build_effects_into(clips: Dictionary) -> void:
	# Touchdown: a very soft, low-passed tap, far below the chime (no squeal).
	clips["touch"] = _norm(_lp(_lp(_thud(0.16), 220.0), 220.0), 0.03)
	# Tyre chirp: a tiny, soft upward blip in the key (A5 gliding to B5), far below the chime; the game plays it on the beat.
	clips["chirp"] = _norm(_lp(_chirp(note_hz(7), note_hz(8), 0.09), 1500.0), LVL_UI * 0.35)
	# Arrival: a very soft, short tone (A4); the game plays it on the beat.
	clips["arrive"] = _norm(_soft(note_hz(3), 0.2, 1.0), LVL_UI * 0.3)
	# Landing: ONE soft chime in the key, each landing in quick succession one step higher up the scale (the game plays it
	# on the next eighth-note of the music, softer when many land close together).
	for k in STEPS:
		var a := _bell(note_hz(5 + k), 1.0, 1.0, 0.6)
		clips["landing_%d" % k] = _norm(_reverb(a, 0.3, 0.5), LVL_GAME * 0.9)
		# Coins: tiny bell plinks, rising with each coin that reaches the counter; quieter than the chime.
		var c := _bell(note_hz(7 + k), 0.4, 1.0, 0.8)
		clips["coin_%d" % k] = _norm(_reverb(c, 0.25, 0.35), LVL_GAME * 0.4)
	# Fine: a low, muted thud. Conflict: the thud with a soft descending two-tone over it.
	clips["fine"] = _norm(_reverb(_thud(0.5), 0.15, 0.3), LVL_GAME * 0.8)
	var tone1 := _soft(note_hz(4) * 0.5, 0.22, 0.8)       # B3
	var tone2 := _soft(note_hz(2) * 0.5, 0.34, 0.8)       # F#3
	var alarm := _mix_at(_mix_at(_thud(0.5), tone1, int(0.02 * rate)), tone2, int(0.2 * rate))
	clips["alarm"] = _norm(_reverb(alarm, 0.2, 0.4), LVL_GAME * 0.9)
	# Go-around: two soft rising tones (E, A) in the key, no noise.
	clips["go_around"] = _norm(_reverb(_mix_at(_soft(note_hz(2) * 0.5, 0.5, 1.0), _soft(note_hz(4) * 0.5, 0.7, 0.9), int(0.2 * rate)), 0.25, 0.4), LVL_GAME * 0.9)
	# Wind shift: three slow bell notes stepping down the scale.
	var w := _mix_at(_mix_at(_bell(note_hz(7), 0.9, 1.0, 0.6), _bell(note_hz(6), 0.9, 0.9, 0.6), int(0.22 * rate)), _bell(note_hz(4), 1.2, 0.9, 0.6), int(0.44 * rate))
	clips["wind"] = _norm(_reverb(w, 0.35, 0.6), LVL_GAME * 0.8)
	# The engine note rising before a go-around: a soft glide from B3 up to F#4 (in the key) over most of a second.
	clips["rev"] = _norm(_lp(_chirp(note_hz(4) * 0.5, note_hz(2), 0.9), 1100.0), LVL_UI * 0.6)
	# Gust: a soft swell of low, filtered air under the music when the wind shifts (no pitch, far below the bells).
	clips["gust"] = _norm(_lp(_whoosh(1.0, 260.0, 620.0), 900.0), LVL_UI * 0.7)
	# Last arrivals: a gentle rising figure up the scale. Clear sky: a warm major chord, slowly blooming.
	var la := PackedFloat32Array()
	for k in 4:
		la = _mix_at(la, _bell(note_hz(3 + k + (1 if k > 1 else 0)), 0.8, 1.0 - 0.1 * k, 0.7), int(k * 0.16 * rate))
	clips["last_arrivals"] = _norm(_reverb(la, 0.35, 0.6), LVL_BIG * 0.7)
	clips["clear_sky"] = _norm(_reverb(_chord([note_hz(0), note_hz(2), note_hz(3), note_hz(5)], 1.6), 0.4, 0.7), LVL_BIG * 0.7)
	# Timer tick: a tiny soft knock. (The game plays it faster and slightly higher as time runs short.)
	clips["tick"] = _norm(_knock(note_hz(3), 0.05), LVL_UI * 0.9)
	# UI: very quiet, very short, soft clicks.
	clips["tap"] = _norm(_knock(note_hz(5), 0.06), LVL_UI)
	clips["press"] = _norm(_knock(note_hz(1), 0.05), LVL_UI * 0.7)
	clips["back"] = _norm(_mix_at(_knock(note_hz(3), 0.05), _knock(note_hz(1), 0.07), int(0.05 * rate)), LVL_UI)
	clips["toggle"] = _norm(_knock(note_hz(7), 0.04), LVL_UI * 0.8)
	clips["error"] = _norm(_soft(note_hz(2) * 0.5, 0.16, 0.9), LVL_UI * 1.2)
	clips["whoosh"] = _norm(_whoosh(0.25, 500.0, 1100.0), LVL_UI * 1.1)
	# A purchase: three soft plinks up the scale. A star: a rising four-note bell figure. A new airport: a little melody.
	var buy := _mix_at(_mix_at(_bell(note_hz(7), 0.4, 1.0, 1.0), _bell(note_hz(9), 0.4, 0.9, 1.0), int(0.07 * rate)), _bell(note_hz(10), 0.6, 0.9, 1.0), int(0.14 * rate))
	clips["buy"] = _norm(_reverb(buy, 0.3, 0.5), LVL_GAME * 0.9)
	var star := PackedFloat32Array()
	for k in 4:
		star = _mix_at(star, _bell(note_hz(8 + k), 0.7, 1.0, 1.0), int(k * 0.09 * rate))
	clips["star"] = _norm(_reverb(star, 0.4, 0.6), LVL_BIG)
	var un := PackedFloat32Array()
	for k in 5:
		un = _mix_at(un, _bell(note_hz([5, 7, 8, 10, 12][k]), 0.9, 1.0, 0.9), int(k * 0.12 * rate))
	clips["unlock"] = _norm(_reverb(un, 0.45, 0.8), LVL_BIG)
	# A results star slamming in: a warm thud with a bell on top.
	clips["slam"] = _norm(_reverb(_mix_at(_thud(0.45), _bell(note_hz(10), 0.8, 0.7, 0.8), int(0.03 * rate)), 0.3, 0.5), LVL_BIG)

# ---------- The music ----------
# D major, 112 BPM: D | A | Bm | G | D | A | G | A, one bar each, eight bars. Three layers, each a loop of exactly the same length, so they
# can be faded in and out over each other without ever drifting: 1 = bass and soft percussion, 2 = rhythm guitar and keys,
# 3 = the lead (a plucked mallet). No pads, no wash: every sound is a short pluck, and the only "room" is a tape-style echo on the lead.

const CHORD_ROOT := [0, 7, 9, 5, 0, 7, 5, 7]       # semitones above D: D A B G D A G A (the Bm bar's root is B)
# Guitar voicings, semitones above D3 (146.83 Hz), low string first.
const VOICING := {0: [0, 7, 12, 16], 7: [-5, 2, 7, 11, 14], 9: [-3, 4, 9, 12, 16], 5: [-7, 0, 5, 9, 12]}
# The lead, in eighth-notes from the start of the loop: [eighth, semitones above D4, length in eighths].
const LEAD := [
	[0, 7, 2], [2, 9, 1], [3, 7, 1], [4, 4, 2], [6, 7, 2],                       # D:  A B A F# A
	[8, 14, 3], [11, 12, 1], [12, 11, 2], [14, 7, 1], [15, 11, 1],               # A:  E D C# A C#
	[16, 12, 2], [18, 9, 1], [19, 12, 1], [20, 16, 2], [22, 14, 1], [23, 12, 1], # Bm: D B D F# E D
	[24, 9, 3], [27, 12, 1], [28, 9, 1], [29, 7, 1], [30, 5, 2],                 # G:  B D B A G
	[32, 7, 2], [34, 9, 1], [35, 7, 1], [36, 12, 2], [38, 16, 2],                # D:  A B A D F#
	[40, 14, 2], [42, 11, 1], [43, 14, 1], [44, 19, 3], [47, 14, 1],             # A:  E C# E A E
	[48, 12, 2], [50, 9, 1], [51, 12, 1], [52, 17, 2], [54, 16, 1], [55, 14, 1], # G:  D B D G F# E
	[56, 11, 2], [58, 14, 2], [60, 7, 2], [62, 11, 1], [63, 7, 1],               # A:  C# E A C# A (back to the top)
]

func _eighth_at(e: float) -> int:
	return int(round(e * BEAT * 0.5 * rate))

func _loop_len() -> int:
	return int(round(LOOP_SECS * rate))

## Add `src` (times `gain`) into the loop `dst` at sample `at`; what runs past the end wraps round to the start, so the loop is seamless.
func _add_wrap(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float = 1.0) -> void:
	var n := dst.size()
	var j := posmod(at, n)
	for i in src.size():
		dst[j] += src[i] * gain
		j += 1
		if j == n:
			j = 0

## A soft electric-bass pluck: a round tone with a little second and third harmonic (so a phone's speaker still shows it).
func _bass(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.006 * rate)
	var r_n := int(0.03 * rate)
	for i in n:
		var t := float(i) / rate
		var ph := TAU * f * t
		out[i] = (sin(ph) + 0.8 * sin(2.0 * ph) * exp(-t * 3.0) + 0.35 * sin(3.0 * ph) * exp(-t * 5.0)) * exp(-t * 2.0) * _win(i, n, a_n, r_n)
	return _lp(out, 1500.0)

## A light kick: a sine falling from 130 to 50 Hz, a soft attack and a quick decay.
func _kick() -> PackedFloat32Array:
	var n := int(0.17 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		ph += TAU * (58.0 + 85.0 * exp(-t * 30.0)) / rate
		out[i] = sin(ph) * exp(-t * 17.0) * _win(i, n, int(0.004 * rate), int(0.05 * rate))
	return out

## A rim click: a short, high, rounded tick (a sine and a breath of noise).
func _rim() -> PackedFloat32Array:
	var n := int(0.06 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_v := 91
	for i in n:
		var t := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		out[i] = (sin(TAU * 1650.0 * t) * exp(-t * 85.0) + 0.35 * noise * exp(-t * 160.0)) * _win(i, n, int(0.001 * rate), int(0.02 * rate))
	return _lp(out, 4200.0)

## A shaker: a short puff of high-passed noise.
func _shaker() -> PackedFloat32Array:
	var n := int(0.07 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_v := 5309
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 2800.0 / rate)
	for i in n:
		var t := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += (noise - lp) * a
		out[i] = (noise - lp) * exp(-t * 55.0) * _win(i, n, int(0.006 * rate), int(0.03 * rate))
	return _lp(out, 7000.0)

## Layer 1: the bass (roots and fifths, one note per beat or so) and the soft percussion (kick on 1 and 3, rim on 2 and 4, a shaker
## on every eighth with the off-beats leaning in; a little 16th-note fill at the end of the eighth bar).
func _layer_rhythm() -> PackedFloat32Array:
	var n := _loop_len()
	var out := PackedFloat32Array()
	out.resize(n)
	var kick := _kick()
	var rim := _rim()
	var shk := _shaker()
	var accents := [0.5, 0.85, 0.6, 0.9, 0.5, 0.85, 0.6, 0.9]
	for bar in 8:
		var e0 := bar * 8
		var root: int = CHORD_ROOT[bar]
		var rf := 73.416 * pow(2.0, float(root) / 12.0)       # D2 and up
		var ff := rf * pow(2.0, 7.0 / 12.0)
		# bass: root (long), root, fifth, root
		# (each note runs a little into the next: the bass never lets go, so there is no gap of silence in the loop)
		_add_wrap(out, _bass(rf, BEAT * 1.6), _eighth_at(e0), 0.5)
		_add_wrap(out, _bass(rf, BEAT * 0.7), _eighth_at(e0 + 3), 0.38)
		_add_wrap(out, _bass(ff, BEAT * 1.1), _eighth_at(e0 + 4), 0.42)
		_add_wrap(out, _bass(rf, BEAT * 1.1), _eighth_at(e0 + 6), 0.42)
		# kick and rim
		_add_wrap(out, kick, _eighth_at(e0), 0.46)
		_add_wrap(out, kick, _eighth_at(e0 + 4), 0.38)
		if bar % 2 == 1:
			_add_wrap(out, kick, _eighth_at(e0 + 5), 0.2)
		_add_wrap(out, rim, _eighth_at(e0 + 2), 0.34)
		_add_wrap(out, rim, _eighth_at(e0 + 6), 0.38)
		for k in 8:
			_add_wrap(out, shk, _eighth_at(e0 + k), 0.4 * accents[k])
		if bar == 7:
			_add_wrap(out, shk, _eighth_at(e0 + 6.5), 0.3)
			_add_wrap(out, shk, _eighth_at(e0 + 7.5), 0.38)
			_add_wrap(out, rim, _eighth_at(e0 + 7.5), 0.2)
	return _norm(out, 0.35)

## One guitar string plucked: a handful of harmonics, the higher ones dying quicker (a bright start, a warm tail), a rounded attack.
func _pluck(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var amps := [1.0, 0.55, 0.32, 0.2, 0.1]
	var a_n := int(0.003 * rate)
	var r_n := int(0.05 * rate)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for k in 5:
			if f * (k + 1) < 6000.0:
				v += float(amps[k]) * sin(TAU * f * (k + 1) * t) * exp(-t * (3.0 + 2.2 * k))
		out[i] = v * _win(i, n, a_n, r_n)
	return _lp(out, 5200.0)

## A soft electric-piano note (the "keys"): a sine, a quick second harmonic and a hint of a third.
func _keys(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.006 * rate)
	var r_n := int(0.05 * rate)
	for i in n:
		var t := float(i) / rate
		var ph := TAU * f * t
		out[i] = (sin(ph) * exp(-t * 3.2) + 0.4 * sin(2.0 * ph) * exp(-t * 6.0) + 0.1 * sin(3.0 * ph) * exp(-t * 9.0)) * _win(i, n, a_n, r_n)
	return out

## Layer 2: the rhythm guitar (a down-down-up-up-down-up strum on each bar, the strings spread over a few milliseconds) and, on the
## off-beats, a light stab of keys.
func _layer_chords() -> PackedFloat32Array:
	var n := _loop_len()
	var out := PackedFloat32Array()
	out.resize(n)
	var plucks := {}                 # (frequency) -> its pluck, rendered once
	var keys := {}
	var strum := [[0, 1.0, true], [2, 0.7, true], [3, 0.5, false], [5, 0.55, false], [6, 0.8, true], [7, 0.45, false]]
	for bar in 8:
		var e0 := bar * 8
		var root: int = CHORD_ROOT[bar]
		var voices: Array = VOICING[root]
		for st in strum:
			var down: bool = st[2]
			var amp: float = st[1]
			var count := voices.size()
			for k in count:
				var idx := k if down else count - 1 - k
				var f := 146.8324 * pow(2.0, float(voices[idx]) / 12.0)
				if not plucks.has(f):
					plucks[f] = _pluck(f, BEAT * 1.1)
				_add_wrap(out, plucks[f], _eighth_at(e0 + st[0]) + int(float(k) * 0.011 * rate), 0.2 * amp * (0.8 if not down else 1.0))
		# keys: the chord's upper notes (an octave up) on the "and" of 2 and of 4
		for kk in [3, 7]:
			for v in [voices[voices.size() - 3], voices[voices.size() - 2], voices[voices.size() - 1]]:
				var fk := 146.8324 * 2.0 * pow(2.0, float(v) / 12.0)
				if not keys.has(fk):
					keys[fk] = _keys(fk, BEAT * 0.5)
				_add_wrap(out, keys[fk], _eighth_at(e0 + kk), 0.07)
	return _norm(out, 0.35)

## A marimba-like mallet: a sine and a bright fourth-partial that dies at once, a soft attack, a short ring.
func _mallet(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.004 * rate)
	var r_n := int(0.06 * rate)
	for i in n:
		var t := float(i) / rate
		var ph := TAU * f * t
		out[i] = (sin(ph) * exp(-t * 4.2) + 0.3 * sin(4.0 * ph) * exp(-t * 20.0) + 0.1 * sin(2.0 * ph) * exp(-t * 9.0)) * _win(i, n, a_n, r_n)
	return out

## Layer 3: the lead, a plucked mallet melody over the eight bars, with a dotted-eighth echo (three eighths later, a third as loud, a
## soft repeat that wraps round the loop).
func _layer_lead() -> PackedFloat32Array:
	var n := _loop_len()
	var out := PackedFloat32Array()
	out.resize(n)
	var mallets := {}
	for nt in LEAD:
		var semis: int = nt[1]
		var f := D4 * pow(2.0, float(semis) / 12.0)
		var len_e: int = nt[2]
		var key := "%d:%d" % [semis, len_e]
		if not mallets.has(key):
			mallets[key] = _mallet(f, BEAT * 0.5 * float(len_e) + 0.35)
		_add_wrap(out, mallets[key], _eighth_at(nt[0]), 0.5)
	var dry := out.duplicate()
	var delay := _eighth_at(3)
	for i in n:
		out[(i + delay) % n] += dry[i] * 0.3
	return _norm(_lp(out, 6500.0), 0.35)

## Fog ambience: a soft, slow breath of low filtered air (a two-second loop; its ends are crossfaded so it is seamless).
func _fog_ambience() -> PackedFloat32Array:
	var n := rate * 2
	var fade := rate / 4
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var seed_v := 4242
	var lp := 0.0
	var lp2 := 0.0
	var fa := 1.0 - exp(-TAU * 104.0 / rate)
	var fb := 1.0 - exp(-TAU * 212.0 / rate)
	for i in n + fade:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += (noise - lp) * fa
		lp2 += (lp - lp2) * fb
		raw[i] = lp2 * (0.65 + 0.35 * sin(TAU * 0.5 * float(i) / rate))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		if i < fade:
			var a := float(i) / fade
			out[i] = raw[i] * a + raw[n + i] * (1.0 - a)
		else:
			out[i] = raw[i]
	return _norm(out, 0.25)

## A low, tense but soft drone for fog: D and the tritone above it (A-flat) that slowly shiver, in the same length as the music.
func _music_tense_loop() -> PackedFloat32Array:
	var secs := LOOP_SECS
	var n := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var f1 := roundf(73.42 * secs) / secs          # whole cycles per loop: no click at the seam
	var f2 := roundf(103.83 * secs) / secs
	var ft := roundf(2.0 * secs) / secs
	for i in n:
		var t := float(i) / rate
		var trem := 0.7 + 0.3 * sin(TAU * ft * t)
		out[i] = (sin(TAU * f1 * t) + 0.7 * sin(TAU * f2 * t) + 0.2 * sin(TAU * f2 * 2.0 * t)) * trem
	return _norm(out, 0.3)

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
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.008 * rate)
	var r_n := int(0.04 * rate)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * f * t) * exp(-t * 4.5)
		if f * 2.0 < rate * 0.5:
			v += 0.3 * bright * sin(TAU * f * 2.0 * t) * exp(-t * 8.0)
		if f * 3.0 < rate * 0.5:
			v += 0.08 * bright * sin(TAU * f * 3.0 * t) * exp(-t * 13.0)
		out[i] = v * amp * _win(i, n, a_n, r_n)
	return out

## A soft, slightly hollow tone (a sine with a touch of triangle), lowpassed: for the muted "bonk" and the descending pair.
func _soft(f: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.012 * rate)
	var r_n := int(0.06 * rate)
	for i in n:
		var t := float(i) / rate
		var ph := fposmod(f * t, 1.0)
		var tri := 4.0 * absf(ph - 0.5) - 1.0
		out[i] = (0.8 * sin(TAU * f * t) + 0.2 * tri) * exp(-t * 6.0) * amp * _win(i, n, a_n, r_n)
	return _lp(out, 900.0)

## A short glide from `f0` to `f1` Hz, a sine with a quick attack and release.
func _chirp(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var u := float(i) / maxf(n - 1, 1)
		ph += TAU * lerpf(f0, f1, u) / rate
		out[i] = sin(ph) * _win(i, n, int(0.012 * rate), int(0.04 * rate))
	return out

## A warm chord: sines with a slow bloom and a long release.
func _chord(freqs: Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.25 * rate)
	var r_n := int(0.5 * rate)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t) + 0.2 * sin(TAU * float(f) * 2.0 * t)
		out[i] = v / freqs.size() * exp(-t * 1.6) * _win(i, n, a_n, r_n)
	return out

## A low thud: a sine falling from 120 to 55 Hz with a soft attack and a rounded decay.
func _thud(dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.01 * rate)
	var r_n := int(0.08 * rate)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		ph += TAU * lerpf(120.0, 55.0, minf(t * 5.0, 1.0)) / rate
		out[i] = sin(ph) * exp(-t * 9.0) * _win(i, n, a_n, r_n)
	return _lp(out, 500.0)

## A tiny soft knock: a short sine with a rounded start.
func _knock(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.006 * rate)
	var r_n := int(0.014 * rate)
	for i in n:
		var t := float(i) / rate
		out[i] = sin(TAU * f * t) * exp(-t * 60.0) * _win(i, n, a_n, r_n)
	return _lp(out, 1400.0)

## Filtered noise that rises and falls in brightness: a swish.
func _whoosh(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var n := int(dur * rate)
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
		var a := 1.0 - exp(-TAU * fc / rate)
		lp += (noise - lp) * a
		lp2 += (lp - lp2) * a
		out[i] = lp2 * sin(PI * k)
	return out

## One-pole lowpass (applied to taste: twice is 12 dB per octave).
func _lp(x: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * fc / rate)
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
	var n := x.size() + int(tail * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var d := [int(0.0297 * rate), int(0.0371 * rate), int(0.0411 * rate), int(0.0437 * rate)]
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
