class_name Sfx
extends Node
## The game's sound, in the spirit of Mini Metro / Alto's Adventure: soft, rounded, cozy (see docs/style.md, "Audio").
## Nothing is synthesised at run time: every sound is a pre-rendered 44.1 kHz 16-bit WAV in assets/audio/ (made by
## tools/render_audio.gd from scripts/SfxSynth.gd). One-shots play from a small pool of players, and the gameplay ones wait for the
## next eighth-note of the music so they land on the beat. There is no engine hum: the music is the only continuous sound
## (plus the fog ambience). The looping layers are the problem on the web: Godot's web samples loop by restarting a new buffer
## from the "ended" event on the main thread, which leaves a gap at every wrap when a phone is busy. So on the web the
## PAGE plays the loops itself (PWAudio in web/shell.html: native, gapless AudioBufferSource loops off the main thread)
## and this script only tells it the level of each layer. Everywhere else (the editor, the tests) the loops are ordinary
## looping players. Buses come from default_bus_layout.tres and are never created at run time.

const RATE := 44100
const POOL := 14
const STEPS := 7               # landing chimes / coin plinks: this many steps up the scale
const BEAT := 0.75             # music: seconds per beat, 8 beats per loop (6 s)
const NAMES := ["landing", "coin", "go_around", "alarm", "fine", "wind", "last_arrivals", "clear_sky", "tick", "tap", "press", "star", "slam", "back", "toggle", "buy", "error", "whoosh", "unlock", "touch", "chirp", "gust", "rev", "arrive"]
## Gameplay sounds that wait for the next eighth-note of the music so they land on the beat (taps and results stingers do not).
const QUANTIZED := ["landing", "chirp", "gust", "coin", "arrive", "go_around", "alarm", "fine", "tick", "wind", "last_arrivals", "clear_sky"]
const EIGHTH := BEAT * 0.5           # the music's grid: 16 eighths per 6 s loop
const LOOP_SECS := BEAT * 8.0
const MAX_PENDING := 12
const FILES := ["touch", "chirp", "gust", "rev", "arrive", "fine", "alarm", "go_around", "wind", "last_arrivals", "clear_sky", "tick", "tap", "press", "back", "toggle", "error", "whoosh", "buy", "star", "unlock", "slam"]
const LAYERS := ["calm", "hot", "tense", "fog"]

var enabled := true
var plays := {}                # sound name -> how many times it was triggered
var music_level := 0.0         # the intense layer's volume 0..1
var music_pitch := 1.0         # (always 1: shifting the music would take it out of key)
var fog_level := 0.0           # 0..1: the fog ambience and the tense music layer follow it
var held := false              # audio is held (the page went to the background): the Master bus is muted
var web_loops := false         # the page plays the loops (web build)
var quantize := true           # gameplay sounds wait for the music's next eighth-note (off in some tests)
var _pending: Array = []       # sounds waiting for their beat: [due_ms, stream, pitch, db, name]
var _recent_land: Array = []   # msec of the latest landings (the chime softens when they come close together)
var _clock0_ms := 0            # where the music loop's clock starts when the page does not provide one
var unlocked := false          # the first user gesture has happened (browsers keep audio suspended until then)

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music_calm: AudioStreamPlayer
var _music_hot: AudioStreamPlayer
var _music_tense: AudioStreamPlayer
var _fog_amb: AudioStreamPlayer
var _players := {}             # layer name -> its looping player (not on the web)
var _layer_db := {"calm": -80.0, "hot": -80.0, "tense": -80.0, "fog": -80.0}
var _js_sent := {}             # layer -> the level last sent to the page
var _music_on := false
var _menu_on := false
var _calm_db := -80.0          # what the music layers are at now; the targets come from the mode (a smooth crossfade)
var _hot_db := -80.0
var _calm_target := -80.0
var _hot_target := -80.0
const FADE_DB_PER_S := 60.0
const MENU_CALM_DB := -8.0
const SHIFT_CALM_DB := -4.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for n in NAMES:
		plays[n] = 0
	if DebugFlags.off("sound"):
		enabled = false
		return
	web_loops = OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.PWAudio && window.PWAudio.enabled)"))
	for f in FILES:
		_streams[f] = load("res://assets/audio/%s.wav" % f)
	for k in STEPS:
		_streams["landing_%d" % k] = load("res://assets/audio/landing_%d.wav" % k)
		_streams["coin_%d" % k] = load("res://assets/audio/coin_%d.wav" % k)
	_streams["landing"] = _streams["landing_0"]
	_streams["coin"] = _streams["coin_0"]
	for i in POOL:
		_pool.append(_player("SFX"))
	if not web_loops:
		_music_calm = _loop_player("calm", "Music")
		_music_hot = _loop_player("hot", "Music")
		_music_tense = _loop_player("tense", "Music")
		_fog_amb = _loop_player("fog", "Ambience")

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"      # (a missing bus must never be named: the web build aborts)
	add_child(p)
	return p

