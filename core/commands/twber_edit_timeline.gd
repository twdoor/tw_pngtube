class_name TwberEditTimeline extends TwberDocumentCommand

enum Operation { CREATE, DELETE, UPDATE, SET_KEY, REMOVE_KEY, SET_PARAMETER_KEY, REMOVE_PARAMETER_KEY, CLEAR_SPRITE_TIMING }
const SETTINGS := ["name", "duration", "loop", "fps", "priority"]

var operation: Operation
var animation_id: String
var _data: Dictionary


func _init(action: Operation, id := "", data: Dictionary = {}) -> void:
	operation = action
	animation_id = id
	_data = data.duplicate(true)
	if data.get("pose") is TwberLayerStateResource:
		_data["pose"] = data["pose"].duplicate(true)
	label = ["Create animation", "Delete animation", "Change animation settings", "Set animation key", "Remove animation key", "Set parameter key", "Remove parameter key", "Use authored sprite timing"][action]
	kinds = TwberDocumentChange.Kind.ANIMATION


func is_name_only() -> bool:
	return operation == Operation.UPDATE and _data.size() == 1 and _data.has("name")


static func find(model: TwberModelResource, id: String) -> TwberTimelineAnimationResource:
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		if animation.id == id:
			return animation
	return null


# UI selection and commands use the same nearest-key rule. Ties choose the
# earlier key, independent of storage order. FPS changes never move saved keys.
static func find_key(animation: TwberTimelineAnimationResource, layer_id: String, time: float) -> int:
	var closest := -1
	var distance := 0.5 / maxf(animation.fps, 1.0)
	for index: int in animation.keyframes.size():
		var key := animation.keyframes[index]
		if key.layer_state.layer_id != layer_id:
			continue
		var delta := absf(key.time - time)
		if delta < distance or (delta == distance and (closest < 0 or key.time < animation.keyframes[closest].time)):
			closest = index
			distance = delta
	return closest


func apply(model: TwberModelResource) -> Error:
	did_change = false
	layer_ids.clear()
	if operation == Operation.CREATE:
		return _create(model)
	var animation := find(model, animation_id)
	if animation == null:
		return ERR_DOES_NOT_EXIST
	layer_ids = animation.get_layer_ids()
	for key: TwberParameterKeyframeResource in animation.parameter_keys:
		_include_parameter_layers(TwberEditParameter.find(model, key.parameter_id))
	if operation == Operation.DELETE:
		model.timeline_animations.erase(animation)
		for parameter: TwberParameterResource in model.parameters:
			for index: int in range(parameter.animation_bindings.size() - 1, -1, -1):
				if parameter.animation_bindings[index].animation_id == animation_id:
					parameter.animation_bindings.remove_at(index)
					kinds |= TwberDocumentChange.Kind.RIG
		did_change = true
		return OK
	if operation == Operation.CLEAR_SPRITE_TIMING:
		did_change = not animation.sprite_keys.is_empty()
		animation.sprite_keys.clear()
		return OK
	if operation == Operation.UPDATE:
		return _update(animation)
	var input_time: Variant = _data.get("time", 0.0)
	if not input_time is float and not input_time is int:
		return ERR_INVALID_PARAMETER
	var time := float(input_time)
	if not is_finite(time) or time < 0.0 or time > animation.duration:
		error_message = "The key must be inside the animation duration"
		return ERR_INVALID_PARAMETER
	if operation in [Operation.SET_PARAMETER_KEY, Operation.REMOVE_PARAMETER_KEY]:
		return _edit_parameter_key(model, animation, time)
	var pose := _data.get("pose") as TwberLayerStateResource
	var layer_id := pose.layer_id if pose != null else String(_data.get("layer_id", ""))
	var layers := TwberLayerHierarchy.index(model)
	if not layers.has(layer_id):
		return ERR_DOES_NOT_EXIST
	var index := find_key(animation, layer_id, time)
	if operation == Operation.REMOVE_KEY:
		if index >= 0:
			animation.keyframes.remove_at(index)
			did_change = true
		return OK
	if operation != Operation.SET_KEY or pose == null:
		return ERR_INVALID_PARAMETER
	var errors: Array[String] = []
	TwberDocumentValidator._validate_state(pose, layers, errors)
	for component: float in [pose.self_modulate.r, pose.self_modulate.g, pose.self_modulate.b, pose.self_modulate.a, pose.animation_frame_rate]:
		if not is_finite(component):
			errors.append("Key contains a nonfinite colour or frame rate")
	if not errors.is_empty():
		error_message = "; ".join(errors)
		return ERR_INVALID_DATA
	if index >= 0:
		var existing := animation.keyframes[index]
		if existing.time == time and TwberLayerStateResource.same_pose(existing.layer_state, pose):
			return OK
	var key := TwberTimelineKeyframeResource.new()
	key.time = time
	key.layer_state = pose.duplicate(true)
	# Updating a recorded pose preserves its hold timing. Newly authored keys
	# retain the legacy linear default.
	if index >= 0:
		key.interpolation = animation.keyframes[index].interpolation
	if index >= 0:
		animation.keyframes[index] = key
	else:
		animation.keyframes.append(key)
	if not layer_ids.has(layer_id):
		layer_ids.append(layer_id)
	did_change = true
	return OK


