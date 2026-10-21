shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;
// A soft, lumpy cloud: a flat quad lying over the field, drawn as a few overlapping blobs.

uniform float alpha = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i) + seed;
		vec2 c = vec2(sin(fi * 2.3) * 0.45, cos(fi * 1.7) * 0.3);
		float r = 0.45 + 0.12 * sin(fi * 3.1);
		d = max(d, 1.0 - length((p - c) / vec2(r * 1.5, r)));
	}
	ALBEDO = tint;
	ALPHA = alpha * smoothstep(0.0, 0.55, d);
}
