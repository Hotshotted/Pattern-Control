class_name Airfield
extends Node3D
## The static scenery of every airport. Each is built ONCE (hidden) and select() just switches which one is shown, so starting
## a shift creates nothing. The real game builds only the airport it opens on before the menu appears, and the others a phase at a
## time while the menu is idle (the unlocked ones first; `select` builds one that is still missing); `boot_lazy = false` (the tests)
## builds all six up front. An airport has: ground, water /
## island decor, runways (each in its colour, with a threshold block at BOTH approach ends: bright when that
## end is active in the current wind, dull when not), helipads, seaplane lanes, mountains, a control tower,
## a windsock that swings with the wind, and trees. A landing makes that end flash (glow()).

## The palette of each look: the countryside (the default), the coast and the Alps: hangar and FBO roofs, walls and the apron.
const PALETTE := {
	"countryside": {"hangar": Color("e2654a"), "fbo": Color("4fb8b2"), "wall": Color("e8e1d2"), "wall2": Color("efe6d3"), "apron": Color("b6bbc2")},
	"coastal": {"hangar": Color("3f8fc2"), "fbo": Color("eaa64a"), "wall": Color("f7f4ea"), "wall2": Color("fbf8ee"), "apron": Color("d2cab6")},
	"alpine": {"hangar": Color("6b4a3a"), "fbo": Color("9a3b2e"), "wall": Color("b98757"), "wall2": Color("c7955f"), "apron": Color("9aa0a8")},
}

## One airport's nodes and the little state it animates.
class AirportScene:
	var root: Node3D
	var airport := 0                    # which airport this is
	var phase := 0                      # build phases done (BUILD_PHASES = finished)
	var occupied: Array = []            # [centre, radius] of what is built on the field (kept clear of upgrade props, tufts, ...)
	var thr_mats: Array[StandardMaterial3D] = []   # runway * 2 + end
	var thr_colors: Array[Color] = []
	var glow_born: Array[int] = []
	var active: Array[bool] = []
	var sock: Node3D
	var ups: Array = []                 # [node, upgrade id, level it appears at]
	var dishes: Array[Node3D] = []      # radar dishes (they turn)
	var mast_lights: Array[StandardMaterial3D] = []   # comms mast beacons (they blink)
	var water := false
	var base_ground := Color.WHITE
	var ground_mat: StandardMaterial3D
	var stripe_mat: StandardMaterial3D
	var tufts: MultiMeshInstance3D
	var tuft_base: Array[Transform3D] = []   # the tufts upright (they lean downwind from this)
	var pond: Dictionary = {}               # {center, r, ripples: [{node, mat, t, off}]}
	var ground_now := Color.WHITE           # the ground's colour before the time of day warms it
	var style := "countryside"
	var lamps: Array = []                   # the lighthouse lamp (it pulses)
	var smoke: Array = []                   # the lodge chimney's puffs: [{node, mat, t}]
	var smoke_at := Vector3.ZERO
	var chairs: Array = []                  # the chairlift's chairs
	var chair_a := Vector2.ZERO
	var chair_b := Vector2.ZERO
	var beacons: Array = []                 # the tower's red beacon (it blinks)
	var apron_c := Vector2.ZERO
	var docks_at: Array[Vector2] = []        # where seaplanes tie up (the pier)
	var ramp_ok := false                    # this airport has a ramp (hangar, tie-downs, ...)
	var slots := {}                         # slot kind -> Array of {node, chocks, pos, yaw, goals, tail, heli}
	var hangar_goals: Array[Vector2] = []
	var hangar_tail := PackedVector2Array()
	var extra_goals: Array[Vector2] = []
	var extra_tail := PackedVector2Array()
	var hangar_label: Label3D
	var extra_tag: Label3D
	var routes := {}                        # a taxi route is fixed per airport: "kind:i:e|slot:idx" -> its points
	var apron_s := 1.0
	var scenery: Array[Vector2] = []        # where the big pieces of scenery stand (the tests check they are clear of the paths' strips)
	var truck: Node3D                       # the fuel truck and its route (it drives from the fuel farm to a parked plane and back)
	var truck_pts := PackedVector2Array()
	var birds: Array = []                   # [{node, shadow, pos, vel, scatter}]
	var balloon: Dictionary = {}            # {node, shadow, x, z}
	var mower: Node3D
	var mower_rows: Array = []              # the translucent stripes it leaves (pooled boxes, revealed over the shift)
	var mower_span := Vector2.ZERO          # x range it works along, and
	var mower_z0 := 0.0                     # the z of its first row
	var leaf_mat: StandardMaterial3D
	var leaf_mid: StandardMaterial3D        # the lighter crown layers (the highlight)
	var leaf_hi: StandardMaterial3D
	var patch_mat: StandardMaterial3D        # the darker mown patches
	var trunk_mat: StandardMaterial3D
	var tree_styles: Array = [[], [], []]   # per tree style: the holders to show
	var strips: Array = []              # taxiway strips [from, to] (world x, z): ground vehicles drive along them
	var veh: Array[Node3D] = []         # ground vehicles
	var veh_strip := PackedInt32Array()
	var veh_t := PackedFloat32Array()   # 0..2 along the strip and back
	var veh_speed := PackedFloat32Array()
	var veh_beacon: Array[StandardMaterial3D] = []
	var lights: MultiMeshInstance3D

var _occupied: Array = []                 # [centre, radius] of what is built on the field (kept clear of upgrade props, tufts, ...)
var wind: Wind                        # set by Main
var traffic: Traffic                  # set by Main (the birds keep away from aircraft)
var progress := -1.0                  # 0..1 through the shift (the mower works the field edge); -1 = the menu: a slow loop
var _life_t := 0.0
var variants: Array[AirportScene] = []     # indexed by airport; null until built
var _pending := {}                        # airport -> its scene, part-built
var _theme := 0
const BUILD_PHASES := 7
static var boot_lazy := true
var cur: AirportScene
var selected := 0
var _sock_deg := 0.0
# Wind you can always see: thin cream streaks drift across the field the way the air is going, the grass leans, the trees sway, the pond ripples.
const STREAKS := 12
const SWING_SECONDS := 1.2
var _st_mm: MultiMesh
var _st_node: MultiMeshInstance3D
var _st_mat: StandardMaterial3D
var _st_pos := PackedVector2Array()
var _st_len := PackedFloat32Array()
var _st_age := PackedFloat32Array()
var _st_ttl := PackedFloat32Array()
var _st_alpha := PackedFloat32Array()      # what each streak's opacity was set to (the tests read it back)
var _st_rng := RandomNumberGenerator.new()
var _wd := -1.0                           # the direction the air is drifting now (degrees, toward): it swings to the wind's
var _last_from := -1.0
var _gust_t := 0.0                        # seconds left of the shift's gust (brighter streaks, harder sway)
var _sway_t := 0.0
var _day := 0.0                           # how far through the shift the light is (0..1): warmer grass, longer shadows

## Time of day: the grass gets a touch warmer and every shadow a little longer as the shift goes on.
func set_time(t: float) -> void:
	_day = clampf(t, 0.0, 1.0)
	Shadow.set_time(_day)
	for v in variants:
		if v != null:
			v.ground_mat.albedo_color = _warmed(v.ground_now, _day)

static func _warmed(c: Color, t: float) -> Color:
	return Color(c.r, c.g * (1.0 - 0.02 * t), c.b * (1.0 - 0.09 * t), c.a)

# The ramp: where landed aircraft taxi to and park (see Ramp.gd). The taxiing ones are scenery: no collisions, drawn under everything.
const TAXI_SPEED := 1.05                  # units / second
const TAXI_FAST := 9.0                    # (times that) for an older one that has to hurry up
const TAXI_MAX := 4                       # at most this many taxi at their own pace
const HELI_SIT := 3.0                     # a helicopter sits on the pad this long, then air-taxis away
const PARK_SCALE := 0.42                  # a parked aircraft is this x the ramp's scale (the taxiing one shrinks to it)
const LAND_SCALE := 0.9                   # ...from this, the size it had on the runway
var ramp := Ramp.new()
var taxis: Array = []                     # the aircraft taxiing now: {node, chocks, route, len, d, wait, ff, slot, hdg, spare}
var ramp_active := false
var hangar_shown := 0                     # how many have rolled into the hangar / been added to the "+N" so far (the taxi has to arrive)
var extra_shown := 0

func _ready() -> void:
	Boot.mark("engine up, scene loaded")
	variants.resize(Airports.COUNT)
	var keep := Airports.current
	if boot_lazy:
		keep = Save.selected_airport if Save.airport_open(Save.selected_airport) else 0
		ensure(keep)
		Boot.mark("airfield %d built" % keep)
	else:
		for a in Airports.COUNT:
			ensure(a)
			Boot.mark("airfield %d built" % a)
	_build_streaks()
	select(keep)
	Boot.mark("airfield ready")

## Show airport `a` (building it first if it is still missing).
func select(a: int) -> void:
	ensure(a)
	selected = a
	for i in variants.size():
		if variants[i] != null:
			variants[i].root.visible = i == a
	cur = variants[a]

## Build airport `a` now, whatever is left of it.
func ensure(a: int) -> void:
	if variants[a] != null:
		return
	var v: AirportScene = _pending.get(a)
	if v == null:
		v = _begin_airport(a)
		_pending[a] = v
	while not _build_phase(v):
		pass

func build_all() -> void:
	for a in Airports.COUNT:
		ensure(a)

## The next airport worth building in the idle time: the one shown, then the unlocked ones (-1 when those are all there).
func _next_wanted(include_locked: bool) -> int:
	if variants[selected] == null:
		return selected
	for a in Airports.COUNT:
		if variants[a] == null and (include_locked or Save.airport_open(a)):
			return a
	return -1

## One phase of the next wanted airport (the menu's idle time calls this every few frames). Returns false when nothing is left to build.
func build_step(include_locked: bool = false) -> bool:
	var a := _next_wanted(include_locked)
	if a < 0:
		return false
	var v: AirportScene = _pending.get(a)
	if v == null:
		v = _begin_airport(a)
		_pending[a] = v
	_build_phase(v)
	return _next_wanted(include_locked) >= 0

func is_built(a: int) -> bool:
	return variants[a] != null

func _begin_airport(a: int) -> AirportScene:
	var v := AirportScene.new()
	v.airport = a
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	v.root = root
	return v

## One phase of an airport's build (0..BUILD_PHASES-1). Returns true when the airport is finished (and then it joins `variants`).
func _build_phase(v: AirportScene) -> bool:
	var keep_current := Airports.current
	var keep_outlines := Prim.outlines
	Airports.current = v.airport
	Prim.outlines = false        # Sunny Airfield: the ground and its props have soft shadows and highlights, never outlines
	_occupied = v.occupied
	var root := v.root
	match v.phase:
		0:
			var ground := Airports.ground_color()
			v.base_ground = ground
			v.ground_now = ground
			v.ground_mat = Prim.mat(ground)
			_ground(root, v.ground_mat, bool(Airports.def().get("water", false)))
			var stripe := _overlay_mat(Color(1, 1, 1, 0.12))        # lighter and darker patches are translucent, so they follow the field's own light
			v.stripe_mat = stripe
			var patch := _overlay_mat(Color(0, 0, 0, 0.07))
			v.patch_mat = patch
			var water: bool = Airports.def().get("water", false)
			v.water = water
			if not water:
				# Mown patches in slightly different greens: long diagonal bands, light and dark, the same on every visit.
				var rngp := RandomNumberGenerator.new()
				rngp.seed = 31 + Airports.current * 17
				for i in 9:
					var bandp := Prim.box(root, Vector3(rngp.randf_range(7.0, 15.0), 0.02, rngp.randf_range(1.6, 3.4)), Vector3(rngp.randf_range(-6.0, 6.0), 0.005 + 0.001 * i, rngp.randf_range(-9.0, 9.0)), stripe if i % 2 == 0 else patch, false)
					bandp.rotation.y = deg_to_rad(rngp.randf_range(-24.0, 24.0))
			else:
				var wave := _overlay_mat(Color(1, 1, 1, 0.16))
				v.stripe_mat = wave
				for i in 5:
					Prim.box(root, Vector3(9.0 + 2.0 * (i % 3), 0.02, 0.5), Vector3(-5.0 + 2.5 * i, 0.005, -8.0 + 4.1 * i), wave, false)
			for d in Airports.decor():
				var m := Prim.mat(d["color"])
				if d["shape"] == "disc":
					Prim.cyl(root, d["r"], d["r"], 0.06, d["sides"], Vector3(d["pos"].x, d["y"], d["pos"].y), m, false)
				else:
					Prim.box(root, Vector3(d["size"].x, 0.04, d["size"].y), Vector3(d["pos"].x, d["y"], d["pos"].y), m, false)
		1:
			for i in Airports.rw_count():
				_runway(v, i)
			for pad in Airports.pads():
				_pad(root, pad)
			for lane in Airports.lanes():
				_lane(root, lane)
			for h in Airports.hazards():
				_mountain(root, h["center"], h["radius"])
		2:
			_taxiways(v)
			_lights(v)
			_vehicles(v)
		3:
			v.occupied = []
			_occupied = v.occupied
			v.style = Airports.style()
			_ramp(v)
			_landmark(v)
			_ramp_slots(v)
		4:
			_life(v)
			var sp := Airports.windsock_pos()
			_windsock(v, Vector3(sp.x, 0.0, sp.y))
		5:
			if not v.water:
				_trees(v)
				_tufts(v)
		6:
			_upgrade_props(v)
	v.phase += 1
	Airports.current = keep_current
	Prim.outlines = keep_outlines
	if v.phase < BUILD_PHASES:
		return false
	_pending.erase(v.airport)
	variants[v.airport] = v
	v.root.visible = v.airport == selected and cur != null
	_dress(v)
	return true

