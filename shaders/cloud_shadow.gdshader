shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;
// A cloud's shadow on the ground: a small, lumpy, soft-edged dark shape (the shadow colour at about 12%), never a white veil.
// A flat quad lying over the field, drawn as a few overlapping blobs; the edge is a short falloff so the shape reads crisply.

uniform float alpha = 0.12;
uniform vec3 tint : source_color = vec3(0.231, 0.29, 0.42);
uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i) + seed;
		vec2 c = vec2(sin(fi * 2.3) * 0.4, cos(fi * 1.7) * 0.25);
		float r = 0.5 + 0.1 * sin(fi * 3.1);
		d = max(d, 1.0 - length((p - c) / vec2(r * 1.4, r)));
	}
	ALBEDO = tint;
	ALPHA = alpha * smoothstep(0.0, 0.25, d);
}
