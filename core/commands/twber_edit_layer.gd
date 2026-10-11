class_name TwberEditLayer extends TwberDocumentCommand

enum Operation { SETTINGS, REPLACE_TEXTURE, REPLACE_FRAMES, CREATE_ANIMATION, RENAME_ANIMATION, DELETE_ANIMATION, SET_ANIMATION_SPEED, SELECT_ANIMATION }

var operation: Operation
var _id: String
var _data: Dictionary
var _textures: Array[Texture2D] = []


func _init(id: String, action: Operation, data: Dictionary = {}, textures: Array[Texture2D] = []) -> void:
	_id = id
	operation = action
	_data = data.duplicate(true)
	for texture: Texture2D in textures:
		_textures.append(texture.duplicate(true) if texture != null else null)
	label = ["Change layer settings", "Replace layer texture", "Replace sprite frames", "Create sprite animation", "Rename sprite animation", "Delete sprite animation", "Change sprite frame rate", "Select sprite animation"][action]
	kinds = TwberDocumentChange.Kind.REST_POSE
	if action != Operation.SETTINGS:
		kinds |= TwberDocumentChange.Kind.ASSETS


func apply(model: TwberModelResource) -> Error:
	did_change = false
	layer_ids = [_id]
	var layers := TwberLayerHierarchy.index(model)
	var layer := layers.get(_id) as TwberLayerResource
	if layer == null:
		return ERR_DOES_NOT_EXIST
	if operation == Operation.SETTINGS:
		return _settings(model, layer, layers)
	if operation == Operation.REPLACE_TEXTURE:
		if layer.type not in [TwberLayerResource.LayerType.SPRITE, TwberLayerResource.LayerType.MESH_SPRITE] or _textures.size() != 1 or _textures[0] == null:
			return ERR_INVALID_PARAMETER
		var previous: Texture2D = model.textures.get(layer.texture_id)
		var texture := _textures[0]
		if layer.mesh != null:
			layer.mesh.texture_origin += TwberTextureUtils.get_logical_texture_origin(texture) - TwberTextureUtils.get_logical_texture_origin(previous)
			var vertices := layer.mesh.rest_vertices if layer.mesh.rest_vertices.size() == layer.mesh.vertices.size() else layer.mesh.vertices
			layer.mesh.uvs.clear()
			for vertex: Vector2 in vertices:
				layer.mesh.uvs.append(vertex - layer.mesh.texture_origin)
		else:
			layer.offset += TwberTextureUtils.get_centered_sprite_offset(texture) - TwberTextureUtils.get_centered_sprite_offset(previous)
		layer.texture_id = _add_texture(model, texture)
		did_change = true
		return OK
	if layer.type != TwberLayerResource.LayerType.ANIMATED_SPRITE:
		return ERR_INVALID_PARAMETER
	var name := String(_data.get("animation", layer.current_animation))
	var animation: TwberAnimationResource
	for item: TwberAnimationResource in layer.animations:
		if item.name == name:
			animation = item
	if animation == null:
		return ERR_DOES_NOT_EXIST
	match operation:
		Operation.REPLACE_FRAMES:
			if _textures.is_empty() or _textures.has(null):
				return ERR_INVALID_PARAMETER
			var previous: Texture2D = null
			if not animation.frame_texture_ids.is_empty():
				previous = model.textures.get(animation.frame_texture_ids[0])
			layer.offset += TwberTextureUtils.get_centered_sprite_offset(_textures[0]) - TwberTextureUtils.get_centered_sprite_offset(previous)
			animation.frame_texture_ids.clear()
			animation.frame_durations.clear()
			for texture: Texture2D in _textures:
				animation.frame_texture_ids.append(_add_texture(model, texture))
				animation.frame_durations.append(1.0)
			layer.current_animation = animation.name
		Operation.CREATE_ANIMATION:
			var copy := animation.duplicate(true) as TwberAnimationResource
			copy.name = _unique_animation_name(layer, String(_data.get("name", "Animation")))
			layer.animations.append(copy)
			layer.current_animation = copy.name
		Operation.RENAME_ANIMATION:
			var next_name := _unique_animation_name(layer, String(_data.get("name", "Animation")), name)
			if next_name == name:
				return OK
			animation.name = next_name
			if layer.current_animation == name:
				layer.current_animation = next_name
			_remap_animation_states(model, name, next_name)
		Operation.DELETE_ANIMATION:
			if layer.animations.size() <= 1:
				error_message = "Keep at least one sprite animation"
				return ERR_INVALID_PARAMETER
			layer.animations.erase(animation)
			var fallback := layer.animations[0].name
			if layer.current_animation == name:
				layer.current_animation = fallback
			_remap_animation_states(model, name, fallback)
		Operation.SET_ANIMATION_SPEED:
			var value: Variant = _data.get("speed")
			if (not value is float and not value is int) or not is_finite(float(value)) or float(value) < 0.0:
				return ERR_INVALID_PARAMETER
			if animation.speed == float(value):
				return OK
			animation.speed = float(value)
		Operation.SELECT_ANIMATION:
			if layer.current_animation == name:
				return OK
			layer.current_animation = name
		_:
			return ERR_INVALID_PARAMETER
	did_change = true
	return OK


