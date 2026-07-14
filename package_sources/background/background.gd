extends TwberEnvironmentPackage

const MODE_COLOR := "color"
const MODE_IMAGE := "image"

var _enabled := true
var _mode := MODE_COLOR
var _color := Color.TRANSPARENT
var _image_path := ""


func set_stage_api(value: TwberStageApi) -> void:
	super.set_stage_api(value)
	_apply_background()


func get_package_name() -> String:
	return "Stage Background"


func get_package_description() -> String:
	return "Choose a solid stage color or a custom background image."


func get_default_enabled() -> bool:
	return true


func is_package_enabled() -> bool:
	return _enabled


func set_package_enabled(value: bool) -> void:
	_enabled = value
	_apply_background()


func get_package_settings() -> Dictionary:
	return {
		"mode": _mode,
		"color": _color,
		"image_path": _image_path,
	}


func apply_package_settings(settings: Dictionary) -> void:
	var requested_mode := String(settings.get("mode", MODE_COLOR))
	_mode = requested_mode if requested_mode in [MODE_COLOR, MODE_IMAGE] else MODE_COLOR
	var color_value: Variant = settings.get("color", Color.TRANSPARENT)
	_color = color_value if color_value is Color else Color.from_string(String(color_value), Color.TRANSPARENT)
	_image_path = String(settings.get("image_path", ""))
	_apply_background()


func _apply_background() -> void:
	if stage_api == null:
		return
	if not _enabled:
		stage_api.clear_background()
	elif _mode == MODE_IMAGE and not _image_path.is_empty():
		stage_api.set_background_image(_image_path)
	else:
		stage_api.set_background_color(_color)
