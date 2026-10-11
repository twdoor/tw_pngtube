extends TwberInputBindingControl

@onready var _display_option: OptionButton = %DisplayOption

var _updating := false


func _ready() -> void:
	_display_option.item_selected.connect(_on_display_selected)


func configure(value: TwberParameterResource, configuration: Dictionary = {}) -> void:
	super.configure(value, configuration)
	_updating = true
	_display_option.clear()
	_display_option.add_item("Automatic · Follow pointer")
	_display_option.set_item_metadata(0, -1)
	for display_index: int in DisplayServer.get_screen_count():
		var display_rect := _get_display_rect(display_index)
		_display_option.add_item("Display %d · %d×%d" % [display_index + 1, display_rect.size.x, display_rect.size.y])
		_display_option.set_item_metadata(_display_option.item_count - 1, display_index)
	var configured_display := -1
	# Older bindings saved Display 1 even when the user never chose a display.
	# Treat them as automatic; an explicit choice in this version saves the mode.
	if String(configuration.get("display_mode", "automatic")) == "fixed":
		configured_display = int(configuration.get("display_index", 0))
	for option_index: int in _display_option.item_count:
		if int(_display_option.get_item_metadata(option_index)) == configured_display:
			_display_option.select(option_index)
			break
	_updating = false


func get_configuration() -> Dictionary:
	if _display_option.selected < 0:
		return {"display_mode": "automatic", "display_index": -1}
	var display_index := int(_display_option.get_item_metadata(_display_option.selected))
	return {
		"display_mode": "automatic" if display_index < 0 else "fixed",
		"display_index": display_index,
	}


func apply_source_value(value: Variant) -> Variant:
	return preload("res://package_sources/mouse/binding_mapper.gd").new().map_value(
		parameter, get_configuration(), value, TwberInputContext.capture_displays(),
	)


func _get_display_rect(display_index: int) -> Rect2:
	if display_index < 0 or display_index >= DisplayServer.get_screen_count():
		return Rect2()
	return Rect2(
		Vector2(DisplayServer.screen_get_position(display_index)),
		Vector2(DisplayServer.screen_get_size(display_index)),
	)


func _on_display_selected(_index: int) -> void:
	if not _updating:
		configuration_changed.emit(get_configuration())
