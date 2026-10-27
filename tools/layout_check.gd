extends SceneTree
## Prints what is wrong with each airport's layout (the same checks as the smoke test's layout section), natively and fast:
##   godot --headless --path . --script tools/layout_check.gd

func _initialize() -> void:
	for a in Airports.COUNT:
		Airports.current = a
		var n := Taxi.net()
		var errs := PackedStringArray(Layout.problems(a))
		print("%-16s nodes %2d edges %2d exits %2d  %s" % [Airports.airport_name(a), n["nodes"].size(), n["edges"].size(), n["exits"].size(), "OK" if errs.is_empty() else ""])
		for e in errs:
			print("    ", e)
	quit()
