class_name TwberLayerStateResource extends Resource

const UNSET_ANIMATION_FRAME_RATE := -1.0

enum Channel {
	POSITION = 1 << 0,
	ROTATION = 1 << 1,
	SCALE = 1 << 2,
	VISIBILITY = 1 << 3,
	COLOR = 1 << 4,
	MESH = 1 << 5,
	ANIMATION = 1 << 6,
	ANIMATION_FRAME_RATE = 1 << 7,
}

const ALL_CHANNELS := (
		Channel.POSITION
		| Channel.ROTATION
		| Channel.SCALE
		| Channel.VISIBILITY
		| Channel.COLOR
		| Channel.MESH
		| Channel.ANIMATION
		| Channel.ANIMATION_FRAME_RATE
)

@export var channels := ALL_CHANNELS
@export var layer_id := ""
@export var position := Vector2.ZERO
@export var rotation := 0.0
@export var scale := Vector2.ONE
@export var visible := true
@export var self_modulate := Color.WHITE
@export var mesh_vertices: PackedVector2Array = []
@export var animation_name := ""
@export var animation_frame_rate := UNSET_ANIMATION_FRAME_RATE


func capture_from_node(node: Node2D) -> void:
	if node == null:
		return

	channels = ALL_CHANNELS
	layer_id = String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	position = node.position
	rotation = node.rotation
	scale = node.scale
	visible = node.visible
	self_modulate = node.self_modulate
	mesh_vertices = PackedVector2Array()
	animation_name = ""
	animation_frame_rate = UNSET_ANIMATION_FRAME_RATE

	if node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		if mesh_sprite.mesh_data != null:
			mesh_vertices = mesh_sprite.mesh_data.vertices.duplicate()
	elif node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = node
		if animated_sprite.sprite_frames != null:
			var current_animation := animated_sprite.animation
			if animated_sprite.sprite_frames.has_animation(current_animation):
				animation_name = String(current_animation)
				var frame_rate := animated_sprite.sprite_frames.get_animation_speed(current_animation)
				if frame_rate >= 0.0:
					animation_frame_rate = frame_rate


func apply_to_node(node: Node2D) -> void:
	if node == null:
		return

	if has_channel(Channel.POSITION):
		node.position = position
	if has_channel(Channel.ROTATION):
		node.rotation = rotation
	if has_channel(Channel.SCALE):
		node.scale = scale
	if has_channel(Channel.VISIBILITY):
		node.visible = visible
	if has_channel(Channel.COLOR):
		node.self_modulate = self_modulate
	if has_channel(Channel.ANIMATION) or has_channel(Channel.ANIMATION_FRAME_RATE):
		_apply_animation_state(node)

	if node is not TwberMeshSprite2D:
		return

	var mesh_sprite: TwberMeshSprite2D = node
	if (
			mesh_sprite.mesh_data != null
			and has_channel(Channel.MESH)
			and not mesh_vertices.is_empty()
			and mesh_vertices.size() == mesh_sprite.mesh_data.vertices.size()
	):
		mesh_sprite.mesh_data.vertices = mesh_vertices.duplicate()
		mesh_sprite.sync_deformation()
	else:
		mesh_sprite.sync_visual_state()


func copy_from(other: TwberLayerStateResource) -> void:
	if other == null:
		return

	channels = other.channels
	layer_id = other.layer_id
	position = other.position
	rotation = other.rotation
	scale = other.scale
	visible = other.visible
	self_modulate = other.self_modulate
	mesh_vertices = other.mesh_vertices.duplicate()
	animation_name = other.animation_name
	animation_frame_rate = other.animation_frame_rate


func sanitize_mesh_vertices(base_state: TwberLayerStateResource) -> void:
	if not has_channel(Channel.MESH):
		mesh_vertices = PackedVector2Array()
		return
	if base_state == null or base_state.mesh_vertices.is_empty():
		mesh_vertices = PackedVector2Array()
		return
	if mesh_vertices.size() != base_state.mesh_vertices.size():
		mesh_vertices = base_state.mesh_vertices.duplicate()


