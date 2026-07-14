extends TwberPackageSettingsControl

const MODE_COLOR := "color"
const MODE_IMAGE := "image"

@onready var _mode_option: OptionButton = %ModeOption
@onready var _color_row: HBoxContainer = %ColorRow
@onready var _color_picker: ColorPickerButton = %ColorPicker
@onready var _image_row: HBoxContainer = %ImageRow
@onready var _image_path_label: Label = %ImagePathLabel
@onready var _choose_image_button: Button = %ChooseImageButton
@onready var _image_dialog: FileDialog = %ImageDialog

var _image_path := ""
var _updating := false


func _ready() -> void:
	_mode_option.add_item("Solid Color")
	_mode_option.set_item_metadata(0, MODE_COLOR)
	_mode_option.add_item("Custom Image")
	_mode_option.set_item_metadata(1, MODE_IMAGE)
	_mode_option.item_selected.connect(_on_mode_selected)
	_color_picker.color_changed.connect(_on_color_changed)
	_choose_image_button.pressed.connect(_image_dialog.show)
	_image_dialog.file_selected.connect(_on_image_selected)


func configure(value: TwberEnvironmentPackage, settings: Dictionary = {}) -> void:
	super.configure(value, settings)
	_updating = true
	var mode := String(settings.get("mode", MODE_COLOR))
	_mode_option.select(1 if mode == MODE_IMAGE else 0)
	var color_value: Variant = settings.get("color", Color.TRANSPARENT)
	_color_picker.color = color_value if color_value is Color else Color.from_string(String(color_value), Color.TRANSPARENT)
	_image_path = String(settings.get("image_path", ""))
	_refresh_image_label()
	_refresh_mode_visibility()
	_updating = false


func get_settings() -> Dictionary:
	return {
		"mode": String(_mode_option.get_item_metadata(_mode_option.selected)),
		"color": _color_picker.color,
		"image_path": _image_path,
	}


func _on_mode_selected(_index: int) -> void:
	_refresh_mode_visibility()
	_emit_settings()


func _on_color_changed(_color: Color) -> void:
	_emit_settings()


func _on_image_selected(path: String) -> void:
	_image_path = path
	_mode_option.select(1)
	_refresh_image_label()
	_refresh_mode_visibility()
	_emit_settings()


func _refresh_mode_visibility() -> void:
	var image_mode := String(_mode_option.get_item_metadata(_mode_option.selected)) == MODE_IMAGE
	_color_row.visible = not image_mode
	_image_row.visible = image_mode


func _refresh_image_label() -> void:
	_image_path_label.text = _image_path.get_file() if not _image_path.is_empty() else "No image selected"
	_image_path_label.tooltip_text = _image_path


func _emit_settings() -> void:
	if not _updating:
		settings_changed.emit(get_settings())
