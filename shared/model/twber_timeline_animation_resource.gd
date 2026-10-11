class_name TwberTimelineAnimationResource extends Resource

@export var id := ""
@export var name := "Animation"
@export var duration := 1.0
@export var loop := true
@export var fps := 30.0
@export var priority := 0
@export var sprite_keys: Array[TwberSpriteKeyframeResource] = []
@export var parameter_keys: Array[TwberParameterKeyframeResource] = []
@export var keyframes: Array[TwberTimelineKeyframeResource] = []


func get_layer_ids() -> Array[String]:
	var seen := {}
	var output: Array[String] = []
	for keyframe: TwberTimelineKeyframeResource in keyframes:
		if keyframe == null or keyframe.layer_state == null:
			continue
		var layer_id := keyframe.layer_state.layer_id
		if layer_id.is_empty() or seen.has(layer_id):
			continue
		seen[layer_id] = true
		output.append(layer_id)
	for key: TwberSpriteKeyframeResource in sprite_keys:
		if key != null and not seen.has(key.layer_id):
			seen[key.layer_id] = true
			output.append(key.layer_id)
	return output


func get_keyframes_for_layer(layer_id: String) -> Array[TwberTimelineKeyframeResource]:
	var output: Array[TwberTimelineKeyframeResource] = []
	for keyframe: TwberTimelineKeyframeResource in keyframes:
		if (
			keyframe != null
			and keyframe.layer_state != null
			and keyframe.layer_state.layer_id == layer_id
		):
			output.append(keyframe)
	output.sort_custom(func(first: TwberTimelineKeyframeResource, second: TwberTimelineKeyframeResource) -> bool:
		return first.time < second.time
	)
	return output


func upsert_keyframe(keyframe: TwberTimelineKeyframeResource, tolerance := 0.0001) -> void:
	if keyframe == null or keyframe.layer_state == null:
		return
	for index: int in keyframes.size():
		var existing := keyframes[index]
		if (
			existing != null
			and existing.layer_state != null
			and existing.layer_state.layer_id == keyframe.layer_state.layer_id
			and absf(existing.time - keyframe.time) <= tolerance
		):
			keyframes[index] = keyframe
			return
	keyframes.append(keyframe)


func remove_keyframe(layer_id: String, key_time: float, tolerance := 0.0001) -> bool:
	for index: int in range(keyframes.size() - 1, -1, -1):
		var keyframe := keyframes[index]
		if (
			keyframe != null
			and keyframe.layer_state != null
			and keyframe.layer_state.layer_id == layer_id
			and absf(keyframe.time - key_time) <= tolerance
		):
			keyframes.remove_at(index)
			return true
	return false


func sample_layer(
		layer_id: String,
		time_position: float,
		base_state: TwberLayerStateResource = null,
) -> TwberLayerStateResource:
	return sample_track(get_keyframes_for_layer(layer_id), time_position, base_state)


static func sample_track(track: Array[TwberTimelineKeyframeResource], time_position: float, base_state: TwberLayerStateResource) -> TwberLayerStateResource:
	if track.is_empty():
		return null
	if track.size() == 1 or time_position <= track[0].time:
		return _materialize(track[0].layer_state, base_state)
	if time_position >= track[-1].time:
		return _materialize(track[-1].layer_state, base_state)

	for index: int in range(1, track.size()):
		var next_key := track[index]
		if time_position > next_key.time:
			continue
		var previous_key := track[index - 1]
		if time_position == next_key.time:
			return _materialize(next_key.layer_state, base_state)
		if previous_key.interpolation == TwberTimelineKeyframeResource.Interpolation.HOLD:
			return _materialize(previous_key.layer_state, base_state)
		var span := maxf(next_key.time - previous_key.time, 0.000001)
		var weight := clampf((time_position - previous_key.time) / span, 0.0, 1.0)
		return _interpolate_states(
				_materialize(previous_key.layer_state, base_state),
				_materialize(next_key.layer_state, base_state),
				weight,
		)
	return _materialize(track[-1].layer_state, base_state)


static func _materialize(
		state: TwberLayerStateResource,
		base_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	if state == null:
		return null
	var output: TwberLayerStateResource = (
		state.materialized(base_state) if base_state != null else state.duplicate(true)
	)
	# Neutral values supply interpolation endpoints, not channel ownership.
	# Applying a sparse track must leave unrelated parameter/track output alone.
	output.channels = state.channels
	return output


static func _interpolate_states(
		first: TwberLayerStateResource,
		second: TwberLayerStateResource,
		weight: float,
) -> TwberLayerStateResource:
	if first == null:
		return second
	if second == null:
		return first
	var output: TwberLayerStateResource = first.duplicate(true)
	output.channels = first.channels | second.channels
	output.position = first.position.lerp(second.position, weight)
	output.rotation = lerp_angle(first.rotation, second.rotation, weight)
	output.scale = first.scale.lerp(second.scale, weight)
	output.self_modulate = first.self_modulate.lerp(second.self_modulate, weight)
	output.visible = first.visible if weight < 0.5 else second.visible
	output.animation_name = first.animation_name if weight < 0.5 else second.animation_name
	output.animation_frame_rate = lerpf(
			first.animation_frame_rate,
			second.animation_frame_rate,
			weight,
	)
	if first.mesh_vertices.size() == second.mesh_vertices.size():
		output.mesh_vertices.resize(first.mesh_vertices.size())
		for index: int in first.mesh_vertices.size():
			output.mesh_vertices[index] = first.mesh_vertices[index].lerp(
					second.mesh_vertices[index],
					weight,
			)
	return output



func copy_contents_from(source: TwberTimelineAnimationResource) -> void:
	id = source.id
	name = source.name
	duration = source.duration
	loop = source.loop
	fps = source.fps
	priority = source.priority
	sprite_keys.clear()
	for key: TwberSpriteKeyframeResource in source.sprite_keys:
		sprite_keys.append(key.duplicate(true))
	parameter_keys.clear()
	for key: TwberParameterKeyframeResource in source.parameter_keys:
		parameter_keys.append(key.duplicate(true))
	keyframes.clear()
	for key: TwberTimelineKeyframeResource in source.keyframes:
		keyframes.append(key.duplicate(true))