## A scene that has just been finished takes the look the others already have: the equipped theme, the bought upgrades, the time of day.
func _dress(v: AirportScene) -> void:
	_apply_theme_to(v, Cosmetics.THEMES[_theme])
	for u in v.ups:
		u[0].visible = Save.upgrade_level(u[1]) >= u[2]

## A very faint static texture on the grass, and only on the grass (the ground mesh: runways, taxiways, aprons, buildings and water are
## separate meshes with none): a tileable blotchy noise that darkens the colour by 0-3%, baked to assets/textures/grass.png (see
## tools/bake_textures.gd). It does not move, and there is no overlay or grain on the screen.
const GRASS_TILE := 4.0               # world units one repeat of the texture covers
const GRASS_SIZE := 128
const GRASS_STRENGTH := 0.025

static var _grass: Texture2D

static func grass_texture() -> Texture2D:
	if _grass == null:
		_grass = load("res://assets/textures/grass.png") if ResourceLoader.exists("res://assets/textures/grass.png") else ImageTexture.create_from_image(grass_image())
	return _grass

## The noise: three octaves of smooth value noise on a torus (it tiles), scaled to white at its lightest and (1 - 3%) grey at its darkest.
static func grass_image() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var img := Image.create(GRASS_SIZE, GRASS_SIZE, false, Image.FORMAT_RGBA8)
	var grids: Array = []
	for cells in [6, 12, 24]:
		var g := PackedFloat32Array()
		g.resize(cells * cells)
		for i in g.size():
			g[i] = rng.randf()
		grids.append([cells, g])
	var weights := [0.5, 0.33, 0.17]
	for y in GRASS_SIZE:
		for x in GRASS_SIZE:
			var n := 0.0
			for k in 3:
				var cells: int = grids[k][0]
				var g: PackedFloat32Array = grids[k][1]
				var fx := float(x) / GRASS_SIZE * cells
				var fy := float(y) / GRASS_SIZE * cells
				var x0 := int(floor(fx))
				var y0 := int(floor(fy))
				var tx := smoothstep(0.0, 1.0, fx - x0)
				var ty := smoothstep(0.0, 1.0, fy - y0)
				var a := lerpf(g[(y0 % cells) * cells + (x0 % cells)], g[(y0 % cells) * cells + ((x0 + 1) % cells)], tx)
				var b := lerpf(g[((y0 + 1) % cells) * cells + (x0 % cells)], g[((y0 + 1) % cells) * cells + ((x0 + 1) % cells)], tx)
				n += lerpf(a, b, ty) * weights[k]
			var v := 1.0 - GRASS_STRENGTH * clampf((n - 0.2) / 0.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return img

## The field: a grid with vertex colours that run from the lit upper-left (#B9DC72) through #8FC45C to the shaded lower-right (#76AA4B),
## as ratios of the material's own colour (so a theme or an airport's own ground keeps the same light). Water gets a gentler version.
func _ground(root: Node3D, m: Material, water: bool) -> void:
	var tex: Texture2D = null
	if not water:
		tex = grass_texture()
		(m as StandardMaterial3D).albedo_texture = tex
	var cols_n := 10
	var rows_n := 14
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var mid := Color(0.774, 0.891, 0.807)
	var low := Color(0.639, 0.773, 0.658)
	for j in rows_n + 1:
		for i in cols_n + 1:
			var x := -20.0 + 40.0 * i / cols_n
			var z := -35.0 + 70.0 * j / rows_n
			verts.append(Vector3(x, 0.0, z))
			norms.append(Vector3.UP)
			uvs.append(Vector2(x, z) / GRASS_TILE)
			var t := ((x + 20.0) / 40.0 + (z + 35.0) / 70.0) * 0.5
			var c := Color.WHITE.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(low, (t - 0.5) * 2.0)
			cols.append(Color.WHITE.lerp(c, 0.4) if water else c)
	for j in rows_n:
		for i in cols_n:
			var a := j * (cols_n + 1) + i
			var b := a + 1
			var c2 := a + cols_n + 1
			var d := c2 + 1
			idx.append_array([a, b, c2, b, d, c2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

## A flat translucent colour (the mown patches and the waves).
func _overlay_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

## Is `p` clear of the strips where paths get drawn: the approach corridors beyond every runway end, the runways themselves and the
## water lanes? Everything that is scenery (tufts, parked planes, cars, the picnic...) keeps to such places.
func _clear_of_paths(p: Vector2, margin: float = 0.4, pads: bool = true) -> bool:
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		var dir := Vector2(sin(h), -cos(h))
		var rel := p - Airports.rw_center(i)
		var along := rel.dot(dir)
		var lateral := absf(rel.dot(Vector2(-dir.y, dir.x)))
		var half := Airports.rw_length(i) * 0.5
		if lateral < Airports.rw_width(i) * 0.5 + 1.0 + margin and absf(along) < half + 6.5:
			return false
	for lane in Airports.lanes():
		var lh := deg_to_rad(lane["heading"])
		var ld := Vector2(sin(lh), -cos(lh))
		var lrel: Vector2 = p - (lane["center"] as Vector2)
		if absf(lrel.dot(Vector2(-ld.y, ld.x))) < lane["width"] * 0.5 + 1.2 and absf(lrel.dot(ld)) < lane["length"] * 0.5 + 1.2:
			return false
	if pads:
		for pad in Airports.pads():
			if p.distance_to(pad["center"]) < pad["radius"] + 1.4:
				return false
	return true

## Is `p` (with `r` to spare) inside something the player's eye follows: a runway and its lights, the approach funnel drawn behind each
## runway end (it widens from the threshold to 3.4 behind it), a water lane's or a helipad's approach? Nothing built, planted or parked goes there.
static func in_strip(p: Vector2, r: float = 0.0, pads: bool = true, hud: bool = true) -> bool:
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		var dir := Vector2(sin(h), -cos(h))
		var rel := p - Airports.rw_center(i)
		var along := absf(rel.dot(dir))
		var lat := absf(rel.dot(Vector2(-dir.y, dir.x)))
		var half := Airports.rw_length(i) * 0.5
		var w: float = Airports.rw_width(i)
		if along < half + r and lat < w * 0.5 + 0.55 + r:
			return true
		if along >= half and along < half + 3.6 + r and lat < w * 0.5 + 0.65 + 1.4 * minf(along - half, 3.4) / 3.4 + r:
			return true
	for lane in Airports.lanes():
		var lh := deg_to_rad(lane["heading"])
		var ld := Vector2(sin(lh), -cos(lh))
		var lrel: Vector2 = p - (lane["center"] as Vector2)
		if absf(lrel.dot(Vector2(-ld.y, ld.x))) < lane["width"] * 0.5 + 1.0 + r and absf(lrel.dot(ld)) < lane["length"] * 0.5 + 1.0 + r:
			return true
	if pads:
		for pad in Airports.pads():
			if p.distance_to(pad["center"]) < pad["radius"] + 0.9 + r:
				return true
	return hud and in_hud(p, r)

## The interface's footprint on the field: pause, the timer / coins pill with the star bar, the wind card and the wind-shift banner,
## each with a 12 px margin, as world rectangles (the 1080 x 1920 layout at the closest view, `Tuning.ortho_size`, so a radar upgrade
## only makes it smaller). Nothing the player must see or aim at (a lane's ends, an approach funnel, a spawn point) goes under it.
const HUD_MARGIN_PX := 12.0
const HUD_RECTS_PX := [
	Rect2(20.0, 10.0, 80.0, 80.0),          # pause
	Rect2(255.0, 0.0, 570.0, 245.0),        # the timer / coins pill and the star bar
	Rect2(924.0, 20.0, 132.0, 150.0),       # the wind card
	Rect2(100.0, 262.0, 880.0, 90.0),       # the wind-shift banner (the widest it gets), just under the star bar
]

static func hud_world_rects(extra_px: float = 0.0) -> Array[Rect2]:
	var k := Tuning.ortho_size / 1080.0
	var kz := k / cos(deg_to_rad(Tuning.camera_tilt_deg))
	var out: Array[Rect2] = []
	for r in HUD_RECTS_PX:
		var g: Rect2 = (r as Rect2).grow(HUD_MARGIN_PX + extra_px)
		out.append(Rect2((g.position.x - 540.0) * k, (g.position.y - 960.0) * kz, g.size.x * k, g.size.y * kz))
	return out

## How far behind a threshold its approach funnel may be drawn (up to 3.4): it stops where the next step would put its centre or either
## side line under the interface. (The overlay draws exactly this, and the tests check it.)
static func funnel_length(thr: Vector2, dir: Vector2) -> float:
	var side := Vector2(-dir.y, dir.x)
	var d := 0.0
	while d < 3.4:
		var nd := minf(d + 0.1, 3.4)
		var lat := 0.35 + 1.4 * nd / 3.4
		for sg in [-1.0, 0.0, 1.0]:
			if in_hud(thr - dir * nd + side * lat * sg):
				return d
		d = nd
	return 3.4

## Is `p` (with `r` world units to spare) under the interface?
static func in_hud(p: Vector2, r: float = 0.0) -> bool:
	for rc in hud_world_rects():
		if rc.grow(r).has_point(p):
			return true
	return false

## Is the whole rectangle clear of those strips (checked on a grid)?
static func rect_out_of_strips(rc: Rect2, r: float = 0.0) -> bool:
	var y := rc.position.y
	while y <= rc.end.y + 0.001:
		var x := rc.position.x
		while x <= rc.end.x + 0.001:
			if in_strip(Vector2(x, y), r):
				return false
			x += 0.25
		y += 0.25
	return true

## Small three-blade grass tufts scattered sparsely over the grass (one MultiMesh per airport; nothing moves).
func _tufts(v: AirportScene) -> void:
	var blade := ArrayMesh.new()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for k in 3:
		var a := k * TAU / 3.0 + 0.5
		var d := Vector3(cos(a), 0.0, sin(a))
		var s := Vector3(-d.z, 0.0, d.x)
		verts.append_array([s * 0.025, -s * 0.025, d * 0.15 + Vector3(0, 0.06, 0)])
		cols.append_array([Color(0.78, 0.78, 0.78), Color(0.78, 0.78, 0.78), Color(1, 1, 1)])
		norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := Prim.mat(Color("7ab351"))
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + Airports.current * 13
	var spots: Array[Transform3D] = []
	var tries := 0
	while spots.size() < 46 and tries < 500:
		tries += 1
		var p := Vector2(rng.randf_range(-4.8, 4.8), rng.randf_range(-8.6, 8.6))
		if not _spot_free(p, 0.35, 9.0) or not _clear_of_paths(p) or in_strip(p, 0.1):
			continue
		var tr := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.1)), Vector3(p.x, 0.012, p.y))
		spots.append(tr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	mm.instance_count = spots.size()
	for k in spots.size():
		mm.set_instance_transform(k, spots[k])
	v.tuft_base = spots
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.root.add_child(mi)
	v.tufts = mi

## Trees at a few fixed spots, each in three styles (round, pine, cactus): the theme picks which one shows.
func _trees(v: AirportScene) -> void:
	v.leaf_mat = Prim.mat(Color("3f7d3f"))
	v.leaf_mid = Prim.mat(v.leaf_mat.albedo_color.lightened(0.18))
	v.leaf_hi = Prim.mat(v.leaf_mat.albedo_color.lightened(0.38))
	v.trunk_mat = Prim.mat(Color(0.45, 0.3, 0.18))
	for t in [Vector2(-4.4, 6.4), Vector2(-3.6, 7.6), Vector2(4.3, 6.9), Vector2(4.5, -6.5), Vector2(-4.4, -6.9), Vector2(3.7, -7.8), Vector2(-4.2, -3.9), Vector2(4.5, 4.4)]:
		var blocked := in_strip(t, 0.45)
		for st in v.strips:
			var sa: Vector2 = st[0]
			var sab: Vector2 = (st[1] as Vector2) - sa
			var su := clampf((t - sa).dot(sab) / maxf(sab.length_squared(), 0.0001), 0.0, 1.0)
			if t.distance_to(sa + sab * su) < 1.0:
				blocked = true
		for h in Airports.hazards():
			if (h["center"] as Vector2).distance_to(t) < h["radius"] + 0.7:
				blocked = true
		if blocked:
			continue
		var round_t := Node3D.new()         # style 0: a cluster of round crowns, each with a shadow, a lighter middle and a highlight
		round_t.position = Vector3(t.x, 0.0, t.y)
		v.root.add_child(round_t)
		_shadow(round_t, 0.2, 0.18, 0.95, 0.95, 1.0, 0.02)
		_shadow(round_t, 0.5, 0.42, 0.6, 0.6, 0.9, 0.02)
		Prim.cyl(round_t, 0.34, 0.4, 0.55, 10, Vector3(0.0, 0.3, 0.0), v.leaf_mat, false)
		Prim.cyl(round_t, 0.22, 0.28, 0.1, 10, Vector3(-0.04, 0.6, -0.04), v.leaf_mid, false)
		Prim.cyl(round_t, 0.1, 0.12, 0.06, 8, Vector3(-0.09, 0.67, -0.09), v.leaf_hi, false)
		Prim.cyl(round_t, 0.22, 0.26, 0.4, 9, Vector3(0.4, 0.22, 0.32), v.leaf_mat, false)
		Prim.cyl(round_t, 0.12, 0.17, 0.08, 9, Vector3(0.37, 0.43, 0.29), v.leaf_mid, false)
		var pine := Node3D.new()            # style 1: a pine
		pine.position = Vector3(t.x, 0.0, t.y)
		v.root.add_child(pine)
		Prim.cyl(pine, 0.05, 0.05, 0.4, 5, Vector3(0, 0.2, 0), v.trunk_mat)
		Prim.cyl(pine, 0.0, 0.42, 0.9, 6, Vector3(0, 0.85, 0), v.leaf_mat)
		var cactus := Node3D.new()          # style 2: a cactus
		cactus.position = Vector3(t.x, 0.0, t.y)
		v.root.add_child(cactus)
		Prim.cyl(cactus, 0.12, 0.14, 0.8, 6, Vector3(0, 0.4, 0), v.leaf_mat)
		Prim.box(cactus, Vector3(0.3, 0.1, 0.1), Vector3(-0.2, 0.5, 0), v.leaf_mat, false)
		Prim.box(cactus, Vector3(0.1, 0.3, 0.1), Vector3(-0.32, 0.65, 0), v.leaf_mat, false)
		Prim.box(cactus, Vector3(0.3, 0.1, 0.1), Vector3(0.2, 0.38, 0), v.leaf_mat, false)
		Prim.box(cactus, Vector3(0.1, 0.26, 0.1), Vector3(0.32, 0.5, 0), v.leaf_mat, false)
		v.tree_styles[0].append(round_t)
		v.tree_styles[1].append(pine)
		v.tree_styles[2].append(cactus)

## Dress every airport in a theme: ground, scenery style and colours (no new nodes).
func apply_theme(index: int) -> void:
	_theme = index
	var t: Dictionary = Cosmetics.THEMES[index]
	for v in variants:
		if v != null:
			_apply_theme_to(v, t)

func _apply_theme_to(v: AirportScene, t: Dictionary) -> void:
	var ground: Color = v.base_ground
	if t["ground"] != null and not v.water:
		ground = t["ground"]
	elif v.water:
		ground = v.base_ground * (t["tint"] as Color)
	v.ground_now = ground
	v.ground_mat.albedo_color = _warmed(ground, _day)
	if v.leaf_mat != null:
		v.leaf_mat.albedo_color = t["leaf"]
		v.leaf_mid.albedo_color = t.get("leaf_mid", (t["leaf"] as Color).lightened(0.18))
		v.leaf_hi.albedo_color = t.get("leaf_hi", (t["leaf"] as Color).lightened(0.38))
		v.trunk_mat.albedo_color = t["trunk"]
	var want: int = t["style"]
	if v.style == "alpine" and want == 0:
		want = 1         # (the mountains have pines)
	for st in 3:
		for holder in v.tree_styles[st]:
			holder.visible = st == want

func _runway(v: AirportScene, i: int) -> void:
	var col := Airports.rw_color(i)
	var root := Node3D.new()
	root.position = Vector3(Airports.rw_center(i).x, 0.0, Airports.rw_center(i).y)
	root.rotation.y = -deg_to_rad(Airports.rw_heading_deg(i))
	v.root.add_child(root)
	var len := Airports.rw_length(i)
	var w := Airports.rw_width(i)
	Prim.box(root, Vector3(w + 0.16, 0.11, len + 0.16), Vector3(0, 0.055, 0), Prim.mat(Tuning.runway_asphalt.darkened(0.3)), false)       # the darker rim
	Prim.box(root, Vector3(w, 0.12, len), Vector3(0, 0.06, 0), Prim.mat(Tuning.runway_asphalt), false)
	var edge := Prim.mat(col)
	for s in [-1.0, 1.0]:
		Prim.box(root, Vector3(0.08, 0.13, len - 0.1), Vector3(s * (w * 0.5 - 0.1), 0.065, 0), edge, false)
	var white := Prim.mat(Color("f2ede4").lerp(Tuning.runway_asphalt, 0.1))       # cream, 90%
	# End 0 is approached from behind its landing direction (local +z end); end 1 from the other side (-z).
	for e in 2:
		var sign := 1.0 if e == 0 else -1.0
		var thr := Prim.mat(col)
		thr.emission_enabled = true
		thr.emission = col
		thr.emission_energy_multiplier = 0.0
		v.thr_mats.append(thr)
		v.thr_colors.append(col)
		v.glow_born.append(0)
		v.active.append(true)
		Prim.box(root, Vector3(w - 0.3, 0.14, 0.5), Vector3(0, 0.07, sign * (len * 0.5 - 0.35)), thr, false)
		for k in 4:   # piano keys just past the threshold block
			Prim.box(root, Vector3(0.08, 0.14, 0.4), Vector3(-0.27 + k * 0.18, 0.07, sign * (len * 0.5 - 0.9)), white, false)
	for k in 5:
		Prim.box(root, Vector3(0.09, 0.14, 0.36), Vector3(0, 0.07, (k - 2) * 1.0), white, false)
	# Approach chevrons in the runway's colour: three Vs on the grass before each end, pointing at the runway.
	var chev := Prim.mat(col.lerp(v.base_ground, 0.15))
	for e in 2:
		var sg := 1.0 if e == 0 else -1.0
		for k in 3:
			for sd in [-1.0, 1.0]:
				var arm := Prim.box(root, Vector3(0.5, 0.03, 0.09), Vector3(sd * 0.2, 0.02, sg * (len * 0.5 + 0.95 + k * 0.42) + sg * 0.1), chev, false)
				arm.rotation.y = deg_to_rad(sg * sd * 32.0)
	Prim.lift(root)       # runways are drawn above the fog
	# Rubber streaks in the touchdown zones (20% black), and the runway numbers (cream, 80%).
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0, 0, 0, 0.14)
	rubber.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rubber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rubber.render_priority = 3
	var hdg := Airports.rw_heading_deg(i)
	for e in 2:
		var sg := 1.0 if e == 0 else -1.0
		for sd in [-1.0, 1.0]:
			Prim.box(root, Vector3(minf(w * 0.2, 0.22), 0.02, 0.8), Vector3(sd * w * 0.22, 0.125, sg * (len * 0.5 - 2.5)), rubber, false)
		var num := posmod(roundi((hdg + 180.0 * e) / 10.0), 36)
		var lab := Label3D.new()
		lab.text = "%02d" % (36 if num == 0 else num)
		lab.font_size = 96
		lab.pixel_size = 0.0046
		lab.modulate = Color(0.949, 0.929, 0.894, 0.8)
		lab.shaded = false
		lab.double_sided = false
		lab.rotation_degrees = Vector3(-90.0, 0.0 if e == 0 else 180.0, 0.0)
		lab.position = Vector3(0.0, 0.142, sg * (len * 0.5 - 1.55))
		lab.render_priority = 4
		root.add_child(lab)
		var sdx := -1.0 if e == 0 else 1.0       # the PAPI lights stand on the pilot's left, beside the touchdown zone
		Models.papi(root, Vector2(sdx * (w * 0.5 + 0.4), sg * (len * 0.5 - 2.7)), sdx)

