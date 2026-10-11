class_name TwberSpriteFrameSampler extends RefCounted

# Rendering adapter only. Both live and explicit playback supply clock states.
static func apply(nodes: Dictionary, states: Dictionary) -> void:
	for id: String in states:
		var sprite := nodes.get(id) as AnimatedSprite2D
		if sprite == null or sprite.sprite_frames == null:
			continue
		var state: Dictionary = states[id]
		var animation := StringName(state.animation)
		var frames := sprite.sprite_frames
		if not frames.has_animation(animation):
			continue
		var count := frames.get_frame_count(animation)
		if count == 0:
			continue
		sprite.pause()
		sprite.animation = animation
		var total := 0.0
		for index: int in count:
			total += frames.get_frame_duration(animation, index)
		var phase := maxf(float(state.phase), 0.0)
		if frames.get_animation_loop(animation):
			phase = fmod(phase, total) if total > 0.0 else 0.0
			if absf(phase - total) <= 0.000000001:
				phase = 0.0
		elif phase >= total - 0.000000001:
			sprite.set_frame_and_progress(count - 1, 1.0)
			continue
		for index: int in count:
			var duration := frames.get_frame_duration(animation, index)
			if phase < duration - 0.000000001 or index == count - 1:
				sprite.set_frame_and_progress(index, phase / duration if duration > 0.0 else 0.0)
				break
			phase = maxf(phase - duration, 0.0)
