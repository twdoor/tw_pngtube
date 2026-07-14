class_name TwberTextureUtils extends RefCounted

const ORIGINAL_SIZE_META := &"twber_original_size"
const TRIM_RECT_META := &"twber_trim_rect"
const VISIBLE_RECT_META := &"twber_visible_rect"
const ALPHA_THRESHOLD_META := &"twber_alpha_threshold"
const SOURCE_PATH_META := &"twber_source_path"
const PACKAGE_PATH_META := &"twber_package_path"
const PACKAGE_TEXTURE_FILE_META := &"twber_package_texture_file"
const PACKAGE_TEXTURE_HASH_META := &"twber_package_texture_sha256"
const PACKAGE_TEXTURE_REGION_META := &"twber_package_texture_region"
const PACKAGE_IMAGE_CACHE_MAX_BYTES := 128 * 1024 * 1024

static var _package_images := {}
static var _package_image_cache_order: Array[String] = []
static var _package_image_cache_sizes := {}
static var _package_image_cache_bytes := 0


static func get_readable_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	if texture is AtlasTexture:
		var atlas_texture: AtlasTexture = texture
		var atlas_image := get_readable_image(atlas_texture.atlas)
		if atlas_image == null:
			return null
		var region := Rect2i(atlas_texture.region).intersection(Rect2i(
				Vector2i.ZERO,
				Vector2i(atlas_image.get_width(), atlas_image.get_height()),
		))
		return atlas_image.get_region(region) if region.size.x > 0 and region.size.y > 0 else null

	var image := texture.get_image()
	if image == null:
		return null
	if not image.is_compressed():
		return image

	var readable := image.duplicate()
	if readable.decompress() != OK:
		return null
	return readable


static func is_gpu_compressed(texture: Texture2D) -> bool:
	if texture == null:
		return false
	if texture is AtlasTexture:
		return is_gpu_compressed((texture as AtlasTexture).atlas)
	var image := texture.get_image()
	return image != null and image.is_compressed()


static func get_authoring_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var packaged_image := _get_packaged_authoring_image(texture)
	if packaged_image != null:
		return packaged_image
	var source_path := String(texture.get_meta(SOURCE_PATH_META, ""))
	if not source_path.is_empty():
		var source_image: Image
		if source_path.begins_with("res://"):
			var absolute_source_path := ProjectSettings.globalize_path(source_path)
			if FileAccess.file_exists(absolute_source_path):
				source_image = Image.new()
				if source_image.load(absolute_source_path) != OK:
					source_image = null
			if source_image == null and ResourceLoader.exists(source_path):
				var resource := load(source_path)
				if resource is Texture2D:
					source_image = get_readable_image(resource)
		elif source_path.begins_with("uid://"):
			if ResourceLoader.exists(source_path):
				var resource := load(source_path)
				if resource is Texture2D:
					source_image = get_readable_image(resource)
		else:
			if FileAccess.file_exists(source_path):
				source_image = Image.new()
				if source_image.load(source_path) != OK:
					source_image = null

		if source_image != null:
			var trim_rect := get_trim_rect(texture).intersection(Rect2i(
					Vector2i.ZERO,
					Vector2i(source_image.get_width(), source_image.get_height()),
			))
			if trim_rect.size.x > 0 and trim_rect.size.y > 0:
				return source_image.get_region(trim_rect)

	return get_readable_image(texture)


static func _get_packaged_authoring_image(texture: Texture2D) -> Image:
	var package_path := String(texture.get_meta(PACKAGE_PATH_META, ""))
	var texture_file := String(texture.get_meta(PACKAGE_TEXTURE_FILE_META, ""))
	if package_path.is_empty() or texture_file.is_empty():
		return null
	var expected_hash := String(texture.get_meta(PACKAGE_TEXTURE_HASH_META, ""))
	var cache_key := "%s:%s:%s" % [package_path, texture_file, expected_hash]
	var image := _get_cached_package_image(cache_key)
	if image == null:
		image = _load_package_image(package_path, texture_file, expected_hash)
		if image == null:
			return null
		_cache_package_image(cache_key, image)
	if image.is_empty():
		return null
	var fallback_region := Rect2i(
			Vector2i.ZERO,
			Vector2i(image.get_width(), image.get_height()),
	)
	var region_value: Variant = texture.get_meta(PACKAGE_TEXTURE_REGION_META, fallback_region)
	var region: Rect2i = region_value if region_value is Rect2i else fallback_region
	region = region.intersection(fallback_region)
	if region.size.x <= 0 or region.size.y <= 0:
		return null
	return image.get_region(region)


