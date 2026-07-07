class_name TwberModelCodec extends RefCounted

const FORMAT_NAME := "twber_model"
const TWBER_EXTENSION := "twber"
const LAYER_TYPE_EMPTY := 0
const LAYER_TYPE_SPRITE := 1
const LAYER_TYPE_ANIMATED_SPRITE := 2
const LAYER_TYPE_MESH_SPRITE := 3
const TwberAnimationResourceScript := preload("res://model/twber_animation_resource.gd")
const TwberLayerResourceScript := preload("res://model/twber_layer_resource.gd")
const TwberMeshResourceScript := preload("res://model/twber_mesh_resource.gd")
const TwberMeshSprite2DScript := preload("res://model/twber_mesh_sprite_2d.gd")
const TwberModelResourceScript := preload("res://model/twber_model_resource.gd")


static func _is_model_resource(resource: Variant) -> bool:
	return resource is Resource and resource.get_script() == TwberModelResourceScript


static func _is_layer_resource(resource: Variant) -> bool:
	return resource is Resource and resource.get_script() == TwberLayerResourceScript


static func _is_animation_resource(resource: Variant) -> bool:
	return resource is Resource and resource.get_script() == TwberAnimationResourceScript


static func _is_mesh_resource(resource: Variant) -> bool:
	return resource is Resource and resource.get_script() == TwberMeshResourceScript


static func from_model_root(model_root: Node2D) -> Resource:
	var model = TwberModelResourceScript.new()
	model.root_position = model_root.position
	model.root_scale = model_root.scale
	model.root_rotation = model_root.rotation

	var state := {
		"next_layer_index": 1,
		"next_texture_index": 1,
		"texture_ids_by_key": {},
	}
	_read_model_children(model_root, model, model.root_layer_ids, state)
	return model


static func apply_to_model_root(model: Resource, model_root: Node2D) -> void:
	for child: Node in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()

	model_root.position = model.root_position
	model_root.scale = model.root_scale
	model_root.rotation = model.root_rotation

	var layers_by_id := {}
	for layer_resource: Resource in model.layers:
		if _is_layer_resource(layer_resource):
			var layer := layer_resource
			if not layer.id.is_empty():
				layers_by_id[layer.id] = layer

	for layer_id: String in model.root_layer_ids:
		_add_layer_node(model_root, layer_id, model, layers_by_id)


static func save_resource(model: Resource, path: String) -> Error:
	return ResourceSaver.save(model, path)


static func load_model(path: String) -> Resource:
	var extension := path.get_extension().to_lower()
	if extension == TWBER_EXTENSION:
		return load_twber(path)

	var resource := ResourceLoader.load(path)
	if _is_model_resource(resource):
		return resource

	push_warning("Selected file is not a TwberModelResource: %s" % path)
	return null


static func export_twber(model: Resource, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(to_dictionary(model, true), "\t"))
	return OK


static func load_twber(path: String) -> Resource:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open model package: %s" % path)
		return null

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_warning("Could not parse model package: %s" % path)
		return null

	if json.data is not Dictionary:
		push_warning("Model package does not contain an object: %s" % path)
		return null

	return from_dictionary(json.data)


static func to_dictionary(model: Resource, include_texture_data: bool) -> Dictionary:
	var layers: Array[Dictionary] = []
	for layer_resource: Resource in model.layers:
		if _is_layer_resource(layer_resource):
			layers.append(_layer_to_dictionary(layer_resource))

	var texture_entries := {}
	for texture_key: Variant in model.textures.keys():
		var texture_id := String(texture_key)
		var texture: Texture2D = model.textures[texture_key]
		var entry := {
			"source": String(model.texture_sources.get(texture_id, "")),
		}
		if include_texture_data:
			entry["png"] = _texture_to_base64_png(texture)
		texture_entries[texture_id] = entry

	return {
		"format": FORMAT_NAME,
		"format_version": model.format_version,
		"root": {
			"position": _vector2_to_array(model.root_position),
			"scale": _vector2_to_array(model.root_scale),
			"rotation": model.root_rotation,
		},
		"root_layer_ids": _string_array_to_array(model.root_layer_ids),
		"layers": layers,
		"textures": texture_entries,
	}


