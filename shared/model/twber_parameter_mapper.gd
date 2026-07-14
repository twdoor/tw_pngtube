class_name TwberParameterMapper extends RefCounted

const SAMPLE_EPSILON := 0.0001
const GEOMETRY_EPSILON := 0.000000000001


static func apply_parameter(
		model_root: Node,
		parameter: TwberParameterResource,
		value: Variant,
) -> Array[String]:
	if model_root == null or parameter == null:
		return []

	var parameters: Array[TwberParameterResource] = [parameter]
	return _apply_parameters_with_layer_nodes(
			parameters,
			{parameter.id: value},
			get_layer_nodes_by_id(model_root),
			"",
			true,
	)


static func apply_parameters(
		model_root: Node,
		parameters: Array[TwberParameterResource],
		parameter_values: Dictionary,
		excluded_parameter_id := "",
) -> Array[String]:
	if model_root == null:
		return []

	return apply_compiled_parameters(
		compile_parameters(parameters),
		parameter_values,
		get_layer_nodes_by_id(model_root),
		excluded_parameter_id,
	)


static func compile_parameters(parameters: Array[TwberParameterResource]) -> Dictionary:
	var entries: Array[Dictionary] = []
	var affected_layer_ids := {}
	for parameter: TwberParameterResource in parameters:
		if parameter == null or parameter.id.is_empty():
			continue

		var layers := {}
		for parameter_position: TwberParameterPositionResource in parameter.positions:
			if parameter_position == null:
				continue
			for layer_state: TwberLayerStateResource in parameter_position.layer_states:
				if layer_state == null or layer_state.layer_id.is_empty():
					continue
				if not layers.has(layer_state.layer_id):
					layers[layer_state.layer_id] = {"samples": []}
					affected_layer_ids[layer_state.layer_id] = true
				var layer_data: Dictionary = layers[layer_state.layer_id]
				var samples: Array = layer_data["samples"]
				var replaced := false
				for sample_index: int in samples.size():
					if parameter.coordinates_equal(
							samples[sample_index]["coordinate"],
							parameter_position.coordinate,
					):
						samples[sample_index] = {
							"coordinate": parameter_position.coordinate,
							"state": layer_state,
						}
						replaced = true
						break
				if not replaced:
					samples.append({
						"coordinate": parameter_position.coordinate,
						"state": layer_state,
					})

		var default_coordinate := parameter.coordinate_from_value(parameter.get_default_value())
		for layer_id: Variant in layers:
			var layer_data: Dictionary = layers[layer_id]
			var samples: Array = layer_data["samples"]
			var has_default := false
			for sample: Dictionary in samples:
				if parameter.coordinates_equal(sample["coordinate"], default_coordinate):
					has_default = true
					break
			if not has_default:
				samples.append({"coordinate": default_coordinate, "state": null})

			if parameter.value_type == TwberParameterResource.ValueType.VECTOR2:
				var points := PackedVector2Array()
				for sample: Dictionary in samples:
					points.append(sample["coordinate"])
				layer_data["points"] = points
				layer_data["triangles"] = (
						Geometry2D.triangulate_delaunay(points)
						if points.size() >= 3
						else PackedInt32Array()
				)
			else:
				samples.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
					return first["coordinate"].x < second["coordinate"].x
				)

		entries.append({"parameter": parameter, "layers": layers})

	return {
		"entries": entries,
		"affected_layer_ids": affected_layer_ids.keys(),
	}


static func apply_compiled_parameters(
		compiled_data: Dictionary,
		parameter_values: Dictionary,
		layer_nodes: Dictionary,
		excluded_parameter_id := "",
		neutral_states_by_layer_id: Dictionary = {},
		target_layer_ids: Dictionary = {},
) -> Array[String]:
	if not neutral_states_by_layer_id.is_empty():
		return _apply_compiled_parameters_with_neutral_states(
				compiled_data,
				parameter_values,
				layer_nodes,
				excluded_parameter_id,
				neutral_states_by_layer_id,
				target_layer_ids,
		)

	var applied_layer_ids: Array[String] = []
	var base_states := {}
	var contributions_by_layer := {}

	var entries: Array = compiled_data.get("entries", [])
	for entry: Dictionary in entries:
		var parameter: TwberParameterResource = entry.get("parameter") as TwberParameterResource
		if parameter == null:
			continue
		if not excluded_parameter_id.is_empty() and parameter.id == excluded_parameter_id:
			continue

		var value: Variant = parameter_values.get(parameter.id, parameter.get_default_value())
		var coordinate := parameter.coordinate_from_value(value)
		var layers: Dictionary = entry.get("layers", {})
		for layer_key: Variant in layers:
			var layer_id := String(layer_key)
			if not layer_nodes.has(layer_id):
				continue

			if not base_states.has(layer_id):
				var base_state := TwberLayerStateResource.new()
				base_state.capture_from_node(layer_nodes[layer_id] as Node2D)
				base_states[layer_id] = base_state
				contributions_by_layer[layer_id] = []

			var sampled_state := _sample_compiled_layer(
					parameter,
					coordinate,
					layers[layer_key],
					base_states[layer_id],
			)
			if sampled_state == null:
				continue

			var layer_contributions: Array = contributions_by_layer[layer_id]
			layer_contributions.append(sampled_state)
			if layer_contributions.size() == 1:
				applied_layer_ids.append(layer_id)

	for layer_id: String in applied_layer_ids:
		var contributions: Array[TwberLayerStateResource] = []
		for contribution: TwberLayerStateResource in contributions_by_layer[layer_id]:
			contributions.append(contribution)
		var composed_state := TwberLayerStateResource.compose(
				base_states[layer_id],
				contributions,
		)
		if composed_state != null:
			composed_state.apply_to_node(layer_nodes[layer_id] as Node2D)

	return applied_layer_ids


