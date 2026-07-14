class_name TwberTextureCache extends RefCounted

static var _textures_by_hash: Dictionary[String, WeakRef] = {}


static func get_texture(content_hash: String) -> Texture2D:
	if content_hash.is_empty() or not _textures_by_hash.has(content_hash):
		return null
	var texture_reference: WeakRef = _textures_by_hash[content_hash]
	var value: Variant = texture_reference.get_ref()
	if value is Texture2D:
		return value
	_textures_by_hash.erase(content_hash)
	return null


static func store_texture(content_hash: String, texture: Texture2D) -> void:
	if content_hash.is_empty() or texture == null:
		return
	_textures_by_hash[content_hash] = weakref(texture)


static func prune() -> void:
	for content_hash: String in _textures_by_hash.keys():
		var texture_reference: WeakRef = _textures_by_hash[content_hash]
		if texture_reference.get_ref() == null:
			_textures_by_hash.erase(content_hash)


static func clear() -> void:
	_textures_by_hash.clear()
