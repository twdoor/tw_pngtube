shader_type canvas_item;
render_mode unshaded;

uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec2 child_to_mask_x = vec2(1.0, 0.0);
uniform vec2 child_to_mask_y = vec2(0.0, 1.0);
uniform vec2 child_to_mask_origin = vec2(0.0);
uniform vec2 mask_top_left = vec2(0.0);
uniform vec2 mask_size = vec2(1.0);
uniform vec2 mask_region_position = vec2(0.0);
uniform vec2 mask_region_size = vec2(1.0);
uniform vec2 mask_flip = vec2(0.0);
uniform float mask_opacity = 1.0;

varying vec2 mask_local_uv;

void vertex() {
	vec2 mask_position = (
		child_to_mask_x * VERTEX.x
		+ child_to_mask_y * VERTEX.y
		+ child_to_mask_origin
	);
	mask_local_uv = (mask_position - mask_top_left) / mask_size;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float inside = (
		step(0.0, mask_local_uv.x)
		* step(0.0, mask_local_uv.y)
		* step(mask_local_uv.x, 1.0)
		* step(mask_local_uv.y, 1.0)
	);
	vec2 sample_uv = mix(mask_local_uv, vec2(1.0) - mask_local_uv, mask_flip);
	vec2 atlas_uv = mask_region_position + sample_uv * mask_region_size;
	float allowed_alpha = texture(mask_texture, atlas_uv).a * inside * mask_opacity;
	source.a *= allowed_alpha;
	COLOR = source;
}
