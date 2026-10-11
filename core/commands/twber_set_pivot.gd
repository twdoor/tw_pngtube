class_name TwberSetPivot extends TwberDocumentCommand

var _id: String
var _pivot: Vector2


func _init(id: String, local_pivot: Vector2) -> void:
	_id = id
	_pivot = local_pivot
	label = "Change layer pivot"
	kinds = TwberDocumentChange.Kind.REST_POSE | TwberDocumentChange.Kind.RIG | TwberDocumentChange.Kind.ANIMATION


func apply(model: TwberModelResource) -> Error:
	did_change = false
	layer_ids.clear()
	var layers := TwberLayerHierarchy.index(model)
	var layer := layers.get(_id) as TwberLayerResource
	if layer == null:
		return ERR_DOES_NOT_EXIST
	if not _pivot.is_finite():
		return ERR_INVALID_PARAMETER
	if _pivot.is_zero_approx():
		return OK
	var old_base := TwberLayerStateResource.from_layer_resource(layer)
	var next_position := layer.position + (_pivot * layer.scale).rotated(layer.rotation)
	for state: TwberLayerStateResource in TwberSetRestTransform.collect_states(model.parameters, model.timeline_animations, _id):
		var resolved := state.materialized(old_base)
		var position := resolved.position + (_pivot * resolved.scale).rotated(resolved.rotation)
		# A rotation/scale-only sample may now need a position channel to keep
		# the artwork fixed around its newly chosen origin.
		if state.has_channel(TwberLayerStateResource.Channel.POSITION) or not position.is_equal_approx(next_position):
			state.channels |= TwberLayerStateResource.Channel.POSITION
			state.position = position
		if state.has_channel(TwberLayerStateResource.Channel.MESH):
			state.mesh_vertices = shifted(state.mesh_vertices, -_pivot)
	layer.position = next_position
	if layer.mesh != null:
		layer.mesh.texture_origin -= _pivot
		layer.mesh.vertices = shifted(layer.mesh.vertices, -_pivot)
		layer.mesh.rest_vertices = shifted(layer.mesh.rest_vertices, -_pivot)
	elif layer.type in [TwberLayerResource.LayerType.SPRITE, TwberLayerResource.LayerType.ANIMATED_SPRITE]:
		layer.offset -= _pivot
	layer_ids.append(_id)
	for child_id: String in layer.children:
		layers[child_id].position -= _pivot
		for state: TwberLayerStateResource in TwberSetRestTransform.collect_states(model.parameters, model.timeline_animations, child_id):
			if state.has_channel(TwberLayerStateResource.Channel.POSITION):
				state.position -= _pivot
		layer_ids.append(child_id)
	did_change = true
	return OK


static func shifted(values: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var output := values.duplicate()
	for index: int in output.size():
		output[index] += delta
	return output
