class_name TwberDeleteLayers extends TwberDocumentCommand

var _ids: Array[String]
var selection_after := ""


func _init(ids: Array[String]) -> void:
	_ids = ids.duplicate()
	label = "Delete layers"
	kinds = TwberDocumentChange.Kind.STRUCTURE | TwberDocumentChange.Kind.RIG | TwberDocumentChange.Kind.ANIMATION


func apply(model: TwberModelResource) -> Error:
	did_change = false
	selection_after = ""
	layer_ids.clear()
	var layers := TwberLayerHierarchy.index(model)
	var parents := TwberLayerHierarchy.parents(model)
	for id: String in _ids:
		if not layers.has(id):
			return ERR_DOES_NOT_EXIST
	var roots := TwberLayerHierarchy.top_level(_ids, parents)
	var removed := {}
	for id: String in roots:
		for descendant: String in TwberLayerHierarchy.subtree(id, layers):
			removed[descendant] = true
	for id: String in roots:
		var siblings := TwberLayerHierarchy.children(model, parents[id])
		var old_index := siblings.find(id)
		siblings.erase(id)
		if roots.size() == 1:
			selection_after = siblings[mini(old_index, siblings.size() - 1)] if not siblings.is_empty() else parents[id]
		if not parents[id].is_empty() and not layer_ids.has(parents[id]):
			layer_ids.append(parents[id])
	for i: int in range(model.layers.size() - 1, -1, -1):
		if removed.has(model.layers[i].id):
			layer_ids.append(model.layers[i].id)
			model.layers.remove_at(i)
	for parameter: TwberParameterResource in model.parameters:
		for i: int in range(parameter.positions.size() - 1, -1, -1):
			var sample := parameter.positions[i]
			for j: int in range(sample.layer_states.size() - 1, -1, -1):
				if removed.has(sample.layer_states[j].layer_id):
					sample.layer_states.remove_at(j)
			if sample.layer_states.is_empty():
				parameter.positions.remove_at(i)
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		for i: int in range(animation.sprite_keys.size() - 1, -1, -1):
			if removed.has(animation.sprite_keys[i].layer_id):
				animation.sprite_keys.remove_at(i)
		for i: int in range(animation.keyframes.size() - 1, -1, -1):
			if removed.has(animation.keyframes[i].layer_state.layer_id):
				animation.keyframes.remove_at(i)
	did_change = not removed.is_empty()
	return OK
