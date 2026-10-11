class_name TwberDuplicateLayers extends TwberDocumentCommand

var _ids: Array[String]
var duplicated_root_ids: Array[String] = []
var id_mapping: Dictionary[String, String] = {}


func _init(ids: Array[String]) -> void:
	_ids = ids.duplicate()
	label = "Duplicate layers"
	kinds = TwberDocumentChange.Kind.STRUCTURE | TwberDocumentChange.Kind.RIG | TwberDocumentChange.Kind.ANIMATION


func apply(model: TwberModelResource) -> Error:
	did_change = false
	duplicated_root_ids.clear()
	id_mapping.clear()
	layer_ids.clear()
	var layers := TwberLayerHierarchy.index(model)
	var parents := TwberLayerHierarchy.parents(model)
	for id: String in _ids:
		if not layers.has(id):
			return ERR_DOES_NOT_EXIST
	var roots := TwberLayerHierarchy.top_level(_ids, parents)
	var used := {}
	used.merge(layers)
	for id: String in roots:
		for descendant: String in TwberLayerHierarchy.subtree(id, layers):
			id_mapping[descendant] = TwberLayerHierarchy.allocate_id(used)
	for id: String in id_mapping:
		var copy := layers[id].duplicate(true) as TwberLayerResource
		copy.id = id_mapping[id]
		for i: int in copy.children.size():
			copy.children[i] = id_mapping[copy.children[i]]
		model.layers.append(copy)
		layers[copy.id] = copy
		layer_ids.append(copy.id)
	for id: String in roots:
		var siblings := TwberLayerHierarchy.children(model, parents[id])
		var copy := layers[id_mapping[id]]
		copy.name = TwberLayerHierarchy.unique_name(layers[id].name + " Copy", siblings, layers)
		siblings.insert(siblings.find(id) + 1, copy.id)
		duplicated_root_ids.append(copy.id)
		if not parents[id].is_empty() and not layer_ids.has(parents[id]):
			layer_ids.append(parents[id])
	for parameter: TwberParameterResource in model.parameters:
		for sample: TwberParameterPositionResource in parameter.positions:
			for state: TwberLayerStateResource in sample.layer_states.duplicate():
				if id_mapping.has(state.layer_id):
					var copy := state.duplicate(true) as TwberLayerStateResource
					copy.layer_id = id_mapping[state.layer_id]
					sample.layer_states.append(copy)
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		for key: TwberSpriteKeyframeResource in animation.sprite_keys.duplicate():
			if id_mapping.has(key.layer_id):
				var copy := key.duplicate(true) as TwberSpriteKeyframeResource
				copy.layer_id = id_mapping[key.layer_id]
				animation.sprite_keys.append(copy)
		for key: TwberTimelineKeyframeResource in animation.keyframes.duplicate():
			if id_mapping.has(key.layer_state.layer_id):
				var copy := key.duplicate(true) as TwberTimelineKeyframeResource
				copy.layer_state.layer_id = id_mapping[key.layer_state.layer_id]
				animation.keyframes.append(copy)
	did_change = not roots.is_empty()
	return OK
