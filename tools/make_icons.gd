extends SceneTree
## Renders the app icon (icon.svg) to the PNG sizes the web / PWA export wants, and the boot splash (assets/splash.svg).
##   godot --headless --path . --script tools/make_icons.gd

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://icons")
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for px in [144, 180, 512]:
		var img := Image.new()
		img.load_svg_from_string(svg, float(px) / 512.0)
		img.save_png("res://icons/icon-%d.png" % px)
		print("icon ", px, " ", img.get_size())
	var sp := Image.new()
	sp.load_svg_from_string(FileAccess.get_file_as_string("res://assets/splash.svg"), 1.0)
	sp.save_png("res://assets/splash.png")
	print("splash ", sp.get_size())
	quit()