static func _apply_compiled_parameters_with_neutral_states(
		compiled_data: Dictionary,
		parameter_values: Dictionary,
		layer_nodes: Dictionary,
		excluded_parameter_id: String,
		neutral_states_by_layer_id: Dictionary,
		target_layer_ids: Dictionary,
) -> Array[String]:
	var scratch_states: Dictionary = compiled_data.get("evaluation_scratch", {})
	if not compiled_data.has("evaluation_scratch"):
		compiled_data["evaluation_scratch"] = scratch_states
	var results := {}
	var contributed := {}
	var applied_layer_ids: Array[String] = []

	# Initialize one reusable result per affected layer. A result starts at the
	# immutable neutral pose, then each parameter contributes its delta in place.
	for layer_key: Variant in compiled_data.get("affected_layer_ids", []):
		var layer_id := String(layer_key)
		if not target_layer_ids.is_empty() and not target_layer_ids.has(layer_id):
			continue
		var base_state := neutral_states_by_layer_id.get(layer_id) as TwberLayerStateResource
		if base_state == null or not layer_nodes.has(layer_id):
			continue
		var result := scratch_states.get(layer_id) as TwberLayerStateResource
		if result == null:
			result = TwberLayerStateResource.new()
			scratch_states[layer_id] = result
		_reset_state_from_base(result, base_state)
		results[layer_id] = result

	var entries: Array = compiled_data.get("entries", [])
	for entry: Dictionary in entries:
		var parameter: TwberParameterResource = entry.get("parameter") as TwberParameterResource
		if parameter == null:
			continue
		if not excluded_parameter_id.is_empty() and parameter.id == excluded_parameter_id:
			continue

		var value: Variant = parameter_values.get(parameter.id, parameter.get_default_value())
		var coordinate := parameter.coordinate_from_value(value)
		var layers: Dictionary = entry.get("layers", {})
		for layer_key: Variant in layers:
			var layer_id := String(layer_key)
			if not results.has(layer_id):
				continue
			var base_state: TwberLayerStateResource = neutral_states_by_layer_id[layer_id]
			var layer_data: Dictionary = layers[layer_key]
			var sampled_state := layer_data.get("evaluation_scratch") as TwberLayerStateResource
			if sampled_state == null:
				sampled_state = TwberLayerStateResource.new()
				layer_data["evaluation_scratch"] = sampled_state
			if not _sample_compiled_layer_into(
					parameter,
					coordinate,
					layer_data,
					base_state,
					sampled_state,
			):
				continue
			_accumulate_state_delta(results[layer_id], base_state, sampled_state)
			if not contributed.has(layer_id):
				contributed[layer_id] = true
				applied_layer_ids.append(layer_id)

	# Also apply untouched neutral results. This makes a bool parameter with no
	# active sample, or an excluded parameter, reset predictably without a
	# separate restore pass over the model tree.
	for layer_id: String in results:
		var result: TwberLayerStateResource = results[layer_id]
		result.self_modulate = Color(
				clampf(result.self_modulate.r, 0.0, 1.0),
				clampf(result.self_modulate.g, 0.0, 1.0),
				clampf(result.self_modulate.b, 0.0, 1.0),
				clampf(result.self_modulate.a, 0.0, 1.0),
		)
		result.apply_to_node(layer_nodes[layer_id] as Node2D)

	return applied_layer_ids


static func _reset_state_from_base(
		result: TwberLayerStateResource,
		base_state: TwberLayerStateResource,
) -> void:
	result.channels = TwberLayerStateResource.ALL_CHANNELS
	result.layer_id = base_state.layer_id
	result.position = base_state.position
	result.rotation = base_state.rotation
	result.scale = base_state.scale
	result.visible = base_state.visible
	result.self_modulate = base_state.self_modulate
	result.animation_name = base_state.animation_name
	result.animation_frame_rate = base_state.animation_frame_rate
	var reset_vertices := result.mesh_vertices
	result.mesh_vertices = PackedVector2Array()
	if reset_vertices.size() != base_state.mesh_vertices.size():
		reset_vertices.resize(base_state.mesh_vertices.size())
	for vertex_index: int in base_state.mesh_vertices.size():
		reset_vertices[vertex_index] = base_state.mesh_vertices[vertex_index]
	result.mesh_vertices = reset_vertices


