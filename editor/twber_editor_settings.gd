class_name TwberEditorSettings extends RefCounted

const CONFIG_PATH := "user://twber_editor_settings.cfg"
const TEXTURES_SECTION := "textures"
const LARGE_TEXTURE_VRAM_THRESHOLD_KEY := "large_texture_vram_threshold_px"
const TRIM_TRANSPARENT_BORDERS_KEY := "trim_transparent_borders"
const TRIM_ALPHA_THRESHOLD_KEY := "trim_alpha_threshold"
const TRIM_PADDING_KEY := "trim_padding"
const EDITING_SECTION := "editing"
const PIXEL_SNAP_ENABLED_KEY := "pixel_snap_enabled"
const ROTATION_SNAP_DEGREES_KEY := "rotation_snap_degrees"
const APPEARANCE_SECTION := "appearance"
const BACKGROUND_COLOR_KEY := "background_color"
const VRAM_THRESHOLD_DISABLED := -1
const VRAM_THRESHOLD_ALWAYS := 0
const DEFAULT_VRAM_THRESHOLD_PX := 1024
const DEFAULT_TRIM_TRANSPARENT_BORDERS := true
const DEFAULT_TRIM_ALPHA_THRESHOLD := 0.001
const DEFAULT_TRIM_PADDING := 2
const MIN_TRIM_PADDING := 0
const MAX_TRIM_PADDING := 32
const DEFAULT_PIXEL_SNAP_ENABLED := true
const DEFAULT_ROTATION_SNAP_DEGREES := 15.0
const MIN_ROTATION_SNAP_DEGREES := 1.0
const MAX_ROTATION_SNAP_DEGREES := 90.0
const DEFAULT_BACKGROUND_COLOR := Color(0.050980393, 0.16862746, 0.27058825, 1.0)
const SCALE_SNAP_STEP := 0.05
const VRAM_THRESHOLD_OPTIONS: Array[int] = [
	VRAM_THRESHOLD_DISABLED,
	DEFAULT_VRAM_THRESHOLD_PX,
	2048,
	4096,
	VRAM_THRESHOLD_ALWAYS,
]

var large_texture_vram_threshold_px := DEFAULT_VRAM_THRESHOLD_PX
var trim_transparent_borders := DEFAULT_TRIM_TRANSPARENT_BORDERS
var trim_alpha_threshold := DEFAULT_TRIM_ALPHA_THRESHOLD
var trim_padding := DEFAULT_TRIM_PADDING
var pixel_snap_enabled := DEFAULT_PIXEL_SNAP_ENABLED
var rotation_snap_degrees := DEFAULT_ROTATION_SNAP_DEGREES
var background_color := DEFAULT_BACKGROUND_COLOR


