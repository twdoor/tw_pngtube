class_name TwberCreateLayer extends TwberDocumentCommand

var created_layer_id := ""
var parent_id: String
var _layer: TwberLayerResource
var _textures: Dictionary[String, Texture2D]
var _sources: Dictionary[String, String]


func _init(layer: TwberLayerResource, parent := "", textures: Dictionary[String, Texture2D] = {}, sources: Dictionary[String, String] = {}) -> void:
	label = "Create layer"
	kinds = TwberDocumentChange.Kind.STRUCTURE | TwberDocumentChange.Kind.ASSETS
	_layer = layer.duplicate(true)
	parent_id = parent
	_textures = textures.duplicate()
	_sources = sources.duplicate()


func apply(model: TwberModelResource) -> Error:
	did_change = false
	created_layer_id = ""
	layer_ids.clear()
	var layers := TwberLayerHierarchy.index(model)
	if not parent_id.is_empty() and not layers.has(parent_id):
		return ERR_DOES_NOT_EXIST
	if not _layer.children.is_empty():
		return ERR_INVALID_PARAMETER
	var layer := _layer.duplicate(true) as TwberLayerResource
	var used := {}
	used.merge(layers)
	layer.id = TwberLayerHierarchy.allocate_id(used)
	layer.name = layer.name.validate_node_name()
	var siblings := TwberLayerHierarchy.children(model, parent_id)
	layer.name = TwberLayerHierarchy.unique_name(layer.name if not layer.name.is_empty() else "Layer", siblings, layers)
	var texture_ids := {}
	var used_textures := {}
	used_textures.merge(model.textures)
	for id: String in _textures:
		if _textures[id] == null:
			return ERR_INVALID_DATA
		var new_id := TwberLayerHierarchy.allocate_id(used_textures, "texture")
		texture_ids[id] = new_id
		model.textures[new_id] = _textures[id]
		if _sources.has(id):
			model.texture_sources[new_id] = _sources[id]
	if not layer.texture_id.is_empty():
		if not texture_ids.has(layer.texture_id):
			return ERR_DOES_NOT_EXIST
		layer.texture_id = texture_ids[layer.texture_id]
	for animation: TwberAnimationResource in layer.animations:
		for i: int in animation.frame_texture_ids.size():
			if not texture_ids.has(animation.frame_texture_ids[i]):
				return ERR_DOES_NOT_EXIST
			animation.frame_texture_ids[i] = texture_ids[animation.frame_texture_ids[i]]
	model.layers.append(layer)
	siblings.append(layer.id)
	created_layer_id = layer.id
	layer_ids = [layer.id]
	if not parent_id.is_empty():
		layer_ids.append(parent_id)
	did_change = true
	return OK
