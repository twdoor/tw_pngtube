class_name TwberReparentLayers extends TwberDocumentCommand

const TRANSFORM_CHANNELS := (TwberLayerStateResource.Channel.POSITION
	| TwberLayerStateResource.Channel.ROTATION | TwberLayerStateResource.Channel.SCALE)

var _ids: Array[String]
var _parent: String
var _before: String
var moved_ids: Array[String] = []


# before_id is a destination sibling; empty means append, after removing movers.
func _init(ids: Array[String], parent_id: String, before_id := "") -> void:
	_ids = ids.duplicate()
	_parent = parent_id
	_before = before_id
	label = "Move layers"
	kinds = (TwberDocumentChange.Kind.STRUCTURE | TwberDocumentChange.Kind.REST_POSE
		| TwberDocumentChange.Kind.RIG | TwberDocumentChange.Kind.ANIMATION)


func apply(model: TwberModelResource) -> Error:
	did_change = false
	layer_ids.clear()
	moved_ids.clear()
	var layers := TwberLayerHierarchy.index(model)
	var parents := TwberLayerHierarchy.parents(model)
	if not _parent.is_empty() and not layers.has(_parent):
		return ERR_DOES_NOT_EXIST
	for id: String in _ids:
		if not layers.has(id):
			return ERR_DOES_NOT_EXIST
	moved_ids = TwberLayerHierarchy.top_level(_ids, parents)
	var destination := TwberLayerHierarchy.children(model, _parent)
	if not _before.is_empty() and (not destination.has(_before) or moved_ids.has(_before)):
		return ERR_INVALID_PARAMETER
	for id: String in moved_ids:
		if TwberLayerHierarchy.subtree(id, layers).has(_parent):
			error_message = "A layer cannot be moved inside itself or its descendants"
			return ERR_INVALID_PARAMETER
	var original_destination := destination.duplicate()
	for id: String in moved_ids:
		if parents[id] != _parent:
			var new_parent_transform := TwberLayerHierarchy.global_transform(_parent, layers, parents)
			if is_zero_approx(new_parent_transform.determinant()):
				error_message = "The destination parent has a zero scale"
				return ERR_INVALID_DATA
			var conversion := new_parent_transform.affine_inverse() * TwberLayerHierarchy.global_transform(parents[id], layers, parents)
			var layer := layers[id]
			var rest := conversion * TwberLayerHierarchy.local_transform(layer)
			if not TwberLayerHierarchy.representable(rest):
				error_message = "This move needs skew or a degenerate transform, which the current model format cannot preserve"
				return ERR_INVALID_DATA
			# Preserve each authored sample in the parents' neutral coordinate spaces.
			# Animated parent motion follows the new hierarchy after the move.
			for state: TwberLayerStateResource in TwberSetRestTransform.collect_states(model.parameters, model.timeline_animations, id):
				if (state.channels & TRANSFORM_CHANNELS) == 0:
					continue
				var pose := conversion * Transform2D(
					state.rotation if state.has_channel(TwberLayerStateResource.Channel.ROTATION) else layer.rotation,
					state.scale if state.has_channel(TwberLayerStateResource.Channel.SCALE) else layer.scale,
					0.0,
					state.position if state.has_channel(TwberLayerStateResource.Channel.POSITION) else layer.position)
				if not TwberLayerHierarchy.representable(pose):
					error_message = "An authored pose would require skew or a degenerate transform after this move"
					return ERR_INVALID_DATA
				# Add a coupled channel only if the coordinate conversion requires it.
				if not pose.origin.is_equal_approx(rest.origin):
					state.channels |= TwberLayerStateResource.Channel.POSITION
				if not is_zero_approx(angle_difference(pose.get_rotation(), rest.get_rotation())):
					state.channels |= TwberLayerStateResource.Channel.ROTATION
				if not pose.get_scale().is_equal_approx(rest.get_scale()):
					state.channels |= TwberLayerStateResource.Channel.SCALE
				if state.has_channel(TwberLayerStateResource.Channel.POSITION):
					state.position = pose.origin
				if state.has_channel(TwberLayerStateResource.Channel.ROTATION):
					state.rotation = pose.get_rotation()
				if state.has_channel(TwberLayerStateResource.Channel.SCALE):
					state.scale = pose.get_scale()
			layer.position = rest.origin
			layer.rotation = rest.get_rotation()
			layer.scale = rest.get_scale()
			did_change = true
	for id: String in moved_ids:
		TwberLayerHierarchy.children(model, parents[id]).erase(id)
		if not parents[id].is_empty() and not layer_ids.has(parents[id]):
			layer_ids.append(parents[id])
	var insertion := destination.size() if _before.is_empty() else destination.find(_before)
	for id: String in moved_ids:
		if parents[id] != _parent:
			layers[id].name = TwberLayerHierarchy.unique_name(layers[id].name, destination, layers)
		destination.insert(insertion, id)
		insertion += 1
		layer_ids.append(id)
	if not _parent.is_empty() and not layer_ids.has(_parent):
		layer_ids.append(_parent)
	did_change = did_change or destination != original_destination
	return OK