func sanitize_animation_state(base_state: TwberLayerStateResource) -> void:
	# States saved before animation channels were introduced deserialize with the
	# sentinel values. Fill those missing fields from the layer's neutral state so
	# the legacy snapshot remains a complete, neutral contribution.
	if base_state == null:
		return
	if has_channel(Channel.ANIMATION) and animation_name.is_empty():
		animation_name = base_state.animation_name
	if has_channel(Channel.ANIMATION_FRAME_RATE) and animation_frame_rate < 0.0:
		animation_frame_rate = base_state.animation_frame_rate


func has_channel(channel: int) -> bool:
	return (channels & channel) != 0


func materialized(neutral_state: TwberLayerStateResource) -> TwberLayerStateResource:
	if neutral_state == null or channels == ALL_CHANNELS:
		return duplicate(true)

	var result: TwberLayerStateResource = neutral_state.duplicate(true)
	result.layer_id = layer_id
	if has_channel(Channel.POSITION):
		result.position = position
	if has_channel(Channel.ROTATION):
		result.rotation = rotation
	if has_channel(Channel.SCALE):
		result.scale = scale
	if has_channel(Channel.VISIBILITY):
		result.visible = visible
	if has_channel(Channel.COLOR):
		result.self_modulate = self_modulate
	if has_channel(Channel.MESH):
		result.mesh_vertices = mesh_vertices.duplicate()
	if has_channel(Channel.ANIMATION):
		result.animation_name = animation_name
	if has_channel(Channel.ANIMATION_FRAME_RATE):
		result.animation_frame_rate = animation_frame_rate
	result.channels = ALL_CHANNELS
	return result


static func from_layer_resource(layer: TwberLayerResource) -> TwberLayerStateResource:
	if layer == null:
		return null

	var state := TwberLayerStateResource.new()
	state.channels = ALL_CHANNELS
	state.layer_id = layer.id
	state.position = layer.position
	state.rotation = layer.rotation
	state.scale = layer.scale
	state.visible = layer.visible
	state.self_modulate = layer.modulate
	if layer.mesh != null:
		state.mesh_vertices = layer.mesh.vertices.duplicate()
	if layer.type == TwberLayerResource.LayerType.ANIMATED_SPRITE:
		state.animation_name = layer.current_animation
		for animation: TwberAnimationResource in layer.animations:
			if animation != null and animation.name == layer.current_animation:
				if animation.speed >= 0.0:
					state.animation_frame_rate = animation.speed
				break
	return state


