shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A round soft puff for contrails (one MultiMesh instance each: the instance colour carries the opacity).

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(1.0);
	ALPHA = COLOR.a * smoothstep(1.0, 0.15, d);
}