static func from_dictionary(data: Dictionary) -> Resource:
	if String(data.get("format", "")) != FORMAT_NAME:
		push_warning("Unsupported model package format.")
		return null

	var model = TwberModelResourceScript.new()
	model.format_version = int(data.get("format_version", TwberModelResourceScript.FORMAT_VERSION))

	var root_data: Dictionary = data.get("root", {})
	model.root_position = _array_to_vector2(root_data.get("position", []), Vector2.ZERO)
	model.root_scale = _array_to_vector2(root_data.get("scale", []), Vector2.ONE)
	model.root_rotation = float(root_data.get("rotation", 0.0))
	model.root_layer_ids = _array_to_string_array(data.get("root_layer_ids", []))

	var textures_data: Dictionary = data.get("textures", {})
	for texture_key: Variant in textures_data.keys():
		var texture_id := String(texture_key)
		var texture_data: Dictionary = textures_data[texture_key]
		var texture := _texture_from_dictionary(texture_data)
		if texture != null:
			model.textures[texture_id] = texture
		model.texture_sources[texture_id] = String(texture_data.get("source", ""))

	var layers_data: Array = data.get("layers", [])
	for layer_data: Variant in layers_data:
		if layer_data is Dictionary:
			model.layers.append(_layer_from_dictionary(layer_data))

	return model


static func _read_model_children(
		parent: Node,
		model: Resource,
		output_child_ids: Array[String],
		state: Dictionary,
) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue

		var layer := _layer_from_node(child, model, state)
		model.layers.append(layer)
		output_child_ids.append(layer.id)
		_read_model_children(child, model, layer.children, state)


static func _layer_from_node(node: Node2D, model: Resource, state: Dictionary) -> Resource:
	var layer = TwberLayerResourceScript.new()
	layer.id = _next_layer_id(state)
	layer.name = node.name
	layer.position = node.position
	layer.scale = node.scale
	layer.rotation = node.rotation

	if node is CanvasItem:
		var canvas_item: CanvasItem = node
		layer.visible = canvas_item.visible
		layer.modulate = canvas_item.modulate
		layer.clip_children = canvas_item.clip_children

	if node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		layer.texture_id = _get_or_store_texture(mesh_sprite.texture, model, state)
		if mesh_sprite.has_mesh_points():
			layer.type = LAYER_TYPE_MESH_SPRITE
			if mesh_sprite.mesh_data != null:
				layer.mesh = mesh_sprite.mesh_data.duplicate(true)
		else:
			layer.type = LAYER_TYPE_SPRITE
	elif node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = node
		layer.type = LAYER_TYPE_ANIMATED_SPRITE
		layer.current_animation = String(animated_sprite.animation)
		_read_animated_sprite(animated_sprite, layer, model, state)
	elif node is Sprite2D:
		var sprite: Sprite2D = node
		layer.type = LAYER_TYPE_SPRITE
		layer.texture_id = _get_or_store_texture(sprite.texture, model, state)
	else:
		layer.type = LAYER_TYPE_EMPTY

	return layer


static func _read_animated_sprite(
		animated_sprite: AnimatedSprite2D,
		layer: Resource,
		model: Resource,
		state: Dictionary,
) -> void:
	if animated_sprite.sprite_frames == null:
		return

	var sprite_frames := animated_sprite.sprite_frames
	for animation_name: String in sprite_frames.get_animation_names():
		var animation = TwberAnimationResourceScript.new()
		animation.name = animation_name
		animation.speed = sprite_frames.get_animation_speed(animation_name)
		animation.loop = sprite_frames.get_animation_loop(animation_name)

		for frame_index: int in sprite_frames.get_frame_count(animation_name):
			var texture := sprite_frames.get_frame_texture(animation_name, frame_index)
			animation.frame_texture_ids.append(_get_or_store_texture(texture, model, state))
			animation.frame_durations.append(sprite_frames.get_frame_duration(animation_name, frame_index))

		layer.animations.append(animation)


