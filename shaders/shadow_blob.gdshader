shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A soft drop shadow in the shape of a little aircraft lying on the ground: blue-grey #3B4A6B, its soft edge baked into `tex`
// (see Shadow.gd), so nothing is blurred at run time.

uniform sampler2D tex : filter_linear;
uniform float alpha = 0.26;

void fragment() {
	ALBEDO = vec3(0.2314, 0.2902, 0.4196);
	ALPHA = alpha * texture(tex, UV).a;
}
