shader_type canvas_item;
render_mode blend_premul_alpha;
// Cozy Airfield: one light over the whole field. A warm glow (#FFD68A, 35% at its centre) pinned to the upper-left corner, fading to
// nothing by 90% of the screen diagonal and added to the picture, and a cool shade (#2F4A7A, 20%) pinned to the lower-right that mixes
// over it. Nothing else: no grain, no texture. Everything is worked out in units of the screen's WIDTH (x 0..1, y 0..aspect), so no
// value is ever bigger than about 2: it is exact even in a phone's half-precision (mediump) fragment shaders.

uniform float aspect = 1.7778;                  // screen height / width
uniform vec4 warm : source_color = vec4(1.0, 0.8392, 0.5412, 1.0);
uniform vec4 cool : source_color = vec4(0.1843, 0.2902, 0.4784, 1.0);
uniform float warm_amount = 0.35;
uniform float cool_amount = 0.20;

void fragment() {
	vec2 p = vec2(UV.x, UV.y * aspect);
	float reach = 0.9 * length(vec2(1.0, aspect));
	float wa = warm_amount * (1.0 - smoothstep(0.0, 1.0, length(p) / reach));
	float ca = cool_amount * (1.0 - smoothstep(0.0, 1.0, length(vec2(1.0, aspect) - p) / reach));
	// premultiplied: the warm light mostly adds, the cool shade mixes over the picture
	vec3 rgb = warm.rgb * wa * 0.75 + cool.rgb * ca;
	float a = wa * 0.5 + ca * (1.0 - wa * 0.5);
	COLOR = vec4(rgb, a);
}