## A parallel taxiway beside each runway that has room for one: asphalt strip, yellow centre dashes and two stubs to the
## runway. All of it lies on the ground, under everything that moves.
func _taxiways(v: AirportScene) -> void:
	if v.water:
		return
	var asphalt := Prim.mat(Color("a3a8b0"))
	var yellow := Prim.mat(Color("e6c35a"))
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		var dir := Vector2(sin(h), -cos(h))
		var perp := Vector2(cos(h), sin(h))
		var c := Airports.rw_center(i)
		var len := Airports.rw_length(i)
		var w := Airports.rw_width(i)
		var half := len * 0.34
		for side in [1.0, -1.0]:
			var off: float = w * 0.5 + 0.95
			var a: Vector2 = c + perp * off * side - dir * half
			var b: Vector2 = c + perp * off * side + dir * half
			var free := true
			for f in [0.0, 0.5, 1.0]:
				if not _spot_free(a.lerp(b, f), 0.4, 8.6):
					free = false
			if not free:
				continue
			var n := Node3D.new()
			n.position = Vector3(c.x, 0.0, c.y)
			n.rotation.y = -h
			v.root.add_child(n)
			Prim.box(n, Vector3(0.6, 0.05, half * 2.0), Vector3(side * off, 0.03, 0), asphalt, false)
			var stub := off - w * 0.5
			for z in [-half, half]:
				Prim.box(n, Vector3(stub + 0.3, 0.05, 0.6), Vector3(side * (w * 0.5 + stub * 0.5 - 0.15), 0.032, z), asphalt, false)
			for k in int(half * 2.0 / 0.6):
				Prim.box(n, Vector3(0.05, 0.06, 0.24), Vector3(side * off, 0.05, -half + 0.3 + k * 0.6), yellow, false)
			# Hold-short lines where each stub meets the runway (two solid, two dashed) and a taxiway sign (black letter on yellow).
			var hold := Prim.mat(Color("e6c35a"))
			for z in [-half, half]:
				for k in 2:
					Prim.box(n, Vector3(0.025, 0.012, 0.6), Vector3(side * (w * 0.5 + 0.3 + k * 0.06), 0.063, z), hold, false)
					for q in 4:
						Prim.box(n, Vector3(0.025, 0.012, 0.1), Vector3(side * (w * 0.5 + 0.42 + k * 0.06), 0.063, z - 0.25 + q * 0.17), hold, false)
			var sign_at := Vector3(side * (off + 0.5), 0.0, -half - 0.45)
			Prim.box(n, Vector3(0.05, 0.1, 0.05), sign_at + Vector3(0, 0.05, 0), Prim.mat(Color("9aa0aa")), false)
			Prim.box(n, Vector3(0.2, 0.05, 0.14), sign_at + Vector3(0, 0.12, 0), hold, false)
			var tl := Label3D.new()
			tl.text = char(65 + i)
			tl.font_size = 64
			tl.pixel_size = 0.0036
			tl.modulate = Color(0.08, 0.08, 0.1)
			tl.shaded = false
			tl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			tl.position = sign_at + Vector3(0, 0.15, 0)
			tl.render_priority = 4
			n.add_child(tl)
			v.strips.append([a, b])
			break

## Runway edge lights and the approach strobes: one MultiMesh per airport; the shader makes them shimmer / run.
func _lights(v: AirportScene) -> void:
	var pts: Array = []        # [Vector3 position, phase, strobe]
	for i in Airports.rw_count():
		var h := deg_to_rad(Airports.rw_heading_deg(i))
		var dir := Vector2(sin(h), -cos(h))
		var perp := Vector2(cos(h), sin(h))
		var c := Airports.rw_center(i)
		var len := Airports.rw_length(i)
		var w := Airports.rw_width(i)
		var lz := -len * 0.5 + 0.35
		var k := 0
		while lz < len * 0.5 - 0.2:
			for side in [-1.0, 1.0]:
				var p: Vector2 = c - dir * lz + perp * side * (w * 0.5 + 0.06)
				pts.append([Vector3(p.x, 0.15, p.y), float(k % 7) / 7.0, 0.0])
			lz += 0.8
			k += 1
		for e in 2:
			var sign := 1.0 if e == 0 else -1.0
			for j in 8:
				var p2: Vector2 = c - dir * (sign * (len * 0.5 + 0.55 + j * 0.5))
				pts.append([Vector3(p2.x, 0.04, p2.y), float(7 - j) / 8.0, 1.0])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.04, 0.09)
	mm.mesh = bm
	mm.instance_count = pts.size()
	for k in pts.size():
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, pts[k][0]))
		mm.set_instance_color(k, Color(pts[k][1], pts[k][2], 0.0, 1.0))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/runway_lights.gdshader")
	mat.render_priority = 3
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.root.add_child(mi)
	v.lights = mi

