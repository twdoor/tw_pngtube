class_name TwberModelCodec extends RefCounted

const FORMAT_NAME := "twber_model"
const TWBER_EXTENSION := "twber"
const PACKAGE_FORMAT := "twber_archive"
const PACKAGE_VERSION := 1
const PACKAGE_MANIFEST_PATH := "manifest.json"
const PACKAGE_MODEL_PATH := "data/model.bin"
const ATLAS_MAX_SIZE := 4096
const ATLAS_PADDING := 2
const TEXTURE_SOURCE_PATH_META := &"twber_source_path"
const LAYER_ID_META := &"twber_layer_id"
const MODEL_PARAMETERS_META := &"twber_parameters"

static func from_model_root(model_root: Node2D) -> TwberModelResource:
	if model_root == null:
		return null

	var model := TwberModelResource.new()
	model.root_position = model_root.position
	model.root_scale = model_root.scale
	model.root_rotation = model_root.rotation
	model.parameters.assign(_get_model_resources_from_root(
			model_root,
			MODEL_PARAMETERS_META,
			func(value: Variant) -> bool: return value is TwberParameterResource,
	))

	var state := _create_layer_id_state(model_root)
	state["next_texture_index"] = 1
	state["texture_ids_by_key"] = {}
	_read_model_children(model_root, model, model.root_layer_ids, state)
	return model


static func apply_to_model_root(model: TwberModelResource, model_root: Node2D) -> void:
	if model == null or model_root == null:
		return

	for child: Node in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()

	model_root.position = model.root_position
	model_root.scale = model.root_scale
	model_root.rotation = model.root_rotation
	_set_model_parameters_on_root(model_root, model)

	var layers_by_id: Dictionary[String, TwberLayerResource] = {}
	for layer: TwberLayerResource in model.layers:
		if layer == null:
			continue
		if layer.id.is_empty():
			continue
		if layers_by_id.has(layer.id):
			push_warning("Ignoring duplicate layer id: %s" % layer.id)
			continue
		layers_by_id[layer.id] = layer

	var added_layer_ids := {}
	for layer_id: String in model.root_layer_ids:
		_add_layer_node(model_root, layer_id, model, layers_by_id, added_layer_ids)


static func clear_model_root_metadata(model_root: Node2D) -> void:
	if model_root == null:
		return

	if model_root.has_meta(MODEL_PARAMETERS_META):
		model_root.remove_meta(MODEL_PARAMETERS_META)


static func ensure_layer_ids(model_root: Node2D) -> void:
	if model_root == null:
		return

	_assign_layer_ids(model_root, _create_layer_id_state(model_root))


static func save_resource(model: TwberModelResource, path: String) -> Error:
	if model == null:
		return ERR_INVALID_PARAMETER

	_normalize_loaded_model(model)
	return ResourceSaver.save(model, path)


static func load_model(path: String) -> TwberModelResource:
	var extension := path.get_extension().to_lower()
	if extension == TWBER_EXTENSION:
		return load_twber(path)

	var resource := ResourceLoader.load(path)
	if resource is TwberModelResource:
		if resource.format_version > TwberModelResource.FORMAT_VERSION:
			push_warning("Model uses a newer unsupported format version: %s" % path)
			return null
		return _normalize_loaded_model(resource)

	push_warning("Selected file is not a TwberModelResource: %s" % path)
	return null


static func export_twber(model: TwberModelResource, path: String) -> Error:
	if model == null:
		return ERR_INVALID_PARAMETER

	_normalize_loaded_model(model)
	var model_data := to_dictionary(model, false)
	var texture_entries: Dictionary = model_data.get("textures", {})
	var texture_package := _build_texture_package(model, texture_entries)
	var failed_texture_ids: Array = texture_package.get("failed_texture_ids", [])
	if not failed_texture_ids.is_empty():
		push_error("Could not export texture data for: %s" % ", ".join(failed_texture_ids))
		return ERR_FILE_CORRUPT
	var texture_payloads: Dictionary = texture_package.get("payloads", {})
	var texture_manifest: Dictionary = texture_package.get("manifest", {})

	var model_bytes := var_to_bytes(model_data)
	var summary := get_model_performance_summary(model)
	summary["estimated_draw_calls"] = _estimate_model_render_batches(
			model,
			int(summary.get("drawable_layers", 0)),
			int(summary.get("clipped_layers", 0)),
			texture_entries,
	)
	summary["atlas_pages"] = int(texture_package.get("atlas_pages", 0))
	summary["standalone_textures"] = int(texture_package.get("standalone_textures", 0))
	var manifest := {
		"package_format": PACKAGE_FORMAT,
		"package_version": PACKAGE_VERSION,
		"model_format": FORMAT_NAME,
		"model_format_version": TwberModelResource.FORMAT_VERSION,
		"model_file": PACKAGE_MODEL_PATH,
		"model_sha256": _sha256_hex(model_bytes),
		"textures": texture_manifest,
		"summary": summary,
	}

	var temporary_path := "%s.tmp" % path
	_remove_file_if_exists(temporary_path)
	var packer := ZIPPacker.new()
	var error := packer.open(temporary_path)
	if error != OK:
		return error
	error = _write_package_file(
			packer,
			PACKAGE_MANIFEST_PATH,
			JSON.stringify(manifest, "\t").to_utf8_buffer(),
	)
	if error == OK:
		error = _write_package_file(packer, PACKAGE_MODEL_PATH, model_bytes)
	if error == OK:
		for texture_path: Variant in texture_payloads:
			error = _write_package_file(
					packer,
					String(texture_path),
					texture_payloads[texture_path],
			)
			if error != OK:
				break
	var close_error := packer.close()
	var result := error if error != OK else close_error
	if result != OK:
		_remove_file_if_exists(temporary_path)
		return result
	return _replace_file_atomically(temporary_path, path)


static func load_twber(path: String) -> TwberModelResource:
	var archive := ZIPReader.new()
	if archive.open(path) == OK:
		var archive_model := _load_twber_archive(archive, path)
		archive.close()
		return archive_model

	# Version 1 packages were JSON files with base64-encoded PNGs. Keep this
	# fallback so existing exported models remain usable.
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


static func _load_twber_archive(archive: ZIPReader, path: String) -> TwberModelResource:
	var files := archive.get_files()
	if not files.has(PACKAGE_MANIFEST_PATH):
		push_warning("Twber archive has no manifest: %s" % path)
		return null

	var json := JSON.new()
	if json.parse(archive.read_file(PACKAGE_MANIFEST_PATH).get_string_from_utf8()) != OK:
		push_warning("Could not parse Twber archive manifest: %s" % path)
		return null
	if json.data is not Dictionary:
		push_warning("Twber archive manifest is invalid: %s" % path)
		return null

	var manifest: Dictionary = json.data
	if _variant_to_string(manifest.get("package_format", "")) != PACKAGE_FORMAT:
		push_warning("Unsupported Twber archive format: %s" % path)
		return null
	var package_version := _variant_to_int(manifest.get("package_version", 0))
	if package_version > PACKAGE_VERSION or package_version < 1:
		push_warning("Unsupported Twber archive version: %s" % package_version)
		return null

	var model_path := _variant_to_string(manifest.get("model_file", PACKAGE_MODEL_PATH))
	if not files.has(model_path):
		push_warning("Twber archive has no model data: %s" % path)
		return null
	var model_bytes := archive.read_file(model_path)
	var expected_model_hash := _variant_to_string(manifest.get("model_sha256", ""))
	if not expected_model_hash.is_empty() and _sha256_hex(model_bytes) != expected_model_hash:
		push_warning("Twber archive model checksum failed: %s" % path)
		return null

	var decoded: Variant = bytes_to_var(model_bytes)
	if decoded is not Dictionary:
		push_warning("Twber archive model data is invalid: %s" % path)
		return null
	var decoded_data: Dictionary = decoded
	var decoded_textures: Dictionary = decoded_data.get("textures", {})
	for texture_key: Variant in decoded_textures:
		var texture_entry: Dictionary = decoded_textures[texture_key]
		texture_entry["_package_path"] = path
		decoded_textures[texture_key] = texture_entry
	decoded_data["textures"] = decoded_textures

	var texture_loader := func(texture_path: String, expected_hash: String) -> PackedByteArray:
		if texture_path.is_empty() or not files.has(texture_path):
			return PackedByteArray()
		var payload := archive.read_file(texture_path)
		if not expected_hash.is_empty() and _sha256_hex(payload) != expected_hash:
			push_warning("Twber texture checksum failed: %s" % texture_path)
			return PackedByteArray()
		return payload
	return from_dictionary(decoded_data, texture_loader)