static func _add_layer_node(
		parent: Node,
		layer_id: String,
		model: Resource,
		layers_by_id: Dictionary,
) -> void:
	if not layers_by_id.has(layer_id):
		return

	var layer: Resource = layers_by_id[layer_id]
	var node := _node_from_layer(layer, model)
	parent.add_child(node)

	for child_id: String in layer.children:
		_add_layer_node(node, child_id, model, layers_by_id)


static func _node_from_layer(layer: Resource, model: Resource) -> Node2D:
	var node: Node2D
	match layer.type:
		LAYER_TYPE_SPRITE:
			var sprite := Sprite2D.new()
			sprite.texture = _get_texture(model, layer.texture_id)
			node = sprite
		LAYER_TYPE_MESH_SPRITE:
			var mesh_sprite := TwberMeshSprite2DScript.new()
			mesh_sprite.texture = _get_texture(model, layer.texture_id)
			if _is_mesh_resource(layer.mesh):
				mesh_sprite.mesh_data = layer.mesh.duplicate(true)
			else:
				mesh_sprite.mesh_data = TwberMeshResourceScript.new()
				if mesh_sprite.texture != null:
					mesh_sprite.reset_texture_origin_from_texture()
			mesh_sprite.sync_mesh()
			node = mesh_sprite
		LAYER_TYPE_ANIMATED_SPRITE:
			var animated_sprite := AnimatedSprite2D.new()
			animated_sprite.sprite_frames = _sprite_frames_from_layer(layer, model)
			animated_sprite.animation = StringName(layer.current_animation)
			if not animated_sprite.sprite_frames.has_animation(animated_sprite.animation):
				animated_sprite.animation = _get_first_animation_name(animated_sprite.sprite_frames)
			if animated_sprite.sprite_frames.has_animation(animated_sprite.animation):
				if animated_sprite.sprite_frames.get_frame_count(animated_sprite.animation) > 0:
					animated_sprite.play(animated_sprite.animation)
			node = animated_sprite
		_:
			node = Node2D.new()

	node.name = layer.name
	node.position = layer.position
	node.scale = layer.scale
	node.rotation = layer.rotation
	node.visible = layer.visible
	node.modulate = layer.modulate
	node.clip_children = layer.clip_children
	return node


static func _sprite_frames_from_layer(layer: Resource, model: Resource) -> SpriteFrames:
	var sprite_frames := SpriteFrames.new()
	var saved_animation_names := {}
	for animation_resource: Resource in layer.animations:
		if _is_animation_resource(animation_resource):
			saved_animation_names[StringName(animation_resource.name)] = true

	if sprite_frames.has_animation(&"default") and not saved_animation_names.has(&"default"):
		sprite_frames.remove_animation(&"default")

	for animation_resource: Resource in layer.animations:
		if not _is_animation_resource(animation_resource):
			continue

		var animation := animation_resource
		var animation_name := StringName(animation.name)
		if not sprite_frames.has_animation(animation_name):
			sprite_frames.add_animation(animation_name)

		sprite_frames.clear(animation_name)
		sprite_frames.set_animation_speed(animation_name, animation.speed)
		sprite_frames.set_animation_loop(animation_name, animation.loop)

		for frame_index: int in animation.frame_texture_ids.size():
			var texture := _get_texture(model, animation.frame_texture_ids[frame_index])
			if texture == null:
				continue

			var duration := 1.0
			if frame_index < animation.frame_durations.size():
				duration = animation.frame_durations[frame_index]
			sprite_frames.add_frame(animation_name, texture, duration)

	return sprite_frames


static func _get_first_animation_name(sprite_frames: SpriteFrames) -> StringName:
	var animation_names := sprite_frames.get_animation_names()
	if animation_names.is_empty():
		return &""

	return StringName(animation_names[0])


static func _get_or_store_texture(texture: Texture2D, model: Resource, state: Dictionary) -> String:
	if texture == null:
		return ""

	var texture_ids_by_key: Dictionary = state["texture_ids_by_key"]
	var texture_key := _get_texture_key(texture)
	if texture_ids_by_key.has(texture_key):
		return texture_ids_by_key[texture_key]

	var texture_id := _next_texture_id(state)
	texture_ids_by_key[texture_key] = texture_id
	model.textures[texture_id] = texture
	model.texture_sources[texture_id] = texture.resource_path
	return texture_id


