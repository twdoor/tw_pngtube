class_name TwberParameterTake extends RefCounted

# A timestamped normalized input trace. Changes are held until their observed
# timestamp; no curve fitting or UI/render-frame timing is baked into the data.
const MAX_KEYS := 200000
var _parameters: Dictionary = {}
var _keys: Array[TwberParameterKeyframeResource] = []
var _last_values: Dictionary = {}
var _last_time := -1.0


func _init(parameters: Array[TwberParameterResource]) -> void:
	for parameter: TwberParameterResource in parameters:
		_parameters[parameter.id] = parameter.duplicate(true)


func sample(time: float, values: Dictionary, key_limit := MAX_KEYS) -> Error:
	if not is_finite(time) or time < 0.0 or time < _last_time or (_last_time < 0.0 and time != 0.0):
		return ERR_INVALID_PARAMETER
	if _parameters.is_empty():
		return ERR_UNCONFIGURED
	var normalized := {}
	for id: String in _parameters:
		var parameter: TwberParameterResource = _parameters[id]
		if not values.has(id) and _last_values.has(id):
			normalized[id] = _last_values[id]
			continue
		var value: Variant = values.get(id, parameter.get_default_value())
		if (value is float and not is_finite(value)) or (value is Vector2 and not value.is_finite()):
			return ERR_INVALID_PARAMETER
		if parameter.value_type == TwberParameterResource.ValueType.VECTOR2 and not value is Vector2:
			return ERR_INVALID_PARAMETER
		if parameter.value_type != TwberParameterResource.ValueType.VECTOR2 and not (value is bool or value is float or value is int):
			return ERR_INVALID_PARAMETER
		normalized[id] = parameter.coordinate_from_value(value)
	var pending: Array[TwberParameterKeyframeResource] = []
	for id: String in normalized:
		if _last_values.has(id) and _last_values[id] == normalized[id]:
			continue
		var key := TwberParameterKeyframeResource.new()
		key.parameter_id = id
		key.coordinate = normalized[id]
		key.time = time
		key.interpolation = TwberParameterKeyframeResource.Interpolation.HOLD
		pending.append(key)
	var additions := pending.size()
	if time == _last_time:
		for key: TwberParameterKeyframeResource in pending:
			for index: int in range(_keys.size() - 1, -1, -1):
				var existing := _keys[index]
				if existing.time != time:
					break
				if existing.parameter_id == key.parameter_id:
					additions -= 1
					break
	if _keys.size() + additions > mini(key_limit, MAX_KEYS):
		return ERR_OUT_OF_MEMORY
	for key: TwberParameterKeyframeResource in pending:
		var replaced := false
		if time == _last_time:
			for index: int in range(_keys.size() - 1, -1, -1):
				if _keys[index].time != time:
					break
				if _keys[index].parameter_id == key.parameter_id:
					_keys[index] = key
					replaced = true
					break
		if not replaced:
			_keys.append(key)
	_last_values = normalized
	_last_time = time
	return OK


func to_clip(duration: float, fps := 30.0) -> TwberTimelineAnimationResource:
	if _keys.is_empty() or not is_finite(duration) or duration < _last_time or not is_finite(fps) or fps < 1.0 or fps > 120.0:
		return null
	var clip := TwberTimelineAnimationResource.new()
	clip.name = "Recorded take"
	clip.duration = maxf(duration, 0.05)
	clip.fps = fps
	clip.loop = false
	for key: TwberParameterKeyframeResource in _keys:
		clip.parameter_keys.append(key.duplicate(true))
	return clip
