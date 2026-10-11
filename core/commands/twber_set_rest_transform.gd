class_name TwberSetRestTransform extends TwberDocumentCommand

var layer_id: String
var position: Vector2
var rotation: float
var scale: Vector2


func _init(id: String, value_position: Vector2, value_rotation: float, value_scale: Vector2) -> void:
	label = "Change layer transform"
	kinds = TwberDocumentChange.Kind.REST_POSE | TwberDocumentChange.Kind.RIG | TwberDocumentChange.Kind.ANIMATION
	layer_id = id
	position = value_position
	rotation = value_rotation
	scale = value_scale
	layer_ids = [id]


func apply(model: TwberModelResource) -> Error:
	did_change = false
	if not position.is_finite() or not scale.is_finite() or not is_finite(rotation):
		return ERR_INVALID_PARAMETER
	for layer: TwberLayerResource in model.layers:
		if layer.id != layer_id:
			continue
		if layer.position == position and layer.rotation == rotation and layer.scale == scale:
			return OK
		var position_delta := position - layer.position
		var rotation_delta := rotation - layer.rotation
		var scale_delta := scale - layer.scale
		rebase_states(collect_states(model.parameters, model.timeline_animations, layer_id),
			position_delta, rotation_delta, scale_delta)
		layer.position = position
		layer.rotation = rotation
		layer.scale = scale
		did_change = true
		return OK
	return ERR_DOES_NOT_EXIST


static func collect_states(
		parameters: Array,
		animations: Array,
		id: String,
) -> Array[TwberLayerStateResource]:
	var output: Array[TwberLayerStateResource] = []
	# A Resource may be referenced by more than one sample. Rebase it once.
	var seen := {}
	for parameter: Variant in parameters:
		if parameter is not TwberParameterResource:
			continue
		for sample: TwberParameterPositionResource in parameter.positions:
			if sample == null:
				continue
			for state: TwberLayerStateResource in sample.layer_states:
				_append_state(state, id, output, seen)
	for animation: Variant in animations:
		if animation is not TwberTimelineAnimationResource:
			continue
		for key: TwberTimelineKeyframeResource in animation.keyframes:
			if key != null:
				_append_state(key.layer_state, id, output, seen)
	return output


static func rebase_states(
		states: Array[TwberLayerStateResource],
		position_delta: Vector2,
		rotation_delta: float,
		scale_delta: Vector2,
) -> void:
	# Compatibility rule for existing absolute samples: preserve each channel's
	# offset from rest. The future scale-ratio rig will have its own versioned rule.
	for state: TwberLayerStateResource in states:
		if state.has_channel(TwberLayerStateResource.Channel.POSITION):
			state.position += position_delta
		if state.has_channel(TwberLayerStateResource.Channel.ROTATION):
			state.rotation += rotation_delta
		if state.has_channel(TwberLayerStateResource.Channel.SCALE):
			state.scale += scale_delta


static func _append_state(
		state: TwberLayerStateResource,
		id: String,
		output: Array[TwberLayerStateResource],
		seen: Dictionary,
) -> void:
	if state != null and state.layer_id == id and not seen.has(state.get_instance_id()):
		seen[state.get_instance_id()] = true
		output.append(state)