static func load_settings() -> TwberEditorSettings:
	var settings := TwberEditorSettings.new()
	var config := ConfigFile.new()
	var error := config.load(CONFIG_PATH)
	if error != OK:
		return settings

	var saved_threshold: Variant = config.get_value(
		TEXTURES_SECTION,
		LARGE_TEXTURE_VRAM_THRESHOLD_KEY,
		DEFAULT_VRAM_THRESHOLD_PX
	)
	if saved_threshold is int and VRAM_THRESHOLD_OPTIONS.has(saved_threshold):
		settings.large_texture_vram_threshold_px = saved_threshold
	else:
		push_warning("Ignoring invalid large-texture VRAM threshold in editor settings.")

	var saved_trim_enabled: Variant = config.get_value(
		TEXTURES_SECTION,
		TRIM_TRANSPARENT_BORDERS_KEY,
		DEFAULT_TRIM_TRANSPARENT_BORDERS,
	)
	if saved_trim_enabled is bool:
		settings.trim_transparent_borders = saved_trim_enabled

	var saved_trim_threshold: Variant = config.get_value(
		TEXTURES_SECTION,
		TRIM_ALPHA_THRESHOLD_KEY,
		DEFAULT_TRIM_ALPHA_THRESHOLD,
	)
	if saved_trim_threshold is int or saved_trim_threshold is float:
		settings.trim_alpha_threshold = clampf(float(saved_trim_threshold), 0.0, 1.0)

	var saved_trim_padding: Variant = config.get_value(
		TEXTURES_SECTION,
		TRIM_PADDING_KEY,
		DEFAULT_TRIM_PADDING,
	)
	if saved_trim_padding is int or saved_trim_padding is float:
		settings.trim_padding = clampi(
				int(saved_trim_padding),
				MIN_TRIM_PADDING,
				MAX_TRIM_PADDING,
		)

	var saved_pixel_snap: Variant = config.get_value(
		EDITING_SECTION,
		PIXEL_SNAP_ENABLED_KEY,
		DEFAULT_PIXEL_SNAP_ENABLED
	)
	if saved_pixel_snap is bool:
		settings.pixel_snap_enabled = saved_pixel_snap
	else:
		push_warning("Ignoring invalid pixel-snap setting in editor settings.")

	var saved_rotation_snap: Variant = config.get_value(
		EDITING_SECTION,
		ROTATION_SNAP_DEGREES_KEY,
		DEFAULT_ROTATION_SNAP_DEGREES
	)
	if saved_rotation_snap is int or saved_rotation_snap is float:
		var rotation_snap := float(saved_rotation_snap)
		if rotation_snap >= MIN_ROTATION_SNAP_DEGREES and rotation_snap <= MAX_ROTATION_SNAP_DEGREES:
			settings.rotation_snap_degrees = rotation_snap
		else:
			push_warning("Ignoring out-of-range rotation-snap setting in editor settings.")
	else:
		push_warning("Ignoring invalid rotation-snap setting in editor settings.")

	var saved_background_color: Variant = config.get_value(
		APPEARANCE_SECTION,
		BACKGROUND_COLOR_KEY,
		DEFAULT_BACKGROUND_COLOR,
	)
	if saved_background_color is Color:
		settings.background_color = saved_background_color
	else:
		push_warning("Ignoring invalid background color in editor settings.")

	return settings


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value(TEXTURES_SECTION, LARGE_TEXTURE_VRAM_THRESHOLD_KEY, large_texture_vram_threshold_px)
	config.set_value(TEXTURES_SECTION, TRIM_TRANSPARENT_BORDERS_KEY, trim_transparent_borders)
	config.set_value(TEXTURES_SECTION, TRIM_ALPHA_THRESHOLD_KEY, trim_alpha_threshold)
	config.set_value(TEXTURES_SECTION, TRIM_PADDING_KEY, trim_padding)
	config.set_value(EDITING_SECTION, PIXEL_SNAP_ENABLED_KEY, pixel_snap_enabled)
	config.set_value(EDITING_SECTION, ROTATION_SNAP_DEGREES_KEY, rotation_snap_degrees)
	config.set_value(APPEARANCE_SECTION, BACKGROUND_COLOR_KEY, background_color)
	return config.save(CONFIG_PATH)


func snap_pixel_position(value: Vector2, origin: Vector2 = Vector2.ZERO) -> Vector2:
	if not pixel_snap_enabled:
		return value

	return (value - origin).round() + origin


func snap_rotation(angle: float) -> float:
	if not pixel_snap_enabled:
		return angle

	return snappedf(angle, deg_to_rad(rotation_snap_degrees))


func snap_scale_factor(factor: float) -> float:
	if not pixel_snap_enabled:
		return factor

	return maxf(snappedf(factor, SCALE_SNAP_STEP), SCALE_SNAP_STEP)


func snap_scale(value: Vector2) -> Vector2:
	if not pixel_snap_enabled:
		return value

	return Vector2(
		snappedf(value.x, SCALE_SNAP_STEP),
		snappedf(value.y, SCALE_SNAP_STEP)
	)


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
