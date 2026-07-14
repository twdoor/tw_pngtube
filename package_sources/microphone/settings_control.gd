extends TwberPackageSettingsControl

@onready var _device_option: OptionButton = %DeviceOption
@onready var _feedback: CheckButton = %Feedback

var _updating := false


func _ready() -> void:
	_device_option.item_selected.connect(_on_changed)
	_feedback.toggled.connect(_on_feedback_changed)


func configure(value: TwberEnvironmentPackage, settings: Dictionary = {}) -> void:
	super.configure(value, settings)
	_updating = true
	_device_option.clear()
	var devices: PackedStringArray = provider.call("get_available_input_devices")
	if devices.is_empty():
		_device_option.add_item("No input devices found")
		_device_option.set_item_disabled(0, true)
	else:
		for device_name: String in devices:
			_device_option.add_item(device_name)
			_device_option.set_item_metadata(_device_option.item_count - 1, device_name)
			if device_name == String(settings.get("input_device", "")):
				_device_option.select(_device_option.item_count - 1)
	_feedback.button_pressed = bool(settings.get("audio_feedback", false))
	_updating = false


func get_settings() -> Dictionary:
	var device_name := ""
	if _device_option.selected >= 0 and not _device_option.is_item_disabled(_device_option.selected):
		device_name = String(_device_option.get_item_metadata(_device_option.selected))
	return {
		"input_device": device_name,
		"audio_feedback": _feedback.button_pressed,
	}


func _on_changed(_index: int) -> void:
	if not _updating:
		settings_changed.emit(get_settings())


func _on_feedback_changed(_enabled: bool) -> void:
	if not _updating:
		settings_changed.emit(get_settings())
