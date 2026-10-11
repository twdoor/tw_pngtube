class_name TwberDocumentValidator extends RefCounted


static func validate(model: TwberModelResource) -> Array[String]:
	var errors: Array[String] = []
	if model == null:
		return ["Model is missing."]
	if model.format_version > TwberModelResource.FORMAT_VERSION:
		errors.append("Model format is newer than this editor supports.")
	if not _finite_transform(model.root_position, model.root_rotation, model.root_scale):
		errors.append("Model root transform is not finite.")
	var layers := {}
	for layer: TwberLayerResource in model.layers:
		if layer == null or layer.id.is_empty():
			errors.append("Every layer needs an ID.")
			continue
		if layers.has(layer.id):
			errors.append("Duplicate layer ID: %s" % layer.id)
		layers[layer.id] = layer
		if not _finite_transform(layer.position, layer.rotation, layer.scale):
			errors.append("Layer transform is not finite: %s" % layer.id)
		if layer.mesh != null:
			for vertex: Vector2 in layer.mesh.vertices:
				if not vertex.is_finite():
					errors.append("Mesh contains a non-finite vertex: %s" % layer.id)
					break
			for index: int in layer.mesh.triangles:
				if index < 0 or index >= layer.mesh.vertices.size():
					errors.append("Mesh triangle index is out of bounds: %s" % layer.id)
					break
			if layer.mesh.triangles.size() % 3 != 0:
				errors.append("Mesh triangle indices must form triplets: %s" % layer.id)
	var references := {}
	for id: String in model.root_layer_ids:
		_count_reference(id, layers, references, errors)
	for layer: TwberLayerResource in layers.values():
		for id: String in layer.children:
			_count_reference(id, layers, references, errors)
	var visited := {}
	var pending := model.root_layer_ids.duplicate()
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if not layers.has(id) or visited.has(id):
			continue
		visited[id] = true
		pending.append_array((layers[id] as TwberLayerResource).children)
	for id: String in layers:
		if int(references.get(id, 0)) != 1:
			errors.append("Layer must have exactly one parent or root entry: %s" % id)
		if not visited.has(id):
			errors.append("Layer is unreachable or belongs to a cycle: %s" % id)
	var animation_ids := {}
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		if animation == null or animation.id.is_empty() or animation_ids.has(animation.id):
			errors.append("Timeline IDs must be present and unique.")
			continue
		animation_ids[animation.id] = true
		if not is_finite(animation.duration) or animation.duration <= 0.0:
			errors.append("Invalid timeline duration: %s" % animation.id)
		for key: TwberTimelineKeyframeResource in animation.keyframes:
			if key == null or not is_finite(key.time) or key.time < 0.0 or key.time > animation.duration or key.interpolation not in [0, 1]:
				errors.append("Invalid timeline key: %s" % animation.id)
				continue
			_validate_state(key.layer_state, layers, errors)
	errors.append_array(validate_sprite_keys(model))
	var parameter_ids := {}
	for parameter: TwberParameterResource in model.parameters:
		if parameter == null or parameter.id.is_empty() or parameter_ids.has(parameter.id):
			errors.append("Parameter IDs must be present and unique.")
			continue
		parameter_ids[parameter.id] = parameter
		for sample: TwberParameterPositionResource in parameter.positions:
			if sample == null or not sample.coordinate.is_finite():
				errors.append("Invalid parameter sample: %s" % parameter.id)
				continue
			for state: TwberLayerStateResource in sample.layer_states:
				_validate_state(state, layers, errors)
		for binding: TwberAnimationBindingResource in parameter.animation_bindings:
			if binding == null or not animation_ids.has(binding.animation_id) or not binding.coordinate.is_finite():
				errors.append("Invalid animation binding: %s" % parameter.id)
	errors.append_array(validate_parameter_keys(model))
	return errors


static func _count_reference(id: String, layers: Dictionary, counts: Dictionary, errors: Array[String]) -> void:
	if not layers.has(id):
		errors.append("Unknown layer reference: %s" % id)
	counts[id] = int(counts.get(id, 0)) + 1


