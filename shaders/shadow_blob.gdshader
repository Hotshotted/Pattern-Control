shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A soft drop shadow in the shape of a little aircraft (a fuselage and a wing), lying on the ground.

uniform float alpha = 0.3;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float fus = 1.0 - length(p / vec2(0.16, 0.95));
	float wng = 1.0 - length(p / vec2(0.95, 0.2));
	float tail = 1.0 - length((p - vec2(0.0, 0.75)) / vec2(0.35, 0.1));
	float d = max(max(fus, wng), tail);
	ALBEDO = vec3(0.02, 0.04, 0.08);
	ALPHA = alpha * smoothstep(0.0, 0.55, d);
}
