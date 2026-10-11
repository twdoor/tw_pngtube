class_name TwberMirrorLayers extends TwberDuplicateLayers

var _settings: Dictionary


func _init(ids: Array[String], settings: Dictionary) -> void:
	super(ids)
	_settings = settings.duplicate(true)
	label = "Mirror layers"


func apply(model: TwberModelResource) -> Error:
	var original_parameters: Array[TwberParameterResource] = []
	for parameter: TwberParameterResource in model.parameters:
		original_parameters.append(parameter.duplicate(true))
	var error := super.apply(model)
	if error != OK or not did_change:
		return error
	# Duplicate owns ID allocation, hierarchy and timeline copying; rig copies
	# need independent coordinate reversal and optional parameter separation.
	model.parameters = original_parameters
	var layers := TwberLayerHierarchy.index(model)
	var parents := TwberLayerHierarchy.parents(model)
	var mirror_x := bool(_settings.get("geometry_x", true))
	var mirror_y := bool(_settings.get("geometry_y", false))
	for source_id: String in id_mapping:
		var copy: TwberLayerResource = layers[id_mapping[source_id]]
		var siblings := TwberLayerHierarchy.children(model, parents[copy.id]).duplicate()
		siblings.erase(copy.id)
		copy.name = TwberLayerHierarchy.unique_name(_get_mirrored_name(layers[source_id].name), siblings, layers)
		copy.position = _mirror_vector(copy.position, mirror_x, mirror_y)
		if mirror_x != mirror_y:
			copy.rotation = wrapf(-copy.rotation, -PI, PI)
		if copy.mesh != null:
			copy.mesh.texture_origin = _mirror_vector(copy.mesh.texture_origin, mirror_x, mirror_y)
			_mirror_packed_vectors(copy.mesh.vertices, mirror_x, mirror_y)
			_mirror_packed_vectors(copy.mesh.rest_vertices, mirror_x, mirror_y)
		elif copy.type in [TwberLayerResource.LayerType.SPRITE, TwberLayerResource.LayerType.ANIMATED_SPRITE]:
			copy.offset = _mirror_vector(copy.offset, mirror_x, mirror_y)
			copy.flip_h = copy.flip_h != mirror_x
			copy.flip_v = copy.flip_v != mirror_y
	var copies := {}
	for id: String in id_mapping.values():
		copies[id] = true
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		for key: TwberTimelineKeyframeResource in animation.keyframes:
			if copies.has(key.layer_state.layer_id):
				_mirror_layer_state_geometry(key.layer_state, mirror_x, mirror_y)
	for source: TwberParameterResource in original_parameters.duplicate():
		var target := source
		if bool(_settings.get("new_parameter", false)):
			target = _make_mirrored_parameter(source, model.parameters, _settings)
		var copied := _copy_parameter_layer_states(source, target, id_mapping, _settings)
		if target != source and copied:
			model.parameters.append(target)
			for clip: TwberTimelineAnimationResource in model.timeline_animations:
				for key: TwberParameterKeyframeResource in clip.parameter_keys.duplicate():
					if key.parameter_id == source.id:
						var copy := key.duplicate(true) as TwberParameterKeyframeResource
						copy.parameter_id = target.id
						copy.coordinate = _mirror_parameter_coordinate(source, key.coordinate, _settings)
						clip.parameter_keys.append(copy)
	return OK


func _copy_parameter_layer_states(
		source_parameter: TwberParameterResource,
		target_parameter: TwberParameterResource,
		layer_id_mapping: Dictionary,
		settings: Dictionary,
) -> bool:
	var copied_any := false
	var source_positions := source_parameter.positions.duplicate()
	for source_position: TwberParameterPositionResource in source_positions:
		if source_position == null:
			continue
		var mirrored_states: Array[TwberLayerStateResource] = []
		var source_states := source_position.layer_states.duplicate()
		for source_state: TwberLayerStateResource in source_states:
			if source_state == null or not layer_id_mapping.has(source_state.layer_id):
				continue
			var mirrored_state := source_state.duplicate(true) as TwberLayerStateResource
			mirrored_state.layer_id = String(layer_id_mapping[source_state.layer_id])
			_mirror_layer_state_geometry(
				mirrored_state,
				bool(settings.get("geometry_x", true)),
				bool(settings.get("geometry_y", false)),
			)
			mirrored_states.append(mirrored_state)
		if mirrored_states.is_empty():
			continue

		var coordinate := _mirror_parameter_coordinate(source_parameter, source_position.coordinate, settings)
		var target_position := target_parameter.find_position(coordinate)
		if target_position == null:
			target_position = TwberParameterPositionResource.new()
			target_position.coordinate = coordinate
			target_parameter.positions.append(target_position)
		for mirrored_state: TwberLayerStateResource in mirrored_states:
			target_position.upsert_state(mirrored_state)
		copied_any = true
	return copied_any


