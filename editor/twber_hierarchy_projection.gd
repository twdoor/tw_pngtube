class_name TwberHierarchyProjection extends RefCounted

# A structural command only changes membership, order, names and transforms.
# Keep surviving nodes (and their prepared textures) instead of recapturing them.
static func apply(model: TwberModelResource, root: Node2D) -> void:
	var nodes := TwberParameterMapper.get_layer_nodes_by_id(root)
	var layers := TwberLayerHierarchy.index(model)
	for id: String in nodes:
		if not layers.has(id):
			var node: Node2D = nodes[id]
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	for layer: TwberLayerResource in model.layers:
		if not nodes.has(layer.id):
			nodes[layer.id] = TwberModelCodec._node_from_layer(layer, model)
	_attach_children(root, model.root_layer_ids, nodes, layers)
	TwberModelCodec._set_model_parameters_on_root(root, model)
	TwberModelCodec._set_model_timeline_animations_on_root(root, model)


static func _attach_children(parent: Node2D, ids: Array[String], nodes: Dictionary, layers: Dictionary[String, TwberLayerResource]) -> void:
	for i: int in ids.size():
		var node: Node2D = nodes[ids[i]]
		var layer := layers[ids[i]]
		if node.get_parent() != parent:
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			parent.add_child(node)
		parent.move_child(node, i)
		node.name = layer.name
		node.position = layer.position
		node.rotation = layer.rotation
		node.scale = layer.scale
		_attach_children(node, layer.children, nodes, layers)
