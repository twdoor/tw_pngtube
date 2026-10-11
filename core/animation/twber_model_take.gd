class_name TwberModelTake extends RefCounted

# Capture the evaluated performance, using an owned authored model. Triggered
# parameter output stays in parameter tracks; property output is baked only for
# channels owned by triggerable clips. No nodes or wall clocks enter this owner.
var _document := TwberModelDocument.new()
var _running := false
var _trace: TwberParameterTake
var _sprite_keys: Array[TwberSpriteKeyframeResource] = []
var _sprite_anchors := {}
var _sprite_names := {}
var _evaluator := TwberModelEvaluator.new()
var _parameters := {}
var _durations := {}
var _bake_channels := {}
var _inputs := {}
var _last_states := {}
var _layer_keys: Array[TwberTimelineKeyframeResource] = []
var _last_time := -1.0


func start(model: TwberModelResource, values: Dictionary, playheads: Dictionary = {}, sprites: Dictionary = {}) -> Error:
	if _running:
		return ERR_BUSY
	var error := _document.replace_model(model)
	if error != OK:
		return error
	var owned := _document.snapshot().to_model_resource()
	_evaluator.configure(owned)
	_parameters.clear()
	_durations.clear()
	_bake_channels.clear()
	_inputs.clear()
	_last_states.clear()
	_layer_keys.clear()
	_last_time = -1.0
	_sprite_keys.clear()
	_sprite_anchors.clear()
	_sprite_names.clear()
	for layer: TwberLayerResource in owned.layers:
		if layer.type == TwberLayerResource.LayerType.ANIMATED_SPRITE:
			var names := {}
			for animation: TwberAnimationResource in layer.animations:
				names[animation.name] = true
			_sprite_names[layer.id] = names
	var triggerable := {}
	for parameter: TwberParameterResource in owned.parameters:
		_parameters[parameter.id] = parameter
		for binding: TwberAnimationBindingResource in parameter.animation_bindings:
			triggerable[binding.animation_id] = true
	for clip: TwberTimelineAnimationResource in owned.timeline_animations:
		_durations[clip.id] = clip.duration
		if not triggerable.has(clip.id):
			continue
		for key: TwberTimelineKeyframeResource in clip.keyframes:
			var id := key.layer_state.layer_id
			_bake_channels[id] = int(_bake_channels.get(id, 0)) | key.layer_state.channels
	if owned.parameters.is_empty() and sprites.is_empty():
		return ERR_UNCONFIGURED
	_trace = TwberParameterTake.new(owned.parameters)
	_running = true
	error = sample(0.0, values, playheads, sprites)
	if error != OK:
		_trace = null
		_running = false
	return error


