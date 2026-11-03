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

varying vec2 world_px;

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 lit = texture(TEXTURE, UV);
	vec4 shade = texture(TEXTURE, UV + vec2(0.0, shade_v));
	// Hard edge. No smoothstep here, ever: the line between lit and unlit is
	// the composition.
	float s = step(0.5, texture(shadow_mask, (world_px - mask_origin) / level_px).r);
	COLOR = vec4(mix(lit.rgb, shade.rgb, s), lit.a);
}
