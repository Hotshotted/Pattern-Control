class_name Sfx
extends Node
## The game's sound, in the spirit of Mini Metro / Alto's Adventure: soft, rounded, cozy (see docs/style.md, "Audio").
## Nothing is synthesised at run time: every sound is a pre-rendered 44.1 kHz 16-bit WAV in assets/audio/ (made by
## tools/render_audio.gd from scripts/SfxSynth.gd). One-shots play from a small pool of players. The looping layers
## (music, fog, the shared engine bed) are the problem on the web: Godot's web samples loop by restarting a new buffer
## from the "ended" event on the main thread, which leaves a gap at every wrap when a phone is busy. So on the web the
## PAGE plays the loops itself (PWAudio in web/shell.html: native, gapless AudioBufferSource loops off the main thread)
## and this script only tells it the level of each layer. Everywhere else (the editor, the tests) the loops are ordinary
## looping players. Buses come from default_bus_layout.tres and are never created at run time.

const RATE := 44100
const POOL := 8
const STEPS := 7               # landing chimes / coin plinks: this many steps up the scale
const BEAT := 0.75             # music: seconds per beat, 8 beats per loop (6 s)
const NAMES := ["landing", "coin", "go_around", "alarm", "fine", "wind", "last_arrivals", "clear_sky", "tick", "tap", "press", "star", "slam", "back", "toggle", "buy", "error", "whoosh", "unlock", "chirp"]
const FILES := ["chirp", "fine", "alarm", "go_around", "wind", "last_arrivals", "clear_sky", "tick", "tap", "press", "back", "toggle", "error", "whoosh", "buy", "star", "unlock", "slam"]
const LAYERS := ["calm", "hot", "tense", "fog", "hum"]

var enabled := true
var plays := {}                # sound name -> how many times it was triggered
var hum_level := PackedFloat32Array()    # per aircraft type: current engine level 0..1 (the shared bed follows their sum)
var music_level := 0.0         # the intense layer's volume 0..1
var music_pitch := 1.0         # (always 1: shifting the music would take it out of key)
var fog_level := 0.0           # 0..1: the fog ambience and the tense music layer follow it
var held := false              # audio is held (the page went to the background): the Master bus is muted
var web_loops := false         # the page plays the loops (web build)
var unlocked := false          # the first user gesture has happened (browsers keep audio suspended until then)

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _hum: AudioStreamPlayer
var _hum_target := PackedFloat32Array()
var _music_calm: AudioStreamPlayer
var _music_hot: AudioStreamPlayer
var _music_tense: AudioStreamPlayer
var _fog_amb: AudioStreamPlayer
var _players := {}             # layer name -> its looping player (not on the web)
var _layer_db := {"calm": -80.0, "hot": -80.0, "tense": -80.0, "fog": -80.0, "hum": -80.0}
var _js_sent := {}             # layer -> the level last sent to the page
var _music_on := false
var _menu_on := false
var _calm_db := -80.0          # what the music layers are at now; the targets come from the mode (a smooth crossfade)
var _hot_db := -80.0
var _calm_target := -80.0
var _hot_target := -80.0
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
		_fog_amb = _loop_player("fog", "SFX")
		_hum = _loop_player("hum", "SFX")

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
	for k in POOL:     # a free player first: taking over one that is still sounding would cut it off with a click
		var q := _pool[(_next + k) % POOL]
		if not q.playing:
			p = q
			_next = (_next + k) % POOL
			break
	_next = (_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	p.volume_db = _rng.randf_range(-0.5, 0.3)
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

## Aircraft per type currently on the field (index = Aircraft.Type): the shared engine bed follows them.
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
	var total := 0.0
	for t in 6:
		hum_level[t] = move_toward(hum_level[t], _hum_target[t], delta * 1.5)
		total += hum_level[t]
	if total > 0.005:
		_start_layers(["hum"])
		_set_layer("hum", linear_to_db(minf(total * 0.7, 1.0)) - 9.0)
	else:
		_set_layer("hum", -80.0)
		_stop_layers(["hum"])
	if web_loops:
		_push_levels()

# ---------- The looping layers ----------

func _start_layers(names: Array) -> void:
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

## The bus a layer sits on: Music for the music, SFX for the rest (their volume sliders and mutes apply).
func _bus_db(layer: String) -> float:
	var idx := AudioServer.get_bus_index("Music" if layer == "calm" or layer == "hot" or layer == "tense" else "SFX")
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