static func _accumulate_state_delta(
		result: TwberLayerStateResource,
		base_state: TwberLayerStateResource,
		contribution: TwberLayerStateResource,
) -> void:
	if contribution.layer_id != base_state.layer_id:
		return
	result.position += contribution.position - base_state.position
	result.rotation += angle_difference(base_state.rotation, contribution.rotation)
	result.scale += contribution.scale - base_state.scale
	result.self_modulate += contribution.self_modulate - base_state.self_modulate
	if contribution.visible != base_state.visible:
		result.visible = not base_state.visible
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
			and result.mesh_vertices.size() == base_state.mesh_vertices.size()
	):
		var accumulated_vertices := result.mesh_vertices
		result.mesh_vertices = PackedVector2Array()
		for vertex_index: int in accumulated_vertices.size():
			accumulated_vertices[vertex_index] += (
					contribution.mesh_vertices[vertex_index]
					- base_state.mesh_vertices[vertex_index]
			)
		result.mesh_vertices = accumulated_vertices


static func _apply_parameters_with_layer_nodes(
		parameters: Array[TwberParameterResource],
		parameter_values: Dictionary,
		layer_nodes: Dictionary,
		excluded_parameter_id: String,
		allow_empty_parameter_id: bool,
) -> Array[String]:
	var applied_layer_ids: Array[String] = []
	var base_states := {}
	var contributions_by_layer := {}

	# Every parameter contribution must be measured from the same untouched layer
	# state. Delay applying anything until all samples have been collected.
	for parameter: TwberParameterResource in parameters:
		if parameter == null:
			continue
		if not allow_empty_parameter_id and parameter.id.is_empty():
			continue
		if (
				not excluded_parameter_id.is_empty()
				and parameter.id == excluded_parameter_id
		):
			continue

		var value: Variant = parameter_values.get(parameter.id, parameter.get_default_value())
		var coordinate := parameter.coordinate_from_value(value)
		for layer_id: String in _get_bound_layer_ids(parameter):
			if not layer_nodes.has(layer_id):
				continue

			if not base_states.has(layer_id):
				var base_state := TwberLayerStateResource.new()
				base_state.capture_from_node(layer_nodes[layer_id] as Node2D)
				base_states[layer_id] = base_state
				contributions_by_layer[layer_id] = []

			var sampled_state := sample_layer_state(
					parameter,
					coordinate,
					layer_id,
					base_states[layer_id],
			)
			if sampled_state == null:
				continue

			var layer_contributions: Array = contributions_by_layer[layer_id]
			layer_contributions.append(sampled_state)
			if layer_contributions.size() == 1:
				applied_layer_ids.append(layer_id)

	for layer_id: String in applied_layer_ids:
		var contributions: Array[TwberLayerStateResource] = []
		for contribution: TwberLayerStateResource in contributions_by_layer[layer_id]:
			contributions.append(contribution)

		var composed_state := TwberLayerStateResource.compose(
				base_states[layer_id],
				contributions,
		)
		if composed_state != null:
			composed_state.apply_to_node(layer_nodes[layer_id] as Node2D)

	return applied_layer_ids


static func sample_layer_state(
		parameter: TwberParameterResource,
		coordinate: Vector2,
		layer_id: String,
		neutral_state: TwberLayerStateResource = null,
) -> TwberLayerStateResource:
	if parameter == null or layer_id.is_empty():
		return null

	var samples: Array[Dictionary] = []
	for parameter_position: TwberParameterPositionResource in parameter.positions:
		if parameter_position == null:
			continue

		var layer_state := parameter_position.find_state(layer_id)
		if layer_state == null:
			continue
		var sampled_layer_state := layer_state.materialized(neutral_state)

		var replaced_duplicate := false
		for sample_index: int in samples.size():
			if parameter.coordinates_equal(samples[sample_index]["coordinate"], parameter_position.coordinate):
				samples[sample_index] = {
					"coordinate": parameter_position.coordinate,
					"state": sampled_layer_state,
				}
				replaced_duplicate = true
				break
		if not replaced_duplicate:
			samples.append({
				"coordinate": parameter_position.coordinate,
				"state": sampled_layer_state,
			})

	if samples.is_empty():
		return null

	if neutral_state != null:
		var default_coordinate := parameter.coordinate_from_value(parameter.get_default_value())
		var has_explicit_default_sample := false
		for sample: Dictionary in samples:
			if parameter.coordinates_equal(sample["coordinate"], default_coordinate):
				has_explicit_default_sample = true
				break
		if not has_explicit_default_sample:
			samples.append({
				"coordinate": default_coordinate,
				"state": neutral_state,
			})

	var clamped_coordinate := parameter.clamp_coordinate(coordinate)
	for sample: Dictionary in samples:
		if parameter.coordinates_equal(sample["coordinate"], clamped_coordinate):
			return _copy_state(sample["state"])

	match parameter.value_type:
		TwberParameterResource.ValueType.BOOL:
			return null
		TwberParameterResource.ValueType.VECTOR2:
			return _sample_vector(samples, clamped_coordinate)
		_:
			return _sample_scalar(samples, clamped_coordinate.x)


