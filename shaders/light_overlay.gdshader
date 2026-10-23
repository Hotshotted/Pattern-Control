shader_type canvas_item;
render_mode blend_premul_alpha;
// Cozy Airfield: one light over the whole field. A warm glow (#FFD68A, 35% at its centre) pinned to the upper-left corner, fading
// to nothing by 90% of the screen diagonal and added to the picture, a cool shade (#2F4A7A, 20%) pinned to the lower-right that
// mixes over it, and 8% static film grain from a tiled noise texture (the same every frame).

uniform sampler2D grain : repeat_enable, filter_nearest;
uniform vec2 view_size = vec2(1080.0, 1920.0);
uniform vec4 warm : source_color = vec4(1.0, 0.8392, 0.5412, 1.0);
uniform vec4 cool : source_color = vec4(0.1843, 0.2902, 0.4784, 1.0);
uniform float warm_amount = 0.35;
uniform float cool_amount = 0.20;
uniform float grain_amount = 0.08;
uniform float grain_tile = 128.0;

void fragment() {
	vec2 p = UV * view_size;
	float reach = 0.9 * length(view_size);
	float wa = warm_amount * (1.0 - smoothstep(0.0, 1.0, length(p) / reach));
	float ca = cool_amount * (1.0 - smoothstep(0.0, 1.0, length(view_size - p) / reach));
	// premultiplied: the warm light mostly adds, the cool shade mixes over the picture
	vec3 rgb = warm.rgb * wa * 0.75 + cool.rgb * ca;
	float a = wa * 0.5 + ca * (1.0 - wa * 0.5);
	float g = (texture(grain, p / grain_tile).r - 0.5) * 2.0 * grain_amount;
	if (g > 0.0) {
		rgb += vec3(g);
	} else {
		a = a + (1.0 - a) * (-g);
	}
	COLOR = vec4(rgb, a);
}