func _create(model: TwberModelResource) -> Error:
	var used := {}
	var names := {}
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		used[animation.id] = true
		names[animation.name] = true
	var animation := TwberTimelineAnimationResource.new()
	animation.id = TwberLayerHierarchy.allocate_id(used, "animation")
	var index := 1
	while names.has("Animation %d" % index):
		index += 1
	animation.name = "Animation %d" % index
	model.timeline_animations.append(animation)
	animation_id = animation.id
	did_change = true
	return OK


func _update(animation: TwberTimelineAnimationResource) -> Error:
	for field: Variant in _data:
		if not field is String or not SETTINGS.has(field) or typeof(_data[field]) != typeof(animation.get(field)):
			return ERR_INVALID_PARAMETER
	var duration: float = _data.get("duration", animation.duration)
	var fps: float = _data.get("fps", animation.fps)
	if not is_finite(duration) or duration < 0.05 or not is_finite(fps) or fps < 1.0:
		error_message = "Duration must be at least 0.05 seconds and frame rate at least 1 fps"
		return ERR_INVALID_PARAMETER
	for key: TwberTimelineKeyframeResource in animation.keyframes:
		if key.time > duration:
			error_message = "The duration would cut off an existing key; remove the later keys or keep a longer duration"
			return ERR_INVALID_PARAMETER
	for key: TwberParameterKeyframeResource in animation.parameter_keys:
		if key.time > duration:
			error_message = "The duration would cut off an existing parameter key"
			return ERR_INVALID_PARAMETER
	for key: TwberSpriteKeyframeResource in animation.sprite_keys:
		if key.time > duration:
			error_message = "The duration would cut off an existing sprite clock key"
			return ERR_INVALID_PARAMETER
	for field: String in _data:
		var value: Variant = _data[field]
		if field == "name":
			value = String(value).strip_edges()
			if value.is_empty():
				value = "Animation"
		if animation.get(field) != value:
			animation.set(field, value)
			did_change = true
	return OK


static func find_parameter_key(animation: TwberTimelineAnimationResource, parameter_id: String, time: float) -> int:
	var closest := -1
	var distance := 0.5 / maxf(animation.fps, 1.0)
	for index: int in animation.parameter_keys.size():
		var key := animation.parameter_keys[index]
		if key.parameter_id != parameter_id:
			continue
		var delta := absf(key.time - time)
		if delta < distance or (delta == distance and (closest < 0 or key.time < animation.parameter_keys[closest].time)):
			closest = index
			distance = delta
	return closest


func _edit_parameter_key(model: TwberModelResource, animation: TwberTimelineAnimationResource, time: float) -> Error:
	var parameter_id := String(_data.get("parameter_id", ""))
	var parameter := TwberEditParameter.find(model, parameter_id)
	if parameter == null:
		return ERR_DOES_NOT_EXIST
	_include_parameter_layers(parameter)
	var index := find_parameter_key(animation, parameter_id, time)
	if operation == Operation.REMOVE_PARAMETER_KEY:
		if index >= 0:
			animation.parameter_keys.remove_at(index)
			did_change = true
		return OK
	var coordinate: Variant = _data.get("coordinate")
	var interpolation: Variant = _data.get("interpolation", TwberParameterKeyframeResource.Interpolation.LINEAR)
	if not coordinate is Vector2 or not coordinate.is_finite() or not interpolation is int or interpolation not in [0, 1]:
		return ERR_INVALID_PARAMETER
	coordinate = parameter.clamp_coordinate(coordinate)
	if index >= 0:
		var existing := animation.parameter_keys[index]
		if existing.time == time and existing.coordinate == coordinate and existing.interpolation == interpolation:
			return OK
	var key := TwberParameterKeyframeResource.new()
	key.parameter_id = parameter_id
	key.time = time
	key.coordinate = coordinate
	key.interpolation = interpolation
	if index >= 0:
		animation.parameter_keys[index] = key
	else:
		animation.parameter_keys.append(key)
	did_change = true
	return OK


func _include_parameter_layers(parameter: TwberParameterResource) -> void:
	if parameter == null:
		return
	for sample: TwberParameterPositionResource in parameter.positions:
		for state: TwberLayerStateResource in sample.layer_states:
			if not layer_ids.has(state.layer_id):
				layer_ids.append(state.layer_id)
