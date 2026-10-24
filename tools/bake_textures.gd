extends SceneTree
## Bakes the small textures (the shadow shapes, the particle dots, the sparkle and the faint grass noise) to assets/textures/*.png, so the game
## loads them instead of computing them at start-up (a few thousand set_pixel calls cost seconds on a phone).
## Run after changing a formula in Shadow.gd / Fx.gd, then commit the PNGs:
##   godot --headless --path . --script tools/bake_textures.gd
## (The smoke test checks the PNGs still match the formulas.)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/textures")
	var shadow = load("res://scripts/Shadow.gd")
	var fx = load("res://scripts/Fx.gd")
	var images: Dictionary = {}
	for shape in shadow.baked_images():
		images["shadow_" + shape] = shadow.baked_images()[shape]
	images["dot_soft"] = fx.dot_image(true)
	images["dot_hard"] = fx.dot_image(false)
	images["star"] = fx.star_image()
	images["grass"] = load("res://scripts/Airfield.gd").grass_image()
	for name in images:
		var path := "res://assets/textures/%s.png" % name
		(images[name] as Image).save_png(path)
		print("baked ", path)
	quit()
