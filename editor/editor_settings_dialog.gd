class_name EditorSettingsDialog extends ConfirmationDialog

signal settings_applied(settings: TwberEditorSettings)

@onready var _threshold_option: OptionButton = %VramThresholdOption

var _settings: TwberEditorSettings


func _ready() -> void:
	close_requested.connect(queue_free)
	canceled.connect(queue_free)
	confirmed.connect(_on_confirmed)
	_refresh_threshold_options()


func set_editor_settings(settings: TwberEditorSettings) -> void:
	_settings = settings
	if is_node_ready():
		_refresh_threshold_options()


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
	var error := _settings.save()
	if error != OK:
		push_warning("Could not save editor settings: %s" % error_string(error))

	settings_applied.emit(_settings)
	queue_free()
