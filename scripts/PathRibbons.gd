class_name PathRibbons
extends Node3D
## Draws every plane's flight path as a flat ribbon on the ground UNDER the planes (so a plane always
## reads on top), starting at the plane's nose and fading in over its first stretch. One pooled
## ImmediateMesh per plane, created once; each frame only rewrites its vertices.

const OUTLINE_Y := 0.2
const COLOR_Y := 0.21
const NOSE := [0.8, 0.95, 1.2]       # nose distance from the plane's centre, by model (speed class)
const HALF := 0.1                    # Sunny Airfield: a path is a line of round dots in the runway's colour
const PERIOD := 0.3                  # ...this far apart
const DOT_R := 0.075                 # ...of this radius
const SHADOW := Color(0.04, 0.06, 0.13)

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
var _dist := PackedFloat32Array()     # distance along the path of each vertex
var _tint_from := -1                 # first ribbon vertex of the tinted final segment (-1 = none)
var _tint_col := Color.WHITE
## Final-segment tint by predicted approach quality (green / yellow / red).
const TINTS := [Color("35c98a"), Color("ffc933"), Color("ff5c4d")]

func _ready() -> void:
	# Two materials with different render priorities: the soft shadow dots are always drawn before the colour dots.
	var shader := preload("res://shaders/path_dots.gdshader")
	var mat_outline := ShaderMaterial.new()
	var mat := ShaderMaterial.new()
	for m in [mat_outline, mat]:
		m.shader = shader
		m.set_shader_parameter("half_width", HALF)
		m.set_shader_parameter("period", PERIOD)
	mat.set_shader_parameter("radius", DOT_R)
	mat_outline.set_shader_parameter("radius", DOT_R * 1.35)
	mat_outline.render_priority = -1
	mat.render_priority = 0
	_dist.resize(Aircraft.PATH_MAX + 2)
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
		if p.active() and p.count > 0 and not p.fogged:
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
		_dist[k] = d
		var a := _pts[maxi(k - 1, 0)]
		var b := _pts[mini(k + 1, m - 1)]
		var tan := b - a
		_nrm[k] = Vector2(-tan.y, tan.x).normalized() if tan.length_squared() > 0.000001 else Vector2(1, 0)
	last_alpha_near[i] = _alpha[0]
	last_alpha_far[i] = _alpha[m - 1]
	var col := Airports.land_color(p.tkind, p.runway)
	if p.emergency:
		col = Color(1.0, 0.35, 0.3)
	if p.cleared:
		col = col.lerp(Color.WHITE, 0.25)
	var om := _outlines[i]
	om.clear_surfaces()
	var im := _meshes[i]
	im.clear_surfaces()
	if p.path_invalid:
		# The wind shifted and this path no longer ends on an open runway end: red dots.
		_tint_from = -1
		_strip(om, m, HALF, OUTLINE_Y, SHADOW, 0.28)
		_strip(im, m, HALF, COLOR_Y, Color(1.0, 0.36, 0.3), 1.0)
	else:
		_tint_from = _tint_start(p, m)
		_tint_col = TINTS[p.ga_band]
		_strip(om, m, HALF, OUTLINE_Y, SHADOW, 0.28)
		_dot(om, _pts[m - 1], DOT_R * 2.2, OUTLINE_Y, SHADOW, _alpha[m - 1] * 0.28)
		_strip(im, m, HALF, COLOR_Y, col, 1.0)
		_dot(im, _pts[m - 1], DOT_R * 1.7, COLOR_Y, _tint_col if _tint_from >= 0 else col, _alpha[m - 1])
	_nodes[i].visible = true
	_outline_nodes[i].visible = true

## For a cleared runway path: the first vertex of its final stretch (the last `tint_distance` of path up to the
## threshold). Everything from there to the end is drawn in the quality colour. -1 = no tint.
func _tint_start(p: Aircraft, m: int) -> int:
	if not p.cleared or not p.can_go_around() or m < 3:
		return -1
	var d := 0.0
	var k := m - 2                    # (the last vertex is the runway's far end)
	while k > 0 and d < Tuning.tint_distance:
		d += _pts[k].distance_to(_pts[k - 1])
		k -= 1
	return k

func _strip(im: ImmediateMesh, m: int, half: float, y: float, col: Color, a_mul: float) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in m:
		var c := _tint_col if (_tint_from >= 0 and k >= _tint_from and col != SHADOW) else col
		im.surface_set_color(Color(c.r, c.g, c.b, _alpha[k] * a_mul))
		var p := _pts[k]
		var nrm := _nrm[k] * half
		var v := _dist[k] / PERIOD
		im.surface_set_uv(Vector2(0.0, v))
		im.surface_add_vertex(Vector3(p.x - nrm.x, y, p.y - nrm.y))
		im.surface_set_uv(Vector2(1.0, v))
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
