extends SceneTree
## Which statements of an airport's build are slow? Builds all six airports (as the background build does, with the clock checked between
## statements) and prints the slowest ones. The background build can only be as smooth as its biggest statement.
##   godot --headless --path . --script tools/build_profile.gd [-- top=30]

func _initialize() -> void:
	var save = root.get_node("Save")
	save.path = "user://build_profile_save.json"
	save.reset_all()
	# a copy of the build code in which every `await _slice()` knows its own line
	var lines := FileAccess.get_file_as_string("res://scripts/Airfield.gd").split("\n")
	var copy := PackedStringArray()
	for k in lines.size():
		copy.append(lines[k].replace("await _slice()", "await _slice(%d)" % (k + 1)))
	var f := FileAccess.open("res://tools/_airfield_profiled.gd", FileAccess.WRITE)
	f.store_string("\n".join(copy).replace("class_name Airfield\n", ""))
	f.close()
	var script = load("res://tools/_airfield_profiled.gd")
	script.boot_lazy = false
	var af = script.new()
	af.slice_trace = true
	root.add_child(af)
	await process_frame
	await process_frame
	var top := 30
	for a in OS.get_cmdline_user_args():
		if a.begins_with("top="):
			top = int(a.substr(4))
	print("variants built: ", af.variants.map(func(x): return x != null), " trace ", af.slice_trace)
	var all: Array = af.slice_log.duplicate()
	all.sort_custom(func(x, y): return x[0] > y[0])
	var total := 0
	for e in all:
		total += e[0]
	print("%d statements, %.0f ms in all" % [all.size(), total / 1000.0])
	for k in mini(top, all.size()):
		var ln: int = all[k][1]
		print("%7.2f ms  before line %d: %s" % [all[k][0] / 1000.0, ln, lines[ln - 2].strip_edges() if ln > 1 else ""])
	DirAccess.remove_absolute("res://tools/_airfield_profiled.gd")
	quit()