static func to_dictionary(model: TwberModelResource, include_texture_data: bool) -> Dictionary:
	if model == null:
		return {}

	var layers: Array[Dictionary] = []
	for layer: TwberLayerResource in model.layers:
		if layer == null:
			continue
		layers.append(_layer_to_dictionary(layer))

	var parameters: Array[Dictionary] = []
	for parameter: TwberParameterResource in model.parameters:
		if parameter == null:
			continue
		parameters.append(_parameter_to_dictionary(parameter))

	var texture_entries := {}
	for texture_key: Variant in model.textures.keys():
		var texture_id := String(texture_key)
		var texture: Texture2D = model.textures[texture_key]
		var entry := {
			"source": String(model.texture_sources.get(texture_id, "")),
		}
		entry.merge(_texture_metadata_to_dictionary(texture), true)
		if include_texture_data:
			entry["png"] = _texture_to_base64_png(texture)
		texture_entries[texture_id] = entry

	return {
		"format": FORMAT_NAME,
		"format_version": TwberModelResource.FORMAT_VERSION,
		"root": {
			"position": _vector2_to_array(model.root_position),
			"scale": _vector2_to_array(model.root_scale),
			"rotation": model.root_rotation,
		},
		"root_layer_ids": model.root_layer_ids.duplicate(),
		"layers": layers,
		"parameters": parameters,
		"textures": texture_entries,
	}


static func from_dictionary(
		data: Dictionary,
		texture_loader: Callable = Callable(),
) -> TwberModelResource:
	if _variant_to_string(data.get("format", "")) != FORMAT_NAME:
		push_warning("Unsupported model package format.")
		return null

	var source_version := _variant_to_int(
			data.get("format_version", TwberModelResource.FORMAT_VERSION),
			TwberModelResource.FORMAT_VERSION,
	)
	if source_version > TwberModelResource.FORMAT_VERSION:
		push_warning("Model package uses a newer unsupported format version.")
		return null
	if (
			source_version < 5
			and not _variant_to_array(data.get("parameter_bindings", [])).is_empty()
	):
		push_warning(
				"Legacy property bindings cannot be converted to full-state parameter positions."
		)

	var model := TwberModelResource.new()
	model.format_version = TwberModelResource.FORMAT_VERSION

	var root_data := _variant_to_dictionary(data.get("root", {}))
	model.root_position = _array_to_vector2(root_data.get("position", []), Vector2.ZERO)
	model.root_scale = _array_to_vector2(root_data.get("scale", []), Vector2.ONE)
	model.root_rotation = _variant_to_float(root_data.get("rotation", 0.0), 0.0)
	model.root_layer_ids = _array_to_string_array(data.get("root_layer_ids", []))

	var textures_data := _variant_to_dictionary(data.get("textures", {}))
	var texture_cache := {}
	for texture_key: Variant in textures_data.keys():
		var texture_id := String(texture_key)
		var texture_value: Variant = textures_data[texture_key]
		if texture_value is not Dictionary:
			push_warning("Ignoring invalid texture entry: %s" % texture_id)
			continue
		var texture_data: Dictionary = texture_value
		var texture := _texture_from_dictionary(texture_data, texture_loader, texture_cache)
		model.textures[texture_id] = texture
		model.texture_sources[texture_id] = _variant_to_string(texture_data.get("source", ""))

	var layers_data := _variant_to_array(data.get("layers", []))
	var layer_ids := {}
	for layer_data: Variant in layers_data:
		if layer_data is Dictionary:
			var layer := _layer_from_dictionary(layer_data)
			if layer.id.is_empty():
				push_warning("Ignoring layer with an empty id.")
				continue
			if layer_ids.has(layer.id):
				push_warning("Ignoring duplicate layer id: %s" % layer.id)
				continue
			layer_ids[layer.id] = true
			model.layers.append(layer)

	var parameters_data := _variant_to_array(data.get("parameters", []))
	var parameter_ids := {}
	for parameter_data: Variant in parameters_data:
		if parameter_data is Dictionary:
			var parameter := _parameter_from_dictionary(parameter_data)
			if parameter.id.is_empty():
				push_warning("Ignoring parameter with an empty id.")
				continue
			if parameter_ids.has(parameter.id):
				push_warning("Ignoring duplicate parameter id: %s" % parameter.id)
				continue
			parameter_ids[parameter.id] = true
			model.parameters.append(parameter)

	return _normalize_loaded_model(model)


static func _read_model_children(
		parent: Node,
		model: TwberModelResource,
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


static func _layer_from_node(
		node: Node2D,
		model: TwberModelResource,
		state: Dictionary,
) -> TwberLayerResource:
	var layer := TwberLayerResource.new()
	layer.id = _get_or_create_layer_id(node, state)
	layer.name = node.name
	layer.position = node.position
	layer.scale = node.scale
	layer.rotation = node.rotation

	if node is CanvasItem:
		var canvas_item: CanvasItem = node
		layer.visible = canvas_item.visible
		layer.modulate = canvas_item.self_modulate
		layer.clip_children = canvas_item.clip_children
		layer.show_behind_parent = canvas_item.show_behind_parent

	if node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		layer.texture_id = _get_or_store_texture(mesh_sprite.texture, model, state)
		if mesh_sprite.has_mesh_points():
			layer.type = TwberLayerResource.LayerType.MESH_SPRITE
			if mesh_sprite.mesh_data != null:
				layer.mesh = mesh_sprite.mesh_data.duplicate(true)
		else:
			layer.type = TwberLayerResource.LayerType.SPRITE
			layer.centered = true
			layer.offset = mesh_sprite.get_texture_origin()
			if mesh_sprite.texture != null:
				layer.offset += mesh_sprite.texture.get_size() * 0.5
	elif node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = node
		layer.type = TwberLayerResource.LayerType.ANIMATED_SPRITE
		layer.offset = animated_sprite.offset
		layer.centered = animated_sprite.centered
		layer.flip_h = animated_sprite.flip_h
		layer.flip_v = animated_sprite.flip_v
		layer.current_animation = String(animated_sprite.animation)
		_read_animated_sprite(animated_sprite, layer, model, state)
	elif node is Sprite2D:
		var sprite: Sprite2D = node
		layer.type = TwberLayerResource.LayerType.SPRITE
		layer.offset = sprite.offset
		layer.centered = sprite.centered
		layer.flip_h = sprite.flip_h
		layer.flip_v = sprite.flip_v
		layer.texture_id = _get_or_store_texture(sprite.texture, model, state)
	else:
		layer.type = TwberLayerResource.LayerType.EMPTY

	return layer


static func _read_animated_sprite(
		animated_sprite: AnimatedSprite2D,
		layer: TwberLayerResource,
		model: TwberModelResource,
		state: Dictionary,
) -> void:
	if animated_sprite.sprite_frames == null:
		return

	var sprite_frames := animated_sprite.sprite_frames
	for animation_name: String in sprite_frames.get_animation_names():
		var animation := TwberAnimationResource.new()
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
		model: TwberModelResource,
		layers_by_id: Dictionary[String, TwberLayerResource],
		added_layer_ids: Dictionary,
) -> void:
	if not layers_by_id.has(layer_id):
		return
	if added_layer_ids.has(layer_id):
		push_warning("Ignoring duplicate or cyclic layer reference: %s" % layer_id)
		return

	added_layer_ids[layer_id] = true
	var layer: TwberLayerResource = layers_by_id[layer_id]
	var node := _node_from_layer(layer, model)
	parent.add_child(node)

	for child_id: String in layer.children:
		_add_layer_node(node, child_id, model, layers_by_id, added_layer_ids)