static func _validate_state(state: TwberLayerStateResource, layers: Dictionary, errors: Array[String]) -> void:
	if state == null or not layers.has(state.layer_id):
		errors.append("Pose references a missing layer.")
		return
	for component: float in [state.self_modulate.r, state.self_modulate.g, state.self_modulate.b, state.self_modulate.a, state.animation_frame_rate]:
		if not is_finite(component):
			errors.append("Pose colour or animation rate is not finite: %s" % state.layer_id)
	if not _finite_transform(state.position, state.rotation, state.scale):
		errors.append("Pose transform is not finite: %s" % state.layer_id)
	if state.has_channel(TwberLayerStateResource.Channel.MESH) and not state.mesh_vertices.is_empty():
		var layer: TwberLayerResource = layers[state.layer_id]
		if layer.mesh == null or state.mesh_vertices.size() != layer.mesh.vertices.size():
			errors.append("Pose mesh topology does not match: %s" % state.layer_id)
		for vertex: Vector2 in state.mesh_vertices:
			if not vertex.is_finite():
				errors.append("Pose mesh contains a non-finite vertex: %s" % state.layer_id)
				break


static func _finite_transform(position: Vector2, rotation: float, scale: Vector2) -> bool:
	return position.is_finite() and is_finite(rotation) and scale.is_finite()


static func validate_parameter_keys(model: TwberModelResource) -> Array[String]:
	var errors: Array[String] = []
	var parameter_ids := {}
	for parameter: TwberParameterResource in model.parameters:
		if parameter != null:
			parameter_ids[parameter.id] = parameter
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		if animation == null:
			continue
		var times := {}
		for key: TwberParameterKeyframeResource in animation.parameter_keys:
			if key == null or not parameter_ids.has(key.parameter_id) or not is_finite(key.time) or key.time < 0.0 or key.time > animation.duration or not key.coordinate.is_finite() or key.interpolation not in [0, 1]:
				errors.append("Invalid parameter key: %s" % animation.id)
				continue
			var parameter: TwberParameterResource = parameter_ids[key.parameter_id]
			if not parameter.clamp_coordinate(key.coordinate).is_equal_approx(key.coordinate):
				errors.append("Parameter range or step would move a timeline key: %s" % key.parameter_id)
			var target := [key.parameter_id, key.time]
			if times.has(target):
				errors.append("Duplicate parameter key: %s" % key.parameter_id)
			times[target] = true
	return errors


static func validate_sprite_keys(model: TwberModelResource) -> Array[String]:
	var errors: Array[String] = []
	var layers := TwberLayerHierarchy.index(model)
	for clip: TwberTimelineAnimationResource in model.timeline_animations:
		if clip == null:
			continue
		var times := {}
		var first := {}
		for key: TwberSpriteKeyframeResource in clip.sprite_keys:
			if key == null or not layers.has(key.layer_id) or not is_finite(key.time) or key.time < 0.0 or key.time > clip.duration or not is_finite(key.phase) or key.phase < 0.0 or not is_finite(key.rate) or key.rate < 0.0:
				errors.append("Invalid sprite clock key: %s" % clip.id)
				continue
			var layer: TwberLayerResource = layers[key.layer_id]
			var found := false
			for animation: TwberAnimationResource in layer.animations:
				found = found or animation.name == key.animation_name
			if layer.type != TwberLayerResource.LayerType.ANIMATED_SPRITE or not found:
				errors.append("Sprite key references a missing animation: %s" % key.layer_id)
			var target := [key.layer_id, key.time]
			if times.has(target):
				errors.append("Duplicate sprite clock key: %s" % key.layer_id)
			times[target] = true
			first[key.layer_id] = minf(float(first.get(key.layer_id, INF)), key.time)
		for id: String in first:
			if first[id] != 0.0:
				errors.append("Sprite clock tracks must start at zero: %s" % id)
	return errors
