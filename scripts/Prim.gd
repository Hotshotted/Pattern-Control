class_name Prim
extends RefCounted
## Low-poly primitive helpers: every shape gets a black inverted-hull outline (shaders/outline_part.gdshader)
## as its material_overlay. Used at build time only: nothing here runs during a run.

static var _outline: ShaderMaterial

## The one outline material shared by every shape.
static func outline() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = preload("res://shaders/outline_part.gdshader")
		_outline.set_shader_parameter("outline_color", Color.BLACK)
		_outline.set_shader_parameter("thickness", Tuning.outline_thickness)
	return _outline

static func mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m

static func _finish(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, outlined: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	if outlined:
		mi.material_overlay = outline()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, outlined: bool = true) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _finish(parent, b, m, pos, outlined)

## A low-poly cylinder / cone (top_r = 0): `sides` radial segments, axis = local y.
static func cyl(parent: Node3D, top_r: float, bottom_r: float, height: float, sides: int, pos: Vector3, m: Material, outlined: bool = true) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return _finish(parent, c, m, pos, outlined)