static func isolate_contribution(
		base_state: TwberLayerStateResource,
		current_state: TwberLayerStateResource,
		other_parameters_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	# Binding happens while every parameter is being previewed. Subtract the
	# already-active parameters so this snapshot owns only the user's new edit.
	if current_state == null:
		return null
	if base_state == null or other_parameters_state == null:
		var fallback := TwberLayerStateResource.new()
		fallback.copy_from(current_state)
		return fallback

	var result := TwberLayerStateResource.new()
	result.channels = 0
	result.layer_id = current_state.layer_id
	if not current_state.position.is_equal_approx(other_parameters_state.position):
		result.channels |= Channel.POSITION
		result.position = base_state.position + current_state.position - other_parameters_state.position
	if not is_equal_approx(current_state.rotation, other_parameters_state.rotation):
		result.channels |= Channel.ROTATION
		result.rotation = base_state.rotation + angle_difference(
				other_parameters_state.rotation,
				current_state.rotation,
		)
	if not current_state.scale.is_equal_approx(other_parameters_state.scale):
		result.channels |= Channel.SCALE
		result.scale = base_state.scale + current_state.scale - other_parameters_state.scale
	if current_state.visible != other_parameters_state.visible:
		result.channels |= Channel.VISIBILITY
		result.visible = not base_state.visible
	if not current_state.self_modulate.is_equal_approx(other_parameters_state.self_modulate):
		result.channels |= Channel.COLOR
		result.self_modulate = (
				base_state.self_modulate
				+ current_state.self_modulate
				- other_parameters_state.self_modulate
		)
	if not _vertex_arrays_equal(current_state.mesh_vertices, other_parameters_state.mesh_vertices):
		result.channels |= Channel.MESH
		result.mesh_vertices = _isolate_mesh_vertices(
				base_state.mesh_vertices,
				current_state.mesh_vertices,
				other_parameters_state.mesh_vertices,
		)
	if current_state.animation_name != other_parameters_state.animation_name:
		result.channels |= Channel.ANIMATION
		result.animation_name = current_state.animation_name
	if not is_equal_approx(
			current_state.animation_frame_rate,
			other_parameters_state.animation_frame_rate,
	):
		result.channels |= Channel.ANIMATION_FRAME_RATE
		result.animation_frame_rate = current_state.animation_frame_rate
	return result


static func compose(
		base_state: TwberLayerStateResource,
		contributions: Array[TwberLayerStateResource],
) -> TwberLayerStateResource:
	# Stored states are complete snapshots for persistence and interpolation, but
	# they are evaluated as deltas from one shared base so parameters can coexist.
	if base_state == null:
		return null

	var result: TwberLayerStateResource = base_state.duplicate(true)
	var rotation_delta := 0.0
	var color_delta := Color(0.0, 0.0, 0.0, 0.0)
	var overrides_visibility := false

	for contribution: TwberLayerStateResource in contributions:
		if contribution == null or contribution.layer_id != base_state.layer_id:
			continue
		result.position += contribution.position - base_state.position
		rotation_delta += angle_difference(base_state.rotation, contribution.rotation)
		result.scale += contribution.scale - base_state.scale
		color_delta += contribution.self_modulate - base_state.self_modulate
		if contribution.visible != base_state.visible:
			overrides_visibility = true
		if (
				not contribution.animation_name.is_empty()
				and contribution.animation_name != base_state.animation_name
		):
			result.animation_name = contribution.animation_name
		if (
				contribution.animation_frame_rate >= 0.0
				and not is_equal_approx(
						contribution.animation_frame_rate,
						base_state.animation_frame_rate,
				)
		):
			result.animation_frame_rate = contribution.animation_frame_rate
		if (
				not base_state.mesh_vertices.is_empty()
				and contribution.mesh_vertices.size() == base_state.mesh_vertices.size()
		):
			for vertex_index: int in result.mesh_vertices.size():
				result.mesh_vertices[vertex_index] += (
						contribution.mesh_vertices[vertex_index]
						- base_state.mesh_vertices[vertex_index]
				)

	result.rotation = base_state.rotation + rotation_delta
	result.visible = not base_state.visible if overrides_visibility else base_state.visible
	result.self_modulate = Color(
			clampf(base_state.self_modulate.r + color_delta.r, 0.0, 1.0),
			clampf(base_state.self_modulate.g + color_delta.g, 0.0, 1.0),
			clampf(base_state.self_modulate.b + color_delta.b, 0.0, 1.0),
			clampf(base_state.self_modulate.a + color_delta.a, 0.0, 1.0),
	)

	return result


static func blend_weighted(
		states: Array[TwberLayerStateResource],
		weights: PackedFloat32Array,
) -> TwberLayerStateResource:
	var item_count := mini(states.size(), weights.size())
	var dominant_state: TwberLayerStateResource
	var dominant_weight := -INF

	for index: int in item_count:
		var state := states[index]
		var weight := float(weights[index])
		if state == null or weight <= 0.0:
			continue
		if weight > dominant_weight:
			dominant_state = state
			dominant_weight = weight

	if dominant_state == null:
		return null

	var total_weight := 0.0
	var blended_position := Vector2.ZERO
	var blended_scale := Vector2.ZERO
	var blended_color := Color(0.0, 0.0, 0.0, 0.0)
	var rotation_sine := 0.0
	var rotation_cosine := 0.0
	var can_blend_mesh := true
	var mesh_vertex_count := dominant_state.mesh_vertices.size()

	for index: int in item_count:
		var state := states[index]
		var weight := float(weights[index])
		if (
				state == null
				or weight <= 0.0
				or state.layer_id != dominant_state.layer_id
		):
			continue

		total_weight += weight
		blended_position += state.position * weight
		blended_scale += state.scale * weight
		blended_color += state.self_modulate * weight
		rotation_sine += sin(state.rotation) * weight
		rotation_cosine += cos(state.rotation) * weight
		if state.mesh_vertices.size() != mesh_vertex_count:
			can_blend_mesh = false

	if total_weight <= 0.0:
		return null

	var result := TwberLayerStateResource.new()
	result.layer_id = dominant_state.layer_id
	result.position = blended_position / total_weight
	result.rotation = atan2(rotation_sine, rotation_cosine)
	result.scale = blended_scale / total_weight
	result.visible = dominant_state.visible
	result.self_modulate = blended_color / total_weight
	result.animation_name = dominant_state.animation_name
	result.animation_frame_rate = dominant_state.animation_frame_rate

	if not can_blend_mesh or mesh_vertex_count == 0:
		# A stale topology cannot be interpolated safely. Leave the mesh channel
		# empty so applying/composing this sample treats it as a neutral no-op.
		result.mesh_vertices = PackedVector2Array()
		return result

	var blended_vertices := dominant_state.mesh_vertices.duplicate()
	for vertex_index: int in mesh_vertex_count:
		blended_vertices[vertex_index] = Vector2.ZERO

	for index: int in item_count:
		var state := states[index]
		var weight := float(weights[index])
		if (
				state == null
				or weight <= 0.0
				or state.layer_id != dominant_state.layer_id
		):
			continue
		for vertex_index: int in mesh_vertex_count:
			blended_vertices[vertex_index] += state.mesh_vertices[vertex_index] * weight

	for vertex_index: int in mesh_vertex_count:
		blended_vertices[vertex_index] /= total_weight
	result.mesh_vertices = blended_vertices
	return result


func _apply_animation_state(node: Node2D) -> void:
	if node is not AnimatedSprite2D:
		return

	var animated_sprite: AnimatedSprite2D = node
	if animated_sprite.sprite_frames == null or animation_name.is_empty():
		return

	var requested_animation := StringName(animation_name)
	if not animated_sprite.sprite_frames.has_animation(requested_animation):
		return

	if animation_frame_rate >= 0.0:
		animated_sprite.sprite_frames.set_animation_speed(
				requested_animation,
				animation_frame_rate,
		)

	if animated_sprite.animation == requested_animation:
		return

	# Switching an actively playing sprite should keep it playing, while applying
	# a state to a deliberately stopped sprite must not start it unexpectedly.
	if animated_sprite.is_playing():
		animated_sprite.play(requested_animation)
	else:
		animated_sprite.animation = requested_animation


static func _isolate_mesh_vertices(
		base_vertices: PackedVector2Array,
		current_vertices: PackedVector2Array,
		other_vertices: PackedVector2Array,
) -> PackedVector2Array:
	if (
			base_vertices.is_empty()
			or current_vertices.size() != base_vertices.size()
			or other_vertices.size() != base_vertices.size()
	):
		return base_vertices.duplicate()

	var output := base_vertices.duplicate()
	for index: int in output.size():
		output[index] += current_vertices[index] - other_vertices[index]
	return output


static func _vertex_arrays_equal(
		first: PackedVector2Array,
		second: PackedVector2Array,
) -> bool:
	if first.size() != second.size():
		return false
	for index: int in first.size():
		if not first[index].is_equal_approx(second[index]):
			return false
	return true