## A couple of ground vehicles driving up and down the first taxiway: a yellow fuel truck with a blue cab, and a white van.
func _vehicles(v: AirportScene) -> void:
	if v.strips.is_empty():
		return
	for k in 2:
		var n := Node3D.new()
		v.root.add_child(n)
		if k == 0:      # the fuel truck: a long yellow tank behind a blue cab
			Prim.box(n, Vector3(0.22, 0.1, 0.36), Vector3(0, 0.1, 0.1), Prim.mat(Color("ffc933")), false)
			Prim.box(n, Vector3(0.2, 0.1, 0.14), Vector3(0, 0.1, -0.16), Prim.mat(Color("3d8bff")), false)
			Prim.box(n, Vector3(0.14, 0.02, 0.3), Vector3(0, 0.16, 0.1), Prim.mat(Color("ffe27a")), false)
		else:
			Prim.box(n, Vector3(0.2, 0.1, 0.34), Vector3(0, 0.1, 0), Prim.mat(Color("f3f7ff")), false)
			Prim.box(n, Vector3(0.18, 0.09, 0.12), Vector3(0, 0.15, -0.1), Prim.mat(Color(0.2, 0.28, 0.38)), false)
		var bm := Prim.mat(Color(1.0, 0.25, 0.2))
		Prim.box(n, Vector3(0.06, 0.05, 0.06), Vector3(0, 0.22, 0.12), bm, false)
		v.veh.append(n)
		v.veh_beacon.append(bm)
		v.veh_strip.append(0)
		v.veh_t.append(0.0 if k == 0 else 1.1)
		v.veh_speed.append(0.07 if k == 0 else 0.05)
	_place_vehicles(v)

func _place_vehicles(v: AirportScene) -> void:
	for k in v.veh.size():
		var st: Array = v.strips[v.veh_strip[k]]
		var a: Vector2 = st[0]
		var b: Vector2 = st[1]
		var t := v.veh_t[k]
		var u := t if t < 1.0 else 2.0 - t
		var p := a.lerp(b, u)
		var d := (b - a) * (1.0 if t < 1.0 else -1.0)
		v.veh[k].position = Vector3(p.x, 0.0, p.y)
		v.veh[k].rotation.y = -atan2(d.x, -d.y)

## A cheap breath of life: vehicles roll along the taxiway, their beacons blink.
func _animate_ground(delta: float, now: int) -> void:
	var on := int(now / 350.0) % 2 == 0
	for k in cur.veh.size():
		cur.veh_t[k] = fposmod(cur.veh_t[k] + cur.veh_speed[k] * delta, 2.0)
		Prim.paint(cur.veh_beacon[k], Color(1.0, 0.25, 0.2) if on else Color(0.3, 0.08, 0.06))
	if not cur.veh.is_empty():
		_place_vehicles(cur)

## A round helipad with an H: a light concrete disc, a ring and an H in the pad's purple.
func _pad(root: Node3D, pad: Dictionary) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var c: Vector2 = pad["center"]
	var r: float = pad["radius"]
	_shadow(holder, c.x + 0.05, c.y + 0.05, r * 2.5, r * 2.5, 0.7, 0.02)
	Prim.cyl(holder, r * 1.06, r * 1.06, 0.1, 16, Vector3(c.x, 0.05, c.y), Prim.mat(Tuning.runway_asphalt.darkened(0.3)), false)
	Prim.cyl(holder, r, r, 0.11, 16, Vector3(c.x, 0.055, c.y), Prim.mat(Color("e9edf4")), false)
	Prim.cyl(holder, r * 0.84, r * 0.84, 0.12, 16, Vector3(c.x, 0.06, c.y), Prim.mat(pad["color"]), false)
	Prim.cyl(holder, r * 0.74, r * 0.74, 0.13, 16, Vector3(c.x, 0.065, c.y), Prim.mat(Color("e9edf4")), false)
	var mark := Prim.mat(pad["color"])
	Prim.box(holder, Vector3(0.1, 0.16, r * 0.9), Vector3(c.x - r * 0.28, 0.07, c.y), mark, false)
	Prim.box(holder, Vector3(0.1, 0.16, r * 0.9), Vector3(c.x + r * 0.28, 0.07, c.y), mark, false)
	Prim.box(holder, Vector3(r * 0.56, 0.16, 0.1), Vector3(c.x, 0.07, c.y), mark, false)
	Prim.lift(holder)       # pads are drawn above the fog

## A strip of water marked out for seaplanes.
func _lane(root: Node3D, lane: Dictionary) -> void:
	var n := Node3D.new()
	n.position = Vector3(lane["center"].x, 0.0, lane["center"].y)
	n.rotation.y = -deg_to_rad(lane["heading"])
	root.add_child(n)
	var len: float = lane["length"]
	var w: float = lane["width"]
	Prim.box(n, Vector3(w, 0.05, len), Vector3(0, 0.05, 0), Prim.mat(Color("62b8e2")), false)
	var edge := Prim.mat(lane["color"])
	for s in [-1.0, 1.0]:
		Prim.box(n, Vector3(0.07, 0.08, len), Vector3(s * w * 0.5, 0.06, 0), edge, false)
		for k in 3:
			Prim.cyl(n, 0.1, 0.1, 0.2, 5, Vector3(s * (w * 0.5 + 0.18), 0.1, (k - 1) * len * 0.42), Prim.mat(Color(1.0, 0.5, 0.15)))
	var white := Prim.mat(Color(0.95, 0.97, 1.0))
	for k in int(len / 1.0) - 1:
		Prim.box(n, Vector3(0.08, 0.08, 0.34), Vector3(0, 0.07, -len * 0.5 + 0.9 + k * 1.0), white, false)
	Prim.lift(n)            # lanes are drawn above the fog

## A low-poly mountain: two peaks with snow caps and a soft shadow. Its radius is the no-fly zone.
func _mountain(root: Node3D, c: Vector2, r: float) -> void:
	var rock := Prim.mat(Color(0.56, 0.54, 0.52))
	var rock2 := Prim.mat(Color(0.66, 0.63, 0.58))
	var snow := Prim.mat(Color(0.97, 0.98, 1.0))
	_shadow(root, c.x + r * 0.27, c.y + r * 0.27, r * 2.7, r * 2.7, 1.0, 0.02)
	Prim.cyl(root, 0.0, r * 0.95, r * 1.5, 7, Vector3(c.x, r * 0.75, c.y), rock, false)
	Prim.cyl(root, 0.0, r * 0.4, r * 0.55, 7, Vector3(c.x, r * 1.25, c.y), snow, false)
	Prim.cyl(root, 0.0, r * 0.6, r * 0.9, 6, Vector3(c.x + r * 0.55, r * 0.45, c.y + r * 0.2), rock2, false)

## A soft round shadow lying on the ground (build time): centre (x, z), size (w, d), `alpha` (1 = the standard 26%), height `y`.
func _shadow(parent: Node3D, x: float, z: float, w: float, d: float, alpha: float, y: float, tex: Texture2D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	mi.mesh = pm
	mi.material_override = Shadow.material(tex if tex != null else Shadow.disc(), alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi

## The shadow of a box-like thing with footprint (fw, fd) at (x, z) and height `h`: cast toward the lower-right, half as long as
## the thing is high, soft-edged.
func _cast(parent: Node3D, x: float, z: float, fw: float, fd: float, h: float, y: float, alpha: float = 1.0) -> void:
	var len := h * 0.5
	var k := 0.7071
	var w := (fw + len * k) / 0.62
	var d := (fd + len * k) / 0.62
	var mi := _shadow(parent, x + len * k * 0.5, z + len * k * 0.5, w, d, alpha, y, Shadow.rect())
	Shadow.register(mi, Vector2(len * k * 0.5, len * k * 0.5))

## The ramp: the apron with the tower, the hangar, the FBO, the picnic and the car park, the tie-downs with their parked planes (one
## being washed), a fenced fuel farm with its truck, the glider on its trailer, and the landmark beyond the fence. Everything keeps
## clear of the approach corridors and the strips where paths are drawn.
func _ramp(v: AirportScene) -> void:
	var root := v.root
	var ap := Airports.apron()
	var tp := Airports.tower_pos()
	var beacons: Array = []
	if ap.is_empty():
		Models.tower(root, tp, beacons)
		v.beacons.append_array(beacons)
		return
	var c: Vector2 = ap["center"]
	var s: float = ap["s"]
	v.apron_c = c
	v.apron_s = s
	v.scenery.append(c)
	_occupied.append([c, 2.1 * s])
	var pal: Dictionary = PALETTE[v.style]
	var slab := Prim.box(root, Vector3(2.8 * s, 0.03, 3.2 * s), Vector3(c.x, 0.0, c.y), Prim.mat(pal["apron"]), false)
	var edge := Prim.box(root, Vector3(2.8 * s + 0.06, 0.028, 3.2 * s + 0.06), Vector3(c.x, -0.002, c.y), Prim.mat(Color("8c9199")), false)
	edge.position.y = -0.002
	Models.tower(root, tp, beacons)
	v.beacons.append_array(beacons)
	Models.hangar(root, c + Vector2(-0.7, -1.0) * s, s, pal["hangar"], pal["wall"])
	Models.fbo(root, c + Vector2(-0.65, 0.1) * s, s, pal["fbo"], pal["wall2"])
	Models.picnic(root, c + Vector2(0.2, 0.25) * s)
	Models.car_lot(root, c + Vector2(1.0, 0.18) * s, s)
	# oil stains on the concrete
	var oil := _overlay_mat(Color(0, 0, 0, 0.16))
	for o in [Vector2(-0.35, 0.82), Vector2(0.95, 1.35)]:
		var st := Prim.cyl(root, 0.1 * s, 0.1 * s, 0.006, 10, Vector3(c.x + o.x * s, 0.02, c.y + o.y * s), oil, false)
		st.scale = Vector3(1.3, 1.0, 0.8)
	# the fuel farm and its truck
	var farm = _find_rect([c + Vector2(0.0, 1.6 * s + 1.3), c + Vector2(-1.4 * s - 1.25, 1.0 * s), c + Vector2(1.4 * s + 1.25, 1.0 * s), c + Vector2(0.0, -1.6 * s - 1.3), c + Vector2(-1.4 * s - 1.25, -1.0 * s)], 1.1, 1.1)
	if farm != null:
		_occupied.append([farm, 0.8])
		v.scenery.append(farm)
		Models.fuel_farm(root, farm, 1.0)
		var truck := Models.fuel_truck(root)
		var home: Vector2 = farm
		var vert: bool = absf(farm.x - c.x) < 0.5
		var dest := Vector2(c.x + 0.33 * s, c.y + 1.18 * s + 0.1 * s) + Vector2(0.0, 0.55 * s)
		var pts := PackedVector2Array()
		if vert:
			var dir_z := -1.0 if farm.y > c.y else 1.0
			pts.append(home + Vector2(0.0, 0.62 * dir_z))
			pts.append(Vector2(home.x, dest.y))
			pts.append(dest)
		else:
			var dir_x := -1.0 if farm.x > c.x else 1.0
			pts.append(home + Vector2(0.62 * dir_x, 0.0))
			pts.append(Vector2(dest.x, home.y))
			pts.append(dest)
		v.truck = truck
		v.truck_pts = pts
	# a glider on its trailer by the hangar
	var gl = _find_rect([c + Vector2(-1.4 * s - 0.35, -0.7 * s), c + Vector2(1.4 * s + 0.35, -0.7 * s), c + Vector2(-1.4 * s - 0.35, 0.9 * s)], 0.6, 1.5)
	if gl != null:
		_occupied.append([gl, 0.7])
		v.scenery.append(gl)
		Models.glider_trailer(root, gl, 8.0)

## The landmark of each look: the countryside has a red barn and a white silo beyond the fence; the coast a lighthouse and a pier with
## gulls; the Alps a timber lodge with chimney smoke, pines and a chairlift with two chairs. All outside the paths' strips.
func _landmark(v: AirportScene) -> void:
	var root := v.root
	match v.style:
		"coastal":
			var lh = _find_rect([Vector2(-3.9, -3.4), Vector2(-3.9, 4.0), Vector2(3.9, 4.2), Vector2(-3.9, 0.4)], 1.0, 1.0)
			if lh != null:
				_occupied.append([lh, 0.8])
				v.scenery.append(lh)
				Models.lighthouse(root, lh, v.lamps)
			var pr = _find_rect([Vector2(4.2, 2.8), Vector2(-4.2, -6.0), Vector2(4.2, -4.8)], 1.7, 0.8)
			if pr != null:
				_occupied.append([pr, 0.9])
				v.scenery.append(pr)
				Models.pier(root, pr + Vector2(-0.65, 0.0))
				v.docks_at = [pr + Vector2(-0.3, 0.5), pr + Vector2(0.35, 0.5)]
		"alpine":
			var lo = _find_rect([Vector2(-3.9, 2.8), Vector2(-3.9, -2.2), Vector2(3.9, -3.8), Vector2(-3.8, 5.0)], 1.7, 1.2)
			if lo != null:
				_occupied.append([lo, 1.1])
				v.scenery.append(lo)
				var chim: Array = []
				Models.lodge(root, lo, chim)
				v.smoke_at = chim[0]
				var smat := StandardMaterial3D.new()
				smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				for k in 4:
					var m := smat.duplicate() as StandardMaterial3D
					m.albedo_color = Color(0.93, 0.92, 0.9, 0.0)
					var puff := Prim.cyl(root, 0.16, 0.16, 0.01, 10, v.smoke_at, m, false)
					puff.visible = false
					v.smoke.append({"node": puff, "mat": m, "t": k * 0.25})
			# pines, in a loose bunch beside the lodge and along the far edge
			var pine_n := 0
			var rng := RandomNumberGenerator.new()
			rng.seed = 91
			var tries := 0
			while pine_n < 7 and tries < 200:
				tries += 1
				var pp := Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-8.0, 8.0))
				if _spot_free(pp, 0.3, 9.0) and _clear_of_paths(pp, 0.1) and not in_strip(pp, 0.4):
					_occupied.append([pp, 0.35])
					Models.pine(root, pp, rng.randf_range(0.9, 1.3))
					pine_n += 1
			# a chairlift line along a clear column at one side
			for x in [-4.6, 4.6]:
				var a := Vector2(x, -5.2)
				var b := Vector2(x, 1.6)
				var ok := true
				for q in 8:
					if not _clear_of_paths(a.lerp(b, q / 7.0), -0.2) or in_strip(a.lerp(b, q / 7.0), 0.3):
						ok = false
				if ok:
					Models.chairlift(root, a, b, v.chairs)
					v.chair_a = a
					v.chair_b = b
					break
			for hz in Airports.hazards():
				var hc: Vector2 = hz["center"]
				Models.snow_patch(root, hc + Vector2(hz["radius"] * 0.9, hz["radius"] * 0.8), 0.45)
		_:
			if not v.water:
				var pd = _find_rect([Vector2(-3.6, 6.6), Vector2(3.6, -6.8), Vector2(-3.6, -6.4), Vector2(3.6, 6.8), Vector2(-3.8, 2.0), Vector2(-3.8, -2.0)], 1.4, 1.1)
				if pd != null:
					_occupied.append([pd, 0.8])
					v.scenery.append(pd)
					_make_pond(v, pd, 0.55)
			if not v.water and Airports.current != 3:
				var corners := [Vector2(-3.4, 7.9), Vector2(3.4, 7.9), Vector2(-3.4, -8.2), Vector2(3.4, -8.2)]
				var bp = _find_rect(corners, 2.4, 1.4)
				if bp != null:
					_occupied.append([bp, 1.1])
					v.scenery.append(bp)
					Models.barn(root, bp)

