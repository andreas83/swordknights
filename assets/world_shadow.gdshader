shader_type canvas_item;
render_mode unshaded;

// Picks a tile's lit or shaded face from the world shadow mask.
//
// The atlas is two halves in register: the shade twin of every tile is
// `shade_v` of the texture's height below it (tools/generate_tiles_png.py).
// So a surface going into shadow is not this surface darkened, it is the next
// tone down the duotone ramp -- which is the whole art direction, and it costs
// one extra texture fetch rather than a second pass over the tilemap.
//
// The mask is solved once per level on the CPU (scripts/render/sun_shadow.gd)
// and never touched again, so there is no per-frame shadow work at all: no
// ray-march, no render target, no light pass. This runs on GL compatibility.

uniform sampler2D shadow_mask : filter_nearest, repeat_disable, hint_default_black;
// Level size in world pixels; the mask covers exactly this rectangle.
uniform vec2 level_px = vec2(1.0, 1.0);
// Where that rectangle's top-left sits in the world. Zero for a level, which
// starts at the origin; a duel zone's mask starts a few columns west of it
// (scripts/duel/zones_view.gd).
uniform vec2 mask_origin = vec2(0.0, 0.0);
// Atlas rows to the shade half, as a fraction of the texture height.
uniform float shade_v = 0.5;

// A secret's stone going away (scripts/world/secret_view.gd). 0 is whole and
// is what every other layer leaves it at, so for them this is one untaken
// branch. Pixels drop out in an ordered dither, nearest `dissolve_from` first:
// hard pixels the whole way, no alpha ever, which is the art direction's rule
// for edges applied to time.
uniform float dissolve = 0.0;
uniform vec2 dissolve_from = vec2(0.0, 0.0);
uniform float dissolve_reach = 64.0;

// A multiply over the result, white unless a scene puts the world out for a
// while (WorldGrade.dim, the Eclipse's dark). This shader is unshaded and
// writes COLOR outright, so neither a node's modulate nor the canvas's
// CanvasModulate reaches the stone; a darkness that must fall on it comes in
// here. At white it is a multiply by exactly one: every other level is the
// same, pixel for pixel.
uniform vec4 tint : source_color = vec4(1.0);

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

varying vec2 world_px;

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (dissolve > 0.0) {
		vec2 px = floor(world_px);
		int index = int(mod(px.x, 4.0)) + int(mod(px.y, 4.0)) * 4;
		float order = (BAYER[index] + 0.5) / 16.0;
		float near = clamp(length(px - dissolve_from) / dissolve_reach, 0.0, 1.0);
		if (order + near * 0.75 < dissolve * 1.75) {
			discard;
		}
	}
	vec4 lit = texture(TEXTURE, UV);
	vec4 shade = texture(TEXTURE, UV + vec2(0.0, shade_v));
	// Hard edge. No smoothstep here, ever: the line between lit and unlit is
	// the composition.
	float s = step(0.5, texture(shadow_mask, (world_px - mask_origin) / level_px).r);
	COLOR = vec4(mix(lit.rgb, shade.rgb, s) * tint.rgb, lit.a);
}
