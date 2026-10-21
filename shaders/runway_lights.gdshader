shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Runway edge lights (steady, a gentle shimmer) and the approach strobe (a white flash that runs towards the runway).
// Per instance colour: r = phase 0..1 along the strobe line, g = 1 for a strobe light, 0 for an edge light.

void fragment() {
	float strobe = pow(max(0.0, sin(TIME * 6.0 - COLOR.r * 6.2832)), 8.0);
	float edge = 0.8 + 0.2 * sin(TIME * 2.0 + COLOR.r * 20.0);
	float v = mix(edge, 0.15 + 1.1 * strobe, COLOR.g);
	ALBEDO = mix(vec3(1.0, 0.92, 0.7), vec3(1.0, 1.0, 1.0), COLOR.g) * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
