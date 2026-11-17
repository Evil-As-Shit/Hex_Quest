shader_type canvas_item;
// Pixel-dissolve reveal. Each texture pixel gets a fixed random threshold; it is visible once
// `reveal` passes that threshold, so a sprite "pixels in" and (with reveal = 1.0) is exactly the
// normal sprite. Animate `reveal` from script (see Room.gd).

// 0.0 = fully hidden, 1.0 = fully visible.
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
// Size of each dissolving block, in texture pixels. 1 = single pixels, 2 = chunky 2x2, ...
uniform float block_size : hint_range(1.0, 8.0, 1.0) = 1.0;

// Cheap, GPU-stable hash (no sin(), which gives visible patterns / drifts on some GPUs).
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Hash on the texture pixel, so the pattern sticks to the art and doesn't swim when the camera moves.
	vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE / block_size);
	// hash is in [0, 1): reveal = 0 hides every pixel, reveal = 1 shows every pixel.
	if (hash12(texel) >= reveal) {
		COLOR.a = 0.0;
	}
	// Otherwise COLOR is left as Godot computed it, so modulate etc. still work.
}