func sample(time: float, values: Dictionary, playheads: Dictionary = {}, sprites: Dictionary = {}) -> Error:
	if not _running:
		return ERR_UNCONFIGURED
	if not is_finite(time) or time < 0.0 or time < _last_time:
		return ERR_INVALID_PARAMETER
	for id: Variant in playheads:
		var phase: Variant = playheads[id]
		if not _durations.has(id) or not (phase is float or phase is int):
			return ERR_INVALID_PARAMETER
		if not is_finite(float(phase)) or phase < 0.0 or phase > _durations[id]:
			return ERR_INVALID_PARAMETER
	var inputs := _inputs.duplicate()
	for id: String in values:
		if not _parameters.has(id):
			continue
		var value: Variant = values[id]
		if _parameters[id].value_type == TwberParameterResource.ValueType.VECTOR2:
			if not value is Vector2 or not value.is_finite():
				return ERR_INVALID_PARAMETER
		elif not (value is bool or value is int or value is float) or not is_finite(float(value)):
			return ERR_INVALID_PARAMETER
		inputs[id] = value
	var sprite_pending: Array[TwberSpriteKeyframeResource] = []
	var sprite_replacements := {}
	for id: String in sprites:
		var value: Variant = sprites[id]
		if not _sprite_names.has(id) or value is not Dictionary:
			return ERR_INVALID_PARAMETER
		var name := str(value.get("animation", ""))
		var phase: Variant = value.get("phase")
		var rate: Variant = value.get("rate")
		if not _sprite_names[id].has(name) or not (phase is float or phase is int) or not (rate is float or rate is int):
			return ERR_INVALID_PARAMETER
		if not is_finite(float(phase)) or phase < 0.0 or not is_finite(float(rate)) or rate < 0.0:
			return ERR_INVALID_PARAMETER
		var previous := _sprite_anchors.get(id) as TwberSpriteKeyframeResource
		if previous != null and previous.animation_name == name and previous.rate == rate and absf(previous.phase + (time - previous.time) * previous.rate - phase) <= 0.000001:
			continue
		if previous == null and time != 0.0:
			return ERR_INVALID_PARAMETER
		var key := TwberSpriteKeyframeResource.new()
		key.layer_id = id
		key.time = time
		key.animation_name = name
		key.phase = phase
		key.rate = rate
		sprite_pending.append(key)
		if previous != null and previous.time == time:
			sprite_replacements[id] = _sprite_keys.find(previous)
	var resolved := _evaluator.resolve_parameters(inputs, playheads)
	var poses := _evaluator.evaluate(inputs, playheads)
	var pending: Array[TwberTimelineKeyframeResource] = []
	var replacements := {}
	for id: String in _bake_channels:
		if not poses.has(id):
			continue
		var state: TwberLayerStateResource = poses[id].duplicate(true)
		state.channels = _bake_channels[id]
		# Clear unowned values so unrelated rig changes don't create baked keys.
		state = state.materialized(TwberLayerStateResource.new())
		state.channels = _bake_channels[id]
		if _last_states.has(id) and TwberLayerStateResource.same_pose(state, _last_states[id]):
			continue
		var key := TwberTimelineKeyframeResource.new()
		key.time = time
		key.layer_state = state
		key.interpolation = TwberTimelineKeyframeResource.Interpolation.HOLD
		pending.append(key)
		if time == _last_time:
			for index: int in range(_layer_keys.size() - 1, -1, -1):
				if _layer_keys[index].time != time:
					break
				if _layer_keys[index].layer_state.layer_id == id:
					replacements[id] = index
					break
	var layer_count := _layer_keys.size() + pending.size() - replacements.size()
	var sprite_count := _sprite_keys.size() + sprite_pending.size() - sprite_replacements.size()
	var key_budget := TwberParameterTake.MAX_KEYS - layer_count - sprite_count
	var error := OK if key_budget >= 0 else ERR_OUT_OF_MEMORY
	if not _parameters.is_empty():
		error = _trace.sample(time, resolved, key_budget)
	if error != OK:
		return error
	for key: TwberTimelineKeyframeResource in pending:
		var id := key.layer_state.layer_id
		if replacements.has(id):
			_layer_keys[replacements[id]] = key
		else:
			_layer_keys.append(key)
		_last_states[id] = key.layer_state
	for key: TwberSpriteKeyframeResource in sprite_pending:
		if sprite_replacements.has(key.layer_id):
			_sprite_keys[sprite_replacements[key.layer_id]] = key
		else:
			_sprite_keys.append(key)
		_sprite_anchors[key.layer_id] = key
	_inputs = inputs
	_last_time = time
	return OK


func finish(duration: float) -> Dictionary:
	if not _running:
		return {"error": ERR_UNCONFIGURED}
	if not is_finite(duration) or duration < _last_time:
		return {"error": ERR_INVALID_PARAMETER}
	var clip := _trace.to_clip(duration) if not _parameters.is_empty() else TwberTimelineAnimationResource.new()
	if _parameters.is_empty():
		clip.duration = maxf(duration, 0.05)
		clip.loop = false
	if clip == null:
		return {"error": ERR_INVALID_PARAMETER}
	for key: TwberTimelineKeyframeResource in _layer_keys:
		clip.keyframes.append(key.duplicate(true))
	for key: TwberSpriteKeyframeResource in _sprite_keys:
		clip.sprite_keys.append(key.duplicate(true))
	var command := TwberImportParameterTake.new(clip)
	var error := _document.execute(command)
	if error != OK:
		return {"error": error}
	_trace = null
	_running = false
	return {
		"error": OK,
		"model": _document.snapshot().to_model_resource(),
		"animation_id": command.animation_id,
	}
