class_name TwberEditor extends CanvasLayer

const MENU_OPEN := 1
const MENU_SAVE := 2
const MENU_EXPORT := 3
const MODEL_RESOURCE_FILTER := "*.tres, *.res ; Editable model resources"
const EXPORTED_MODEL_FILTER := "*.twber ; Twber model packages"
const TwberModelCodecScript := preload("res://model/twber_model_codec.gd")

@onready var _file_menu_button: MenuButton = %FileMenuButton
@onready var _model_root: Node2D = $ModelPreview/Textures
@onready var _editor_placer: EditorPlacer = $PanelContainer/MarginContainer/VBoxContainer/Menus/EditorPlacer

var _current_resource_path := ""


func _ready() -> void:
	var popup := _file_menu_button.get_popup()
	popup.set_item_disabled(popup.get_item_index(MENU_SAVE), false)
	popup.id_pressed.connect(_on_file_menu_id_pressed)


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		MENU_OPEN:
			_open_model_dialog()
		MENU_SAVE:
			_save_model()
		MENU_EXPORT:
			_export_model_dialog()


func _open_model_dialog() -> void:
	var dialog := _create_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Open model")
	dialog.filters = PackedStringArray([MODEL_RESOURCE_FILTER, EXPORTED_MODEL_FILTER])
	dialog.file_selected.connect(func(path: String) -> void:
		_open_model(path)
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.7)


func _save_model() -> void:
	if _current_resource_path.is_empty():
		_save_model_dialog()
		return

	_save_model_resource(_current_resource_path)


func _save_model_dialog() -> void:
	var dialog := _create_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save editable model resource")
	dialog.filters = PackedStringArray([MODEL_RESOURCE_FILTER])
	dialog.current_file = "model.tres"
	dialog.file_selected.connect(func(path: String) -> void:
		_save_model_resource(_normalize_resource_path(path))
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.7)


func _export_model_dialog() -> void:
	var dialog := _create_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Export Twber model")
	dialog.filters = PackedStringArray([EXPORTED_MODEL_FILTER])
	dialog.current_file = "model.twber"
	dialog.file_selected.connect(func(path: String) -> void:
		_export_model(_normalize_export_path(path))
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.7)


func _open_model(path: String) -> void:
	var model = TwberModelCodecScript.load_model(path)
	if model == null:
		return

	TwberModelCodecScript.apply_to_model_root(model, _model_root)
	_editor_placer.reload_from_preview()

	if path.get_extension().to_lower() == TwberModelCodecScript.TWBER_EXTENSION:
		_current_resource_path = ""
	else:
		_current_resource_path = path


func _save_model_resource(path: String) -> void:
	var model = TwberModelCodecScript.from_model_root(_model_root)
	var error: Error = TwberModelCodecScript.save_resource(model, path)
	if error != OK:
		push_error("Could not save model resource: %s" % error_string(error))
		return

	_current_resource_path = path


func _export_model(path: String) -> void:
	var model = TwberModelCodecScript.from_model_root(_model_root)
	var error: Error = TwberModelCodecScript.export_twber(model, path)
	if error != OK:
		push_error("Could not export Twber model: %s" % error_string(error))


func _create_file_dialog(file_mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = file_mode
	dialog.use_native_dialog = false
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	return dialog


func _normalize_resource_path(path: String) -> String:
	var extension := path.get_extension().to_lower()
	if extension == "tres" or extension == "res":
		return path
	if extension.is_empty():
		return "%s.tres" % path

	return "%s.tres" % path.get_basename()


func _normalize_export_path(path: String) -> String:
	if path.get_extension().to_lower() == TwberModelCodecScript.TWBER_EXTENSION:
		return path

	if path.get_extension().is_empty():
		return "%s.%s" % [path, TwberModelCodecScript.TWBER_EXTENSION]

	return "%s.%s" % [path.get_basename(), TwberModelCodecScript.TWBER_EXTENSION]
