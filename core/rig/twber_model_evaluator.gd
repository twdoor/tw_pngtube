class_name TwberModelEvaluator extends RefCounted

# Scene-free compiled instance. Inputs and source resources are never mutated.
# evaluate() returns borrowed pose buffers; duplicate states to retain a frame.
var _rig: Dictionary = {}
var _neutral: Dictionary = {}
var _parameters: Dictionary = {}
var _parameter_layers: Dictionary = {}
var _clips: Array[Dictionary] = []
var _affected: Dictionary = {}
var _poses: Dictionary = {}


func configure(model: TwberModelResource) -> void:
	_neutral.clear()
	_parameters.clear()
	_parameter_layers.clear()
	_clips.clear()
	_affected.clear()
	_poses.clear()
	var parameters: Array[TwberParameterResource] = []
	for source: TwberParameterResource in model.parameters:
		var parameter := source.duplicate(true) as TwberParameterResource
		parameters.append(parameter)
		_parameters[parameter.id] = parameter
	_rig = TwberParameterMapper.compile_parameters(parameters)
	for layer: TwberLayerResource in model.layers:
		_neutral[layer.id] = TwberLayerStateResource.from_layer_resource(layer)
	for entry: Dictionary in _rig.get("entries", []):
		var id: String = entry.parameter.id
		_parameter_layers[id] = entry.layers.keys()
		for layer_id: String in entry.layers:
			_affected[layer_id] = true
	for source: TwberTimelineAnimationResource in model.timeline_animations:
		var clip := source.duplicate(true) as TwberTimelineAnimationResource
		var layers := {}
		for id: String in clip.get_layer_ids():
			layers[id] = clip.get_keyframes_for_layer(id)
			_affected[id] = true
		var tracks := {}
		for key: TwberParameterKeyframeResource in clip.parameter_keys:
			if not tracks.has(key.parameter_id):
				var keys: Array[TwberParameterKeyframeResource] = []
				tracks[key.parameter_id] = keys
			tracks[key.parameter_id].append(key)
		for keys: Array in tracks.values():
			keys.sort_custom(func(a: TwberParameterKeyframeResource, b: TwberParameterKeyframeResource) -> bool: return a.time < b.time)
		_clips.append({"clip": clip, "layers": layers, "parameters": tracks})
	# Larger priority wins; equal priorities use stable clip IDs, never activation order.
	_clips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.clip.priority < b.clip.priority if a.clip.priority != b.clip.priority else a.clip.id < b.clip.id)


func resolve_parameters(values: Dictionary, playheads: Dictionary = {}) -> Dictionary:
	var resolved := {}
	for id: String in _parameters:
		var parameter: TwberParameterResource = _parameters[id]
		resolved[id] = parameter.value_from_coordinate(parameter.coordinate_from_value(values.get(id, parameter.get_default_value())))
	for entry: Dictionary in _clips:
		var clip: TwberTimelineAnimationResource = entry.clip
		if not playheads.has(clip.id):
			continue
		var time := clampf(float(playheads[clip.id]), 0.0, clip.duration)
		for id: String in entry.parameters:
			if _parameters.has(id):
				resolved[id] = TwberParameterKeyframeResource.sample(entry.parameters[id], time, _parameters[id])
	return resolved


func evaluate(values: Dictionary = {}, playheads: Dictionary = {}, targets: Dictionary = {}) -> Dictionary:
	var resolved := resolve_parameters(values, playheads)
	var rig := TwberParameterMapper.sample_compiled_parameters(_rig, resolved, _neutral, "", targets)
	var output := {}
	for id: String in _affected:
		if not _neutral.has(id) or (not targets.is_empty() and not targets.has(id)):
			continue
		if not _poses.has(id):
			_poses[id] = TwberLayerStateResource.new()
		TwberParameterMapper._reset_state_from_base(_poses[id], rig.get(id, _neutral[id]))
		output[id] = _poses[id]
	for entry: Dictionary in _clips:
		var clip: TwberTimelineAnimationResource = entry.clip
		if not playheads.has(clip.id):
			continue
		var time := clampf(float(playheads[clip.id]), 0.0, clip.duration)
		for id: String in entry.layers:
			if not output.has(id):
				continue
			var sample := TwberTimelineAnimationResource.sample_track(entry.layers[id], time, _neutral[id])
			if sample != null:
				TwberParameterMapper._reset_state_from_base(output[id], sample.materialized(output[id]))
	return output


func layers_for_parameters(ids: Array[String]) -> Dictionary:
	var layers := {}
	for id: String in ids:
		for layer_id: String in _parameter_layers.get(id, []):
			layers[layer_id] = true
	return layers


func neutral_states() -> Dictionary:
	var states := {}
	for id: String in _neutral:
		states[id] = _neutral[id].duplicate(true)
	return states
