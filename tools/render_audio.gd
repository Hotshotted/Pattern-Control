extends SceneTree
## Renders every sound of the game to 44.1 kHz, 16-bit, mono WAV files, so phones never synthesise at load:
##   godot --headless --path . --script tools/render_audio.gd
## One-shots go to assets/audio/<name>.wav, loops (music layers, fog, the shared engine bed) to assets/audio/loops/<name>.wav.
## The synthesis lives in scripts/SfxSynth.gd; the smoke test re-renders it and checks the committed files are current.

const RATE := 44100

static func wav_bytes(samples: PackedFloat32Array, rate: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var b := PackedByteArray()
	b.append_array("RIFF".to_ascii_buffer())
	var tmp := PackedByteArray()
	tmp.resize(4)
	tmp.encode_u32(0, 36 + data.size())
	b.append_array(tmp)
	b.append_array("WAVEfmt ".to_ascii_buffer())
	tmp.encode_u32(0, 16)
	b.append_array(tmp)
	var h := PackedByteArray()
	h.resize(16)
	h.encode_u16(0, 1)            # PCM
	h.encode_u16(2, 1)            # mono
	h.encode_u32(4, rate)
	h.encode_u32(8, rate * 2)
	h.encode_u16(12, 2)
	h.encode_u16(14, 16)
	b.append_array(h)
	b.append_array("data".to_ascii_buffer())
	tmp.encode_u32(0, data.size())
	b.append_array(tmp)
	b.append_array(data)
	return b

func _initialize() -> void:
	var synth := SfxSynth.new()
	synth.rate = RATE
	DirAccess.make_dir_recursive_absolute("res://assets/audio/loops")
	var t0 := Time.get_ticks_msec()
	var total := 0
	var clips := synth.clips()
	for k in clips.keys():
		var b := wav_bytes(clips[k], RATE)
		var f := FileAccess.open("res://assets/audio/%s.wav" % k, FileAccess.WRITE)
		f.store_buffer(b)
		f.close()
		total += b.size()
	var loops := synth.loops()
	for k in loops.keys():
		var b2 := wav_bytes(loops[k], RATE)
		var f2 := FileAccess.open("res://assets/audio/loops/%s.wav" % k, FileAccess.WRITE)
		f2.store_buffer(b2)
		f2.close()
		total += b2.size()
	print("rendered %d clips and %d loops, %.2f MB, in %d ms" % [clips.size(), loops.size(), total / 1048576.0, Time.get_ticks_msec() - t0])
	quit()