static func _node_from_layer(layer: TwberLayerResource, model: TwberModelResource) -> Node2D:
	var node: Node2D
	match layer.type:
		TwberLayerResource.LayerType.SPRITE:
			var sprite := Sprite2D.new()
			sprite.texture = _get_texture(model, layer.texture_id)
			sprite.offset = layer.offset
			sprite.centered = layer.centered
			sprite.flip_h = layer.flip_h
			sprite.flip_v = layer.flip_v
			node = sprite
		TwberLayerResource.LayerType.MESH_SPRITE:
			var mesh_sprite := TwberMeshSprite2D.new()
			mesh_sprite.texture = _get_texture(model, layer.texture_id)
			if layer.mesh != null:
				mesh_sprite.mesh_data = layer.mesh.duplicate(true)
			else:
				mesh_sprite.mesh_data = TwberMeshResource.new()
				if mesh_sprite.texture != null:
					mesh_sprite.reset_texture_origin_from_texture()
			mesh_sprite.sync_mesh()
			node = mesh_sprite
		TwberLayerResource.LayerType.ANIMATED_SPRITE:
			var animated_sprite := AnimatedSprite2D.new()
			animated_sprite.sprite_frames = _sprite_frames_from_layer(layer, model)
			animated_sprite.offset = layer.offset
			animated_sprite.centered = layer.centered
			animated_sprite.flip_h = layer.flip_h
			animated_sprite.flip_v = layer.flip_v
			var requested_animation := StringName(layer.current_animation)
			if animated_sprite.sprite_frames.has_animation(requested_animation):
				animated_sprite.animation = requested_animation
			else:
				animated_sprite.animation = _get_first_animation_name(animated_sprite.sprite_frames)
			if animated_sprite.sprite_frames.has_animation(animated_sprite.animation):
				if animated_sprite.sprite_frames.get_frame_count(animated_sprite.animation) > 0:
					animated_sprite.play(animated_sprite.animation)
			node = animated_sprite
		_:
			node = Node2D.new()

	node.name = layer.name if not layer.name.is_empty() else "Layer"
	node.set_meta(LAYER_ID_META, layer.id)
	node.position = layer.position
	node.scale = layer.scale
	node.rotation = layer.rotation
	node.visible = layer.visible
	node.self_modulate = layer.modulate
	node.clip_children = _variant_to_enum(
			layer.clip_children,
			CanvasItem.CLIP_CHILDREN_AND_DRAW,
			CanvasItem.CLIP_CHILDREN_DISABLED,
	) as CanvasItem.ClipChildrenMode
	node.show_behind_parent = layer.show_behind_parent
	if node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		mesh_sprite.sync_visual_state()
	return node


static func _sprite_frames_from_layer(
		layer: TwberLayerResource,
		model: TwberModelResource,
) -> SpriteFrames:
	var sprite_frames := SpriteFrames.new()
	var saved_animation_names := {}
	for animation: TwberAnimationResource in layer.animations:
		if animation == null:
			continue
		saved_animation_names[StringName(animation.name)] = true

	if (
			not saved_animation_names.is_empty()
			and sprite_frames.has_animation(&"default")
			and not saved_animation_names.has(&"default")
	):
		sprite_frames.remove_animation(&"default")

	for animation: TwberAnimationResource in layer.animations:
		if animation == null:
			continue
		var animation_name := StringName(animation.name)
		if not sprite_frames.has_animation(animation_name):
			sprite_frames.add_animation(animation_name)

		sprite_frames.clear(animation_name)
		sprite_frames.set_animation_speed(animation_name, maxf(animation.speed, 0.0))
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


static func _get_or_store_texture(
		texture: Texture2D,
		model: TwberModelResource,
		state: Dictionary,
) -> String:
	if texture == null:
		return ""

	var texture_ids_by_key: Dictionary = state["texture_ids_by_key"]
	var texture_key := _get_texture_key(texture)
	if texture_ids_by_key.has(texture_key):
		return texture_ids_by_key[texture_key]

	var texture_id := _next_texture_id(state)
	texture_ids_by_key[texture_key] = texture_id
	model.textures[texture_id] = texture
	model.texture_sources[texture_id] = _get_texture_source_path(texture)
	return texture_id


static func _get_texture(model: TwberModelResource, texture_id: String) -> Texture2D:
	if texture_id.is_empty() or not model.textures.has(texture_id):
		return null

	var texture: Variant = model.textures[texture_id]
	if texture is Texture2D:
		return texture

	return null


static func _get_texture_key(texture: Texture2D) -> String:
	var source_path := _get_texture_source_path(texture)
	if not source_path.is_empty():
		return "path:%s:%s:%s" % [
			source_path,
			TwberTextureUtils.get_trim_rect(texture),
			texture.get_size(),
		]

	return "object:%s" % texture.get_instance_id()


static func _get_texture_source_path(texture: Texture2D) -> String:
	if texture.has_meta(TEXTURE_SOURCE_PATH_META):
		return String(texture.get_meta(TEXTURE_SOURCE_PATH_META, ""))

	return texture.resource_path


static func _get_or_create_layer_id(node: Node2D, state: Dictionary) -> String:
	var claimed_layer_ids: Dictionary = state["claimed_layer_ids"]
	if node.has_meta(LAYER_ID_META):
		var stored_id := String(node.get_meta(LAYER_ID_META, ""))
		if not stored_id.is_empty() and not claimed_layer_ids.has(stored_id):
			claimed_layer_ids[stored_id] = true
			return stored_id

	var layer_id := _next_layer_id(state)
	state["used_layer_ids"][layer_id] = true
	claimed_layer_ids[layer_id] = true
	node.set_meta(LAYER_ID_META, layer_id)
	return layer_id


static func _create_layer_id_state(model_root: Node2D) -> Dictionary:
	var reserved_layer_ids := {}
	_reserve_existing_layer_ids(model_root, reserved_layer_ids)
	return {
		"next_layer_index": 1,
		"used_layer_ids": reserved_layer_ids,
		"claimed_layer_ids": {},
	}


static func _reserve_existing_layer_ids(parent: Node, reserved_layer_ids: Dictionary) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue

		var layer_id := String(child.get_meta(LAYER_ID_META, ""))
		if not layer_id.is_empty():
			reserved_layer_ids[layer_id] = true
		_reserve_existing_layer_ids(child, reserved_layer_ids)


static func _assign_layer_ids(parent: Node, state: Dictionary) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue

		_get_or_create_layer_id(child, state)
		_assign_layer_ids(child, state)


static func _next_layer_id(state: Dictionary) -> String:
	var used_layer_ids: Dictionary = state["used_layer_ids"]
	while true:
		var index: int = state["next_layer_index"]
		state["next_layer_index"] = index + 1
		var layer_id := "layer_%03d" % index
		if not used_layer_ids.has(layer_id):
			return layer_id

	return ""


static func _get_model_resources_from_root(
		model_root: Node2D,
		metadata_key: StringName,
		is_valid_resource: Callable,
) -> Array[Resource]:
	var values: Variant = model_root.get_meta(metadata_key, [])
	if values is not Array:
		return []

	return _duplicate_resource_array(values, is_valid_resource)


static func _set_model_parameters_on_root(
		model_root: Node2D,
		model: TwberModelResource,
) -> void:
	model_root.set_meta(MODEL_PARAMETERS_META, _duplicate_resource_array(model.parameters))


static func _duplicate_resource_array(
		values: Array,
		is_valid_resource: Callable = Callable(),
) -> Array[Resource]:
	var output: Array[Resource] = []
	for value: Variant in values:
		if value is not Resource:
			continue
		if is_valid_resource.is_valid() and not is_valid_resource.call(value):
			continue
		output.append(value.duplicate(true))
	return output


static func _next_texture_id(state: Dictionary) -> String:
	var index: int = state["next_texture_index"]
	state["next_texture_index"] = index + 1
	return "texture_%03d" % index


static func _layer_to_dictionary(layer: TwberLayerResource) -> Dictionary:
	var animations: Array[Dictionary] = []
	for animation: TwberAnimationResource in layer.animations:
		if animation == null:
			continue
		animations.append(_animation_to_dictionary(animation))

	var output := {
		"id": layer.id,
		"name": layer.name,
		"type": layer.type,
		"children": layer.children.duplicate(),
		"visible": layer.visible,
		"position": _vector2_to_array(layer.position),
		"scale": _vector2_to_array(layer.scale),
		"rotation": layer.rotation,
		"modulate": _color_to_array(layer.modulate),
		"clip_children": layer.clip_children,
		"show_behind_parent": layer.show_behind_parent,
		"texture_id": layer.texture_id,
		"offset": _vector2_to_array(layer.offset),
		"centered": layer.centered,
		"flip_h": layer.flip_h,
		"flip_v": layer.flip_v,
		"current_animation": layer.current_animation,
		"animations": animations,
	}

	if layer.mesh != null:
		output["mesh"] = _mesh_to_dictionary(layer.mesh)

	return output