## The first of `cands` (centres) whose w x d rectangle lies in the field, clear of the paths' strips and of everything built.
func _find_rect(cands: Array, w: float, d: float, pads: bool = true) -> Variant:
	for p in cands:
		if _rect_clear(p, w, d, pads):
			return p
	return null

func _rect_clear(c: Vector2, w: float, d: float, pads: bool = true) -> bool:
	if absf(c.x) + w * 0.5 > 5.0 or absf(c.y) + d * 0.5 > 8.8:
		return false
	var nx := maxi(int(ceil(w / 0.4)), 1)
	var nz := maxi(int(ceil(d / 0.4)), 1)
	for i in nx + 1:
		for j in nz + 1:
			var p := c + Vector2(-w * 0.5 + w * i / nx, -d * 0.5 + d * j / nz)
			if not _clear_of_paths(p, -0.1, pads) or in_strip(p, 0.05, pads):
				return false
			for o in _occupied:
				if p.distance_to(o[0]) < float(o[1]):
					return false
			for hz in Airports.hazards():
				if p.distance_to(hz["center"]) < hz["radius"] + 0.3:
					return false
			var wm := Airports.windsock_pos()
			if p.distance_to(wm) < 0.5:
				return false
	return true

## The moving scenery, built once: two birds, the hot-air balloon with its far shadow, and the mower with the stripes it leaves.
func _life(v: AirportScene) -> void:
	var root := v.root
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + Airports.current * 31
	for k in 2:
		var b := Models.bird(root, Color("fbfaf6") if v.style == "coastal" else Color("3a3f4c"))
		b.position.y = 1.1
		var sh := Models.blob(root, Vector2.ZERO, 0.3, 0.3, 0.02, 0.6)
		var a := rng.randf() * TAU
		v.birds.append({"node": b, "shadow": sh, "pos": Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-6.0, 6.0)), "vel": Vector2.from_angle(a) * 0.2, "scatter": 0.0})
	var bn := Models.balloon(root)
	bn.position.y = 2.4
	var bs := Models.blob(root, Vector2.ZERO, 1.7, 1.7, 0.02, 0.55)
	v.balloon = {"node": bn, "shadow": bs, "x": rng.randf_range(-5.0, 3.0), "z": -7.0}
	if v.water:
		return
	# the mower: along the far (top) edge of the field, over the longest stretch that is clear of the paths' strips
	var z0 := -8.45
	var best := Vector2.ZERO
	var run_start := -999.0
	var x := -4.9
	while x <= 5.0:
		var ok := _clear_of_paths(Vector2(x, z0), 0.1)
		for o in _occupied:
			if Vector2(x, z0).distance_to(o[0]) < float(o[1]):
				ok = false
		if ok and run_start < -900.0:
			run_start = x
		if (not ok or x > 4.85) and run_start > -900.0:
			if x - run_start > best.y - best.x:
				best = Vector2(run_start, x)
			run_start = -999.0
		x += 0.2
	if best.y - best.x < 1.4:
		return
	v.mower_span = best
	v.mower_z0 = z0
	var stripe := _overlay_mat(Color(1, 1, 1, 0.14))
	for k in 5:
		var st := Prim.box(root, Vector3(best.y - best.x, 0.012, 0.22), Vector3((best.x + best.y) * 0.5, 0.012, z0 + 0.25 * k), stripe, false)
		st.visible = false
		v.mower_rows.append(st)
	v.mower = Models.mower(root)
	v.mower.visible = false

## A pole with a striped cone on top. The cone's pivot turns to point downwind.
func _windsock(v: AirportScene, at: Vector3) -> void:
	_cast(v.root, at.x, at.z, 0.12, 0.12, 1.3, 0.02, 0.8)
	Prim.cyl(v.root, 0.04, 0.05, 1.3, 5, at + Vector3(0, 0.65, 0), Prim.mat(Color(0.8, 0.8, 0.82)))
	var sock := Node3D.new()
	sock.position = at + Vector3(0, 1.3, 0)
	v.root.add_child(sock)
	v.sock = sock
	var orange := Prim.mat(Color("ff6a3d"))
	var white := Prim.mat(Color(0.97, 0.97, 0.95))
	var radii := [0.22, 0.17, 0.12, 0.07]
	for k in 3:
		var seg := Prim.cyl(sock, radii[k + 1], radii[k], 0.32, 6, Vector3(0, 0, -(0.16 + k * 0.32)), orange if k % 2 == 0 else white)
		seg.rotation.x = deg_to_rad(-90.0)

## A landing happened on this end: flash its threshold.
func glow(runway: int, end: int) -> void:
	if DebugFlags.off("glow"):
		return
	if runway * 2 + end < cur.glow_born.size():
		cur.glow_born[runway * 2 + end] = Time.get_ticks_msec()

## Bright thresholds on the ends the wind allows, dull ones on the others.
func show_active(w: Wind) -> void:
	for r in Airports.rw_count():
		for e in 2:
			cur.active[r * 2 + e] = w.is_active(r, e)

## The pre-warm draws every airport at once; afterwards only the current one stays visible.
func show_all(on: bool) -> void:
	for i in variants.size():
		if variants[i] == null:
			continue
		variants[i].root.visible = on or i == selected
		for u in variants[i].ups:      # (every upgrade's scenery is drawn too, so none of it is first seen mid-game)
			u[0].visible = true if on else Save.upgrade_level(u[1]) >= u[2]

func reset() -> void:
	for v in variants:
		if v != null:
			v.glow_born.fill(0)
	_ramp_clear()
	_last_from = -1.0
	_gust_t = 0.0
	_wd = -1.0

func _process(delta: float) -> void:
	if cur == null:
		return
	var now := Time.get_ticks_msec()
	for d in cur.dishes:
		d.rotation.y += delta * 1.8
	var blink := 1.6 if int(now / 600.0) % 2 == 0 and DebugFlags.life_enabled() else 0.0
	for lm in cur.mast_lights:
		Prim.glow(lm, blink)
		Prim.paint(lm, Color(1.0, 0.2, 0.15) if blink > 0.0 else Color(0.55, 0.16, 0.13))
	for k in cur.thr_mats.size():
		var age := (now - cur.glow_born[k]) / 600.0
		var flash := 0.0 if cur.glow_born[k] == 0 or age >= 1.0 else 2.5 * (1.0 - age)
		var m := cur.thr_mats[k]
		var on := cur.active[k]
		Prim.paint(m, cur.thr_colors[k] if on else Color(0.38, 0.39, 0.42))
		Prim.glow(m, (0.45 if on else 0.0) + flash)
	if DebugFlags.life_enabled():
		_animate_ground(delta, now)
		_animate_life(delta)
	_animate_wind(delta, now)
	if cur.lights != null:
		cur.lights.visible = not DebugFlags.windtest_enabled()       # (the lights shimmer by themselves: the web wind check wants a still field)
	var pulse := 1.4 if int(now / 1400.0) % 2 == 0 and DebugFlags.life_enabled() else 0.2
	for lm2 in cur.lamps:
		Prim.glow(lm2, pulse)
	for bm in cur.beacons:
		Prim.glow(bm, blink)
		Prim.paint(bm, Color(0.95, 0.23, 0.19) if blink > 0.0 else Color(0.45, 0.14, 0.12))
	if wind != null and cur.sock != null:
		_sock_deg += wrapf(wind.toward_deg() - _sock_deg, -180.0, 180.0) * (1.0 if DebugFlags.windtest_enabled() else minf(delta * 2.5, 1.0))
		var wiggle := sin(now / 260.0) * 6.0 if DebugFlags.life_enabled() else 0.0
		cur.sock.rotation.y = -deg_to_rad(_sock_deg + wiggle)
		cur.sock.rotation.x = deg_to_rad(sin(now / 190.0) * 4.0) if DebugFlags.life_enabled() else 0.0