static func _sample_compiled_layer(
		parameter: TwberParameterResource,
		coordinate: Vector2,
		layer_data: Dictionary,
		neutral_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	var samples: Array = layer_data.get("samples", [])
	if samples.is_empty():
		return null

	var clamped_coordinate := parameter.clamp_coordinate(coordinate)
	for sample: Dictionary in samples:
		if parameter.coordinates_equal(sample["coordinate"], clamped_coordinate):
			return _resolve_compiled_state(sample, neutral_state)

	match parameter.value_type:
		TwberParameterResource.ValueType.BOOL:
			return null
		TwberParameterResource.ValueType.VECTOR2:
			return _sample_compiled_vector(samples, layer_data, clamped_coordinate, neutral_state)
		_:
			return _sample_compiled_scalar(samples, clamped_coordinate.x, neutral_state)


static func _sample_compiled_layer_into(
		parameter: TwberParameterResource,
		coordinate: Vector2,
		layer_data: Dictionary,
		neutral_state: TwberLayerStateResource,
		output: TwberLayerStateResource,
) -> bool:
	var samples: Array = layer_data.get("samples", [])
	if samples.is_empty():
		return false

	var clamped_coordinate := parameter.clamp_coordinate(coordinate)
	for sample_index: int in samples.size():
		if parameter.coordinates_equal(samples[sample_index]["coordinate"], clamped_coordinate):
			_resolve_compiled_state_into(samples[sample_index], neutral_state, output)
			return true

	match parameter.value_type:
		TwberParameterResource.ValueType.BOOL:
			return false
		TwberParameterResource.ValueType.VECTOR2:
			return _sample_compiled_vector_into(
					samples,
					layer_data,
					clamped_coordinate,
					neutral_state,
					output,
			)
		_:
			return _sample_compiled_scalar_into(
					samples,
					clamped_coordinate.x,
					neutral_state,
					output,
			)


static func _sample_compiled_scalar_into(
		samples: Array,
		scalar: float,
		neutral_state: TwberLayerStateResource,
		output: TwberLayerStateResource,
) -> bool:
	if samples.size() == 1 or scalar <= float(samples[0]["coordinate"].x):
		_resolve_compiled_state_into(samples[0], neutral_state, output)
		return true
	if scalar >= float(samples[samples.size() - 1]["coordinate"].x):
		_resolve_compiled_state_into(samples[samples.size() - 1], neutral_state, output)
		return true

	for index: int in samples.size() - 1:
		var first_value := float(samples[index]["coordinate"].x)
		var second_value := float(samples[index + 1]["coordinate"].x)
		if scalar > second_value:
			continue
		var weight := inverse_lerp(first_value, second_value, scalar)
		return _blend_compiled_indices_into(
				samples,
				index,
				1.0 - weight,
				index + 1,
				weight,
				-1,
				0.0,
				neutral_state,
				output,
		)

	_resolve_compiled_state_into(samples[samples.size() - 1], neutral_state, output)
	return true


static func _sample_compiled_vector_into(
		samples: Array,
		layer_data: Dictionary,
		coordinate: Vector2,
		neutral_state: TwberLayerStateResource,
		output: TwberLayerStateResource,
) -> bool:
	if samples.size() == 1:
		_resolve_compiled_state_into(samples[0], neutral_state, output)
		return true
	if samples.size() == 2:
		var segment_weight := _get_segment_weight(
				samples[0]["coordinate"],
				samples[1]["coordinate"],
				coordinate,
		)
		return _blend_compiled_indices_into(
				samples,
				0,
				1.0 - segment_weight,
				1,
				segment_weight,
				-1,
				0.0,
				neutral_state,
				output,
		)

	var points: PackedVector2Array = layer_data.get("points", PackedVector2Array())
	var triangles: PackedInt32Array = layer_data.get("triangles", PackedInt32Array())
	var closest_edge := Vector2i(-1, -1)
	var closest_edge_weight := 0.0
	var closest_distance_squared := INF
	for triangle_start: int in range(0, triangles.size() - 2, 3):
		var first_index := int(triangles[triangle_start])
		var second_index := int(triangles[triangle_start + 1])
		var third_index := int(triangles[triangle_start + 2])
		var weights := _get_barycentric_weights(
				coordinate,
				points[first_index],
				points[second_index],
				points[third_index],
		)
		if not weights.is_empty() and _weights_are_inside_triangle(weights):
			return _blend_compiled_indices_into(
					samples,
					first_index,
					weights[0],
					second_index,
					weights[1],
					third_index,
					weights[2],
					neutral_state,
					output,
			)

		for edge: Vector2i in [
			Vector2i(first_index, second_index),
			Vector2i(second_index, third_index),
			Vector2i(third_index, first_index),
		]:
			var edge_weight := _get_segment_weight(points[edge.x], points[edge.y], coordinate)
			var closest_point := points[edge.x].lerp(points[edge.y], edge_weight)
			var distance_squared := coordinate.distance_squared_to(closest_point)
			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_edge = edge
				closest_edge_weight = edge_weight

	if closest_edge.x >= 0:
		return _blend_compiled_indices_into(
				samples,
				closest_edge.x,
				1.0 - closest_edge_weight,
				closest_edge.y,
				closest_edge_weight,
				-1,
				0.0,
				neutral_state,
				output,
		)

	var nearest := Vector2i(-1, -1)
	var nearest_distances := Vector2(INF, INF)
	for index: int in samples.size():
		var distance := coordinate.distance_squared_to(samples[index]["coordinate"])
		if distance < nearest_distances.x:
			nearest.y = nearest.x
			nearest_distances.y = nearest_distances.x
			nearest.x = index
			nearest_distances.x = distance
		elif distance < nearest_distances.y:
			nearest.y = index
			nearest_distances.y = distance
	if nearest.x < 0:
		return false
	if nearest.y < 0:
		_resolve_compiled_state_into(samples[nearest.x], neutral_state, output)
		return true
	var nearest_weight := _get_segment_weight(
			samples[nearest.x]["coordinate"],
			samples[nearest.y]["coordinate"],
			coordinate,
	)
	return _blend_compiled_indices_into(
			samples,
			nearest.x,
			1.0 - nearest_weight,
			nearest.y,
			nearest_weight,
			-1,
			0.0,
			neutral_state,
			output,
	)


static func _resolve_compiled_state_into(
		sample: Dictionary,
		neutral_state: TwberLayerStateResource,
		output: TwberLayerStateResource,
) -> void:
	var sparse := sample.get("state") as TwberLayerStateResource
	output.channels = TwberLayerStateResource.ALL_CHANNELS
	output.layer_id = neutral_state.layer_id
	output.position = (
			sparse.position
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.POSITION)
			else neutral_state.position
	)
	output.rotation = (
			sparse.rotation
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.ROTATION)
			else neutral_state.rotation
	)
	output.scale = (
			sparse.scale
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.SCALE)
			else neutral_state.scale
	)
	output.visible = (
			sparse.visible
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.VISIBILITY)
			else neutral_state.visible
	)
	output.self_modulate = (
			sparse.self_modulate
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.COLOR)
			else neutral_state.self_modulate
	)
	output.animation_name = (
			sparse.animation_name
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.ANIMATION)
			else neutral_state.animation_name
	)
	output.animation_frame_rate = (
			sparse.animation_frame_rate
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.ANIMATION_FRAME_RATE)
			else neutral_state.animation_frame_rate
	)
	var source_vertices := neutral_state.mesh_vertices
	if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.MESH):
		source_vertices = sparse.mesh_vertices
	var output_vertices := output.mesh_vertices
	output.mesh_vertices = PackedVector2Array()
	if output_vertices.size() != source_vertices.size():
		output_vertices.resize(source_vertices.size())
	for vertex_index: int in source_vertices.size():
		output_vertices[vertex_index] = source_vertices[vertex_index]
	output.mesh_vertices = output_vertices


