class_name TwberSpriteClock extends RefCounted

var _animations := {}
var _states := {}


func configure(model: TwberModelResource) -> void:
	_animations.clear()
	_states.clear()
	for layer: TwberLayerResource in model.layers:
		if layer.type != TwberLayerResource.LayerType.ANIMATED_SPRITE or layer.animations.is_empty():
			continue
		var animations := {}
		for animation: TwberAnimationResource in layer.animations:
			animations[animation.name] = animation.duplicate(true)
		_animations[layer.id] = animations
		var name := layer.current_animation if animations.has(layer.current_animation) else layer.animations[0].name
		_states[layer.id] = {"animation": name, "phase": 0.0, "rate": maxf(animations[name].speed, 0.0)}


func is_empty() -> bool:
	return _states.is_empty()


func sync(poses: Dictionary) -> void:
	for id: String in _states:
		var pose := poses.get(id) as TwberLayerStateResource
		if pose == null:
			continue
		var state: Dictionary = _states[id]
		var name := pose.animation_name
		if not _animations[id].has(name):
			continue
		if state.animation != name:
			state.animation = name
			state.phase = 0.0
			state.rate = maxf(_animations[id][name].speed, 0.0)
		if pose.animation_frame_rate >= 0.0:
			state.rate = pose.animation_frame_rate


func advance(delta: float) -> void:
	for id: String in _states:
		var state: Dictionary = _states[id]
		state.phase = maxf(float(state.phase) + maxf(delta, 0.0) * float(state.rate), 0.0)


func states() -> Dictionary:
	return _states.duplicate(true)


func restore(states: Dictionary) -> void:
	_states = states.duplicate(true)