## The moving scenery: the fuel truck (a slow loop from the fuel farm to a parked plane and back), birds (they scatter from aircraft),
## the balloon drifting across the top, the mower and its stripes. ?nolife stops all of it.
func _animate_life(delta: float) -> void:
	_life_t += delta
	var v := cur
	if v.truck != null and v.truck_pts.size() >= 2:
		var total := 0.0
		for i in v.truck_pts.size() - 1:
			total += v.truck_pts[i].distance_to(v.truck_pts[i + 1])
		var speed := 0.22
		var go := total / speed
		var cycle := 2.0 * go + 14.0
		var u := fposmod(_life_t + 3.0, cycle)
		var d := 0.0
		var fwd := true
		if u < go:
			d = u * speed
		elif u < go + 5.0:
			d = total
		elif u < 2.0 * go + 5.0:
			d = total - (u - go - 5.0) * speed
			fwd = false
		else:
			d = 0.0
		var pos := v.truck_pts[0]
		var heading := Vector2.DOWN
		var left := d
		for i in v.truck_pts.size() - 1:
			var seg := v.truck_pts[i].distance_to(v.truck_pts[i + 1])
			heading = (v.truck_pts[i + 1] - v.truck_pts[i]).normalized() if seg > 0.0001 else heading
			if left <= seg or i == v.truck_pts.size() - 2:
				pos = v.truck_pts[i].lerp(v.truck_pts[i + 1], clampf(left / maxf(seg, 0.0001), 0.0, 1.0))
				break
			left -= seg
		if not fwd:
			heading = -heading
		v.truck.position = Vector3(pos.x, 0.0, pos.y)
		v.truck.rotation.y = -atan2(heading.x, -heading.y)
	for b in v.birds:
		var p: Vector2 = b["pos"]
		var vel: Vector2 = b["vel"]
		var scatter: float = b["scatter"]
		if traffic != null:
			for pl in traffic.planes:
				if pl.active() and pl.entered and not pl.fogged and pl.pos.distance_to(p) < 1.7:
					vel = (p - pl.pos).normalized() * 1.5
					scatter = 1.6
		scatter = maxf(scatter - delta, 0.0)
		if scatter <= 0.0 and vel.length() > 0.24:
			vel = vel.lerp(vel.normalized() * 0.2, minf(delta * 0.8, 1.0))
		p += vel * delta
		if absf(p.x) > 6.2:
			p.x = -signf(p.x) * 6.0
		if absf(p.y) > 10.5:
			p.y = -signf(p.y) * 10.3
		b["pos"] = p
		b["vel"] = vel
		b["scatter"] = scatter
		var n: Node3D = b["node"]
		n.position = Vector3(p.x, 1.1, p.y)
		n.rotation.y = -atan2(vel.x, -vel.y)
		n.get_child(0).rotation.y = deg_to_rad(-20.0 - 25.0 * sin(_life_t * 9.0 + p.x))
		n.get_child(1).rotation.y = deg_to_rad(20.0 + 25.0 * sin(_life_t * 9.0 + p.x))
		(b["shadow"] as Node3D).position = Vector3(p.x + 0.3, 0.02, p.y + 0.3)
	for sm in v.smoke:
		sm["t"] = fposmod(float(sm["t"]) + delta * 0.18, 1.0)
		var u: float = sm["t"]
		var dir := Vector2(1.0, 0.4)
		if wind != null:
			var tw := deg_to_rad(wind.toward_deg())
			dir = Vector2(sin(tw), -cos(tw))
		var puff: MeshInstance3D = sm["node"]
		puff.visible = true
		puff.position = Vector3(v.smoke_at.x + dir.x * u * 0.9, v.smoke_at.y, v.smoke_at.z + dir.y * u * 0.9)
		puff.scale = Vector3.ONE * lerpf(0.6, 2.0, u)
		Prim.paint(sm["mat"] as StandardMaterial3D, Color(0.93, 0.92, 0.9, snappedf(0.55 * (1.0 - u) * minf(u * 8.0, 1.0), 0.02)))
	for ci in v.chairs.size():
		var cu := fposmod(_life_t * 0.035 + ci * 0.5, 1.0)
		var cp := v.chair_a.lerp(v.chair_b, cu)
		(v.chairs[ci] as Node3D).position = Vector3(cp.x, 0.0, cp.y)
	if not v.balloon.is_empty():
		var bx: float = v.balloon["x"] + delta * 0.11
		if bx > 6.5:
			bx = -6.5
		v.balloon["x"] = bx
		var bz: float = v.balloon["z"] + sin(_life_t * 0.15) * delta * 0.05
		v.balloon["z"] = bz
		(v.balloon["node"] as Node3D).position = Vector3(bx, 2.4, bz)
		(v.balloon["shadow"] as Node3D).position = Vector3(bx + 1.0, 0.02, bz + 1.0)
	if v.mower != null:
		var prog := progress if progress >= 0.0 else fposmod(_life_t / 90.0, 1.0)
		var rows := v.mower_rows.size()
		var f := prog * rows
		var row := mini(int(f), rows - 1)
		var pass_t := f - float(row)
		var fx := pass_t if row % 2 == 0 else 1.0 - pass_t
		var mx := lerpf(v.mower_span.x, v.mower_span.y, fx)
		v.mower.visible = true
		v.mower.position = Vector3(mx, 0.0, v.mower_z0 + 0.25 * row)
		v.mower.rotation.y = deg_to_rad(-90.0 if row % 2 == 0 else 90.0)
		for k in rows:
			var st: MeshInstance3D = v.mower_rows[k]
			var reveal := 1.0 if k < row else (pass_t if k == row else 0.0)
			st.visible = reveal > 0.01
			if st.visible:
				var span := v.mower_span.y - v.mower_span.x
				st.scale = Vector3(reveal, 1.0, 1.0)
				var start_left := k % 2 == 0
				st.position.x = (v.mower_span.x + span * reveal * 0.5) if start_left else (v.mower_span.y - span * reveal * 0.5)

# ---------- Upgrade scenery: each purchased upgrade can be seen on the airport ----------