static func _load_package_image(
		package_path: String,
		texture_file: String,
		expected_hash: String,
) -> Image:
	var archive := ZIPReader.new()
	if archive.open(package_path) != OK:
		return null
	if not archive.get_files().has(texture_file):
		archive.close()
		return null
	var payload := archive.read_file(texture_file)
	archive.close()
	if not expected_hash.is_empty() and _sha256_hex(payload) != expected_hash:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(payload) != OK:
		return null
	return image


static func _get_cached_package_image(cache_key: String) -> Image:
	var image := _package_images.get(cache_key) as Image
	if image == null:
		return null
	_package_image_cache_order.erase(cache_key)
	_package_image_cache_order.append(cache_key)
	return image


static func _cache_package_image(cache_key: String, image: Image) -> void:
	if cache_key.is_empty() or image == null or image.is_empty():
		return
	var byte_size := image.get_width() * image.get_height() * 4
	if byte_size > PACKAGE_IMAGE_CACHE_MAX_BYTES:
		return
	if _package_images.has(cache_key):
		_package_image_cache_bytes -= int(_package_image_cache_sizes.get(cache_key, 0))
		_package_image_cache_order.erase(cache_key)
	_package_images[cache_key] = image
	_package_image_cache_sizes[cache_key] = byte_size
	_package_image_cache_order.append(cache_key)
	_package_image_cache_bytes += byte_size
	while (
			_package_image_cache_bytes > PACKAGE_IMAGE_CACHE_MAX_BYTES
			and _package_image_cache_order.size() > 1
	):
		var oldest_key: String = _package_image_cache_order.pop_front()
		_package_image_cache_bytes -= int(_package_image_cache_sizes.get(oldest_key, 0))
		_package_image_cache_sizes.erase(oldest_key)
		_package_images.erase(oldest_key)


static func clear_package_image_cache() -> void:
	_package_images.clear()
	_package_image_cache_order.clear()
	_package_image_cache_sizes.clear()
	_package_image_cache_bytes = 0


static func _sha256_hex(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(data)
	return context.finish().hex_encode()


static func find_alpha_used_rect(image: Image, alpha_threshold: float) -> Rect2i:
	if image == null:
		return Rect2i()

	var readable := image
	if image.is_compressed():
		readable = image.duplicate()
		if readable.decompress() != OK:
			return Rect2i()

	var threshold := clampf(alpha_threshold, 0.0, 1.0)
	var threshold_byte := floori(threshold * 255.0)
	if threshold_byte <= 0:
		return readable.get_used_rect()

	var rgba := readable
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba = readable.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
	var image_width := rgba.get_width()
	var image_height := rgba.get_height()
	var pixel_data := rgba.get_data()
	var min_position := Vector2i(image_width, image_height)
	var max_position := Vector2i(-1, -1)
	for y: int in image_height:
		for x: int in image_width:
			var alpha_index := (y * image_width + x) * 4 + 3
			if int(pixel_data[alpha_index]) <= threshold_byte:
				continue
			var position := Vector2i(x, y)
			min_position = min_position.min(position)
			max_position = max_position.max(position)

	if max_position.x < min_position.x or max_position.y < min_position.y:
		return Rect2i()
	return Rect2i(min_position, max_position - min_position + Vector2i.ONE)


static func padded_rect(rect: Rect2i, padding: int, image_size: Vector2i) -> Rect2i:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)

	var safe_padding := maxi(padding, 0)
	var begin := (rect.position - Vector2i.ONE * safe_padding).max(Vector2i.ZERO)
	var end := (rect.end + Vector2i.ONE * safe_padding).min(image_size)
	return Rect2i(begin, end - begin)


