shader_type spatial;
// Atmospheric fog: one big translucent quad over the field, drawn AFTER the opaque ground and scenery (which it
// dims) and BEFORE the aircraft, paths and runways (which are lifted into a later render priority, so they stay
// fully readable above it). The density is drifting value noise: soft waves that thicken and thin over time.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

uniform float amount : hint_range(0.0, 1.0) = 0.0;     // how much fog there is right now (0 = none)
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;
uniform vec2 drift = vec2(0.5, 0.3);                    // the way the waves roll (follows the wind)
uniform vec3 fog_color : source_color = vec3(0.78, 0.83, 0.9);

varying vec2 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = wpos * 0.16 + drift * TIME * 0.35;
	float n = vnoise(p) * 0.6 + vnoise(p * 2.3 + vec2(7.0, 3.0) - drift.yx * TIME * 0.2) * 0.3 + vnoise(p * 5.1 - drift * TIME * 0.3) * 0.1;
	float wave = 0.5 + 0.5 * sin(TIME * 0.45 + n * 5.0 + wpos.y * 0.22 - wpos.x * 0.12);   // thickening and thinning
	float d = smoothstep(0.12, 0.85, n * (0.6 + 0.6 * wave));
	ALBEDO = fog_color;
	ALPHA = amount * max_alpha * (0.35 + 0.65 * d);
}
