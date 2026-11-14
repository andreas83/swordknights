// The cloth of a textured model, recoloured to a team without losing its
// texture (scripts/player/rigged_costume.gd).
//
// A generated model's cloth shares its texture with gold trim, steel and
// leather: the tunic's part carries the lion and the belt too. So the colour
// is moved per pixel, not per part: a pixel whose hue is near the cloth's own
// (`source_hue`) and that is saturated enough to be dyed cloth takes the
// tint's hue, and its saturation and value are scaled by the tint's over the
// cloth's mean, so a fold's shadow stays a shadow and a worn highlight stays a
// highlight. Everything else in the texture -- the trim, the lion, a strap --
// keeps its own colour. `amount` 0 is the texture as made.
//
// Colours are compared in linear space, where the shader samples them; the
// costume measures the cloth's mean hue, saturation and value the same way.
shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float normal_depth = 1.0;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float amount = 0.0;
uniform float source_hue = 0.6;
uniform float source_saturation = 0.6;
uniform float source_value = 0.4;
// How far round the hue circle from the cloth's hue a pixel still counts as
// the cloth, fully and then not at all.
uniform vec2 hue_reach = vec2(0.05, 0.1);

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb * albedo.rgb;
	vec3 hsv = rgb_to_hsv(base);
	float away = abs(fract(hsv.x - source_hue + 0.5) - 0.5);
	float cloth = (1.0 - smoothstep(hue_reach.x, hue_reach.y, away))
		* smoothstep(0.12, 0.25, hsv.y);
	vec3 want = rgb_to_hsv(tint.rgb);
	vec3 dyed = hsv_to_rgb(vec3(want.x,
		clamp(hsv.y * want.y / max(source_saturation, 0.05), 0.0, 1.0),
		clamp(hsv.z * want.z / max(source_value, 0.02), 0.0, 1.0)));
	ALBEDO = mix(base, dyed, cloth * amount);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
