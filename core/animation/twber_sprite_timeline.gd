class_name TwberSpriteTimeline extends RefCounted

# Unrecorded authored curves use a canonical 240 Hz integration grid plus exact
# key/switch boundaries. Seeking order and export FPS never change that grid.
# Captured anchors bypass integration and retain the actual live phase.
const TICKS_PER_SECOND := 240.0
var _model: TwberModelResource
var _evaluator := TwberModelEvaluator.new()
var _clock := TwberSpriteClock.new()
var _clips := {}
var _tracks := {}
var _boundaries := {}
var _timing_changes := {}
var _clip_id := ""
var _time := 0.0
var _tick := 1
var _boundary := 0


func configure(model: TwberModelResource) -> void:
	_model = model.duplicate(true)
	_evaluator.configure(_model)
	_clock.configure(_model)
	_clips.clear()
	_tracks.clear()
	_boundaries.clear()
	_timing_changes.clear()
	_clip_id = ""
	_time = 0.0
	for clip: TwberTimelineAnimationResource in _model.timeline_animations:
		_clips[clip.id] = clip
		var tracks := {}
		for key: TwberSpriteKeyframeResource in clip.sprite_keys:
			if not tracks.has(key.layer_id):
				tracks[key.layer_id] = []
			tracks[key.layer_id].append(key)
		for track: Array in tracks.values():
			track.sort_custom(func(a: TwberSpriteKeyframeResource, b: TwberSpriteKeyframeResource) -> bool: return a.time < b.time)
		_tracks[clip.id] = tracks
		var timing_changes := false
		var timing_mask := TwberLayerStateResource.Channel.ANIMATION | TwberLayerStateResource.Channel.ANIMATION_FRAME_RATE
		for key: TwberTimelineKeyframeResource in clip.keyframes:
			timing_changes = timing_changes or (key.layer_state.channels & timing_mask) != 0
		for key: TwberParameterKeyframeResource in clip.parameter_keys:
			var parameter := _find_parameter(key.parameter_id)
			if parameter == null:
				continue
			for sample: TwberParameterPositionResource in parameter.positions:
				for pose: TwberLayerStateResource in sample.layer_states:
					timing_changes = timing_changes or (pose.channels & timing_mask) != 0
		_timing_changes[clip.id] = timing_changes
		var times := {}
		for key: TwberParameterKeyframeResource in clip.parameter_keys:
			if key.time > 0.0:
				times[key.time] = true
		for id: String in clip.get_layer_ids():
			var track := clip.get_keyframes_for_layer(id)
			for index: int in track.size():
				if track[index].time > 0.0:
					times[track[index].time] = true
				if index > 0 and track[index - 1].interpolation == TwberTimelineKeyframeResource.Interpolation.LINEAR:
					# Legacy discrete property interpolation switches at midpoint.
					times[(track[index - 1].time + track[index].time) * 0.5] = true
		var sorted := times.keys()
		sorted.sort()
		_boundaries[clip.id] = sorted


func seek(id: String, time: float) -> Dictionary:
	if not _clips.has(id) or not is_finite(time) or time < 0.0 or _clock.is_empty():
		return {}
	time = minf(time, _clips[id].duration)
	var tracks: Dictionary = _tracks[id]
	var output: Dictionary
	if tracks.size() == _clock.states().size():
		output = {}
	elif not _timing_changes[id]:
		var constant_clock := TwberSpriteClock.new()
		constant_clock.configure(_model)
		constant_clock.sync(_evaluator.evaluate({}, {id: 0.0}))
		constant_clock.advance(time)
		output = constant_clock.states()
	else:
		if _clip_id != id or time < _time:
			_clock.configure(_model)
			_clock.sync(_evaluator.evaluate({}, {id: 0.0}))
			_clip_id = id
			_time = 0.0
			_tick = 1
			_boundary = 0
		var boundaries: Array = _boundaries[id]
		while true:
			var next := float(_tick) / TICKS_PER_SECOND
			if _boundary < boundaries.size():
				next = minf(next, boundaries[_boundary])
			if next > time:
				break
			_clock.advance(next - _time)
			_clock.sync(_evaluator.evaluate({}, {id: next}))
			_time = next
			if next >= float(_tick) / TICKS_PER_SECOND:
				_tick += 1
			if _boundary < boundaries.size() and next >= boundaries[_boundary]:
				_boundary += 1
		# Fractional seeks never change the cached canonical boundary state.
		var checkpoint := _clock.states()
		_clock.advance(time - _time)
		_clock.sync(_evaluator.evaluate({}, {id: time}))
		output = _clock.states()
		_clock.restore(checkpoint)
	for layer_id: String in tracks:
		var track: Array = tracks[layer_id]
		var index := _key_at(track, time)
		if index >= 0:
			output[layer_id] = (track[index] as TwberSpriteKeyframeResource).state_at(time)
	return output


static func _key_at(track: Array, time: float) -> int:
	var low := 0
	var high := track.size()
	while low < high:
		var middle := (low + high) / 2
		if track[middle].time <= time:
			low = middle + 1
		else:
			high = middle
	return low - 1


func rest_states() -> Dictionary:
	var clock := TwberSpriteClock.new()
	clock.configure(_model)
	return clock.states()


func _find_parameter(id: String) -> TwberParameterResource:
	for parameter: TwberParameterResource in _model.parameters:
		if parameter.id == id:
			return parameter
	return null