static func _layer_from_dictionary(data: Dictionary) -> TwberLayerResource:
	var layer := TwberLayerResource.new()
	layer.id = _variant_to_string(data.get("id", ""))
	layer.name = _variant_to_string(data.get("name", ""), "Layer")
	if layer.name.is_empty():
		layer.name = "Layer"
	layer.type = _variant_to_enum(
			data.get("type", TwberLayerResource.LayerType.EMPTY),
			TwberLayerResource.LayerType.MESH_SPRITE,
			TwberLayerResource.LayerType.EMPTY,
	) as TwberLayerResource.LayerType
	layer.children = _array_to_string_array(data.get("children", []))
	layer.visible = _variant_to_bool(data.get("visible", true), true)
	layer.position = _array_to_vector2(data.get("position", []), Vector2.ZERO)
	layer.scale = _array_to_vector2(data.get("scale", []), Vector2.ONE)
	layer.rotation = _variant_to_float(data.get("rotation", 0.0), 0.0)
	layer.modulate = _array_to_color(data.get("modulate", []), Color.WHITE)
	layer.clip_children = _variant_to_enum(
			data.get("clip_children", CanvasItem.CLIP_CHILDREN_DISABLED),
			CanvasItem.CLIP_CHILDREN_AND_DRAW,
			CanvasItem.CLIP_CHILDREN_DISABLED,
	) as CanvasItem.ClipChildrenMode
	layer.show_behind_parent = _variant_to_bool(data.get("show_behind_parent", false), false)
	layer.texture_id = _variant_to_string(data.get("texture_id", ""))
	layer.offset = _array_to_vector2(data.get("offset", []), Vector2.ZERO)
	layer.centered = _variant_to_bool(data.get("centered", true), true)
	layer.flip_h = _variant_to_bool(data.get("flip_h", false), false)
	layer.flip_v = _variant_to_bool(data.get("flip_v", false), false)
	layer.current_animation = _variant_to_string(data.get("current_animation", "default"), "default")
	if data.has("mesh"):
		layer.mesh = _mesh_from_dictionary(data["mesh"])

	var animations_data := _variant_to_array(data.get("animations", []))
	for animation_data: Variant in animations_data:
		if animation_data is Dictionary:
			layer.animations.append(_animation_from_dictionary(animation_data))

	return layer


static func _animation_to_dictionary(animation: TwberAnimationResource) -> Dictionary:
	return {
		"name": animation.name,
		"speed": animation.speed,
		"loop": animation.loop,
		"frame_texture_ids": animation.frame_texture_ids.duplicate(),
		"frame_durations": animation.frame_durations.duplicate(),
	}


static func _animation_from_dictionary(data: Dictionary) -> TwberAnimationResource:
	var animation := TwberAnimationResource.new()
	animation.name = _variant_to_string(data.get("name", "default"), "default")
	if animation.name.is_empty():
		animation.name = "default"
	animation.speed = maxf(_variant_to_float(data.get("speed", 4.0), 4.0), 0.0)
	animation.loop = _variant_to_bool(data.get("loop", true), true)
	animation.frame_texture_ids = _array_to_string_array(data.get("frame_texture_ids", []))
	animation.frame_durations = _array_to_float_array(data.get("frame_durations", []))
	return animation


static func _parameter_to_dictionary(parameter: TwberParameterResource) -> Dictionary:
	var positions: Array[Dictionary] = []
	for parameter_position: TwberParameterPositionResource in parameter.positions:
		if parameter_position != null and not parameter_position.layer_states.is_empty():
			positions.append(_parameter_position_to_dictionary(parameter_position))

	return {
		"id": parameter.id,
		"name": parameter.name,
		"value_type": parameter.value_type,
		"default_bool": parameter.default_bool,
		"default_int": parameter.default_int,
		"default_float": parameter.default_float,
		"default_vector2": _vector2_to_array(parameter.default_vector2),
		"min_value": parameter.min_value,
		"max_value": parameter.max_value,
		"min_vector2": _vector2_to_array(parameter.min_vector2),
		"max_vector2": _vector2_to_array(parameter.max_vector2),
		"step": TwberParameterResource.normalize_step_for_type(
				parameter.value_type,
				parameter.step,
				true,
		),
		"positions": positions,
	}


static func _normalize_loaded_model(model: TwberModelResource) -> TwberModelResource:
	var known_layer_ids := {}
	var base_states_by_layer_id: Dictionary[String, TwberLayerStateResource] = {}
	for layer: TwberLayerResource in model.layers:
		if layer != null and not layer.id.is_empty():
			known_layer_ids[layer.id] = true
			base_states_by_layer_id[layer.id] = TwberLayerStateResource.from_layer_resource(layer)

	for parameter: TwberParameterResource in model.parameters:
		if parameter == null:
			continue
		parameter.step = TwberParameterResource.normalize_step_for_type(
				parameter.value_type,
				parameter.step,
				true,
		)

		var normalized_positions: Array[TwberParameterPositionResource] = []
		for parameter_position: TwberParameterPositionResource in parameter.positions:
			if parameter_position == null:
				continue
			parameter_position.coordinate = parameter.clamp_coordinate(
					parameter_position.coordinate,
			)
			for state_index: int in range(parameter_position.layer_states.size() - 1, -1, -1):
				var layer_state := parameter_position.layer_states[state_index]
				if layer_state == null or not known_layer_ids.has(layer_state.layer_id):
					parameter_position.layer_states.remove_at(state_index)
					continue
				var base_state := base_states_by_layer_id.get(
						layer_state.layer_id,
				) as TwberLayerStateResource
				layer_state.sanitize_mesh_vertices(base_state)
				layer_state.sanitize_animation_state(base_state)
			if parameter_position.layer_states.is_empty():
				continue

			var existing_position: TwberParameterPositionResource
			for candidate: TwberParameterPositionResource in normalized_positions:
				if parameter.coordinates_equal(candidate.coordinate, parameter_position.coordinate):
					existing_position = candidate
					break
			if existing_position == null:
				normalized_positions.append(parameter_position)
			else:
				for layer_state: TwberLayerStateResource in parameter_position.layer_states:
					existing_position.upsert_state(layer_state)
		parameter.positions = normalized_positions

	model.format_version = TwberModelResource.FORMAT_VERSION
	return model


static func _parameter_from_dictionary(data: Dictionary) -> TwberParameterResource:
	var parameter := TwberParameterResource.new()
	parameter.id = _variant_to_string(data.get("id", ""))
	parameter.name = _variant_to_string(data.get("name", ""))
	parameter.value_type = _variant_to_enum(
			data.get(
					"value_type",
					TwberParameterResource.ValueType.FLOAT,
			),
			TwberParameterResource.ValueType.VECTOR2,
			TwberParameterResource.ValueType.FLOAT,
	) as TwberParameterResource.ValueType
	parameter.default_bool = _variant_to_bool(data.get("default_bool", false))
	parameter.default_int = _variant_to_int(data.get("default_int", 0))
	parameter.default_float = _variant_to_float(data.get("default_float", 0.0))
	parameter.default_vector2 = _array_to_vector2(data.get("default_vector2", []), Vector2.ZERO)
	parameter.min_value = _variant_to_float(data.get("min_value", 0.0))
	parameter.max_value = _variant_to_float(data.get("max_value", 1.0), 1.0)
	parameter.min_vector2 = _array_to_vector2(
			data.get("min_vector2", []),
			Vector2(-1.0, -1.0),
	)
	parameter.max_vector2 = _array_to_vector2(
			data.get("max_vector2", []),
			Vector2(1.0, 1.0),
	)
	var default_step := TwberParameterResource.normalize_step_for_type(
			parameter.value_type,
			TwberParameterResource.CONTINUOUS_STEP,
	)
	parameter.step = TwberParameterResource.normalize_step_for_type(
			parameter.value_type,
			_variant_to_float(data.get("step", default_step), default_step),
			true,
	)

	var positions_data := _variant_to_array(data.get("positions", []))
	for position_data: Variant in positions_data:
		if position_data is not Dictionary:
			continue
		var parameter_position := _parameter_position_from_dictionary(position_data)
		if not parameter_position.layer_states.is_empty():
			parameter.positions.append(parameter_position)
	return parameter


static func _parameter_position_to_dictionary(
		parameter_position: TwberParameterPositionResource,
) -> Dictionary:
	var layer_states: Array[Dictionary] = []
	for layer_state: TwberLayerStateResource in parameter_position.layer_states:
		if layer_state != null and not layer_state.layer_id.is_empty():
			layer_states.append(_layer_state_to_dictionary(layer_state))

	return {
		"coordinate": _vector2_to_array(parameter_position.coordinate),
		"layer_states": layer_states,
	}


static func _parameter_position_from_dictionary(
		data: Dictionary,
) -> TwberParameterPositionResource:
	var parameter_position := TwberParameterPositionResource.new()
	parameter_position.coordinate = _array_to_vector2(data.get("coordinate", []), Vector2.ZERO)

	var states_data := _variant_to_array(data.get("layer_states", []))
	for state_data: Variant in states_data:
		if state_data is not Dictionary:
			continue
		var layer_state := _layer_state_from_dictionary(state_data)
		if not layer_state.layer_id.is_empty():
			parameter_position.upsert_state(layer_state)

	return parameter_position