## Is the point `p` clear of runways, pads, lanes, mountains, the tower and the windsock (with `r` to spare)?
func _spot_free(p: Vector2, r: float, bound: float = 6.0) -> bool:
	for i in Airports.rw_count():
		var a := Airports.end_threshold(i, 0)
		var b := Airports.end_far(i, 0)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) < Airports.rw_width(i) * 0.5 + r + 0.15:
			return false
	for pad in Airports.pads():
		if p.distance_to(pad["center"]) < pad["radius"] + r:
			return false
	for lane in Airports.lanes():
		var h := deg_to_rad(lane["heading"])
		var dir := Vector2(sin(h), -cos(h))
		var a2: Vector2 = lane["center"] - dir * lane["length"] * 0.5
		var ab2: Vector2 = dir * lane["length"]
		var t2 := clampf((p - a2).dot(ab2) / maxf(ab2.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a2 + ab2 * t2) < lane["width"] * 0.5 + r + 0.3:
			return false
	for hz in Airports.hazards():
		if p.distance_to(hz["center"]) < hz["radius"] + r:
			return false
	if p.distance_to(Airports.tower_pos()) < 0.8 + r or p.distance_to(Airports.windsock_pos()) < 0.5 + r:
		return false
	for o in _occupied:
		if p.distance_to(o[0]) < float(o[1]) + r:
			return false
	return absf(p.x) < 4.6 and absf(p.y) < bound

## Up to `n` free spots on rings around `c`, at least `spacing` apart (then, if the rings were not enough, anywhere on the field,
## nearest first).
func _find_spots(c: Vector2, n: int, r: float, spacing: float, radii: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for ring in radii:
		for k in 12:
			var p: Vector2 = c + Vector2(cos(k * TAU / 12.0 + 0.4), sin(k * TAU / 12.0 + 0.4)) * ring
			if not _spot_free(p, r, 8.6) or in_strip(p, r):
				continue
			var ok := true
			for q in out:
				if q.distance_to(p) < spacing:
					ok = false
			if ok:
				out.append(p)
				if out.size() >= n:
					return out
	var best: Array = []
	var relaxed: Array = []        # (only where the field is too crowded: under the interface, but still outside every strip)
	var gx := -4.4
	while gx <= 4.4:
		var gz := -8.4
		while gz <= 8.4:
			var p2 := Vector2(gx, gz)
			if _spot_free(p2, r, 8.6) and _clear_of_paths(p2, -0.9):
				if not in_strip(p2, r):
					best.append(p2)
				elif not in_strip(p2, r, true, false):
					relaxed.append(p2)
			gz += 0.5
		gx += 0.5
	best.sort_custom(func(a: Vector2, b: Vector2): return a.distance_to(c) < b.distance_to(c))
	relaxed.sort_custom(func(a: Vector2, b: Vector2): return a.distance_to(c) < b.distance_to(c))
	best.append_array(relaxed)
	for p3 in best:
		var ok2 := true
		for q in out:
			if q.distance_to(p3) < spacing:
				ok2 = false
		if ok2:
			out.append(p3)
			if out.size() >= n:
				break
	return out

func _upgrade_props(v: AirportScene) -> void:
	var root := v.root
	var tower: Vector2 = v.apron_c if v.apron_s > 0.0 and not v.apron_c.is_equal_approx(Vector2.ZERO) else Airports.tower_pos()
	var ar := 2.1 * v.apron_s if not v.apron_c.is_equal_approx(Vector2.ZERO) else 0.0       # (the props stand around the apron, not on it)
	var metal := Prim.mat(Color(0.78, 0.8, 0.84))
	var dark := Prim.mat(Color(0.2, 0.22, 0.26))
	# Radar: up to three turning dishes around the tower.
	var spots := _find_spots(tower, 3, 0.35, 0.8, [ar + 0.5, ar + 0.9, ar + 1.3, 1.2, 1.6, 2.1])
	for k in spots.size():
		var holder := Node3D.new()
		holder.position = Vector3(spots[k].x, 0.0, spots[k].y)
		root.add_child(holder)
		Prim.cyl(holder, 0.05, 0.06, 0.7, 5, Vector3(0, 0.35, 0), metal)
		var turret := Node3D.new()
		turret.position = Vector3(0, 0.78, 0)
		holder.add_child(turret)
		var dish := Prim.cyl(turret, 0.36, 0.04, 0.16, 8, Vector3(0, 0.0, -0.1), metal)
		dish.rotation.x = deg_to_rad(-62.0)
		Prim.box(turret, Vector3(0.05, 0.05, 0.3), Vector3(0, 0.12, -0.12), dark, false)
		v.dishes.append(turret)
		v.ups.append([holder, "radar", k + 1])
	# Better Comms: radio masts with blinking beacons.
	spots = _find_spots(tower, 3, 0.3, 0.8, [ar + 1.5, ar + 1.9, ar + 2.3, 2.4, 2.9, 3.4])
	for k in spots.size():
		var holder := Node3D.new()
		holder.position = Vector3(spots[k].x, 0.0, spots[k].y)
		root.add_child(holder)
		Prim.cyl(holder, 0.03, 0.07, 1.6, 4, Vector3(0, 0.8, 0), metal)
		Prim.box(holder, Vector3(0.5, 0.04, 0.04), Vector3(0, 1.25, 0), metal, false)
		var lm := Prim.mat(Color(1.0, 0.2, 0.15))
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.15, 0.1)
		lm.emission_energy_multiplier = 0.0
		v.mast_lights.append(lm)
		Prim.cyl(holder, 0.07, 0.07, 0.12, 6, Vector3(0, 1.64, 0), lm, false)
		v.ups.append([holder, "comms", k + 1])
	# Tower Staff: a terminal annex, then a bigger one, then a flag.
	spots = _find_spots(tower, 3, 0.55, 1.0, [ar + 0.9, ar + 1.3, ar + 1.7, 1.9, 2.4, 2.9])
	for k in spots.size():
		var holder := Node3D.new()
		holder.position = Vector3(spots[k].x, 0.0, spots[k].y)
		root.add_child(holder)
		if k == 2:
			Prim.cyl(holder, 0.03, 0.03, 1.1, 4, Vector3(0, 0.55, 0), metal, false)
			Prim.box(holder, Vector3(0.5, 0.3, 0.03), Vector3(0.25, 0.95, 0), Prim.mat(Color(0.9, 0.2, 0.2)), false)
		else:
			Prim.box(holder, Vector3(0.9 + 0.3 * k, 0.4, 0.55), Vector3(0, 0.2, 0), Prim.mat(Color(0.88, 0.85, 0.78)))
			Prim.box(holder, Vector3(0.96 + 0.3 * k, 0.1, 0.62), Vector3(0, 0.45, 0), Prim.mat(Color(0.55, 0.3, 0.25)))
		v.ups.append([holder, "tower", k + 1])
	# Holding Fixes: marker cones (two more each level) out in the airspace.
	var cone_a := Prim.mat(Color(1.0, 0.5, 0.1))
	var cone_b := Prim.mat(Color(0.97, 0.97, 0.95))
	var fix_pos: Array[Vector2] = []
	for z in [-1.5, 1.0, -3.2, 2.6, -4.6, 4.4, 0.0, -2.2, 3.4, -5.4, 5.4, -6.4, 6.4, -7.4, 7.4, -8.2, 8.2]:
		for x in [-4.2, 4.2, -3.6, 3.6, -4.6, 4.6, 0.0]:
			fix_pos.append(Vector2(x, z))
	var placed := 0
	for p in fix_pos:
		if placed >= 6 or not _spot_free(p, 0.3, 8.6) or in_strip(p, 0.25):
			continue
		var near_other := false
		for u in v.ups:
			if u[1] == "holding" and Vector2(u[0].position.x, u[0].position.z).distance_to(p) < 1.6:
				near_other = true
		if near_other:
			continue
		var holder := Node3D.new()
		holder.position = Vector3(p.x, 0.0, p.y)
		root.add_child(holder)
		Prim.cyl(holder, 0.0, 0.22, 0.5, 6, Vector3(0, 0.25, 0), cone_a)
		Prim.cyl(holder, 0.0, 0.12, 0.2, 6, Vector3(0, 0.44, 0), cone_b, false)
		v.ups.append([holder, "holding", 1 + placed / 2])
		placed += 1
	# Approach Control: rows of approach lights behind every runway end (3, 6, then 9 of them).
	var light := Prim.mat(Color(1.0, 0.95, 0.7))
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for r in Airports.rw_count():
		for e in 2:
			var thr := Airports.end_threshold(r, e)
			var dir := Airports.end_dir(r, e)
			var side := Vector2(-dir.y, dir.x)
			for k in 9:
				var p := thr - dir * (0.9 + k * 0.42) + side * (0.0 if k % 3 == 0 else (0.3 if k % 3 == 1 else -0.3))
				if not _spot_free(p, 0.1, 8.0):
					continue
				var node := Prim.box(root, Vector3(0.14, 0.1, 0.14), Vector3(p.x, 0.05, p.y), light, false)
				v.ups.append([node, "approach", 1 + k / 3])
	# Fast Turnoffs: angled exit taxiways off each runway (2, 4, then 6).
	var taxi := Prim.mat(Tuning.runway_asphalt.lightened(0.05))
	for r in Airports.rw_count():
		var rr := Node3D.new()
		rr.position = Vector3(Airports.rw_center(r).x, 0.0, Airports.rw_center(r).y)
		rr.rotation.y = -deg_to_rad(Airports.rw_heading_deg(r))
		root.add_child(rr)
		var len := Airports.rw_length(r)
		var w := Airports.rw_width(r)
		for k in 6:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var z := (0.34 - 0.07 * (k / 2)) * len * (1.0 if (k / 2) % 2 == 0 else -1.0)
			var strip := Prim.box(rr, Vector3(0.32, 0.1, 1.3), Vector3(sx * (w * 0.5 + 0.35), 0.05, z), taxi)
			strip.rotation.y = deg_to_rad(sx * 35.0)
			v.ups.append([strip, "turnoffs", 1 + k / 2])

## Show each upgrade's scenery that has been bought (called at start-up and after a purchase).
func show_upgrades() -> void:
	for v in variants:
		if v == null:
			continue
		for u in v.ups:
			u[0].visible = Save.upgrade_level(u[1]) >= u[2]

func upgrade_nodes_visible(id: String) -> int:
	var n := 0
	for u in cur.ups:
		if u[1] == id and u[0].visible:
			n += 1
	return n


# ---------- The ramp: hangar, tie-downs, overflow spots, heli spot, dock ----------

func _slot_node(v: AirportScene, root: Node3D, pos: Vector2, yaw: float, heli: bool) -> Dictionary:
	var holder := Node3D.new()
	holder.position = Vector3(pos.x, 0.0, pos.y)
	holder.rotation.y = -yaw
	root.add_child(holder)
	var ch: Node3D = null if heli else Models.chocks(holder, PARK_SCALE * v.apron_s * 2.0)
	return {"chocks": ch, "pos": pos, "yaw": yaw, "heli": heli, "mi": -1}

## The apron's six tie-downs (the second row on an extension of the slab, to the south or else the west), the hangar's door, the "+N"
## tag, the overflow spots on the grass along the taxiway, the heli spot (airports with a pad) and the dock (the island's pier).
## Every plane that will ever park is built here, hidden, and only shown when one arrives: nothing is allocated during a shift.
func _ramp_slots(v: AirportScene) -> void:
	if Airports.apron().is_empty():
		return
	var root := v.root
	var c := v.apron_c
	var s := v.apron_s
	var pal: Dictionary = PALETTE[v.style]
	v.ramp_ok = true
	var south := absf(c.y + 2.7 * s) < 8.9 and rect_out_of_strips(Rect2(c.x - 1.4 * s, c.y + 1.6 * s, 2.8 * s, 1.1 * s), 0.1)
	var west := not south and c.x - 2.5 * s > -5.0 and rect_out_of_strips(Rect2(c.x - 2.5 * s, c.y - 1.6 * s, 1.1 * s, 3.2 * s), 0.1)
	var ex := c.x + 1.55 * s
	var aisle1 := c.y + 0.82 * s
	var aisle2 := c.y + 1.72 * s
	var ties: Array = []
	for i in 3:
		var x := c.x + (-0.9 + 0.9 * i) * s
		var p := Vector2(x, c.y + 1.28 * s)
		ties.append({"pos": p, "yaw": PI, "goals": [Vector2(ex, aisle1)], "tail": PackedVector2Array([Vector2(x, aisle1), p])})
	var tag_pos := c + Vector2(1.0 * s, 1.45 * s)
	v.extra_goals = [Vector2(ex, aisle1)]
	v.extra_tail = PackedVector2Array([Vector2(c.x + 1.0 * s, aisle1), tag_pos])
	if south:
		Prim.box(root, Vector3(2.8 * s, 0.03, 1.1 * s), Vector3(c.x, 0.0, c.y + 2.15 * s), Prim.mat(pal["apron"]), false)
		for i in 3:
			var x2 := c.x + (-0.9 + 0.9 * i) * s
			var p2 := Vector2(x2, c.y + 2.23 * s)
			ties.append({"pos": p2, "yaw": PI, "goals": [Vector2(ex, aisle2)], "tail": PackedVector2Array([Vector2(x2, aisle2), p2])})
		tag_pos = c + Vector2(1.0 * s, 2.4 * s)
		v.extra_goals = [Vector2(ex, aisle2)]
		v.extra_tail = PackedVector2Array([Vector2(c.x + 1.0 * s, aisle2), tag_pos])
	elif west:
		Prim.box(root, Vector3(1.1 * s, 0.03, 3.2 * s), Vector3(c.x - 1.95 * s, 0.0, c.y), Prim.mat(pal["apron"]), false)
		for i in 3:
			var p3 := Vector2(c.x - 1.95 * s, c.y + (-0.55 + 0.95 * i) * s)
			ties.append({"pos": p3, "yaw": PI * 0.5, "goals": [p3 + Vector2(-1.0 * s, 0.0)], "tail": PackedVector2Array([p3])})
		tag_pos = c + Vector2(-1.95 * s, -1.35 * s)
		v.extra_goals = [tag_pos + Vector2(-1.0 * s, 0.0)]
		v.extra_tail = PackedVector2Array([tag_pos])
	v.slots["tie"] = []
	for i in ties.size():
		var t: Dictionary = ties[i]
		var e := _slot_node(v, root, t["pos"], t["yaw"], false)
		e["goals"] = t["goals"]
		e["tail"] = t["tail"]
		(v.slots["tie"] as Array).append(e)
		Models.tie_down(root, (t["pos"] as Vector2) + Vector2(sin(t["yaw"]), -cos(t["yaw"])) * -0.02, -rad_to_deg(t["yaw"]))
	# the hangar: the door faces south; aircraft come along the gap between it and the FBO
	var door := Vector2(c.x - 0.7 * s, c.y - 0.62 * s)
	v.hangar_goals = [Vector2(ex, c.y - 0.38 * s), Vector2(c.x - 1.55 * s, c.y - 0.38 * s)]
	v.hangar_tail = PackedVector2Array([Vector2(c.x - 0.7 * s, c.y - 0.38 * s), door])
	v.hangar_label = _ramp_label(root, Vector3(c.x - 0.7 * s, 0.55, c.y - 1.0 * s), 0.0042 * s, Color("f7f0e1"))
	v.extra_tag = _ramp_label(root, Vector3(tag_pos.x, 0.06, tag_pos.y), 0.0042 * s, Color("f7f0e1"))
	v.extra_tag.visible = false
	v.hangar_label.visible = false
	# the overflow spots: on the grass along the taxiway, nearest the apron first
	v.slots["over"] = []
	var far0 := Airports.land_far(Aircraft.Kind.RUNWAY, 0, 0)
	var dir0 := Airports.end_dir(0, 0)
	var best: PackedVector2Array
	for g in v.hangar_goals:
		var r0 := Ramp.taxi_route(far0, dir0, g, v.hangar_tail)
		if not r0.is_empty() and (best.is_empty() or Ramp.route_length(r0) < Ramp.route_length(best)):
			best = r0
	var chosen: Array[Vector2] = []
	var walk: Array = []         # [point, tangent] along the route, from the apron end back
	var total := Ramp.route_length(best)
	var d := total - 2.2 * s
	while d > 1.4:
		walk.append(_route_at(best, d))
		d -= 0.8
	for w in walk:
		if chosen.size() >= Ramp.OVERS:
			break
		var wp: Vector2 = w[0]
		var wt: Vector2 = w[1]
		var wn := Vector2(-wt.y, wt.x)
		for sg in [1.0, -1.0]:
			var cp: Vector2 = wp + wn * sg * 0.72
			if chosen.size() >= Ramp.OVERS:
				break
			if not _spot_free(cp, 0.4, 8.6) or not _clear_of_paths(cp, -0.3) or in_strip(cp, 0.35) or cp.distance_to(c) < 2.0 * s + 0.3:
				continue
			var near := false
			for o in chosen:
				if o.distance_to(cp) < 0.95:
					near = true
			if near:
				continue
			chosen.append(cp)
			_occupied.append([cp, 0.42])
			var ye := atan2(wt.x, -wt.y)
			var e2 := _slot_node(v, root, cp, ye, false)
			e2["goals"] = [cp]
			e2["tail"] = PackedVector2Array()
			(v.slots["over"] as Array).append(e2)
			break
	# a marked heli spot (airports with a pad)
	v.slots["heli"] = []
	if not Airports.pads().is_empty():
		var cands: Array[Vector2] = []
		for ring in [1.9 * s + 0.6, 2.2 * s + 0.7, 2.4 * s + 1.0, 2.7 * s + 1.2, 3.0 * s + 1.4, 3.5 * s + 1.6, 4.0 * s + 1.8]:
			for k in 16:
				cands.append(c + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * ring)
		var pc: Vector2 = Airports.pads()[0]["center"]       # (also beside the pad itself: the helicopter has only a short hop)
		for ring in [1.6, 2.0, 2.4, 2.9]:
			for k in 16:
				cands.append(pc + Vector2(cos(k * TAU / 16.0 + 0.2), sin(k * TAU / 16.0 + 0.2)) * ring)
		var hs = _find_rect(cands, 0.9, 0.9, false)       # (it may stand beside its own pad, inside the pad's ring)
		if hs != null:
			_occupied.append([hs, 0.5])
			Prim.cyl(root, 0.4, 0.4, 0.012, 16, Vector3(hs.x, 0.02, hs.y), Prim.mat(Airports.PAD_COLOR.lightened(0.15)), false)
			Prim.cyl(root, 0.34, 0.34, 0.012, 16, Vector3(hs.x, 0.026, hs.y), Prim.mat(Color("f2ede4")), false)
			var hl := _ramp_label(root, Vector3(hs.x, 0.034, hs.y), 0.0035, Airports.PAD_COLOR)
			hl.text = "H"
			var he := _slot_node(v, root, hs, 0.0, true)
			he["goals"] = [hs]
			he["tail"] = PackedVector2Array()
			(v.slots["heli"] as Array).append(he)
	# the dock (the pier's two berths)
	v.slots["dock"] = []
	for dk in v.docks_at:
		var de := _slot_node(v, root, dk, PI * 0.5, false)
		de["goals"] = [dk]
		de["tail"] = PackedVector2Array()
		(v.slots["dock"] as Array).append(de)

func _ramp_label(root: Node3D, at: Vector3, px: float, col: Color) -> Label3D:
	var lab := Label3D.new()
	lab.font_size = 96
	lab.pixel_size = px
	lab.modulate = col
	lab.outline_modulate = Color(0.23, 0.14, 0.06, 0.9)
	lab.outline_size = 10
	lab.shaded = false
	lab.double_sided = false
	lab.no_depth_test = false
	lab.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lab.position = at
	lab.render_priority = 5
	root.add_child(lab)
	return lab

## The point and direction `d` units along a polyline.
func _route_at(r: PackedVector2Array, d: float) -> Array:
	var left := maxf(d, 0.0)
	for k in r.size() - 1:
		var seg := r[k].distance_to(r[k + 1])
		if left <= seg or k == r.size() - 2:
			var t := (r[k + 1] - r[k]).normalized() if seg > 0.0001 else Vector2(0, -1)
			return [r[k] + t * minf(left, seg), t]
		left -= seg
	return [r[0], Vector2(0, -1)]

## A new shift: the hangar is empty and the ramp bare (in place; the planes and labels were all built with the airport).
func ramp_begin() -> void:
	_ramp_clear()
	var v := cur
	ramp_active = v != null and v.ramp_ok
	if not ramp_active:
		return
	ramp.reset(Ramp.capacity(), (v.slots["over"] as Array).size(), (v.slots["dock"] as Array).size(), (v.slots["heli"] as Array).size(), (v.slots["tie"] as Array).size())
	_ramp_labels()

func _ramp_clear() -> void:
	ramp_active = false
	taxis.clear()
	hangar_shown = 0
	extra_shown = 0
	if traffic != null:
		traffic.ramp_free_all()
	for v in variants:
		if v == null or not v.ramp_ok:
			continue
		for kind in v.slots:
			for e in v.slots[kind]:
				e["mi"] = -1
				if e["chocks"] != null:
					(e["chocks"] as Node3D).visible = false
		v.hangar_label.visible = false
		v.extra_tag.visible = false

func _ramp_labels() -> void:
	var v := cur
	if v == null or not v.ramp_ok:
		return
	v.hangar_label.visible = ramp_active
	v.hangar_label.text = "%d / %d" % [hangar_shown, ramp.cap]
	v.hangar_label.modulate = Color("ffd25a") if hangar_shown >= ramp.cap else Color("f7f0e1")
	v.extra_tag.visible = ramp_active and extra_shown > 0
	v.extra_tag.text = "+%d" % extra_shown

## An aircraft has landed: it taxis along its airport's fixed route to its place (see Ramp.place), as the very same model, livery and
## student badge that landed. Returns that place.
func begin_taxi(type: int, kind: int, idx: int, end: int, student: bool = false, cls: int = -1) -> Dictionary:
	if not ramp_active or traffic == null:
		return {}
	var v := cur
	var slot := ramp.place(type)
	var far := Airports.land_far(kind, idx, end)
	var hdg := deg_to_rad(Airports.land_heading_deg(kind, idx, end))
	var dir := Vector2(sin(hdg), -cos(hdg))
	var sk: String = slot["kind"]
	var key := "%d:%d:%d|%s:%d" % [kind, idx, end, sk, slot["idx"]]
	var route: PackedVector2Array = v.routes.get(key, PackedVector2Array())
	if route.is_empty():
		var entry := _slot_entry(v, slot)
		for g in entry["goals"]:
			var r := Ramp.taxi_route(far, dir, g, entry["tail"], kind != Aircraft.Kind.PAD)
			if not r.is_empty() and (route.is_empty() or Ramp.route_length(r) < Ramp.route_length(route)):
				route = r
		if route.is_empty():
			route = PackedVector2Array([far, far])        # (never: every slot has a goal that can be reached)
		v.routes[key] = route
	# keep at most TAXI_MAX at their own pace: the older ones hurry
	var moving := 0
	for t in taxis:
		if not t["ff"]:
			moving += 1
	var ti := 0
	while moving > TAXI_MAX - 1 and ti < taxis.size():
		if not taxis[ti]["ff"]:
			taxis[ti]["ff"] = true
			moving -= 1
		ti += 1
	var mi := traffic.ramp_claim()
	if mi < 0 and not taxis.is_empty():
		var old: Dictionary = taxis.pop_front()
		_finish_taxi(old)
		mi = traffic.ramp_claim()
	if mi < 0:
		_count_arrival(slot)
		return slot
	var c := cls if cls >= 0 else Tuning.type_speed_class(type)
	traffic.ramp_configure(mi, type, c, kind, idx, student)
	var h0 := atan2(dir.x, -dir.y)
	var scale0 := LAND_SCALE
	traffic.ramp_place(mi, route[0], h0, scale0, 0.0, false, 0.0, type)
	var entry_slot: Dictionary = {} if sk == "hangar" or sk == "extra" else (v.slots[sk] as Array)[slot["idx"]]
	if not entry_slot.is_empty():
		entry_slot["mi"] = mi
		if entry_slot["chocks"] != null:
			(entry_slot["chocks"] as Node3D).visible = false
	var sit := HELI_SIT if type == Aircraft.Type.HELI else 0.0
	taxis.append({"mi": mi, "type": type, "entry": entry_slot, "route": route, "len": Ramp.route_length(route), "d": 0.0, "wait": sit, "ff": false, "slot": slot, "hdg": h0, "clock": 0.0, "scale": scale0})
	return slot

func _slot_entry(v: AirportScene, slot: Dictionary) -> Dictionary:
	match slot["kind"]:
		"hangar":
			return {"goals": v.hangar_goals, "tail": v.hangar_tail}
		"extra":
			return {"goals": v.extra_goals, "tail": v.extra_tail}
		_:
			var e: Dictionary = (v.slots[slot["kind"]] as Array)[slot["idx"]]
			return {"goals": e["goals"], "tail": e["tail"]}

func _count_arrival(slot: Dictionary) -> void:
	if slot.get("counted", false):         # (a landing that counts toward the hangar, wherever it parked)
		hangar_shown += 1
	if slot["kind"] == "extra":
		extra_shown += 1
	_ramp_labels()

func _finish_taxi(t: Dictionary) -> void:
	var slot: Dictionary = t["slot"]
	var mi: int = t["mi"]
	match slot["kind"]:
		"hangar", "extra":
			traffic.ramp_release(mi)
		_:
			var e: Dictionary = t["entry"]
			var scale := PARK_SCALE * cur.apron_s
			traffic.ramp_place(mi, e["pos"], float(e["yaw"]), scale, 0.0, false, 0.0, int(t["type"]))
			if e["chocks"] != null:
				(e["chocks"] as Node3D).visible = true
	_count_arrival(slot)

## Move the taxiing aircraft along their routes (the shift's own clock: a paused shift stands still). A helicopter sits on its pad for
## HELI_SIT seconds first, then air-taxis (a little above the ground) to its heli spot.
func step_taxi(delta: float) -> void:
	var i := 0
	while i < taxis.size():
		var t: Dictionary = taxis[i]
		var type: int = t["type"]
		var dt := delta
		if t["wait"] > 0.0:
			dt = delta - float(t["wait"])           # (what is left of the step once the wait is over)
			t["wait"] = maxf(float(t["wait"]) - delta, 0.0)
			if dt <= 0.0:
				i += 1
				continue
		var fast: bool = t["ff"]
		t["d"] = float(t["d"]) + TAXI_SPEED * (TAXI_FAST if fast else 1.0) * dt
		t["clock"] = float(t["clock"]) + dt
		if float(t["d"]) >= float(t["len"]):
			_finish_taxi(t)
			taxis.remove_at(i)
			continue
		var at := _route_at(t["route"], float(t["d"]))
		var p: Vector2 = at[0]
		var tan: Vector2 = at[1]
		var want := atan2(tan.x, -tan.y)
		var diff := wrapf(want - float(t["hdg"]), -PI, PI)
		var turn := 4.0 * dt * (TAXI_FAST * 0.5 if fast else 1.0)
		t["hdg"] = float(t["hdg"]) + clampf(diff, -turn, turn)
		# it shrinks from the size it landed at to the ramp's, over its first stretch
		var park := PARK_SCALE * cur.apron_s
		var scale := lerpf(LAND_SCALE, park, smoothstep(0.0, 3.0, float(t["d"])))
		var hover := 0.12 if type == Aircraft.Type.HELI else 0.0
		traffic.ramp_place(int(t["mi"]), p, float(t["hdg"]), scale, hover, true, float(t["clock"]), type)
		i += 1

# ---------- The wind you can always see ----------

func _build_streaks() -> void:
	_st_rng.seed = 4242
	_st_pos.resize(STREAKS)
	_st_len.resize(STREAKS)
	_st_age.resize(STREAKS)
	_st_ttl.resize(STREAKS)
	_st_alpha.resize(STREAKS)
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 0.03)
	_st_mat = StandardMaterial3D.new()
	_st_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_st_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_st_mat.vertex_color_use_as_albedo = true
	_st_mat.albedo_color = Color(0.99, 0.95, 0.85, 1.0)
	_st_mat.render_priority = 1
	_st_mm = MultiMesh.new()
	_st_mm.transform_format = MultiMesh.TRANSFORM_3D
	_st_mm.use_colors = true
	_st_mm.mesh = quad
	_st_mm.instance_count = STREAKS
	for i in STREAKS:
		_st_pos[i] = Vector2(_st_rng.randf_range(-5.0, 5.0), _st_rng.randf_range(-9.0, 9.0))
		_st_len[i] = _st_rng.randf_range(0.55, 1.1)          # 60-120 px
		_st_ttl[i] = _st_rng.randf_range(5.0, 9.0)
		_st_age[i] = _st_rng.randf() * _st_ttl[i]
		_st_mm.set_instance_color(i, Color(1, 1, 1, 0))
	_st_node = MultiMeshInstance3D.new()
	_st_node.multimesh = _st_mm
	_st_node.material_override = _st_mat
	_st_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_st_node.position = Vector3(0, 0.62, 0)          # above the props of the ground, below the paths (which are drawn over everything) and the aircraft's fliers
	_st_node.visible = DebugFlags.wind_enabled()
	add_child(_st_node)

