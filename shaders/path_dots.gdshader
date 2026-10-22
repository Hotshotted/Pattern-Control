shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A flight path as a line of round dots: the ribbon's UV.x runs across it (0..1) and UV.y along it in dot periods.
// Colour and opacity come from the vertex colour (the runway's colour, tinted by approach quality near the end).

uniform float half_width = 0.1;     // half the ribbon width, in world units
uniform float period = 0.3;         // distance between dot centres
uniform float radius = 0.075;       // dot radius

void fragment() {
	vec2 q = vec2((UV.x - 0.5) * 2.0 * half_width, (fract(UV.y) - 0.5) * period);
	float d = length(q);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * (1.0 - smoothstep(radius - 0.012, radius + 0.012, d));
}