## A looping layer as an ordinary looping player (the editor and the tests; on the web the page does this).
func _loop_player(layer: String, bus: String) -> AudioStreamPlayer:
	var p := _player(bus)
	var st = load("res://assets/audio/loops/%s.wav" % layer)
	if st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / 2
		p.stream = st
	p.volume_db = -80.0
	_players[layer] = p
	return p

# ---------- Playing ----------

## A one-shot. `pitch` is a ratio (1 = as rendered); every play also gets about +-1% random pitch (the sounds stay in key) and
## a hair of random level. Gameplay sounds wait for the music's next eighth-note (see `_schedule`).
func play(sound: String, pitch: float = 1.0) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or not _streams.has(sound):
		return
	_schedule(sound, _streams[sound], pitch, 0.0)

## A sound that climbs the scale: "landing" and "coin" have STEPS clips, each a note higher in the key. Counts as `sound`.
## Landings in quick succession are each a little quieter (velocity): one landing is the full chime, five close together
## are about 9 dB down.
func play_step(sound: String, step: int) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled:
		return
	var key := "%s_%d" % [sound, clampi(step, 0, STEPS - 1)]
	if not _streams.has(key):
		return
	var db := 0.0
	if sound == "landing":
		var now := Time.get_ticks_msec()
		while not _recent_land.is_empty() and now - int(_recent_land[0]) > 3000:
			_recent_land.pop_front()
		db = -2.2 * minf(float(_recent_land.size()), 4.0)
		_recent_land.append(now)
	_schedule(sound, _streams[key], 1.0, db)

## Seconds into the music's 6 s loop (the page's audio clock on the web, else our own).
func music_phase() -> float:
	if web_loops:
		var ph = JavaScriptBridge.eval("window.PWAudio && PWAudio.phase ? PWAudio.phase() : -1")
		if ph is float and ph >= 0.0:
			return fposmod(ph, LOOP_SECS)
	return fposmod((Time.get_ticks_msec() - _clock0_ms) / 1000.0, LOOP_SECS)

## Seconds from now to the next eighth-note of the music.
func next_beat_wait() -> float:
	var into := fposmod(music_phase(), EIGHTH)
	var wait := EIGHTH - into
	return wait if wait > 0.03 else wait + EIGHTH      # (too close to the beat to make it: take the next one)

## Play now, or (a gameplay sound while the music runs) on the next eighth-note. One of each sound per beat at most.
func _schedule(sound: String, stream: AudioStream, pitch: float, db: float) -> void:
	if not quantize or not _music_on or not QUANTIZED.has(sound):
		_fire(stream, pitch, db)
		return
	var due := Time.get_ticks_msec() + int(next_beat_wait() * 1000.0)
	for e in _pending:
		if e[4] == sound and absi(int(e[0]) - due) < 120:
			return       # that beat already has one
	if _pending.size() >= MAX_PENDING:
		return
	_pending.append([due, stream, pitch, db, sound])

## How many sounds are waiting for their beat.
func pending_count() -> int:
	return _pending.size()

## Play everything that is waiting now (tests; leaving the shift).
func flush_pending() -> void:
	for e in _pending:
		_fire(e[1], e[2], e[3])
	_pending.clear()

func _fire(stream: AudioStream, pitch: float, db: float = 0.0) -> void:
	var p := _pool[_next]
	for k in POOL:     # a free player first: taking over one that is still sounding would cut it off with a click
		var q := _pool[(_next + k) % POOL]
		if not q.playing:
			p = q
			_next = (_next + k) % POOL
			break
	_next = (_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.99, 1.01)
	p.volume_db = _rng.randf_range(-0.5, 0.3) + db
	p.play()

## The first touch: browsers only let audio run after a gesture. Looping players that were started while the page was
## still locked are restarted now, so they begin cleanly with the audio context running.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if not enabled:
		return
	for p in _players.values():
		if p.playing:
			p.stop()
			p.play()

