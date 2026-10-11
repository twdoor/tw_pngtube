class_name TwberLayerHierarchy extends RefCounted

# Resource-only hierarchy operations. An empty parent ID denotes the model root.
static func index(model: TwberModelResource) -> Dictionary[String, TwberLayerResource]:
	var result: Dictionary[String, TwberLayerResource] = {}
	for layer: TwberLayerResource in model.layers:
		result[layer.id] = layer
	return result


static func parents(model: TwberModelResource) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	for id: String in model.root_layer_ids:
		result[id] = ""
	for layer: TwberLayerResource in model.layers:
		for id: String in layer.children:
			result[id] = layer.id
	return result


static func children(model: TwberModelResource, id: String) -> Array[String]:
	return model.root_layer_ids if id.is_empty() else index(model)[id].children


static func top_level(ids: Array[String], parent_ids: Dictionary[String, String]) -> Array[String]:
	var result: Array[String] = []
	for id: String in ids:
		var ancestor := parent_ids[id]
		while not ancestor.is_empty() and not ids.has(ancestor):
			ancestor = parent_ids[ancestor]
		if ancestor.is_empty() and not result.has(id):
			result.append(id)
	return result


static func subtree(id: String, layers: Dictionary[String, TwberLayerResource]) -> Array[String]:
	var result: Array[String] = [id]
	var cursor := 0
	while cursor < result.size():
		result.append_array(layers[result[cursor]].children)
		cursor += 1
	return result


static func allocate_id(used: Dictionary, prefix := "layer") -> String:
	var number := 1
	var id := "%s_%03d" % [prefix, number]
	while used.has(id):
		number += 1
		id = "%s_%03d" % [prefix, number]
	used[id] = true
	return id


static func unique_name(desired: String, siblings: Array[String], layers: Dictionary[String, TwberLayerResource]) -> String:
	var names := {}
	for id: String in siblings:
		names[layers[id].name] = true
	var result := desired
	var suffix := 2
	while names.has(result):
		result = "%s %d" % [desired, suffix]
		suffix += 1
	return result


static func local_transform(layer: TwberLayerResource) -> Transform2D:
	return Transform2D(layer.rotation, layer.scale, 0.0, layer.position)


static func global_transform(id: String, layers: Dictionary[String, TwberLayerResource], parent_ids: Dictionary[String, String]) -> Transform2D:
	var result := Transform2D.IDENTITY
	while not id.is_empty():
		result = local_transform(layers[id]) * result
		id = parent_ids[id]
	return result


static func representable(transform: Transform2D) -> bool:
	if not transform.is_finite() or is_zero_approx(transform.determinant()):
		return false
	# The v9 schema has no skew channel. Never silently drop a shear.
	return transform.is_equal_approx(Transform2D(transform.get_rotation(), transform.get_scale(), 0.0, transform.origin))
