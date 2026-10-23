class_name Models
extends RefCounted
## Cozy Airfield: the little buildings, vehicles and scenery of the field, built once from soft shaded boxes and cylinders (no
## outlines; see Prim for the shading and Shadow for the shadows). Every builder takes a parent and a position on the ground
## and returns the node it made. Buildings are drawn as a block with a darker 4 px side on the right and bottom.

const SIDE := 0.04
const RUST := Color("e2654a")
const TEAL := Color("4fb8b2")
const CREAM := Color("fff2dc")
const NAVY := Color("1f3358")

static func _m(c: Color) -> StandardMaterial3D:
	return Prim.mat(c)

static func _box(p: Node3D, size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	return Prim.box(p, size, at, _m(c), false)

static func _cyl(p: Node3D, top_r: float, bottom_r: float, h: float, sides: int, at: Vector3, c: Color) -> MeshInstance3D:
	return Prim.cyl(p, top_r, bottom_r, h, sides, at, _m(c), false)

## A soft shadow cast toward the lower-right by something `h` high with footprint (fw, fd) centred on `at` (x, z) in `parent`.
static func cast(parent: Node3D, at: Vector2, fw: float, fd: float, h: float, y: float = 0.02, alpha: float = 1.0) -> void:
	var len := h * 0.5
	var k := 0.7071
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2((fw + len * k) / 0.62, (fd + len * k) / 0.62)
	mi.mesh = pm
	mi.material_override = Shadow.material(Shadow.rect(), alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(at.x + len * k * 0.5, y, at.y + len * k * 0.5)
	parent.add_child(mi)
	Shadow.register(mi, Vector2(len * k * 0.5, len * k * 0.5))

## A round soft shadow (trees, tanks, the balloon).
static func blob(parent: Node3D, at: Vector2, w: float, d: float, y: float = 0.02, alpha: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	mi.mesh = pm
	mi.material_override = Shadow.material(Shadow.disc(), alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(at.x, y, at.y)
	parent.add_child(mi)
	return mi

## A building block: the top face and a darker 4 px side on its right and bottom.
static func block(p: Node3D, size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	_box(p, size, at + Vector3(SIDE, -0.012, SIDE), c.darkened(0.38))
	return _box(p, size, at, c)

## The hangar: walls, a rust roof with a lighter ridge line, and an open door on the south side.
static func hangar(p: Node3D, at: Vector2, s: float = 1.0, roof: Color = RUST, wall: Color = Color("e8e1d2")) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	var w := 1.3 * s
	var d := 0.95 * s
	cast(n, Vector2.ZERO, w, d, 0.5 * s, 0.03)
	block(n, Vector3(w, 0.4, d), Vector3(0, 0.2, 0), wall)
	block(n, Vector3(w + 0.08, 0.06, d + 0.08), Vector3(0, 0.43, 0), roof)
	_box(n, Vector3(w + 0.08, 0.03, 0.06), Vector3(0, 0.47, 0), roof.lightened(0.3))                           # the ridge
	for k in [-1.0, 1.0]:
		_box(n, Vector3(w + 0.06, 0.012, 0.025), Vector3(0, 0.465, k * d * 0.26), roof.darkened(0.2))      # roof seams
	_box(n, Vector3(w * 0.62, 0.34, 0.05), Vector3(0, 0.19, d * 0.5 + 0.03), Color("3a2c2a"))              # the open door
	_box(n, Vector3(w * 0.62, 0.012, 0.16), Vector3(0, 0.012, d * 0.5 + 0.13), Color("d9d3c8"))            # the lit floor showing through it
	return n

## The FBO: teal roof, cream porch with two posts.
static func fbo(p: Node3D, at: Vector2, s: float = 1.0, roof: Color = TEAL, wall: Color = Color("efe6d3")) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	var w := 1.0 * s
	var d := 0.7 * s
	cast(n, Vector2.ZERO, w, d, 0.4 * s, 0.03)
	block(n, Vector3(w, 0.3, d), Vector3(0, 0.15, 0), wall)
	block(n, Vector3(w + 0.06, 0.05, d + 0.06), Vector3(0, 0.33, 0), roof)
	_box(n, Vector3(w + 0.06, 0.025, 0.05), Vector3(0, 0.36, 0), roof.lightened(0.3))
	block(n, Vector3(w * 0.5, 0.03, 0.2 * s), Vector3(0, 0.3, d * 0.5 + 0.12 * s), CREAM)
	for k in [-1.0, 1.0]:
		_box(n, Vector3(0.03, 0.28, 0.03), Vector3(k * w * 0.22, 0.14, d * 0.5 + 0.2 * s), Color("cdbfa4"))
	return n

## The tower: a cream building and shaft, a navy cab with a lighter roof, and a red beacon. Returns the beacon's material.
static func tower(p: Node3D, at: Vector2, beacon_out: Array = []) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	cast(n, Vector2.ZERO, 0.8, 0.7, 1.5, 0.05)
	block(n, Vector3(0.84, 0.44, 0.7), Vector3(0, 0.22, 0), CREAM)
	_cyl(n, 0.15, 0.19, 0.8, 8, Vector3(0, 0.84, 0), Color("f3e4c8"))
	_cyl(n, 0.36, 0.3, 0.24, 8, Vector3(0, 1.36, 0), NAVY)
	_cyl(n, 0.42, 0.42, 0.05, 8, Vector3(0, 1.52, 0), Color("f3e4c8"))
	_cyl(n, 0.3, 0.34, 0.05, 8, Vector3(0, 1.58, 0), Color("7a8fb8"))
	var beacon := _m(Color("e03a30"))
	beacon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon.emission_enabled = true
	beacon.emission = Color("ff3b30")
	beacon.emission_energy_multiplier = 0.0
	Prim.cyl(n, 0.06, 0.08, 0.1, 8, Vector3(0, 1.67, 0), beacon, false)
	beacon_out.append(beacon)
	return n

## A small light plane standing still (parked, chocked, or being washed), white with the livery on nose, wingtips and fin.
static func parked_plane(p: Node3D, at: Vector2, yaw_deg: float, accent: Color, s: float = 0.8, chocks: bool = true) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	n.rotation.y = deg_to_rad(yaw_deg)
	p.add_child(n)
	var white := Color("f6f8fc")
	var k := s
	var fus := _cyl(n, 0.11 * k, 0.11 * k, 0.9 * k, 8, Vector3(0, 0.16, 0), white)
	fus.rotation.x = deg_to_rad(90.0)
	var nose := _cyl(n, 0.0, 0.11 * k, 0.28 * k, 8, Vector3(0, 0.16, -0.58 * k), accent)
	nose.rotation.x = deg_to_rad(-90.0)
	_box(n, Vector3(0.12 * k, 0.07 * k, 0.2 * k), Vector3(0, 0.24, -0.2 * k), Color("2b4a7a"))
	_box(n, Vector3(1.3 * k, 0.04, 0.26 * k), Vector3(0, 0.2, -0.05 * k), white)
	for sx in [-1.0, 1.0]:
		_box(n, Vector3(0.14 * k, 0.045, 0.26 * k), Vector3(sx * 0.6 * k, 0.2, -0.05 * k), accent)
	_box(n, Vector3(0.5 * k, 0.035, 0.16 * k), Vector3(0, 0.17, 0.45 * k), white)
	_box(n, Vector3(0.04, 0.22 * k, 0.18 * k), Vector3(0, 0.27, 0.45 * k), accent)
	for sx in [-1.0, 1.0]:
		_cyl(n, 0.035, 0.035, 0.03, 6, Vector3(sx * 0.18 * k, 0.04, -0.2 * k), Color("2a2d36")).rotation.z = deg_to_rad(90.0)
	cast(n, Vector2(0, 0), 1.3 * k, 0.9 * k, 0.28, 0.025, 0.9)
	if chocks:
		for sx in [-1.0, 1.0]:
			_box(n, Vector3(0.05, 0.04, 0.03), Vector3(sx * 0.18 * k, 0.02, -0.2 * k - 0.07), Color("2a2a2e"))
	return n

## A plane being washed: the parked plane in a puddle with a hose coiled beside it.
static func washed_plane(p: Node3D, at: Vector2, yaw_deg: float, accent: Color, s: float = 0.8) -> Node3D:
	var n := parked_plane(p, at, yaw_deg, accent, s, false)
	var puddle := _cyl(n, 0.34, 0.34, 0.01, 14, Vector3(0.05, 0.012, 0.3), Color("86bddb"))
	puddle.scale = Vector3(1.0, 1.0, 0.7)
	var hose := Color("2f6f86")
	for i in 4:
		_box(n, Vector3(0.05, 0.02, 0.2), Vector3(0.45 + i * 0.07, 0.02, 0.1 + i * 0.14), hose).rotation.y = deg_to_rad(20.0 + i * 15.0)
	_cyl(n, 0.045, 0.05, 0.1, 6, Vector3(0.7, 0.05, 0.62), Color("e8b04a"))
	return n

## A tie-down: a cream T painted on the apron (the stem points at the plane's nose).
static func tie_down(p: Node3D, at: Vector2, yaw_deg: float = 0.0) -> void:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	n.rotation.y = deg_to_rad(yaw_deg)
	p.add_child(n)
	var c := Color("f2ede4")
	_box(n, Vector3(0.05, 0.012, 0.4), Vector3(0, 0.03, 0), c)
	_box(n, Vector3(0.26, 0.012, 0.05), Vector3(0, 0.03, -0.2), c)

## A fenced fuel farm: two white tanks inside a square of cream rails.
static func fuel_farm(p: Node3D, at: Vector2, s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	var w := 0.95 * s
	_box(n, Vector3(w, 0.012, w), Vector3(0, 0.014, 0), Color("c3bfae"))
	var h := w * 0.5
	for z in [-h, h]:
		_box(n, Vector3(w, 0.05, 0.03), Vector3(0, 0.05, z), Color("efe6d3"))
	for x in [-h, h]:
		_box(n, Vector3(0.03, 0.05, w), Vector3(x, 0.05, 0), Color("efe6d3"))
	for k in [-1.0, 1.0]:
		var at_t := Vector2(k * 0.2 * s, 0.0)
		blob(n, at_t + Vector2(0.1, 0.1), 0.62 * s, 0.62 * s, 0.025, 0.9)
		_cyl(n, 0.17 * s, 0.17 * s, 0.26, 12, Vector3(at_t.x, 0.15, at_t.y), Color("f4f1ea"))
		_cyl(n, 0.13 * s, 0.14 * s, 0.03, 12, Vector3(at_t.x, 0.285, at_t.y), Color("d9d4c6"))
		_box(n, Vector3(0.2 * s, 0.03, 0.04), Vector3(at_t.x, 0.3, at_t.y), Color("e24b3b"))
	return n

## The fuel truck (a red cab, a yellow tank), pointing along -z.
static func fuel_truck(p: Node3D) -> Node3D:
	var n := Node3D.new()
	p.add_child(n)
	_box(n, Vector3(0.16, 0.09, 0.26), Vector3(0, 0.1, 0.07), Color("f2c23a"))
	_cyl(n, 0.075, 0.075, 0.24, 8, Vector3(0, 0.17, 0.07), Color("f6d35e")).rotation.x = deg_to_rad(90.0)
	_box(n, Vector3(0.15, 0.1, 0.1), Vector3(0, 0.11, -0.12), Color("d9402f"))
	_box(n, Vector3(0.11, 0.03, 0.04), Vector3(0, 0.14, -0.16), Color("2b4a7a"))
	for z in [-0.1, 0.16]:
		for sx in [-1.0, 1.0]:
			_cyl(n, 0.03, 0.03, 0.03, 6, Vector3(sx * 0.085, 0.04, z), Color("2a2d36")).rotation.z = deg_to_rad(90.0)
	blob(n, Vector2(0.06, 0.06), 0.4, 0.5, 0.03, 0.8)
	return n

## A small car, pointing along -z.
static func car(p: Node3D, at: Vector2, yaw_deg: float, c: Color) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	n.rotation.y = deg_to_rad(yaw_deg)
	p.add_child(n)
	_box(n, Vector3(0.17, 0.06, 0.3), Vector3(0, 0.05, 0), c)
	_box(n, Vector3(0.13, 0.05, 0.15), Vector3(0, 0.1, 0.02), c.lightened(0.18))
	_box(n, Vector3(0.11, 0.02, 0.05), Vector3(0, 0.125, -0.04), Color("2b4a7a"))
	blob(n, Vector2(0.04, 0.04), 0.42, 0.5, 0.02, 0.8)
	return n

## A small car park: a slab with painted bays and a few cars.
static func car_lot(p: Node3D, at: Vector2, s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	var w := 0.86 * s
	var d := 0.52 * s
	_box(n, Vector3(w, 0.014, d), Vector3(0, 0.026, 0), Color("858b96"))
	for i in 5:
		_box(n, Vector3(0.012, 0.012, d * 0.9), Vector3(-w * 0.5 + 0.03 + i * (w - 0.06) / 4.0, 0.036, 0), Color("f2ede4"))
	var cols := [Color("d9533f"), Color("4c8fd6"), Color("f2c23a"), Color("f4f1ea")]
	for i in 4:
		if i == 2:
			continue
		car(n, Vector2(-w * 0.5 + 0.03 + (i + 0.5) * (w - 0.06) / 4.0, 0.0) * 1.0, (i * 7) % 5 - 2.0, cols[i]).position.y = 0.03
	return n

## A picnic table with a bench each side, and a dog lying beside it.
static func picnic(p: Node3D, at: Vector2) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	blob(n, Vector2(0.06, 0.06), 0.6, 0.5, 0.04, 0.8)
	_box(n, Vector3(0.3, 0.03, 0.17), Vector3(0, 0.14, 0), Color("a8723f"))
	for z in [-0.13, 0.13]:
		_box(n, Vector3(0.3, 0.025, 0.05), Vector3(0, 0.1, z), Color("8f5f34"))
	var dog := Node3D.new()
	dog.position = Vector3(0.28, 0.07, 0.06)
	dog.rotation.y = deg_to_rad(-30.0)
	n.add_child(dog)
	_box(dog, Vector3(0.07, 0.05, 0.13), Vector3(0, 0.03, 0), Color("d9a066"))
	_box(dog, Vector3(0.055, 0.05, 0.055), Vector3(0, 0.04, -0.09), Color("c98c52"))
	_box(dog, Vector3(0.02, 0.02, 0.06), Vector3(0.0, 0.035, 0.09), Color("d9a066")).rotation.y = deg_to_rad(25.0)
	return n

## The red barn with its white-roofed silo, and a run of fence in front of them.
static func barn(p: Node3D, at: Vector2) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	cast(n, Vector2.ZERO, 1.0, 0.7, 0.55, 0.03)
	block(n, Vector3(1.0, 0.4, 0.7), Vector3(0, 0.2, 0), Color("b8352b"))
	block(n, Vector3(1.06, 0.06, 0.76), Vector3(0, 0.43, 0), Color("8f3a2e"))
	_box(n, Vector3(1.06, 0.03, 0.06), Vector3(0, 0.47, 0), Color("c9654f"))
	_box(n, Vector3(0.3, 0.3, 0.04), Vector3(0, 0.17, 0.37), Color("f4eadb"))
	blob(n, Vector2(0.9, 0.1), 0.7, 0.7, 0.03, 1.0)
	_cyl(n, 0.2, 0.2, 0.78, 12, Vector3(0.82, 0.39, -0.05), Color("f1ece0"))
	_cyl(n, 0.0, 0.2, 0.14, 12, Vector3(0.82, 0.85, -0.05), Color("9aa3b0"))
	for i in 7:
		_box(n, Vector3(0.03, 0.12, 0.03), Vector3(-0.75 + i * 0.28, 0.06, 0.62), Color("efe6d3"))
	_box(n, Vector3(1.7, 0.02, 0.02), Vector3(0.0, 0.1, 0.62), Color("efe6d3"))
	return n

## A glider on its trailer: the long white fuselage, its wings laid alongside, a dark trailer with two wheels.
static func glider_trailer(p: Node3D, at: Vector2, yaw_deg: float) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	n.rotation.y = deg_to_rad(yaw_deg)
	p.add_child(n)
	blob(n, Vector2(0.06, 0.06), 0.5, 1.5, 0.02, 0.8)
	_box(n, Vector3(0.2, 0.03, 1.2), Vector3(0, 0.06, 0), Color("4a505c"))
	_cyl(n, 0.07, 0.04, 1.0, 6, Vector3(0, 0.14, 0), Color("f6f8fc")).rotation.x = deg_to_rad(90.0)
	for sx in [-1.0, 1.0]:
		_box(n, Vector3(0.08, 0.025, 1.0), Vector3(sx * 0.1, 0.12, 0.05), Color("eef2f8"))
		_cyl(n, 0.045, 0.045, 0.03, 8, Vector3(sx * 0.12, 0.045, 0.2), Color("2a2d36")).rotation.z = deg_to_rad(90.0)
	_box(n, Vector3(0.04, 0.03, 0.3), Vector3(0, 0.05, -0.7), Color("4a505c"))
	return n

## The PAPI lights beside a touchdown zone: four lamps, two white and two red.
static func papi(p: Node3D, at: Vector2, outward: float) -> void:
	for i in 4:
		var c := Color("f8f4ea") if i < 2 else Color("e2483b")
		var m := _m(c)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.5
		Prim.cyl(p, 0.045, 0.05, 0.07, 8, Vector3(at.x + outward * i * 0.14, 0.05, at.y), m, false)

## A hot-air balloon (red and cream gores, a basket) at height `y`, drawn under the aircraft; its big soft shadow is a separate node.
static func balloon(p: Node3D) -> Node3D:
	var n := Node3D.new()
	p.add_child(n)
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.7
	sphere.radial_segments = 16
	sphere.rings = 8
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for i in verts.size():
		var a := atan2(verts[i].z, verts[i].x)
		var gore := int(floor((a + PI) / TAU * 8.0)) % 2
		var f := 1.0 - 0.2 * clampf((verts[i].x + verts[i].z) / 0.68 * 0.5 + 0.5, 0.0, 1.0)
		var c := Color("e0483a") if gore == 0 else Color("fff0d8")
		cols[i] = Color(c.r * f, c.g * f, c.b * f, 1.0)
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := _m(Color.WHITE)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = -5
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var bm := _m(Color("a8723f"))
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.no_depth_test = true
	bm.render_priority = -4
	var basket := Prim.box(n, Vector3(0.12, 0.08, 0.12), Vector3(0.0, 0.22, 0.0), bm, false)
	basket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

## A bird: two little wings that flap by scaling. Returns the node; its two wing meshes are children 0 and 1.
static func bird(p: Node3D, c: Color = Color("3a3f4c")) -> Node3D:
	var n := Node3D.new()
	p.add_child(n)
	for sx in [-1.0, 1.0]:
		var w := _box(n, Vector3(0.1, 0.01, 0.05), Vector3(sx * 0.05, 0.0, 0.0), c)
		w.rotation.y = deg_to_rad(-sx * 20.0)
	_box(n, Vector3(0.035, 0.015, 0.09), Vector3(0, 0.0, 0.0), c)
	return n

## A ride-on mower, pointing along -z.
static func mower(p: Node3D) -> Node3D:
	var n := Node3D.new()
	p.add_child(n)
	_box(n, Vector3(0.2, 0.07, 0.24), Vector3(0, 0.07, 0), Color("d9402f"))
	_box(n, Vector3(0.24, 0.03, 0.12), Vector3(0, 0.035, -0.12), Color("a8302a"))
	_box(n, Vector3(0.08, 0.05, 0.08), Vector3(0, 0.13, 0.05), Color("3a3f4c"))
	blob(n, Vector2(0.05, 0.05), 0.5, 0.5, 0.03, 0.8)
	return n

## The lighthouse (coastal): a white tower with two red bands, a gallery and a lantern whose lamp blinks (its material goes into `lamp_out`).
static func lighthouse(p: Node3D, at: Vector2, lamp_out: Array = []) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	cast(n, Vector2.ZERO, 0.5, 0.5, 1.6, 0.03)
	_cyl(n, 0.3, 0.34, 0.1, 10, Vector3(0, 0.05, 0), Color("c9b896"))
	_cyl(n, 0.2, 0.27, 0.5, 10, Vector3(0, 0.35, 0), Color("f6f3ea"))
	_cyl(n, 0.17, 0.2, 0.3, 10, Vector3(0, 0.75, 0), Color("e2483b"))
	_cyl(n, 0.14, 0.17, 0.3, 10, Vector3(0, 1.05, 0), Color("f6f3ea"))
	_cyl(n, 0.12, 0.14, 0.2, 10, Vector3(0, 1.3, 0), Color("e2483b"))
	_cyl(n, 0.2, 0.2, 0.04, 10, Vector3(0, 1.43, 0), Color("4a5a6a"))
	var lamp := _m(Color("ffe9a0"))
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.emission_enabled = true
	lamp.emission = Color("ffe9a0")
	lamp.emission_energy_multiplier = 0.0
	Prim.cyl(n, 0.09, 0.09, 0.12, 8, Vector3(0, 1.51, 0), lamp, false)
	_cyl(n, 0.0, 0.14, 0.1, 8, Vector3(0, 1.62, 0), Color("e2483b"))
	lamp_out.append(lamp)
	return n

## A short wooden pier running along +x from `at`, with posts, and gulls on it.
static func pier(p: Node3D, at: Vector2, length: float = 1.3) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	blob(n, Vector2(length * 0.5 + 0.06, 0.06), length + 0.5, 0.7, 0.02, 0.9)
	_box(n, Vector3(length, 0.04, 0.32), Vector3(length * 0.5, 0.07, 0), Color("a8723f"))
	for i in 5:
		_box(n, Vector3(0.02, 0.045, 0.32), Vector3(0.12 + i * length / 5.0, 0.085, 0), Color("8a5a30"))
	for i in 3:
		for sz in [-1.0, 1.0]:
			_box(n, Vector3(0.05, 0.12, 0.05), Vector3(0.1 + i * length * 0.45, 0.03, sz * 0.17), Color("6b4a2a"))
	for g in 3:
		gull(n, Vector2(0.3 + g * 0.38, (g % 2) * 0.1 - 0.05), 0.08)
	return n

## A gull standing (or, scaled up in the air, flying): white body, grey wings.
static func gull(p: Node3D, at: Vector2, y: float) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, y, at.y)
	p.add_child(n)
	_box(n, Vector3(0.05, 0.04, 0.09), Vector3(0, 0, 0), Color("fbfaf6"))
	_box(n, Vector3(0.12, 0.012, 0.04), Vector3(0, 0.02, 0.01), Color("b8bfc9"))
	_box(n, Vector3(0.02, 0.02, 0.02), Vector3(0, 0.01, -0.055), Color("f0a23a"))
	return n

## The timber lodge (alpine): log walls, a dark red roof with a snow cap, a stone chimney. Chimney position goes in `chimney_out`.
static func lodge(p: Node3D, at: Vector2, chimney_out: Array = []) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	cast(n, Vector2.ZERO, 1.1, 0.75, 0.55, 0.03)
	block(n, Vector3(1.1, 0.36, 0.75), Vector3(0, 0.18, 0), Color("a8744a"))
	block(n, Vector3(1.18, 0.07, 0.83), Vector3(0, 0.4, 0), Color("8f3a2e"))
	_box(n, Vector3(1.18, 0.03, 0.06), Vector3(0, 0.45, 0), Color("c9654f"))
	for i in 3:
		_box(n, Vector3(0.28, 0.012, 0.3), Vector3(-0.38 + i * 0.38, 0.442, -0.22), Color("f4f6fa"))      # snow on the roof
	_box(n, Vector3(0.14, 0.34, 0.14), Vector3(0.38, 0.5, 0.18), Color("8a8f98"))
	_box(n, Vector3(0.18, 0.04, 0.18), Vector3(0.38, 0.69, 0.18), Color("6f747c"))
	_box(n, Vector3(0.3, 0.2, 0.04), Vector3(-0.2, 0.12, 0.39), Color("5a3a22"))
	chimney_out.append(Vector3(at.x + 0.38, 0.75, at.y + 0.18))
	return n

## A pine tree: three stacked cones on a trunk, with a soft shadow.
static func pine(p: Node3D, at: Vector2, s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	blob(n, Vector2(0.16 * s, 0.14 * s), 0.62 * s, 0.62 * s, 0.02, 1.0)
	_cyl(n, 0.03, 0.04, 0.12 * s, 5, Vector3(0, 0.06 * s, 0), Color("6b4a2a"))
	_cyl(n, 0.0, 0.26 * s, 0.34 * s, 8, Vector3(0, 0.26 * s, 0), Color("2f6b3c"))
	_cyl(n, 0.0, 0.2 * s, 0.3 * s, 8, Vector3(0, 0.44 * s, 0), Color("3f8048"))
	_cyl(n, 0.0, 0.14 * s, 0.24 * s, 8, Vector3(0, 0.6 * s, 0), Color("4f9657"))
	_cyl(n, 0.0, 0.06 * s, 0.08 * s, 8, Vector3(0, 0.72 * s, 0), Color("f4f6fa"))
	return n

## A chairlift line from `a` to `b`: two pylons, a cable, and two chairs (returned, to be moved along the cable).
static func chairlift(p: Node3D, a: Vector2, b: Vector2, chairs_out: Array = []) -> void:
	for q in [a, b]:
		_box(p, Vector3(0.05, 0.4, 0.05), Vector3(q.x, 0.2, q.y), Color("8a8f98"))
		_box(p, Vector3(0.32, 0.03, 0.04), Vector3(q.x, 0.4, q.y), Color("6f747c"))
		blob(p, Vector2(q.x + 0.1, q.y + 0.1), 0.4, 0.4, 0.02, 0.7)
	var mid := (a + b) * 0.5
	var d := b - a
	var cable := _box(p, Vector3(0.012, 0.012, d.length()), Vector3(mid.x, 0.4, mid.y), Color("3a3f4c"))
	cable.rotation.y = atan2(d.x, d.y)
	for k in 2:
		var ch := Node3D.new()
		p.add_child(ch)
		_box(ch, Vector3(0.03, 0.1, 0.03), Vector3(0, 0.34, 0), Color("3a3f4c"))
		_box(ch, Vector3(0.12, 0.03, 0.08), Vector3(0, 0.28, 0), Color("e2483b"))
		chairs_out.append(ch)

## A soft white patch of snow on the ground.
static func snow_patch(p: Node3D, at: Vector2, r: float) -> void:
	var m := _m(Color(1, 1, 1, 0.7))
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := Prim.cyl(p, r, r, 0.008, 12, Vector3(at.x, 0.016, at.y), m, false)
	mi.scale = Vector3(1.0, 1.0, 0.8)

## The wheel chocks of a parked plane (a node of its own, so they can appear once the plane has parked). `k` is the plane's scale.
static func chocks(p: Node3D, k: float) -> Node3D:
	var n := Node3D.new()
	p.add_child(n)
	for sx in [-1.0, 1.0]:
		_box(n, Vector3(0.05, 0.04, 0.03), Vector3(sx * 0.18 * k, 0.02, -0.2 * k - 0.07), Color("2a2a2e"))
	n.visible = false
	return n

## A parked helicopter: pale body, a tail boom, skids and a rotor (it is still).
static func parked_heli(p: Node3D, at: Vector2, accent: Color, k: float = 0.5) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.0, at.y)
	p.add_child(n)
	var white := Color("f6f8fc")
	_box(n, Vector3(0.34 * k * 2.0, 0.18 * k * 2.0, 0.5 * k * 2.0), Vector3(0, 0.16, 0), white)
	_box(n, Vector3(0.3 * k * 2.0, 0.09, 0.2 * k * 2.0), Vector3(0, 0.2, -0.22 * k * 2.0), Color("2b4a7a"))
	_box(n, Vector3(0.07 * k * 2.0, 0.07 * k * 2.0, 0.7 * k * 2.0), Vector3(0, 0.18, 0.55 * k * 2.0), accent)
	_box(n, Vector3(0.03, 0.14 * k * 2.0, 0.1 * k * 2.0), Vector3(0, 0.24, 0.9 * k * 2.0), accent)
	for sx in [-1.0, 1.0]:
		_box(n, Vector3(0.03, 0.02, 0.55 * k * 2.0), Vector3(sx * 0.2 * k * 2.0, 0.04, 0.0), Color("2a2d36"))
	_box(n, Vector3(1.5 * k * 2.0, 0.015, 0.06), Vector3(0, 0.3, 0), Color("c9cfda"))
	_box(n, Vector3(0.06, 0.015, 1.5 * k * 2.0), Vector3(0, 0.3, 0), Color("c9cfda"))
	cast(n, Vector2(0, 0.1), 1.2 * k * 2.0, 1.2 * k * 2.0, 0.28, 0.025, 0.9)
	return n
