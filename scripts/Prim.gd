class_name Prim
extends RefCounted
## Low-poly primitive helpers: every shape gets a black inverted-hull outline (shaders/outline_part.gdshader)
## as its material_overlay. Used at build time only: nothing here runs during a run.

## Sunny Airfield: aircraft carry a thin, soft slate outline (like the canvas' 45%-ink stroke); the ground and its props
## carry none (they get soft shadows and highlights instead), so the airfield builds with `outlines = false`.
const SOFT_OUTLINE := Color(0.32, 0.38, 0.5)
static var outlines := true
static var _outline: ShaderMaterial

## The one outline material shared by every shape.
static func outline() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = preload("res://shaders/outline_part.gdshader")
		_outline.set_shader_parameter("outline_color", SOFT_OUTLINE)
		_outline.set_shader_parameter("thickness", Tuning.outline_thickness)
	return _outline

static var _outline_top: ShaderMaterial

## The same outline for things that must be drawn above the fog (see lift()).
static func outline_top() -> ShaderMaterial:
	if _outline_top == null:
		_outline_top = ShaderMaterial.new()
		_outline_top.shader = preload("res://shaders/outline_part_top.gdshader")
		_outline_top.set_shader_parameter("outline_color", SOFT_OUTLINE)
		_outline_top.set_shader_parameter("thickness", Tuning.outline_thickness)
		_outline_top.render_priority = ABOVE_FOG
	return _outline_top

## Render priority of everything that sits above the fog (the fog layer draws at FogLayer.PRIORITY, far below).
const ABOVE_FOG := 2

## Move a node's meshes into the transparent pass, after the fog: their materials become "alpha with depth
## pre-pass" (they still look opaque and depth-sort correctly) at a priority above the fog layer, and the
## outlines switch to the transparent-pass outline. The ground and scenery are left alone, so only they are dimmed.
static func lift(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var m := mi.material_override as BaseMaterial3D
		if m != null:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.render_priority = ABOVE_FOG
		if mi.material_overlay != null:
			mi.material_overlay = outline_top()
	for c in node.get_children():
		lift(c)

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
	if outlined and outlines:
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