## The page went to the background (or the phone was locked): hold everything silent. Nothing resumes until `release()`.
func hold() -> void:
	held = true
	AudioServer.set_bus_mute(0, true)
	if web_loops:
		JavaScriptBridge.eval("window.PWAudio && PWAudio.setHeld(true)")

## The player is back and tapped (Resume): sound may run again.
func release() -> void:
	held = false
	AudioServer.set_bus_mute(0, false)
	if web_loops:
		JavaScriptBridge.eval("window.PWAudio && PWAudio.setHeld(false)")

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

## Work out where each layer should be; they glide there in _process (no jumps, no clicks).
func _retarget(hot: float) -> void:
	_calm_target = SHIFT_CALM_DB if _music_on else (MENU_CALM_DB if _menu_on else -80.0)
	_hot_target = linear_to_db(maxf(hot * 0.8, 0.0001)) - 6.0 if _music_on else -80.0
	if not enabled:
		return
	if (_calm_target > -70.0 or _hot_target > -70.0):
		_start_layers(["calm", "hot"])

func _glide_music(delta: float) -> void:
	_calm_db = move_toward(_calm_db, _calm_target, FADE_DB_PER_S * delta)
	_hot_db = move_toward(_hot_db, _hot_target, FADE_DB_PER_S * delta)
	_set_layer("calm", _calm_db)
	_set_layer("hot", _hot_db)
	if _calm_db <= -75.0 and _hot_db <= -75.0 and _calm_target <= -70.0:
		_stop_layers(["calm", "hot"])

## Fog: a soft ambient bed, and a tense (but still soft) music layer on top of the music while it is around.
func set_fog(level: float) -> void:
	fog_level = clampf(level, 0.0, 1.0)
	if not enabled:
		return
	if fog_level > 0.01:
		_start_layers(["fog"])
		_set_layer("fog", linear_to_db(fog_level) + Tuning.fog_ambient_db)
	else:
		_set_layer("fog", -80.0)
		_stop_layers(["fog"])
	var tense := fog_level * Tuning.fog_music_tension if _music_on else 0.0
	if tense > 0.01:
		_start_layers(["tense"])
		_set_layer("tense", linear_to_db(tense) - 9.0)
	else:
		_set_layer("tense", -80.0)
		_stop_layers(["tense"])

func _process(delta: float) -> void:
	if not enabled:
		return
	_glide_music(delta)
	if not _pending.is_empty():
		var now_ms := Time.get_ticks_msec()
		var k := 0
		while k < _pending.size():
			var e: Array = _pending[k]
			if now_ms >= int(e[0]):
				_fire(e[1], e[2], e[3])
				_pending.remove_at(k)
			else:
				k += 1
	if web_loops:
		_push_levels()

# ---------- The looping layers ----------

func _start_layers(names: Array) -> void:
	if _clock0_ms == 0:
		_clock0_ms = Time.get_ticks_msec()
	for n in names:
		var p: AudioStreamPlayer = _players.get(n)
		if p != null and not p.playing and p.stream != null:
			p.play()

func _stop_layers(names: Array) -> void:
	for n in names:
		var p: AudioStreamPlayer = _players.get(n)
		if p != null and p.playing and _layer_db[n] <= -75.0:
			p.stop()

func _set_layer(name: String, db: float) -> void:
	_layer_db[name] = db
	var p: AudioStreamPlayer = _players.get(name)
	if p != null:
		p.volume_db = db

## The bus a layer sits on: Music for the music, Ambience for the fog (their volume sliders and mutes apply).
func _bus_db(layer: String) -> float:
	var idx := AudioServer.get_bus_index("Music" if layer == "calm" or layer == "hot" or layer == "tense" else "Ambience")
	if idx < 0:
		return 0.0
	return -80.0 if AudioServer.is_bus_mute(idx) else AudioServer.get_bus_volume_db(idx)

## Tell the page the level of every layer that changed (one small call per frame at most).
func _push_levels() -> void:
	var changed := ""
	for n in LAYERS:
		var out_db := maxf(_layer_db[n] + _bus_db(n), -80.0)
		if not _js_sent.has(n) or absf(out_db - float(_js_sent[n])) > 0.05:
			_js_sent[n] = out_db
			changed += "%s:%.2f," % [n, out_db]
	if changed != "":
		JavaScriptBridge.eval("window.PWAudio.setMany({" + changed + "})")
