class_name TwberEditor extends CanvasLayer

const MENU_NEW := 4
const MENU_OPEN := 1
const MENU_SAVE := 2
const MENU_EXPORT := 3
const MENU_SETTINGS := 5
const MODEL_RESOURCE_FILTER := "*.tres, *.res ; Editable model resources"
const EXPORTED_MODEL_FILTER := "*.twber ; Twber model packages"
const SETTINGS_DIALOG_SCENE := preload("res://editor/editor_settings_dialog.tscn")

@onready var _file_menu_button: MenuButton = %FileMenuButton
@onready var _model_root: Node2D = $ModelPreview/Textures
@onready var _editor_placer: EditorPlacer = $PanelContainer/MarginContainer/VBoxContainer/Menus/EditorPlacer
@onready var _editor_mesher = $PanelContainer/MarginContainer/VBoxContainer/Menus/EditorMesher
@onready var _editor_rigger = $PanelContainer/MarginContainer/VBoxContainer/Menus/EditorRigger
@onready var _menus: TabContainer = $PanelContainer/MarginContainer/VBoxContainer/Menus

var _current_resource_path := ""
var _default_model_root_position := Vector2.ZERO
var _default_model_root_scale := Vector2.ONE
var _default_model_root_rotation := 0.0
var _editor_settings: TwberEditorSettings


func _ready() -> void:
	_remember_default_model_root_transform()
	_editor_settings = TwberEditorSettings.load_settings()
	_editor_placer.set_editor_settings(_editor_settings)

	var popup := _file_menu_button.get_popup()
	_set_menu_item_disabled(popup, MENU_SAVE, false)
	popup.id_pressed.connect(_on_file_menu_id_pressed)
	_menus.tab_changed.connect(_on_tab_changed)
	_editor_mesher.model_tree_changed.connect(_on_mesher_model_tree_changed)


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		MENU_NEW:
			_new_model()
		MENU_OPEN:
			_open_model_dialog()
		MENU_SAVE:
			_save_model()
		MENU_EXPORT:
			_export_model_dialog()
		MENU_SETTINGS:
			_open_settings_dialog()


func _new_model() -> void:
	for child: Node in _model_root.get_children():
		_model_root.remove_child(child)
		child.queue_free()

	_model_root.position = _default_model_root_position
	_model_root.scale = _default_model_root_scale
	_model_root.rotation = _default_model_root_rotation
	_current_resource_path = ""

	_reload_editors_from_preview()
	_menus.current_tab = _editor_placer.get_index()


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
	var model = TwberModelCodec.load_model(path)
	if model == null:
		return

	TwberModelCodec.apply_to_model_root(model, _model_root)
	_reload_editors_from_preview()

	if path.get_extension().to_lower() == TwberModelCodec.TWBER_EXTENSION:
		_current_resource_path = ""
	else:
		_current_resource_path = path


func _save_model_resource(path: String) -> void:
	var model = TwberModelCodec.from_model_root(_model_root)
	var error: Error = TwberModelCodec.save_resource(model, path)
	if error != OK:
		push_error("Could not save model resource: %s" % error_string(error))
		return

	_current_resource_path = path


func _export_model(path: String) -> void:
	var model = TwberModelCodec.from_model_root(_model_root)
	var error: Error = TwberModelCodec.export_twber(model, path)
	if error != OK:
		push_error("Could not export Twber model: %s" % error_string(error))


func _open_settings_dialog() -> void:
	var dialog: EditorSettingsDialog = SETTINGS_DIALOG_SCENE.instantiate()
	dialog.set_editor_settings(_editor_settings)
	dialog.settings_applied.connect(func(settings: TwberEditorSettings) -> void:
		_editor_settings = settings
		_editor_placer.set_editor_settings(_editor_settings)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 150))


func _on_tab_changed(tab_index: int) -> void:
	var tab := _menus.get_child(tab_index)
	if tab == _editor_placer:
		_editor_placer.reload_from_preview()
	elif tab == _editor_mesher:
		_editor_mesher.reload_from_preview()
	elif tab == _editor_rigger:
		_editor_rigger.reload_from_preview()


func _on_mesher_model_tree_changed() -> void:
	_editor_placer.reload_from_preview()
	_editor_rigger.reload_from_preview()


func _reload_editors_from_preview() -> void:
	_editor_placer.reload_from_preview()
	_editor_mesher.reload_from_preview()
	_editor_rigger.reload_from_preview()


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


func _remember_default_model_root_transform() -> void:
	_default_model_root_position = _model_root.position
	_default_model_root_scale = _model_root.scale
	_default_model_root_rotation = _model_root.rotation


func _set_menu_item_disabled(popup: PopupMenu, id: int, disabled: bool) -> void:
	var item_index := popup.get_item_index(id)
	if item_index != -1:
		popup.set_item_disabled(item_index, disabled)


func _normalize_resource_path(path: String) -> String:
	var extension := path.get_extension().to_lower()
	if extension == "tres" or extension == "res":
		return path
	if extension.is_empty():
		return "%s.tres" % path

	return "%s.tres" % path.get_basename()


func _normalize_export_path(path: String) -> String:
	if path.get_extension().to_lower() == TwberModelCodec.TWBER_EXTENSION:
		return path

	if path.get_extension().is_empty():
		return "%s.%s" % [path, TwberModelCodec.TWBER_EXTENSION]

	return "%s.%s" % [path.get_basename(), TwberModelCodec.TWBER_EXTENSION]