static func _get_texture(model: Resource, texture_id: String) -> Texture2D:
	if texture_id.is_empty() or not model.textures.has(texture_id):
		return null

	var texture: Variant = model.textures[texture_id]
	if texture is Texture2D:
		return texture

	return null


static func _get_texture_key(texture: Texture2D) -> String:
	if not texture.resource_path.is_empty():
		return "path:%s" % texture.resource_path

	return "object:%s" % texture.get_instance_id()


static func _next_layer_id(state: Dictionary) -> String:
	var index: int = state["next_layer_index"]
	state["next_layer_index"] = index + 1
	return "layer_%03d" % index


static func _next_texture_id(state: Dictionary) -> String:
	var index: int = state["next_texture_index"]
	state["next_texture_index"] = index + 1
	return "texture_%03d" % index


static func _layer_to_dictionary(layer: Resource) -> Dictionary:
	var animations: Array[Dictionary] = []
	for animation_resource: Resource in layer.animations:
		if _is_animation_resource(animation_resource):
			animations.append(_animation_to_dictionary(animation_resource))

	var output := {
		"id": layer.id,
		"name": layer.name,
		"type": layer.type,
		"children": _string_array_to_array(layer.children),
		"visible": layer.visible,
		"position": _vector2_to_array(layer.position),
		"scale": _vector2_to_array(layer.scale),
		"rotation": layer.rotation,
		"modulate": _color_to_array(layer.modulate),
		"clip_children": layer.clip_children,
		"texture_id": layer.texture_id,
		"current_animation": layer.current_animation,
		"animations": animations,
	}

	if _is_mesh_resource(layer.mesh):
		output["mesh"] = _mesh_to_dictionary(layer.mesh)

	return output


static func _layer_from_dictionary(data: Dictionary) -> Resource:
	var layer = TwberLayerResourceScript.new()
	layer.id = String(data.get("id", ""))
	layer.name = String(data.get("name", ""))
	layer.type = int(data.get("type", LAYER_TYPE_EMPTY))
	layer.children = _array_to_string_array(data.get("children", []))
	layer.visible = bool(data.get("visible", true))
	layer.position = _array_to_vector2(data.get("position", []), Vector2.ZERO)
	layer.scale = _array_to_vector2(data.get("scale", []), Vector2.ONE)
	layer.rotation = float(data.get("rotation", 0.0))
	layer.modulate = _array_to_color(data.get("modulate", []), Color.WHITE)
	layer.clip_children = int(data.get("clip_children", CanvasItem.CLIP_CHILDREN_DISABLED))
	layer.texture_id = String(data.get("texture_id", ""))
	layer.current_animation = String(data.get("current_animation", "default"))
	layer.mesh = _mesh_from_dictionary(data.get("mesh", {}))

	var animations_data: Array = data.get("animations", [])
	for animation_data: Variant in animations_data:
		if animation_data is Dictionary:
			layer.animations.append(_animation_from_dictionary(animation_data))

	return layer


static func _animation_to_dictionary(animation: Resource) -> Dictionary:
	return {
		"name": animation.name,
		"speed": animation.speed,
		"loop": animation.loop,
		"frame_texture_ids": _string_array_to_array(animation.frame_texture_ids),
		"frame_durations": _float_array_to_array(animation.frame_durations),
	}


static func _animation_from_dictionary(data: Dictionary) -> Resource:
	var animation = TwberAnimationResourceScript.new()
	animation.name = String(data.get("name", "default"))
	animation.speed = float(data.get("speed", 4.0))
	animation.loop = bool(data.get("loop", true))
	animation.frame_texture_ids = _array_to_string_array(data.get("frame_texture_ids", []))
	animation.frame_durations = _array_to_float_array(data.get("frame_durations", []))
	return animation


static func _mesh_to_dictionary(mesh: Resource) -> Dictionary:
	if not _is_mesh_resource(mesh):
		return {}

	return {
		"texture_origin": _vector2_to_array(mesh.texture_origin),
		"rest_vertices": _packed_vector2_array_to_array(mesh.rest_vertices),
		"vertices": _packed_vector2_array_to_array(mesh.vertices),
		"uvs": _packed_vector2_array_to_array(mesh.uvs),
		"triangles": _packed_int32_array_to_array(mesh.triangles),
	}


