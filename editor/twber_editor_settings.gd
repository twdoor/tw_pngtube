class_name TwberEditorSettings extends RefCounted

const CONFIG_PATH := "user://twber_editor_settings.cfg"
const TEXTURES_SECTION := "textures"
const LARGE_TEXTURE_VRAM_THRESHOLD_KEY := "large_texture_vram_threshold_px"
const VRAM_THRESHOLD_DISABLED := -1
const VRAM_THRESHOLD_ALWAYS := 0
const DEFAULT_VRAM_THRESHOLD_PX := 1024
const VRAM_THRESHOLD_OPTIONS: Array[int] = [
	VRAM_THRESHOLD_DISABLED,
	1024,
	2048,
	4096,
	VRAM_THRESHOLD_ALWAYS,
]

var large_texture_vram_threshold_px := DEFAULT_VRAM_THRESHOLD_PX


static func load_settings() -> TwberEditorSettings:
	var settings := TwberEditorSettings.new()
	var config := ConfigFile.new()
	var error := config.load(CONFIG_PATH)
	if error != OK:
		return settings

	settings.large_texture_vram_threshold_px = int(config.get_value(
		TEXTURES_SECTION,
		LARGE_TEXTURE_VRAM_THRESHOLD_KEY,
		DEFAULT_VRAM_THRESHOLD_PX
	))
	return settings


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value(TEXTURES_SECTION, LARGE_TEXTURE_VRAM_THRESHOLD_KEY, large_texture_vram_threshold_px)
	return config.save(CONFIG_PATH)


func should_vram_compress_texture(texture: Texture2D) -> bool:
	if texture == null:
		return false

	return should_vram_compress_size(texture.get_width(), texture.get_height())


func should_vram_compress_size(width: int, height: int) -> bool:
	if large_texture_vram_threshold_px == VRAM_THRESHOLD_DISABLED:
		return false

	if large_texture_vram_threshold_px == VRAM_THRESHOLD_ALWAYS:
		return true

	return maxi(width, height) >= large_texture_vram_threshold_px


static func get_vram_threshold_label(threshold_px: int) -> String:
	match threshold_px:
		VRAM_THRESHOLD_DISABLED:
			return "Off"
		VRAM_THRESHOLD_ALWAYS:
			return "Always"
		_:
			return "Over %d px" % threshold_px
