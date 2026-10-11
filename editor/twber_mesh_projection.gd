class_name TwberMeshProjection extends RefCounted

# Apply only a layer's mesh/type changes; preserve other layers and camera state.
static func apply(model: TwberModelResource, root: Node2D, id: String) -> Node2D:
	var layer := TwberLayerHierarchy.index(model).get(id) as TwberLayerResource
	var node := TwberParameterMapper.get_layer_nodes_by_id(root).get(id) as Node2D
	if layer == null or node == null:
		return null
	if node is TwberMeshSprite2D and layer.type == TwberLayerResource.LayerType.MESH_SPRITE:
		node.mesh_data = layer.mesh.duplicate(true)
		node.sync_mesh()
	elif node is Sprite2D and layer.type == TwberLayerResource.LayerType.SPRITE:
		node.offset = layer.offset
		node.centered = layer.centered
	else:
		var replacement := TwberModelCodec._node_from_layer(layer, model)
		# Reuse the prepared texture/atlas mapping while only changing geometry.
		if (node is Sprite2D or node is TwberMeshSprite2D) and (replacement is Sprite2D or replacement is TwberMeshSprite2D):
			replacement.texture = node.texture
		var parent := node.get_parent()
		var index := node.get_index()
		for child: Node in node.get_children():
			node.remove_child(child)
			replacement.add_child(child)
		parent.remove_child(node)
		parent.add_child(replacement)
		parent.move_child(replacement, index)
		node.queue_free()
		node = replacement
	TwberModelCodec._set_model_parameters_on_root(root, model)
	TwberModelCodec._set_model_timeline_animations_on_root(root, model)
	return node
