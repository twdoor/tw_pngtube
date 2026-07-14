class_name TwberTextureAtlasBuilder extends RefCounted

const MAX_ATLAS_SIZE := 4096
const PADDING := 2


static func optimize_model_root(
		model_root: Node2D,
		compression_threshold_px: int,
) -> Dictionary:
	if model_root == null:
		return {}
	var references: Array[Dictionary] = []
	var textures: Array[Texture2D] = []
	var seen_texture_ids := {}
	_collect_texture_references(model_root, references, textures, seen_texture_ids)
	var result := build_atlases(textures, compression_threshold_px)
	var mapped_textures: Dictionary = result.get("textures_by_instance_id", {})
	for texture_reference: Dictionary in references:
		var source_texture: Texture2D = texture_reference["texture"] as Texture2D
		if source_texture == null or not mapped_textures.has(source_texture.get_instance_id()):
			continue
		var mapped_texture: Texture2D = mapped_textures[source_texture.get_instance_id()]
		if mapped_texture == source_texture:
			continue
		match String(texture_reference["kind"]):
			"sprite":
				(texture_reference["node"] as Sprite2D).texture = mapped_texture
			"mesh":
				(texture_reference["node"] as TwberMeshSprite2D).texture = mapped_texture
			"animation":
				var animated_sprite: AnimatedSprite2D = texture_reference["node"]
				animated_sprite.sprite_frames.set_frame(
						texture_reference["animation"],
						int(texture_reference["frame"]),
						mapped_texture,
						float(texture_reference["duration"]),
				)
	return result


static func model_root_uses_atlas_textures(model_root: Node2D) -> bool:
	if model_root == null:
		return false
	var references: Array[Dictionary] = []
	var textures: Array[Texture2D] = []
	var seen_texture_ids := {}
	_collect_texture_references(model_root, references, textures, seen_texture_ids)
	if textures.is_empty():
		return false
	for texture: Texture2D in textures:
		if texture is not AtlasTexture:
			return false
	return true


static func build_atlases(
		textures: Array[Texture2D],
		compression_threshold_px: int,
) -> Dictionary:
	var output := {}
	for texture: Texture2D in textures:
		if texture != null:
			output[texture.get_instance_id()] = texture

	var unique_items_by_content := {}
	for texture: Texture2D in textures:
		if texture == null:
			continue
		var image := TwberTextureUtils.get_authoring_image(texture)
		if image == null or image.is_empty():
			continue
		var rgba_image := image.duplicate()
		if rgba_image.get_format() != Image.FORMAT_RGBA8:
			rgba_image.convert(Image.FORMAT_RGBA8)
		var content_key := "%dx%d:%s" % [
			rgba_image.get_width(),
			rgba_image.get_height(),
			_hash_image_data(rgba_image.get_data()),
		]
		if unique_items_by_content.has(content_key):
			unique_items_by_content[content_key]["textures"].append(texture)
			continue
		unique_items_by_content[content_key] = {
			"image": rgba_image,
			"size": Vector2i(rgba_image.get_width(), rgba_image.get_height()),
			"textures": [texture],
		}

	var items: Array[Dictionary] = []
	for item: Dictionary in unique_items_by_content.values():
		var item_size: Vector2i = item["size"]
		if item_size.x + PADDING * 2 <= MAX_ATLAS_SIZE and item_size.y + PADDING * 2 <= MAX_ATLAS_SIZE:
			items.append(item)
	items.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_size: Vector2i = first["size"]
		var second_size: Vector2i = second["size"]
		return first_size.y > second_size.y
	)

	var pages: Array[Dictionary] = []
	for item: Dictionary in items:
		var placed := false
		for page: Dictionary in pages:
			var region := _try_place(page, item["size"])
			if region.size == Vector2i.ZERO:
				continue
			item["region"] = region
			page["items"].append(item)
			placed = true
			break
		if placed:
			continue
		var page := {
			"cursor_x": PADDING,
			"cursor_y": PADDING,
			"row_height": 0,
			"used_size": Vector2i.ONE,
			"items": [],
		}
		item["region"] = _try_place(page, item["size"])
		page["items"].append(item)
		pages.append(page)

	var atlas_textures: Array[Texture2D] = []
	var atlased_texture_count := 0
	for page: Dictionary in pages:
		var source_count := 0
		for item: Dictionary in page["items"]:
			source_count += item["textures"].size()
		if page["items"].size() < 2 and source_count < 2:
			continue

		var used_size: Vector2i = page["used_size"]
		used_size.x = maxi(4, ceili(float(used_size.x) / 4.0) * 4)
		used_size.y = maxi(4, ceili(float(used_size.y) / 4.0) * 4)
		var atlas_image := Image.create(used_size.x, used_size.y, false, Image.FORMAT_RGBA8)
		atlas_image.fill(Color.TRANSPARENT)
		for item: Dictionary in page["items"]:
			_blit_with_extrusion(atlas_image, item["image"], item["region"])
		if _should_compress(used_size, compression_threshold_px):
			var compression_error := atlas_image.compress(
					Image.COMPRESS_S3TC,
					Image.COMPRESS_SOURCE_GENERIC,
			)
			if compression_error != OK:
				push_warning("Could not compress editor atlas: %s" % error_string(compression_error))
		var atlas_texture := ImageTexture.create_from_image(atlas_image)
		atlas_texture.resource_name = "Twber Preview Atlas %d" % atlas_textures.size()
		atlas_textures.append(atlas_texture)

		for item: Dictionary in page["items"]:
			var region: Rect2i = item["region"]
			for source_texture: Texture2D in item["textures"]:
				var wrapper := AtlasTexture.new()
				wrapper.atlas = atlas_texture
				wrapper.region = Rect2(region)
				wrapper.resource_name = source_texture.resource_name
				TwberTextureUtils.copy_metadata(source_texture, wrapper)
				output[source_texture.get_instance_id()] = wrapper
				atlased_texture_count += 1

	return {
		"textures_by_instance_id": output,
		"atlas_textures": atlas_textures,
		"atlas_pages": atlas_textures.size(),
		"atlased_textures": atlased_texture_count,
	}


