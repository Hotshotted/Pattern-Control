shader_type spatial;
// The same inverted-hull outline as outline_part.gdshader, but in the transparent pass (blend_mix, alpha 1), so it
// is drawn after the fog together with the aircraft / runway it belongs to.
render_mode unshaded, cull_front, blend_mix;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float thickness = 0.07;

void vertex() {
	vec3 v = VERTEX + sign(VERTEX) * thickness;
	vec3 world = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = 1.0;
}
