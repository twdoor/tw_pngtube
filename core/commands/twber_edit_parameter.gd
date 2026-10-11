class_name TwberEditParameter extends TwberDocumentCommand

enum Operation { CREATE, DELETE, UPDATE, BIND_POSE, REMOVE_POSE, BIND_ANIMATION, REMOVE_ANIMATION }
const SETTINGS := ["name", "min_value", "max_value", "min_vector2", "max_vector2", "step", "default_bool", "default_int", "default_float", "default_vector2"]
var operation: Operation
var parameter_id: String
var _data: Dictionary


func _init(action: Operation, id := "", data: Dictionary = {}) -> void:
	operation = action
	parameter_id = id
	_data = data.duplicate(true)
	if data.get("pose") is TwberLayerStateResource:
		_data["pose"] = data["pose"].duplicate(true)
	label = ["Create parameter", "Delete parameter", "Change parameter settings", "Bind parameter pose", "Remove parameter pose", "Bind animation trigger", "Remove animation trigger"][action]
	kinds = TwberDocumentChange.Kind.RIG


func get_bound_layer_id() -> String:
	var pose := _data.get("pose") as TwberLayerStateResource
	return pose.layer_id if pose != null else ""


func is_name_only() -> bool:
	return operation == Operation.UPDATE and _data.size() == 1 and _data.has("name")


static func find(model: TwberModelResource, id: String) -> TwberParameterResource:
	for parameter: TwberParameterResource in model.parameters:
		if parameter.id == id:
			return parameter
	return null


func apply(model: TwberModelResource) -> Error:
	did_change = false
	layer_ids.clear()
	if operation == Operation.CREATE:
		return _create(model)
	var parameter := find(model, parameter_id)
	if parameter == null:
		return ERR_DOES_NOT_EXIST
	for sample: TwberParameterPositionResource in parameter.positions:
		for state: TwberLayerStateResource in sample.layer_states:
			if not layer_ids.has(state.layer_id):
				layer_ids.append(state.layer_id)
	if operation == Operation.DELETE:
		model.parameters.erase(parameter)
		for clip: TwberTimelineAnimationResource in model.timeline_animations:
			for index: int in range(clip.parameter_keys.size() - 1, -1, -1):
				if clip.parameter_keys[index].parameter_id == parameter_id:
					clip.parameter_keys.remove_at(index)
					kinds |= TwberDocumentChange.Kind.ANIMATION
		did_change = true
		return OK
	if operation == Operation.UPDATE:
		return _update(parameter)
	if not _data.get("coordinate", Vector2.ZERO) is Vector2:
		return ERR_INVALID_PARAMETER
	var coordinate: Vector2 = _data.get("coordinate", Vector2.ZERO)
	if not coordinate.is_finite():
		return ERR_INVALID_PARAMETER
	coordinate = parameter.clamp_coordinate(coordinate)
	if operation == Operation.BIND_POSE:
		return _bind_pose(model, parameter, coordinate)
	if operation == Operation.REMOVE_POSE:
		var layer_id := String(_data.get("layer_id", ""))
		if not TwberLayerHierarchy.index(model).has(layer_id):
			return ERR_DOES_NOT_EXIST
		var sample := parameter.find_position(coordinate)
		if sample != null:
			did_change = sample.remove_state(layer_id)
			if sample.layer_states.is_empty():
				parameter.positions.erase(sample)
		return OK
	var animation_id := String(_data.get("animation_id", ""))
	var exists := false
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		if animation.id == animation_id:
			exists = true
	if not exists:
		return ERR_DOES_NOT_EXIST
	if parameter.value_type not in [TwberParameterResource.ValueType.BOOL, TwberParameterResource.ValueType.INT]:
		error_message = "Animation triggers require a Bool or Int parameter"
		return ERR_INVALID_PARAMETER
	var binding := parameter.find_animation_binding(animation_id, coordinate)
	if operation == Operation.BIND_ANIMATION and binding == null:
		binding = TwberAnimationBindingResource.new()
		binding.animation_id = animation_id
		binding.coordinate = coordinate
		parameter.animation_bindings.append(binding)
		did_change = true
	elif operation == Operation.REMOVE_ANIMATION and binding != null:
		parameter.animation_bindings.erase(binding)
		did_change = true
	return OK


func _create(model: TwberModelResource) -> Error:
	var type := int(_data.get("value_type", -1))
	if type < 0 or type > TwberParameterResource.ValueType.VECTOR2:
		return ERR_INVALID_PARAMETER
	var parameter := TwberParameterResource.new()
	parameter.value_type = type as TwberParameterResource.ValueType
	var prefixes := ["bool", "int", "float", "vector"]
	var names := ["Bool", "Int", "Float", "Vector"]
	var used := {}
	var used_names := {}
	for existing: TwberParameterResource in model.parameters:
		used[existing.id] = true
		used_names[existing.name] = true
	parameter.id = TwberLayerHierarchy.allocate_id(used, prefixes[type])
	var index := 1
	while used_names.has("%s %d" % [names[type], index]):
		index += 1
	parameter.name = "%s %d" % [names[type], index]
	if type in [TwberParameterResource.ValueType.BOOL, TwberParameterResource.ValueType.INT]:
		parameter.step = TwberParameterResource.DISCRETE_STEP
	if type == TwberParameterResource.ValueType.INT:
		parameter.max_value = 10.0
	model.parameters.append(parameter)
	parameter_id = parameter.id
	did_change = true
	return OK


