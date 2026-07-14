class_name EditorSettingsDialog extends ConfirmationDialog

signal settings_applied(settings: TwberEditorSettings)

@onready var _threshold_option: OptionButton = %VramThresholdOption
@onready var _trim_transparent_check_box: CheckBox = %TrimTransparentCheckBox
@onready var _trim_alpha_threshold: SpinBox = %TrimAlphaThreshold
@onready var _trim_padding: SpinBox = %TrimPadding
@onready var _pixel_snap_check_box: CheckBox = %PixelSnapCheckBox
@onready var _rotation_snap_degrees: SpinBox = %RotationSnapDegrees

var _settings: TwberEditorSettings


func _ready() -> void:
	close_requested.connect(queue_free)
	canceled.connect(queue_free)
	confirmed.connect(_on_confirmed)
	_pixel_snap_check_box.toggled.connect(_on_pixel_snap_toggled)
	_trim_transparent_check_box.toggled.connect(_on_trim_transparent_toggled)
	_refresh_controls()


func set_editor_settings(settings: TwberEditorSettings) -> void:
	_settings = settings
	if is_node_ready():
		_refresh_controls()


func _refresh_controls() -> void:
	_refresh_threshold_options()

	var pixel_snap_enabled := TwberEditorSettings.DEFAULT_PIXEL_SNAP_ENABLED
	var rotation_snap_degrees := TwberEditorSettings.DEFAULT_ROTATION_SNAP_DEGREES
	var trim_enabled := TwberEditorSettings.DEFAULT_TRIM_TRANSPARENT_BORDERS
	var trim_alpha_threshold := TwberEditorSettings.DEFAULT_TRIM_ALPHA_THRESHOLD
	var trim_padding := TwberEditorSettings.DEFAULT_TRIM_PADDING
	if _settings != null:
		pixel_snap_enabled = _settings.pixel_snap_enabled
		rotation_snap_degrees = _settings.rotation_snap_degrees
		trim_enabled = _settings.trim_transparent_borders
		trim_alpha_threshold = _settings.trim_alpha_threshold
		trim_padding = _settings.trim_padding

	_trim_transparent_check_box.set_pressed_no_signal(trim_enabled)
	_trim_alpha_threshold.value = trim_alpha_threshold
	_trim_padding.value = trim_padding
	_set_trim_controls_enabled(trim_enabled)
	_pixel_snap_check_box.set_pressed_no_signal(pixel_snap_enabled)
	_rotation_snap_degrees.value = rotation_snap_degrees
	_rotation_snap_degrees.editable = pixel_snap_enabled


func _refresh_threshold_options() -> void:
	if _threshold_option == null:
		return

	_threshold_option.clear()
	var selected_index := 0
	var current_threshold := TwberEditorSettings.DEFAULT_VRAM_THRESHOLD_PX
	if _settings != null:
		current_threshold = _settings.large_texture_vram_threshold_px

	for threshold: int in TwberEditorSettings.VRAM_THRESHOLD_OPTIONS:
		_threshold_option.add_item(TwberEditorSettings.get_vram_threshold_label(threshold))
		var item_index := _threshold_option.item_count - 1
		_threshold_option.set_item_metadata(item_index, threshold)
		if threshold == current_threshold:
			selected_index = item_index

	_threshold_option.select(selected_index)


func _on_confirmed() -> void:
	if _settings == null:
		queue_free()
		return

	_settings.large_texture_vram_threshold_px = int(_threshold_option.get_selected_metadata())
	_settings.trim_transparent_borders = _trim_transparent_check_box.button_pressed
	_settings.trim_alpha_threshold = _trim_alpha_threshold.value
	_settings.trim_padding = int(_trim_padding.value)
	_settings.pixel_snap_enabled = _pixel_snap_check_box.button_pressed
	_settings.rotation_snap_degrees = _rotation_snap_degrees.value
	var error := _settings.save()
	if error != OK:
		push_warning("Could not save editor settings: %s" % error_string(error))

	settings_applied.emit(_settings)
	queue_free()


func _on_pixel_snap_toggled(enabled: bool) -> void:
	_rotation_snap_degrees.editable = enabled


func _on_trim_transparent_toggled(enabled: bool) -> void:
	_set_trim_controls_enabled(enabled)


func _set_trim_controls_enabled(enabled: bool) -> void:
	_trim_alpha_threshold.editable = enabled
	_trim_padding.editable = enabled