static func _blend_compiled_indices_into(
		samples: Array,
		first_index: int,
		first_weight: float,
		second_index: int,
		second_weight: float,
		third_index: int,
		third_weight: float,
		neutral_state: TwberLayerStateResource,
		output: TwberLayerStateResource,
) -> bool:
	var total_weight := 0.0
	var blended_position := Vector2.ZERO
	var blended_scale := Vector2.ZERO
	var blended_color := Color(0.0, 0.0, 0.0, 0.0)
	var rotation_sine := 0.0
	var rotation_cosine := 0.0
	var dominant_sparse: TwberLayerStateResource
	var dominant_weight := -INF
	var mesh_vertex_count := neutral_state.mesh_vertices.size()
	var can_blend_mesh := mesh_vertex_count > 0
	var blended_vertices := output.mesh_vertices
	output.mesh_vertices = PackedVector2Array()
	if blended_vertices.size() != mesh_vertex_count:
		blended_vertices.resize(mesh_vertex_count)
	for vertex_index: int in blended_vertices.size():
		blended_vertices[vertex_index] = Vector2.ZERO

	for slot: int in 3:
		var sample_index: int
		var weight: float
		match slot:
			0:
				sample_index = first_index
				weight = first_weight
			1:
				sample_index = second_index
				weight = second_weight
			_:
				sample_index = third_index
				weight = third_weight
		if sample_index < 0 or sample_index >= samples.size() or weight <= 0.0:
			continue
		var sparse := samples[sample_index].get("state") as TwberLayerStateResource
		if sparse != null and sparse.layer_id != neutral_state.layer_id:
			continue
		if weight > dominant_weight:
			dominant_weight = weight
			dominant_sparse = sparse
		total_weight += weight
		var position := (
				sparse.position
				if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.POSITION)
				else neutral_state.position
		)
		var rotation := (
				sparse.rotation
				if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.ROTATION)
				else neutral_state.rotation
		)
		var scale := (
				sparse.scale
				if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.SCALE)
				else neutral_state.scale
		)
		var color := (
				sparse.self_modulate
				if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.COLOR)
				else neutral_state.self_modulate
		)
		blended_position += position * weight
		blended_scale += scale * weight
		blended_color += color * weight
		rotation_sine += sin(rotation) * weight
		rotation_cosine += cos(rotation) * weight

		if can_blend_mesh:
			var mesh_vertices := neutral_state.mesh_vertices
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.MESH):
				mesh_vertices = sparse.mesh_vertices
			if mesh_vertices.size() != mesh_vertex_count:
				can_blend_mesh = false
			else:
				for vertex_index: int in mesh_vertex_count:
					blended_vertices[vertex_index] += mesh_vertices[vertex_index] * weight

	if total_weight <= 0.0 or dominant_weight == -INF:
		output.mesh_vertices = blended_vertices
		return false

	output.channels = TwberLayerStateResource.ALL_CHANNELS
	output.layer_id = neutral_state.layer_id
	output.position = blended_position / total_weight
	output.rotation = atan2(rotation_sine, rotation_cosine)
	output.scale = blended_scale / total_weight
	output.self_modulate = blended_color / total_weight
	output.visible = (
			dominant_sparse.visible
			if dominant_sparse != null and dominant_sparse.has_channel(TwberLayerStateResource.Channel.VISIBILITY)
			else neutral_state.visible
	)
	output.animation_name = (
			dominant_sparse.animation_name
			if dominant_sparse != null and dominant_sparse.has_channel(TwberLayerStateResource.Channel.ANIMATION)
			else neutral_state.animation_name
	)
	output.animation_frame_rate = (
			dominant_sparse.animation_frame_rate
			if dominant_sparse != null and dominant_sparse.has_channel(TwberLayerStateResource.Channel.ANIMATION_FRAME_RATE)
			else neutral_state.animation_frame_rate
	)
	if can_blend_mesh:
		for vertex_index: int in mesh_vertex_count:
			blended_vertices[vertex_index] /= total_weight
	else:
		blended_vertices.resize(0)
	output.mesh_vertices = blended_vertices
	return true