func _update(parameter: TwberParameterResource) -> Error:
	var before := parameter.duplicate(true) as TwberParameterResource
	for field: Variant in _data:
		if not field is String or not SETTINGS.has(field) or typeof(_data[field]) != typeof(parameter.get(field)):
			return ERR_INVALID_PARAMETER
		parameter.set(field, _data[field])
	parameter.name = parameter.name.strip_edges()
	if (not is_finite(parameter.min_value) or not is_finite(parameter.max_value)
		or not parameter.min_vector2.is_finite() or not parameter.max_vector2.is_finite()
		or not is_finite(parameter.step) or parameter.step <= 0.0
		or not is_finite(parameter.default_float) or not parameter.default_vector2.is_finite()
		or parameter.min_value > parameter.max_value
		or parameter.min_vector2.x > parameter.max_vector2.x or parameter.min_vector2.y > parameter.max_vector2.y):
		return ERR_INVALID_PARAMETER
	if parameter.value_type == TwberParameterResource.ValueType.BOOL and (parameter.min_value != 0.0 or parameter.max_value != 1.0):
		return ERR_INVALID_PARAMETER
	if parameter.value_type in [TwberParameterResource.ValueType.INT, TwberParameterResource.ValueType.BOOL]:
		parameter.step = TwberParameterResource.DISCRETE_STEP
		if parameter.min_value != roundf(parameter.min_value) or parameter.max_value != roundf(parameter.max_value):
			return ERR_INVALID_PARAMETER
	# Refuse edits that would displace or merge existing poses or triggers.
	var coordinates: Array[Vector2] = []
	for sample: TwberParameterPositionResource in parameter.positions:
		coordinates.append(sample.coordinate)
	for binding: TwberAnimationBindingResource in parameter.animation_bindings:
		coordinates.append(binding.coordinate)
	var coordinate_settings_changed := (before.min_value != parameter.min_value or before.max_value != parameter.max_value
		or before.min_vector2 != parameter.min_vector2 or before.max_vector2 != parameter.max_vector2 or before.step != parameter.step)
	for coordinate: Vector2 in coordinates:
		if coordinate_settings_changed and not parameter.clamp_coordinate(coordinate).is_equal_approx(coordinate):
			error_message = "The range or step would move an existing pose or animation trigger; remove the binding or keep its coordinate available"
			return ERR_INVALID_PARAMETER
	if coordinate_settings_changed:
		for first: int in coordinates.size():
			for second: int in range(first + 1, coordinates.size()):
				if (not before.coordinates_equal(coordinates[first], coordinates[second])
					and parameter.coordinates_equal(coordinates[first], coordinates[second])):
					error_message = "The new step would merge existing binding coordinates"
					return ERR_INVALID_PARAMETER
	match parameter.value_type:
		TwberParameterResource.ValueType.INT:
			parameter.default_int = int(parameter.get_default_value())
		TwberParameterResource.ValueType.FLOAT:
			parameter.default_float = float(parameter.get_default_value())
		TwberParameterResource.ValueType.VECTOR2:
			parameter.default_vector2 = parameter.get_default_value()
	for field: String in SETTINGS:
		if parameter.get(field) != before.get(field):
			did_change = true
	return OK


func _bind_pose(model: TwberModelResource, parameter: TwberParameterResource, coordinate: Vector2) -> Error:
	if not _data.get("values", {}) is Dictionary or not _data.get("snap", {}) is Dictionary:
		return ERR_INVALID_PARAMETER
	var values: Dictionary = _data.get("values", {})
	for value: Variant in values.values():
		if value is float and not is_finite(value):
			return ERR_INVALID_PARAMETER
		if value is Vector2 and not value.is_finite():
			return ERR_INVALID_PARAMETER
	var snap: Dictionary = _data.get("snap", {})
	for field: String in ["rotation", "scale"]:
		if snap.has(field):
			var value: Variant = snap[field]
			if (not value is float and not value is int) or not is_finite(float(value)) or float(value) <= 0.0:
				return ERR_INVALID_PARAMETER
	var edited := _data.get("pose") as TwberLayerStateResource
	if edited == null:
		return ERR_INVALID_PARAMETER
	var layers := TwberLayerHierarchy.index(model)
	var errors: Array[String] = []
	TwberDocumentValidator._validate_state(edited, layers, errors)
	for component: float in [edited.self_modulate.r, edited.self_modulate.g, edited.self_modulate.b, edited.self_modulate.a]:
		if not is_finite(component):
			errors.append("Pose colour is not finite")
	if not errors.is_empty():
		error_message = "; ".join(errors)
		return ERR_INVALID_DATA
	var layer := layers[edited.layer_id]
	var base := TwberLayerStateResource.from_layer_resource(layer)
	var others := TwberRigSampling.sample_others(model, layer, _data.get("values", {}), parameter.id, _data.get("snap", {}))
	var isolated := TwberLayerStateResource.isolate_contribution(base, edited.materialized(base), others)
	var sample := parameter.find_position(coordinate)
	if sample != null and TwberLayerStateResource.same_pose(sample.find_state(edited.layer_id), isolated):
		return OK
	if sample == null:
		sample = TwberParameterPositionResource.new()
		sample.coordinate = coordinate
		parameter.positions.append(sample)
	sample.upsert_state(isolated)
	if not layer_ids.has(edited.layer_id):
		layer_ids.append(edited.layer_id)
	did_change = true
	return OK
