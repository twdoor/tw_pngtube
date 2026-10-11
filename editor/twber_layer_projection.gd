class_name TwberLayerProjection extends RefCounted

# Change existing layer properties without invalidating tool selections or
# rebuilding unaffected nodes. The caller restores previews before applying.
static func apply(model: TwberModelResource, root: Node2D, ids: Array[String], assets: bool) -> void:
	var layers := TwberLayerHierarchy.index(model)
	var nodes := TwberParameterMapper.get_layer_nodes_by_id(root)
	for id: String in ids:
		var node := nodes.get(id) as Node2D
		var layer := layers.get(id) as TwberLayerResource
		if node == null or layer == null:
			continue
		node.name = layer.name
		node.position = layer.position
		node.rotation = layer.rotation
		node.scale = layer.scale
		node.visible = layer.visible
		node.self_modulate = layer.modulate
		node.clip_children = layer.clip_children
		node.show_behind_parent = layer.show_behind_parent
		if node is TwberMeshSprite2D:
			if assets:
				node.texture = model.textures.get(layer.texture_id)
			node.mesh_data = layer.mesh.duplicate(true) if layer.mesh != null else TwberMeshResource.new()
			node.sync_mesh()
		elif node is Sprite2D or node is AnimatedSprite2D:
			node.offset = layer.offset
			node.centered = layer.centered
			node.flip_h = layer.flip_h
			node.flip_v = layer.flip_v
			if assets:
				if node is Sprite2D:
					node.texture = model.textures.get(layer.texture_id)
				else:
					node.sprite_frames = TwberModelCodec._sprite_frames_from_layer(layer, model)
					node.play(layer.current_animation)
	TwberModelCodec._set_model_parameters_on_root(root, model)
	TwberModelCodec._set_model_timeline_animations_on_root(root, model)