static func _mesh_from_dictionary(data: Variant) -> Resource:
	if data is not Dictionary:
		return null

	var mesh = TwberMeshResourceScript.new()
	mesh.texture_origin = _array_to_vector2(data.get("texture_origin", []), Vector2.ZERO)
	mesh.rest_vertices = _array_to_packed_vector2_array(data.get("rest_vertices", []))
	mesh.vertices = _array_to_packed_vector2_array(data.get("vertices", []))
	mesh.uvs = _array_to_packed_vector2_array(data.get("uvs", []))
	mesh.triangles = _array_to_packed_int32_array(data.get("triangles", []))

	if mesh.rest_vertices.size() != mesh.vertices.size():
		mesh.rest_vertices = mesh.vertices.duplicate()

	if mesh.uvs.size() != mesh.vertices.size():
		mesh.uvs = PackedVector2Array()
		for vertex: Vector2 in mesh.vertices:
			mesh.uvs.append(vertex - mesh.texture_origin)

	return mesh


static func _texture_to_base64_png(texture: Texture2D) -> String:
	if texture == null:
		return ""

	var image := texture.get_image()
	if image == null:
		return ""

	return Marshalls.raw_to_base64(image.save_png_to_buffer())


static func _texture_from_dictionary(data: Dictionary) -> Texture2D:
	var encoded_webp := String(data.get("webp", ""))
	if not encoded_webp.is_empty():
		var image := Image.new()
		var error := image.load_webp_from_buffer(Marshalls.base64_to_raw(encoded_webp))
		if error == OK:
			return ImageTexture.create_from_image(image)

	var encoded_png := String(data.get("png", ""))
	if not encoded_png.is_empty():
		var image := Image.new()
		var error := image.load_png_from_buffer(Marshalls.base64_to_raw(encoded_png))
		if error == OK:
			return ImageTexture.create_from_image(image)

	var source_path := String(data.get("source", ""))
	if not source_path.is_empty():
		var texture := load(source_path)
		if texture is Texture2D:
			return texture

	return null


static func _vector2_to_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]


static func _array_to_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is not Array or value.size() < 2:
		return fallback

	return Vector2(float(value[0]), float(value[1]))


static func _packed_vector2_array_to_array(values: PackedVector2Array) -> Array:
	var output: Array = []
	for value: Vector2 in values:
		output.append(_vector2_to_array(value))
	return output


static func _array_to_packed_vector2_array(values: Variant) -> PackedVector2Array:
	var output := PackedVector2Array()
	if values is not Array:
		return output

	for value: Variant in values:
		output.append(_array_to_vector2(value, Vector2.ZERO))
	return output


static func _packed_int32_array_to_array(values: PackedInt32Array) -> Array[int]:
	var output: Array[int] = []
	for value: int in values:
		output.append(value)
	return output


static func _array_to_packed_int32_array(values: Variant) -> PackedInt32Array:
	var output := PackedInt32Array()
	if values is not Array:
		return output

	for value: Variant in values:
		output.append(int(value))
	return output


static func _color_to_array(value: Color) -> Array[float]:
	return [value.r, value.g, value.b, value.a]


static func _array_to_color(value: Variant, fallback: Color) -> Color:
	if value is not Array or value.size() < 4:
		return fallback

	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _string_array_to_array(values: Array[String]) -> Array[String]:
	var output: Array[String] = []
	for value: String in values:
		output.append(value)
	return output


static func _array_to_string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	if values is not Array:
		return output

	for value: Variant in values:
		output.append(String(value))
	return output


static func _float_array_to_array(values: Array[float]) -> Array[float]:
	var output: Array[float] = []
	for value: float in values:
		output.append(value)
	return output


static func _array_to_float_array(values: Variant) -> Array[float]:
	var output: Array[float] = []
	if values is not Array:
		return output

	for value: Variant in values:
		output.append(float(value))
	return output