## The pond: a little water with a sand rim; its ripples (a few thin rings) are pooled.
func _make_pond(v: AirportScene, c: Vector2, r: float) -> void:
	var root := v.root
	Prim.cyl(root, r + 0.08, r + 0.1, 0.012, 16, Vector3(c.x, 0.016, c.y), Prim.mat(Color("d8c98f")), false)
	Prim.cyl(root, r, r, 0.012, 16, Vector3(c.x, 0.024, c.y), Prim.mat(Color("6fb7d4")), false)
	Prim.cyl(root, r * 0.6, r * 0.6, 0.012, 14, Vector3(c.x - r * 0.12, 0.03, c.y - r * 0.12), Prim.mat(Color("8ccce2")), false)
	var ripples: Array = []
	var prng := RandomNumberGenerator.new()
	prng.seed = 5 + Airports.current
	for k in 3:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.46
		ring.outer_radius = 0.5
		ring.rings = 16
		ring.ring_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3(0.01, 0.1, 0.01)
		mi.position = Vector3(c.x, 0.04, c.y)
		root.add_child(mi)
		ripples.append({"node": mi, "mat": mat, "t": k / 3.0, "off": Vector2(prng.randf_range(-0.4, 0.4), prng.randf_range(-0.4, 0.4)) * r})
	v.pond = {"center": c, "r": r, "ripples": ripples}

func _animate_wind(delta: float, now: int) -> void:
	if wind == null or cur == null:
		return
	var on := DebugFlags.wind_enabled()
	_st_node.visible = on
	var toward := wind.toward_deg()
	if _last_from >= 0.0 and wind.from_deg != _last_from:
		_gust_t = SWING_SECONDS
	_last_from = wind.from_deg
	if _wd < 0.0:
		_wd = toward                         # (a new shift or the first frame: no swing)
	_wd = fposmod(_wd + wrapf(toward - _wd, -180.0, 180.0) * (1.0 - exp(-delta * 2.5)), 360.0)
	_gust_t = maxf(_gust_t - delta, 0.0)
	if not on:
		return
	_sway_t += delta
	var strength := wind.strength()
	var dir := Vector2(sin(deg_to_rad(_wd)), -cos(deg_to_rad(_wd)))
	var speed := lerpf(0.19, 0.55, strength)        # 20-60 px/s
	var bright := 1.0 + clampf(_gust_t / SWING_SECONDS, 0.0, 1.0)          # the streaks briefly double
	var th := atan2(-dir.y, dir.x)
	for i in STREAKS:
		_st_age[i] += delta
		if _st_age[i] >= _st_ttl[i]:
			_st_age[i] = 0.0
			_st_ttl[i] = _st_rng.randf_range(5.0, 9.0)
			_st_len[i] = _st_rng.randf_range(0.55, 1.1)
			_st_pos[i] = Vector2(_st_rng.randf_range(-5.0, 5.0), _st_rng.randf_range(-9.0, 9.0))
		_st_pos[i] += dir * speed * (0.8 + 0.4 * float(i % 3) / 2.0) * delta
		var u := _st_age[i] / _st_ttl[i]
		var a := 0.10 * bright * sin(PI * u)
		_st_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, th).scaled(Vector3(_st_len[i], 1.0, 1.0)), Vector3(_st_pos[i].x, 0.0, _st_pos[i].y)))
		_st_alpha[i] = a
		_st_mm.set_instance_color(i, Color(1, 1, 1, a))
	# the grass leans downwind (more the stronger it blows)
	var v := cur
	if v.tufts != null and not v.tuft_base.is_empty():
		var axis := Vector3(dir.y, 0.0, -dir.x)
		var lean := Basis(axis, deg_to_rad(8.0 + 16.0 * strength))
		var mm := v.tufts.multimesh
		for k in v.tuft_base.size():
			var tb := v.tuft_base[k]
			mm.set_instance_transform(k, Transform3D(lean * tb.basis, tb.origin))
	# the trees sway: a slow rock about a lean downwind, harder for a second after a shift
	var hard := 1.0 + 2.0 * clampf(_gust_t / 1.0, 0.0, 1.0)
	var lean_t := deg_to_rad(1.5 + 2.5 * strength)
	for st in 3:
		for holder in v.tree_styles[st]:
			var ph: float = holder.position.x * 1.7 + holder.position.z * 0.9
			var ang := lean_t + deg_to_rad(1.6 * (0.4 + strength)) * hard * sin(_sway_t * 1.9 + ph)
			holder.basis = Basis(Vector3(dir.y, 0.0, -dir.x), ang)
	# the pond ripples
	if not v.pond.is_empty():
		var r: float = v.pond["r"]
		var c: Vector2 = v.pond["center"]
		for rp in v.pond["ripples"]:
			rp["t"] = fposmod(float(rp["t"]) + delta * 0.3, 1.0)
			var t: float = rp["t"]
			var mi: MeshInstance3D = rp["node"]
			var off: Vector2 = rp["off"]
			var pp := c + off + dir * t * 0.25 * r
			mi.position = Vector3(pp.x, 0.04, pp.y)
			mi.scale = Vector3(r * 0.9 * t + 0.02, 0.1, r * 0.55 * t + 0.02)
			Prim.paint(rp["mat"] as StandardMaterial3D, Color(1, 1, 1, snappedf(0.5 * (1.0 - t) * minf(t * 6.0, 1.0), 0.02)))