static func _collect_texture_references(
		parent: Node,
		references: Array[Dictionary],
		textures: Array[Texture2D],
		seen_texture_ids: Dictionary,
) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue
		if child is TwberMeshSprite2D:
			_add_reference("mesh", child, (child as TwberMeshSprite2D).texture, references, textures, seen_texture_ids)
		elif child is AnimatedSprite2D:
			var animated_sprite: AnimatedSprite2D = child
			if animated_sprite.sprite_frames != null:
				for animation: StringName in animated_sprite.sprite_frames.get_animation_names():
					for frame_index: int in animated_sprite.sprite_frames.get_frame_count(animation):
						var texture := animated_sprite.sprite_frames.get_frame_texture(animation, frame_index)
						_add_reference(
								"animation",
								animated_sprite,
								texture,
								references,
								textures,
								seen_texture_ids,
								{
									"animation": animation,
									"frame": frame_index,
									"duration": animated_sprite.sprite_frames.get_frame_duration(animation, frame_index),
								},
						)
		elif child is Sprite2D:
			_add_reference("sprite", child, (child as Sprite2D).texture, references, textures, seen_texture_ids)
		_collect_texture_references(child, references, textures, seen_texture_ids)


static func _add_reference(
		kind: String,
		node: Node2D,
		texture: Texture2D,
		references: Array[Dictionary],
		textures: Array[Texture2D],
		seen_texture_ids: Dictionary,
		extra: Dictionary = {},
) -> void:
	if texture == null:
		return
	var texture_reference := {"kind": kind, "node": node, "texture": texture}
	texture_reference.merge(extra, true)
	references.append(texture_reference)
	var texture_id := texture.get_instance_id()
	if not seen_texture_ids.has(texture_id):
		seen_texture_ids[texture_id] = true
		textures.append(texture)


static func _try_place(page: Dictionary, item_size: Vector2i) -> Rect2i:
	var cursor_x := int(page["cursor_x"])
	var cursor_y := int(page["cursor_y"])
	var row_height := int(page["row_height"])
	if cursor_x + item_size.x + PADDING > MAX_ATLAS_SIZE:
		cursor_x = PADDING
		cursor_y += row_height + PADDING
		row_height = 0
	if cursor_y + item_size.y + PADDING > MAX_ATLAS_SIZE:
		return Rect2i()
	var region := Rect2i(Vector2i(cursor_x, cursor_y), item_size)
	page["cursor_x"] = cursor_x + item_size.x + PADDING
	page["cursor_y"] = cursor_y
	page["row_height"] = maxi(row_height, item_size.y)
	page["used_size"] = (page["used_size"] as Vector2i).max(region.end + Vector2i.ONE * PADDING)
	return region


static func _blit_with_extrusion(atlas: Image, source: Image, region: Rect2i) -> void:
	atlas.blit_rect(source, Rect2i(Vector2i.ZERO, region.size), region.position)
	for distance: int in range(1, PADDING + 1):
		for x: int in region.size.x:
			atlas.set_pixelv(Vector2i(region.position.x + x, region.position.y - distance), source.get_pixel(x, 0))
			atlas.set_pixelv(Vector2i(region.position.x + x, region.end.y - 1 + distance), source.get_pixel(x, region.size.y - 1))
		for y: int in region.size.y:
			atlas.set_pixelv(Vector2i(region.position.x - distance, region.position.y + y), source.get_pixel(0, y))
			atlas.set_pixelv(Vector2i(region.end.x - 1 + distance, region.position.y + y), source.get_pixel(region.size.x - 1, y))
	for offset_x: int in range(1, PADDING + 1):
		for offset_y: int in range(1, PADDING + 1):
			atlas.set_pixel(region.position.x - offset_x, region.position.y - offset_y, source.get_pixel(0, 0))
			atlas.set_pixel(region.end.x - 1 + offset_x, region.position.y - offset_y, source.get_pixel(region.size.x - 1, 0))
			atlas.set_pixel(region.position.x - offset_x, region.end.y - 1 + offset_y, source.get_pixel(0, region.size.y - 1))
			atlas.set_pixel(region.end.x - 1 + offset_x, region.end.y - 1 + offset_y, source.get_pixel(region.size.x - 1, region.size.y - 1))


static func _should_compress(size: Vector2i, threshold_px: int) -> bool:
	if threshold_px < 0:
		return false
	return threshold_px == 0 or maxi(size.x, size.y) >= threshold_px


static func _hash_image_data(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(data)
	return context.finish().hex_encode()