static func _layer_state_to_dictionary(layer_state: TwberLayerStateResource) -> Dictionary:
	var output := {
		"layer_id": layer_state.layer_id,
		"channels": layer_state.channels,
	}
	if layer_state.has_channel(TwberLayerStateResource.Channel.POSITION):
		output["position"] = _vector2_to_array(layer_state.position)
	if layer_state.has_channel(TwberLayerStateResource.Channel.ROTATION):
		output["rotation"] = layer_state.rotation
	if layer_state.has_channel(TwberLayerStateResource.Channel.SCALE):
		output["scale"] = _vector2_to_array(layer_state.scale)
	if layer_state.has_channel(TwberLayerStateResource.Channel.VISIBILITY):
		output["visible"] = layer_state.visible
	if layer_state.has_channel(TwberLayerStateResource.Channel.COLOR):
		output["self_modulate"] = _color_to_array(layer_state.self_modulate)
	if layer_state.has_channel(TwberLayerStateResource.Channel.MESH):
		output["mesh_vertices"] = _packed_vector2_array_to_array(layer_state.mesh_vertices)
	if layer_state.has_channel(TwberLayerStateResource.Channel.ANIMATION):
		output["animation_name"] = layer_state.animation_name
	if layer_state.has_channel(TwberLayerStateResource.Channel.ANIMATION_FRAME_RATE):
		output["animation_frame_rate"] = layer_state.animation_frame_rate
	return output


static func _layer_state_from_dictionary(data: Dictionary) -> TwberLayerStateResource:
	var layer_state := TwberLayerStateResource.new()
	layer_state.channels = clampi(
			_variant_to_int(
					data.get("channels", TwberLayerStateResource.ALL_CHANNELS),
					TwberLayerStateResource.ALL_CHANNELS,
			),
			0,
			TwberLayerStateResource.ALL_CHANNELS,
	)
	layer_state.layer_id = _variant_to_string(data.get("layer_id", ""))
	layer_state.position = _array_to_vector2(data.get("position", []), Vector2.ZERO)
	layer_state.rotation = _variant_to_float(data.get("rotation", 0.0), 0.0)
	layer_state.scale = _array_to_vector2(data.get("scale", []), Vector2.ONE)
	layer_state.visible = _variant_to_bool(data.get("visible", true), true)
	layer_state.self_modulate = _array_to_color(data.get("self_modulate", []), Color.WHITE)
	layer_state.mesh_vertices = _array_to_packed_vector2_array(data.get("mesh_vertices", []))
	# Versions before 6 did not persist animated-sprite state. Keep sentinel
	# values until model normalization can resolve them against the layer base.
	layer_state.animation_name = _variant_to_string(data.get("animation_name", ""))
	layer_state.animation_frame_rate = _variant_to_float(
			data.get("animation_frame_rate", -1.0),
			-1.0,
	)
	return layer_state


static func _mesh_to_dictionary(mesh: TwberMeshResource) -> Dictionary:
	return {
		"texture_origin": _vector2_to_array(mesh.texture_origin),
		"rest_vertices": _packed_vector2_array_to_array(mesh.rest_vertices),
		"vertices": _packed_vector2_array_to_array(mesh.vertices),
		"uvs": _packed_vector2_array_to_array(mesh.uvs),
		"triangles": _packed_int32_array_to_array(mesh.triangles),
		"cut_edges": _packed_int32_array_to_array(mesh.cut_edges),
		"joined_edges": _packed_int32_array_to_array(mesh.joined_edges),
	}


static func _mesh_from_dictionary(data: Variant) -> TwberMeshResource:
	if data is not Dictionary:
		return null

	var mesh := TwberMeshResource.new()
	mesh.texture_origin = _array_to_vector2(data.get("texture_origin", []), Vector2.ZERO)
	mesh.rest_vertices = _array_to_packed_vector2_array(data.get("rest_vertices", []))
	mesh.vertices = _array_to_packed_vector2_array(data.get("vertices", []))
	mesh.uvs = _array_to_packed_vector2_array(data.get("uvs", []))
	mesh.triangles = _array_to_packed_int32_array(data.get("triangles", []))
	mesh.cut_edges = _array_to_packed_int32_array(data.get("cut_edges", []))
	mesh.joined_edges = _array_to_packed_int32_array(data.get("joined_edges", []))

	if mesh.rest_vertices.size() != mesh.vertices.size():
		mesh.rest_vertices = mesh.vertices.duplicate()

	if mesh.uvs.size() != mesh.vertices.size():
		mesh.uvs = PackedVector2Array()
		for vertex: Vector2 in mesh.vertices:
			mesh.uvs.append(vertex - mesh.texture_origin)

	mesh.sanitize_topology()
	return mesh


static func _texture_to_base64_png(texture: Texture2D) -> String:
	if texture == null:
		return ""

	var image := TwberTextureUtils.get_readable_image(texture)
	if image == null:
		return ""

	return Marshalls.raw_to_base64(image.save_png_to_buffer())


static func _texture_to_png_buffer(texture: Texture2D) -> PackedByteArray:
	if texture == null:
		return PackedByteArray()
	var image := TwberTextureUtils.get_readable_image(texture)
	if image == null:
		return PackedByteArray()
	return image.save_png_to_buffer()


static func _build_texture_package(
		model: TwberModelResource,
		texture_entries: Dictionary,
) -> Dictionary:
	var atlas_items: Array[Dictionary] = []
	var standalone_items: Array[Dictionary] = []
	var failed_texture_ids: Array[String] = []
	var unique_items_by_content := {}
	for texture_key: Variant in texture_entries:
		var texture_id := String(texture_key)
		var texture: Texture2D = model.textures.get(texture_id) as Texture2D
		var image := TwberTextureUtils.get_authoring_image(texture)
		if image == null or image.get_width() <= 0 or image.get_height() <= 0:
			failed_texture_ids.append(texture_id)
			continue
		var rgba_image := image.duplicate()
		if rgba_image.get_format() != Image.FORMAT_RGBA8:
			rgba_image.convert(Image.FORMAT_RGBA8)
		var content_key := "%dx%d:%s" % [
			rgba_image.get_width(),
			rgba_image.get_height(),
			_sha256_hex(rgba_image.get_data()),
		]
		if unique_items_by_content.has(content_key):
			unique_items_by_content[content_key]["ids"].append(texture_id)
			continue
		var item := {
			"id": texture_id,
			"ids": [texture_id],
			"image": rgba_image,
			"size": Vector2i(rgba_image.get_width(), rgba_image.get_height()),
		}
		unique_items_by_content[content_key] = item

	for item: Dictionary in unique_items_by_content.values():
		var rgba_image: Image = item["image"]
		if (
				rgba_image.get_width() + ATLAS_PADDING * 2 > ATLAS_MAX_SIZE
				or rgba_image.get_height() + ATLAS_PADDING * 2 > ATLAS_MAX_SIZE
		):
			standalone_items.append(item)
		else:
			atlas_items.append(item)

	atlas_items.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_size: Vector2i = first["size"]
		var second_size: Vector2i = second["size"]
		if first_size.y == second_size.y:
			return String(first["id"]) < String(second["id"])
		return first_size.y > second_size.y
	)

	var pages: Array[Dictionary] = []
	for item: Dictionary in atlas_items:
		var placed := false
		for page: Dictionary in pages:
			var placed_region := _try_place_atlas_item(page, item["size"])
			if placed_region.size == Vector2i.ZERO:
				continue
			item["region"] = placed_region
			page["items"].append(item)
			placed = true
			break
		if placed:
			continue

		var page := {
			"cursor_x": ATLAS_PADDING,
			"cursor_y": ATLAS_PADDING,
			"row_height": 0,
			"used_size": Vector2i.ONE,
			"items": [],
		}
		var new_page_region := _try_place_atlas_item(page, item["size"])
		item["region"] = new_page_region
		page["items"].append(item)
		pages.append(page)

	var shared_pages: Array[Dictionary] = []
	for page: Dictionary in pages:
		if page["items"].size() < 2:
			standalone_items.append(page["items"][0])
		else:
			shared_pages.append(page)
	pages = shared_pages

	var payloads := {}
	var file_manifest := {}
	for page_index: int in pages.size():
		var page: Dictionary = pages[page_index]
		var used_size: Vector2i = page["used_size"]
		used_size.x = maxi(4, ceili(float(used_size.x) / 4.0) * 4)
		used_size.y = maxi(4, ceili(float(used_size.y) / 4.0) * 4)
		var atlas_image := Image.create(used_size.x, used_size.y, false, Image.FORMAT_RGBA8)
		atlas_image.fill(Color(0.0, 0.0, 0.0, 0.0))
		for item: Dictionary in page["items"]:
			_blit_atlas_item(atlas_image, item["image"], item["region"])

		var atlas_path := "textures/atlas_%03d.png" % page_index
		var png_data := atlas_image.save_png_to_buffer()
		var atlas_hash := _sha256_hex(png_data)
		payloads[atlas_path] = png_data
		file_manifest[atlas_path] = {
			"byte_size": png_data.size(),
			"sha256": atlas_hash,
			"size": [used_size.x, used_size.y],
			"kind": "atlas",
		}
		var gpu_variant := _add_gpu_texture_variant(
				atlas_image,
				"textures/atlas_%03d.s3tc" % page_index,
				payloads,
				file_manifest,
		)
		for item: Dictionary in page["items"]:
			var region: Rect2i = item["region"]
			for texture_id: String in item["ids"]:
				var entry: Dictionary = texture_entries[texture_id]
				entry["atlas_file"] = atlas_path
				entry["atlas_sha256"] = atlas_hash
				entry["region"] = [
					region.position.x,
					region.position.y,
					region.size.x,
					region.size.y,
				]
				entry.merge(gpu_variant, true)

	for item: Dictionary in standalone_items:
		var texture_path := "textures/%s.png" % item["id"]
		var png_data: PackedByteArray = item["image"].save_png_to_buffer()
		var texture_hash := _sha256_hex(png_data)
		payloads[texture_path] = png_data
		file_manifest[texture_path] = {
			"byte_size": png_data.size(),
			"sha256": texture_hash,
			"size": [item["size"].x, item["size"].y],
			"kind": "standalone",
		}
		var gpu_variant := _add_gpu_texture_variant(
				item["image"],
				"textures/%s.s3tc" % item["id"],
				payloads,
				file_manifest,
		)
		for texture_id: String in item["ids"]:
			var entry: Dictionary = texture_entries[texture_id]
			entry["file"] = texture_path
			entry["byte_size"] = png_data.size()
			entry["sha256"] = texture_hash
			entry.merge(gpu_variant, true)

	return {
		"payloads": payloads,
		"manifest": file_manifest,
		"atlas_pages": pages.size(),
		"standalone_textures": standalone_items.size(),
		"failed_texture_ids": failed_texture_ids,
	}