func _make_mirrored_parameter(
		source: TwberParameterResource,
		existing_parameters: Array[TwberParameterResource],
		settings: Dictionary,
) -> TwberParameterResource:
	var mirrored := source.duplicate(true) as TwberParameterResource
	mirrored.positions.clear()
	mirrored.name = _make_unique_parameter_name_for_mirror(
		_get_mirrored_name(source.name),
		existing_parameters,
	)
	mirrored.id = _make_unique_parameter_id_for_mirror(
		_get_mirrored_name(source.id),
		existing_parameters,
	)
	var mirrored_default := _mirror_parameter_coordinate(
		source,
		source.coordinate_from_value(source.get_default_value()),
		settings,
	)
	match source.value_type:
		TwberParameterResource.ValueType.BOOL:
			mirrored.default_bool = mirrored_default.x >= 0.5
		TwberParameterResource.ValueType.INT:
			mirrored.default_int = int(roundf(mirrored_default.x))
		TwberParameterResource.ValueType.VECTOR2:
			mirrored.default_vector2 = mirrored_default
		_:
			mirrored.default_float = mirrored_default.x
	for binding: TwberAnimationBindingResource in mirrored.animation_bindings:
		binding.coordinate = _mirror_parameter_coordinate(source, binding.coordinate, settings)
	return mirrored


func _mirror_parameter_coordinate(
		parameter: TwberParameterResource,
		coordinate: Vector2,
		settings: Dictionary,
) -> Vector2:
	var output := coordinate
	if bool(settings.get("bindings_x", false)):
		if parameter.value_type == TwberParameterResource.ValueType.VECTOR2:
			output.x = parameter.get_vector_min().x + parameter.get_vector_max().x - output.x
		else:
			output.x = parameter.get_scalar_min() + parameter.get_scalar_max() - output.x
	if (
		bool(settings.get("bindings_y", false))
		and parameter.value_type == TwberParameterResource.ValueType.VECTOR2
	):
		output.y = parameter.get_vector_min().y + parameter.get_vector_max().y - output.y
	return parameter.clamp_coordinate(output)


func _mirror_layer_state_geometry(
		state: TwberLayerStateResource,
		mirror_x: bool,
		mirror_y: bool,
) -> void:
	if state.has_channel(TwberLayerStateResource.Channel.POSITION):
		state.position = _mirror_vector(state.position, mirror_x, mirror_y)
	if state.has_channel(TwberLayerStateResource.Channel.ROTATION) and mirror_x != mirror_y:
		state.rotation = wrapf(-state.rotation, -PI, PI)
	if state.has_channel(TwberLayerStateResource.Channel.MESH):
		_mirror_packed_vectors(state.mesh_vertices, mirror_x, mirror_y)


func _mirror_packed_vectors(values: PackedVector2Array, mirror_x: bool, mirror_y: bool) -> void:
	for index: int in values.size():
		values[index] = _mirror_vector(values[index], mirror_x, mirror_y)


func _mirror_vector(value: Vector2, mirror_x: bool, mirror_y: bool) -> Vector2:
	return Vector2(-value.x if mirror_x else value.x, -value.y if mirror_y else value.y)


func _get_mirrored_name(source_name: String) -> String:
	var pairs := [
		["Left", "Right"], ["left", "right"], ["LEFT", "RIGHT"],
		["_L", "_R"], [".L", ".R"], ["-L", "-R"], [" L", " R"],
	]
	for pair: Array in pairs:
		if source_name.contains(pair[0]):
			return source_name.replace(pair[0], pair[1])
		if source_name.contains(pair[1]):
			return source_name.replace(pair[1], pair[0])
	if source_name.ends_with("L"):
		return source_name.left(source_name.length() - 1) + "R"
	if source_name.ends_with("R"):
		return source_name.left(source_name.length() - 1) + "L"
	return "%s Mirror" % source_name


func _make_unique_parameter_name_for_mirror(
		desired_name: String,
		parameters: Array[TwberParameterResource],
) -> String:
	var used := {}
	for parameter: TwberParameterResource in parameters:
		used[parameter.name] = true
	return _make_unique_name(desired_name, used)


func _make_unique_parameter_id_for_mirror(
		desired_id: String,
		parameters: Array[TwberParameterResource],
) -> String:
	var base_id := desired_id.strip_edges().replace(" ", "_").to_lower()
	if base_id.is_empty():
		base_id = "parameter_mirror"
	var used := {}
	for parameter: TwberParameterResource in parameters:
		used[parameter.id] = true
	return _make_unique_name(base_id, used)


func _make_unique_name(desired: String, used: Dictionary) -> String:
	var name := desired
	var index := 2
	while used.has(name):
		name = "%s %d" % [desired, index]
		index += 1
	return name