static func prepare_image(
		image: Image,
		trim_enabled: bool,
		alpha_threshold: float,
		padding: int,
		forced_trim_rect: Rect2i = Rect2i(),
) -> Dictionary:
	if image == null:
		return {}

	var readable := image
	if image.is_compressed():
		readable = image.duplicate()
		if readable.decompress() != OK:
			return {}

	var original_size := Vector2i(readable.get_width(), readable.get_height())
	var used_rect := find_alpha_used_rect(readable, alpha_threshold)
	var trim_rect := Rect2i(Vector2i.ZERO, original_size)
	if forced_trim_rect.size.x > 0 and forced_trim_rect.size.y > 0:
		trim_rect = forced_trim_rect.intersection(Rect2i(Vector2i.ZERO, original_size))
	elif trim_enabled:
		trim_rect = padded_rect(used_rect, padding, original_size)

	if trim_rect.size.x <= 0 or trim_rect.size.y <= 0:
		trim_rect = Rect2i(Vector2i.ZERO, Vector2i.ONE)

	var output_image := readable
	if trim_rect.position != Vector2i.ZERO or trim_rect.size != original_size:
		output_image = readable.get_region(trim_rect)

	var visible_rect := Rect2i()
	if used_rect.size.x > 0 and used_rect.size.y > 0:
		visible_rect = Rect2i(used_rect.position - trim_rect.position, used_rect.size)

	return {
		"image": output_image,
		"original_size": original_size,
		"trim_rect": trim_rect,
		"visible_rect": visible_rect,
		"alpha_threshold": clampf(alpha_threshold, 0.0, 1.0),
	}


static func apply_metadata(texture: Texture2D, prepared: Dictionary) -> void:
	if texture == null or prepared.is_empty():
		return

	texture.set_meta(ORIGINAL_SIZE_META, prepared.get("original_size", Vector2i(texture.get_size())))
	texture.set_meta(
			TRIM_RECT_META,
			prepared.get("trim_rect", Rect2i(Vector2i.ZERO, Vector2i(texture.get_size()))),
	)
	texture.set_meta(VISIBLE_RECT_META, prepared.get("visible_rect", Rect2i()))
	texture.set_meta(ALPHA_THRESHOLD_META, float(prepared.get("alpha_threshold", 0.0)))


static func copy_metadata(source: Texture2D, destination: Texture2D) -> void:
	if source == null or destination == null:
		return

	for key: StringName in [
		SOURCE_PATH_META,
		PACKAGE_PATH_META,
		PACKAGE_TEXTURE_FILE_META,
		PACKAGE_TEXTURE_HASH_META,
		PACKAGE_TEXTURE_REGION_META,
		ORIGINAL_SIZE_META,
		TRIM_RECT_META,
		VISIBLE_RECT_META,
		ALPHA_THRESHOLD_META,
	]:
		if source.has_meta(key):
			destination.set_meta(key, source.get_meta(key))


static func get_original_size(texture: Texture2D) -> Vector2i:
	if texture == null:
		return Vector2i.ZERO
	var fallback := Vector2i(texture.get_size())
	var value: Variant = texture.get_meta(ORIGINAL_SIZE_META, fallback)
	return value if value is Vector2i else fallback


static func get_trim_rect(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var fallback := Rect2i(Vector2i.ZERO, Vector2i(texture.get_size()))
	var value: Variant = texture.get_meta(TRIM_RECT_META, fallback)
	return value if value is Rect2i else fallback


static func get_visible_rect(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var value: Variant = texture.get_meta(VISIBLE_RECT_META, Rect2i())
	if value is Rect2i:
		return value
	return Rect2i()


static func get_logical_texture_origin(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	var original_size := Vector2(get_original_size(texture))
	var trim_rect := get_trim_rect(texture)
	return -original_size * 0.5 + Vector2(trim_rect.position)


static func get_centered_sprite_offset(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return get_logical_texture_origin(texture) + texture.get_size() * 0.5