static func _try_place_atlas_item(page: Dictionary, item_size: Vector2i) -> Rect2i:
	var cursor_x := int(page["cursor_x"])
	var cursor_y := int(page["cursor_y"])
	var row_height := int(page["row_height"])
	if cursor_x + item_size.x + ATLAS_PADDING > ATLAS_MAX_SIZE:
		cursor_x = ATLAS_PADDING
		cursor_y += row_height + ATLAS_PADDING
		row_height = 0
	if cursor_y + item_size.y + ATLAS_PADDING > ATLAS_MAX_SIZE:
		return Rect2i()

	var region := Rect2i(Vector2i(cursor_x, cursor_y), item_size)
	page["cursor_x"] = cursor_x + item_size.x + ATLAS_PADDING
	page["cursor_y"] = cursor_y
	page["row_height"] = maxi(row_height, item_size.y)
	var used_size: Vector2i = page["used_size"]
	page["used_size"] = used_size.max(region.end + Vector2i.ONE * ATLAS_PADDING)
	return region


static func _add_gpu_texture_variant(
		source: Image,
		file_path: String,
		payloads: Dictionary,
		file_manifest: Dictionary,
) -> Dictionary:
	var gpu_image: Image = source.duplicate()
	var error: Error = gpu_image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC)
	if error != OK:
		return {}
	var data: PackedByteArray = gpu_image.get_data()
	var gpu_hash := _sha256_hex(data)
	payloads[file_path] = data
	file_manifest[file_path] = {
		"byte_size": data.size(),
		"sha256": gpu_hash,
		"size": [gpu_image.get_width(), gpu_image.get_height()],
		"format": gpu_image.get_format(),
		"kind": "gpu_s3tc",
	}
	return {
		"gpu_file": file_path,
		"gpu_sha256": gpu_hash,
		"gpu_width": gpu_image.get_width(),
		"gpu_height": gpu_image.get_height(),
		"gpu_format": gpu_image.get_format(),
	}


static func _blit_atlas_item(atlas: Image, source: Image, region: Rect2i) -> void:
	atlas.blit_rect(source, Rect2i(Vector2i.ZERO, region.size), region.position)
	for distance: int in range(1, ATLAS_PADDING + 1):
		for x: int in region.size.x:
			atlas.set_pixelv(
					Vector2i(region.position.x + x, region.position.y - distance),
					source.get_pixel(x, 0),
			)
			atlas.set_pixelv(
					Vector2i(region.position.x + x, region.end.y - 1 + distance),
					source.get_pixel(x, region.size.y - 1),
			)
		for y: int in region.size.y:
			atlas.set_pixelv(
					Vector2i(region.position.x - distance, region.position.y + y),
					source.get_pixel(0, y),
			)
			atlas.set_pixelv(
					Vector2i(region.end.x - 1 + distance, region.position.y + y),
					source.get_pixel(region.size.x - 1, y),
			)
	for offset_x: int in range(1, ATLAS_PADDING + 1):
		for offset_y: int in range(1, ATLAS_PADDING + 1):
			atlas.set_pixel(
					region.position.x - offset_x,
					region.position.y - offset_y,
					source.get_pixel(0, 0),
			)
			atlas.set_pixel(
					region.end.x - 1 + offset_x,
					region.position.y - offset_y,
					source.get_pixel(region.size.x - 1, 0),
			)
			atlas.set_pixel(
					region.position.x - offset_x,
					region.end.y - 1 + offset_y,
					source.get_pixel(0, region.size.y - 1),
			)
			atlas.set_pixel(
					region.end.x - 1 + offset_x,
					region.end.y - 1 + offset_y,
					source.get_pixel(region.size.x - 1, region.size.y - 1),
			)


static func _texture_from_dictionary(
		data: Dictionary,
		texture_loader: Callable = Callable(),
		texture_cache: Dictionary = {},
) -> Texture2D:
	var source_path := _variant_to_string(data.get("source", ""))
	var atlas_file := _variant_to_string(data.get("atlas_file", ""))
	if not atlas_file.is_empty() and texture_loader.is_valid():
		var atlas_texture := _load_package_texture(
				atlas_file,
				_variant_to_string(data.get("atlas_sha256", "")),
				texture_loader,
				texture_cache,
				data,
		)
		var region := _array_to_rect2i(data.get("region", []), Rect2i())
		if atlas_texture != null and region.size.x > 0 and region.size.y > 0:
			var region_texture := AtlasTexture.new()
			region_texture.atlas = atlas_texture
			region_texture.region = Rect2(region)
			if not source_path.is_empty():
				region_texture.resource_name = source_path.get_file().get_basename()
				region_texture.set_meta(TEXTURE_SOURCE_PATH_META, source_path)
			_apply_texture_metadata_from_dictionary(region_texture, data)
			_apply_package_authoring_metadata(
					region_texture,
					data,
					atlas_file,
					_variant_to_string(data.get("atlas_sha256", "")),
					region,
			)
			return region_texture
	var package_file := _variant_to_string(data.get("file", ""))
	if not package_file.is_empty() and texture_loader.is_valid():
		var package_texture := _load_package_texture(
				package_file,
				_variant_to_string(data.get("sha256", "")),
				texture_loader,
				texture_cache,
				data,
		)
		if package_texture != null:
			var standalone_region := AtlasTexture.new()
			standalone_region.atlas = package_texture
			standalone_region.region = Rect2(Vector2.ZERO, package_texture.get_size())
			if not source_path.is_empty():
				standalone_region.resource_name = source_path.get_file().get_basename()
				standalone_region.set_meta(TEXTURE_SOURCE_PATH_META, source_path)
			_apply_texture_metadata_from_dictionary(standalone_region, data)
			_apply_package_authoring_metadata(
					standalone_region,
					data,
					package_file,
					_variant_to_string(data.get("sha256", "")),
					Rect2i(Vector2i.ZERO, Vector2i(package_texture.get_size())),
			)
			return standalone_region
	var encoded_webp := _variant_to_string(data.get("webp", ""))
	if not encoded_webp.is_empty():
		var image := Image.new()
		var error := image.load_webp_from_buffer(Marshalls.base64_to_raw(encoded_webp))
		if error == OK:
			var webp_texture := _image_texture_from_embedded_image(image, source_path)
			_apply_texture_metadata_from_dictionary(webp_texture, data)
			return webp_texture

	var encoded_png := _variant_to_string(data.get("png", ""))
	if not encoded_png.is_empty():
		var image := Image.new()
		var error := image.load_png_from_buffer(Marshalls.base64_to_raw(encoded_png))
		if error == OK:
			var png_texture := _image_texture_from_embedded_image(image, source_path)
			_apply_texture_metadata_from_dictionary(png_texture, data)
			return png_texture

	if not source_path.is_empty():
		var source_texture := _load_texture_from_source_path(source_path)
		_apply_texture_metadata_from_dictionary(source_texture, data)
		return source_texture

	return null