func _settings(model: TwberModelResource, layer: TwberLayerResource, layers: Dictionary) -> Error:
	for field: Variant in _data:
		var value: Variant = _data[field]
		match field:
			"name":
				if not value is String:
					return ERR_INVALID_PARAMETER
				value = value.strip_edges().validate_node_name()
				if value.is_empty():
					return ERR_INVALID_PARAMETER
				var siblings := TwberLayerHierarchy.children(model, TwberLayerHierarchy.parents(model)[_id]).duplicate()
				siblings.erase(_id)
				value = TwberLayerHierarchy.unique_name(value, siblings, layers)
			"visible", "show_behind_parent":
				if not value is bool:
					return ERR_INVALID_PARAMETER
			"clip_children":
				if not value is int or value < 0 or value > CanvasItem.CLIP_CHILDREN_AND_DRAW:
					return ERR_INVALID_PARAMETER
			"opacity":
				if (not value is float and not value is int) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
					return ERR_INVALID_PARAMETER
				if not is_equal_approx(layer.modulate.a, float(value)):
					layer.modulate.a = float(value)
					did_change = true
				continue
			_:
				return ERR_INVALID_PARAMETER
		if layer.get(field) != value:
			layer.set(field, value)
			did_change = true
	return OK


func _remap_animation_states(model: TwberModelResource, previous: String, next: String) -> void:
	for state: TwberLayerStateResource in TwberSetRestTransform.collect_states(model.parameters, model.timeline_animations, _id):
		if state.has_channel(TwberLayerStateResource.Channel.ANIMATION) and state.animation_name == previous:
			state.animation_name = next
			kinds |= TwberDocumentChange.Kind.RIG | TwberDocumentChange.Kind.ANIMATION

	for clip: TwberTimelineAnimationResource in model.timeline_animations:
		for key: TwberSpriteKeyframeResource in clip.sprite_keys:
			if key.layer_id == _id and key.animation_name == previous:
				key.animation_name = next
				kinds |= TwberDocumentChange.Kind.ANIMATION


static func _unique_animation_name(layer: TwberLayerResource, desired: String, ignored := "") -> String:
	var base := desired.strip_edges()
	if base.is_empty():
		base = "Animation"
	var used := {}
	for animation: TwberAnimationResource in layer.animations:
		if animation.name != ignored:
			used[animation.name] = true
	var name := base
	var index := 2
	while used.has(name):
		name = "%s %d" % [base, index]
		index += 1
	return name


static func _add_texture(model: TwberModelResource, texture: Texture2D) -> String:
	var used := {}
	used.merge(model.textures)
	var id := TwberLayerHierarchy.allocate_id(used, "texture")
	model.textures[id] = texture
	model.texture_sources[id] = TwberModelCodec._get_texture_source_path(texture)
	return id