static func _sample_compiled_scalar(
		samples: Array,
		scalar: float,
		neutral_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	if samples.size() == 1 or scalar <= float(samples[0]["coordinate"].x):
		return _resolve_compiled_state(samples[0], neutral_state)
	if scalar >= float(samples[samples.size() - 1]["coordinate"].x):
		return _resolve_compiled_state(samples[samples.size() - 1], neutral_state)

	for index: int in samples.size() - 1:
		var first: Dictionary = samples[index]
		var second: Dictionary = samples[index + 1]
		var first_value := float(first["coordinate"].x)
		var second_value := float(second["coordinate"].x)
		if scalar > second_value:
			continue
		var weight := inverse_lerp(first_value, second_value, scalar)
		return _blend_compiled_samples(
				[first, second],
				PackedFloat32Array([1.0 - weight, weight]),
				neutral_state,
		)

	return _resolve_compiled_state(samples[samples.size() - 1], neutral_state)


static func _sample_compiled_vector(
		samples: Array,
		layer_data: Dictionary,
		coordinate: Vector2,
		neutral_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	if samples.size() == 1:
		return _resolve_compiled_state(samples[0], neutral_state)
	if samples.size() == 2:
		return _blend_compiled_segment(samples, 0, 1, coordinate, neutral_state)

	var points: PackedVector2Array = layer_data.get("points", PackedVector2Array())
	var triangles: PackedInt32Array = layer_data.get("triangles", PackedInt32Array())
	var closest_edge := Vector2i(-1, -1)
	var closest_edge_weight := 0.0
	var closest_distance_squared := INF

	for triangle_start: int in range(0, triangles.size() - 2, 3):
		var first_index := int(triangles[triangle_start])
		var second_index := int(triangles[triangle_start + 1])
		var third_index := int(triangles[triangle_start + 2])
		var weights := _get_barycentric_weights(
				coordinate,
				points[first_index],
				points[second_index],
				points[third_index],
		)
		if not weights.is_empty() and _weights_are_inside_triangle(weights):
			return _blend_compiled_samples(
					[samples[first_index], samples[second_index], samples[third_index]],
					weights,
					neutral_state,
			)

		for edge: Vector2i in [
			Vector2i(first_index, second_index),
			Vector2i(second_index, third_index),
			Vector2i(third_index, first_index),
		]:
			var edge_weight := _get_segment_weight(points[edge.x], points[edge.y], coordinate)
			var closest_point := points[edge.x].lerp(points[edge.y], edge_weight)
			var distance_squared := coordinate.distance_squared_to(closest_point)
			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_edge = edge
				closest_edge_weight = edge_weight

	if closest_edge.x >= 0:
		return _blend_compiled_samples(
				[samples[closest_edge.x], samples[closest_edge.y]],
				PackedFloat32Array([1.0 - closest_edge_weight, closest_edge_weight]),
				neutral_state,
		)

	var nearest := Vector2i(-1, -1)
	var nearest_distances := Vector2(INF, INF)
	for index: int in samples.size():
		var distance := coordinate.distance_squared_to(samples[index]["coordinate"])
		if distance < nearest_distances.x:
			nearest.y = nearest.x
			nearest_distances.y = nearest_distances.x
			nearest.x = index
			nearest_distances.x = distance
		elif distance < nearest_distances.y:
			nearest.y = index
			nearest_distances.y = distance
	if nearest.y < 0:
		return _resolve_compiled_state(samples[nearest.x], neutral_state)
	return _blend_compiled_segment(samples, nearest.x, nearest.y, coordinate, neutral_state)


static func _blend_compiled_segment(
		samples: Array,
		first_index: int,
		second_index: int,
		coordinate: Vector2,
		neutral_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	var weight := _get_segment_weight(
			samples[first_index]["coordinate"],
			samples[second_index]["coordinate"],
			coordinate,
	)
	return _blend_compiled_samples(
			[samples[first_index], samples[second_index]],
			PackedFloat32Array([1.0 - weight, weight]),
			neutral_state,
	)


static func _blend_compiled_samples(
		samples: Array,
		weights: PackedFloat32Array,
		neutral_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	var item_count := mini(samples.size(), weights.size())
	var dominant_index := -1
	var dominant_weight := -INF
	var total_weight := 0.0
	var blended_position := Vector2.ZERO
	var blended_scale := Vector2.ZERO
	var blended_color := Color(0.0, 0.0, 0.0, 0.0)
	var rotation_sine := 0.0
	var rotation_cosine := 0.0
	var mesh_vertex_count := neutral_state.mesh_vertices.size()
	var can_blend_mesh := mesh_vertex_count > 0
	var blended_vertices := PackedVector2Array()
	if can_blend_mesh:
		blended_vertices.resize(mesh_vertex_count)

	for index: int in item_count:
		var weight := float(weights[index])
		if weight <= 0.0:
			continue
		var sparse: TwberLayerStateResource = samples[index].get("state") as TwberLayerStateResource
		if sparse != null and sparse.layer_id != neutral_state.layer_id:
			continue
		if weight > dominant_weight:
			dominant_weight = weight
			dominant_index = index
		total_weight += weight

		var position := neutral_state.position
		var scale := neutral_state.scale
		var color := neutral_state.self_modulate
		var rotation := neutral_state.rotation
		if sparse != null:
			if sparse.has_channel(TwberLayerStateResource.Channel.POSITION):
				position = sparse.position
			if sparse.has_channel(TwberLayerStateResource.Channel.SCALE):
				scale = sparse.scale
			if sparse.has_channel(TwberLayerStateResource.Channel.COLOR):
				color = sparse.self_modulate
			if sparse.has_channel(TwberLayerStateResource.Channel.ROTATION):
				rotation = sparse.rotation

		blended_position += position * weight
		blended_scale += scale * weight
		blended_color += color * weight
		rotation_sine += sin(rotation) * weight
		rotation_cosine += cos(rotation) * weight

		if can_blend_mesh:
			var mesh_vertices := neutral_state.mesh_vertices
			if sparse != null and sparse.has_channel(TwberLayerStateResource.Channel.MESH):
				mesh_vertices = sparse.mesh_vertices
			if mesh_vertices.size() != mesh_vertex_count:
				can_blend_mesh = false
			else:
				for vertex_index: int in mesh_vertex_count:
					blended_vertices[vertex_index] += mesh_vertices[vertex_index] * weight

	if total_weight <= 0.0 or dominant_index < 0:
		return null

	var dominant: TwberLayerStateResource = samples[dominant_index].get("state") as TwberLayerStateResource
	var result := TwberLayerStateResource.new()
	result.channels = TwberLayerStateResource.ALL_CHANNELS
	result.layer_id = neutral_state.layer_id
	result.position = blended_position / total_weight
	result.rotation = atan2(rotation_sine, rotation_cosine)
	result.scale = blended_scale / total_weight
	result.self_modulate = blended_color / total_weight
	result.visible = (
			dominant.visible
			if dominant != null and dominant.has_channel(TwberLayerStateResource.Channel.VISIBILITY)
			else neutral_state.visible
	)
	result.animation_name = (
			dominant.animation_name
			if dominant != null and dominant.has_channel(TwberLayerStateResource.Channel.ANIMATION)
			else neutral_state.animation_name
	)
	result.animation_frame_rate = (
			dominant.animation_frame_rate
			if dominant != null and dominant.has_channel(TwberLayerStateResource.Channel.ANIMATION_FRAME_RATE)
			else neutral_state.animation_frame_rate
	)
	if can_blend_mesh:
		for vertex_index: int in mesh_vertex_count:
			blended_vertices[vertex_index] /= total_weight
		result.mesh_vertices = blended_vertices
	return result


static func _resolve_compiled_state(
		sample: Dictionary,
		neutral_state: TwberLayerStateResource,
) -> TwberLayerStateResource:
	var state: Variant = sample.get("state")
	return (
			(state as TwberLayerStateResource).materialized(neutral_state)
			if state is TwberLayerStateResource
			else neutral_state.duplicate(true)
	)


static func get_layer_nodes_by_id(root: Node) -> Dictionary:
	var output := {}
	if root != null:
		_collect_layer_nodes_by_id(root, output)
	return output


static func _collect_layer_nodes_by_id(node: Node, output: Dictionary) -> void:
	if node.has_meta(TwberModelCodec.LAYER_ID_META):
		var layer_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
		if not layer_id.is_empty() and node is Node2D:
			output[layer_id] = node

	for child: Node in node.get_children():
		_collect_layer_nodes_by_id(child, output)


static func _get_bound_layer_ids(parameter: TwberParameterResource) -> Array[String]:
	var output: Array[String] = []
	var seen := {}
	for parameter_position: TwberParameterPositionResource in parameter.positions:
		if parameter_position == null:
			continue
		for layer_state: TwberLayerStateResource in parameter_position.layer_states:
			if layer_state == null or layer_state.layer_id.is_empty() or seen.has(layer_state.layer_id):
				continue
			seen[layer_state.layer_id] = true
			output.append(layer_state.layer_id)
	return output


static func _sample_scalar(samples: Array[Dictionary], scalar: float) -> TwberLayerStateResource:
	samples.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return first["coordinate"].x < second["coordinate"].x
	)

	if samples.size() == 1 or scalar <= float(samples[0]["coordinate"].x):
		return _copy_state(samples[0]["state"])
	if scalar >= float(samples[samples.size() - 1]["coordinate"].x):
		return _copy_state(samples[samples.size() - 1]["state"])

	for index: int in samples.size() - 1:
		var first: Dictionary = samples[index]
		var second: Dictionary = samples[index + 1]
		var first_value := float(first["coordinate"].x)
		var second_value := float(second["coordinate"].x)
		if scalar > second_value:
			continue

		var weight := inverse_lerp(first_value, second_value, scalar)
		return _blend_states(
				[first["state"], second["state"]],
				PackedFloat32Array([1.0 - weight, weight]),
		)

	return _copy_state(samples[samples.size() - 1]["state"])


static func _sample_vector(
		samples: Array[Dictionary],
		coordinate: Vector2,
) -> TwberLayerStateResource:
	if samples.size() == 1:
		return _copy_state(samples[0]["state"])
	if samples.size() == 2:
		return _sample_segment(samples[0], samples[1], coordinate)

	var points := PackedVector2Array()
	for sample: Dictionary in samples:
		points.append(sample["coordinate"])

	var triangles := Geometry2D.triangulate_delaunay(points)
	var closest_edge: Array = []
	var closest_edge_weight := 0.0
	var closest_distance_squared := INF

	for triangle_start: int in range(0, triangles.size() - 2, 3):
		var first_index := int(triangles[triangle_start])
		var second_index := int(triangles[triangle_start + 1])
		var third_index := int(triangles[triangle_start + 2])
		var weights := _get_barycentric_weights(
				coordinate,
				points[first_index],
				points[second_index],
				points[third_index],
		)
		if not weights.is_empty() and _weights_are_inside_triangle(weights):
			return _blend_states(
					[
						samples[first_index]["state"],
						samples[second_index]["state"],
						samples[third_index]["state"],
					],
					weights,
			)

		for edge: Array in [
				[first_index, second_index],
				[second_index, third_index],
				[third_index, first_index],
		]:
			var edge_weight := _get_segment_weight(points[edge[0]], points[edge[1]], coordinate)
			var closest_point := points[edge[0]].lerp(points[edge[1]], edge_weight)
			var distance_squared := coordinate.distance_squared_to(closest_point)
			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_edge = edge
				closest_edge_weight = edge_weight

	if not closest_edge.is_empty():
		return _blend_states(
				[
					samples[closest_edge[0]]["state"],
					samples[closest_edge[1]]["state"],
				],
				PackedFloat32Array([1.0 - closest_edge_weight, closest_edge_weight]),
		)

	return _sample_two_nearest(samples, coordinate)


static func _sample_segment(
		first: Dictionary,
		second: Dictionary,
		coordinate: Vector2,
) -> TwberLayerStateResource:
	var weight := _get_segment_weight(first["coordinate"], second["coordinate"], coordinate)
	return _blend_states(
			[first["state"], second["state"]],
			PackedFloat32Array([1.0 - weight, weight]),
	)


static func _sample_two_nearest(
		samples: Array[Dictionary],
		coordinate: Vector2,
) -> TwberLayerStateResource:
	samples.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return coordinate.distance_squared_to(first["coordinate"]) < coordinate.distance_squared_to(second["coordinate"])
	)
	return _sample_segment(samples[0], samples[1], coordinate)


static func _get_segment_weight(first: Vector2, second: Vector2, point: Vector2) -> float:
	var segment := second - first
	var length_squared := segment.length_squared()
	if length_squared <= GEOMETRY_EPSILON:
		return 0.0
	return clampf((point - first).dot(segment) / length_squared, 0.0, 1.0)


static func _get_barycentric_weights(
		point: Vector2,
		first: Vector2,
		second: Vector2,
		third: Vector2,
) -> PackedFloat32Array:
	var denominator := (
			(second.y - third.y) * (first.x - third.x)
			+ (third.x - second.x) * (first.y - third.y)
	)
	if absf(denominator) <= GEOMETRY_EPSILON:
		return PackedFloat32Array()

	var first_weight := (
			(second.y - third.y) * (point.x - third.x)
			+ (third.x - second.x) * (point.y - third.y)
	) / denominator
	var second_weight := (
			(third.y - first.y) * (point.x - third.x)
			+ (first.x - third.x) * (point.y - third.y)
	) / denominator
	return PackedFloat32Array([
		first_weight,
		second_weight,
		1.0 - first_weight - second_weight,
	])


static func _weights_are_inside_triangle(weights: PackedFloat32Array) -> bool:
	for weight: float in weights:
		if weight < -SAMPLE_EPSILON or weight > 1.0 + SAMPLE_EPSILON:
			return false
	return true


static func _blend_states(
		states: Array[TwberLayerStateResource],
		weights: PackedFloat32Array,
) -> TwberLayerStateResource:
	return TwberLayerStateResource.blend_weighted(states, weights)


static func _copy_state(state: TwberLayerStateResource) -> TwberLayerStateResource:
	return state.duplicate(true) if state != null else null