static func _apply_package_authoring_metadata(
		texture: Texture2D,
		data: Dictionary,
		texture_file: String,
		texture_hash: String,
		region: Rect2i,
) -> void:
	var package_path := _variant_to_string(data.get("_package_path", ""))
	if texture == null or package_path.is_empty() or texture_file.is_empty():
		return
	texture.set_meta(TwberTextureUtils.PACKAGE_PATH_META, package_path)
	texture.set_meta(TwberTextureUtils.PACKAGE_TEXTURE_FILE_META, texture_file)
	texture.set_meta(TwberTextureUtils.PACKAGE_TEXTURE_HASH_META, texture_hash)
	texture.set_meta(TwberTextureUtils.PACKAGE_TEXTURE_REGION_META, region)


static func _load_package_texture(
		package_file: String,
		expected_hash: String,
		texture_loader: Callable,
		texture_cache: Dictionary,
		variant_data: Dictionary,
) -> Texture2D:
	if OS.has_feature("pc"):
		var gpu_file := _variant_to_string(variant_data.get("gpu_file", ""))
		if not gpu_file.is_empty():
			if texture_cache.has(gpu_file):
				return texture_cache[gpu_file]
			var gpu_hash := _variant_to_string(variant_data.get("gpu_sha256", ""))
			var gpu_cache_key := "gpu:%s" % gpu_hash if not gpu_hash.is_empty() else ""
			var shared_gpu_texture := TwberTextureCache.get_texture(gpu_cache_key)
			if shared_gpu_texture != null:
				texture_cache[gpu_file] = shared_gpu_texture
				return shared_gpu_texture
			var gpu_bytes: PackedByteArray = texture_loader.call(
					gpu_file,
					gpu_hash,
			)
			var gpu_width := _variant_to_int(variant_data.get("gpu_width", 0))
			var gpu_height := _variant_to_int(variant_data.get("gpu_height", 0))
			var gpu_format := _variant_to_int(variant_data.get("gpu_format", -1), -1)
			if (
					not gpu_bytes.is_empty()
					and gpu_width > 0
					and gpu_height > 0
					and gpu_format >= 0
					and gpu_format < Image.FORMAT_MAX
			):
				var gpu_image := Image.create_from_data(
						gpu_width,
						gpu_height,
						false,
						gpu_format as Image.Format,
						gpu_bytes,
				)
				if gpu_image != null and not gpu_image.is_empty():
					var gpu_texture := ImageTexture.create_from_image(gpu_image)
					texture_cache[gpu_file] = gpu_texture
					TwberTextureCache.store_texture(gpu_cache_key, gpu_texture)
					return gpu_texture

	if texture_cache.has(package_file):
		return texture_cache[package_file]
	var png_cache_key := "png:%s" % expected_hash if not expected_hash.is_empty() else ""
	var shared_texture := TwberTextureCache.get_texture(png_cache_key)
	if shared_texture != null:
		texture_cache[package_file] = shared_texture
		return shared_texture
	var package_bytes: PackedByteArray = texture_loader.call(package_file, expected_hash)
	if package_bytes.is_empty():
		return null
	var package_image := Image.new()
	if package_image.load_png_from_buffer(package_bytes) != OK:
		return null
	var package_texture := ImageTexture.create_from_image(package_image)
	texture_cache[package_file] = package_texture
	TwberTextureCache.store_texture(png_cache_key, package_texture)
	return package_texture


static func _write_package_file(
		packer: ZIPPacker,
		file_path: String,
		data: PackedByteArray,
) -> Error:
	var error := packer.start_file(file_path)
	if error != OK:
		return error
	packer.write_file(data)
	return packer.close_file()


static func _replace_file_atomically(temporary_path: String, target_path: String) -> Error:
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var target_absolute := ProjectSettings.globalize_path(target_path)
	var backup_absolute := "%s.backup" % target_absolute
	_remove_file_if_exists(backup_absolute)

	var had_target := FileAccess.file_exists(target_path)
	if had_target:
		var backup_error := DirAccess.rename_absolute(target_absolute, backup_absolute)
		if backup_error != OK:
			_remove_file_if_exists(temporary_path)
			return backup_error

	var replace_error := DirAccess.rename_absolute(temporary_absolute, target_absolute)
	if replace_error != OK:
		if had_target:
			DirAccess.rename_absolute(backup_absolute, target_absolute)
		_remove_file_if_exists(temporary_path)
		return replace_error

	_remove_file_if_exists(backup_absolute)
	return OK


