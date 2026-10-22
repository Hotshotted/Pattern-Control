shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A soft round drop shadow lying on the ground under a prop (a tree, a hangar, the tower): ink at low alpha, fading out at the rim.

uniform float alpha = 0.2;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = 1.0 - length(p);
	ALBEDO = vec3(0.02, 0.04, 0.08);
	ALPHA = alpha * smoothstep(0.0, 0.55, d);
}
