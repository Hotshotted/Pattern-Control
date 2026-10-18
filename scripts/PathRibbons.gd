class_name PathRibbons
extends Node3D
## Draws every plane's flight path as a flat ribbon on the ground UNDER the planes (so a plane always
## reads on top), starting at the plane's nose and fading in over its first stretch. One pooled
## ImmediateMesh per plane, created once; each frame only rewrites its vertices.

const OUTLINE_Y := 0.2
const COLOR_Y := 0.21
const NOSE := [0.8, 0.95, 1.2]       # nose distance from the plane's centre, by model (speed class)

var traffic: Traffic
var last_start: Array[Vector2] = []  # per pooled plane: where its ribbon starts (the nose)
var last_alpha_near := PackedFloat32Array()   # opacity at the nose / at the far end, for the tests
var last_alpha_far := PackedFloat32Array()

var _meshes: Array[ImmediateMesh] = []       # the colour ribbon (+ its end dot) of each pooled plane
var _outlines: Array[ImmediateMesh] = []     # ...and its black outline, a second mesh drawn first
var _nodes: Array[MeshInstance3D] = []
var _outline_nodes: Array[MeshInstance3D] = []
var _pts := PackedVector2Array()     # scratch: nose + the remaining path
var _nrm := PackedVector2Array()
var _alpha := PackedFloat32Array()

func _ready() -> void:
	# Two materials with different render priorities: the outline is always drawn before the colour.
	var mat_outline := StandardMaterial3D.new()
	var mat := StandardMaterial3D.new()
	for m in [mat_outline, mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_outline.render_priority = -1
	mat.render_priority = 0
	_pts.resize(Aircraft.PATH_MAX + 2)
	_nrm.resize(Aircraft.PATH_MAX + 2)
	_alpha.resize(Aircraft.PATH_MAX + 2)
	for i in Traffic.MAX_POOL:
		var im := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = mat
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var om := ImmediateMesh.new()
		var omi := MeshInstance3D.new()
		omi.mesh = om
		omi.material_override = mat_outline
		omi.visible = false
		omi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(omi)
		_meshes.append(im)
		_nodes.append(mi)
		_outlines.append(om)
		_outline_nodes.append(omi)
		last_start.append(Vector2.ZERO)
		last_alpha_near.append(0.0)
		last_alpha_far.append(0.0)

func _process(_delta: float) -> void:
	if traffic == null:
		return
	for i in Traffic.MAX_POOL:
		var p := traffic.planes[i]
		if p.active() and p.count > 0:
			_build(p, i)
		elif _nodes[i].visible:
			_meshes[i].clear_surfaces()
			_outlines[i].clear_surfaces()
			_nodes[i].visible = false
			_outline_nodes[i].visible = false

func _build(p: Aircraft, i: int) -> void:
	var n := p.count
	var dir := Vector2(sin(p.vis_heading), -cos(p.vis_heading))
	_pts[0] = p.pos + dir * NOSE[p.speed_class]
	for k in n:
		_pts[k + 1] = p.pts[p.head + k]
	var m := n + 1
	last_start[i] = _pts[0]
	# Opacity grows with the distance along the path from the nose.
	var d := 0.0
	var fade := maxf(Tuning.path_fade_distance, 0.01)
	for k in m:
		if k > 0:
			d += _pts[k].distance_to(_pts[k - 1])
		_alpha[k] = lerpf(Tuning.path_fade_min, 1.0, smoothstep(0.0, fade, d))
		var a := _pts[maxi(k - 1, 0)]
		var b := _pts[mini(k + 1, m - 1)]
		var tan := b - a
		_nrm[k] = Vector2(-tan.y, tan.x).normalized() if tan.length_squared() > 0.000001 else Vector2(1, 0)
	last_alpha_near[i] = _alpha[0]
	last_alpha_far[i] = _alpha[m - 1]
	var col := Airports.rw_color(p.runway)
	if p.cleared:
		col = col.lerp(Color.WHITE, 0.25)
	var om := _outlines[i]
	om.clear_surfaces()
	_strip(om, m, Tuning.path_outline_width * 0.5, OUTLINE_Y, Color(0, 0, 0), 0.9)
	_dot(om, _pts[m - 1], Tuning.path_outline_width * 0.8, OUTLINE_Y, Color.BLACK, _alpha[m - 1])
	var im := _meshes[i]
	im.clear_surfaces()
	_strip(im, m, Tuning.path_width * 0.5, COLOR_Y, col, 1.0)
	_dot(im, _pts[m - 1], Tuning.path_width * 1.3, COLOR_Y, col, _alpha[m - 1])
	_nodes[i].visible = true
	_outline_nodes[i].visible = true

func _strip(im: ImmediateMesh, m: int, half: float, y: float, col: Color, a_mul: float) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in m:
		im.surface_set_color(Color(col.r, col.g, col.b, _alpha[k] * a_mul))
		var p := _pts[k]
		var nrm := _nrm[k] * half
		im.surface_add_vertex(Vector3(p.x - nrm.x, y, p.y - nrm.y))
		im.surface_add_vertex(Vector3(p.x + nrm.x, y, p.y + nrm.y))
	im.surface_end()

func _dot(im: ImmediateMesh, at: Vector2, r: float, y: float, col: Color, a: float) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(Color(col.r, col.g, col.b, a))
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		im.surface_add_vertex(Vector3(at.x, y, at.y))
		im.surface_add_vertex(Vector3(at.x + cos(a0) * r, y, at.y + sin(a0) * r))
		im.surface_add_vertex(Vector3(at.x + cos(a1) * r, y, at.y + sin(a1) * r))
	im.surface_end()