static func _remove_file_if_exists(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


static func _sha256_hex(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(data)
	return context.finish().hex_encode()


static func get_model_performance_summary(model: TwberModelResource) -> Dictionary:
	if model == null:
		return {}

	var mesh_count := 0
	var vertex_count := 0
	var triangle_count := 0
	var drawable_layer_count := 0
	var clipped_layer_count := 0
	var animation_frame_count := 0
	for layer: TwberLayerResource in model.layers:
		if layer == null:
			continue
		if layer.type != TwberLayerResource.LayerType.EMPTY:
			drawable_layer_count += 1
		if layer.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			clipped_layer_count += 1
		if layer.mesh != null:
			mesh_count += 1
			vertex_count += layer.mesh.vertices.size()
			triangle_count += floori(float(layer.mesh.triangles.size()) / 3.0)
		for animation: TwberAnimationResource in layer.animations:
			if animation != null:
				animation_frame_count += animation.frame_texture_ids.size()

	var texture_pixels := 0
	var original_texture_pixels := 0
	var estimated_texture_vram_bytes := 0
	var counted_physical_textures := {}
	for texture_value: Variant in model.textures.values():
		if texture_value is not Texture2D:
			continue
		var texture: Texture2D = texture_value
		texture_pixels += texture.get_width() * texture.get_height()
		var original_size := TwberTextureUtils.get_original_size(texture)
		original_texture_pixels += original_size.x * original_size.y
		var physical_texture := texture
		if texture is AtlasTexture and (texture as AtlasTexture).atlas != null:
			physical_texture = (texture as AtlasTexture).atlas
		var physical_texture_id := physical_texture.get_instance_id()
		if not counted_physical_textures.has(physical_texture_id):
			counted_physical_textures[physical_texture_id] = true
			var bytes_per_pixel := 1 if TwberTextureUtils.is_gpu_compressed(physical_texture) else 4
			estimated_texture_vram_bytes += (
					physical_texture.get_width()
					* physical_texture.get_height()
					* bytes_per_pixel
			)

	var parameter_position_count := 0
	var parameter_state_count := 0
	var parameter_mesh_vertex_count := 0
	for parameter: TwberParameterResource in model.parameters:
		if parameter == null:
			continue
		for position: TwberParameterPositionResource in parameter.positions:
			if position == null:
				continue
			parameter_position_count += 1
			for state: TwberLayerStateResource in position.layer_states:
				if state == null:
					continue
				parameter_state_count += 1
				parameter_mesh_vertex_count += state.mesh_vertices.size()

	return {
		"layers": model.layers.size(),
		"drawable_layers": drawable_layer_count,
		"estimated_draw_calls": _estimate_model_render_batches(
				model,
				drawable_layer_count,
				clipped_layer_count,
		),
		"clipped_layers": clipped_layer_count,
		"meshes": mesh_count,
		"vertices": vertex_count,
		"triangles": triangle_count,
		"textures": model.textures.size(),
		"texture_pixels": texture_pixels,
		"original_texture_pixels": original_texture_pixels,
		"trimmed_pixels_saved": maxi(original_texture_pixels - texture_pixels, 0),
		"estimated_texture_vram_bytes": estimated_texture_vram_bytes,
		"animation_frames": animation_frame_count,
		"parameters": model.parameters.size(),
		"parameter_positions": parameter_position_count,
		"parameter_states": parameter_state_count,
		"parameter_mesh_vertices": parameter_mesh_vertex_count,
	}


static func _estimate_model_render_batches(
		model: TwberModelResource,
		drawable_layer_count: int,
		clipped_layer_count: int,
		packaged_texture_entries: Dictionary = {},
) -> int:
	if clipped_layer_count > 0:
		return drawable_layer_count + clipped_layer_count
	var layers_by_id := {}
	for layer: TwberLayerResource in model.layers:
		if layer != null and not layer.id.is_empty():
			layers_by_id[layer.id] = layer
	var state := {
		"batches": 0,
		"texture_key": "",
		"vertices": 0,
	}
	for layer_id: String in model.root_layer_ids:
		_estimate_layer_batches(
				layer_id,
				model,
				layers_by_id,
				state,
				packaged_texture_entries,
		)
	return int(state["batches"])


static func _estimate_layer_batches(
		layer_id: String,
		model: TwberModelResource,
		layers_by_id: Dictionary,
		state: Dictionary,
		packaged_texture_entries: Dictionary,
) -> void:
	if not layers_by_id.has(layer_id):
		return
	var layer: TwberLayerResource = layers_by_id[layer_id]
	if layer.visible:
		var texture_id := layer.texture_id
		if layer.type == TwberLayerResource.LayerType.ANIMATED_SPRITE:
			texture_id = _get_current_animation_texture_id(layer)
		var texture: Texture2D = model.textures.get(texture_id) as Texture2D
		if texture != null and layer.type != TwberLayerResource.LayerType.EMPTY:
			var texture_key := _get_packaged_texture_key(
					texture_id,
					texture,
					packaged_texture_entries,
			)
			var vertex_count := 4
			if layer.mesh != null and layer.mesh.vertices.size() >= 3:
				vertex_count = layer.mesh.vertices.size()
			if (
					String(state["texture_key"]) != texture_key
					or int(state["vertices"]) + vertex_count > 65535
			):
				state["batches"] = int(state["batches"]) + 1
				state["texture_key"] = texture_key
				state["vertices"] = 0
			state["vertices"] = int(state["vertices"]) + vertex_count
		for child_id: String in layer.children:
			_estimate_layer_batches(
					child_id,
					model,
					layers_by_id,
					state,
					packaged_texture_entries,
			)


static func _get_current_animation_texture_id(layer: TwberLayerResource) -> String:
	for animation: TwberAnimationResource in layer.animations:
		if (
				animation != null
				and animation.name == layer.current_animation
				and not animation.frame_texture_ids.is_empty()
		):
			return animation.frame_texture_ids[0]
	for animation: TwberAnimationResource in layer.animations:
		if animation != null and not animation.frame_texture_ids.is_empty():
			return animation.frame_texture_ids[0]
	return ""


static func _get_physical_texture_key(texture: Texture2D) -> String:
	if texture is AtlasTexture and (texture as AtlasTexture).atlas != null:
		return "atlas:%d" % (texture as AtlasTexture).atlas.get_instance_id()
	return "texture:%d" % texture.get_instance_id()


static func _get_packaged_texture_key(
		texture_id: String,
		texture: Texture2D,
		packaged_texture_entries: Dictionary,
) -> String:
	if packaged_texture_entries.has(texture_id):
		var entry: Dictionary = packaged_texture_entries[texture_id]
		var atlas_file := _variant_to_string(entry.get("atlas_file", ""))
		if not atlas_file.is_empty():
			return "package:%s" % atlas_file
		var texture_file := _variant_to_string(entry.get("file", ""))
		if not texture_file.is_empty():
			return "package:%s" % texture_file
	return _get_physical_texture_key(texture)


static func _image_texture_from_embedded_image(image: Image, source_path: String) -> ImageTexture:
	var texture := ImageTexture.create_from_image(image)
	if not source_path.is_empty():
		texture.resource_name = source_path.get_file().get_basename()
		texture.set_meta(TEXTURE_SOURCE_PATH_META, source_path)
	return texture


static func _load_texture_from_source_path(source_path: String) -> Texture2D:
	if source_path.begins_with("res://") or source_path.begins_with("uid://"):
		var resource := load(source_path)
		if resource is Texture2D:
			return resource
		return null

	var image := Image.new()
	var error := image.load(source_path)
	if error != OK:
		return null

	var image_texture := ImageTexture.create_from_image(image)
	image_texture.resource_name = source_path.get_file().get_basename()
	image_texture.set_meta(TEXTURE_SOURCE_PATH_META, source_path)
	return image_texture


static func _texture_metadata_to_dictionary(texture: Texture2D) -> Dictionary:
	if texture == null:
		return {}
	var original_size := TwberTextureUtils.get_original_size(texture)
	var trim_rect := TwberTextureUtils.get_trim_rect(texture)
	var visible_rect := TwberTextureUtils.get_visible_rect(texture)
	return {
		"original_size": [original_size.x, original_size.y],
		"trim_rect": [trim_rect.position.x, trim_rect.position.y, trim_rect.size.x, trim_rect.size.y],
		"visible_rect": [
			visible_rect.position.x,
			visible_rect.position.y,
			visible_rect.size.x,
			visible_rect.size.y,
		],
		"alpha_threshold": float(texture.get_meta(TwberTextureUtils.ALPHA_THRESHOLD_META, 0.0)),
	}


static func _apply_texture_metadata_from_dictionary(texture: Texture2D, data: Dictionary) -> void:
	if texture == null:
		return
	var fallback_size := Vector2i(texture.get_size())
	var original_size := _array_to_vector2i(data.get("original_size", []), fallback_size)
	var trim_rect := _array_to_rect2i(
			data.get("trim_rect", []),
			Rect2i(Vector2i.ZERO, fallback_size),
	)
	var visible_rect := _array_to_rect2i(data.get("visible_rect", []), Rect2i())
	TwberTextureUtils.apply_metadata(texture, {
		"original_size": original_size,
		"trim_rect": trim_rect,
		"visible_rect": visible_rect,
		"alpha_threshold": _variant_to_float(data.get("alpha_threshold", 0.0)),
	})


static func _array_to_vector2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is not Array or value.size() < 2:
		return fallback
	if not _is_number(value[0]) or not _is_number(value[1]):
		return fallback
	return Vector2i(_variant_to_int(value[0]), _variant_to_int(value[1]))


static func _array_to_rect2i(value: Variant, fallback: Rect2i) -> Rect2i:
	if value is not Array or value.size() < 4:
		return fallback
	for component: Variant in value.slice(0, 4):
		if not _is_number(component):
			return fallback
	return Rect2i(
			_variant_to_int(value[0]),
			_variant_to_int(value[1]),
			_variant_to_int(value[2]),
			_variant_to_int(value[3]),
	)


static func _vector2_to_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]


static func _array_to_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is not Array or value.size() < 2:
		return fallback
	if not _is_number(value[0]) or not _is_number(value[1]):
		return fallback

	return Vector2(_variant_to_float(value[0]), _variant_to_float(value[1]))


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
		output.append(_variant_to_int(value, -1))
	return output


static func _color_to_array(value: Color) -> Array[float]:
	return [value.r, value.g, value.b, value.a]


static func _array_to_color(value: Variant, fallback: Color) -> Color:
	if value is not Array or value.size() < 4:
		return fallback
	for component: Variant in value.slice(0, 4):
		if not _is_number(component):
			return fallback

	return Color(
			_variant_to_float(value[0]),
			_variant_to_float(value[1]),
			_variant_to_float(value[2]),
			_variant_to_float(value[3]),
	)


static func _array_to_string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	if values is not Array:
		return output

	for value: Variant in values:
		if value is String or value is StringName:
			output.append(String(value))
	return output


static func _array_to_float_array(values: Variant) -> Array[float]:
	var output: Array[float] = []
	if values is not Array:
		return output

	for value: Variant in values:
		output.append(_variant_to_float(value, 1.0))
	return output


static func _variant_to_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _variant_to_array(value: Variant) -> Array:
	return value if value is Array else []


static func _variant_to_float(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if _is_number(value) else fallback


static func _variant_to_int(value: Variant, fallback: int = 0) -> int:
	return int(value) if _is_number(value) else fallback


static func _variant_to_enum(value: Variant, maximum: int, fallback: int) -> int:
	var parsed := _variant_to_int(value, fallback)
	return parsed if parsed >= 0 and parsed <= maximum else fallback


static func _variant_to_bool(value: Variant, fallback: bool = false) -> bool:
	if value is bool:
		return value
	if _is_number(value):
		return not is_zero_approx(float(value))
	return fallback


static func _variant_to_string(value: Variant, fallback: String = "") -> String:
	return String(value) if value is String or value is StringName else fallback


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
